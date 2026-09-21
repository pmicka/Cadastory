export const FARM_WATCH_THERMAL_EXPOSURE_PRODUCT = Object.freeze({
  key: 'thermal-exposure-context',
  productKind: 'thermal-exposure-context',
  algorithmVersion: 'hrrr-solar-component-context-v1',
  outputSchemaVersion: 'thermal-exposure-context-v1',
  evidenceClass: 'deterministic_derived',
  artifactBucket: 'farm-watch-derived',
  artifactMimeType: 'application/json',
  forcingSourceState: 'analysis',
  forcingMaxAgeMinutes: 180,
  refreshDays: 3650,
})

export const FARM_WATCH_THERMAL_EXPOSURE_LIMITATIONS = Object.freeze([
  'Meteorological inputs are HRRR modeled environmental proxies at the nearest model grid point, not on-property instrument observations.',
  'The mapped solar factors are geometric terrain-incidence and linear TCC-screening proxies. They are not measured irradiance, absorbed radiation, surface temperature, or operative temperature.',
  'HRRR downward shortwave and longwave fluxes remain scalar forcing components. v1 does not redistribute those fluxes across terrain because direct/diffuse partitioning and canopy radiative transfer are not modeled.',
  'Wind is the HRRR 10 m true wind at the model grid point. Terrain/canopy aerodynamic shelter is not modeled spatially in v1.',
  'Air temperature, dew point, relative humidity, cloud cover, precipitation rate, shortwave, longwave, and wind remain separate components. No arbitrary weighted thermal index is calculated.',
  'Human heat-index, wind-chill, or species-specific body-temperature formulas are not used.',
  'This product performs no thermal-refuge, wildlife-use, habitat, bedding, travel, forage, or management inference.',
])

function sha(value: string, label: string) {
  const normalized = String(value || '').trim().toLowerCase()
  if (!/^[0-9a-f]{64}$/.test(normalized)) throw new Error(label + ' is invalid')
  return normalized
}

export function requireThermalValidAt(value: string) {
  const raw = String(value || '').trim()
  const ms = Date.parse(raw)
  if (!Number.isFinite(ms)) throw new Error('thermal valid_at is invalid')
  return new Date(ms).toISOString()
}

export function thermalExposureSourceSignature(args: {
  solarTerrainMaterializationIdentitySha256: string
  solarTerrainArtifactSha256: string
  meteorologicalForcingIdentitySha256: string
  meteorologicalForcingValidAt: string
  sourceIndexSha256: string
  sourceRecordsSha256: string
}) {
  const p = FARM_WATCH_THERMAL_EXPOSURE_PRODUCT
  return [
    'product=' + p.productKind,
    'solar_terrain_materialization_identity_sha256=' +
      sha(args.solarTerrainMaterializationIdentitySha256, 'solar terrain identity'),
    'solar_terrain_artifact_sha256=' +
      sha(args.solarTerrainArtifactSha256, 'solar terrain artifact'),
    'meteorological_forcing_identity_sha256=' +
      sha(args.meteorologicalForcingIdentitySha256, 'meteorological forcing identity'),
    'meteorological_forcing_valid_at=' + requireThermalValidAt(args.meteorologicalForcingValidAt),
    'source_index_sha256=' + sha(args.sourceIndexSha256, 'forcing source index'),
    'source_records_sha256=' + sha(args.sourceRecordsSha256, 'forcing source records'),
    'forcing_source_state=' + p.forcingSourceState,
    'forcing_max_age_minutes=' + p.forcingMaxAgeMinutes,
    'solar_factor=terrain-direct-incidence-v1',
    'canopy_screening=linear-open-fraction-from-tcc-v1',
    'composite_thermal_index=none',
  ].join('|')
}

export function thermalExposureArtifactPath(
  propertyId: string,
  inputSignature: string,
  artifactSha256: string,
) {
  return [
    'properties',
    propertyId,
    FARM_WATCH_THERMAL_EXPOSURE_PRODUCT.productKind,
    inputSignature,
    artifactSha256 + '.json',
  ].join('/')
}

function gridValid(grid: any, expectedCellMeters: number) {
  return Boolean(
    grid &&
    grid.native_crs === 'EPSG:32616' &&
    Number(grid.cell_meters) === expectedCellMeters &&
    Number.isInteger(Number(grid.width)) &&
    Number(grid.width) > 0 &&
    Number.isInteger(Number(grid.height)) &&
    Number(grid.height) > 0 &&
    typeof grid.domain_valid_base64 === 'string' &&
    typeof grid.orientation_valid_u8_base64 === 'string' &&
    typeof grid.canopy_valid_u8_base64 === 'string' &&
    typeof grid.terrain_shadow_u8_base64 === 'string' &&
    typeof grid.terrain_direct_beam_factor_x1000_u16_base64 === 'string' &&
    typeof grid.canopy_screened_direct_beam_factor_x1000_u16_base64 === 'string'
  )
}

function finite(value: unknown) {
  return typeof value === 'number' && Number.isFinite(value)
}

export function validateThermalExposureArtifact(value: any) {
  const p = FARM_WATCH_THERMAL_EXPOSURE_PRODUCT
  const forcing = value?.meteorological_forcing
  return Boolean(
    value?.schema === p.outputSchemaVersion &&
    value?.method === p.algorithmVersion &&
    value?.status === 'available' &&
    value?.evidence_class === p.evidenceClass &&
    Number.isFinite(Date.parse(String(value?.valid_at || ''))) &&
    /^[0-9a-f]{64}$/.test(String(value?.dependencies?.solar_terrain_artifact_sha256 || '')) &&
    /^[0-9a-f]{64}$/.test(String(value?.dependencies?.meteorological_forcing_identity_sha256 || '')) &&
    forcing?.source_state === p.forcingSourceState &&
    finite(forcing?.fields?.air_temperature_2m_c) &&
    finite(forcing?.fields?.dew_point_2m_c) &&
    finite(forcing?.fields?.relative_humidity_2m_pct) &&
    finite(forcing?.fields?.wind_speed_10m_mps) &&
    finite(forcing?.fields?.wind_direction_from_deg) &&
    finite(forcing?.fields?.downward_shortwave_wm2) &&
    finite(forcing?.fields?.downward_longwave_wm2) &&
    finite(forcing?.fields?.total_cloud_cover_pct) &&
    finite(forcing?.fields?.precipitation_rate_mm_hr) &&
    finite(value?.solar_position?.elevation_deg) &&
    finite(value?.solar_position?.azimuth_deg) &&
    gridValid(value?.local_grid, 10) &&
    gridValid(value?.landscape_grid, 30) &&
    value?.operative_temperature_calculated === false &&
    value?.composite_thermal_index_calculated === false &&
    value?.scoring_performed === false &&
    value?.behavioral_inference_performed === false
  )
}
