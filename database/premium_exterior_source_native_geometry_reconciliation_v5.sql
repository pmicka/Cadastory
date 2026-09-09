-- Premium exterior source-native geometry reconciliation v5
-- Final production rules for exact source-native OSM containment and <=1m near-edge identity.
-- These functions promote footprint identity only. Unsupported physical attributes remain null/gated.

create or replace function intelligence.reconcile_premium_exterior_source_native_containment_v1(p_target_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','extensions','intelligence','decisioning','ingest'
as $function$
declare
  v_t intelligence.premium_exterior_targets%rowtype;
  v_f intelligence.osm_building_identity_features%rowtype;
  v_source_id uuid; v_raw_id uuid; v_hash text; v_containing_count integer:=0;
  v_target_name_norm text; v_building_name_norm text; v_name_similarity numeric:=0;
  v_specific_class_evidence boolean:=false; v_eligible boolean:=false;
  v_basis text:='source_native_osm_node_unique_building_containment_v1';
  v_confidence numeric:=0.96; v_bc decisioning.building_candidates%rowtype;
begin
  select * into v_t from intelligence.premium_exterior_targets where id=p_target_id for update;
  if not found then raise exception 'premium exterior target not found'; end if;
  if v_t.building_source_record_id is not null then raise exception 'target already has building identity'; end if;
  if v_t.location is null or coalesce(v_t.source_native_id,'') not like 'https://www.openstreetmap.org/node/%' then
    raise exception 'target is not an unresolved OSM node POI';
  end if;

  v_target_name_norm:=intelligence.normalize_identity_text_v1(coalesce(v_t.name,''));
  select count(*) into v_containing_count
  from intelligence.osm_building_identity_features f
  where extensions.st_covers(f.geometry,v_t.location::extensions.geometry);
  if v_containing_count<>1 then raise exception 'target is not contained by exactly one OSM building polygon: %',v_containing_count; end if;

  select * into v_f
  from intelligence.osm_building_identity_features f
  where extensions.st_covers(f.geometry,v_t.location::extensions.geometry)
  limit 1;
  if not found then raise exception 'containing OSM building feature not found'; end if;

  v_building_name_norm:=intelligence.normalize_identity_text_v1(coalesce(v_f.name,''));
  if v_target_name_norm<>'' and v_building_name_norm<>'' then
    v_name_similarity:=extensions.similarity(v_target_name_norm,v_building_name_norm);
  end if;

  v_specific_class_evidence :=
    (v_t.target_class='religious_facility' and (coalesce(v_f.amenity_tag,'')='place_of_worship' or coalesce(v_f.building_tag,'') in ('church','chapel','religious')))
    or (v_t.target_class='hotel' and (coalesce(v_f.raw_tags->>'tourism','') in ('hotel','motel','guest_house') or coalesce(v_f.building_tag,'') in ('hotel','motel')))
    or (v_t.target_class='dealership_showroom' and (coalesce(v_f.raw_tags->>'shop','')='car' or coalesce(v_f.raw_tags->>'amenity','')='car_rental'))
    or (v_t.target_class='museum_performing_arts' and (coalesce(v_f.raw_tags->>'tourism','')='museum' or coalesce(v_f.amenity_tag,'') in ('theatre','arts_centre')))
    or (v_t.target_class='hospital' and (coalesce(v_f.amenity_tag,'')='hospital' or coalesce(v_f.building_tag,'')='hospital'));

  v_eligible :=
    v_t.target_class in ('religious_facility','hotel','dealership_showroom')
    or (v_t.target_class='museum_performing_arts' and v_target_name_norm<>'')
    or (v_t.target_class='convention_event_center' and v_t.target_subclass='events_venue' and v_target_name_norm<>'')
    or (v_t.target_class='hospital' and v_target_name_norm<>'' and v_t.address_text is not null)
    or (v_t.target_class='university' and v_target_name_norm<>'' and v_building_name_norm<>'' and v_name_similarity>=0.70
        and v_target_name_norm !~ '(entrance|lawn|circle|campus|university)');
  if not v_eligible then raise exception 'target class/semantics are not eligible for source-native containment reconciliation'; end if;
  if v_target_name_norm ~ '(^| )(camp|campus|retreat|seminary|stadium|complex|medical center)( |$)' then
    raise exception 'site-level target name is excluded from building containment reconciliation';
  end if;
  if v_target_name_norm='' and not v_specific_class_evidence then raise exception 'unnamed target lacks building-specific class evidence'; end if;
  if v_target_name_norm ~ '^(church|chapel|hotel|motel|museum|theatre)$' and not v_specific_class_evidence then
    raise exception 'generic target name requires building-specific class evidence';
  end if;

  select id into v_source_id from ingest.sources where slug='openstreetmap-targeted-building-identity';
  if v_source_id is null then raise exception 'targeted OSM canonical source is not registered'; end if;
  v_hash:=md5(v_f.osm_iri||'|'||coalesce(v_f.source_timestamp::text,'')||'|'||coalesce(v_f.raw_tags::text,''));

  insert into ingest.raw_records(source_id,source_native_id,source_url,retrieved_at,observed_at,content_hash,parser_version,
    parse_status,provisional_entity_type,location,within_pilot_radius,raw_payload,geometry)
  values(v_source_id,v_f.osm_iri,v_f.osm_iri,now(),v_f.source_timestamp,v_hash,
    'targeted-osm-source-native-containment-v1','parsed','building',extensions.st_pointonsurface(v_f.geometry),true,
    jsonb_build_object(
      'properties',jsonb_strip_nulls(jsonb_build_object(
        'PROP_ADDR',nullif(concat_ws(' ',nullif(v_f.addr_housenumber,''),nullif(v_f.addr_street,'')),''),
        'PROP_CITY',v_f.addr_city,'PROP_ST',v_t.state_code,'PROP_ZIP',v_f.addr_postcode,
        'OSM_NAME',v_f.name,'OSM_BUILDING',v_f.building_tag)),
      'osm_iri',v_f.osm_iri,'osm_type',v_f.osm_type,'osm_id',v_f.osm_id,'region_slug',v_f.region_slug,
      'source_timestamp',v_f.source_timestamp,'raw_tags',v_f.raw_tags,'materialization_basis',v_basis,
      'materialized_for_target_id',p_target_id,'target_class',v_t.target_class,'target_subclass',v_t.target_subclass,
      'target_name',v_t.name,'building_name_similarity',v_name_similarity,
      'guardrail','The source OSM POI node is contained by exactly one OSM building polygon. Site-level classes require specialized semantics. This establishes footprint identity only; height, stories, facade, glazing, condition and service need remain unknown unless independently resolved.'),
    v_f.geometry)
  on conflict(source_id,source_native_id,content_hash) do update set retrieved_at=excluded.retrieved_at
  returning id into v_raw_id;

  select * into v_bc from decisioning.building_candidates where source_record_id=v_raw_id;
  if not found then raise exception 'targeted OSM raw record did not materialize into building_candidates'; end if;

  insert into intelligence.premium_exterior_osm_identity_candidates(
    target_id,osm_building_iri,osm_geometry,distance_m,building_tag,building_name,operator_name,brand_name,amenity_tag,
    addr_housenumber,addr_street,addr_city,addr_postcode,canonical_building_source_record_id,canonical_overlap_ratio,
    canonical_edge_distance_m,status,confidence,evidence,first_observed_at,last_observed_at,name_similarity,address_match,
    operator_similarity,class_compatible,canonical_second_overlap_ratio,canonical_uniqueness_margin,corroboration_basis)
  values(p_target_id,v_f.osm_iri,v_f.geometry,0,v_f.building_tag,v_f.name,v_f.operator_name,v_f.brand_name,v_f.amenity_tag,
    v_f.addr_housenumber,v_f.addr_street,v_f.addr_city,v_f.addr_postcode,v_raw_id,1,0,'reconciled',v_confidence,
    jsonb_build_object('resolver','source_native_osm_node_containment_v1','promotion_basis',v_basis,
      'containing_buildings',v_containing_count,'target_name',v_t.name,'target_class',v_t.target_class,
      'target_subclass',v_t.target_subclass,'building_name_similarity',v_name_similarity,
      'class_specific_building_evidence',v_specific_class_evidence,
      'guardrail','OSM node-to-building containment is accepted only for exactly one containing building polygon and class-specific anti-site-level semantics.'),
    now(),now(),v_name_similarity,false,0,v_specific_class_evidence,0,1,'source_native_unique_containment')
  on conflict(target_id,osm_building_iri) do update set
    canonical_building_source_record_id=excluded.canonical_building_source_record_id,canonical_overlap_ratio=1,
    canonical_edge_distance_m=0,status='reconciled',confidence=excluded.confidence,
    evidence=coalesce(intelligence.premium_exterior_osm_identity_candidates.evidence,'{}'::jsonb)||excluded.evidence,
    last_observed_at=now(),name_similarity=excluded.name_similarity,class_compatible=excluded.class_compatible,
    canonical_second_overlap_ratio=0,canonical_uniqueness_margin=1,corroboration_basis='source_native_unique_containment';

  update intelligence.premium_exterior_targets
  set building_source_record_id=v_bc.source_record_id,building_source_slug=v_bc.source_slug,footprint_sqft=v_bc.footprint_sqft,
      mapped_height_m=null,property_address=v_bc.property_address,property_city=v_bc.property_city,
      state_code=coalesce(state_code,v_bc.state_code),postal_code=v_bc.postal_code,building_match_distance_m=0,
      evidence=coalesce(evidence,'{}'::jsonb)||jsonb_build_object(
        'building_identity_status','verified_reconciled','building_identity_verified_at',now(),
        'building_identity_basis',v_basis,'building_identity_osm_building_iri',v_f.osm_iri,
        'building_identity_containing_buildings',v_containing_count,'building_identity_name_similarity',v_name_similarity,
        'building_identity_confidence',v_confidence,
        'building_identity_guardrail','Source-native OSM POI node is inside exactly one eligible OSM building polygon; only footprint identity is promoted. Physical attributes remain independently gated.'),
      updated_at=now()
  where id=p_target_id;

  update intelligence.premium_exterior_building_link_candidates
  set status='superseded',evidence=coalesce(evidence,'{}'::jsonb)||jsonb_build_object('superseded_at',now(),
      'resolution_basis',v_basis,'superseded_by_osm_building_iri',v_f.osm_iri),last_observed_at=now()
  where target_id=p_target_id and status='quarantined';

  insert into intelligence.premium_exterior_building_link_candidates(
    target_id,candidate_building_source_record_id,candidate_building_source_slug,source_slug,prior_centroid_distance_m,
    footprint_edge_distance_m,point_inside_footprint,match_basis,status,confidence,evidence,first_observed_at,last_observed_at)
  values(p_target_id,v_bc.source_record_id,v_bc.source_slug,'openstreetmap-premium-exterior-facilities',0,0,true,
    v_basis,'verified',v_confidence,jsonb_build_object('osm_building_iri',v_f.osm_iri,'containing_buildings',v_containing_count,
      'building_name_similarity',v_name_similarity,'verified_at',now(),'verification_basis',v_basis),now(),now())
  on conflict(target_id,candidate_building_source_record_id) do update set
    candidate_building_source_slug=excluded.candidate_building_source_slug,source_slug=excluded.source_slug,
    footprint_edge_distance_m=0,point_inside_footprint=true,match_basis=v_basis,status='verified',confidence=v_confidence,
    evidence=coalesce(intelligence.premium_exterior_building_link_candidates.evidence,'{}'::jsonb)||excluded.evidence,
    last_observed_at=now();

  return jsonb_build_object('target_id',p_target_id,'osm_building_iri',v_f.osm_iri,
    'canonical_building_source_record_id',v_raw_id,'canonical_materialization_source','openstreetmap-targeted-building-identity',
    'building_identity_status','verified_reconciled','building_identity_basis',v_basis,'confidence',v_confidence,
    'containing_buildings',v_containing_count,'target_class',v_t.target_class,'target_subclass',v_t.target_subclass,
    'building_name_similarity',v_name_similarity,'class_specific_building_evidence',v_specific_class_evidence);
end;
$function$;

create or replace function intelligence.reconcile_premium_exterior_source_native_near_edge_v1(p_target_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','extensions','intelligence','decisioning','ingest'
as $function$
declare
  v_t intelligence.premium_exterior_targets%rowtype; v_f intelligence.osm_building_identity_features%rowtype;
  v_first_m double precision; v_second_m double precision; v_margin_m double precision;
  v_specific_class_evidence boolean:=false; v_target_name_norm text; v_source_id uuid; v_raw_id uuid; v_hash text;
  v_bc decisioning.building_candidates%rowtype; v_basis text:='source_native_osm_node_unique_near_edge_v1'; v_confidence numeric:=0.94;
begin
  select * into v_t from intelligence.premium_exterior_targets where id=p_target_id for update;
  if not found then raise exception 'premium exterior target not found'; end if;
  if v_t.building_source_record_id is not null then raise exception 'target already has building identity'; end if;
  if v_t.location is null or coalesce(v_t.source_native_id,'') not like 'https://www.openstreetmap.org/node/%' then raise exception 'target is not an unresolved OSM node POI'; end if;
  if v_t.target_class not in ('religious_facility','hotel','dealership_showroom') then raise exception 'target class not eligible: %',v_t.target_class; end if;

  v_target_name_norm:=intelligence.normalize_identity_text_v1(coalesce(v_t.name,''));
  if v_target_name_norm ~ '(^| )(camp|campus|retreat|seminary|stadium|complex|medical center)( |$)' then raise exception 'site-level target semantics are excluded'; end if;

  select * into v_f
  from intelligence.osm_building_identity_features f
  where f.geometry operator(extensions.&&) extensions.st_expand(v_t.location::extensions.geometry,0.002)
    and extensions.st_dwithin(v_t.location::extensions.geography,f.geometry::extensions.geography,150)
  order by extensions.st_distance(v_t.location::extensions.geography,f.geometry::extensions.geography),f.osm_iri limit 1;
  if not found then raise exception 'no nearby OSM building'; end if;
  v_first_m:=extensions.st_distance(v_t.location::extensions.geography,v_f.geometry::extensions.geography);

  select extensions.st_distance(v_t.location::extensions.geography,f.geometry::extensions.geography) into v_second_m
  from intelligence.osm_building_identity_features f
  where f.osm_iri<>v_f.osm_iri
    and f.geometry operator(extensions.&&) extensions.st_expand(v_t.location::extensions.geometry,0.002)
    and extensions.st_dwithin(v_t.location::extensions.geography,f.geometry::extensions.geography,150)
  order by extensions.st_distance(v_t.location::extensions.geography,f.geometry::extensions.geography),f.osm_iri limit 1;
  v_second_m:=coalesce(v_second_m,999); v_margin_m:=v_second_m-v_first_m;
  if v_first_m>1 or v_margin_m<20 then raise exception 'nearest OSM building does not satisfy <=1m and >=20m margin thresholds: first %, margin %',v_first_m,v_margin_m; end if;

  if coalesce(v_f.raw_tags->>'disused:amenity','')<>'' or coalesce(v_f.raw_tags->>'disused:shop','')<>'' or coalesce(v_f.raw_tags->>'disused:tourism','')<>'' then
    raise exception 'nearest OSM building carries conflicting/disused use metadata';
  end if;

  v_specific_class_evidence :=
    (v_t.target_class='religious_facility' and (coalesce(v_f.amenity_tag,'')='place_of_worship' or coalesce(v_f.building_tag,'') in ('church','chapel','religious')))
    or (v_t.target_class='hotel' and (coalesce(v_f.raw_tags->>'tourism','') in ('hotel','motel','guest_house') or coalesce(v_f.building_tag,'') in ('hotel','motel')))
    or (v_t.target_class='dealership_showroom' and (coalesce(v_f.raw_tags->>'shop','')='car' or coalesce(v_f.raw_tags->>'amenity','')='car_rental'));
  if v_target_name_norm='' and not v_specific_class_evidence then raise exception 'unnamed target lacks building-specific class evidence'; end if;
  if v_target_name_norm ~ '^(church|chapel|hotel|motel)$' and not v_specific_class_evidence then raise exception 'generic target name requires building-specific class evidence'; end if;

  select id into v_source_id from ingest.sources where slug='openstreetmap-targeted-building-identity';
  if v_source_id is null then raise exception 'targeted OSM canonical source is not registered'; end if;
  v_hash:=md5(v_f.osm_iri||'|'||coalesce(v_f.source_timestamp::text,'')||'|'||coalesce(v_f.raw_tags::text,''));

  insert into ingest.raw_records(source_id,source_native_id,source_url,retrieved_at,observed_at,content_hash,parser_version,
    parse_status,provisional_entity_type,location,within_pilot_radius,raw_payload,geometry)
  values(v_source_id,v_f.osm_iri,v_f.osm_iri,now(),v_f.source_timestamp,v_hash,'targeted-osm-source-native-near-edge-v1','parsed','building',
    extensions.st_pointonsurface(v_f.geometry),true,
    jsonb_build_object('properties',jsonb_strip_nulls(jsonb_build_object(
      'PROP_ADDR',nullif(concat_ws(' ',nullif(v_f.addr_housenumber,''),nullif(v_f.addr_street,'')),''),
      'PROP_CITY',v_f.addr_city,'PROP_ST',v_t.state_code,'PROP_ZIP',v_f.addr_postcode,'OSM_NAME',v_f.name,'OSM_BUILDING',v_f.building_tag)),
      'osm_iri',v_f.osm_iri,'osm_type',v_f.osm_type,'osm_id',v_f.osm_id,'region_slug',v_f.region_slug,
      'source_timestamp',v_f.source_timestamp,'raw_tags',v_f.raw_tags,'materialization_basis',v_basis,
      'materialized_for_target_id',p_target_id,'nearest_edge_m',v_first_m,'second_nearest_edge_m',v_second_m,
      'uniqueness_margin_m',v_margin_m,'guardrail','Source OSM POI is within 1m of a uniquely nearest OSM building with >=20m separation to the next building. Site-level targets and conflicting use metadata are excluded. Only footprint identity is promoted.'),v_f.geometry)
  on conflict(source_id,source_native_id,content_hash) do update set retrieved_at=excluded.retrieved_at returning id into v_raw_id;

  select * into v_bc from decisioning.building_candidates where source_record_id=v_raw_id;
  if not found then raise exception 'targeted OSM raw record did not materialize into building_candidates'; end if;

  insert into intelligence.premium_exterior_osm_identity_candidates(
    target_id,osm_building_iri,osm_geometry,distance_m,building_tag,building_name,operator_name,brand_name,amenity_tag,
    addr_housenumber,addr_street,addr_city,addr_postcode,canonical_building_source_record_id,canonical_overlap_ratio,
    canonical_edge_distance_m,status,confidence,evidence,first_observed_at,last_observed_at,name_similarity,address_match,
    operator_similarity,class_compatible,canonical_second_overlap_ratio,canonical_uniqueness_margin,corroboration_basis)
  values(p_target_id,v_f.osm_iri,v_f.geometry,v_first_m,v_f.building_tag,v_f.name,v_f.operator_name,v_f.brand_name,v_f.amenity_tag,
    v_f.addr_housenumber,v_f.addr_street,v_f.addr_city,v_f.addr_postcode,v_raw_id,1,0,'reconciled',v_confidence,
    jsonb_build_object('resolver','source_native_osm_node_near_edge_v1','promotion_basis',v_basis,'nearest_edge_m',v_first_m,
      'second_nearest_edge_m',v_second_m,'uniqueness_margin_m',v_margin_m,'target_name',v_t.name,'target_class',v_t.target_class,
      'class_specific_building_evidence',v_specific_class_evidence,
      'guardrail','Near-edge identity requires <=1m true footprint gap, >=20m second-nearest margin, simple facility semantics, and no conflicting use metadata.'),
    now(),now(),0,false,0,v_specific_class_evidence,0,1,'source_native_unique_near_edge')
  on conflict(target_id,osm_building_iri) do update set canonical_building_source_record_id=excluded.canonical_building_source_record_id,
    canonical_overlap_ratio=1,canonical_edge_distance_m=0,status='reconciled',confidence=excluded.confidence,
    evidence=coalesce(intelligence.premium_exterior_osm_identity_candidates.evidence,'{}'::jsonb)||excluded.evidence,
    last_observed_at=now(),canonical_second_overlap_ratio=0,canonical_uniqueness_margin=1,corroboration_basis='source_native_unique_near_edge';

  update intelligence.premium_exterior_targets
  set building_source_record_id=v_bc.source_record_id,building_source_slug=v_bc.source_slug,footprint_sqft=v_bc.footprint_sqft,
      mapped_height_m=null,property_address=v_bc.property_address,property_city=v_bc.property_city,state_code=coalesce(state_code,v_bc.state_code),
      postal_code=v_bc.postal_code,building_match_distance_m=v_first_m,
      evidence=coalesce(evidence,'{}'::jsonb)||jsonb_build_object('building_identity_status','verified_reconciled',
        'building_identity_verified_at',now(),'building_identity_basis',v_basis,'building_identity_osm_building_iri',v_f.osm_iri,
        'building_identity_edge_distance_m',round(v_first_m::numeric,2),'building_identity_second_nearest_edge_m',round(v_second_m::numeric,2),
        'building_identity_uniqueness_margin_m',round(v_margin_m::numeric,2),'building_identity_confidence',v_confidence,
        'building_identity_guardrail','Near-edge source-native reconciliation promotes footprint identity only; physical attributes remain independently gated.'),
      updated_at=now()
  where id=p_target_id;

  update intelligence.premium_exterior_building_link_candidates
  set status='superseded',evidence=coalesce(evidence,'{}'::jsonb)||jsonb_build_object('superseded_at',now(),
      'resolution_basis',v_basis,'superseded_by_osm_building_iri',v_f.osm_iri),last_observed_at=now()
  where target_id=p_target_id and status='quarantined';

  insert into intelligence.premium_exterior_building_link_candidates(
    target_id,candidate_building_source_record_id,candidate_building_source_slug,source_slug,prior_centroid_distance_m,
    footprint_edge_distance_m,point_inside_footprint,match_basis,status,confidence,evidence,first_observed_at,last_observed_at)
  values(p_target_id,v_bc.source_record_id,v_bc.source_slug,'openstreetmap-premium-exterior-facilities',v_first_m,v_first_m,false,v_basis,'verified',v_confidence,
    jsonb_build_object('osm_building_iri',v_f.osm_iri,'nearest_edge_m',v_first_m,'second_nearest_edge_m',v_second_m,
      'uniqueness_margin_m',v_margin_m,'verified_at',now(),'verification_basis',v_basis),now(),now())
  on conflict(target_id,candidate_building_source_record_id) do update set
    candidate_building_source_slug=excluded.candidate_building_source_slug,source_slug=excluded.source_slug,
    footprint_edge_distance_m=excluded.footprint_edge_distance_m,point_inside_footprint=false,match_basis=v_basis,status='verified',confidence=v_confidence,
    evidence=coalesce(intelligence.premium_exterior_building_link_candidates.evidence,'{}'::jsonb)||excluded.evidence,last_observed_at=now();

  return jsonb_build_object('target_id',p_target_id,'osm_building_iri',v_f.osm_iri,'canonical_building_source_record_id',v_raw_id,
    'building_identity_status','verified_reconciled','building_identity_basis',v_basis,'confidence',v_confidence,
    'nearest_edge_m',v_first_m,'second_nearest_edge_m',v_second_m,'uniqueness_margin_m',v_margin_m,
    'class_specific_building_evidence',v_specific_class_evidence);
end;
$function$;

revoke all on function intelligence.reconcile_premium_exterior_source_native_containment_v1(uuid) from public, anon, authenticated;
revoke all on function intelligence.reconcile_premium_exterior_source_native_near_edge_v1(uuid) from public, anon, authenticated;
grant execute on function intelligence.reconcile_premium_exterior_source_native_containment_v1(uuid) to service_role;
grant execute on function intelligence.reconcile_premium_exterior_source_native_near_edge_v1(uuid) to service_role;
