begin;

create or replace function farm_watch.farm_watch_materialization_dependency_registry_v1()
returns jsonb
language sql
immutable
set search_path = 'pg_catalog'
as $$
  select $registry${"registry_version":"farm-watch-materialization-dependency-registry-v1","manifest_schema":"farm-watch-materialization-dependency-manifest-v1","p0_1_external_resolution":"contract_only","external_sources":[{"key":"external:kyfromabove-phase3-dem","authority":"Kentucky Division of Geographic Information / KyFromAbove","source_kind":"arcgis-imageserver","contract_seed":"kyfromabove-phase3-dem|service=Ky_DEM_KYAPED_2FT_Phase3_WGS84WM|provider_revision=unresolved","resolution_status":"contract_only","authoritative":false},{"key":"external:kyfromabove-lidar-stac","authority":"Kentucky Division of Geographic Information / KyFromAbove","source_kind":"stac","contract_seed":"kyfromabove-lidar-stac|collections=laz-phase3,laz-phase2|selection=all-intersecting-usable-item-footprints|provider_revision=unresolved","resolution_status":"contract_only","authoritative":false},{"key":"external:kyfromabove-phase3-copc","authority":"Kentucky Division of Geographic Information / KyFromAbove","source_kind":"copc-assets","contract_seed":"kyfromabove-phase3-copc|collection=laz-phase3|asset_selection=stac-current|provider_revision=unresolved","resolution_status":"contract_only","authoritative":false},{"key":"external:kyfromabove-phase3-imagery-2024","authority":"Kentucky Division of Geographic Information / KyFromAbove","source_kind":"arcgis-imagery-pair","contract_seed":"kyfromabove-phase3-imagery-2024|rgb=Ky_KYAPED_Phase3_3IN_WGS84WM|ir=Ky_KYAPED_Phase3_3IN_IR|acquisition=2024-02-14|provider_revision=unresolved","resolution_status":"contract_only","authoritative":false},{"key":"external:kyfromabove-phase2-imagery-2019","authority":"Kentucky Division of Geographic Information / KyFromAbove","source_kind":"arcgis-imagery-pair","contract_seed":"kyfromabove-phase2-imagery-2019|rgb=Ky_KYAPED_Phase2_6IN_WGS84WM|ir=Ky_KYAPED_Phase2_6IN_IR|acquisition=2019-03-27|provider_revision=unresolved","resolution_status":"contract_only","authoritative":false},{"key":"external:nlcd-tcc-v2025-6","authority":"USGS / MRLC / NLCD Tree Canopy Cover","source_kind":"arcgis-imageserver","contract_seed":"nlcd-tcc-v2025-6|year=2025|source=USFS_EDW_NLCD_TCC_CONUS|provider_revision=release-label-only","resolution_status":"contract_only","authoritative":false},{"key":"external:usgs-3dep-dynamic","authority":"USGS 3D Elevation Program","source_kind":"arcgis-imageserver","contract_seed":"usgs-3dep-dynamic|service=3DEPElevation|role=solar-horizon-fallback|provider_revision=unresolved","resolution_status":"contract_only","authoritative":false},{"key":"external:fia-bigmap-2018-species-biomass","authority":"USDA Forest Service FIA","source_kind":"arcgis-imageserver","contract_seed":"fia-bigmap-2018-species-biomass|year=2018|metric=live-tree-aboveground-biomass|provider_revision=fixed-release-label","resolution_status":"contract_only","authoritative":false}],"products":[{"product_kind":"terrain-analysis","algorithm_version":"phase3-dem-61x61-conditioned-flow-v2","output_schema_version":"terrain-analysis-v2","dependencies":[{"key":"external:kyfromabove-phase3-dem","kind":"external","resolver":"external-contract-v1","required":true,"unavailable_reason":"kyfromabove_phase3_dem_unavailable","comparisons":[{"current_field":"identity_sha256","recorded":{"source":"external_contract"},"reason":"kyfromabove_phase3_dem_identity_changed"}]}]},{"product_kind":"lidar-source-coverage","algorithm_version":"kyfromabove-stac-coverage-plan-v1","output_schema_version":"lidar-source-coverage-v1","dependencies":[{"key":"external:kyfromabove-lidar-stac","kind":"external","resolver":"external-contract-v1","required":true,"unavailable_reason":"kyfromabove_lidar_stac_unavailable","comparisons":[{"current_field":"identity_sha256","recorded":{"source":"external_contract"},"reason":"kyfromabove_lidar_stac_identity_changed"}]}]},{"product_kind":"lidar-physical-structure","algorithm_version":"phase3-copc-physical-v3-multiasset","output_schema_version":"lidar-physical-structure-v1","dependencies":[{"key":"materialization:lidar-source-coverage","kind":"materialization","resolver":"materialization-ref-v1","product_kind":"lidar-source-coverage","required":true,"unavailable_reason":"lidar_source_dependency_unavailable","comparisons":[{"current_field":"artifact_sha256","recorded":{"source":"provenance","path":["source_plan_artifact_sha256"]},"reason":"lidar_source_artifact_changed","normalizer":"text"}]},{"key":"external:kyfromabove-phase3-copc","kind":"external","resolver":"external-contract-v1","required":true,"unavailable_reason":"kyfromabove_phase3_copc_unavailable","comparisons":[{"current_field":"identity_sha256","recorded":{"source":"external_contract"},"reason":"kyfromabove_phase3_copc_identity_changed"}]}]},{"product_kind":"leaf-off-woody-structure","algorithm_version":"leaf_off_structure_v1_2_7m","output_schema_version":"leaf-off-woody-structure-v1","dependencies":[{"key":"external:kyfromabove-phase3-imagery-2024","kind":"external","resolver":"external-contract-v1","required":true,"unavailable_reason":"kyfromabove_phase3_imagery_2024_unavailable","comparisons":[{"current_field":"identity_sha256","recorded":{"source":"external_contract"},"reason":"kyfromabove_phase3_imagery_2024_identity_changed"}]},{"key":"external:kyfromabove-phase2-imagery-2019","kind":"external","resolver":"external-contract-v1","required":true,"unavailable_reason":"kyfromabove_phase2_imagery_2019_unavailable","comparisons":[{"current_field":"identity_sha256","recorded":{"source":"external_contract"},"reason":"kyfromabove_phase2_imagery_2019_identity_changed"}]},{"key":"external:kyfromabove-phase3-dem","kind":"external","resolver":"external-contract-v1","required":true,"unavailable_reason":"kyfromabove_phase3_dem_unavailable","comparisons":[{"current_field":"identity_sha256","recorded":{"source":"external_contract"},"reason":"kyfromabove_phase3_dem_identity_changed"}]}]},{"product_kind":"structure-complementarity","algorithm_version":"current-leaf-off-lidar-complementarity-v4","output_schema_version":"structure-complementarity-v1","dependencies":[{"key":"materialization:lidar-physical-structure","kind":"materialization","resolver":"materialization-ref-v1","product_kind":"lidar-physical-structure","required":true,"unavailable_reason":"lidar_physical_dependency_unavailable","comparisons":[{"current_field":"artifact_sha256","recorded":{"source":"signature","key":"lidar_physical_artifact_sha256"},"reason":"lidar_physical_artifact_changed","normalizer":"text"}]},{"key":"materialization:leaf-off-woody-structure","kind":"materialization","resolver":"materialization-ref-v1","product_kind":"leaf-off-woody-structure","required":true,"unavailable_reason":"leaf_off_dependency_unavailable","comparisons":[{"current_field":"artifact_sha256","recorded":{"source":"signature","key":"leaf_off_artifact_sha256"},"reason":"leaf_off_artifact_changed","normalizer":"text"}]}]},{"product_kind":"landscape-structure-context","algorithm_version":"local500m-phase3-lidar-2024-leafoff-structure-v1","output_schema_version":"landscape-structure-context-v1","dependencies":[{"key":"context:landscape-domain","kind":"context","resolver":"farm-watch-context-v1","context_kind":"landscape-domain","required":true,"unavailable_reason":"landscape_domain_unavailable","comparisons":[{"current_field":"identity_sha256","recorded":{"source":"signature","key":"landscape_domain_identity_sha256"},"reason":"landscape_domain_changed"}]},{"key":"external:kyfromabove-lidar-stac","kind":"external","resolver":"external-contract-v1","required":true,"unavailable_reason":"kyfromabove_lidar_stac_unavailable","comparisons":[{"current_field":"identity_sha256","recorded":{"source":"external_contract"},"reason":"kyfromabove_lidar_stac_identity_changed"}]},{"key":"external:kyfromabove-phase3-copc","kind":"external","resolver":"external-contract-v1","required":true,"unavailable_reason":"kyfromabove_phase3_copc_unavailable","comparisons":[{"current_field":"identity_sha256","recorded":{"source":"external_contract"},"reason":"kyfromabove_phase3_copc_identity_changed"}]},{"key":"external:kyfromabove-phase3-imagery-2024","kind":"external","resolver":"external-contract-v1","required":true,"unavailable_reason":"kyfromabove_phase3_imagery_2024_unavailable","comparisons":[{"current_field":"identity_sha256","recorded":{"source":"external_contract"},"reason":"kyfromabove_phase3_imagery_2024_identity_changed"}]},{"key":"external:kyfromabove-phase3-dem","kind":"external","resolver":"external-contract-v1","required":true,"unavailable_reason":"kyfromabove_phase3_dem_unavailable","comparisons":[{"current_field":"identity_sha256","recorded":{"source":"external_contract"},"reason":"kyfromabove_phase3_dem_identity_changed"}]}]},{"product_kind":"study-aligned-vegetation-height-context","algorithm_version":"wiemers-first-return-minus-ground-local500m-v1","output_schema_version":"study-aligned-vegetation-height-context-v2","dependencies":[{"key":"context:landscape-domain","kind":"context","resolver":"farm-watch-context-v1","context_kind":"landscape-domain","required":true,"unavailable_reason":"landscape_domain_unavailable","comparisons":[{"current_field":"identity_sha256","recorded":{"source":"signature","key":"landscape_domain_identity_sha256"},"reason":"landscape_domain_changed"}]},{"key":"external:kyfromabove-lidar-stac","kind":"external","resolver":"external-contract-v1","required":true,"unavailable_reason":"kyfromabove_lidar_stac_unavailable","comparisons":[{"current_field":"identity_sha256","recorded":{"source":"external_contract"},"reason":"kyfromabove_lidar_stac_identity_changed"}]},{"key":"external:kyfromabove-phase3-copc","kind":"external","resolver":"external-contract-v1","required":true,"unavailable_reason":"kyfromabove_phase3_copc_unavailable","comparisons":[{"current_field":"identity_sha256","recorded":{"source":"external_contract"},"reason":"kyfromabove_phase3_copc_identity_changed"}]}]},{"product_kind":"terrain-form-permeability","algorithm_version":"barrier-aware-phase3-dem-terrain-form-permeability-v1","output_schema_version":"terrain-form-permeability-v1","dependencies":[{"key":"context:landscape-domain","kind":"context","resolver":"farm-watch-context-v1","context_kind":"landscape-domain","required":true,"unavailable_reason":"landscape_domain_unavailable","comparisons":[{"current_field":"identity_sha256","recorded":{"source":"signature","key":"landscape_domain_identity_sha256"},"reason":"landscape_domain_changed"}]},{"key":"context:landscape-physical","kind":"context","resolver":"farm-watch-context-v1","context_kind":"landscape-physical","required":true,"unavailable_reason":"landscape_physical_unavailable","comparisons":[{"current_field":"identity_sha256","recorded":{"source":"signature","key":"landscape_physical_identity_sha256"},"reason":"landscape_physical_changed"}]},{"key":"external:kyfromabove-phase3-dem","kind":"external","resolver":"external-contract-v1","required":true,"unavailable_reason":"kyfromabove_phase3_dem_unavailable","comparisons":[{"current_field":"identity_sha256","recorded":{"source":"external_contract"},"reason":"kyfromabove_phase3_dem_identity_changed"}]}]},{"product_kind":"spatial-edge-patch-context","algorithm_version":"local500m-canopy-field-structure-pattern-v1","output_schema_version":"spatial-edge-patch-context-v1","dependencies":[{"key":"context:landscape-domain","kind":"context","resolver":"farm-watch-context-v1","context_kind":"landscape-domain","required":true,"unavailable_reason":"landscape_domain_unavailable","comparisons":[{"current_field":"identity_sha256","recorded":{"source":"signature","key":"landscape_domain_identity_sha256"},"reason":"landscape_domain_changed"}]},{"key":"context:landscape-physical","kind":"context","resolver":"farm-watch-context-v1","context_kind":"landscape-physical","required":true,"unavailable_reason":"landscape_physical_unavailable","comparisons":[{"current_field":"identity_sha256","recorded":{"source":"signature","key":"landscape_physical_identity_sha256"},"reason":"landscape_physical_changed"}]},{"key":"context:resource-edge","kind":"context","resolver":"farm-watch-context-v1","context_kind":"resource-edge","required":true,"unavailable_reason":"resource_edge_unavailable","comparisons":[{"current_field":"identity_sha256","recorded":{"source":"signature","key":"resource_edge_identity_sha256"},"reason":"resource_edge_changed"}]},{"key":"materialization:landscape-structure-context","kind":"materialization","resolver":"materialization-ref-v1","product_kind":"landscape-structure-context","required":true,"unavailable_reason":"landscape_structure_dependency_unavailable","comparisons":[{"current_field":"identity_sha256","recorded":{"source":"signature","key":"landscape_structure_identity_sha256"},"reason":"landscape_structure_identity_changed","normalizer":"text"},{"current_field":"artifact_sha256","recorded":{"source":"signature","key":"landscape_structure_artifact_sha256"},"reason":"landscape_structure_artifact_changed","normalizer":"text"}]},{"key":"external:nlcd-tcc-v2025-6","kind":"external","resolver":"external-contract-v1","required":true,"unavailable_reason":"nlcd_tcc_v2025_6_unavailable","comparisons":[{"current_field":"identity_sha256","recorded":{"source":"external_contract"},"reason":"nlcd_tcc_v2025_6_identity_changed"}]}]},{"product_kind":"solar-terrain-context","algorithm_version":"terrain-horizon-canopy-context-v3","output_schema_version":"solar-terrain-context-v1","dependencies":[{"key":"materialization:terrain-form-permeability","kind":"materialization","resolver":"materialization-ref-v1","product_kind":"terrain-form-permeability","required":true,"unavailable_reason":"terrain_form_dependency_unavailable","comparisons":[{"current_field":"identity_sha256","recorded":{"source":"signature","key":"terrain_materialization_identity_sha256"},"reason":"terrain_form_identity_changed","normalizer":"text"},{"current_field":"artifact_sha256","recorded":{"source":"signature","key":"terrain_artifact_sha256"},"reason":"terrain_form_artifact_changed","normalizer":"text"}]},{"key":"materialization:spatial-edge-patch-context","kind":"materialization","resolver":"materialization-ref-v1","product_kind":"spatial-edge-patch-context","required":true,"unavailable_reason":"spatial_pattern_dependency_unavailable","comparisons":[{"current_field":"identity_sha256","recorded":{"source":"signature","key":"spatial_pattern_materialization_identity_sha256"},"reason":"spatial_pattern_identity_changed","normalizer":"text"},{"current_field":"artifact_sha256","recorded":{"source":"signature","key":"spatial_pattern_artifact_sha256"},"reason":"spatial_pattern_artifact_changed","normalizer":"text"}]},{"key":"external:kyfromabove-phase3-dem","kind":"external","resolver":"external-contract-v1","required":true,"unavailable_reason":"kyfromabove_phase3_dem_unavailable","comparisons":[{"current_field":"identity_sha256","recorded":{"source":"external_contract"},"reason":"kyfromabove_phase3_dem_identity_changed"}]},{"key":"external:usgs-3dep-dynamic","kind":"external","resolver":"external-contract-v1","required":true,"unavailable_reason":"usgs_3dep_dynamic_unavailable","comparisons":[{"current_field":"identity_sha256","recorded":{"source":"external_contract"},"reason":"usgs_3dep_dynamic_identity_changed"}]},{"key":"external:nlcd-tcc-v2025-6","kind":"external","resolver":"external-contract-v1","required":true,"unavailable_reason":"nlcd_tcc_v2025_6_unavailable","comparisons":[{"current_field":"identity_sha256","recorded":{"source":"external_contract"},"reason":"nlcd_tcc_v2025_6_identity_changed"}]}]},{"product_kind":"solar-exposure-context","algorithm_version":"terrain-canopy-potential-solar-exposure-v1","output_schema_version":"solar-exposure-context-v1","dependencies":[{"key":"materialization:solar-terrain-context","kind":"materialization","resolver":"materialization-ref-v1","product_kind":"solar-terrain-context","required":true,"unavailable_reason":"solar_terrain_dependency_unavailable","comparisons":[{"current_field":"identity_sha256","recorded":{"source":"signature","key":"solar_terrain_materialization_identity_sha256"},"reason":"solar_terrain_identity_changed","normalizer":"text"},{"current_field":"artifact_sha256","recorded":{"source":"signature","key":"solar_terrain_artifact_sha256"},"reason":"solar_terrain_artifact_changed","normalizer":"text"}]},{"key":"temporal:calendar-date","kind":"temporal","resolver":"calendar-date-v1","required":true,"unavailable_reason":"calendar_date_unavailable","comparisons":[{"current_field":"value","recorded":{"source":"signature","key":"solar_date"},"reason":"calendar_date_mismatch","normalizer":"text"}]}]},{"product_kind":"thermal-exposure-context","algorithm_version":"hrrr-solar-component-context-v1","output_schema_version":"thermal-exposure-context-v1","dependencies":[{"key":"materialization:solar-terrain-context","kind":"materialization","resolver":"materialization-ref-v1","product_kind":"solar-terrain-context","required":true,"unavailable_reason":"solar_terrain_dependency_unavailable","comparisons":[{"current_field":"identity_sha256","recorded":{"source":"signature","key":"solar_terrain_materialization_identity_sha256"},"reason":"solar_terrain_identity_changed","normalizer":"text"},{"current_field":"artifact_sha256","recorded":{"source":"signature","key":"solar_terrain_artifact_sha256"},"reason":"solar_terrain_artifact_changed","normalizer":"text"}]},{"key":"state:meteorological-forcing-analysis","kind":"state","resolver":"meteorological-forcing-v1","source_state":"analysis","max_age_minutes":180,"required":true,"unavailable_reason":"meteorological_forcing_unavailable","comparisons":[{"current_field":"identity_sha256","recorded":{"source":"signature","key":"meteorological_forcing_identity_sha256"},"reason":"meteorological_forcing_identity_changed","normalizer":"text"},{"current_field":"valid_at","recorded":{"source":"signature","key":"meteorological_forcing_valid_at"},"reason":"meteorological_forcing_time_changed","normalizer":"timestamptz"},{"current_field":"source_index_sha256","recorded":{"source":"signature","key":"source_index_sha256"},"reason":"meteorological_source_index_changed","normalizer":"text"},{"current_field":"source_records_sha256","recorded":{"source":"signature","key":"source_records_sha256"},"reason":"meteorological_source_records_changed","normalizer":"text"}]}]},{"product_kind":"horizontal-visibility-context","algorithm_version":"barrier-aware-local500m-horizontal-visibility-v1","output_schema_version":"horizontal-visibility-context-v1","dependencies":[{"key":"context:landscape-domain","kind":"context","resolver":"farm-watch-context-v1","context_kind":"landscape-domain","required":true,"unavailable_reason":"landscape_domain_unavailable","comparisons":[{"current_field":"identity_sha256","recorded":{"source":"signature","key":"landscape_domain_identity_sha256"},"reason":"landscape_domain_changed"}]},{"key":"materialization:landscape-structure-context","kind":"materialization","resolver":"materialization-ref-v1","product_kind":"landscape-structure-context","required":true,"unavailable_reason":"landscape_structure_dependency_unavailable","comparisons":[{"current_field":"identity_sha256","recorded":{"source":"signature","key":"landscape_structure_identity_sha256"},"reason":"landscape_structure_identity_changed","normalizer":"text"},{"current_field":"artifact_sha256","recorded":{"source":"signature","key":"landscape_structure_artifact_sha256"},"reason":"landscape_structure_artifact_changed","normalizer":"text"}]},{"key":"materialization:terrain-form-permeability","kind":"materialization","resolver":"materialization-ref-v1","product_kind":"terrain-form-permeability","required":true,"unavailable_reason":"terrain_form_dependency_unavailable","comparisons":[{"current_field":"identity_sha256","recorded":{"source":"signature","key":"terrain_form_identity_sha256"},"reason":"terrain_form_identity_changed","normalizer":"text"},{"current_field":"artifact_sha256","recorded":{"source":"signature","key":"terrain_form_artifact_sha256"},"reason":"terrain_form_artifact_changed","normalizer":"text"}]}]},{"product_kind":"mast-capacity","algorithm_version":"bigmap2018-species-biomass-broad3000-v2","output_schema_version":"mast-capacity-v1","dependencies":[{"key":"context:landscape-domain","kind":"context","resolver":"farm-watch-context-v1","context_kind":"landscape-domain","required":true,"unavailable_reason":"landscape_domain_unavailable","comparisons":[{"current_field":"identity_sha256","recorded":{"source":"signature","key":"landscape_domain_identity_sha256"},"reason":"landscape_domain_changed"}]},{"key":"external:fia-bigmap-2018-species-biomass","kind":"external","resolver":"external-contract-v1","required":true,"unavailable_reason":"fia_bigmap_2018_species_biomass_unavailable","comparisons":[{"current_field":"identity_sha256","recorded":{"source":"external_contract"},"reason":"fia_bigmap_2018_identity_changed"}]}]}]}$registry$::jsonb;
