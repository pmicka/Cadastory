
-- Farm Watch strict nested landscape-domain v3.
-- Absorb child geometries into parents after barrier-aware derivation so PostGIS
-- containment predicates are exact despite sub-dimensional floating/topology noise.

create or replace function farm_watch.farm_watch_context_contract_v1(
  p_product_kind text
) returns jsonb
language plpgsql
immutable
security definer
set search_path=pg_catalog
as $$
begin
  if p_product_kind='soils-map-units' then
    return jsonb_build_object(
      'algorithm_version','ssurgo-map-units-v1',
      'output_schema_version','farm-watch-soils-map-units-v1',
      'source_signature','usda-nrcs-geodata-cg-soils-ssurgo|usda-nrcs-soil-data-access-ssurgo|geometry_query=farm_watch_ssurgo_polygon_v1|attribute_query=farm_watch_ssurgo_mapunit_component_v1'
    );
  elsif p_product_kind='soils-profiles' then
    return jsonb_build_object(
      'algorithm_version','ssurgo-deep-profiles-v1',
      'output_schema_version','farm-watch-soils-profiles-v1',
      'source_signature','usda-nrcs-soil-data-access-ssurgo|query=farm_watch_ssurgo_deep_profile_v1'
    );
  elsif p_product_kind='hydrology' then
    return jsonb_build_object(
      'algorithm_version','authoritative-hydrology-scoped-v3',
      'output_schema_version','farm-watch-hydrology-v1',
      'source_signature','usgs-3dhp-mapserver-50-flowline-buffer_m=1000|usgs-3dhp-mapserver-60-waterbody-buffer_m=3000|usfws-nwi-mapserver-0-wetland-buffer_m=3000|normalization=farm_watch_hydrology_v1'
    );
  elsif p_product_kind='landscape-domain' then
    return jsonb_build_object(
      'algorithm_version','barrier-aware-landscape-domain-v3',
      'output_schema_version','farm-watch-landscape-domain-v1',
      'source_signature','zones_m=500,1500,3000|hard_barrier=matched_3dhp_named_flowline_to_intersecting_river_waterbody|fallback_flowline_buffer_m=30|component_rule=intersects_property|nesting=child_absorbed_into_parent_exact'
    );
  elsif p_product_kind='land' then
    return jsonb_build_object(
      'algorithm_version','farm-watch-land-context-v6',
      'output_schema_version','farm-watch-land-context-v1',
      'source_signature','kgs-24k-geology|kgs-lithology|kgs-sinkholes|ky-huc12|kyfromabove-phase3-dem|nlcd-tcc-v2025-6|science-tcc-v2025-6|science-tcc-se-v2025-6|physical-synthesis-v1'
    );
  elsif p_product_kind='environment' then
    return jsonb_build_object(
      'algorithm_version','farm-watch-environment-context-v1',
      'output_schema_version','farm-watch-environment-context-v1',
      'source_signature','daymet-daily-single-pixel|usgs-daily-values-nearest-gauge|usdm-county-weekly|soil-moisture-unresolved'
    );
  elsif p_product_kind='regulatory-static' then
    return jsonb_build_object(
      'algorithm_version','farm-watch-regulatory-static-v1',
      'output_schema_version','farm-watch-regulatory-static-v1',
      'source_signature','franklin-zoning|future-land-use|fema-nfhl|pad-us|kdfwr-deer-regulations|kentucky-drone-wildlife-rules'
    );
  elsif p_product_kind='regulatory-faa' then
    return jsonb_build_object(
      'algorithm_version','farm-watch-regulatory-faa-v1',
      'output_schema_version','farm-watch-regulatory-faa-v1',
      'source_signature','faa-airspace-awareness|uas-facility-map|national-security|special-use-airspace|airports|stadiums|tfr'
    );
  end if;
  raise exception 'unsupported Farm Watch context product: %', p_product_kind;
end;
$$;

revoke all on function farm_watch.farm_watch_context_contract_v1(text) from public,anon,authenticated;
grant execute on function farm_watch.farm_watch_context_contract_v1(text) to postgres,service_role;

