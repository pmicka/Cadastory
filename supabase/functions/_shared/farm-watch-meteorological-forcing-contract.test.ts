import {
  FARM_WATCH_METEOROLOGICAL_FORCING_PRODUCT,
  validateFarmWatchMeteorologicalForcingContext,
  validateFarmWatchMeteorologicalForcingResponse,
} from './farm-watch-meteorological-forcing-contract.ts'

function assert(condition: unknown, message = 'assertion failed'): asserts condition {
  if (!condition) throw new Error(message)
}

function forcing() {
  return {
    schema: FARM_WATCH_METEOROLOGICAL_FORCING_PRODUCT.outputSchemaVersion,
    method: FARM_WATCH_METEOROLOGICAL_FORCING_PRODUCT.algorithmVersion,
    evidence_class: FARM_WATCH_METEOROLOGICAL_FORCING_PRODUCT.evidenceClass,
    valid_at: '2026-09-21T17:00:00Z',
    source_state: 'analysis',
    source: {
      authority: 'NOAA / NCEP',
      model: 'HRRR CONUS 3 km',
      model_slug: FARM_WATCH_METEOROLOGICAL_FORCING_PRODUCT.sourceModel,
      reference_time: '2026-09-21T17:00:00Z',
      forecast_lead_hours: 0,
      spatial_resolution_km: 3,
    },
    grid: {
      target_latitude: 38.2,
      target_longitude: -84.9,
      sampled_latitude: 38.21,
      sampled_longitude: 275.1,
      distance_m: 1400,
    },
    fields: {
      air_temperature_2m_c: 28.1,
      dew_point_2m_c: 14.8,
      relative_humidity_2m_pct: 44.2,
      wind_grid_u_10m_mps: 1.1,
      wind_grid_v_10m_mps: -2.3,
      wind_east_10m_mps: 0.9,
      wind_north_10m_mps: -2.4,
      wind_speed_10m_mps: 2.56,
      wind_direction_from_deg: 20.6,
      downward_shortwave_wm2: 611,
      downward_longwave_wm2: 331,
      total_cloud_cover_pct: 18,
      precipitation_rate_mm_hr: 0,
    },
    scoring_performed: false,
    behavioral_inference_performed: false,
    interpretation_boundary: 'modeled neutral environmental forcing only',
  }
}

Deno.test('analysis forcing validates with zero lead and neutral semantics', () => {
  assert(validateFarmWatchMeteorologicalForcingContext(forcing()))
})

Deno.test('analysis forcing rejects nonzero forecast lead', () => {
  const value = forcing()
  value.source.forecast_lead_hours = 1
  assert(!validateFarmWatchMeteorologicalForcingContext(value))
})

Deno.test('forecast forcing must align valid time with reference + lead', () => {
  const value = forcing()
  value.source_state = 'forecast'
  value.valid_at = '2026-09-21T19:00:00Z'
  value.source.forecast_lead_hours = 2
  assert(validateFarmWatchMeteorologicalForcingContext(value))
  value.valid_at = '2026-09-21T18:00:00Z'
  assert(!validateFarmWatchMeteorologicalForcingContext(value))
})

Deno.test('forcing rejects excessive grid distance and physical range errors', () => {
  const value = forcing()
  value.grid.distance_m = 6000
  assert(!validateFarmWatchMeteorologicalForcingContext(value))
  value.grid.distance_m = 1000
  value.fields.relative_humidity_2m_pct = 110
  assert(!validateFarmWatchMeteorologicalForcingContext(value))
})

Deno.test('response preserves exact source hashes and no deer semantics', () => {
  const value = {
    status: 'available',
    context: forcing(),
    identity: {
      boundary_sha256: 'a'.repeat(64),
      source_index_sha256: 'b'.repeat(64),
      source_records_sha256: 'c'.repeat(64),
      algorithm_version: FARM_WATCH_METEOROLOGICAL_FORCING_PRODUCT.algorithmVersion,
      output_schema_version: FARM_WATCH_METEOROLOGICAL_FORCING_PRODUCT.outputSchemaVersion,
      identity_sha256: 'd'.repeat(64),
    },
  }
  assert(validateFarmWatchMeteorologicalForcingResponse(value))
  const encoded = JSON.stringify(value)
  for (const forbidden of ['deer_score','habitat_score','bedding_score','stand_score']) {
    assert(!encoded.includes(forbidden))
  }
})

Deno.test('boundary/contract invalidation must withhold context', () => {
  assert(validateFarmWatchMeteorologicalForcingResponse({
    status:'stale',
    invalidation_reason:'property_boundary_changed',
    context:null,
  }))
  assert(!validateFarmWatchMeteorologicalForcingResponse({
    status:'stale',
    invalidation_reason:'property_boundary_changed',
    context:forcing(),
  }))
})
