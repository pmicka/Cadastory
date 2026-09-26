begin;

create table if not exists farm_watch.property_managed_food_inventory_v1 (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references farm_watch.properties(id) on delete cascade,
  season_year integer not null check (season_year between 2000 and 2100),
  inventory_status text not null
    check (inventory_status in ('confirmed_none','configured','unknown')),
  asserted_on date,
  source_context jsonb not null default '{}'::jsonb,
  notes text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (property_id, season_year)
);

comment on table farm_watch.property_managed_food_inventory_v1 is
  'Private property/year inventory state for managed food plots and managed forage features. confirmed_none is an explicit known absence, not missing data.';

create table if not exists farm_watch.property_managed_food_features_v1 (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references farm_watch.properties(id) on delete cascade,
  feature_key text not null,
  feature_class text not null
    check (feature_class in ('food_plot','managed_forage_area','study_relevant_managed_cover')),
  cover_type text,
  geometry_basis text not null,
  geometry_precision_m numeric check (geometry_precision_m is null or geometry_precision_m > 0),
  source_context jsonb not null default '{}'::jsonb,
  notes text,
  geometry extensions.geometry(Geometry,4326) not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (property_id, feature_key),
  check (feature_key ~ '^[a-z0-9][a-z0-9_-]{0,79}$'),
  check (upper(extensions.geometrytype(geometry)) in ('POLYGON','MULTIPOLYGON'))
);

comment on table farm_watch.property_managed_food_features_v1 is
  'Stable operator-configured polygons for managed food plots/forage features. Geometry is configured once and year-specific management state is stored separately.';

create index if not exists property_managed_food_features_v1_geometry_gix
  on farm_watch.property_managed_food_features_v1 using gist (geometry);

create index if not exists property_managed_food_features_v1_property_idx
  on farm_watch.property_managed_food_features_v1(property_id)
  where active=true;

create table if not exists farm_watch.property_managed_food_feature_state_v1 (
  id uuid primary key default gen_random_uuid(),
  feature_id uuid not null references farm_watch.property_managed_food_features_v1(id) on delete cascade,
  season_year integer not null check (season_year between 2000 and 2100),
  management_state text not null
    check (management_state in ('active','inactive','unknown')),
  asserted_on date,
  source_context jsonb not null default '{}'::jsonb,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (feature_id, season_year)
);

comment on table farm_watch.property_managed_food_feature_state_v1 is
  'Year-specific management state for stable managed-food polygons. A polygon may be reused across years without redrawing it.';

alter table farm_watch.property_managed_food_inventory_v1 enable row level security;
alter table farm_watch.property_managed_food_features_v1 enable row level security;
alter table farm_watch.property_managed_food_feature_state_v1 enable row level security;

revoke all on table farm_watch.property_managed_food_inventory_v1 from public, anon, authenticated;
revoke all on table farm_watch.property_managed_food_features_v1 from public, anon, authenticated;
revoke all on table farm_watch.property_managed_food_feature_state_v1 from public, anon, authenticated;

grant select, insert, update, delete on table farm_watch.property_managed_food_inventory_v1 to service_role;
grant select, insert, update, delete on table farm_watch.property_managed_food_features_v1 to service_role;
grant select, insert, update, delete on table farm_watch.property_managed_food_feature_state_v1 to service_role;

