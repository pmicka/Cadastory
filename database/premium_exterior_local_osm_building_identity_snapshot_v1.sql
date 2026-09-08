-- Premium exterior local OSM building identity snapshot v1
--
-- Final architecture after rejecting planet-wide OSM building scans:
--   * reuse Scout's Geofabrik state PBFs developer-side
--   * extract only small neighborhoods around unresolved OSM POI nodes
--   * retain only polygonal building=* ways/relations
--   * route KY/IN from authoritative Census TIGER county geometry
--   * fail closed rather than guessing an unresolved state
--   * never treat the cache itself as verified building identity

begin;

create table if not exists intelligence.premium_exterior_osm_identity_candidates (
  target_id uuid not null references intelligence.premium_exterior_targets(id) on delete cascade,
  osm_building_iri text not null,
  osm_geometry extensions.geometry(Geometry,4326),
  distance_m numeric,
  building_tag text,
  building_name text,
  operator_name text,
  brand_name text,
  amenity_tag text,
  addr_housenumber text,
  addr_street text,
  addr_city text,
  addr_postcode text,
  canonical_building_source_record_id uuid,
  canonical_overlap_ratio numeric,
  canonical_edge_distance_m numeric,
  status text not null default 'candidate',
  confidence numeric,
  evidence jsonb not null default '{}'::jsonb,
  first_observed_at timestamptz not null default now(),
  last_observed_at timestamptz not null default now(),
  name_similarity numeric,
  address_match boolean,
  operator_similarity numeric,
  class_compatible boolean,
  canonical_second_overlap_ratio numeric,
  canonical_uniqueness_margin numeric,
  corroboration_basis text,
  primary key (target_id,osm_building_iri),
  constraint premium_exterior_osm_identity_candidates_status_chk
    check (status in ('candidate','reconciled','rejected','superseded'))
);

create index if not exists premium_exterior_osm_identity_candidates_status_idx
  on intelligence.premium_exterior_osm_identity_candidates(status,last_observed_at desc);
create index if not exists premium_exterior_osm_identity_candidates_target_idx
  on intelligence.premium_exterior_osm_identity_candidates(target_id);
create index if not exists premium_exterior_osm_identity_candidates_geom_idx
  on intelligence.premium_exterior_osm_identity_candidates using gist(osm_geometry);

alter table intelligence.premium_exterior_osm_identity_candidates enable row level security;
revoke all on intelligence.premium_exterior_osm_identity_candidates from public,anon,authenticated;
grant select,insert,update,delete on intelligence.premium_exterior_osm_identity_candidates to service_role;

comment on table intelligence.premium_exterior_osm_identity_candidates is
  'Private evidence ledger for unresolved OSM POI node -> OSM building -> canonical building reconciliation. Proximity alone is never identity.';

create table if not exists intelligence.osm_building_identity_features (
  osm_type text not null,
  osm_id text not null,
  osm_iri text generated always as ('https://www.openstreetmap.org/'||osm_type||'/'||osm_id) stored,
  region_slug text not null references decisioning.site_access_snapshot_regions(region_slug),
  geometry extensions.geometry(Geometry,4326) not null,
  building_tag text,
  name text,
  operator_name text,
  brand_name text,
  amenity_tag text,
  addr_housenumber text,
  addr_street text,
  addr_city text,
  addr_postcode text,
  building_levels text,
  height text,
  building_material text,
  raw_tags jsonb not null default '{}'::jsonb,
  source_timestamp timestamptz,
  first_observed_at timestamptz not null default now(),
  last_observed_at timestamptz not null default now(),
  primary key (osm_type,osm_id),
  constraint osm_building_identity_features_type_chk check (osm_type in ('way','relation'))
);

create index if not exists osm_building_identity_features_geom_idx
  on intelligence.osm_building_identity_features using gist(geometry);
create index if not exists osm_building_identity_features_region_idx
  on intelligence.osm_building_identity_features(region_slug,last_observed_at desc);
create index if not exists osm_building_identity_features_name_idx
  on intelligence.osm_building_identity_features using gin (name extensions.gin_trgm_ops)
  where name is not null;

alter table intelligence.osm_building_identity_features enable row level security;
revoke all on intelligence.osm_building_identity_features from public,anon,authenticated;
grant select,insert,update,delete on intelligence.osm_building_identity_features to service_role;

comment on table intelligence.osm_building_identity_features is
  'Targeted local OSM building polygons extracted from the same Geofabrik PBFs used by Scout site-access snapshots. Intentionally scoped to unresolved premium-exterior POI neighborhoods, not a regional building mirror.';

