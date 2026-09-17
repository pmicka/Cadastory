create table if not exists farm_watch.property_hydrology_features_v1 (
  property_id uuid not null references farm_watch.properties(id) on delete cascade,
  source_slug text not null,
  feature_kind text not null check (feature_kind in ('flowline','waterbody','wetland')),
  source_feature_id text not null,
  geometry extensions.geometry(Geometry,4326) not null,
  intersects_property boolean not null default false,
  distance_m numeric not null,
  intersection_acres numeric,
  intersection_length_m numeric,
  properties jsonb not null default '{}'::jsonb,
  retrieved_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (property_id, source_slug, feature_kind, source_feature_id)
);

create index if not exists property_hydrology_features_v1_property_kind_idx
  on farm_watch.property_hydrology_features_v1(property_id, feature_kind, distance_m);
create index if not exists property_hydrology_features_v1_geometry_gix
  on farm_watch.property_hydrology_features_v1 using gist(geometry);

alter table farm_watch.property_hydrology_features_v1 enable row level security;
revoke all on table farm_watch.property_hydrology_features_v1 from public, anon, authenticated;
grant select, insert, update, delete on table farm_watch.property_hydrology_features_v1 to service_role;

comment on table farm_watch.property_hydrology_features_v1 is
'Owner-only Farm Watch cache of authoritative USGS 3DHP flowline/waterbody and USFWS NWI wetland features within a bounded distance of a selected private property. DEM-derived flow interpretation is intentionally excluded.';