create or replace function farm_watch.farm_watch_get_managed_food_feature_context_v1_internal(
  p_slug text,
  p_as_of_date date default current_date
)
returns jsonb
language sql
stable
security definer
set search_path=pg_catalog,farm_watch,extensions
as $$
  with property as (
    select p.id,p.slug
    from farm_watch.properties p
    where p.slug=p_slug
      and p.status='active'
    limit 1
  ),
  inventory as (
    select i.*
    from farm_watch.property_managed_food_inventory_v1 i
    join property p on p.id=i.property_id
    where i.active
      and i.season_year=extract(year from p_as_of_date)::integer
    limit 1
  ),
  configured as (
    select
      f.feature_key,
      f.feature_class,
      f.cover_type,
      f.geometry_basis,
      f.geometry_precision_m,
      f.source_context,
      f.notes,
      s.management_state,
      s.asserted_on as state_asserted_on,
      s.source_context as state_source_context,
      s.notes as state_notes,
      extensions.st_asgeojson(f.geometry,7)::jsonb as geometry_geojson
    from farm_watch.property_managed_food_features_v1 f
    join property p on p.id=f.property_id
    join farm_watch.property_managed_food_feature_state_v1 s
      on s.feature_id=f.id
     and s.season_year=extract(year from p_as_of_date)::integer
    where f.active
    order by f.feature_key
  ),
  summary as (
    select
      count(*)::integer as configured_feature_count,
      count(*) filter (where management_state='active')::integer as active_feature_count,
      count(*) filter (where management_state is null or management_state='unknown')::integer
        as unknown_state_count,
      coalesce(
        jsonb_agg(
          jsonb_strip_nulls(
            jsonb_build_object(
              'feature_key',feature_key,
              'feature_class',feature_class,
              'cover_type',cover_type,
              'management_state',coalesce(management_state,'unknown'),
              'geometry_basis',geometry_basis,
              'geometry_precision_m',geometry_precision_m,
              'geometry_geojson',geometry_geojson,
              'feature_source_context',source_context,
              'feature_notes',notes,
              'state_asserted_on',state_asserted_on,
              'state_source_context',state_source_context,
              'state_notes',state_notes
            )
          )
          order by feature_key
        ),
        '[]'::jsonb
      ) as features
    from configured
  )
  select
    case
      when p.id is null then jsonb_build_object(
        'status','missing',
        'schema','managed-food-feature-context-v1',
        'property',jsonb_build_object('slug',p_slug),
        'as_of_date',p_as_of_date
      )
      else jsonb_build_object(
        'status',case
          when i.inventory_status='confirmed_none' then 'known'
          when i.inventory_status='configured' and s.unknown_state_count=0 then
            case when s.active_feature_count>0 then 'available' else 'known' end
          else 'unavailable'
        end,
        'schema','managed-food-feature-context-v1',
        'product_key','managed-food-feature-context',
        'property',jsonb_build_object('slug',p.slug),
        'as_of_date',p_as_of_date,
        'season_year',extract(year from p_as_of_date)::integer,
        'inventory_status',coalesce(i.inventory_status,'unknown'),
        'inventory_asserted_on',i.asserted_on,
        'inventory_source_context',coalesce(i.source_context,'{}'::jsonb),
        'inventory_notes',i.notes,
        'configured_feature_count',s.configured_feature_count,
        'active_feature_count',s.active_feature_count,
        'managed_food_present',case
          when i.inventory_status='confirmed_none' then false
          when i.inventory_status='configured' and s.unknown_state_count=0
            then s.active_feature_count>0
          else null
        end,
        'features',s.features,
        'evidence_class','operator_configured_static_feature_inventory',
        'scoring_performed',false,
        'behavioral_inference_performed',false,
        'interpretation_boundary',
          'This context records explicit managed food-plot/forage geometry and current management state only. It does not infer forage chemistry, nutritional abundance, deer attraction, or deer use. Supplemental feeders and mineral attractants are separate point observations and do not become managed-food polygons.'
      )
    end
  from (select 1) seed
  left join property p on true
  left join inventory i on true
  cross join summary s;
$$;

revoke all on function farm_watch.farm_watch_get_managed_food_feature_context_v1_internal(text,date)
  from public, anon, authenticated;
grant execute on function farm_watch.farm_watch_get_managed_food_feature_context_v1_internal(text,date)
  to service_role;