create or replace function public.internal_get_premium_exterior_osm_building_snapshot_config()
returns jsonb
language sql
security definer
set search_path=''
as $$
with unresolved as (
  select distinct on (t.id)
    t.id as target_id,
    t.source_native_id,
    t.name as target_name,
    t.address_text as target_address,
    t.target_class,
    t.target_subclass,
    t.location
  from intelligence.premium_exterior_targets t
  join intelligence.premium_exterior_building_link_candidates q
    on q.target_id=t.id and q.status='quarantined'
  where t.source_present
    and t.location is not null
    and t.building_source_record_id is null
    and t.source_native_id like 'https://www.openstreetmap.org/node/%'
    and coalesce(t.evidence->>'source_scope','') <> 'site_area'
    and coalesce(t.evidence->>'building_identity_status','') not in ('verified_geometry','verified_documented','verified_reconciled')
  order by t.id,q.last_observed_at desc
), routed as (
  select
    u.*,
    c.state_code,
    case c.state_code when 'KY' then 'kentucky' when 'IN' then 'indiana' else null end as region_slug
  from unresolved u
  left join lateral (
    select cl.state_code
    from scout.county_lookup cl
    where extensions.st_covers(cl.geometry,u.location::extensions.geometry)
      and cl.state_code in ('KY','IN')
    order by cl.state_code,cl.geoid
    limit 1
  ) c on true
), per_region as (
  select
    r.region_slug,
    sr.state_code,
    sr.upstream_pbf_url,
    jsonb_agg(jsonb_build_object(
      'target_id',r.target_id,
      'source_native_id',r.source_native_id,
      'target_name',r.target_name,
      'target_address',r.target_address,
      'target_class',r.target_class,
      'target_subclass',r.target_subclass,
      'longitude',extensions.st_x(r.location::extensions.geometry),
      'latitude',extensions.st_y(r.location::extensions.geometry),
      'radius_m',400
    ) order by r.target_id) as targets
  from routed r
  join decisioning.site_access_snapshot_regions sr
    on sr.region_slug=r.region_slug and sr.enabled
  where r.region_slug is not null
  group by r.region_slug,sr.state_code,sr.upstream_pbf_url
), unrouted as (
  select count(*)::integer as n from routed where region_slug is null
)
select jsonb_build_object(
  'contract_version',2,
  'generated_at',now(),
  'routing_basis','Census TIGER county geometry via scout.county_lookup; unresolved states fail closed',
  'unrouted_count',(select n from unrouted),
  'regions',coalesce((
    select jsonb_agg(jsonb_build_object(
      'region_slug',region_slug,
      'state_code',state_code,
      'pbf_url',upstream_pbf_url,
      'target_count',jsonb_array_length(targets),
      'targets',targets
    ) order by region_slug)
    from per_region
  ),'[]'::jsonb)
);
$$;

revoke all on function public.internal_get_premium_exterior_osm_building_snapshot_config() from public,anon,authenticated;
grant execute on function public.internal_get_premium_exterior_osm_building_snapshot_config() to service_role;

create or replace function public.internal_upsert_premium_exterior_osm_building_batch(
  p_region_slug text,
  p_source_timestamp timestamptz,
  p_features jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_n integer:=0; v_skipped integer:=0;
begin
  if not exists(select 1 from decisioning.site_access_snapshot_regions where region_slug=p_region_slug and enabled) then
    raise exception 'unknown or disabled snapshot region %',p_region_slug;
  end if;
  with rows as (
    select
      x.osm_type,x.osm_id,x.geometry,x.tags,
      case when x.geometry is null then null else extensions.st_setsrid(extensions.st_geomfromgeojson(x.geometry::text),4326) end as geom
    from jsonb_to_recordset(coalesce(p_features,'[]'::jsonb)) x(osm_type text,osm_id text,geometry jsonb,tags jsonb)
    where x.osm_type in ('way','relation') and x.osm_id is not null
  ), valid as (
    select * from rows
    where geom is not null
      and extensions.geometrytype(geom) in ('POLYGON','MULTIPOLYGON')
      and coalesce(tags->>'building','') not in ('','no')
  ), up as (
    insert into intelligence.osm_building_identity_features(
      osm_type,osm_id,region_slug,geometry,building_tag,name,operator_name,brand_name,amenity_tag,
      addr_housenumber,addr_street,addr_city,addr_postcode,building_levels,height,building_material,
      raw_tags,source_timestamp,first_observed_at,last_observed_at
    )
    select
      osm_type,osm_id,p_region_slug,geom,tags->>'building',nullif(tags->>'name',''),nullif(tags->>'operator',''),nullif(tags->>'brand',''),nullif(tags->>'amenity',''),
      nullif(tags->>'addr:housenumber',''),nullif(tags->>'addr:street',''),nullif(tags->>'addr:city',''),nullif(tags->>'addr:postcode',''),
      nullif(tags->>'building:levels',''),nullif(tags->>'height',''),nullif(tags->>'building:material',''),
      tags,p_source_timestamp,now(),now()
    from valid
    on conflict (osm_type,osm_id) do update set
      region_slug=excluded.region_slug,
      geometry=excluded.geometry,
      building_tag=excluded.building_tag,
      name=excluded.name,
      operator_name=excluded.operator_name,
      brand_name=excluded.brand_name,
      amenity_tag=excluded.amenity_tag,
      addr_housenumber=excluded.addr_housenumber,
      addr_street=excluded.addr_street,
      addr_city=excluded.addr_city,
      addr_postcode=excluded.addr_postcode,
      building_levels=excluded.building_levels,
      height=excluded.height,
      building_material=excluded.building_material,
      raw_tags=excluded.raw_tags,
      source_timestamp=excluded.source_timestamp,
      last_observed_at=now()
    returning 1
  )
  select count(*) into v_n from up;
  v_skipped:=greatest(0,case when jsonb_typeof(coalesce(p_features,'[]'::jsonb))='array' then jsonb_array_length(coalesce(p_features,'[]'::jsonb)) else 0 end-v_n);
  return jsonb_build_object('accepted',v_n,'skipped',v_skipped,'region_slug',p_region_slug);
end;
$$;

revoke all on function public.internal_upsert_premium_exterior_osm_building_batch(text,timestamptz,jsonb) from public,anon,authenticated;
grant execute on function public.internal_upsert_premium_exterior_osm_building_batch(text,timestamptz,jsonb) to service_role;

-- The discarded planet-wide QLever resolver is deliberately not part of runtime.
update ingest.collector_routes
set enabled=false,allow_dispatch=false,updated_at=now()
where slug='resolve-premium-exterior-osm-identity';

commit;
