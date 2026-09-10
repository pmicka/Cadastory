create or replace view agriculture.v_pasture_soil_capability_v1 as
select
  s.field_id,
  s.mukey,
  s.mapunit_name,
  s.dominant_component_key,
  s.dominant_component_name,
  s.dominant_component_pct,
  s.representative_slope_pct,
  case
    when s.representative_slope_pct is null then 'unknown'
    when s.representative_slope_pct <= 5 then 'gentle'
    when s.representative_slope_pct <= 12 then 'rolling'
    when s.representative_slope_pct <= 20 then 'steep'
    else 'very_steep'
  end as terrain_class,
  s.drainage_class,
  case
    when s.drainage_class is null then 'unknown'
    when lower(s.drainage_class) in ('very poorly drained','poorly drained') then 'high_wetness_constraint'
    when lower(s.drainage_class)='somewhat poorly drained' then 'moderate_wetness_constraint'
    when lower(s.drainage_class)='moderately well drained' then 'mild_wetness_constraint'
    else 'low_wetness_constraint'
  end as drainage_constraint_class,
  s.hydrologic_group,
  case
    when s.hydrologic_group is null then 'unknown'
    when s.hydrologic_group in ('D','C/D','B/D','A/D') then 'higher_runoff_potential'
    when s.hydrologic_group='C' then 'moderate_runoff_potential'
    when s.hydrologic_group in ('A','B') then 'lower_runoff_potential'
    else 'unknown'
  end as hydrologic_runoff_class,
  s.available_water_storage_0_100_mm,
  case
    when s.available_water_storage_0_100_mm is null then 'unknown'
    when s.available_water_storage_0_100_mm < 100 then 'low'
    when s.available_water_storage_0_100_mm < 150 then 'moderate_low'
    when s.available_water_storage_0_100_mm < 200 then 'moderate_high'
    else 'high'
  end as rootzone_water_storage_class,
  s.forage_suitability_group_id,
  s.range_production_low_lb_ac_yr,
  s.range_production_rv_lb_ac_yr,
  s.range_production_high_lb_ac_yr,
  s.sample_method,
  s.status as sample_status,
  s.last_sampled_at,
  jsonb_build_object(
    'capability_version','pasture_soil_capability_v1',
    'sample_scope','representative SSURGO map unit/component at field interior point; not polygon-weighted',
    'terrain_class_basis','representative component slope heuristic',
    'drainage_constraint_basis','NRCS drainage class mapped to Scout qualitative wetness categories',
    'hydrologic_runoff_basis','NRCS hydrologic soil group mapped to qualitative runoff potential',
    'water_storage_basis','dominant-component chorizon available water capacity integrated through 0-100 cm; Scout qualitative bins are heuristic',
    'forage_suitability_optional',true
  ) as evidence_summary
from agriculture.pasture_soil_point_samples_v1 s
where s.status='success';

comment on view agriculture.v_pasture_soil_capability_v1 is
'Qualitative pasture soil capability context derived from representative-point SSURGO samples. Scout category bins are planning heuristics, not NRCS interpretations or whole-field agronomic determinations.';

create or replace view agriculture.v_livestock_pasture_portfolio_with_soil_v1 as
select
  p.*,
  sc.mukey as best_field_ssurgo_mukey,
  sc.mapunit_name as best_field_soil_mapunit,
  sc.dominant_component_name as best_field_dominant_soil_component,
  sc.dominant_component_pct as best_field_dominant_component_pct,
  sc.representative_slope_pct as best_field_representative_slope_pct,
  sc.terrain_class as best_field_terrain_class,
  sc.drainage_class as best_field_drainage_class,
  sc.drainage_constraint_class as best_field_drainage_constraint_class,
  sc.hydrologic_group as best_field_hydrologic_group,
  sc.hydrologic_runoff_class as best_field_hydrologic_runoff_class,
  sc.available_water_storage_0_100_mm as best_field_available_water_storage_0_100_mm,
  sc.rootzone_water_storage_class as best_field_rootzone_water_storage_class,
  sc.forage_suitability_group_id as best_field_forage_suitability_group_id,
  (sc.field_id is not null) as best_field_has_ssurgo_sample,
  sc.last_sampled_at as best_field_soil_sampled_at
from agriculture.v_livestock_pasture_portfolio_v1 p
left join agriculture.v_pasture_soil_capability_v1 sc on sc.field_id=p.best_field_id;

comment on view agriculture.v_livestock_pasture_portfolio_with_soil_v1 is
'Livestock pasture research portfolios with representative-point SSURGO capability context for the best-ranked field. Soil context does not strengthen operation attribution by itself.';