$$;

create or replace function farm_watch.farm_watch_materialization_dependency_contract_v1(
  p_product_kind text
)
returns jsonb
language sql
immutable
set search_path = 'pg_catalog'
as $$
  select product
  from jsonb_array_elements(
    farm_watch.farm_watch_materialization_dependency_registry_v1()->'products'
  ) product
  where product->>'product_kind'=p_product_kind
  limit 1;
$$;

create or replace function farm_watch.farm_watch_external_dependency_contract_v1(
  p_dependency_key text
)
returns jsonb
language sql
immutable
set search_path = 'pg_catalog'
as $$
  select source || jsonb_build_object(
    'contract_identity_sha256',
    encode(
      extensions.digest(
        convert_to(source->>'contract_seed','UTF8'),
        'sha256'
      ),
      'hex'
    )
  )
  from jsonb_array_elements(
    farm_watch.farm_watch_materialization_dependency_registry_v1()->'external_sources'
  ) source
  where source->>'key'=p_dependency_key
  limit 1;
$$;

create or replace function farm_watch.farm_watch_recorded_dependency_value_v1(
  p_source_signature text,
  p_source_provenance jsonb,
  p_dependency jsonb,
  p_comparison jsonb
)
returns text
language plpgsql
stable
set search_path = 'pg_catalog','farm_watch'
as $$
declare
  v_recorded jsonb := p_comparison->'recorded';
  v_source text := v_recorded->>'source';
  v_value text;
  v_path text[];
