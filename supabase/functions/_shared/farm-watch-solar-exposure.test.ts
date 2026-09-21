import {
  buildSolarExposureArtifact,
  buildSolarTerrainArtifact,
  directTerrainIncidence,
  geometricSolarDay,
  interpolatedHorizonDeg,
  sampleTargetGrid,
  solarPositionUtc,
} from './farm-watch-solar-exposure.ts'
import {
  FARM_WATCH_SOLAR_EXPOSURE_PRODUCT,
  FARM_WATCH_SOLAR_TERRAIN_PRODUCT,
  solarExposureSourceSignature,
  solarTerrainSourceSignature,
  validateSolarExposureArtifact,
  validateSolarTerrainArtifact,
} from './farm-watch-solar-exposure-contract.ts'

function assert(condition: unknown, message = 'assertion failed'): asserts condition {
  if (!condition) throw new Error(message)
}

function approx(actual: number, expected: number, tolerance: number) {
  assert(Math.abs(actual - expected) <= tolerance, `${actual} not within ${tolerance} of ${expected}`)
}

function encodeU8(values: Uint8Array) {
  let binary = ''
  for (const value of values) binary += String.fromCharCode(value)
  return btoa(binary)
}

function encodeU16(values: Uint16Array) {
  const bytes = new Uint8Array(values.buffer)
  let binary = ''
  for (const value of bytes) binary += String.fromCharCode(value)
  return btoa(binary)
}

function decodeU16(value: string) {
  const binary = atob(value)
  const bytes = Uint8Array.from(binary, (char) => char.charCodeAt(0))
  return new Uint16Array(bytes.buffer)
}

function terrainGrid(width: number, height: number, cellMeters: number, bbox: any, elevationFt = 500) {
  const count = width * height
  return {
    native_crs: 'EPSG:32616',
    bbox,
    cell_meters: cellMeters,
    width,
    height,
    encoding: 'base64-packed-little-endian-v1',
    elevation_offset_ft: elevationFt,
    domain_valid_base64: encodeU8(new Uint8Array(count).fill(1)),
    elevation_tenths_ft_u16_base64: encodeU16(new Uint16Array(count)),
  }
}

function canopyGrid(width: number, height: number, cellMeters: number, bbox: any, percent = 40) {
  const count = width * height
  return {
    native_crs: 'EPSG:32616',
    bbox,
    cell_meters: cellMeters,
    width,
    height,
    encoding: 'base64-packed-little-endian-v1',
    domain_valid_base64: encodeU8(new Uint8Array(count).fill(1)),
    canopy_percent_u8_base64: encodeU8(new Uint8Array(count).fill(percent)),
  }
}

const localBBox = { west: 684000, east: 684050, south: 4242000, north: 4242050 }
const landscapeBBox = { west: 683970, east: 684060, south: 4241970, north: 4242060 }

function dependencies() {
  return {
    terrainArtifact: {
      local_form_grid: terrainGrid(5, 5, 10, localBBox),
      landscape_cost_grid: terrainGrid(3, 3, 30, landscapeBBox),
    },
    terrainMaterializationIdentitySha256: 'a'.repeat(64),
    terrainArtifactSha256: 'b'.repeat(64),
    spatialPatternArtifact: {
      canopy_pattern: {
        grid: canopyGrid(3, 3, 30, landscapeBBox, 40),
      },
    },
    spatialPatternMaterializationIdentitySha256: 'c'.repeat(64),
    spatialPatternArtifactSha256: 'd'.repeat(64),
  }
}

async function rasterFetch(input: string | URL | Request, init?: RequestInit) {
  const url = String(input)
  const params = new URLSearchParams(String(init?.body || ''))
  const geometry = JSON.parse(params.get('geometry') || '{}')
  const points = Array.isArray(geometry.points) ? geometry.points : []
  const canopy = url.includes('/Vegetation/')
  const samples = points.map((_point: number[], index: number) => ({
    locationId: index,
    value: canopy ? 50 : 500,
  }))
  return new Response(JSON.stringify({ samples }), {
    status: 200,
    headers: { 'content-type': 'application/json' },
  })
}

Deno.test('solar noon is nearly overhead at equator near March equinox', () => {
  const day = geometricSolarDay('2026-03-20', 0, 0)
  const sun = solarPositionUtc(day.solarNoon, 0, 0)
  assert(sun.elevation_deg > 89)
  assert(sun.azimuth_deg >= 0 && sun.azimuth_deg < 360)
})

