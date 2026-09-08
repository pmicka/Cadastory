-- Scout by Cadastory
-- Premium exterior local OSM identity resolution v3
--
-- Extends the targeted OSM building-identity repair path with:
--   * local punctuation/apostrophe/trailing-acronym name equivalence;
--   * sticky terminal statuses for rejected/superseded/reconciled evidence;
--   * a narrowly scoped generic worship geometry/class lane;
--   * explicit manual-review labeling for the remaining ambiguous local cases.
--
-- Guardrails remain unchanged:
--   * proximity alone is never building identity;
--   * site/operator affinity is not physical-building identity;
--   * targeted OSM canonical rows provide geometry/footprint and explicit address only;
--   * height, stories, facade, glazing, condition and service need remain unknown
--     unless independently resolved from a trusted source.

create or replace function intelligence.normalize_local_osm_name_variant_v1(p_text text)
returns text
language sql
immutable
strict
set search_path='pg_catalog'
as $$
  select btrim(
    regexp_replace(
      regexp_replace(
        regexp_replace(
          lower(regexp_replace(p_text, E'[[:space:]]*\\([^()]{2,12}\\)[[:space:]]*$', '', 'g')),
          '[''’]', '', 'g'
        ),
        '[^a-z0-9]+', ' ', 'g'
      ),
      '[[:space:]]+', ' ', 'g'
    )
  );
$$;

revoke all on function intelligence.normalize_local_osm_name_variant_v1(text) from public, anon, authenticated;
grant execute on function intelligence.normalize_local_osm_name_variant_v1(text) to service_role;

create or replace function intelligence.preserve_premium_exterior_osm_identity_terminal_status_v1()
returns trigger
language plpgsql
security definer
set search_path='pg_catalog','intelligence'
as $$
begin
  if old.status in ('rejected','superseded','reconciled') and new.status='candidate' then
    new.status:=old.status;
  end if;
  return new;
end;
$$;

drop trigger if exists preserve_premium_exterior_osm_identity_terminal_status_v1
  on intelligence.premium_exterior_osm_identity_candidates;
create trigger preserve_premium_exterior_osm_identity_terminal_status_v1
before update of status on intelligence.premium_exterior_osm_identity_candidates
for each row execute function intelligence.preserve_premium_exterior_osm_identity_terminal_status_v1();

