import {
  FARM_WATCH_DEER_TIER1_CONTEXT_PRODUCT,
  validateFarmWatchExtremeWeatherEventContext,
  validateFarmWatchHumanFootprintContext,
  validateFarmWatchRoadFocalContext,
  validateFarmWatchMultiscaleCoverContext,
} from './farm-watch-deer-tier1-context-contract.ts'

function assert(condition: unknown, message = 'assertion failed'): asserts condition {
  if (!condition) throw new Error(message)
}

const sha = 'a'.repeat(64)

Deno.test('human-footprint context preserves Delisle building area and Stephens road radii', () => {
  const value = {
    schema: FARM_WATCH_DEER_TIER1_CONTEXT_PRODUCT.humanFootprint.outputSchemaVersion,
    method: FARM_WATCH_DEER_TIER1_CONTEXT_PRODUCT.humanFootprint.algorithmVersion,
    evidence_class: 'deterministic_derived',
    building_development: {
      study_area_km2: 10.36,
      building_count: 12,
      building_density_per_km2: 12 / 10.36,
      source_profile: {
        service: {
          service_item_id: '0ec8512ad21e4bb987d7e848d14e7e24',
          is_view: true,
          has_static_data: true,
          max_record_count: 2000,
          last_edit_at: '2026-06-08T00:00:00.000Z',
          schema_last_edit_at: '2025-10-14T00:00:00.000Z',
          data_last_edit_at: '2025-09-23T00:00:00.000Z',
        },
        local_feature_vintage: {
          production_date: {
            min: '2021-01-01T00:00:00.000Z',
            max: '2023-01-01T00:00:00.000Z',
            non_null_count: 12,
            coverage_fraction: 1,
          },
          imagery_date: {
            min: '2020-01-01T00:00:00.000Z',
            max: '2022-01-01T00:00:00.000Z',
            non_null_count: 10,
            coverage_fraction: 10 / 12,
          },
        },
        completeness: {
          queried_feature_count: 12,
          inventory_design: 'structures greater than 450 square feet in the United States and its territories',
          known_minimum_structure_area_sqft: 450,
          spatial_completeness_status: 'not_quantified_by_source',
          query_method: 'ArcGIS aggregate statistics over exact 10.36 km2 analytical window',
          transfer_limit_risk: 'none_for_aggregate_statistics',
          attribute_coverage: {
            source_attribution: { non_null_count: 12, coverage_fraction: 1 },
            validation_method: { non_null_count: 8, coverage_fraction: 8 / 12 },
            uuid: { non_null_count: 12, coverage_fraction: 1 },
          },
        },
      },
    },
    road_context: {
      study_sampling_radii_m: [30, 90, 270],
      scopes: {
        local_500m: { road_length_m: 100 },
        landscape_1500m: { road_length_m: 500 },
      },
    },
    source_fingerprint_sha256: sha,
    deer_inference_performed: false,
  }
  assert(validateFarmWatchHumanFootprintContext(value))
  assert(!validateFarmWatchHumanFootprintContext({
    ...value,
    building_development: {
      ...value.building_development,
      source_profile: {
        ...value.building_development.source_profile,
        completeness: {
          ...value.building_development.source_profile.completeness,
          spatial_completeness_status: 'assumed_complete',
        },
      },
    },
  }))
})

Deno.test('M36 road focal context preserves 10 m road-distance raster and 30/90/270 m focal means', () => {
  const value = {
    schema: FARM_WATCH_DEER_TIER1_CONTEXT_PRODUCT.roadFocal.outputSchemaVersion,
    method: FARM_WATCH_DEER_TIER1_CONTEXT_PRODUCT.roadFocal.algorithmVersion,
    evidence_class: 'deterministic_derived',
    source_method: {
      study_road_raster_resolution_m: 10,
      study_focal_radii_m: [30, 90, 270],
    },
    focal_mean_distance_to_road_m: {
      '30m': { mean_m: 910.504, cell_count: 26 },
      '90m': { mean_m: 909.985, cell_count: 254 },
      '270m': { mean_m: 917.631, cell_count: 2284 },
    },
    source_signature_sha256: sha,
    identity_sha256: sha,
    deer_inference_performed: false,
    coefficient_transfer_performed: false,
  }
  assert(validateFarmWatchRoadFocalContext(value))

  assert(!validateFarmWatchRoadFocalContext({
    ...value,
    source_method: {
      study_road_raster_resolution_m: 30,
      study_focal_radii_m: [30, 90, 270],
    },
  }))
})

Deno.test('multiscale context requires exact 1 and 9 km2 windows', () => {
  const value = {
    schema: FARM_WATCH_DEER_TIER1_CONTEXT_PRODUCT.multiscaleCover.outputSchemaVersion,
    method: FARM_WATCH_DEER_TIER1_CONTEXT_PRODUCT.multiscaleCover.algorithmVersion,
    evidence_class: 'deterministic_derived',
    windows: [
      { area_km2: 1, geometry_basis: 'property_centered_square' },
      { area_km2: 9, geometry_basis: 'property_centered_square' },
    ],
    deer_inference_performed: false,
  }
  assert(validateFarmWatchMultiscaleCoverContext(value))
})

Deno.test('extreme-weather gate rejects ordinary weather and accepts explicit tropical alert types', () => {
  const base = {
    schema: FARM_WATCH_DEER_TIER1_CONTEXT_PRODUCT.extremeWeather.outputSchemaVersion,
    method: FARM_WATCH_DEER_TIER1_CONTEXT_PRODUCT.extremeWeather.algorithmVersion,
    evidence_class: 'authoritative_event_context',
    ordinary_weather_activation_allowed: false,
    deer_inference_performed: false,
    coefficient_transfer_performed: false,
    source_health: {
      status: 'healthy',
      http_status: 200,
      poll_age_seconds: 120,
      unresolved_qualifying_event_count: 0,
    },
  }

  assert(validateFarmWatchExtremeWeatherEventContext({
    ...base,
    applicability_state: 'not_applicable',
    event_active: false,
    events: [],
  }))

  assert(validateFarmWatchExtremeWeatherEventContext({
    ...base,
    applicability_state: 'active_extreme_event',
    event_active: true,
    events: [{ event_type: 'Hurricane Warning', status: 'Actual' }],
  }))

  assert(!validateFarmWatchExtremeWeatherEventContext({
    ...base,
    applicability_state: 'active_extreme_event',
    event_active: true,
    events: [{ event_type: 'Severe Thunderstorm Warning', status: 'Actual' }],
  }))

  assert(!validateFarmWatchExtremeWeatherEventContext({
    ...base,
    applicability_state: 'not_applicable',
    event_active: false,
    events: [],
    source_health: {
      ...base.source_health,
      status: 'unavailable',
      http_status: 503,
    },
  }))

  assert(!validateFarmWatchExtremeWeatherEventContext({
    ...base,
    applicability_state: 'not_applicable',
    event_active: false,
    events: [],
    source_health: {
      ...base.source_health,
      poll_age_seconds: 3600,
    },
  }))
})
