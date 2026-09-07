-- Scout building attribute + historic masonry enrichment pipeline v1
--
-- Purpose:
--   Preserve source-specific observations for building height/stories/facade
--   attributes and National Register historic-resource context without
--   overwriting canonical building records. Internal collectors write through
--   service-role-only RPCs; derived views carry confidence/provenance into
--   Scout decisioning.

create table if not exists decisioning.building_attribute_observations (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null references ingest.sources(id),
  source_native_id text not null,
  source_feature_kind text not null default 'building',
  observed_at timestamptz not null default now(),
  source_timestamp timestamptz,
  geometry geometry(Geometry,4326) not null,
  height_m numeric,
  height_status text not null default 'unknown',
  story_count integer,
  story_status text not null default 'unknown',
  facade_material text,
  raw_facade_material text,
  facade_material_status text not null default 'unknown',
  glazing_signal text,
  has_parts boolean,
  confidence numeric not null default 0.80 check (confidence >= 0 and confidence <= 1),
  attributes jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(source_id, source_native_id, source_feature_kind),
  check (height_m is null or height_m > 0),
  check (story_count is null or story_count > 0)
);

alter table decisioning.building_attribute_observations enable row level security;
create index if not exists building_attribute_observations_geometry_gix
  on decisioning.building_attribute_observations using gist(geometry);
create index if not exists building_attribute_observations_source_idx
  on decisioning.building_attribute_observations(source_id, observed_at desc);

create table if not exists decisioning.building_attribute_matches (
  building_source_record_id uuid not null,
  observation_id uuid not null references decisioning.building_attribute_observations(id) on delete cascade,
  match_basis text not null,
  overlap_ratio numeric,
  centroid_distance_m numeric,
  confidence numeric not null check (confidence >= 0 and confidence <= 1),
  matched_at timestamptz not null default now(),
  primary key(building_source_record_id, observation_id)
);

alter table decisioning.building_attribute_matches enable row level security;
create index if not exists building_attribute_matches_observation_idx
  on decisioning.building_attribute_matches(observation_id);
create index if not exists building_attribute_matches_building_idx
  on decisioning.building_attribute_matches(building_source_record_id, confidence desc);

create table if not exists intelligence.historic_resources (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null references ingest.sources(id),
  source_native_id text not null,
  resource_name text,
  resource_type text,
  reference_number text,
  designation_status text,
  listed_date date,
  address_text text,
  city text,
  county_name text,
  state_code text,
  is_national_historic_landmark boolean,
  geometry geometry(Geometry,4326) not null,
  confidence numeric not null default 0.90 check (confidence >= 0 and confidence <= 1),
  source_url text,
  observed_at timestamptz not null default now(),
  attributes jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(source_id, source_native_id)
);

alter table intelligence.historic_resources enable row level security;
create index if not exists historic_resources_geometry_gix
  on intelligence.historic_resources using gist(geometry);
create index if not exists historic_resources_state_type_idx
  on intelligence.historic_resources(state_code, resource_type);

create table if not exists intelligence.historic_resource_building_matches (
  historic_resource_id uuid not null references intelligence.historic_resources(id) on delete cascade,
  building_source_record_id uuid not null,
  relationship_type text not null,
  distance_m numeric,
  confidence numeric not null check (confidence >= 0 and confidence <= 1),
  matched_at timestamptz not null default now(),
  primary key(historic_resource_id, building_source_record_id, relationship_type)
);

alter table intelligence.historic_resource_building_matches enable row level security;
create index if not exists historic_resource_building_matches_building_idx
  on intelligence.historic_resource_building_matches(building_source_record_id, confidence desc);