Deno.test('geometric solar day and daylight thirds are deterministic', () => {
  const day = geometricSolarDay('2026-06-21', 38.32, -84.89)
  assert(day.daylightMinutes > 800)
  assert(day.daylightMinutes < 950)
  const morning = day.windows.morning[1] - day.windows.morning[0]
  const midday = day.windows.midday[1] - day.windows.midday[0]
  const evening = day.windows.evening[1] - day.windows.evening[0]
  approx(morning, midday, 1e-9)
  approx(midday, evening, 1e-9)
})

Deno.test('south-facing slope receives greater noon direct potential than north-facing slope', () => {
  const elevation = 50
  const azimuth = 180
  const south = directTerrainIncidence(elevation, azimuth, 30, 180, 0)
  const north = directTerrainIncidence(elevation, azimuth, 30, 0, 0)
  assert(south > north)
})

Deno.test('terrain horizon blocks direct potential and horizon interpolation wraps north', () => {
  const horizons = Array.from({ length: 24 }, (_, index) => index === 0 ? 40 : 0)
  const nearNorth = interpolatedHorizonDeg(horizons, 359)
  assert(nearNorth > 15 && nearNorth <= 20)
  assert(directTerrainIncidence(20, 0, 0, 0, 30) === 0)
})

Deno.test('solar source signatures bind dependencies, date, and physical contract', () => {
  const staticSig = solarTerrainSourceSignature({
    terrainMaterializationIdentitySha256: 'a'.repeat(64),
    terrainArtifactSha256: 'b'.repeat(64),
    spatialPatternMaterializationIdentitySha256: 'c'.repeat(64),
    spatialPatternArtifactSha256: 'd'.repeat(64),
  })
  assert(staticSig.includes('horizon_sector_count=24'))
  assert(staticSig.includes('dem_support_sampling=required_orientation_and_horizon_ray_union_v2'))
  assert(staticSig.includes('raster_sampling_retry=900x4_then_250x2_then_50x1_v1'))
  assert(staticSig.includes('dem_fallback_source=usgs-3dep-dynamic'))
  assert(staticSig.includes('dem_fallback_policy=required_primary_missing_only_v1'))
  assert(staticSig.includes('dem_required_coverage=100pct'))
  const day1 = solarExposureSourceSignature({
    solarTerrainMaterializationIdentitySha256: 'e'.repeat(64),
    solarTerrainArtifactSha256: 'f'.repeat(64),
    solarDate: '2026-09-21',
  })
  const day2 = solarExposureSourceSignature({
    solarTerrainMaterializationIdentitySha256: 'e'.repeat(64),
    solarTerrainArtifactSha256: 'f'.repeat(64),
    solarDate: '2026-09-22',
  })
  assert(day1 !== day2)
})

Deno.test('static solar terrain artifact reuses target elevations and keeps neutral semantics', async () => {
  const built = await buildSolarTerrainArtifact({
    ...dependencies(),
    fetchImpl: rasterFetch as typeof fetch,
  })
  assert(validateSolarTerrainArtifact(built.artifact))
  assert(built.artifact.local_grid.width === 5)
  assert(built.artifact.landscape_grid.width === 3)
  assert(built.artifact.horizon_contract.sector_count === 24)
  assert(built.artifact.method === 'terrain-horizon-canopy-context-v3')
  assert(built.artifact.summary.support_dem_required_cell_count > 0)
  assert(
    built.artifact.summary.support_dem_available_required_cell_count ===
      built.artifact.summary.support_dem_required_cell_count,
  )
  assert(built.artifact.scoring_performed === false)
  assert(built.artifact.behavioral_inference_performed === false)
  assert(
    built.artifact.source_provenance.terrain_target_reuse.includes('no target DEM resampling'),
  )
  const encoded = JSON.stringify(built.artifact)
  for (const forbidden of ['deer_score','habitat_score','bedding_score','stand_score']) {
    assert(!encoded.includes(forbidden))
  }
})



