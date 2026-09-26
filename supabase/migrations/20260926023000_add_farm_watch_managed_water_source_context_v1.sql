begin;

create table if not exists farm_watch.property_managed_water_inventory_v1 (
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
  unique(property_id,season_year)
);

comment on table farm_watch.property_managed_water_inventory_v1 is
  'Private property/year inventory state for managed artificial water sources such as stock ponds, troughs, and tanks. confirmed_none is explicit known absence, not missing data.';

create table if not exists farm_watch.property_managed_water_sources_v1 (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references farm_watch.properties(id) on delete cascade,
  source_key text not null,
  source_class text not null
    check (source_class in ('stock_pond','trough','tank','other_managed_water')),
  name text,
  geometry_basis text not null,
  geometry_precision_m numeric check (geometry_precision_m is null or geometry_precision_m > 0),
  source_context jsonb not null default '{}'::jsonb,
  notes text,
  geometry extensions.geometry(Geometry,4326) not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(property_id,source_key),
  check (source_key ~ '^[a-z0-9][a-z0-9_-]{0,79}$'),
  check (
    upper(extensions.geometrytype(geometry)) in (
      'POINT','MULTIPOINT','POLYGON','MULTIPOLYGON'
    )
  )
);

comment on table farm_watch.property_managed_water_sources_v1 is
  'Stable operator-configured geometry for managed artificial water sources. Geometry is configured once; dated/year-scoped usable-water state is stored separately.';

create index if not exists property_managed_water_sources_v1_geometry_gix
  on farm_watch.property_managed_water_sources_v1 using gist(geometry);

create index if not exists property_managed_water_sources_v1_property_idx
  on farm_watch.property_managed_water_sources_v1(property_id)
  where active=true;

create table if not exists farm_watch.property_managed_water_source_state_v1 (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null references farm_watch.property_managed_water_sources_v1(id) on delete cascade,
  season_year integer not null check (season_year between 2000 and 2100),
  availability_state text not null
    check (availability_state in ('known_usable','known_not_usable','unknown')),
  valid_from date,
  valid_through date,
  asserted_on date,
  source_context jsonb not null default '{}'::jsonb,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(source_id,season_year),
  check (valid_through is null or valid_from is not null),
  check (valid_through is null or valid_through >= valid_from),
  check (valid_from is null or extract(year from valid_from)::integer=season_year),
  check (valid_through is null or extract(year from valid_through)::integer=season_year)
);

comment on table farm_watch.property_managed_water_source_state_v1 is
  'Year-scoped explicit usable-water state for a stable managed source. known_usable is operator-configured factual source availability, not inferred from hydrography or weather.';

alter table farm_watch.property_managed_water_inventory_v1 enable row level security;
alter table farm_watch.property_managed_water_sources_v1 enable row level security;
alter table farm_watch.property_managed_water_source_state_v1 enable row level security;

revoke all on table farm_watch.property_managed_water_inventory_v1 from public,anon,authenticated;
revoke all on table farm_watch.property_managed_water_sources_v1 from public,anon,authenticated;
revoke all on table farm_watch.property_managed_water_source_state_v1 from public,anon,authenticated;

grant select,insert,update,delete on table farm_watch.property_managed_water_inventory_v1 to service_role;
grant select,insert,update,delete on table farm_watch.property_managed_water_sources_v1 to service_role;
grant select,insert,update,delete on table farm_watch.property_managed_water_source_state_v1 to service_role;