create or replace function intelligence.promote_premium_exterior_local_osm_identity_v1(
  p_target_id uuid,
  p_osm_building_iri text
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','extensions','intelligence','decisioning','ingest'
as $function$
declare
  v_c intelligence.premium_exterior_osm_identity_candidates%rowtype;
  v_t intelligence.premium_exterior_targets%rowtype;
  v_bc decisioning.building_candidates%rowtype;
  v_edge_distance_m double precision;
  v_source_slug text;
  v_target_name_norm text;
  v_target_name_variant text;
  v_building_name_variant text;
  v_exact_address_building_count integer:=0;
  v_variant_named_building_count integer:=0;
  v_compatible_worship_building_count integer:=0;
  v_name_identity_lane boolean:=false;
  v_name_variant_identity_lane boolean:=false;
  v_address_identity_lane boolean:=false;
  v_generic_worship_geometry_lane boolean:=false;
  v_identity_basis text;
begin
  select * into v_c
  from intelligence.premium_exterior_osm_identity_candidates
  where target_id=p_target_id and osm_building_iri=p_osm_building_iri
  for update;
  if not found then raise exception 'OSM identity candidate not found'; end if;
  if v_c.status<>'candidate' then
    raise exception 'OSM identity candidate is not promotable from status %',v_c.status;
  end if;

  select * into v_t
  from intelligence.premium_exterior_targets
  where id=p_target_id
  for update;
  if not found then raise exception 'premium exterior target not found: %',p_target_id; end if;

  v_target_name_norm:=intelligence.normalize_identity_text_v1(v_t.name);
  v_target_name_variant:=intelligence.normalize_local_osm_name_variant_v1(v_t.name);
  v_building_name_variant:=intelligence.normalize_local_osm_name_variant_v1(coalesce(v_c.building_name,''));

  if v_t.location is not null
     and coalesce(v_c.addr_housenumber,'')<>''
     and coalesce(v_c.addr_street,'')<>'' then
    select count(*) into v_exact_address_building_count
    from intelligence.osm_building_identity_features f2
    where lower(coalesce(f2.addr_housenumber,''))=lower(v_c.addr_housenumber)
      and intelligence.normalize_identity_text_v1(f2.addr_street)=intelligence.normalize_identity_text_v1(v_c.addr_street)
      and extensions.st_dwithin(v_t.location::extensions.geography,f2.geometry::extensions.geography,200);
  end if;

  if v_t.location is not null and v_target_name_variant<>'' then
    select count(*) into v_variant_named_building_count
    from intelligence.osm_building_identity_features f2
    where f2.name is not null
      and intelligence.normalize_local_osm_name_variant_v1(f2.name)=v_target_name_variant
      and extensions.st_dwithin(v_t.location::extensions.geography,f2.geometry::extensions.geography,200);
  end if;

  if v_t.location is not null then
    select count(*) into v_compatible_worship_building_count
    from intelligence.osm_building_identity_features f2
    where extensions.st_dwithin(v_t.location::extensions.geography,f2.geometry::extensions.geography,50)
      and (
        coalesce(f2.amenity_tag,'')='place_of_worship'
        or coalesce(f2.building_tag,'') in('church','chapel','religious')
      );
  end if;

  v_name_identity_lane:=
    coalesce(v_c.name_similarity,0)>=0.95
    and v_c.corroboration_basis in('strong_name_match','exact_house_and_street')
    and coalesce(v_c.class_compatible,false);

  v_name_variant_identity_lane:=
    v_t.target_class='religious_facility'
    and v_target_name_variant<>''
    and v_target_name_variant=v_building_name_variant
    and v_variant_named_building_count=1
    and coalesce(v_c.distance_m,1000000000)<=10
    and coalesce(v_c.class_compatible,false)
    and v_c.corroboration_basis='strong_name_match';

  v_address_identity_lane:=
    coalesce(v_c.address_match,false)
    and coalesce(v_c.distance_m,1000000000)<=10
    and v_exact_address_building_count=1
    and coalesce(v_c.addr_housenumber,'')<>''
    and coalesce(v_c.addr_street,'')<>'';

  v_generic_worship_geometry_lane:=
    v_t.target_class='religious_facility'
    and v_target_name_norm in('church','chapel')
    and coalesce(v_c.distance_m,1000000000)<=3
    and coalesce(v_c.class_compatible,false)
    and v_compatible_worship_building_count=1
    and (
      coalesce(v_c.amenity_tag,'')='place_of_worship'
      or coalesce(v_c.building_tag,'') in('church','chapel','religious')
    );

  if (
       v_target_name_norm ~ '^(church|chapel|hotel|motel|museum|stadium)$'
       and not v_generic_worship_geometry_lane
     )
     or v_target_name_norm ~ '(camp|campus|retreat|seminary|university|stadium|complex|medical center)' then
    raise exception 'target name is too generic or site-level for automatic building promotion: %',v_t.name;
  end if;

  if v_t.target_class in('university','sports_venue','amusement_park','convention_event_center','hospital') then
    raise exception 'multi-building/site-level target class requires manual or stronger building-specific reconciliation: %',v_t.target_class;
  end if;

  if v_c.canonical_building_source_record_id is null
     or coalesce(v_c.confidence,0)<0.93
     or not(
       v_name_identity_lane
       or v_name_variant_identity_lane
       or v_address_identity_lane
       or v_generic_worship_geometry_lane
     )
     or coalesce(v_c.canonical_overlap_ratio,0)<0.80
     or coalesce(v_c.canonical_uniqueness_margin,0)<0.80 then
    raise exception 'OSM identity candidate does not satisfy deterministic promotion thresholds';
  end if;

  if v_t.building_source_record_id is not null
     and v_t.building_source_record_id<>v_c.canonical_building_source_record_id then
    raise exception 'target already has a different building identity: %',v_t.building_source_record_id;
  end if;

  select * into v_bc
  from decisioning.building_candidates
  where source_record_id=v_c.canonical_building_source_record_id;
  if not found or v_bc.geometry is null then
    raise exception 'canonical building candidate missing geometry: %',v_c.canonical_building_source_record_id;
  end if;

  if v_t.location is not null then
    v_edge_distance_m:=extensions.st_distance(v_t.location::extensions.geography,v_bc.geometry::extensions.geography);
  end if;
  v_source_slug:=v_bc.source_slug;

  v_identity_basis:=case
    when v_generic_worship_geometry_lane
      then 'local_osm_unique_worship_geometry_plus_unique_canonical_overlap_v1'
    when v_address_identity_lane and not v_name_identity_lane and not v_name_variant_identity_lane
      then 'local_osm_unique_exact_address_containment_plus_unique_canonical_overlap_v1'
    when v_name_variant_identity_lane and not v_name_identity_lane
      then 'local_osm_name_variant_equivalence_plus_unique_canonical_overlap_v1'
    else 'local_osm_exact_name_plus_unique_canonical_overlap_v1'
  end;

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
        'building_identity_name_variant_equivalent',v_name_variant_identity_lane,
        'building_identity_variant_named_buildings_within_200m',v_variant_named_building_count,
        'building_identity_compatible_worship_buildings_within_50m',v_compatible_worship_building_count,
        'building_identity_address_match',v_c.address_match,
        'building_identity_exact_address_buildings_within_200m',v_exact_address_building_count,
        'building_identity_confidence',v_c.confidence,
        'building_identity_edge_distance_m',case when v_edge_distance_m is null then null else round(v_edge_distance_m::numeric,2) end,
        'building_identity_guardrail','Promoted only after strong OSM identity corroboration plus a unique canonical footprint; generic names require unique near-field class-compatible geometry and multi-building/site-level targets remain excluded.'
      )),
      updated_at=now()
  where id=p_target_id;

  insert into intelligence.premium_exterior_building_link_candidates(
    target_id,candidate_building_source_record_id,candidate_building_source_slug,source_slug,
    prior_centroid_distance_m,footprint_edge_distance_m,point_inside_footprint,
    match_basis,status,confidence,evidence,first_observed_at,last_observed_at
  ) values (
    p_target_id,v_bc.source_record_id,v_source_slug,'openstreetmap-premium-exterior-facilities',
    v_edge_distance_m,v_edge_distance_m,
    case when v_t.location is null then false else extensions.st_covers(v_bc.geometry,v_t.location::extensions.geometry) end,
    v_identity_basis,'verified',v_c.confidence,
    jsonb_build_object(
      'osm_building_iri',v_c.osm_building_iri,
      'osm_building_name',v_c.building_name,
      'canonical_overlap_ratio',v_c.canonical_overlap_ratio,
      'canonical_uniqueness_margin',v_c.canonical_uniqueness_margin,
      'name_similarity',v_c.name_similarity,
      'name_variant_equivalent',v_name_variant_identity_lane,
      'variant_named_buildings_within_200m',v_variant_named_building_count,
      'compatible_worship_buildings_within_50m',v_compatible_worship_building_count,
      'address_match',v_c.address_match,
      'exact_address_buildings_within_200m',v_exact_address_building_count,
      'promoted_at',now(),
      'verification_basis',v_identity_basis
    ),now(),now()
  )
  on conflict(target_id,candidate_building_source_record_id) do update set
    candidate_building_source_slug=excluded.candidate_building_source_slug,
    source_slug=excluded.source_slug,
    footprint_edge_distance_m=excluded.footprint_edge_distance_m,
    point_inside_footprint=excluded.point_inside_footprint,
    match_basis=excluded.match_basis,
    status='verified',
    confidence=excluded.confidence,
    evidence=coalesce(intelligence.premium_exterior_building_link_candidates.evidence,'{}'::jsonb)||excluded.evidence,
    last_observed_at=now();

  update intelligence.premium_exterior_osm_identity_candidates
  set status='reconciled',
      evidence=coalesce(evidence,'{}'::jsonb)||jsonb_build_object('promoted_at',now(),'promotion_basis',v_identity_basis),
      last_observed_at=now()
  where target_id=p_target_id and osm_building_iri=p_osm_building_iri;

  update intelligence.premium_exterior_osm_identity_candidates
  set status='superseded',
      evidence=coalesce(evidence,'{}'::jsonb)||jsonb_build_object('superseded_at',now(),'superseded_by_osm_building_iri',p_osm_building_iri),
      last_observed_at=now()
  where target_id=p_target_id and osm_building_iri<>p_osm_building_iri and status='candidate';

  return jsonb_build_object(
    'target_id',p_target_id,
    'osm_building_iri',p_osm_building_iri,
    'canonical_building_source_record_id',v_bc.source_record_id,
    'canonical_overlap_ratio',v_c.canonical_overlap_ratio,
    'name_similarity',v_c.name_similarity,
    'name_variant_equivalent',v_name_variant_identity_lane,
    'compatible_worship_buildings_within_50m',v_compatible_worship_building_count,
    'address_match',v_c.address_match,
    'confidence',v_c.confidence,
    'building_identity_status','verified_reconciled',
    'building_identity_basis',v_identity_basis
  );