Deno.test('solar terrain fills only unresolved required Phase 3 support from USGS 3DEP', async () => {
  let primaryCalls = 0
  let fallbackCalls = 0
  const fetchImpl = async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input)
    const params = new URLSearchParams(String(init?.body || ''))
    const geometry = JSON.parse(params.get('geometry') || '{}')
    const points = Array.isArray(geometry.points) ? geometry.points : []
    const canopy = url.includes('/Vegetation/')
    const fallback = url.includes('/3DEPElevation/')

    if (canopy) {
      return new Response(JSON.stringify({
        samples: points.map((_point: number[], index: number) => ({
          locationId: index,
          value: 50,
        })),
      }), { status: 200, headers: { 'content-type': 'application/json' } })
    }

    if (fallback) {
      fallbackCalls += 1
      return new Response(JSON.stringify({
        samples: points.map((_point: number[], index: number) => ({
          locationId: index,
          value: 152.4,
        })),
      }), { status: 200, headers: { 'content-type': 'application/json' } })
    }

    primaryCalls += 1
    const samples = points.flatMap((_point: number[], index: number) =>
      index === 0 ? [] : [{ locationId: index, value: 500 }]
    )
    return new Response(JSON.stringify({ samples }), {
      status: 200,
      headers: { 'content-type': 'application/json' },
    })
  }

  const built = await buildSolarTerrainArtifact({
    ...dependencies(),
    fetchImpl: fetchImpl as typeof fetch,
  })

  assert(validateSolarTerrainArtifact(built.artifact))
  assert(primaryCalls > 0)
  assert(fallbackCalls > 0)
  assert(built.artifact.summary.support_dem_fallback_required_cell_count > 0)
  assert(
    built.artifact.summary.support_dem_primary_required_cell_count +
      built.artifact.summary.support_dem_fallback_required_cell_count ===
      built.artifact.summary.support_dem_required_cell_count,
  )
  assert(
    built.artifact.source_provenance.dem_fallback_source_url.includes('3DEPElevation'),
  )
  assert(
    /^[0-9a-f]{64}$/.test(
      built.artifact.source_provenance.dem_support_source_mask_sha256,
    ),
  )
})

Deno.test('date solar exposure artifact integrates windows and canopy proxy stays bounded', async () => {
  const staticBuilt = await buildSolarTerrainArtifact({
    ...dependencies(),
    fetchImpl: rasterFetch as typeof fetch,
  })
  const built = await buildSolarExposureArtifact({
    solarDate: '2026-09-21',
    solarTerrainArtifact: staticBuilt.artifact,
    solarTerrainMaterializationIdentitySha256: 'e'.repeat(64),
    solarTerrainArtifactSha256: 'f'.repeat(64),
  })
  assert(validateSolarExposureArtifact(built.artifact))
  assert(
    built.artifact.solar_day.integration_step_minutes ===
      FARM_WATCH_SOLAR_EXPOSURE_PRODUCT.integrationStepMinutes,
  )

  const windows = built.artifact.local_grid.windows
  const full = decodeU16(windows.full_day.terrain_potential_milli_sun_hours_u16_base64)
  const morning = decodeU16(windows.morning.terrain_potential_milli_sun_hours_u16_base64)
  const midday = decodeU16(windows.midday.terrain_potential_milli_sun_hours_u16_base64)
  const evening = decodeU16(windows.evening.terrain_potential_milli_sun_hours_u16_base64)
  const screened = decodeU16(
    windows.full_day.canopy_screened_potential_milli_sun_hours_u16_base64,
  )

  for (let i = 0; i < full.length; i += 1) {
    assert(Math.abs(full[i] - (morning[i] + midday[i] + evening[i])) <= 2)
    assert(screened[i] <= full[i])
  }
})

Deno.test('solar product contracts retain fixed grains and neutral evidence class', () => {
  assert(FARM_WATCH_SOLAR_TERRAIN_PRODUCT.localCellMeters === 10)
  assert(FARM_WATCH_SOLAR_TERRAIN_PRODUCT.landscapeCellMeters === 30)
  assert(FARM_WATCH_SOLAR_TERRAIN_PRODUCT.evidenceClass === 'deterministic_derived')
  assert(FARM_WATCH_SOLAR_EXPOSURE_PRODUCT.evidenceClass === 'deterministic_derived')
})


Deno.test('raster sampler retries omitted points in smaller batches', async () => {
  const width = 400
  const valid = new Uint8Array(width).fill(1)
  let calls = 0
  const fetchImpl = async (_input: string | URL | Request, init?: RequestInit) => {
    calls += 1
    const params = new URLSearchParams(String(init?.body || ''))
    const geometry = JSON.parse(params.get('geometry') || '{}')
    const points = Array.isArray(geometry.points) ? geometry.points : []
    const omit = points.length > 250
    const samples = points.flatMap((_point: number[], index: number) =>
      omit && index % 10 === 0 ? [] : [{ locationId: index, value: 500 + index / 1000 }]
    )
    return new Response(JSON.stringify({ samples }), {
      status: 200,
      headers: { 'content-type': 'application/json' },
    })
  }

  const values = await sampleTargetGrid(
    {
      bbox: {
        west: 684000,
        east: 684000 + width * 30,
        south: 4242000,
        north: 4242030,
      },
      cell_meters: 30,
      width,
      height: 1,
    },
    valid,
    'https://example.invalid/ImageServer',
    {},
    fetchImpl as typeof fetch,
  )

  assert(calls >= 2)
  assert([...values].every(Number.isFinite))
})