insert into ingest.sources(
  slug,name,authority,source_class,geographic_scope,acquisition_method,
  update_cadence,authority_level,status,homepage_url,license_notes,
  commercial_use_status,notes
)
values
(
  'openstreetmap-geofabrik-building-attributes',
  'OpenStreetMap Geofabrik Building Attribute Snapshot',
  'OpenStreetMap contributors / Geofabrik GmbH',
  'building_attribute_context',
  'Scout Louisville 100-mile pilot portions of Kentucky, Indiana and Ohio',
  'regional PBF snapshot filtered to building height/level/material tags',
  'snapshot / operator-triggered refresh',
  'community_primary',
  'active_reference',
  'https://download.geofabrik.de/',
  'ODbL attribution and share-alike obligations apply to OSM-derived database content.',
  'allowed_with_license_compliance',
  'Use only explicit building attributes such as building:levels, height, building:material and facade:material; absence is not evidence of absence.'
),
(
  'usgs-3dep-lidar',
  'USGS 3D Elevation Program Lidar Point Cloud',
  'U.S. Geological Survey',
  'building_height_context',
  'United States',
  '3DEP lidar / point-cloud derived building height enrichment',
  'source-vintage dependent',
  'federal_primary',
  'active_reference',
  'https://www.usgs.gov/3d-elevation-program',
  'USGS 3DEP products are public domain.',
  'allowed',
  'Use as derived height evidence with acquisition date, quality level and derivation method retained.'
),
(
  'nps-national-register-historic-places',
  'National Register of Historic Places Public Spatial Dataset',
  'U.S. National Park Service',
  'historic_property_inventory',
  'United States',
  'NPS ArcGIS FeatureServer / public GIS dataset',
  'periodic public refresh',
  'federal_primary',
  'active_reference',
  'https://www.nps.gov/subjects/nationalregister/data-downloads.htm',
  'Public NPS cultural-resource spatial data; preserve source caveats and positional uncertainty.',
  'allowed_with_source_caveats',
  'Historic designation is not proof of masonry material, current condition, cleaning need, or contributing-resource status inside a district.'
)
on conflict (slug) do update set
  name=excluded.name,
  authority=excluded.authority,
  source_class=excluded.source_class,
  geographic_scope=excluded.geographic_scope,
  acquisition_method=excluded.acquisition_method,
  update_cadence=excluded.update_cadence,
  authority_level=excluded.authority_level,
  status=excluded.status,
  homepage_url=excluded.homepage_url,
  license_notes=excluded.license_notes,
  commercial_use_status=excluded.commercial_use_status,
  notes=excluded.notes,
  updated_at=now();

update ingest.sources
set acquisition_method='cloud GeoParquet / bounded area extraction',
    status='active_reference',
    notes=concat_ws(
      ' ',
      nullif(notes,''),
      'Building schema exposes height, num_floors and facade_material; retain source provenance for every resolved attribute.'
    ),
    updated_at=now()
where slug='overture-buildings';

