-- Scope Farm Watch hydrology collection by source need.
-- Visible/reference flowlines stay within 1 km; 3 km waterbody/wetland context supports landscape modeling.

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
      'algorithm_version','barrier-aware-landscape-domain-v1',
      'output_schema_version','farm-watch-landscape-domain-v1',
      'source_signature','zones_m=500,1500,3000|hard_barrier=matched_3dhp_named_flowline_to_intersecting_river_waterbody|fallback_flowline_buffer_m=30|component_rule=intersects_property'
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