begin
  if v_source='signature' then
    return farm_watch.farm_watch_source_signature_value_v1(
      p_source_signature,
      v_recorded->>'key'
    );
  elsif v_source='signature_json' then
    v_value := farm_watch.farm_watch_source_signature_value_v1(
      p_source_signature,
      v_recorded->>'key'
    );
    if v_value is null then return null; end if;
    select array_agg(value order by ordinality)
      into v_path
    from jsonb_array_elements_text(v_recorded->'path') with ordinality;
    begin
      return (v_value::jsonb)#>>v_path;
    exception when others then
      return null;
    end;
  elsif v_source='provenance' then
    select array_agg(value order by ordinality)
      into v_path
    from jsonb_array_elements_text(v_recorded->'path') with ordinality;
    return p_source_provenance#>>v_path;
  elsif v_source='external_contract' then
    return farm_watch.farm_watch_external_dependency_contract_v1(
      p_dependency->>'key'
    )->>'contract_identity_sha256';
  elsif v_source='literal' then
    return v_recorded->>'value';
  end if;
  return null;
end;
$$;

create or replace function farm_watch.farm_watch_compare_materialization_dependency_v1(
  p_source_signature text,
  p_source_provenance jsonb,
  p_dependency jsonb,
  p_current jsonb
)
returns jsonb
language plpgsql
stable
set search_path = 'pg_catalog','farm_watch'
as $$
declare
  v_reasons jsonb := '[]'::jsonb;
  v_comparison jsonb;
  v_recorded text;
  v_current text;
  v_normalizer text;
  v_reason text;