create or replace function public.internal_ingest_building_attribute_batch(
  p_source_slug text,
  p_features jsonb,
  p_source_timestamp timestamptz default null
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','extensions','ingest','decisioning'
as $$
declare
  v_source_id uuid;
  v_feature jsonb;
  v_geom geometry;
  v_obs_id uuid;
  v_building_id uuid;
  v_overlap numeric;
  v_distance numeric;
  v_candidate_area numeric;
  v_source_area numeric;
  v_match_conf numeric;
  v_accepted int := 0;
  v_matched int := 0;
  v_unmatched int := 0;
  v_invalid int := 0;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service_role required';
  end if;
  if jsonb_typeof(p_features) <> 'array' then
    raise exception 'p_features must be a JSON array';
  end if;

  select id into v_source_id
  from ingest.sources
  where slug=p_source_slug
    and status in ('active','active_reference','source_identified')
  limit 1;

  if v_source_id is null then
    raise exception 'unknown or inactive source: %', p_source_slug;
  end if;

  for v_feature in select value from jsonb_array_elements(p_features)
  loop
    begin
      v_geom := st_setsrid(st_geomfromgeojson((v_feature->'geometry')::text),4326);
      if v_geom is null or st_isempty(v_geom) then
        raise exception 'empty geometry';
      end if;
      if not st_isvalid(v_geom) then
        v_geom := st_makevalid(v_geom);
      end if;

      insert into decisioning.building_attribute_observations(
        source_id,source_native_id,source_feature_kind,observed_at,source_timestamp,geometry,
        height_m,height_status,story_count,story_status,facade_material,raw_facade_material,
        facade_material_status,glazing_signal,has_parts,confidence,attributes,updated_at
      ) values (
        v_source_id,
        nullif(v_feature->>'source_native_id',''),
        coalesce(nullif(v_feature->>'feature_kind',''),'building'),
        now(),
        p_source_timestamp,
        v_geom,
        nullif(v_feature->>'height_m','')::numeric,
        coalesce(nullif(v_feature->>'height_status',''),'unknown'),
        nullif(v_feature->>'story_count','')::integer,
        coalesce(nullif(v_feature->>'story_status',''),'unknown'),
        nullif(v_feature->>'facade_material',''),
        nullif(v_feature->>'raw_facade_material',''),
        coalesce(nullif(v_feature->>'facade_material_status',''),'unknown'),
        nullif(v_feature->>'glazing_signal',''),
        nullif(v_feature->>'has_parts','')::boolean,
        coalesce(nullif(v_feature->>'confidence','')::numeric,0.80),
        coalesce(v_feature->'attributes','{}'::jsonb),
        now()
      )
      on conflict(source_id,source_native_id,source_feature_kind) do update set
        observed_at=excluded.observed_at,
        source_timestamp=excluded.source_timestamp,
        geometry=excluded.geometry,
        height_m=excluded.height_m,
        height_status=excluded.height_status,
        story_count=excluded.story_count,
        story_status=excluded.story_status,
        facade_material=excluded.facade_material,
        raw_facade_material=excluded.raw_facade_material,
        facade_material_status=excluded.facade_material_status,
        glazing_signal=excluded.glazing_signal,
        has_parts=excluded.has_parts,
        confidence=excluded.confidence,
        attributes=excluded.attributes,
        updated_at=now()
      returning id into v_obs_id;

      v_accepted := v_accepted + 1;

      select q.source_record_id,q.overlap_ratio,q.distance_m,q.candidate_area,q.source_area
      into v_building_id,v_overlap,v_distance,v_candidate_area,v_source_area
      from (
        select bc.source_record_id,
          case
            when st_dimension(v_geom)=2 and st_dimension(bc.geometry)=2 then
              st_area(st_intersection(st_makevalid(bc.geometry),v_geom)::geography) /
              nullif(
                least(
                  st_area(st_makevalid(bc.geometry)::geography),
                  st_area(v_geom::geography)
                ),
                0
              )
            else 0
          end as overlap_ratio,
          st_distance(
            st_pointonsurface(st_makevalid(bc.geometry))::geography,
            st_pointonsurface(v_geom)::geography
          ) as distance_m,
          st_area(st_makevalid(bc.geometry)::geography) as candidate_area,
          case when st_dimension(v_geom)=2 then st_area(v_geom::geography) else null end as source_area
        from decisioning.building_candidates bc
        where bc.geometry is not null
          and bc.geometry && st_expand(v_geom,0.001)
        order by overlap_ratio desc nulls last, distance_m asc
        limit 1
      ) q;

      if v_building_id is not null and (
        coalesce(v_overlap,0) >= 0.45 or
        (
          coalesce(v_distance,999999) <= 7
          and v_source_area is not null
          and v_candidate_area is not null
          and v_source_area/nullif(v_candidate_area,0) between 0.40 and 2.50
        )
      ) then
        v_match_conf := least(0.99,greatest(0.65,coalesce(v_overlap,0.65)));
        insert into decisioning.building_attribute_matches(
          building_source_record_id,observation_id,match_basis,overlap_ratio,
          centroid_distance_m,confidence,matched_at
        ) values (
          v_building_id,
          v_obs_id,
          case when coalesce(v_overlap,0) >= 0.45
            then 'footprint_overlap'
            else 'centroid_and_area_agreement'
          end,
          v_overlap,
          v_distance,
          v_match_conf,
          now()
        )
        on conflict(building_source_record_id,observation_id) do update set
          match_basis=excluded.match_basis,
          overlap_ratio=excluded.overlap_ratio,
          centroid_distance_m=excluded.centroid_distance_m,
          confidence=excluded.confidence,
          matched_at=now();
        v_matched := v_matched + 1;
      else
        v_unmatched := v_unmatched + 1;
      end if;
    exception when others then
      v_invalid := v_invalid + 1;
    end;
  end loop;

  return jsonb_build_object(
    'accepted',v_accepted,
    'matched',v_matched,
    'unmatched',v_unmatched,
    'invalid',v_invalid
  );
end;
$$;

revoke all on function public.internal_ingest_building_attribute_batch(text,jsonb,timestamptz)
  from public,anon,authenticated;
grant execute on function public.internal_ingest_building_attribute_batch(text,jsonb,timestamptz)
  to service_role;

create or replace function public.internal_ingest_historic_resource_batch(
  p_source_slug text,
  p_features jsonb,
  p_observed_at timestamptz default now()
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','extensions','ingest','intelligence','decisioning'
as $$
declare
  v_source_id uuid;
  v_feature jsonb;
  v_geom geometry;
  v_resource_id uuid;
  v_resource_type text;
  v_building record;
  v_inserted int := 0;
  v_matches int := 0;
  v_invalid int := 0;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service_role required';
  end if;
  if jsonb_typeof(p_features) <> 'array' then
    raise exception 'p_features must be a JSON array';
  end if;

  select id into v_source_id
  from ingest.sources
  where slug=p_source_slug
    and status in ('active','active_reference','source_identified')
  limit 1;

  if v_source_id is null then
    raise exception 'unknown or inactive source: %', p_source_slug;
  end if;

  for v_feature in select value from jsonb_array_elements(p_features)
  loop
    begin
      v_geom := st_setsrid(st_geomfromgeojson((v_feature->'geometry')::text),4326);
      if v_geom is null or st_isempty(v_geom) then
        raise exception 'empty geometry';
      end if;
      if not st_isvalid(v_geom) then
        v_geom := st_makevalid(v_geom);
      end if;
      v_resource_type := lower(coalesce(nullif(v_feature->>'resource_type',''),'unknown'));

      insert into intelligence.historic_resources(
        source_id,source_native_id,resource_name,resource_type,reference_number,
        designation_status,listed_date,address_text,city,county_name,state_code,
        is_national_historic_landmark,geometry,confidence,source_url,observed_at,
        attributes,updated_at
      ) values (
        v_source_id,
        nullif(v_feature->>'source_native_id',''),
        nullif(v_feature->>'resource_name',''),
        v_resource_type,
        nullif(v_feature->>'reference_number',''),
        nullif(v_feature->>'designation_status',''),
        nullif(v_feature->>'listed_date','')::date,
        nullif(v_feature->>'address_text',''),
        nullif(v_feature->>'city',''),
        nullif(v_feature->>'county_name',''),
        upper(nullif(v_feature->>'state_code','')),
        coalesce(nullif(v_feature->>'is_national_historic_landmark','')::boolean,false),
        v_geom,
        coalesce(nullif(v_feature->>'confidence','')::numeric,0.90),
        nullif(v_feature->>'source_url',''),
        coalesce(p_observed_at,now()),
        coalesce(v_feature->'attributes','{}'::jsonb),
        now()
      )
      on conflict(source_id,source_native_id) do update set
        resource_name=excluded.resource_name,
        resource_type=excluded.resource_type,
        reference_number=excluded.reference_number,
        designation_status=excluded.designation_status,
        listed_date=excluded.listed_date,
        address_text=excluded.address_text,
        city=excluded.city,
        county_name=excluded.county_name,
        state_code=excluded.state_code,
        is_national_historic_landmark=excluded.is_national_historic_landmark,
        geometry=excluded.geometry,
        confidence=excluded.confidence,
        source_url=excluded.source_url,
        observed_at=excluded.observed_at,
        attributes=excluded.attributes,
        updated_at=now()
      returning id into v_resource_id;

      v_inserted := v_inserted + 1;
      delete from intelligence.historic_resource_building_matches
      where historic_resource_id=v_resource_id;

      if st_dimension(v_geom)=0 and v_resource_type <> 'district' then
        select bc.source_record_id,
               st_distance(
                 st_pointonsurface(st_makevalid(bc.geometry))::geography,
                 v_geom::geography
               ) as distance_m
        into v_building
        from decisioning.building_candidates bc
        where bc.geometry is not null
          and bc.geometry && st_expand(v_geom,0.0006)
          and st_dwithin(
            st_pointonsurface(st_makevalid(bc.geometry))::geography,
            v_geom::geography,
            50
          )
        order by distance_m asc
        limit 1;

        if v_building.source_record_id is not null then
          insert into intelligence.historic_resource_building_matches(
            historic_resource_id,building_source_record_id,relationship_type,
            distance_m,confidence
          ) values (
            v_resource_id,
            v_building.source_record_id,
            'listed_resource_point_match',
            v_building.distance_m,
            case when v_building.distance_m <= 10 then 0.95
                 when v_building.distance_m <= 25 then 0.85
                 else 0.70 end
          );
          v_matches := v_matches + 1;
        end if;
      elsif st_dimension(v_geom)=2 then
        for v_building in
          select bc.source_record_id,
                 st_distance(
                   st_pointonsurface(st_makevalid(bc.geometry))::geography,
                   st_pointonsurface(v_geom)::geography
                 ) as distance_m
          from decisioning.building_candidates bc
          where bc.geometry is not null
            and bc.geometry && v_geom
            and st_intersects(st_makevalid(bc.geometry),v_geom)
        loop
          insert into intelligence.historic_resource_building_matches(
            historic_resource_id,building_source_record_id,relationship_type,
            distance_m,confidence
          ) values (
            v_resource_id,
            v_building.source_record_id,
            case when v_resource_type='district'
              then 'within_listed_district'
              else 'listed_resource_polygon_match'
            end,
            v_building.distance_m,
            case when v_resource_type='district' then 0.80 else 0.95 end
          )
          on conflict do nothing;
          v_matches := v_matches + 1;
        end loop;
      end if;
    exception when others then
      v_invalid := v_invalid + 1;
    end;
  end loop;

  return jsonb_build_object(
    'accepted',v_inserted,
    'building_matches',v_matches,
    'invalid',v_invalid
  );
end;
$$;

revoke all on function public.internal_ingest_historic_resource_batch(text,jsonb,timestamptz)
  from public,anon,authenticated;
grant execute on function public.internal_ingest_historic_resource_batch(text,jsonb,timestamptz)
  to service_role;

create or replace view decisioning.v_building_resolved_attributes
with (security_invoker=true) as
select
  bc.source_record_id as building_source_record_id,
  bc.source_slug,
  bc.source_native_id,
  bc.footprint_sqft,
  coalesce(h.height_m,bc.height_m) as resolved_height_m,
  case
    when h.height_m is not null then h.height_status
    when bc.height_m is not null then 'source_automated'
    else 'unknown'
  end as resolved_height_status,
  h.source_slug as resolved_height_source_slug,
  s.story_count as resolved_story_count,
  coalesce(s.story_status,'unknown') as resolved_story_status,
  s.source_slug as resolved_story_source_slug,
  f.facade_material as resolved_facade_material,
  f.raw_facade_material as resolved_raw_facade_material,
  coalesce(f.facade_material_status,'unknown') as resolved_facade_material_status,
  f.source_slug as resolved_facade_material_source_slug,
  case when g.glass_present then 'glass_facade_present' else null end as glazing_signal,
  g.glazing_confidence,
  coalesce(parts.part_count,0) as matched_building_part_count,
  case
    when coalesce(parts.part_count,0) >= 2 then 'multi_part_geometry_present'
    when coalesce(parts.part_count,0)=1 then 'single_part_geometry_present'
    else 'unknown'
  end as vertical_geometry_signal,
  greatest(
    coalesce(h.match_confidence,0),
    coalesce(s.match_confidence,0),
    coalesce(f.match_confidence,0),
    coalesce(g.glazing_confidence,0)
  ) as resolved_attribute_confidence
from decisioning.building_candidates bc
left join lateral (
  select o.height_m,o.height_status,src.slug as source_slug,m.confidence as match_confidence
  from decisioning.building_attribute_matches m
  join decisioning.building_attribute_observations o on o.id=m.observation_id
  join ingest.sources src on src.id=o.source_id
  where m.building_source_record_id=bc.source_record_id
    and o.height_m is not null
  order by
    case o.height_status
      when 'documented' then 4
      when 'derived_lidar' then 3
      when 'source_reported' then 3
      when 'automated' then 2
      else 1
    end desc,
    case o.source_feature_kind when 'building' then 2 else 1 end desc,
    m.confidence desc,
    o.confidence desc,
    o.observed_at desc
  limit 1
) h on true
left join lateral (
  select o.story_count,o.story_status,src.slug as source_slug,m.confidence as match_confidence
  from decisioning.building_attribute_matches m
  join decisioning.building_attribute_observations o on o.id=m.observation_id
  join ingest.sources src on src.id=o.source_id
  where m.building_source_record_id=bc.source_record_id
    and o.story_count is not null
  order by
    case o.story_status
      when 'documented' then 4
      when 'source_reported' then 3
      when 'derived' then 2
      else 1
    end desc,
    case o.source_feature_kind when 'building' then 2 else 1 end desc,
    m.confidence desc,
    o.confidence desc,
    o.observed_at desc
  limit 1
) s on true
left join lateral (
  select
    o.facade_material,
    o.raw_facade_material,
    o.facade_material_status,
    src.slug as source_slug,
    m.confidence as match_confidence
  from decisioning.building_attribute_matches m
  join decisioning.building_attribute_observations o on o.id=m.observation_id
  join ingest.sources src on src.id=o.source_id
  where m.building_source_record_id=bc.source_record_id
    and o.facade_material is not null
  order by
    case o.facade_material_status
      when 'documented' then 4
      when 'source_reported' then 3
      when 'normalized' then 2
      else 1
    end desc,
    case o.source_feature_kind when 'building' then 2 else 1 end desc,
    m.confidence desc,
    o.confidence desc,
    o.observed_at desc
  limit 1
) f on true
left join lateral (
  select
    bool_or(
      o.facade_material='glass'
      or o.glazing_signal in ('glass_facade','glass_facade_present','confirmed_glazed')
    ) as glass_present,
    max(m.confidence*o.confidence) as glazing_confidence
  from decisioning.building_attribute_matches m
  join decisioning.building_attribute_observations o on o.id=m.observation_id
  where m.building_source_record_id=bc.source_record_id
) g on true
left join lateral (
  select count(*)::int as part_count
  from decisioning.building_attribute_matches m
  join decisioning.building_attribute_observations o on o.id=m.observation_id
  where m.building_source_record_id=bc.source_record_id
    and o.source_feature_kind='building_part'
) parts on true;

revoke all on decisioning.v_building_resolved_attributes from public,anon,authenticated;
grant select on decisioning.v_building_resolved_attributes to service_role;

create or replace view intelligence.v_building_historic_context
with (security_invoker=true) as
select
  bc.source_record_id as building_source_record_id,
  bool_or(
    hr.resource_type='building'
    and m.relationship_type in ('listed_resource_point_match','listed_resource_polygon_match')
  ) as individually_listed_building,
  bool_or(m.relationship_type='within_listed_district') as within_listed_district,
  bool_or(coalesce(hr.is_national_historic_landmark,false)) as national_historic_landmark_context,
  max(m.confidence) as historic_match_confidence,
  array_remove(array_agg(distinct hr.reference_number),null) as reference_numbers,
  array_remove(array_agg(distinct hr.resource_name),null) as historic_resource_names
from decisioning.building_candidates bc
left join intelligence.historic_resource_building_matches m
  on m.building_source_record_id=bc.source_record_id
left join intelligence.historic_resources hr
  on hr.id=m.historic_resource_id
group by bc.source_record_id;

revoke all on intelligence.v_building_historic_context from public,anon,authenticated;
grant select on intelligence.v_building_historic_context to service_role;

create or replace view cleaning.v_historic_masonry_targets
with (security_invoker=true) as
select
  a.building_source_record_id,
  a.source_slug,
  a.source_native_id,
  a.footprint_sqft,
  a.resolved_height_m,
  a.resolved_story_count,
  a.resolved_facade_material,
  a.resolved_raw_facade_material,
  a.resolved_facade_material_status,
  a.resolved_facade_material_source_slug,
  h.individually_listed_building,
  h.within_listed_district,
  h.national_historic_landmark_context,
  h.historic_match_confidence,
  h.reference_numbers,
  h.historic_resource_names,
  case
    when lower(coalesce(a.resolved_raw_facade_material,'')) like '%limestone%'
      then 'explicit_limestone_signal'
    when a.resolved_facade_material='stone'
      then 'stone_material_limestone_unresolved'
    else 'no_limestone_specific_evidence'
  end as limestone_signal,
  case
    when a.resolved_facade_material in ('brick','stone','concrete','cement_block','plaster')
      and h.individually_listed_building then 'high'
    when a.resolved_facade_material in ('brick','stone','concrete','cement_block','plaster')
      and h.within_listed_district then 'medium'
    when h.individually_listed_building or h.within_listed_district
      then 'surface_material_unresolved'
    else 'not_historic_context'
  end as masonry_target_status,
  (
    a.resolved_facade_material in ('brick','stone','concrete','cement_block','plaster')
    and (h.individually_listed_building or h.within_listed_district)
  ) as rankable_historic_masonry_candidate,
  'Historic designation is a targeting/context signal only. Verify contributing status, actual facade material, condition, preservation requirements and appropriate cleaning method before outreach or pricing.'::text as guardrail
from decisioning.v_building_resolved_attributes a
join intelligence.v_building_historic_context h
  on h.building_source_record_id=a.building_source_record_id
where h.individually_listed_building or h.within_listed_district;

revoke all on cleaning.v_historic_masonry_targets from public,anon,authenticated;
grant select on cleaning.v_historic_masonry_targets to service_role;

create or replace view decisioning.v_building_height_resolution_queue
with (security_invoker=true) as
select
  a.building_source_record_id,
  a.source_slug,
  a.source_native_id,
  a.footprint_sqft,
  a.resolved_height_m,
  a.resolved_height_status,
  a.resolved_story_count,
  a.resolved_story_status,
  case
    when a.resolved_story_count is null and a.resolved_height_m is null
      then 'height_and_stories_missing'
    when a.resolved_story_count is null then 'stories_missing'
    when a.resolved_height_m is null then 'height_missing'
    else 'resolved'
  end as resolution_need,
  case
    when exists(
      select 1
      from intelligence.premium_exterior_targets p
      where p.building_source_record_id=a.building_source_record_id
        and p.source_present
    ) then 'premium_exterior_target'
    else 'general_building'
  end as priority_context
from decisioning.v_building_resolved_attributes a
where a.resolved_story_count is null or a.resolved_height_m is null;

revoke all on decisioning.v_building_height_resolution_queue from public,anon,authenticated;
grant select on decisioning.v_building_height_resolution_queue to service_role;
