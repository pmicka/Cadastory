insert into ingest.sources (
  slug,name,authority,source_class,geographic_scope,acquisition_method,update_cadence,
  authority_level,status,homepage_url,commercial_use_status,notes
) values
('kgs-24k-geologic-formations','Kentucky Geological Survey 1:24,000 Geologic Formations','Kentucky Geological Survey','geologic_mapping','Kentucky','KGS ArcGIS REST MapServer / digitized 1:24,000 geologic quadrangle mapping','source-vintage dependent','state','active_reference','https://kgs.uky.edu/arcgis/rest/services/GeologicMapData/KY24KGeologicFormations_WGS84/MapServer','reviewed_reference','Compiled from 707 KGS/USGS 7.5-minute geologic quadrangle maps; mapped geology, not a site boring.'),
('kgs-24k-dominant-lithology','Kentucky Geological Survey 1:24,000 Dominant Lithology','Kentucky Geological Survey','geologic_mapping_derived_attribute','Kentucky','KGS ArcGIS REST MapServer; dominant lithology derived by KGS from mapped geologic formations','source-vintage dependent','state','active_reference','https://kgs.uky.edu/arcgis/rest/services/GeologicMapData/KY24KLitho_WGS84/MapServer','reviewed_reference','KGS-derived attribute from mapped geologic formations; not a field sample.'),
('kgs-kentucky-sinkhole-outlines','Kentucky Geological Survey Kentucky Sinkhole Outlines','Kentucky Geological Survey','mapped_sinkhole_inventory','Kentucky','KGS ArcGIS REST MapServer; closed topographic contours digitized from 7.5-minute topographic mapping','source-vintage dependent','state','active_reference','https://kgs.uky.edu/arcgis/rest/services/KYWater/KYSinkholes/MapServer','reviewed_reference','Mapped closed topographic depressions; absence is mapped absence only and does not predict future subsidence.'),
('ky-huc-8-10-12','Kentucky 8, 10 and 12 Digit Hydrologic Units','USGS / Kentucky Division of Water','watershed_boundary','Kentucky','Kentucky GIS ArcGIS REST MapServer / Watershed Boundary Dataset','periodic','federal_state','active_reference','https://kygisserver.ky.gov/arcgis/rest/services/WGS84WM_Services/Ky_8_10_12_Digit_Hydrologic_Units_WGS84WM/MapServer','reviewed_reference','Hydrologic unit boundaries for water-resource management and localized watershed studies.')
on conflict (slug) do update set
  name=excluded.name,authority=excluded.authority,source_class=excluded.source_class,
  geographic_scope=excluded.geographic_scope,acquisition_method=excluded.acquisition_method,
  update_cadence=excluded.update_cadence,authority_level=excluded.authority_level,
  status=excluded.status,homepage_url=excluded.homepage_url,notes=excluded.notes,updated_at=now();