begin
  if coalesce(p_current->>'status','unavailable') <> 'available' then
    return jsonb_build_array(
      coalesce(
        p_dependency->>'unavailable_reason',
        'dependency_unavailable:' || coalesce(p_dependency->>'key','unknown')
      )
    );
  end if;

  for v_comparison in
    select value
    from jsonb_array_elements(coalesce(p_dependency->'comparisons','[]'::jsonb))
  loop
    v_recorded := farm_watch.farm_watch_recorded_dependency_value_v1(
      p_source_signature,
      coalesce(p_source_provenance,'{}'::jsonb),
      p_dependency,
      v_comparison
    );
    v_current := p_current->>(v_comparison->>'current_field');
    v_normalizer := coalesce(v_comparison->>'normalizer','text');
    v_reason := coalesce(
      v_comparison->>'reason',
      'dependency_identity_changed:' || coalesce(p_dependency->>'key','unknown')
    );

    if v_recorded is null or v_current is null then
      v_reasons := v_reasons || jsonb_build_array(
        'recorded_dependency_binding_missing:' ||
        coalesce(p_dependency->>'key','unknown') || ':' ||
        coalesce(v_comparison->>'current_field','unknown')
      );
    elsif v_normalizer='timestamptz' then
      begin
        if v_recorded::timestamptz is distinct from v_current::timestamptz then
          v_reasons := v_reasons || jsonb_build_array(v_reason);
        end if;
      exception when others then
        v_reasons := v_reasons || jsonb_build_array(
          'recorded_dependency_binding_invalid:' ||
          coalesce(p_dependency->>'key','unknown') || ':' ||
          coalesce(v_comparison->>'current_field','unknown')
        );
      end;
    elsif v_recorded is distinct from v_current then
      v_reasons := v_reasons || jsonb_build_array(v_reason);
    end if;
  end loop;

  return v_reasons;