create or replace function farm_watch.farm_watch_get_managed_water_source_context_v1_internal(
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
    from farm_watch.property_managed_water_inventory_v1 i
    join property p on p.id=i.property_id
    where i.active
      and i.season_year=extract(year from p_as_of_date)::integer
    limit 1
  ),
  configured as (
    select
      w.source_key,
      w.source_class,
      w.name,
      w.geometry_basis,
      w.geometry_precision_m,
      w.source_context,
      w.notes,
      s.availability_state,
      s.valid_from,
      s.valid_through,
      s.asserted_on as state_asserted_on,
      s.source_context as state_source_context,
      s.notes as state_notes,
      case
        when s.availability_state='known_usable'
          and (
            s.valid_from is null
            or p_as_of_date between s.valid_from and coalesce(s.valid_through,make_date(s.season_year,12,31))
          )
          then 'known_managed_source_present'
        when s.availability_state='known_not_usable'
          and (
            s.valid_from is null
            or p_as_of_date between s.valid_from and coalesce(s.valid_through,make_date(s.season_year,12,31))
          )
          then 'known_managed_source_absent'
        else 'managed_source_state_unknown'
      end as current_presence_state,
      extensions.st_asgeojson(w.geometry,7)::jsonb as geometry_geojson
    from farm_watch.property_managed_water_sources_v1 w
    join property p on p.id=w.property_id
    join farm_watch.property_managed_water_source_state_v1 s
      on s.source_id=w.id
     and s.season_year=extract(year from p_as_of_date)::integer
    where w.active
    order by w.source_key
  ),
  summary as (
    select
      count(*)::integer as configured_source_count,
      count(*) filter (where current_presence_state='known_managed_source_present')::integer
        as known_usable_count,
      count(*) filter (where current_presence_state='known_managed_source_absent')::integer
        as known_not_usable_count,
      count(*) filter (where current_presence_state='managed_source_state_unknown')::integer
        as unknown_state_count,
      coalesce(
        jsonb_agg(
          jsonb_strip_nulls(
            jsonb_build_object(
              'source_key',source_key,
              'source_class',source_class,
              'name',name,
              'current_presence_state',current_presence_state,
              'availability_state',availability_state,
              'valid_from',valid_from,
              'valid_through',valid_through,
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
          order by source_key
        ),
        '[]'::jsonb
      ) as sources
    from configured
  )
  select
    case
      when p.id is null then jsonb_build_object(
        'status','missing',
        'schema','managed-water-source-context-v1',
        'property',jsonb_build_object('slug',p_slug),
        'as_of_date',p_as_of_date
      )
      else jsonb_build_object(
        'status',case
          when i.inventory_status='confirmed_none' then 'known'
          when i.inventory_status='configured' and s.unknown_state_count=0
            then case when s.known_usable_count>0 then 'available' else 'known' end
          else 'unavailable'
        end,
        'schema','managed-water-source-context-v1',
        'product_key','managed-water-source-context',
        'property',jsonb_build_object('slug',p.slug),
        'as_of_date',p_as_of_date,
        'season_year',extract(year from p_as_of_date)::integer,
        'inventory_status',coalesce(i.inventory_status,'unknown'),
        'inventory_asserted_on',i.asserted_on,
        'inventory_source_context',coalesce(i.source_context,'{}'::jsonb),
        'inventory_notes',i.notes,
        'configured_source_count',s.configured_source_count,
        'known_usable_count',s.known_usable_count,
        'known_not_usable_count',s.known_not_usable_count,
        'current_presence_state',case
          when i.inventory_status='confirmed_none' then 'known_managed_source_absent'
          when i.inventory_status='configured' and s.unknown_state_count=0 and s.known_usable_count>0
            then 'known_managed_source_present'
          when i.inventory_status='configured' and s.unknown_state_count=0
            then 'known_managed_source_absent'
          else 'managed_source_state_unknown'
        end,
        'sources',s.sources,
        'evidence_class','operator_configured_static_feature_inventory',
        'scoring_performed',false,
        'behavioral_inference_performed',false,
        'interpretation_boundary',
          'This context records explicit managed artificial water-source geometry and dated/year-scoped usable-water state only. It does not infer water presence from hydrography, precipitation, drainage, or remotely sensed wetness, and it does not infer deer attraction, visitation, movement, or habitat quality.'
      )
    end
  from (select 1) seed
  left join property p on true
  left join inventory i on true
  cross join summary s;
$$;

revoke all on function farm_watch.farm_watch_get_managed_water_source_context_v1_internal(text,date)
  from public,anon,authenticated;
grant execute on function farm_watch.farm_watch_get_managed_water_source_context_v1_internal(text,date)
  to service_role;

commit;
