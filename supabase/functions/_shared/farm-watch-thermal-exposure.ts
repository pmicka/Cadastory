import { Buffer } from 'node:buffer'
import {
  FARM_WATCH_METEOROLOGICAL_FORCING_PRODUCT,
  validateFarmWatchMeteorologicalForcingResponse,
} from './farm-watch-meteorological-forcing-contract.ts'
import {
  decodeSolarTerrainGrid,
  directTerrainIncidence,
  interpolatedHorizonDeg,
  solarPositionUtc,
} from './farm-watch-solar-exposure.ts'
import { sha256Hex } from './farm-watch-terrain.ts'
import {
  FARM_WATCH_THERMAL_EXPOSURE_PRODUCT,
} from './farm-watch-thermal-exposure-contract.ts'

function encodeU8(values: Uint8Array) {
  return Buffer.from(values.buffer, values.byteOffset, values.byteLength).toString('base64')
}

function encodeU16(values: Uint16Array) {
  return Buffer.from(values.buffer, values.byteOffset, values.byteLength).toString('base64')
}

function finite(value: unknown, label: string) {
  const number = Number(value)
  if (!Number.isFinite(number)) throw new Error(label + ' is not finite')
  return number
}

function distribution(values: number[]) {
  const sorted = values.filter(Number.isFinite).sort((a, b) => a - b)
  if (!sorted.length) {
    return { count: 0, min: null, median: null, mean: null, max: null }
  }
  const total = sorted.reduce((sum, value) => sum + value, 0)
  return {
    count: sorted.length,
    min: sorted[0],
    median: sorted[Math.floor(sorted.length / 2)],
    mean: total / sorted.length,
    max: sorted[sorted.length - 1],
  }
}

function buildThermalGrid(
  grid: ReturnType<typeof decodeSolarTerrainGrid>,
  solarElevationDeg: number,
  solarAzimuthDeg: number,
) {
  const shadow = new Uint8Array(grid.domain.length)
  const terrainFactor = new Uint16Array(grid.domain.length)
  const canopyFactor = new Uint16Array(grid.domain.length)
  const terrainValues: number[] = []
  const canopyValues: number[] = []

  for (let index = 0; index < grid.domain.length; index += 1) {
    if (!grid.domain[index] || !grid.orientationValid[index]) continue

    const horizonValues = grid.horizons.map((values: Uint8Array) => values[index])
    const horizonDeg = interpolatedHorizonDeg(horizonValues, solarAzimuthDeg)
    const terrainShadow =
      solarElevationDeg > 0 && solarElevationDeg <= horizonDeg
    if (terrainShadow) shadow[index] = 1

    const factor = directTerrainIncidence(
      solarElevationDeg,
      solarAzimuthDeg,
      grid.slope[index] / 10,
      grid.aspect[index] / 10,
      horizonDeg,
    )
    terrainFactor[index] = Math.max(
      0,
      Math.min(1000, Math.round(factor * 1000)),
    )
    terrainValues.push(factor)

    if (grid.canopyValid[index]) {
      const openFraction = 1 - grid.canopyPercent[index] / 100
      const screened = factor * openFraction
      canopyFactor[index] = Math.max(
        0,
        Math.min(1000, Math.round(screened * 1000)),
      )
      canopyValues.push(screened)
    }
  }

  return {
    encoded: {
      native_crs: grid.native_crs,
      bbox: grid.bbox,
      cell_meters: grid.cell_meters,
      width: grid.width,
      height: grid.height,
      encoding: 'base64-packed-little-endian-v1',
      domain_valid_base64: encodeU8(grid.domain),
      orientation_valid_u8_base64: encodeU8(grid.orientationValid),
      canopy_valid_u8_base64: encodeU8(grid.canopyValid),
      terrain_shadow_u8_base64: encodeU8(shadow),
      terrain_direct_beam_factor_x1000_u16_base64: encodeU16(terrainFactor),
      canopy_screened_direct_beam_factor_x1000_u16_base64: encodeU16(canopyFactor),
    },
    summary: {
      terrain_direct_beam_factor: distribution(terrainValues),
      canopy_screened_direct_beam_factor: distribution(canopyValues),
      terrain_shadow_cell_count: shadow.reduce((sum, value) => sum + (value ? 1 : 0), 0),
      orientation_valid_cell_count:
        grid.orientationValid.reduce((sum, value) => sum + (value ? 1 : 0), 0),
      canopy_valid_cell_count:
        grid.canopyValid.reduce((sum, value) => sum + (value ? 1 : 0), 0),
    },
  }
}