end;
$function$;

create or replace function intelligence.materialize_premium_exterior_targeted_osm_canonical_v1(
  p_target_id uuid,
  p_osm_building_iri text
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','extensions','intelligence','decisioning','ingest'
as $function$
declare
  v_c intelligence.premium_exterior_osm_identity_candidates%rowtype;
  v_t intelligence.premium_exterior_targets%rowtype;
  v_f intelligence.osm_building_identity_features%rowtype;
  v_source_id uuid;
  v_raw_id uuid;
  v_hash text;
  v_target_name_norm text;
  v_address text;
  v_result jsonb;
  v_target_name_variant text;
  v_building_name_variant text;
  v_materialization_basis text;
  v_exact_named_building_count integer:=0;
  v_exact_address_building_count integer:=0;
  v_variant_named_building_count integer:=0;
  v_compatible_worship_building_count integer:=0;
  v_unique_named_worship_lane boolean:=false;
  v_unique_address_containment_lane boolean:=false;
  v_name_variant_lane boolean:=false;
  v_generic_worship_geometry_lane boolean:=false;
begin
  select * into v_c
  from intelligence.premium_exterior_osm_identity_candidates
  where target_id=p_target_id and osm_building_iri=p_osm_building_iri
  for update;
  if not found then raise exception 'OSM identity candidate not found'; end if;

  select * into v_t
  from intelligence.premium_exterior_targets
  where id=p_target_id
  for update;
  if not found then raise exception 'premium exterior target not found'; end if;

  select * into v_f
  from intelligence.osm_building_identity_features
  where osm_iri=p_osm_building_iri;
  if not found or v_f.geometry is null then raise exception 'OSM building feature missing geometry'; end if;

  v_target_name_norm:=intelligence.normalize_identity_text_v1(v_t.name);
  v_target_name_variant:=intelligence.normalize_local_osm_name_variant_v1(v_t.name);
  v_building_name_variant:=intelligence.normalize_local_osm_name_variant_v1(coalesce(v_f.name,''));

  if v_t.location is not null and v_target_name_norm<>'' then
    select count(*) into v_exact_named_building_count
    from intelligence.osm_building_identity_features f2
    where f2.name is not null
      and intelligence.normalize_identity_text_v1(f2.name)=v_target_name_norm
      and extensions.st_dwithin(v_t.location::extensions.geography,f2.geometry::extensions.geography,400);
  end if;

  if v_t.location is not null and v_target_name_variant<>'' then
    select count(*) into v_variant_named_building_count
    from intelligence.osm_building_identity_features f2
    where f2.name is not null
      and intelligence.normalize_local_osm_name_variant_v1(f2.name)=v_target_name_variant
      and extensions.st_dwithin(v_t.location::extensions.geography,f2.geometry::extensions.geography,200);
  end if;

  if v_t.location is not null
     and coalesce(v_c.addr_housenumber,'')<>''
     and coalesce(v_c.addr_street,'')<>'' then
    select count(*) into v_exact_address_building_count
    from intelligence.osm_building_identity_features f2
    where lower(coalesce(f2.addr_housenumber,''))=lower(v_c.addr_housenumber)
      and intelligence.normalize_identity_text_v1(f2.addr_street)=intelligence.normalize_identity_text_v1(v_c.addr_street)
      and extensions.st_dwithin(v_t.location::extensions.geography,f2.geometry::extensions.geography,200);
  end if;

  if v_t.location is not null then
    select count(*) into v_compatible_worship_building_count
    from intelligence.osm_building_identity_features f2
    where extensions.st_dwithin(v_t.location::extensions.geography,f2.geometry::extensions.geography,50)
      and (
        coalesce(f2.amenity_tag,'')='place_of_worship'
        or coalesce(f2.building_tag,'') in('church','chapel','religious')
      );
  end if;

  v_unique_named_worship_lane:=
    v_t.target_class='religious_facility'
    and coalesce(v_c.name_similarity,0)>=0.99
    and coalesce(v_c.class_compatible,false)
    and coalesce(v_c.distance_m,1000000000)<=100
    and v_exact_named_building_count=1
    and (
      coalesce(v_f.amenity_tag,'')='place_of_worship'
      or coalesce(v_f.building_tag,'') in('church','chapel','religious')
    );

  v_unique_address_containment_lane:=
    coalesce(v_c.address_match,false)
    and coalesce(v_c.distance_m,1000000000)<=10
    and v_exact_address_building_count=1
    and v_t.location is not null
    and extensions.st_covers(v_f.geometry,v_t.location::extensions.geometry);

  v_name_variant_lane:=
    v_t.target_class='religious_facility'
    and v_target_name_variant<>''
    and v_target_name_variant=v_building_name_variant
    and v_variant_named_building_count=1
    and coalesce(v_c.distance_m,1000000000)<=10
    and coalesce(v_c.class_compatible,false)
    and v_c.corroboration_basis='strong_name_match';

  v_generic_worship_geometry_lane:=
    v_t.target_class='religious_facility'
    and v_target_name_norm in('church','chapel')
    and coalesce(v_c.distance_m,1000000000)<=3
    and coalesce(v_c.class_compatible,false)
    and v_compatible_worship_building_count=1
    and (
      coalesce(v_f.amenity_tag,'')='place_of_worship'
      or coalesce(v_f.building_tag,'') in('church','chapel','religious')
    );

  if v_c.status<>'candidate'
     or not(
       (coalesce(v_c.name_similarity,0)>=0.95 and coalesce(v_c.class_compatible,false) and coalesce(v_c.distance_m,1000000000)<=10)
       or (coalesce(v_c.name_similarity,0)>=0.95 and coalesce(v_c.class_compatible,false) and coalesce(v_c.address_match,false) and coalesce(v_c.distance_m,1000000000)<=25)
       or v_unique_named_worship_lane
       or v_unique_address_containment_lane
       or v_name_variant_lane
       or v_generic_worship_geometry_lane
     )
     or v_t.target_class not in('religious_facility','dealership_showroom','hotel','museum_performing_arts')
     or (
       v_target_name_norm ~ '^(church|chapel|hotel|motel|museum|stadium)$'
       and not v_generic_worship_geometry_lane
     )
     or v_target_name_norm ~ '(camp|campus|retreat|seminary|university|stadium|complex|medical center)' then
    raise exception 'candidate does not satisfy targeted OSM canonical materialization thresholds';
  end if;

  if not v_unique_address_containment_lane
     and not v_name_variant_lane
     and not v_generic_worship_geometry_lane then
    if coalesce(intelligence.normalize_identity_text_v1(v_f.name),'')=''
       or extensions.similarity(v_target_name_norm,intelligence.normalize_identity_text_v1(v_f.name))<0.95 then
      raise exception 'current OSM feature name no longer corroborates target';
    end if;
  elsif v_name_variant_lane and v_target_name_variant<>v_building_name_variant then
    raise exception 'current OSM feature name variant no longer corroborates target';
  end if;

  v_materialization_basis:=case
    when v_generic_worship_geometry_lane
      then 'unique_compatible_worship_building_within_3m_v1'
    when v_unique_address_containment_lane and coalesce(v_c.name_similarity,0)<0.95
      then 'unique_exact_address_point_inside_building_v1'
    when v_name_variant_lane and coalesce(v_c.name_similarity,0)<0.95
      then 'unique_local_name_variant_worship_building_within_10m_v1'
    when coalesce(v_c.distance_m,1000000000)<=10
      then 'near_exact_target_building_name_plus_target_point_within_10m_v1'
    when coalesce(v_c.address_match,false) and coalesce(v_c.distance_m,1000000000)<=25
      then 'near_exact_target_building_name_plus_exact_address_within_25m_v1'
    when v_unique_named_worship_lane
      then 'unique_exact_named_worship_building_within_100m_v1'
    when v_unique_address_containment_lane
      then 'unique_exact_address_point_inside_building_v1'
    when v_name_variant_lane
      then 'unique_local_name_variant_worship_building_within_10m_v1'
    else null
  end;
  if v_materialization_basis is null then raise exception 'no approved targeted OSM materialization basis'; end if;

  select id into v_source_id
  from ingest.sources
  where slug='openstreetmap-targeted-building-identity';
  if v_source_id is null then raise exception 'targeted OSM canonical source is not registered'; end if;

  v_hash:=md5(v_f.osm_iri||'|'||coalesce(v_f.source_timestamp::text,'')||'|'||coalesce(v_f.raw_tags::text,''));
  v_address:=nullif(concat_ws(' ',nullif(v_f.addr_housenumber,''),nullif(v_f.addr_street,'')),'');

  insert into ingest.raw_records(
    source_id,source_native_id,source_url,retrieved_at,observed_at,content_hash,
    parser_version,parse_status,provisional_entity_type,location,within_pilot_radius,
    raw_payload,geometry
  ) values (
    v_source_id,v_f.osm_iri,v_f.osm_iri,now(),v_f.source_timestamp,v_hash,
    'targeted-osm-building-identity-v1','parsed','building',extensions.st_pointonsurface(v_f.geometry),true,
    jsonb_build_object(
      'properties',jsonb_strip_nulls(jsonb_build_object(
        'PROP_ADDR',v_address,'PROP_CITY',v_f.addr_city,'PROP_ST',v_t.state_code,
        'PROP_ZIP',v_f.addr_postcode,'OSM_NAME',v_f.name,'OSM_BUILDING',v_f.building_tag
      )),
      'osm_iri',v_f.osm_iri,'osm_type',v_f.osm_type,'osm_id',v_f.osm_id,
      'region_slug',v_f.region_slug,'source_timestamp',v_f.source_timestamp,
      'raw_tags',v_f.raw_tags,'materialization_basis',v_materialization_basis,
      'exact_named_buildings_within_400m',v_exact_named_building_count,
      'variant_named_buildings_within_200m',v_variant_named_building_count,
      'compatible_worship_buildings_within_50m',v_compatible_worship_building_count,
      'name_variant_equivalent',v_name_variant_lane,
      'exact_address_buildings_within_200m',v_exact_address_building_count,
      'materialized_for_target_id',p_target_id,
      'guardrail','This raw record establishes the OSM building footprint identity only; no OSM height/material/condition claims are promoted here.'
    ),
    v_f.geometry
  )
  on conflict(source_id,source_native_id,content_hash) do update
    set retrieved_at=excluded.retrieved_at
  returning id into v_raw_id;

  if not exists(select 1 from decisioning.building_candidates where source_record_id=v_raw_id) then
    raise exception 'targeted OSM raw record did not materialize into canonical building_candidates view: %',v_raw_id;
  end if;

  update intelligence.premium_exterior_osm_identity_candidates
  set canonical_building_source_record_id=v_raw_id,
      canonical_overlap_ratio=1,
      canonical_edge_distance_m=0,
      canonical_second_overlap_ratio=0,
      canonical_uniqueness_margin=1,
      confidence=greatest(confidence,0.97),
      evidence=coalesce(evidence,'{}'::jsonb)||jsonb_build_object(
        'targeted_osm_canonical_materialized_at',now(),
        'targeted_osm_canonical_source_record_id',v_raw_id,
        'targeted_osm_canonical_basis',v_materialization_basis,
        'exact_named_buildings_within_400m',v_exact_named_building_count,
        'variant_named_buildings_within_200m',v_variant_named_building_count,
        'compatible_worship_buildings_within_50m',v_compatible_worship_building_count,
        'name_variant_equivalent',v_name_variant_lane,
        'exact_address_buildings_within_200m',v_exact_address_building_count
      ),
      last_observed_at=now()
  where target_id=p_target_id and osm_building_iri=p_osm_building_iri;

  v_result:=intelligence.promote_premium_exterior_local_osm_identity_v1(p_target_id,p_osm_building_iri);
  return v_result||jsonb_build_object(
    'canonical_materialization_source','openstreetmap-targeted-building-identity',
    'canonical_materialization_basis',v_materialization_basis,
    'exact_named_buildings_within_400m',v_exact_named_building_count,
    'variant_named_buildings_within_200m',v_variant_named_building_count,
    'compatible_worship_buildings_within_50m',v_compatible_worship_building_count,
    'name_variant_equivalent',v_name_variant_lane,
    'exact_address_buildings_within_200m',v_exact_address_building_count
  );
end;
$function$;

-- Preserve site/operator evidence without allowing it to re-enter the active
-- building-candidate queue on later refreshes.
update intelligence.premium_exterior_osm_identity_candidates c
set status='rejected',
    evidence=coalesce(c.evidence,'{}'::jsonb)||jsonb_build_object(
      'rejected_at',now(),
      'rejection_basis','site_level_or_operator_only_not_building_specific_v1',
      'rejection_guardrail','Operator/site affinity is contextual evidence, not physical building identity.'
    ),
    last_observed_at=now()
from intelligence.premium_exterior_targets t
where t.id=c.target_id
  and c.status='candidate'
  and coalesce(c.evidence->>'resolver','')='local_geofabrik_osm_building_identity_v1'
  and t.target_class='university';

-- Label the remaining active local candidates with the reason they require
-- site/parcel/manual resolution rather than a broader automatic distance rule.
update intelligence.premium_exterior_osm_identity_candidates c
set evidence=coalesce(c.evidence,'{}'::jsonb)||jsonb_build_object(
      'manual_review_lane',case
        when t.target_class='sports_venue' then 'multi_structure_sports_venue_requires_site_resolution'
        when t.name='Kentucky Music Hall of Fame and Museum' then 'far_exact_name_museum_requires_site_or_source_resolution'
        when t.name='Louisville Baha''i Center' then 'far_exact_address_requires_site_or_parcel_resolution'
        else 'manual_building_identity_review'
      end,
      'manual_review_reason',case
        when t.target_class='sports_venue' then 'Exact OSM facility/building naming is insufficient to collapse a stadium site into one physical building.'
        when t.name='Kentucky Music Hall of Fame and Museum' then 'Exact named museum building is about 196m from the target POI; distance exceeds automatic identity lanes.'
        when t.name='Louisville Baha''i Center' then 'Exact addressed building is about 94m from the target POI and lacks independent building-name/type corroboration.'
        else 'Additional building-specific evidence required.'
      end,
      'manual_review_labeled_at',now()
    ),
    last_observed_at=now()
from intelligence.premium_exterior_targets t
where t.id=c.target_id
  and c.status='candidate'
  and coalesce(c.evidence->>'resolver','')='local_geofabrik_osm_building_identity_v1';
