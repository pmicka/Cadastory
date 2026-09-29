begin;

CREATE OR REPLACE FUNCTION farm_watch.farm_watch_source_signature_value_v1(p_signature text, p_key text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
  select nullif(substring(token from char_length(p_key) + 2), '')
  from unnest(string_to_array(coalesce(p_signature, ''), '|')) as token
  where token like p_key || '=%'
  limit 1;
$function$


CREATE OR REPLACE FUNCTION farm_watch.farm_watch_get_current_materialization_ref_v1_internal(p_property_id uuid, p_product_kind text, p_as_of_date date DEFAULT CURRENT_DATE, p_as_of_at timestamp with time zone DEFAULT now(), p_depth integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'farm_watch'
AS $function$
declare
  v_slug text;
  v_expected_algorithm text;
  v_expected_schema text;
  v_row farm_watch.property_materializations_v1%rowtype;
  v_latest farm_watch.property_materializations_v1%rowtype;
  v_has_latest boolean := false;
  v_signature text;
  v_reasons jsonb;
  v_domain jsonb;
  v_physical jsonb;
  v_resource jsonb;
  v_dep jsonb;
  v_dep2 jsonb;
  v_forcing jsonb;
  v_token text;
  v_materialization jsonb;
  v_stale_reasons jsonb := '[]'::jsonb;
  v_candidate_seen boolean := false;
begin
  if p_property_id is null or p_product_kind is null or p_as_of_date is null or p_as_of_at is null then
    return jsonb_build_object(
      'status','unavailable',
      'reason_codes',jsonb_build_array('invalid_freshness_request')
    );
  end if;

  if p_depth > 8 then
    return jsonb_build_object(
      'status','unavailable',
      'reason_codes',jsonb_build_array('dependency_depth_exceeded')
    );
  end if;

  select p.slug into v_slug
  from farm_watch.properties p
  where p.id=p_property_id and p.status='active'
  limit 1;

  if v_slug is null then
    return jsonb_build_object(
      'status','unavailable',
      'reason_codes',jsonb_build_array('property_unavailable')
    );
  end if;

  case p_product_kind
    when 'lidar-source-coverage' then
      v_expected_algorithm := 'kyfromabove-stac-coverage-plan-v1';
      v_expected_schema := 'lidar-source-coverage-v1';
    when 'lidar-physical-structure' then
      v_expected_algorithm := 'phase3-copc-physical-v3-multiasset';
      v_expected_schema := 'lidar-physical-structure-v1';
    when 'study-aligned-vegetation-height-context' then
      v_expected_algorithm := 'wiemers-first-return-minus-ground-local500m-v1';
      v_expected_schema := 'study-aligned-vegetation-height-context-v2';
    when 'landscape-structure-context' then
      v_expected_algorithm := 'local500m-phase3-lidar-2024-leafoff-structure-v1';
      v_expected_schema := 'landscape-structure-context-v1';
    when 'terrain-form-permeability' then
      v_expected_algorithm := 'barrier-aware-phase3-dem-terrain-form-permeability-v1';
      v_expected_schema := 'terrain-form-permeability-v1';
    when 'spatial-edge-patch-context' then
      v_expected_algorithm := 'local500m-canopy-field-structure-pattern-v1';
      v_expected_schema := 'spatial-edge-patch-context-v1';
    when 'solar-terrain-context' then
      v_expected_algorithm := 'terrain-horizon-canopy-context-v3';
      v_expected_schema := 'solar-terrain-context-v1';
    when 'solar-exposure-context' then
      v_expected_algorithm := 'terrain-canopy-potential-solar-exposure-v1';
      v_expected_schema := 'solar-exposure-context-v1';
    when 'thermal-exposure-context' then
      v_expected_algorithm := 'hrrr-solar-component-context-v1';
      v_expected_schema := 'thermal-exposure-context-v1';
    when 'horizontal-visibility-context' then
      v_expected_algorithm := 'barrier-aware-local500m-horizontal-visibility-v1';
      v_expected_schema := 'horizontal-visibility-context-v1';
    when 'mast-capacity' then
      v_expected_algorithm := 'bigmap2018-species-biomass-broad3000-v2';
      v_expected_schema := 'mast-capacity-v1';
    else
      return jsonb_build_object(
        'status','unavailable',
        'reason_codes',jsonb_build_array('unsupported_product_contract'),
        'product_kind',p_product_kind
      );
  end case;

  select m.* into v_latest
  from farm_watch.property_materializations_v1 m
  where m.property_id=p_property_id
    and m.product_kind=p_product_kind
    and m.completed_at is not null
  order by m.completed_at desc,m.created_at desc
  limit 1;
  v_has_latest := found;

  for v_row in
    select m.*
    from farm_watch.property_materializations_v1 m
    where m.property_id=p_property_id
      and m.product_kind=p_product_kind
      and m.algorithm_version=v_expected_algorithm
      and m.output_schema_version=v_expected_schema
      and m.completed_at is not null
    order by m.completed_at desc,m.created_at desc
  loop
    v_candidate_seen := true;
    v_reasons := '[]'::jsonb;
    v_signature := coalesce(v_row.source_provenance->>'source_signature','');

    if v_row.expires_at is not null and v_row.expires_at <= now() then
      v_reasons := v_reasons || jsonb_build_array('expired');
    end if;

    if jsonb_array_length(v_reasons)=0 then
      case p_product_kind
        when 'lidar-source-coverage' then
          null;

        when 'lidar-physical-structure' then
          v_dep := farm_watch.farm_watch_get_current_materialization_ref_v1_internal(
            p_property_id,'lidar-source-coverage',p_as_of_date,p_as_of_at,p_depth+1
          );
          if coalesce(v_dep->>'status','unavailable') <> 'available' then
            v_reasons := v_reasons || jsonb_build_array('lidar_source_dependency_unavailable');
          elsif coalesce(
              v_row.source_provenance->>'source_plan_artifact_sha256',
              v_row.source_provenance#>>'{source_descriptor,source_plan_artifact_sha256}'
            ) is distinct from v_dep#>>'{materialization,artifact_sha256}' then
            v_reasons := v_reasons || jsonb_build_array('lidar_source_artifact_changed');
          end if;

        when 'study-aligned-vegetation-height-context' then
          v_domain := farm_watch.farm_watch_get_landscape_domain_v1_internal(v_slug);
          if coalesce(v_domain->>'status','unavailable') <> 'available' then
            v_reasons := v_reasons || jsonb_build_array('landscape_domain_unavailable');
          elsif coalesce(
              farm_watch.farm_watch_source_signature_value_v1(v_signature,'landscape_domain_identity_sha256'),
              v_row.source_provenance#>>'{landscape_domain_identity,identity_sha256}'
            ) is distinct from v_domain#>>'{identity,identity_sha256}' then
            v_reasons := v_reasons || jsonb_build_array('landscape_domain_changed');
          end if;

        when 'landscape-structure-context' then
          v_domain := farm_watch.farm_watch_get_landscape_domain_v1_internal(v_slug);
          if coalesce(v_domain->>'status','unavailable') <> 'available' then
            v_reasons := v_reasons || jsonb_build_array('landscape_domain_unavailable');
          elsif coalesce(
              farm_watch.farm_watch_source_signature_value_v1(v_signature,'landscape_domain_identity_sha256'),
              v_row.source_provenance->>'landscape_domain_identity_sha256',
              v_row.source_provenance#>>'{landscape_domain_identity,identity_sha256}'
            ) is distinct from v_domain#>>'{identity,identity_sha256}' then
            v_reasons := v_reasons || jsonb_build_array('landscape_domain_changed');
          end if;

        when 'terrain-form-permeability' then
          v_domain := farm_watch.farm_watch_get_landscape_domain_v1_internal(v_slug);
          v_physical := farm_watch.farm_watch_get_landscape_physical_context_v1_internal(v_slug);
          if coalesce(v_domain->>'status','unavailable') <> 'available' then
            v_reasons := v_reasons || jsonb_build_array('landscape_domain_unavailable');
          elsif farm_watch.farm_watch_source_signature_value_v1(v_signature,'landscape_domain_identity_sha256')
                is distinct from v_domain#>>'{identity,identity_sha256}' then
            v_reasons := v_reasons || jsonb_build_array('landscape_domain_changed');
          end if;
          if coalesce(v_physical->>'status','unavailable') <> 'available' then
            v_reasons := v_reasons || jsonb_build_array('landscape_physical_unavailable');
          elsif farm_watch.farm_watch_source_signature_value_v1(v_signature,'landscape_physical_identity_sha256')
                is distinct from v_physical#>>'{identity,identity_sha256}' then
            v_reasons := v_reasons || jsonb_build_array('landscape_physical_changed');
          end if;

        when 'spatial-edge-patch-context' then
          v_domain := farm_watch.farm_watch_get_landscape_domain_v1_internal(v_slug);
          v_physical := farm_watch.farm_watch_get_landscape_physical_context_v1_internal(v_slug);
          v_resource := farm_watch.farm_watch_get_resource_edge_context_v1_internal(v_slug,false);
          v_dep := farm_watch.farm_watch_get_current_materialization_ref_v1_internal(
            p_property_id,'landscape-structure-context',p_as_of_date,p_as_of_at,p_depth+1
          );
          if coalesce(v_domain->>'status','unavailable') <> 'available' then
            v_reasons := v_reasons || jsonb_build_array('landscape_domain_unavailable');
          elsif farm_watch.farm_watch_source_signature_value_v1(v_signature,'landscape_domain_identity_sha256')
                is distinct from v_domain#>>'{identity,identity_sha256}' then
            v_reasons := v_reasons || jsonb_build_array('landscape_domain_changed');
          end if;
          if coalesce(v_physical->>'status','unavailable') <> 'available' then
            v_reasons := v_reasons || jsonb_build_array('landscape_physical_unavailable');
          elsif farm_watch.farm_watch_source_signature_value_v1(v_signature,'landscape_physical_identity_sha256')
                is distinct from v_physical#>>'{identity,identity_sha256}' then
            v_reasons := v_reasons || jsonb_build_array('landscape_physical_changed');
          end if;
          if coalesce(v_resource->>'status','unavailable') <> 'available' then
            v_reasons := v_reasons || jsonb_build_array('resource_edge_unavailable');
          elsif farm_watch.farm_watch_source_signature_value_v1(v_signature,'resource_edge_identity_sha256')
                is distinct from v_resource#>>'{identity,identity_sha256}' then
            v_reasons := v_reasons || jsonb_build_array('resource_edge_changed');
          end if;
          if coalesce(v_dep->>'status','unavailable') <> 'available' then
            v_reasons := v_reasons || jsonb_build_array('landscape_structure_dependency_unavailable');
          else
            if farm_watch.farm_watch_source_signature_value_v1(v_signature,'landscape_structure_identity_sha256')
                  is distinct from v_dep#>>'{materialization,identity_sha256}' then
              v_reasons := v_reasons || jsonb_build_array('landscape_structure_identity_changed');
            end if;
            if farm_watch.farm_watch_source_signature_value_v1(v_signature,'landscape_structure_artifact_sha256')
                  is distinct from v_dep#>>'{materialization,artifact_sha256}' then
              v_reasons := v_reasons || jsonb_build_array('landscape_structure_artifact_changed');
            end if;
          end if;

        when 'solar-terrain-context' then
          v_dep := farm_watch.farm_watch_get_current_materialization_ref_v1_internal(
            p_property_id,'terrain-form-permeability',p_as_of_date,p_as_of_at,p_depth+1
          );
          v_dep2 := farm_watch.farm_watch_get_current_materialization_ref_v1_internal(
            p_property_id,'spatial-edge-patch-context',p_as_of_date,p_as_of_at,p_depth+1
          );
          if coalesce(v_dep->>'status','unavailable') <> 'available' then
            v_reasons := v_reasons || jsonb_build_array('terrain_form_dependency_unavailable');
          else
            if farm_watch.farm_watch_source_signature_value_v1(v_signature,'terrain_materialization_identity_sha256')
                  is distinct from v_dep#>>'{materialization,identity_sha256}' then
              v_reasons := v_reasons || jsonb_build_array('terrain_form_identity_changed');
            end if;
            if farm_watch.farm_watch_source_signature_value_v1(v_signature,'terrain_artifact_sha256')
                  is distinct from v_dep#>>'{materialization,artifact_sha256}' then
              v_reasons := v_reasons || jsonb_build_array('terrain_form_artifact_changed');
            end if;
          end if;
          if coalesce(v_dep2->>'status','unavailable') <> 'available' then
            v_reasons := v_reasons || jsonb_build_array('spatial_pattern_dependency_unavailable');
          else
            if farm_watch.farm_watch_source_signature_value_v1(v_signature,'spatial_pattern_materialization_identity_sha256')
                  is distinct from v_dep2#>>'{materialization,identity_sha256}' then
              v_reasons := v_reasons || jsonb_build_array('spatial_pattern_identity_changed');
            end if;
            if farm_watch.farm_watch_source_signature_value_v1(v_signature,'spatial_pattern_artifact_sha256')
                  is distinct from v_dep2#>>'{materialization,artifact_sha256}' then
              v_reasons := v_reasons || jsonb_build_array('spatial_pattern_artifact_changed');
            end if;
          end if;

        when 'solar-exposure-context' then
          v_dep := farm_watch.farm_watch_get_current_materialization_ref_v1_internal(
            p_property_id,'solar-terrain-context',p_as_of_date,p_as_of_at,p_depth+1
          );
          if coalesce(v_dep->>'status','unavailable') <> 'available' then
            v_reasons := v_reasons || jsonb_build_array('solar_terrain_dependency_unavailable');
          else
            if farm_watch.farm_watch_source_signature_value_v1(v_signature,'solar_terrain_materialization_identity_sha256')
                  is distinct from v_dep#>>'{materialization,identity_sha256}' then
              v_reasons := v_reasons || jsonb_build_array('solar_terrain_identity_changed');
            end if;
            if farm_watch.farm_watch_source_signature_value_v1(v_signature,'solar_terrain_artifact_sha256')
                  is distinct from v_dep#>>'{materialization,artifact_sha256}' then
              v_reasons := v_reasons || jsonb_build_array('solar_terrain_artifact_changed');
            end if;
          end if;
          if farm_watch.farm_watch_source_signature_value_v1(v_signature,'solar_date')
                is distinct from p_as_of_date::text then
            v_reasons := v_reasons || jsonb_build_array('calendar_date_mismatch');
          end if;

        when 'thermal-exposure-context' then
          v_dep := farm_watch.farm_watch_get_current_materialization_ref_v1_internal(
            p_property_id,'solar-terrain-context',p_as_of_date,p_as_of_at,p_depth+1
          );
          if coalesce(v_dep->>'status','unavailable') <> 'available' then
            v_reasons := v_reasons || jsonb_build_array('solar_terrain_dependency_unavailable');
          else
            if farm_watch.farm_watch_source_signature_value_v1(v_signature,'solar_terrain_materialization_identity_sha256')
                  is distinct from v_dep#>>'{materialization,identity_sha256}' then
              v_reasons := v_reasons || jsonb_build_array('solar_terrain_identity_changed');
            end if;
            if farm_watch.farm_watch_source_signature_value_v1(v_signature,'solar_terrain_artifact_sha256')
                  is distinct from v_dep#>>'{materialization,artifact_sha256}' then
              v_reasons := v_reasons || jsonb_build_array('solar_terrain_artifact_changed');
            end if;
          end if;

          v_forcing := farm_watch.farm_watch_get_meteorological_forcing_v1_internal(
            v_slug,p_as_of_at,180,'analysis'
          );
          if coalesce(v_forcing->>'status','unavailable') <> 'available' then
            v_reasons := v_reasons || jsonb_build_array(
              'meteorological_forcing_' || coalesce(v_forcing->>'status','unavailable')
            );
          else
            if farm_watch.farm_watch_source_signature_value_v1(v_signature,'meteorological_forcing_identity_sha256')
                  is distinct from v_forcing#>>'{identity,identity_sha256}' then
              v_reasons := v_reasons || jsonb_build_array('meteorological_forcing_identity_changed');
            end if;
            v_token := farm_watch.farm_watch_source_signature_value_v1(v_signature,'meteorological_forcing_valid_at');
            if v_token is null or v_token::timestamptz is distinct from (v_forcing->>'valid_at')::timestamptz then
              v_reasons := v_reasons || jsonb_build_array('meteorological_forcing_time_changed');
            end if;
            if farm_watch.farm_watch_source_signature_value_v1(v_signature,'source_index_sha256')
                  is distinct from v_forcing#>>'{identity,source_index_sha256}' then
              v_reasons := v_reasons || jsonb_build_array('meteorological_source_index_changed');
            end if;
            if farm_watch.farm_watch_source_signature_value_v1(v_signature,'source_records_sha256')
                  is distinct from v_forcing#>>'{identity,source_records_sha256}' then
              v_reasons := v_reasons || jsonb_build_array('meteorological_source_records_changed');
            end if;
          end if;

        when 'horizontal-visibility-context' then
          v_domain := farm_watch.farm_watch_get_landscape_domain_v1_internal(v_slug);
          v_dep := farm_watch.farm_watch_get_current_materialization_ref_v1_internal(
            p_property_id,'landscape-structure-context',p_as_of_date,p_as_of_at,p_depth+1
          );
          v_dep2 := farm_watch.farm_watch_get_current_materialization_ref_v1_internal(
            p_property_id,'terrain-form-permeability',p_as_of_date,p_as_of_at,p_depth+1
          );
          if coalesce(v_domain->>'status','unavailable') <> 'available' then
            v_reasons := v_reasons || jsonb_build_array('landscape_domain_unavailable');
          elsif farm_watch.farm_watch_source_signature_value_v1(v_signature,'landscape_domain_identity_sha256')
                is distinct from v_domain#>>'{identity,identity_sha256}' then
            v_reasons := v_reasons || jsonb_build_array('landscape_domain_changed');
          end if;
          if coalesce(v_dep->>'status','unavailable') <> 'available' then
            v_reasons := v_reasons || jsonb_build_array('landscape_structure_dependency_unavailable');
          else
            if farm_watch.farm_watch_source_signature_value_v1(v_signature,'landscape_structure_identity_sha256')
                  is distinct from v_dep#>>'{materialization,identity_sha256}' then
              v_reasons := v_reasons || jsonb_build_array('landscape_structure_identity_changed');
            end if;
            if farm_watch.farm_watch_source_signature_value_v1(v_signature,'landscape_structure_artifact_sha256')
                  is distinct from v_dep#>>'{materialization,artifact_sha256}' then
              v_reasons := v_reasons || jsonb_build_array('landscape_structure_artifact_changed');
            end if;
          end if;
          if coalesce(v_dep2->>'status','unavailable') <> 'available' then
            v_reasons := v_reasons || jsonb_build_array('terrain_form_dependency_unavailable');
          else
            if farm_watch.farm_watch_source_signature_value_v1(v_signature,'terrain_form_identity_sha256')
                  is distinct from v_dep2#>>'{materialization,identity_sha256}' then
              v_reasons := v_reasons || jsonb_build_array('terrain_form_identity_changed');
            end if;
            if farm_watch.farm_watch_source_signature_value_v1(v_signature,'terrain_form_artifact_sha256')
                  is distinct from v_dep2#>>'{materialization,artifact_sha256}' then
              v_reasons := v_reasons || jsonb_build_array('terrain_form_artifact_changed');
            end if;
          end if;

        when 'mast-capacity' then
          v_domain := farm_watch.farm_watch_get_landscape_domain_v1_internal(v_slug);
          if coalesce(v_domain->>'status','unavailable') <> 'available' then
            v_reasons := v_reasons || jsonb_build_array('landscape_domain_unavailable');
          elsif coalesce(
              farm_watch.farm_watch_source_signature_value_v1(v_signature,'landscape_domain_identity_sha256'),
              v_row.source_provenance#>>'{landscape_domain_identity,identity_sha256}'
            ) is distinct from v_domain#>>'{identity,identity_sha256}' then
            v_reasons := v_reasons || jsonb_build_array('landscape_domain_changed');
          end if;
      end case;
    end if;

    if jsonb_array_length(v_reasons)=0 then
      v_materialization := jsonb_strip_nulls(jsonb_build_object(
        'id',v_row.id,
        'product_kind',v_row.product_kind,
        'algorithm_version',v_row.algorithm_version,
        'output_schema_version',v_row.output_schema_version,
        'identity_sha256',v_row.identity_sha256,
        'evidence_class',v_row.evidence_class,
        'summary',v_row.summary,
        'source_provenance',v_row.source_provenance,
        'limitations',v_row.limitations,
        'artifact_bucket',v_row.artifact_bucket,
        'artifact_path',v_row.artifact_path,
        'artifact_format',v_row.artifact_format,
        'artifact_mime_type',v_row.artifact_mime_type,
        'artifact_size_bytes',v_row.artifact_size_bytes,
        'artifact_sha256',v_row.artifact_sha256,
        'completed_at',v_row.completed_at,
        'expires_at',v_row.expires_at
      ));
      return jsonb_build_object(
        'status','available',
        'freshness_contract','dependency-aware-materialization-v1',
        'reason_codes','[]'::jsonb,
        'as_of_date',p_as_of_date,
        'as_of_at',p_as_of_at,
        'materialization',v_materialization
      );
    end if;

    if jsonb_array_length(v_stale_reasons)=0 then
      v_stale_reasons := v_reasons;
    end if;
  end loop;

  if not v_candidate_seen and v_has_latest then
    v_stale_reasons := jsonb_build_array('contract_version_mismatch');
  elsif jsonb_array_length(v_stale_reasons)=0 and v_has_latest then
    v_stale_reasons := jsonb_build_array('no_current_materialization');
  end if;

  if v_has_latest then
    v_materialization := jsonb_strip_nulls(jsonb_build_object(
      'id',v_latest.id,
      'product_kind',v_latest.product_kind,
      'algorithm_version',v_latest.algorithm_version,
      'output_schema_version',v_latest.output_schema_version,
      'identity_sha256',v_latest.identity_sha256,
      'evidence_class',v_latest.evidence_class,
      'summary',v_latest.summary,
      'source_provenance',v_latest.source_provenance,
      'limitations',v_latest.limitations,
      'artifact_bucket',v_latest.artifact_bucket,
      'artifact_path',v_latest.artifact_path,
      'artifact_format',v_latest.artifact_format,
      'artifact_mime_type',v_latest.artifact_mime_type,
      'artifact_size_bytes',v_latest.artifact_size_bytes,
      'artifact_sha256',v_latest.artifact_sha256,
      'completed_at',v_latest.completed_at,
      'expires_at',v_latest.expires_at
    ));
    return jsonb_build_object(
      'status','stale',
      'freshness_contract','dependency-aware-materialization-v1',
      'reason_codes',v_stale_reasons,
      'as_of_date',p_as_of_date,
      'as_of_at',p_as_of_at,
      'materialization',v_materialization
    );
  end if;

  return jsonb_build_object(
    'status','unavailable',
    'freshness_contract','dependency-aware-materialization-v1',
    'reason_codes',jsonb_build_array('not_materialized'),
    'as_of_date',p_as_of_date,
    'as_of_at',p_as_of_at,
    'materialization',null
  );
end;
$function$


revoke all on function farm_watch.farm_watch_source_signature_value_v1(text,text)
  from public,anon,authenticated;
grant execute on function farm_watch.farm_watch_source_signature_value_v1(text,text)
  to service_role;

revoke all on function farm_watch.farm_watch_get_current_materialization_ref_v1_internal(uuid,text,date,timestamptz,integer)
  from public,anon,authenticated;
grant execute on function farm_watch.farm_watch_get_current_materialization_ref_v1_internal(uuid,text,date,timestamptz,integer)
  to service_role;

comment on function farm_watch.farm_watch_get_current_materialization_ref_v1_internal(uuid,text,date,timestamptz,integer) is
'Resolves the current Farm Watch materialization for a product by contract version, expiry, source/dependency identities, and requested date/time. Historical artifacts remain persisted but do not become current merely because their retention expiration is in the future.';

commit;