export async function buildThermalExposureArtifact(args: {
  solarTerrainArtifact: any
  solarTerrainMaterializationIdentitySha256: string
  solarTerrainArtifactSha256: string
  meteorologicalForcingResponse: any
}) {
  const p = FARM_WATCH_THERMAL_EXPOSURE_PRODUCT
  const forcingResponse = args.meteorologicalForcingResponse

  if (!validateFarmWatchMeteorologicalForcingResponse(forcingResponse)) {
    throw new Error('meteorological forcing response violates the Farm Watch contract')
  }
  if (forcingResponse.status !== 'available') {
    throw new Error('current meteorological forcing is unavailable')
  }

  const forcing = forcingResponse.context
  if (forcing.source_state !== p.forcingSourceState) {
    throw new Error('thermal exposure requires HRRR analysis forcing')
  }

  const forcingIdentity = String(forcingResponse.identity?.identity_sha256 || '')
  const sourceIndexSha = String(forcingResponse.identity?.source_index_sha256 || '')
  const sourceRecordsSha = String(forcingResponse.identity?.source_records_sha256 || '')
  if (
    !/^[0-9a-f]{64}$/.test(forcingIdentity) ||
    !/^[0-9a-f]{64}$/.test(sourceIndexSha) ||
    !/^[0-9a-f]{64}$/.test(sourceRecordsSha)
  ) throw new Error('meteorological forcing identity is invalid')

  const validAt = new Date(String(forcing.valid_at))
  if (!Number.isFinite(validAt.getTime())) throw new Error('meteorological forcing valid_at is invalid')

  const anchor = args.solarTerrainArtifact?.solar_anchor
  const latitude = finite(anchor?.latitude, 'solar anchor latitude')
  const longitude = finite(anchor?.longitude, 'solar anchor longitude')
  const solar = solarPositionUtc(validAt, latitude, longitude)

  const local = decodeSolarTerrainGrid(args.solarTerrainArtifact?.local_grid)
  const landscape = decodeSolarTerrainGrid(args.solarTerrainArtifact?.landscape_grid)
  const localBuilt = buildThermalGrid(local, solar.elevation_deg, solar.azimuth_deg)
  const landscapeBuilt = buildThermalGrid(
    landscape,
    solar.elevation_deg,
    solar.azimuth_deg,
  )

  const fields = forcing.fields
  const meteorologicalFields = {
    air_temperature_2m_c: finite(fields.air_temperature_2m_c, 'air temperature'),
    dew_point_2m_c: finite(fields.dew_point_2m_c, 'dew point'),
    relative_humidity_2m_pct: finite(fields.relative_humidity_2m_pct, 'relative humidity'),
    wind_speed_10m_mps: finite(fields.wind_speed_10m_mps, 'wind speed'),
    wind_direction_from_deg: finite(fields.wind_direction_from_deg, 'wind direction'),
    wind_east_10m_mps: finite(fields.wind_east_10m_mps, 'east wind'),
    wind_north_10m_mps: finite(fields.wind_north_10m_mps, 'north wind'),
    downward_shortwave_wm2: finite(fields.downward_shortwave_wm2, 'downward shortwave'),
    downward_longwave_wm2: finite(fields.downward_longwave_wm2, 'downward longwave'),
    total_cloud_cover_pct: finite(fields.total_cloud_cover_pct, 'cloud cover'),
    precipitation_rate_mm_hr: finite(fields.precipitation_rate_mm_hr, 'precipitation rate'),
  }

  const sampledSourceSha256 = await sha256Hex(JSON.stringify({
    solar_terrain_artifact_sha256: args.solarTerrainArtifactSha256,
    meteorological_forcing_identity_sha256: forcingIdentity,
    source_index_sha256: sourceIndexSha,
    source_records_sha256: sourceRecordsSha,
    valid_at: validAt.toISOString(),
    solar_position: {
      elevation_deg: solar.elevation_deg,
      azimuth_deg: solar.azimuth_deg,
    },
  }))

  const artifact = {
    schema: p.outputSchemaVersion,
    method: p.algorithmVersion,
    status: 'available',
    evidence_class: p.evidenceClass,
    valid_at: validAt.toISOString(),
    dependencies: {
      solar_terrain_materialization_identity_sha256:
        args.solarTerrainMaterializationIdentitySha256,
      solar_terrain_artifact_sha256: args.solarTerrainArtifactSha256,
      meteorological_forcing_identity_sha256: forcingIdentity,
      meteorological_forcing_source_index_sha256: sourceIndexSha,
      meteorological_forcing_source_records_sha256: sourceRecordsSha,
    },
    meteorological_forcing: {
      evidence_class: FARM_WATCH_METEOROLOGICAL_FORCING_PRODUCT.evidenceClass,
      source_model: forcing.source.model_slug,
      source_state: forcing.source_state,
      reference_time: forcing.source.reference_time,
      forecast_lead_hours: forcing.source.forecast_lead_hours,
      valid_at: forcing.valid_at,
      age_minutes_at_resolution: forcingResponse.age_minutes,
      grid: forcing.grid,
      fields: meteorologicalFields,
      interpretation_boundary:
        'Modeled HRRR grid-point forcing only; not an on-property weather-station observation.',
    },
    solar_position: {
      anchor_latitude: latitude,
      anchor_longitude: longitude,
      elevation_deg: solar.elevation_deg,
      azimuth_deg: solar.azimuth_deg,
      sun_above_geometric_horizon: solar.elevation_deg > 0,
      geometry:
        'NOAA-style geometric solar position at the exact HRRR forcing valid time; atmospheric refraction omitted.',
    },
    spatial_component_contract: {
      terrain_direct_beam_factor:
        'Dimensionless direct-beam terrain-incidence factor after geometric terrain-horizon shadowing; 0..1.',
      canopy_screened_direct_beam_factor:
        'Terrain direct-beam factor multiplied by the transparent linear proxy (1 - TCC/100); not measured canopy transmittance.',
      atmospheric_radiation_policy:
        'HRRR downward shortwave and longwave remain unredistributed scalar forcing components because v1 does not separate direct/diffuse shortwave or model canopy radiative transfer.',
      wind_policy:
        'HRRR 10 m true wind remains an unredistributed scalar forcing component; terrain/canopy aerodynamic shelter is not modeled.',
    },
    local_grid: localBuilt.encoded,
    landscape_grid: landscapeBuilt.encoded,
    summary: {
      local: localBuilt.summary,
      landscape: landscapeBuilt.summary,
    },
    source_provenance: {
      sampled_source_sha256: sampledSourceSha256,
      static_context_reuse:
        'solar-terrain-context artifact only; no DEM or canopy resampling',
      meteorological_forcing_reuse:
        'centrally persisted Farm Watch HRRR forcing only; no weather-source refetch',
    },
    operative_temperature_calculated: false,
    composite_thermal_index_calculated: false,
    scoring_performed: false,
    behavioral_inference_performed: false,
    interpretation_boundary:
      'Neutral co-registration of modeled meteorological forcing and terrain/canopy solar geometry only. No operative temperature, thermal refuge, wildlife use, habitat, bedding, travel, forage, or management inference is performed.',
  }

  return { artifact, sampledSourceSha256 }
}