end;
$$;

revoke all on function farm_watch.farm_watch_materialization_dependency_registry_v1()
  from public,anon,authenticated;
grant execute on function farm_watch.farm_watch_materialization_dependency_registry_v1()
  to service_role;

revoke all on function farm_watch.farm_watch_materialization_dependency_contract_v1(text)
  from public,anon,authenticated;
grant execute on function farm_watch.farm_watch_materialization_dependency_contract_v1(text)
  to service_role;

revoke all on function farm_watch.farm_watch_external_dependency_contract_v1(text)
  from public,anon,authenticated;
grant execute on function farm_watch.farm_watch_external_dependency_contract_v1(text)
  to service_role;

revoke all on function farm_watch.farm_watch_recorded_dependency_value_v1(text,jsonb,jsonb,jsonb)
  from public,anon,authenticated,service_role;
revoke all on function farm_watch.farm_watch_compare_materialization_dependency_v1(text,jsonb,jsonb,jsonb)
  from public,anon,authenticated,service_role;

comment on function farm_watch.farm_watch_materialization_dependency_registry_v1() is
'Canonical Farm Watch dependency registry for all 14 materialized product kinds. P0.1 declares external dependencies explicitly but resolves them to contract identities only; P0.2 is responsible for authoritative provider-observation identities.';

commit;