create or replace function farm_watch.farm_watch_refresh_landscape_domain_v1_internal(
  p_slug text
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,farm_watch,extensions
as $$
declare
  v_property_id uuid;
  v_boundary extensions.geometry;
  v_hydrology_identity text;
  v_hydrology_current boolean;
  v_hydrology_buffer integer;
  v_hydrology_source_status jsonb;
  v_barrier_hydrology_available boolean;
  v_rule_count integer;
  v_resolved_rule_count integer;
  v_barrier extensions.geometry;
  v_barrier_context jsonb;
  v_local_raw extensions.geometry;
  v_landscape_raw extensions.geometry;
  v_local extensions.geometry;
  v_landscape extensions.geometry;
  v_broad extensions.geometry;
  v_identity jsonb;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service_role required';
  end if;

  select id,boundary into v_property_id,v_boundary
  from farm_watch.properties
  where slug=p_slug and status='active' and boundary is not null
  limit 1;

  if v_property_id is null then
    return jsonb_build_object('status','unavailable','reason','active property boundary unavailable');
  end if;

  v_hydrology_identity := farm_watch.farm_watch_context_identity_v1(v_property_id,'hydrology')->>'identity_sha256';

  select
    exists(
      select 1 from farm_watch.hydrology_refresh_state_v1
      where property_id=v_property_id and identity_sha256=v_hydrology_identity
    ),
    coalesce(max(buffer_m),0),
    coalesce((array_agg(source_status order by retrieved_at desc))[1],'{}'::jsonb)
  into v_hydrology_current,v_hydrology_buffer,v_hydrology_source_status
  from farm_watch.hydrology_refresh_state_v1
  where property_id=v_property_id;

  v_barrier_hydrology_available :=
    coalesce(v_hydrology_source_status->>'flowline','')='available'
    and coalesce(v_hydrology_source_status->>'waterbody','')='available';

  if not v_hydrology_current or v_hydrology_buffer < 3000 or not v_barrier_hydrology_available then
    return jsonb_build_object(
      'status','unavailable',
      'reason','current 3000 m USGS 3DHP flowline and waterbody context required',
      'hydrology_identity_current',v_hydrology_current,
      'hydrology_buffer_m',v_hydrology_buffer,
      'hydrology_source_status',v_hydrology_source_status
    );
  end if;

  select count(*) into v_rule_count
  from farm_watch.property_landscape_barrier_rules_v1
  where property_id=v_property_id and active and permeability=0;

  with rules as (
    select *
    from farm_watch.property_landscape_barrier_rules_v1
    where property_id=v_property_id and active and permeability=0
  ),
  lines as (
    select
      r.barrier_label,
      h.source_feature_id,
      h.geometry
    from rules r
    join farm_watch.property_hydrology_features_v1 h
      on h.property_id=r.property_id
     and h.source_slug=r.source_slug
     and h.feature_kind=r.source_feature_kind
     and lower(coalesce(h.properties->>r.source_property_key,''))=lower(r.source_property_value)
  ),
  bodies as (
    select distinct
      l.barrier_label,
      h.source_feature_id,
      h.geometry
    from lines l
    join farm_watch.property_hydrology_features_v1 h
      on h.property_id=v_property_id
     and h.source_slug='usgs-3dhp'
     and h.feature_kind='waterbody'
     and lower(coalesce(h.properties->>'feature_type',''))='river'
     and (
       extensions.st_intersects(h.geometry,l.geometry)
       or extensions.st_dwithin(h.geometry::extensions.geography,l.geometry::extensions.geography,25)
     )
  ),
  line_union as (
    select barrier_label,
           extensions.st_unaryunion(extensions.st_collect(geometry)) geom,
           jsonb_agg(source_feature_id order by source_feature_id) ids
    from lines group by barrier_label
  ),
  body_union as (
    select barrier_label,
           extensions.st_unaryunion(extensions.st_collect(geometry)) geom,
           jsonb_agg(source_feature_id order by source_feature_id) ids
    from bodies group by barrier_label
  ),
  resolved as (
    select
      r.barrier_label,
      r.evidence_class,
      r.rationale,
      r.permeability,
      lu.ids flowline_ids,
      bu.ids waterbody_ids,
      case
        when bu.geom is not null then bu.geom
        when lu.geom is not null then (extensions.st_buffer(lu.geom::extensions.geography,30))::extensions.geometry
        else null
      end geom
    from rules r
    left join line_union lu on lu.barrier_label=r.barrier_label
    left join body_union bu on bu.barrier_label=r.barrier_label
  )
  select
    count(*) filter(where geom is not null),
    extensions.st_multi(
      extensions.st_collectionextract(
        extensions.st_unaryunion(extensions.st_collect(geom)),
        3
      )
    ),
    coalesce(
      jsonb_agg(
        jsonb_strip_nulls(jsonb_build_object(
          'barrier_label',barrier_label,
          'barrier_class','major_river',
          'permeability',permeability,
          'evidence_class',evidence_class,
          'rationale',rationale,
          'matched_flowline_ids',flowline_ids,
          'matched_waterbody_ids',waterbody_ids,
          'resolution',case
            when waterbody_ids is not null then 'intersecting_3dhp_river_waterbody'
            when flowline_ids is not null then '30m_flowline_fallback'
            else 'unresolved'
          end
        ))
        order by barrier_label
      ),
      '[]'::jsonb
    )
  into v_resolved_rule_count,v_barrier,v_barrier_context
  from resolved;

  if v_resolved_rule_count < v_rule_count then
    insert into farm_watch.property_landscape_domains_v1(
      property_id,status,barrier_context,boundary_sha256,source_signature,source_signature_sha256,
      algorithm_version,output_schema_version,identity_sha256,retrieved_at,last_error,updated_at
    )
    select
      v_property_id,'unavailable',v_barrier_context,
      i->>'boundary_sha256',i->>'source_signature',i->>'source_signature_sha256',
      i->>'algorithm_version',i->>'output_schema_version',i->>'identity_sha256',
      now(),'one or more hard barrier rules could not be resolved',now()
    from (select farm_watch.farm_watch_context_identity_v1(v_property_id,'landscape-domain') i) s
    on conflict(property_id) do update set
      status=excluded.status,
      local_500m=null,
      landscape_1500m=null,
      broad_3000m=null,
      barrier_geometry=excluded.barrier_geometry,
      barrier_context=excluded.barrier_context,
      boundary_sha256=excluded.boundary_sha256,
      source_signature=excluded.source_signature,
      source_signature_sha256=excluded.source_signature_sha256,
      algorithm_version=excluded.algorithm_version,
      output_schema_version=excluded.output_schema_version,
      identity_sha256=excluded.identity_sha256,
      retrieved_at=excluded.retrieved_at,
      last_error=excluded.last_error,
      updated_at=now();

    return jsonb_build_object(
      'status','unavailable',
      'reason','hard barrier rule unresolved',
      'rules_expected',v_rule_count,
      'rules_resolved',v_resolved_rule_count,
      'barriers',v_barrier_context
    );
  end if;

  v_broad := farm_watch.farm_watch_barrier_aware_buffer_v1(v_boundary,v_barrier,3000);
  v_landscape_raw := farm_watch.farm_watch_barrier_aware_buffer_v1(v_boundary,v_barrier,1500);
  v_local_raw := farm_watch.farm_watch_barrier_aware_buffer_v1(v_boundary,v_barrier,500);

  if v_local_raw is null or v_landscape_raw is null or v_broad is null then
    return jsonb_build_object('status','unavailable','reason','landscape domain geometry could not be derived');
  end if;

  v_landscape := extensions.st_multi(
    extensions.st_collectionextract(
      extensions.st_makevalid(
        extensions.st_intersection(v_landscape_raw,v_broad)
      ),
      3
    )
  );

  v_local := extensions.st_multi(
    extensions.st_collectionextract(
      extensions.st_makevalid(
        extensions.st_intersection(v_local_raw,v_landscape)
      ),
      3
    )
  );

  -- Absorb each child into its parent. The added polygon area is expected to be
  -- effectively zero and exists only to eliminate sub-dimensional topology noise.
  v_landscape := extensions.st_multi(
    extensions.st_collectionextract(
      extensions.st_unaryunion(extensions.st_collect(v_landscape,v_local)),
      3
    )
  );

  v_broad := extensions.st_multi(
    extensions.st_collectionextract(
      extensions.st_unaryunion(extensions.st_collect(v_broad,v_landscape)),
      3
    )
  );

  if v_local is null or extensions.st_isempty(v_local)
     or v_landscape is null or extensions.st_isempty(v_landscape)
     or v_broad is null or extensions.st_isempty(v_broad) then
    return jsonb_build_object('status','unavailable','reason','nested landscape domain geometry could not be derived');
  end if;

  if not extensions.st_coveredby(v_local,v_landscape)
     or not extensions.st_coveredby(v_landscape,v_broad) then
    return jsonb_build_object(
      'status','unavailable',
      'reason','landscape domain nesting invariant failed'
    );
  end if;

  v_identity := farm_watch.farm_watch_context_identity_v1(v_property_id,'landscape-domain');

  insert into farm_watch.property_landscape_domains_v1(
    property_id,status,local_500m,landscape_1500m,broad_3000m,barrier_geometry,barrier_context,
    boundary_sha256,source_signature,source_signature_sha256,algorithm_version,output_schema_version,
    identity_sha256,retrieved_at,last_error,updated_at
  ) values (
    v_property_id,'available',v_local,v_landscape,v_broad,v_barrier,v_barrier_context,
    v_identity->>'boundary_sha256',v_identity->>'source_signature',v_identity->>'source_signature_sha256',
    v_identity->>'algorithm_version',v_identity->>'output_schema_version',
    v_identity->>'identity_sha256',now(),null,now()
  )
  on conflict(property_id) do update set
    status=excluded.status,
    local_500m=excluded.local_500m,
    landscape_1500m=excluded.landscape_1500m,
    broad_3000m=excluded.broad_3000m,
    barrier_geometry=excluded.barrier_geometry,
    barrier_context=excluded.barrier_context,
    boundary_sha256=excluded.boundary_sha256,
    source_signature=excluded.source_signature,
    source_signature_sha256=excluded.source_signature_sha256,
    algorithm_version=excluded.algorithm_version,
    output_schema_version=excluded.output_schema_version,
    identity_sha256=excluded.identity_sha256,
    retrieved_at=excluded.retrieved_at,
    last_error=null,
    updated_at=now();

  return jsonb_build_object(
    'status','available',
    'identity_sha256',v_identity->>'identity_sha256',
    'zones_m',jsonb_build_array(500,1500,3000),
    'nested_exact',true,
    'nesting_verified',true,
    'hard_barrier_count',v_rule_count,
    'barriers',v_barrier_context,
    'retrieved_at',now()
  );
end;
$$;

revoke all on function farm_watch.farm_watch_refresh_landscape_domain_v1_internal(text) from public,anon,authenticated;
grant execute on function farm_watch.farm_watch_refresh_landscape_domain_v1_internal(text) to service_role;