with p as (
  select id
  from farm_watch.properties
  where slug='validation-property-01' and status='active'
  limit 1
)
insert into farm_watch.property_managed_food_inventory_v1 (
  property_id,
  season_year,
  inventory_status,
  asserted_on,
  source_context,
  notes
)
select
  p.id,
  2026,
  'confirmed_none',
  date '2026-09-25',
  jsonb_build_object(
    'source_class','owner_configuration',
    'owner_confirmed_local_date','2026-09-25',
    'scope','managed food plots and managed forage areas on the watched property',
    'configuration_semantics','explicit known absence for 2026; future years require their own state'
  ),
  'Owner confirmed there are no food plots or managed forage areas on Flat Creek in 2026.'
from p
on conflict (property_id,season_year) do update
set inventory_status=excluded.inventory_status,
    asserted_on=excluded.asserted_on,
    source_context=excluded.source_context,
    notes=excluded.notes,
    active=true,
    updated_at=now();

update farm_watch.property_operator_observations_v1 o
set source_context=jsonb_set(
      o.source_context,
      '{feature_semantics_v1}',
      jsonb_build_object(
        'resource_class','supplemental_feed_point',
        'feed_material','corn',
        'owner_confirmed_local_date','2026-09-25',
        'included_in_managed_food_feature_context',false,
        'boundary_reason','FW-M29/FW-M32 managed-food context is polygonal food-plot/managed-forage configuration; this feeder remains a separate point observation.'
      ),
      true
    ),
    notes=concat_ws(
      ' ',
      o.notes,
      'On 2026-09-25 the owner confirmed this is a large corn feeder. It remains a supplemental-feed point and is not promoted to a managed-food polygon.'
    ),
    updated_at=now()
from farm_watch.properties p
where o.property_id=p.id
  and p.slug='validation-property-01'
  and o.observation_key='flat-creek-deer-feeder-01'
  and o.active;

with p as (
  select id
  from farm_watch.properties
  where slug='validation-property-01' and status='active'
  limit 1
)
insert into farm_watch.property_operator_observations_v1 (
  property_id,
  observation_key,
  observation_kind,
  observation_state,
  persistence_status,
  timing_status,
  observed_date_start,
  geometry_basis,
  geometry_precision_m,
  related_feature_key,
  source_context,
  notes,
  geometry
)
select
  p.id,
  'flat-creek-salt-block-01',
  'mineral_attractant_location',
  'observed_present',
  'unknown',
  'dated',
  date '2026-09-25',
  'operator_identified_canonical_trail_junction_v1',
  15.0,
  'flat-creek-phase3-image-trails',
  jsonb_build_object(
    'source_class','owner_observation',
    'owner_confirmed_local_date','2026-09-25',
    'resource_class','mineral_attractant_point',
    'canonical_trail_path_key','flat-creek-phase3-image-trails',
    'junction_incident_segments',3,
    'canonical_junction_geojson',jsonb_build_object(
      'type','Point',
      'coordinates',jsonb_build_array(-84.8850346,38.3234328)
    ),
    'map_screenshot_used_for_verification',true,
    'source_screenshot_persisted',false,
    'included_in_managed_food_feature_context',false
  ),
  'Owner identified the salt block at the three-way trail junction marked on the Farm Watch map. The point is snapped to the existing canonical operator-confirmed trail junction; the verification screenshot is not persisted.',
  extensions.st_setsrid(extensions.st_makepoint(-84.8850346,38.3234328),4326)
from p
on conflict (property_id,observation_key) do update
set observation_kind=excluded.observation_kind,
    observation_state=excluded.observation_state,
    persistence_status=excluded.persistence_status,
    timing_status=excluded.timing_status,
    observed_date_start=excluded.observed_date_start,
    geometry_basis=excluded.geometry_basis,
    geometry_precision_m=excluded.geometry_precision_m,
    related_feature_key=excluded.related_feature_key,
    source_context=excluded.source_context,
    notes=excluded.notes,
    geometry=excluded.geometry,
    active=true,
    updated_at=now();

commit;