create table if not exists farm_watch.property_land_context_v1 (
  property_id uuid primary key references farm_watch.properties(id) on delete cascade,
  status text not null default 'unknown' check (status in ('available','partial','unavailable','unknown')),
  context jsonb not null default '{}'::jsonb,
  retrieved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table farm_watch.property_land_context_v1 enable row level security;
revoke all on farm_watch.property_land_context_v1 from public,anon,authenticated;
grant select,insert,update,delete on farm_watch.property_land_context_v1 to service_role;

create or replace function farm_watch.farm_watch_get_land_anchor_v1_internal(p_slug text)
returns jsonb language sql security definer set search_path=pg_catalog,farm_watch,extensions as $$
with p as (
  select id,stated_acres,boundary,coalesce(center,extensions.st_pointonsurface(boundary)) pt
  from farm_watch.properties where slug=p_slug limit 1
)
select jsonb_build_object(
  'property_id',id,'stated_acres',stated_acres,
  'lat',case when pt is null then null else extensions.st_y(pt) end,
  'lon',case when pt is null then null else extensions.st_x(pt) end,
  'boundary_geojson',case when boundary is null then null else extensions.st_asgeojson(boundary)::jsonb end
) from p;
$$;

create or replace function farm_watch.farm_watch_compute_land_context_v1_internal(
  p_slug text,p_geology jsonb,p_huc jsonb,p_sinkholes jsonb
) returns jsonb
language sql security definer set search_path=pg_catalog,farm_watch,extensions as $$
with p as (
  select boundary,extensions.st_area(boundary::geography)/4046.8564224 parcel_acres
  from farm_watch.properties where slug=p_slug limit 1
),
g as (
  select f->'properties' props,
    extensions.st_makevalid(extensions.st_setsrid(extensions.st_geomfromgeojson((f->'geometry')::text),4326)) geom
  from jsonb_array_elements(coalesce(p_geology->'features','[]'::jsonb)) f
  where f->'geometry' is not null
),
g_clip as (
  select g.props,extensions.st_intersection(g.geom,p.boundary) clipped,p.parcel_acres
  from g cross join p where extensions.st_intersects(g.geom,p.boundary)
),
g_rows as (
  select jsonb_build_object(
    'map_symbol',props->>'map_symbol','formation_code',props->>'formation_code',
    'formation_name',props->>'formation_name','dominant_lithology',props->>'dominant_lithology',
    'maximum_age',props->>'maximum_age','minimum_age',props->>'minimum_age',
    'quadrangle_name',props->>'quadrangle_name','description',props->>'description',
    'source_name',props->>'source_name','source_uri',props->>'source_uri',
    'intersection_acres',round((extensions.st_area(clipped::geography)/4046.8564224)::numeric,3),
    'parcel_percent',round(((extensions.st_area(clipped::geography)/4046.8564224)/nullif(parcel_acres,0)*100)::numeric,1)
  ) obj, extensions.st_area(clipped::geography) area_m2
  from g_clip where not extensions.st_isempty(clipped)
),
h as (
  select f->'properties' props,
    extensions.st_makevalid(extensions.st_setsrid(extensions.st_geomfromgeojson((f->'geometry')::text),4326)) geom
  from jsonb_array_elements(coalesce(p_huc->'features','[]'::jsonb)) f
  where f->'geometry' is not null
),
h_clip as (
  select h.props,extensions.st_intersection(h.geom,p.boundary) clipped,p.parcel_acres
  from h cross join p where extensions.st_intersects(h.geom,p.boundary)
),
h_rows as (
  select jsonb_build_object(
    'huc12',props->>'huc12','name',props->>'name','hu_type',props->>'hu_type',
    'hu_mod',props->>'hu_mod','to_huc',props->>'to_huc',
    'watershed_area_acres',nullif(props->>'area_acres','')::numeric,
    'intersection_acres',round((extensions.st_area(clipped::geography)/4046.8564224)::numeric,3),
    'parcel_percent',round(((extensions.st_area(clipped::geography)/4046.8564224)/nullif(parcel_acres,0)*100)::numeric,1)
  ) obj, extensions.st_area(clipped::geography) area_m2
  from h_clip where not extensions.st_isempty(clipped)
),
s as (
  select f->'properties' props,
    extensions.st_makevalid(extensions.st_setsrid(extensions.st_geomfromgeojson((f->'geometry')::text),4326)) geom
  from jsonb_array_elements(coalesce(p_sinkholes->'features','[]'::jsonb)) f
  where f->'geometry' is not null
),
s_rows as (
  select jsonb_build_object(
    'objectid',props->>'objectid','county_name',props->>'county_name',
    'quadrangle_name',props->>'quadrangle_name',
    'mapped_acres',nullif(props->>'mapped_acres','')::numeric,
    'intersects_property',extensions.st_intersects(s.geom,p.boundary),
    'distance_m',round(extensions.st_distance(s.geom::geography,p.boundary::geography)::numeric,1)
  ) obj,
  extensions.st_distance(s.geom::geography,p.boundary::geography) distance_m
  from s cross join p
)
select jsonb_build_object(
  'parcel_geodesic_acres',(select round(parcel_acres::numeric,3) from p),
  'geology',jsonb_build_object(
    'mapped_units',(select coalesce(jsonb_agg(obj order by area_m2 desc),'[]'::jsonb) from g_rows),
    'mapped_coverage_acres',(select round(coalesce(sum(area_m2),0)::numeric/4046.8564224,3) from g_rows)
  ),
  'watershed',jsonb_build_object(
    'huc12_units',(select coalesce(jsonb_agg(obj order by area_m2 desc),'[]'::jsonb) from h_rows),
    'mapped_coverage_acres',(select round(coalesce(sum(area_m2),0)::numeric/4046.8564224,3) from h_rows)
  ),
  'sinkholes',jsonb_build_object(
    'intersecting_count',(select count(*) from s_rows where coalesce((obj->>'intersects_property')::boolean,false)),
    'nearest',(select obj from s_rows order by distance_m nulls last limit 1)
  )
);
$$;

create or replace function farm_watch.farm_watch_get_land_context_v1_internal(p_slug text)
returns jsonb language sql security definer set search_path=pg_catalog,farm_watch as $$
select jsonb_build_object('status',c.status,'context',c.context,'retrieved_at',c.retrieved_at)
from farm_watch.property_land_context_v1 c
join farm_watch.properties p on p.id=c.property_id
where p.slug=p_slug limit 1;
$$;

create or replace function farm_watch.farm_watch_upsert_land_context_v1_internal(
  p_slug text,p_status text,p_context jsonb,p_retrieved_at timestamptz default now()
) returns void
language plpgsql security definer set search_path=pg_catalog,farm_watch as $$
declare v_property_id uuid;
begin
  if p_status not in ('available','partial','unavailable','unknown') then raise exception 'invalid land context status'; end if;
  select id into v_property_id from farm_watch.properties where slug=p_slug limit 1;
  if v_property_id is null then raise exception 'property not found'; end if;
  insert into farm_watch.property_land_context_v1(property_id,status,context,retrieved_at)
  values(v_property_id,p_status,coalesce(p_context,'{}'::jsonb),coalesce(p_retrieved_at,now()))
  on conflict(property_id) do update set
    status=excluded.status,context=excluded.context,retrieved_at=excluded.retrieved_at,updated_at=now();
end;
$$;

revoke all on function farm_watch.farm_watch_get_land_anchor_v1_internal(text) from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_compute_land_context_v1_internal(text,jsonb,jsonb,jsonb) from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_get_land_context_v1_internal(text) from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_upsert_land_context_v1_internal(text,text,jsonb,timestamptz) from public,anon,authenticated;
grant execute on function farm_watch.farm_watch_get_land_anchor_v1_internal(text) to service_role;
grant execute on function farm_watch.farm_watch_compute_land_context_v1_internal(text,jsonb,jsonb,jsonb) to service_role;
grant execute on function farm_watch.farm_watch_get_land_context_v1_internal(text) to service_role;
grant execute on function farm_watch.farm_watch_upsert_land_context_v1_internal(text,text,jsonb,timestamptz) to service_role;

create or replace function public.farm_watch_get_land_anchor_v1_internal(p_slug text)
returns jsonb language sql security definer set search_path=pg_catalog
as $$ select farm_watch.farm_watch_get_land_anchor_v1_internal(p_slug); $$;
create or replace function public.farm_watch_compute_land_context_v1_internal(
  p_slug text,p_geology jsonb,p_huc jsonb,p_sinkholes jsonb
) returns jsonb language sql security definer set search_path=pg_catalog
as $$ select farm_watch.farm_watch_compute_land_context_v1_internal(p_slug,p_geology,p_huc,p_sinkholes); $$;
create or replace function public.farm_watch_get_land_context_v1_internal(p_slug text)
returns jsonb language sql security definer set search_path=pg_catalog
as $$ select farm_watch.farm_watch_get_land_context_v1_internal(p_slug); $$;
create or replace function public.farm_watch_upsert_land_context_v1_internal(
  p_slug text,p_status text,p_context jsonb,p_retrieved_at timestamptz default now()
) returns void language sql security definer set search_path=pg_catalog
as $$ select farm_watch.farm_watch_upsert_land_context_v1_internal(p_slug,p_status,p_context,p_retrieved_at); $$;

revoke all on function public.farm_watch_get_land_anchor_v1_internal(text) from public,anon,authenticated;
revoke all on function public.farm_watch_compute_land_context_v1_internal(text,jsonb,jsonb,jsonb) from public,anon,authenticated;
revoke all on function public.farm_watch_get_land_context_v1_internal(text) from public,anon,authenticated;
revoke all on function public.farm_watch_upsert_land_context_v1_internal(text,text,jsonb,timestamptz) from public,anon,authenticated;
grant execute on function public.farm_watch_get_land_anchor_v1_internal(text) to service_role;
grant execute on function public.farm_watch_compute_land_context_v1_internal(text,jsonb,jsonb,jsonb) to service_role;
grant execute on function public.farm_watch_get_land_context_v1_internal(text) to service_role;
grant execute on function public.farm_watch_upsert_land_context_v1_internal(text,text,jsonb,timestamptz) to service_role;
