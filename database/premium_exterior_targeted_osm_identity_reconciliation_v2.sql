-- Scout by Cadastory
-- Premium exterior targeted OSM building identity reconciliation v2
--
-- Purpose
--   Repair facility/POI -> physical-building identity without relaxing distance
--   into an identity rule. OSM building polygons enter the canonical footprint
--   layer only through bounded, corroborated identity lanes.
--
-- Guardrails
--   * Facility/POI proximity alone is never building identity.
--   * Targeted OSM canonical rows contribute geometry/footprint and explicit
--     address only. Height, stories, facade, glazing, condition and service need
--     remain unknown unless independently resolved by another trusted source.
--   * Generic and multi-building/site-level targets are excluded from automatic
--     reconciliation.
--   * All canonical rows are backed by ingest.raw_records provenance.

insert into ingest.sources(
  slug,name,authority,source_class,geographic_scope,acquisition_method,update_cadence,
  authority_level,status,homepage_url,license_notes,commercial_use_status,notes,updated_at
) values (
  'openstreetmap-targeted-building-identity',
  'OpenStreetMap Targeted Building Identity Footprints',
  'OpenStreetMap contributors / Geofabrik GmbH',
  'building_identity_footprint',
  'Scout unresolved premium-exterior target neighborhoods in the Louisville pilot region',
  'Targeted Geofabrik regional .osm.pbf extraction around unresolved OSM node POIs; only strongly corroborated building polygons are materialized canonically',
  'on_demand_identity_repair',
  'community_primary',
  'active',
  'https://download.geofabrik.de/north-america/us.html',
  'OpenStreetMap data under ODbL 1.0; attribution required: © OpenStreetMap contributors. Geofabrik regional extracts are the distribution mechanism.',
  'allowed_with_attribution',
  'Narrow identity-repair source only. It does not import OSM height, levels, material, condition, maintenance need or other physical claims.',
  now()
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

-- decisioning.building_candidates is a derived view over ingest.raw_records.
-- Admit the targeted OSM identity-repair source without making the view writable.
create or replace view decisioning.building_candidates as
with base as (
  select
    r.id as source_record_id,
    s.slug as source_slug,
    r.source_native_id,
    r.parse_status,
    r.location,
    r.geometry,
    r.observed_at,
    r.raw_payload,
    r.raw_payload -> 'properties' as p
  from ingest.raw_records r
  join ingest.sources s on s.id=r.source_id
  where s.slug in (
    'ky-ornl-building-footprints',
    'in-state-building-footprints',
    'openstreetmap-targeted-building-identity'
  )
    and r.within_pilot_radius is true
), normalized as (
  select
    base.source_record_id,
    base.source_slug,
    base.source_native_id,
    base.parse_status,
    base.location,
    base.geometry,
    base.p,
    case
      when base.source_slug='ky-ornl-building-footprints' then nullif(base.p->>'SQFEET','')::double precision
      when base.source_slug='in-state-building-footprints' then nullif(base.p->>'SHAPE__Area','')::double precision * 10.76391041671
      when base.source_slug='openstreetmap-targeted-building-identity' and base.geometry is not null then extensions.st_area(base.geometry::extensions.geography) * 10.76391041671
      else null::double precision
    end as footprint_sqft,
    case
      when base.source_slug='ky-ornl-building-footprints' then nullif(base.p->>'HEIGHT','')::double precision
      else null::double precision
    end as height_m,
    case
      when base.source_slug in ('ky-ornl-building-footprints','openstreetmap-targeted-building-identity') then nullif(base.p->>'PROP_ADDR','')
      else null::text
    end as property_address,
    case
      when base.source_slug in ('ky-ornl-building-footprints','openstreetmap-targeted-building-identity') then nullif(base.p->>'PROP_CITY','')
      else null::text
    end as property_city,
    case
      when base.source_slug='ky-ornl-building-footprints' then coalesce(nullif(base.p->>'PROP_ST',''),'KY')
      when base.source_slug='in-state-building-footprints' then 'IN'::text
      when base.source_slug='openstreetmap-targeted-building-identity' then nullif(base.p->>'PROP_ST','')
      else null::text
    end as state_code,
    case
      when base.source_slug in ('ky-ornl-building-footprints','openstreetmap-targeted-building-identity') then nullif(base.p->>'PROP_ZIP','')
      else null::text
    end as postal_code,
    case
      when base.source_slug='in-state-building-footprints' then nullif(base.p->>'county','')
      else null::text
    end as county_name,
    case
      when base.source_slug='ky-ornl-building-footprints' and coalesce(base.p->>'IMAGE_DATE','') ~ '^[0-9]+$' then to_timestamp(((base.p->>'IMAGE_DATE')::double precision)/1000.0)::date
      when base.source_slug='in-state-building-footprints' and coalesce(base.p->>'lidaryear','') ~ '^[0-9]{4}$' then make_date((base.p->>'lidaryear')::integer,1,1)
      when base.source_slug='openstreetmap-targeted-building-identity' then base.observed_at::date
      else null::date
    end as source_vintage_date
  from base
)
select
  source_record_id,source_slug,source_native_id,parse_status,location,geometry,
  footprint_sqft,height_m,property_address,property_city,state_code,postal_code,
  county_name,source_vintage_date,
  case
    when footprint_sqft>=50000 or height_m>=20 then 'A'
    when footprint_sqft>=20000 or height_m>=12 then 'B'
    else 'C'
  end as relevance_tier,
  case
    when height_m>=20 then 'tall_structure'
    when footprint_sqft>=50000 then 'very_large_footprint'
    when height_m>=12 then 'height_signal'
    when footprint_sqft>=20000 then 'large_footprint'
    when source_slug='openstreetmap-targeted-building-identity' then 'targeted_identity_repair'
    else 'minimum_discovery_scale'
  end as relevance_reason
from normalized;

comment on view decisioning.building_candidates is
'Canonical building candidate projection from raw ingested footprint records. Includes KY ORNL, Indiana state footprints, and narrowly materialized targeted OSM identity-repair footprints. Targeted OSM rows contribute geometry/footprint and explicit address only; height remains unknown.';

create or replace function intelligence.promote_premium_exterior_local_osm_identity_v1(
  p_target_id uuid,
  p_osm_building_iri text
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions, intelligence, decisioning, ingest
as $$
declare
  v_c intelligence.premium_exterior_osm_identity_candidates%rowtype;
  v_t intelligence.premium_exterior_targets%rowtype;
  v_bc decisioning.building_candidates%rowtype;
  v_edge_distance_m double precision;
  v_source_slug text;
  v_target_name_norm text;
  v_exact_address_building_count integer:=0;
  v_name_identity_lane boolean:=false;
  v_address_identity_lane boolean:=false;
  v_identity_basis text;
begin
  select * into v_c
  from intelligence.premium_exterior_osm_identity_candidates
  where target_id=p_target_id and osm_building_iri=p_osm_building_iri
  for update;
  if not found then raise exception 'OSM identity candidate not found'; end if;
  if v_c.status<>'candidate' then raise exception 'OSM identity candidate is not promotable from status %',v_c.status; end if;

  select * into v_t from intelligence.premium_exterior_targets where id=p_target_id for update;
  if not found then raise exception 'premium exterior target not found: %',p_target_id; end if;

  v_target_name_norm:=intelligence.normalize_identity_text_v1(v_t.name);
  if v_target_name_norm ~ '^(church|chapel|hotel|motel|museum|stadium)$'
     or v_target_name_norm ~ '(camp|campus|retreat|seminary|university|stadium|complex|medical center)' then
    raise exception 'target name is too generic or site-level for automatic building promotion: %',v_t.name;
  end if;
  if v_t.target_class in ('university','sports_venue','amusement_park','convention_event_center','hospital') then
    raise exception 'multi-building/site-level target class requires manual or stronger building-specific reconciliation: %',v_t.target_class;
  end if;

  if v_t.location is not null and coalesce(v_c.addr_housenumber,'')<>'' and coalesce(v_c.addr_street,'')<>'' then
    select count(*) into v_exact_address_building_count
    from intelligence.osm_building_identity_features f2
    where lower(coalesce(f2.addr_housenumber,''))=lower(v_c.addr_housenumber)
      and intelligence.normalize_identity_text_v1(f2.addr_street)=intelligence.normalize_identity_text_v1(v_c.addr_street)
      and extensions.st_dwithin(v_t.location::extensions.geography,f2.geometry::extensions.geography,200);
  end if;

  v_name_identity_lane :=
    coalesce(v_c.name_similarity,0)>=0.95
    and v_c.corroboration_basis in ('strong_name_match','exact_house_and_street')
    and coalesce(v_c.class_compatible,false);

  v_address_identity_lane :=
    coalesce(v_c.address_match,false)
    and coalesce(v_c.distance_m,1000000000)<=10
    and v_exact_address_building_count=1
    and coalesce(v_c.addr_housenumber,'')<>''
    and coalesce(v_c.addr_street,'')<>'';

  if v_c.canonical_building_source_record_id is null
     or coalesce(v_c.confidence,0)<0.93
     or not (v_name_identity_lane or v_address_identity_lane)
     or coalesce(v_c.canonical_overlap_ratio,0)<0.80
     or coalesce(v_c.canonical_uniqueness_margin,0)<0.80 then
    raise exception 'OSM identity candidate does not satisfy deterministic promotion thresholds';
  end if;

  if v_t.building_source_record_id is not null and v_t.building_source_record_id<>v_c.canonical_building_source_record_id then
    raise exception 'target already has a different building identity: %',v_t.building_source_record_id;
  end if;

  select * into v_bc from decisioning.building_candidates where source_record_id=v_c.canonical_building_source_record_id;
  if not found or v_bc.geometry is null then raise exception 'canonical building candidate missing geometry: %',v_c.canonical_building_source_record_id; end if;

  if v_t.location is not null then
    v_edge_distance_m:=extensions.st_distance(v_t.location::extensions.geography,v_bc.geometry::extensions.geography);
  end if;
  v_source_slug:=v_bc.source_slug;
  v_identity_basis:=case when v_address_identity_lane and not v_name_identity_lane
    then 'local_osm_unique_exact_address_containment_plus_unique_canonical_overlap_v1'
    else 'local_osm_exact_name_plus_unique_canonical_overlap_v1' end;

  update intelligence.premium_exterior_targets
  set building_source_record_id=v_bc.source_record_id,
      building_source_slug=v_source_slug,
      footprint_sqft=v_bc.footprint_sqft,
      mapped_height_m=v_bc.height_m,
      property_address=v_bc.property_address,
      property_city=v_bc.property_city,
      state_code=coalesce(state_code,v_bc.state_code),
      postal_code=v_bc.postal_code,
      building_match_distance_m=v_edge_distance_m,
      evidence=coalesce(evidence,'{}'::jsonb)||jsonb_strip_nulls(jsonb_build_object(
        'building_identity_status','verified_reconciled',
        'building_identity_verified_at',now(),
        'building_identity_basis',v_identity_basis,
        'building_identity_osm_building_iri',v_c.osm_building_iri,
        'building_identity_osm_building_name',v_c.building_name,
        'building_identity_canonical_overlap_ratio',round(v_c.canonical_overlap_ratio,3),
        'building_identity_canonical_uniqueness_margin',round(v_c.canonical_uniqueness_margin,3),
        'building_identity_name_similarity',round(v_c.name_similarity,3),
        'building_identity_address_match',v_c.address_match,
        'building_identity_exact_address_buildings_within_200m',v_exact_address_building_count,
        'building_identity_confidence',v_c.confidence,
        'building_identity_edge_distance_m',case when v_edge_distance_m is null then null else round(v_edge_distance_m::numeric,2) end,
        'building_identity_guardrail','Promoted only after strong OSM identity corroboration plus a unique canonical footprint; generic and multi-building/site-level targets are excluded.'
      )),updated_at=now()
  where id=p_target_id;

  insert into intelligence.premium_exterior_building_link_candidates(
    target_id,candidate_building_source_record_id,candidate_building_source_slug,source_slug,
    prior_centroid_distance_m,footprint_edge_distance_m,point_inside_footprint,match_basis,status,confidence,evidence,first_observed_at,last_observed_at
  ) values (
    p_target_id,v_bc.source_record_id,v_source_slug,'openstreetmap-premium-exterior-facilities',
    v_edge_distance_m,v_edge_distance_m,case when v_t.location is null then false else extensions.st_covers(v_bc.geometry,v_t.location::extensions.geometry) end,
    v_identity_basis,'verified',v_c.confidence,
    jsonb_build_object('osm_building_iri',v_c.osm_building_iri,'osm_building_name',v_c.building_name,'canonical_overlap_ratio',v_c.canonical_overlap_ratio,
      'canonical_uniqueness_margin',v_c.canonical_uniqueness_margin,'name_similarity',v_c.name_similarity,'address_match',v_c.address_match,
      'exact_address_buildings_within_200m',v_exact_address_building_count,'promoted_at',now(),'verification_basis',v_identity_basis),now(),now()
  ) on conflict(target_id,candidate_building_source_record_id) do update set
    candidate_building_source_slug=excluded.candidate_building_source_slug,source_slug=excluded.source_slug,
    footprint_edge_distance_m=excluded.footprint_edge_distance_m,point_inside_footprint=excluded.point_inside_footprint,
    match_basis=excluded.match_basis,status='verified',confidence=excluded.confidence,
    evidence=coalesce(intelligence.premium_exterior_building_link_candidates.evidence,'{}'::jsonb)||excluded.evidence,last_observed_at=now();

  update intelligence.premium_exterior_osm_identity_candidates
  set status='reconciled',evidence=coalesce(evidence,'{}'::jsonb)||jsonb_build_object('promoted_at',now(),'promotion_basis',v_identity_basis),last_observed_at=now()
  where target_id=p_target_id and osm_building_iri=p_osm_building_iri;

  update intelligence.premium_exterior_osm_identity_candidates
  set status='superseded',evidence=coalesce(evidence,'{}'::jsonb)||jsonb_build_object('superseded_at',now(),'superseded_by_osm_building_iri',p_osm_building_iri),last_observed_at=now()
  where target_id=p_target_id and osm_building_iri<>p_osm_building_iri and status='candidate';

  return jsonb_build_object('target_id',p_target_id,'osm_building_iri',p_osm_building_iri,'canonical_building_source_record_id',v_bc.source_record_id,
    'canonical_overlap_ratio',v_c.canonical_overlap_ratio,'name_similarity',v_c.name_similarity,'address_match',v_c.address_match,
    'confidence',v_c.confidence,'building_identity_status','verified_reconciled','building_identity_basis',v_identity_basis);
end;
$$;

create or replace function intelligence.materialize_premium_exterior_targeted_osm_canonical_v1(
  p_target_id uuid,
  p_osm_building_iri text
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions, intelligence, decisioning, ingest
as $$
declare
  v_c intelligence.premium_exterior_osm_identity_candidates%rowtype;
  v_t intelligence.premium_exterior_targets%rowtype;
  v_f intelligence.osm_building_identity_features%rowtype;
  v_source_id uuid; v_raw_id uuid; v_hash text; v_target_name_norm text; v_address text; v_result jsonb;
  v_materialization_basis text; v_exact_named_building_count integer:=0; v_exact_address_building_count integer:=0;
  v_unique_named_worship_lane boolean:=false; v_unique_address_containment_lane boolean:=false;
begin
  select * into v_c from intelligence.premium_exterior_osm_identity_candidates where target_id=p_target_id and osm_building_iri=p_osm_building_iri for update;
  if not found then raise exception 'OSM identity candidate not found'; end if;
  select * into v_t from intelligence.premium_exterior_targets where id=p_target_id for update;
  if not found then raise exception 'premium exterior target not found'; end if;
  select * into v_f from intelligence.osm_building_identity_features where osm_iri=p_osm_building_iri;
  if not found or v_f.geometry is null then raise exception 'OSM building feature missing geometry'; end if;

  v_target_name_norm:=intelligence.normalize_identity_text_v1(v_t.name);
  if v_t.location is not null and v_target_name_norm<>'' then
    select count(*) into v_exact_named_building_count from intelligence.osm_building_identity_features f2
    where f2.name is not null and intelligence.normalize_identity_text_v1(f2.name)=v_target_name_norm
      and extensions.st_dwithin(v_t.location::extensions.geography,f2.geometry::extensions.geography,400);
  end if;
  if v_t.location is not null and coalesce(v_c.addr_housenumber,'')<>'' and coalesce(v_c.addr_street,'')<>'' then
    select count(*) into v_exact_address_building_count from intelligence.osm_building_identity_features f2
    where lower(coalesce(f2.addr_housenumber,''))=lower(v_c.addr_housenumber)
      and intelligence.normalize_identity_text_v1(f2.addr_street)=intelligence.normalize_identity_text_v1(v_c.addr_street)
      and extensions.st_dwithin(v_t.location::extensions.geography,f2.geometry::extensions.geography,200);
  end if;

  v_unique_named_worship_lane:=v_t.target_class='religious_facility' and coalesce(v_c.name_similarity,0)>=0.99 and coalesce(v_c.class_compatible,false)
    and coalesce(v_c.distance_m,1000000000)<=100 and v_exact_named_building_count=1
    and (coalesce(v_f.amenity_tag,'')='place_of_worship' or coalesce(v_f.building_tag,'') in('church','chapel','religious'));
  v_unique_address_containment_lane:=coalesce(v_c.address_match,false) and coalesce(v_c.distance_m,1000000000)<=10
    and v_exact_address_building_count=1 and v_t.location is not null and extensions.st_covers(v_f.geometry,v_t.location::extensions.geometry);

  if v_c.status<>'candidate'
     or not (
       (coalesce(v_c.name_similarity,0)>=0.95 and coalesce(v_c.class_compatible,false) and coalesce(v_c.distance_m,1000000000)<=10)
       or (coalesce(v_c.name_similarity,0)>=0.95 and coalesce(v_c.class_compatible,false) and coalesce(v_c.address_match,false) and coalesce(v_c.distance_m,1000000000)<=25)
       or v_unique_named_worship_lane
       or v_unique_address_containment_lane
     )
     or v_t.target_class not in('religious_facility','dealership_showroom','hotel','museum_performing_arts')
     or v_target_name_norm ~ '^(church|chapel|hotel|motel|museum|stadium)$'
     or v_target_name_norm ~ '(camp|campus|retreat|seminary|university|stadium|complex|medical center)' then
    raise exception 'candidate does not satisfy targeted OSM canonical materialization thresholds';
  end if;

  if not v_unique_address_containment_lane then
    if coalesce(intelligence.normalize_identity_text_v1(v_f.name),'')='' or extensions.similarity(v_target_name_norm,intelligence.normalize_identity_text_v1(v_f.name))<0.95 then
      raise exception 'current OSM feature name no longer corroborates target';
    end if;
  end if;

  v_materialization_basis:=case
    when v_unique_address_containment_lane and coalesce(v_c.name_similarity,0)<0.95 then 'unique_exact_address_point_inside_building_v1'
    when coalesce(v_c.distance_m,1000000000)<=10 then 'near_exact_target_building_name_plus_target_point_within_10m_v1'
    when coalesce(v_c.address_match,false) and coalesce(v_c.distance_m,1000000000)<=25 then 'near_exact_target_building_name_plus_exact_address_within_25m_v1'
    when v_unique_named_worship_lane then 'unique_exact_named_worship_building_within_100m_v1'
    when v_unique_address_containment_lane then 'unique_exact_address_point_inside_building_v1'
    else null end;
  if v_materialization_basis is null then raise exception 'no approved targeted OSM materialization basis'; end if;

  select id into v_source_id from ingest.sources where slug='openstreetmap-targeted-building-identity';
  if v_source_id is null then raise exception 'targeted OSM canonical source is not registered'; end if;
  v_hash:=md5(v_f.osm_iri||'|'||coalesce(v_f.source_timestamp::text,'')||'|'||coalesce(v_f.raw_tags::text,''));
  v_address:=nullif(concat_ws(' ',nullif(v_f.addr_housenumber,''),nullif(v_f.addr_street,'')),'');

  insert into ingest.raw_records(source_id,source_native_id,source_url,retrieved_at,observed_at,content_hash,parser_version,parse_status,provisional_entity_type,location,within_pilot_radius,raw_payload,geometry)
  values(v_source_id,v_f.osm_iri,v_f.osm_iri,now(),v_f.source_timestamp,v_hash,'targeted-osm-building-identity-v1','parsed','building',extensions.st_pointonsurface(v_f.geometry),true,
    jsonb_build_object('properties',jsonb_strip_nulls(jsonb_build_object('PROP_ADDR',v_address,'PROP_CITY',v_f.addr_city,'PROP_ST',v_t.state_code,'PROP_ZIP',v_f.addr_postcode,'OSM_NAME',v_f.name,'OSM_BUILDING',v_f.building_tag)),
      'osm_iri',v_f.osm_iri,'osm_type',v_f.osm_type,'osm_id',v_f.osm_id,'region_slug',v_f.region_slug,'source_timestamp',v_f.source_timestamp,'raw_tags',v_f.raw_tags,
      'materialization_basis',v_materialization_basis,'exact_named_buildings_within_400m',v_exact_named_building_count,'exact_address_buildings_within_200m',v_exact_address_building_count,
      'materialized_for_target_id',p_target_id,'guardrail','This raw record establishes the OSM building footprint identity only; no OSM height/material/condition claims are promoted here.'),v_f.geometry)
  on conflict(source_id,source_native_id,content_hash) do update set retrieved_at=excluded.retrieved_at returning id into v_raw_id;

  if not exists(select 1 from decisioning.building_candidates where source_record_id=v_raw_id) then raise exception 'targeted OSM raw record did not materialize into canonical building_candidates view: %',v_raw_id; end if;

  update intelligence.premium_exterior_osm_identity_candidates
  set canonical_building_source_record_id=v_raw_id,canonical_overlap_ratio=1,canonical_edge_distance_m=0,canonical_second_overlap_ratio=0,canonical_uniqueness_margin=1,
      confidence=greatest(confidence,0.97),evidence=coalesce(evidence,'{}'::jsonb)||jsonb_build_object('targeted_osm_canonical_materialized_at',now(),
        'targeted_osm_canonical_source_record_id',v_raw_id,'targeted_osm_canonical_basis',v_materialization_basis,'exact_named_buildings_within_400m',v_exact_named_building_count,
        'exact_address_buildings_within_200m',v_exact_address_building_count),last_observed_at=now()
  where target_id=p_target_id and osm_building_iri=p_osm_building_iri;

  v_result:=intelligence.promote_premium_exterior_local_osm_identity_v1(p_target_id,p_osm_building_iri);
  return v_result||jsonb_build_object('canonical_materialization_source','openstreetmap-targeted-building-identity','canonical_materialization_basis',v_materialization_basis,
    'exact_named_buildings_within_400m',v_exact_named_building_count,'exact_address_buildings_within_200m',v_exact_address_building_count);
end;
$$;

revoke all on function intelligence.promote_premium_exterior_local_osm_identity_v1(uuid,text) from public, anon, authenticated;
grant execute on function intelligence.promote_premium_exterior_local_osm_identity_v1(uuid,text) to service_role;
revoke all on function intelligence.materialize_premium_exterior_targeted_osm_canonical_v1(uuid,text) from public, anon, authenticated;
grant execute on function intelligence.materialize_premium_exterior_targeted_osm_canonical_v1(uuid,text) to service_role;

comment on function intelligence.promote_premium_exterior_local_osm_identity_v1(uuid,text) is
'Promotes one local OSM identity candidate only after a unique canonical footprint and either strong named-facility corroboration or unique exact-address containment. Generic and multi-building/site-level targets are rejected.';
comment on function intelligence.materialize_premium_exterior_targeted_osm_canonical_v1(uuid,text) is
'Materializes strongly corroborated OSM building identity using bounded lanes: near-exact name <=10m; near-exact name+exact address <=25m; unique exact-named worship building <=100m; or a unique exact-address building containing the target point. Only geometry/footprint and explicit address enter the canonical source.';

-- Review surface: only unresolved candidate rows can be auto-ready. Reconciled rows
-- remain visible for audit but never re-enter the queue.
create or replace view intelligence.v_premium_exterior_local_osm_reconciliation_review_v1 as
with base as (
  select c.*,
         t.name as target_name,
         t.address_text as target_address,
         t.target_class,
         t.target_subclass,
         intelligence.normalize_identity_text_v1(t.name) as target_name_norm,
         row_number() over (partition by c.target_id order by coalesce(c.confidence,0) desc,coalesce(c.canonical_overlap_ratio,0) desc,coalesce(c.distance_m,1000000000),c.osm_building_iri) as candidate_rank,
         lead(c.confidence) over (partition by c.target_id order by coalesce(c.confidence,0) desc,coalesce(c.canonical_overlap_ratio,0) desc,coalesce(c.distance_m,1000000000),c.osm_building_iri) as next_confidence
  from intelligence.premium_exterior_osm_identity_candidates c
  join intelligence.premium_exterior_targets t on t.id=c.target_id
  where c.status in ('candidate','reconciled')
    and coalesce(c.evidence->>'resolver','')='local_geofabrik_osm_building_identity_v1'
)
select
  target_id,osm_building_iri,osm_geometry,distance_m,building_tag,building_name,operator_name,brand_name,amenity_tag,
  addr_housenumber,addr_street,addr_city,addr_postcode,canonical_building_source_record_id,canonical_overlap_ratio,
  canonical_edge_distance_m,status,confidence,evidence,first_observed_at,last_observed_at,name_similarity,address_match,
  operator_similarity,class_compatible,canonical_second_overlap_ratio,canonical_uniqueness_margin,corroboration_basis,
  target_name,target_address,target_class,target_subclass,target_name_norm,candidate_rank,next_confidence,
  (
    status='candidate'
    and target_class in ('religious_facility','dealership_showroom','hotel','museum_performing_arts')
    and coalesce(target_name_norm,'') !~ '^(church|chapel|hotel|motel|museum|stadium)$'
    and coalesce(target_name_norm,'') !~ '(camp|campus|retreat|seminary|university|stadium|complex|medical center)'
    and canonical_building_source_record_id is not null
    and coalesce(canonical_overlap_ratio,0)>=0.80
    and coalesce(canonical_uniqueness_margin,0)>=0.80
    and coalesce(confidence,0)>=0.93
    and coalesce(name_similarity,0)>=0.95
    and corroboration_basis in ('strong_name_match','exact_house_and_street')
    and coalesce(class_compatible,false)
    and coalesce(distance_m,1000000000)<=200
    and candidate_rank=1
    and (next_confidence is null or coalesce(confidence,0)-coalesce(next_confidence,0)>=0.15)
  ) as auto_reconcile_ready
from base;

comment on view intelligence.v_premium_exterior_local_osm_reconciliation_review_v1 is
'Review surface for local Geofabrik OSM building identity candidates. Reconciled rows remain auditable but never report auto_reconcile_ready.';
