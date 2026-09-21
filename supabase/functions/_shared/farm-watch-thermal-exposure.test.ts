import { Buffer } from 'node:buffer'
import {
  buildThermalExposureArtifact,
} from './farm-watch-thermal-exposure.ts'
import {
  FARM_WATCH_THERMAL_EXPOSURE_PRODUCT,
  thermalExposureSourceSignature,
  validateThermalExposureArtifact,
} from './farm-watch-thermal-exposure-contract.ts'

function assert(condition: unknown, message = 'assertion failed'): asserts condition {
  if (!condition) throw new Error(message)
}

function encodeU8(values: Uint8Array) {
  return Buffer.from(values.buffer, values.byteOffset, values.byteLength).toString('base64')
}

function encodeU16(values: Uint16Array) {
  return Buffer.from(values.buffer, values.byteOffset, values.byteLength).toString('base64')
}

function decodeU16(value: string) {
  const bytes = Buffer.from(value, 'base64')
  const copy = Uint8Array.from(bytes)
  return new Uint16Array(copy.buffer)
}

function solarGrid(
  cellMeters: number,
  width: number,
  aspectsDeg: number[],
  canopyPct: number[],
) {
  const count = width
  const domain = new Uint8Array(count).fill(1)
  const orientation = new Uint8Array(count).fill(1)
  const canopyValid = new Uint8Array(count).fill(1)
  const slope = new Uint16Array(count).fill(300)
  const aspect = new Uint16Array(count)
  const canopy = new Uint8Array(count)
  for (let i = 0; i < count; i += 1) {
    aspect[i] = Math.round(aspectsDeg[i] * 10)
    canopy[i] = canopyPct[i]
  }
  return {
    native_crs: 'EPSG:32616',
    bbox: {
      west: 684000,
      east: 684000 + width * cellMeters,
      south: 4242000,
      north: 4242000 + cellMeters,
    },
    cell_meters: cellMeters,
    width,
    height: 1,
    encoding: 'base64-packed-little-endian-v1',
    elevation_offset_ft: 500,
    domain_valid_base64: encodeU8(domain),
    elevation_tenths_ft_u16_base64: encodeU16(new Uint16Array(count)),
    slope_tenths_degree_u16_base64: encodeU16(slope),
    aspect_tenths_degree_u16_base64: encodeU16(aspect),
    orientation_valid_u8_base64: encodeU8(orientation),
    canopy_valid_u8_base64: encodeU8(canopyValid),
    canopy_percent_u8_base64: encodeU8(canopy),
    horizon_half_degree_u8_base64: Array.from(
      { length: 24 },
      () => encodeU8(new Uint8Array(count)),
    ),
    horizon_mean_half_degree_u8_base64: encodeU8(new Uint8Array(count)),
    horizon_max_half_degree_u8_base64: encodeU8(new Uint8Array(count)),
  }
}

function solarTerrainArtifact() {
  return {
    schema: 'solar-terrain-context-v1',
    method: 'terrain-horizon-canopy-context-v1',
    status: 'available',
    evidence_class: 'deterministic_derived',
    solar_anchor: {
      latitude: 38.32,
      longitude: -84.89,
      basis: 'test',
    },
    local_grid: solarGrid(10, 2, [180, 0], [50, 0]),
    landscape_grid: solarGrid(30, 1, [180], [25]),
  }
}

function forcingResponse(validAt = '2026-09-21T17:00:00.000Z') {
  return {
    status: 'available',
    property: { slug: 'validation-property-01' },
    requested_valid_at: '2026-09-21T17:30:00.000Z',
    valid_at: validAt,
    age_minutes: 30,
    context: {
      schema: 'farm-watch-meteorological-forcing-v1',
      method: 'noaa-hrrr-nearest-grid-analysis-v1',
      evidence_class: 'modeled_environmental_proxy',
      valid_at: validAt,
      source_state: 'analysis',
      source: {
        authority: 'NOAA / NCEP',
        model: 'HRRR CONUS 3 km',
        model_slug: 'noaa-hrrr-conus-3km',
        reference_time: validAt,
        forecast_lead_hours: 0,
        spatial_resolution_km: 3,
        file_url: 'https://example.invalid/hrrr.grib2',
        index_url: 'https://example.invalid/hrrr.grib2.idx',
        index_sha256: '1'.repeat(64),
        record_ranges: [],
      },
      grid: {
        target_latitude: 38.32,
        target_longitude: -84.89,
        sampled_latitude: 38.31,
        sampled_longitude: -84.88,
        distance_m: 1024.1,
      },
      fields: {
        air_temperature_2m_c: 28,
        dew_point_2m_c: 20,
        relative_humidity_2m_pct: 67,
        wind_grid_u_10m_mps: 1,
        wind_grid_v_10m_mps: 0,
        wind_east_10m_mps: 1,
        wind_north_10m_mps: 0,
        wind_speed_10m_mps: 1,
        wind_direction_from_deg: 270,
        downward_shortwave_wm2: 770,
        downward_longwave_wm2: 386,
        total_cloud_cover_pct: 13,
        precipitation_rate_mm_hr: 0,
      },
      scoring_performed: false,
      behavioral_inference_performed: false,
      interpretation_boundary: 'test forcing',
    },
    identity: {
      boundary_sha256: 'a'.repeat(64),
      source_index_sha256: 'b'.repeat(64),
      source_records_sha256: 'c'.repeat(64),
      algorithm_version: 'noaa-hrrr-nearest-grid-analysis-v1',
      output_schema_version: 'farm-watch-meteorological-forcing-v1',
      identity_sha256: 'd'.repeat(64),
    },
    retrieved_at: '2026-09-21T17:05:00.000Z',
  }
}