create table if not exists farm_watch.hydrology_refresh_state_v1 (
  property_id uuid primary key references farm_watch.properties(id) on delete cascade,
  buffer_m integer not null check (buffer_m between 0 and 1500),
  status text not null check (status in ('available','partial','unavailable')),
  source_status jsonb not null default '{}'::jsonb,
  retrieved_at timestamptz not null,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table farm_watch.hydrology_refresh_state_v1 enable row level security;
revoke all on table farm_watch.hydrology_refresh_state_v1 from public, anon, authenticated;
grant select, insert, update, delete on table farm_watch.hydrology_refresh_state_v1 to service_role;

create or replace function public.farm_watch_replace_hydrology_v1_internal(
  p_slug text,
  p_features jsonb,
  p_buffer_m integer default 1000,
  p_source_status jsonb default '{}'::jsonb,
  p_retrieved_at timestamptz default now()
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','farm_watch','extensions'
as $function$
declare
  v_property_id uuid;
  v_boundary extensions.geometry;
  v_item jsonb;
  v_kind text;
  v_source_slug text;
  v_source_feature_id text;
  v_geom extensions.geometry;
  v_intersects boolean;
  v_distance_m numeric;
  v_inserted integer := 0;
  v_available integer := 0;
  v_total_sources integer := 3;
  v_status text;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service_role required';
  end if;
  if p_buffer_m < 0 or p_buffer_m > 1500 then
    raise exception 'p_buffer_m must be between 0 and 1500';
  end if;
  if jsonb_typeof(coalesce(p_features,'[]'::jsonb)) <> 'array' then
    raise exception 'p_features must be a JSON array';
  end if;

  select p.id, p.boundary
  into v_property_id, v_boundary
  from farm_watch.properties p
  where p.slug=p_slug and p.status='active'
  limit 1;

  if v_property_id is null or v_boundary is null then
    raise exception 'active Farm Watch property with boundary required';
  end if;

  if coalesce(p_source_status->>'flowline','')='available' then
    delete from farm_watch.property_hydrology_features_v1
    where property_id=v_property_id and feature_kind='flowline';
    v_available := v_available + 1;
  end if;
  if coalesce(p_source_status->>'waterbody','')='available' then
    delete from farm_watch.property_hydrology_features_v1
    where property_id=v_property_id and feature_kind='waterbody';
    v_available := v_available + 1;
  end if;
  if coalesce(p_source_status->>'wetland','')='available' then
    delete from farm_watch.property_hydrology_features_v1
    where property_id=v_property_id and feature_kind='wetland';
    v_available := v_available + 1;
  end if;

  for v_item in select value from jsonb_array_elements(coalesce(p_features,'[]'::jsonb))
  loop
    begin
      v_kind := nullif(v_item->>'feature_kind','');
      v_source_slug := nullif(v_item->>'source_slug','');
      v_source_feature_id := nullif(v_item->>'source_feature_id','');
      if v_kind not in ('flowline','waterbody','wetland') or v_source_slug is null or v_source_feature_id is null then
        continue;
      end if;
      if v_item->'geometry' is null or v_item->'geometry'='null'::jsonb then
        continue;
      end if;

      v_geom := extensions.st_setsrid(extensions.st_geomfromgeojson((v_item->'geometry')::text),4326);
      v_geom := extensions.st_makevalid(v_geom);
      if v_kind='flowline' then
        v_geom := extensions.st_collectionextract(v_geom,2);
      else
        v_geom := extensions.st_collectionextract(v_geom,3);
      end if;
      if v_geom is null or extensions.st_isempty(v_geom) then
        continue;
      end if;

      if not extensions.st_dwithin(v_geom::extensions.geography, v_boundary::extensions.geography, p_buffer_m) then
        continue;
      end if;

      v_intersects := extensions.st_intersects(v_geom,v_boundary);
      v_distance_m := extensions.st_distance(v_geom::extensions.geography,v_boundary::extensions.geography);

      insert into farm_watch.property_hydrology_features_v1(
        property_id,source_slug,feature_kind,source_feature_id,geometry,intersects_property,distance_m,
        intersection_acres,intersection_length_m,properties,retrieved_at,updated_at
      ) values (
        v_property_id,v_source_slug,v_kind,v_source_feature_id,v_geom,v_intersects,v_distance_m,
        case when v_intersects and v_kind in ('waterbody','wetland')
          then extensions.st_area(extensions.st_intersection(v_geom,v_boundary)::extensions.geography)/4046.8564224
          else null end,
        case when v_intersects and v_kind='flowline'
          then extensions.st_length(extensions.st_intersection(v_geom,v_boundary)::extensions.geography)
          else null end,
        coalesce(v_item->'properties','{}'::jsonb),coalesce(p_retrieved_at,now()),now()
      )
      on conflict(property_id,source_slug,feature_kind,source_feature_id) do update set
        geometry=excluded.geometry,
        intersects_property=excluded.intersects_property,
        distance_m=excluded.distance_m,
        intersection_acres=excluded.intersection_acres,
        intersection_length_m=excluded.intersection_length_m,
        properties=excluded.properties,
        retrieved_at=excluded.retrieved_at,
        updated_at=now();
      v_inserted := v_inserted + 1;
    exception when others then
      continue;
    end;
  end loop;

  v_status := case
    when v_available=v_total_sources then 'available'
    when v_available>0 then 'partial'
    else 'unavailable'
  end;

  insert into farm_watch.hydrology_refresh_state_v1(property_id,buffer_m,status,source_status,retrieved_at,last_error,updated_at)
  values (v_property_id,p_buffer_m,v_status,coalesce(p_source_status,'{}'::jsonb),coalesce(p_retrieved_at,now()),null,now())
  on conflict(property_id) do update set
    buffer_m=excluded.buffer_m,
    status=excluded.status,
    source_status=excluded.source_status,
    retrieved_at=excluded.retrieved_at,
    last_error=null,
    updated_at=now();

  return jsonb_build_object(
    'status',v_status,
    'features_stored',v_inserted,
    'sources_available',v_available,
    'sources_expected',v_total_sources,
    'buffer_m',p_buffer_m,
    'retrieved_at',coalesce(p_retrieved_at,now())
  );
end;
$function$;

revoke all on function public.farm_watch_replace_hydrology_v1_internal(text,jsonb,integer,jsonb,timestamptz) from public, anon, authenticated;
grant execute on function public.farm_watch_replace_hydrology_v1_internal(text,jsonb,integer,jsonb,timestamptz) to service_role;

create or replace function public.farm_watch_get_hydrology_v1_internal(p_slug text)
returns jsonb
language sql
stable
security definer
set search_path='pg_catalog'
as $function$
  with property as (
    select p.id
    from farm_watch.properties p
    where p.slug=p_slug and p.status='active'
    limit 1
  ),
  features as (
    select h.*
    from farm_watch.property_hydrology_features_v1 h
    join property p on p.id=h.property_id
  ),
  state as (
    select s.*
    from farm_watch.hydrology_refresh_state_v1 s
    join property p on p.id=s.property_id
  ),
  feature_json as (
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'type','Feature',
        'id',f.source_slug||':'||f.feature_kind||':'||f.source_feature_id,
        'geometry',extensions.st_asgeojson(f.geometry,6)::jsonb,
        'properties',coalesce(f.properties,'{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
          'source_slug',f.source_slug,
          'feature_kind',f.feature_kind,
          'source_feature_id',f.source_feature_id,
          'intersects_property',f.intersects_property,
          'distance_m',round(f.distance_m,1),
          'intersection_acres',case when f.intersection_acres is null then null else round(f.intersection_acres,3) end,
          'intersection_length_m',case when f.intersection_length_m is null then null else round(f.intersection_length_m,1) end
        ))
      )
      order by f.feature_kind,f.distance_m,f.source_feature_id
    ),'[]'::jsonb) as features
    from features f
  ),
  stats as (
    select
      count(*)::integer as feature_count,
      count(*) filter(where feature_kind='flowline')::integer as flowline_count,
      count(*) filter(where feature_kind='waterbody')::integer as waterbody_count,
      count(*) filter(where feature_kind='wetland')::integer as wetland_count,
      count(*) filter(where intersects_property)::integer as intersecting_count,
      min(distance_m) filter(where feature_kind='flowline') as nearest_flowline_m,
      min(distance_m) filter(where feature_kind='waterbody') as nearest_waterbody_m,
      min(distance_m) filter(where feature_kind='wetland') as nearest_wetland_m,
      sum(coalesce(intersection_acres,0)) filter(where feature_kind='wetland') as wetland_intersection_acres,
      sum(coalesce(intersection_acres,0)) filter(where feature_kind='waterbody') as waterbody_intersection_acres,
      sum(coalesce(intersection_length_m,0)) filter(where feature_kind='flowline') as flowline_intersection_m
    from features
  )
  select jsonb_build_object(
    'status',coalesce((select status from state),'unavailable'),
    'feature_collection',jsonb_build_object('type','FeatureCollection','features',(select features from feature_json)),
    'summary',jsonb_strip_nulls(jsonb_build_object(
      'source','USGS 3DHP + USFWS NWI',
      'feature_count',coalesce((select feature_count from stats),0),
      'flowline_count',coalesce((select flowline_count from stats),0),
      'waterbody_count',coalesce((select waterbody_count from stats),0),
      'wetland_count',coalesce((select wetland_count from stats),0),
      'intersecting_count',coalesce((select intersecting_count from stats),0),
      'nearest_flowline_m',case when (select nearest_flowline_m from stats) is null then null else round((select nearest_flowline_m from stats),1) end,
      'nearest_waterbody_m',case when (select nearest_waterbody_m from stats) is null then null else round((select nearest_waterbody_m from stats),1) end,
      'nearest_wetland_m',case when (select nearest_wetland_m from stats) is null then null else round((select nearest_wetland_m from stats),1) end,
      'wetland_intersection_acres',case when (select wetland_intersection_acres from stats) is null then null else round((select wetland_intersection_acres from stats),3) end,
      'waterbody_intersection_acres',case when (select waterbody_intersection_acres from stats) is null then null else round((select waterbody_intersection_acres from stats),3) end,
      'flowline_intersection_m',case when (select flowline_intersection_m from stats) is null then null else round((select flowline_intersection_m from stats),1) end,
      'buffer_m',(select buffer_m from state),
      'source_status',(select source_status from state),
      'retrieved_at',(select retrieved_at from state)
    ))
  );
$function$;

revoke all on function public.farm_watch_get_hydrology_v1_internal(text) from public, anon, authenticated;
grant execute on function public.farm_watch_get_hydrology_v1_internal(text) to service_role;
