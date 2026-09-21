import {
  HRRR_ALGORITHM_VERSION,
  HRRR_EVIDENCE_CLASS,
  HRRR_MAX_GRID_DISTANCE_KM,
  HRRR_MODEL_SLUG,
  HRRR_OUTPUT_SCHEMA_VERSION,
} from './farm-watch-hrrr.ts'

export const FARM_WATCH_METEOROLOGICAL_FORCING_PRODUCT = Object.freeze({
  key: 'meteorological-forcing',
  algorithmVersion: HRRR_ALGORITHM_VERSION,
  outputSchemaVersion: HRRR_OUTPUT_SCHEMA_VERSION,
  evidenceClass: HRRR_EVIDENCE_CLASS,
  sourceModel: HRRR_MODEL_SLUG,
  maxGridDistanceM: HRRR_MAX_GRID_DISTANCE_KM * 1000,
  sourceStates: Object.freeze(['analysis','forecast'] as const),
  collectorSourceState: 'analysis' as const,
  collectorForecastLeadHours: 0,
  requiredFieldKeys: Object.freeze([
    'air_temperature_2m_c',
    'dew_point_2m_c',
    'relative_humidity_2m_pct',
    'wind_grid_u_10m_mps',
    'wind_grid_v_10m_mps',
    'wind_east_10m_mps',
    'wind_north_10m_mps',
    'wind_speed_10m_mps',
    'wind_direction_from_deg',
    'downward_shortwave_wm2',
    'downward_longwave_wm2',
    'total_cloud_cover_pct',
    'precipitation_rate_mm_hr',
  ] as const),
})

export const FARM_WATCH_METEOROLOGICAL_FORCING_LIMITATIONS = Object.freeze([
  'HRRR values are modeled environmental conditions at the nearest model grid point, not on-property weather-station observations.',
  'Farm Watch meteorological forcing must preserve reference time, valid time, forecast lead, source state, grid-point distance, and exact source hashes.',
  'The v1 collector stores f00 analysis rows only. Forecast storage is schema-compatible but is not populated by the v1 collector.',
  'Grid-relative HRRR wind components must be rotated to true east/north before deriving meteorological wind direction.',
  'Meteorological forcing is neutral environmental evidence and performs no deer-use, movement, bedding, habitat-quality, or management inference.',
])

function finite(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value)
}

function iso(value: unknown) {
  return typeof value === 'string' && Number.isFinite(Date.parse(value))
}

export function validateFarmWatchMeteorologicalForcingContext(value: any) {
  if (
    value?.schema !== FARM_WATCH_METEOROLOGICAL_FORCING_PRODUCT.outputSchemaVersion ||
    value?.method !== FARM_WATCH_METEOROLOGICAL_FORCING_PRODUCT.algorithmVersion ||
    value?.evidence_class !== FARM_WATCH_METEOROLOGICAL_FORCING_PRODUCT.evidenceClass ||
    value?.source_state !== 'analysis' && value?.source_state !== 'forecast' ||
    value?.scoring_performed !== false ||
    value?.behavioral_inference_performed !== false ||
    !iso(value?.valid_at) ||
    !value?.source ||
    value.source.model_slug !== FARM_WATCH_METEOROLOGICAL_FORCING_PRODUCT.sourceModel ||
    !iso(value.source.reference_time) ||
    !Number.isInteger(value.source.forecast_lead_hours) ||
    !value?.grid ||
    !finite(value.grid.target_latitude) ||
    !finite(value.grid.target_longitude) ||
    !finite(value.grid.sampled_latitude) ||
    !finite(value.grid.sampled_longitude) ||
    !finite(value.grid.distance_m) ||
    value.grid.distance_m < 0 ||
    value.grid.distance_m > FARM_WATCH_METEOROLOGICAL_FORCING_PRODUCT.maxGridDistanceM ||
    !value?.fields
  ) return false

  if (value.source_state === 'analysis') {
    if (value.source.forecast_lead_hours !== 0) return false
    if (Date.parse(value.valid_at) !== Date.parse(value.source.reference_time)) return false
  } else {
    const expected = Date.parse(value.source.reference_time) + value.source.forecast_lead_hours * 3_600_000
    if (Date.parse(value.valid_at) !== expected) return false
  }

  for (const key of FARM_WATCH_METEOROLOGICAL_FORCING_PRODUCT.requiredFieldKeys) {
    if (!finite(value.fields[key])) return false
  }

  return (
    value.fields.relative_humidity_2m_pct >= 0 &&
    value.fields.relative_humidity_2m_pct <= 100 &&
    value.fields.total_cloud_cover_pct >= 0 &&
    value.fields.total_cloud_cover_pct <= 100 &&
    value.fields.wind_speed_10m_mps >= 0 &&
    value.fields.wind_direction_from_deg >= 0 &&
    value.fields.wind_direction_from_deg < 360 &&
    value.fields.downward_shortwave_wm2 >= 0 &&
    value.fields.downward_longwave_wm2 >= 0 &&
    value.fields.precipitation_rate_mm_hr >= 0
  )
}

export function validateFarmWatchMeteorologicalForcingResponse(value: any) {
  if (!['available','stale','missing'].includes(String(value?.status || ''))) return false
  if (value?.status === 'missing') return value?.context == null
  if (value?.invalidation_reason) return value?.status === 'stale' && value?.context == null
  if (!validateFarmWatchMeteorologicalForcingContext(value?.context)) return false

  const identity = value?.identity
  return Boolean(
    identity &&
    /^[0-9a-f]{64}$/.test(String(identity.boundary_sha256 || '')) &&
    /^[0-9a-f]{64}$/.test(String(identity.source_index_sha256 || '')) &&
    /^[0-9a-f]{64}$/.test(String(identity.source_records_sha256 || '')) &&
    identity.algorithm_version === FARM_WATCH_METEOROLOGICAL_FORCING_PRODUCT.algorithmVersion &&
    identity.output_schema_version === FARM_WATCH_METEOROLOGICAL_FORCING_PRODUCT.outputSchemaVersion &&
    /^[0-9a-f]{64}$/.test(String(identity.identity_sha256 || ''))
  )
}