Deno.test('thermal signature binds exact forcing identity and valid time', () => {
  const base = {
    solarTerrainMaterializationIdentitySha256: 'e'.repeat(64),
    solarTerrainArtifactSha256: 'f'.repeat(64),
    meteorologicalForcingIdentitySha256: 'd'.repeat(64),
    meteorologicalForcingValidAt: '2026-09-21T17:00:00Z',
    sourceIndexSha256: 'b'.repeat(64),
    sourceRecordsSha256: 'c'.repeat(64),
  }
  const a = thermalExposureSourceSignature(base)
  const b = thermalExposureSourceSignature({
    ...base,
    meteorologicalForcingIdentitySha256: '9'.repeat(64),
  })
  assert(a !== b)
  assert(a.includes('composite_thermal_index=none'))
})

Deno.test('thermal context co-registers forcing without a composite thermal score', async () => {
  const built = await buildThermalExposureArtifact({
    solarTerrainArtifact: solarTerrainArtifact(),
    solarTerrainMaterializationIdentitySha256: 'e'.repeat(64),
    solarTerrainArtifactSha256: 'f'.repeat(64),
    meteorologicalForcingResponse: forcingResponse(),
  })
  assert(validateThermalExposureArtifact(built.artifact))
  assert(built.artifact.operative_temperature_calculated === false)
  assert(built.artifact.composite_thermal_index_calculated === false)
  assert(built.artifact.scoring_performed === false)
  assert(built.artifact.behavioral_inference_performed === false)
  assert(built.artifact.meteorological_forcing.fields.air_temperature_2m_c === 28)
  const serialized = JSON.stringify(built.artifact)
  for (const forbidden of ['deer_score','thermal_refuge_score','habitat_score','bedding_score']) {
    assert(!serialized.includes(forbidden))
  }
})

Deno.test('south-facing terrain direct-beam factor exceeds north-facing factor under daytime southern sun', async () => {
  const built = await buildThermalExposureArtifact({
    solarTerrainArtifact: solarTerrainArtifact(),
    solarTerrainMaterializationIdentitySha256: 'e'.repeat(64),
    solarTerrainArtifactSha256: 'f'.repeat(64),
    meteorologicalForcingResponse: forcingResponse(),
  })
  assert(built.artifact.solar_position.elevation_deg > 0)
  const factors = decodeU16(
    built.artifact.local_grid.terrain_direct_beam_factor_x1000_u16_base64,
  )
  assert(factors[0] > factors[1])
})

Deno.test('linear canopy screening is bounded by raw terrain factor', async () => {
  const built = await buildThermalExposureArtifact({
    solarTerrainArtifact: solarTerrainArtifact(),
    solarTerrainMaterializationIdentitySha256: 'e'.repeat(64),
    solarTerrainArtifactSha256: 'f'.repeat(64),
    meteorologicalForcingResponse: forcingResponse(),
  })
  const raw = decodeU16(
    built.artifact.local_grid.terrain_direct_beam_factor_x1000_u16_base64,
  )
  const screened = decodeU16(
    built.artifact.local_grid.canopy_screened_direct_beam_factor_x1000_u16_base64,
  )
  assert(screened[0] <= raw[0])
  assert(screened[1] <= raw[1])
  assert(Math.abs(screened[0] - raw[0] * 0.5) <= 1)
  assert(screened[1] === raw[1])
})

Deno.test('nighttime forcing yields zero solar factors without relabeling night as terrain shadow', async () => {
  const built = await buildThermalExposureArtifact({
    solarTerrainArtifact: solarTerrainArtifact(),
    solarTerrainMaterializationIdentitySha256: 'e'.repeat(64),
    solarTerrainArtifactSha256: 'f'.repeat(64),
    meteorologicalForcingResponse: forcingResponse('2026-09-21T04:00:00.000Z'),
  })
  assert(built.artifact.solar_position.elevation_deg < 0)
  const raw = decodeU16(
    built.artifact.local_grid.terrain_direct_beam_factor_x1000_u16_base64,
  )
  assert([...raw].every((value) => value === 0))
  assert(built.artifact.summary.local.terrain_shadow_cell_count === 0)
})

Deno.test('thermal product remains deterministic-derived and analysis-only', () => {
  assert(FARM_WATCH_THERMAL_EXPOSURE_PRODUCT.evidenceClass === 'deterministic_derived')
  assert(FARM_WATCH_THERMAL_EXPOSURE_PRODUCT.forcingSourceState === 'analysis')
  assert(FARM_WATCH_THERMAL_EXPOSURE_PRODUCT.forcingMaxAgeMinutes === 180)
})
