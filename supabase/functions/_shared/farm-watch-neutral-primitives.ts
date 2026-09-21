import { Buffer } from 'node:buffer'
import proj4 from 'npm:proj4@2.12.1'
import {
  FARM_WATCH_SPATIAL_PATTERN_PRODUCT,
  FARM_WATCH_TERRAIN_FORM_PRODUCT,
} from './farm-watch-neutral-primitives-contract.ts'
import {
  pointInPolygonGeometry,
  sha256Hex,
  type GeoJsonGeometry,
} from './farm-watch-terrain.ts'

const EPSG_32616 = 'EPSG:32616'

type MetricGrid = {
  native_crs: string
  bbox: { west: number; east: number; south: number; north: number }
  cell_meters: number
  width: number
  height: number
  domain_valid: Uint8Array
  lon_lat: Array<[number, number] | null>
  values: Array<number | null>
}

function finite(value: unknown): number | null {
  const n = Number(value)
  return Number.isFinite(n) ? n : null
}

function projectedBounds(geometry: GeoJsonGeometry) {
  const coords = geometry.type === 'Polygon'
    ? geometry.coordinates.flat(1)
    : geometry.coordinates.flat(2)
  if (!coords.length) throw new Error('analysis geometry is empty')
  const projected = coords.map((point: any) =>
    proj4('EPSG:4326', EPSG_32616, [Number(point[0]), Number(point[1])])
  )
  const xs = projected.map((point: any) => Number(point[0])).filter(Number.isFinite)
  const ys = projected.map((point: any) => Number(point[1])).filter(Number.isFinite)
  if (!xs.length || !ys.length) throw new Error('analysis geometry projection failed')
  return {
    west: Math.min(...xs),
    east: Math.max(...xs),
    south: Math.min(...ys),
    north: Math.max(...ys),
  }
}

export function buildMetricGrid(geometry: GeoJsonGeometry, cellMeters: number): MetricGrid {
  if (!Number.isFinite(cellMeters) || cellMeters <= 0) throw new Error('invalid metric grid cell size')
  const bounds = projectedBounds(geometry)
  const west = Math.floor(bounds.west / cellMeters) * cellMeters
  const east = Math.ceil(bounds.east / cellMeters) * cellMeters
  const south = Math.floor(bounds.south / cellMeters) * cellMeters
  const north = Math.ceil(bounds.north / cellMeters) * cellMeters
  const width = Math.max(1, Math.ceil((east - west) / cellMeters))
  const height = Math.max(1, Math.ceil((north - south) / cellMeters))
  const count = width * height
  if (count > 300000) throw new Error('metric grid exceeds bounded Farm Watch cell budget')

  const domainValid = new Uint8Array(count)
  const lonLat: Array<[number, number] | null> = new Array(count).fill(null)
  const values: Array<number | null> = new Array(count).fill(null)
  for (let row = 0; row < height; row += 1) {
    const y = north - (row + 0.5) * cellMeters
    for (let col = 0; col < width; col += 1) {
      const x = west + (col + 0.5) * cellMeters
      const [lon, lat] = proj4(EPSG_32616, 'EPSG:4326', [x, y])
      const index = row * width + col
      if (!pointInPolygonGeometry(Number(lon), Number(lat), geometry)) continue
      domainValid[index] = 1
      lonLat[index] = [Number(lon), Number(lat)]
    }
  }

  return {
    native_crs: EPSG_32616,
    bbox: { west, east, south, north },
    cell_meters: cellMeters,
    width,
    height,
    domain_valid: domainValid,
    lon_lat: lonLat,
    values,
  }
}

async function postSampleBatch(
  sourceUrl: string,
  points: Array<[number, number]>,
  extra: Record<string, string> = {},
  fetchImpl: typeof fetch = fetch,
) {
  const body = new URLSearchParams({
    geometryType: 'esriGeometryMultipoint',
    geometry: JSON.stringify({ points, spatialReference: { wkid: 4326 } }),
    returnFirstValueOnly: 'true',
    f: 'json',
    ...extra,
  })
  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), 15000)
  try {
    const response = await fetchImpl(sourceUrl.replace(/\/$/, '') + '/getSamples', {
      method: 'POST',
      signal: controller.signal,
      headers: {
        'content-type': 'application/x-www-form-urlencoded;charset=UTF-8',
        accept: 'application/json',
        'user-agent': 'Cadastory-Farm-Watch-Neutral-Primitives/1.0',
      },
      body,
    })
    if (!response.ok) throw new Error('raster samples returned ' + response.status)
    const payload = await response.json()
    if (payload?.error) throw new Error(payload.error.message || 'raster sample request failed')
    if (!Array.isArray(payload?.samples)) throw new Error('raster sample response is unavailable')
    return payload.samples
  } finally {
    clearTimeout(timeout)
  }
}

export async function sampleMetricGrid(
  grid: MetricGrid,
  sourceUrl: string,
  extra: Record<string, string> = {},
  fetchImpl: typeof fetch = fetch,
) {
  const work: Array<{ index: number; point: [number, number] }> = []
  grid.lon_lat.forEach((point, index) => {
    if (grid.domain_valid[index] && point) work.push({ index, point })
  })
  const batches: Array<typeof work> = []
  for (let offset = 0; offset < work.length; offset += 900) {
    batches.push(work.slice(offset, offset + 900))
  }

  for (let cursor = 0; cursor < batches.length; cursor += 4) {
    const group = batches.slice(cursor, cursor + 4)
    const responses = await Promise.all(group.map(async (batch) => ({
      batch,
      samples: await postSampleBatch(
        sourceUrl,
        batch.map((row) => row.point),
        extra,
        fetchImpl,
      ),
    })))
    for (const response of responses) {
      for (const sample of response.samples) {
        const localIndex = Number(sample.locationId)
        const target = response.batch[localIndex]
        const value = finite(sample.value)
        if (!target || value === null) continue
        grid.values[target.index] = value
      }
    }
  }

  const expected = work.length
  const available = work.reduce(
    (sum, row) => sum + (Number.isFinite(grid.values[row.index]) ? 1 : 0),
    0,
  )
  if (!expected || available / expected < 0.97) {
    throw new Error(
      'raster coverage is incomplete for neutral primitive grid: ' +
      available + '/' + expected,
    )
  }
  return grid
}

function neighbors8(width: number, height: number, index: number) {
  const row = Math.floor(index / width)
  const col = index % width
  const out: number[] = []
  for (let dy = -1; dy <= 1; dy += 1) {
    for (let dx = -1; dx <= 1; dx += 1) {
      if (!dx && !dy) continue
      const r = row + dy
      const c = col + dx
      if (r < 0 || r >= height || c < 0 || c >= width) continue
      out.push(r * width + c)
    }
  }
  return out
}

function cardinalNeighbor(
  width: number,
  height: number,
  row: number,
  col: number,
  dx: number,
  dy: number,
) {
  const r = row + dy
  const c = col + dx
  if (r < 0 || r >= height || c < 0 || c >= width) return -1
  return r * width + c
}

function deriveSlope(grid: MetricGrid) {
  const out: Array<number | null> = new Array(grid.values.length).fill(null)
  const ftToM = 0.3048
  for (let row = 1; row < grid.height - 1; row += 1) {
    for (let col = 1; col < grid.width - 1; col += 1) {
      const index = row * grid.width + col
      if (!grid.domain_valid[index] || !Number.isFinite(grid.values[index])) continue
      const l = grid.values[index - 1]
      const r = grid.values[index + 1]
      const u = grid.values[index - grid.width]
      const d = grid.values[index + grid.width]
      if (![l, r, u, d].every(Number.isFinite)) continue
      const dzdx = ((Number(r) - Number(l)) * ftToM) / (2 * grid.cell_meters)
      const dzdy = ((Number(d) - Number(u)) * ftToM) / (2 * grid.cell_meters)
      out[index] = Math.hypot(dzdx, dzdy) * 100
    }
  }
  return out
}

function neighborhoodStats(grid: MetricGrid, radiusCells: number) {
  const mean: Array<number | null> = new Array(grid.values.length).fill(null)
  const relief: Array<number | null> = new Array(grid.values.length).fill(null)
  for (let row = 0; row < grid.height; row += 1) {
    for (let col = 0; col < grid.width; col += 1) {
      const index = row * grid.width + col
      if (!grid.domain_valid[index] || !Number.isFinite(grid.values[index])) continue
      let sum = 0
      let count = 0
      let min = Infinity
      let max = -Infinity
      for (let dy = -radiusCells; dy <= radiusCells; dy += 1) {
        for (let dx = -radiusCells; dx <= radiusCells; dx += 1) {
          if (dx * dx + dy * dy > radiusCells * radiusCells) continue
          const r = row + dy
          const c = col + dx
          if (r < 0 || r >= grid.height || c < 0 || c >= grid.width) continue
          const neighbor = r * grid.width + c
          const value = grid.values[neighbor]
          if (!grid.domain_valid[neighbor] || !Number.isFinite(value)) continue
          sum += Number(value)
          count += 1
          min = Math.min(min, Number(value))
          max = Math.max(max, Number(value))
        }
      }
      if (count >= 5) {
        mean[index] = sum / count
        relief[index] = max - min
      }
    }
  }
  return { mean, relief }
}

function standardDeviation(values: Array<number | null>) {
  const valid = values.filter((value): value is number => Number.isFinite(value))
  if (valid.length < 2) return 0
  const mean = valid.reduce((sum, value) => sum + value, 0) / valid.length
  return Math.sqrt(valid.reduce((sum, value) => sum + (value - mean) ** 2, 0) / valid.length)
}

function distribution(values: Array<number | null>) {
  const valid = values.filter((value): value is number => Number.isFinite(value)).sort((a,b)=>a-b)
  if (!valid.length) return { count: 0, min: null, p10: null, p25: null, median: null, p75: null, p90: null, max: null, mean: null }
  const q = (p: number) => valid[Math.min(valid.length - 1, Math.max(0, Math.round((valid.length - 1) * p)))]
  return {
    count: valid.length,
    min: valid[0],
    p10: q(0.1),
    p25: q(0.25),
    median: q(0.5),
    p75: q(0.75),
    p90: q(0.9),
    max: valid[valid.length - 1],
    mean: valid.reduce((sum,value)=>sum+value,0)/valid.length,
  }
}

function deriveTerrainForms(grid: MetricGrid, slopes: Array<number | null>) {
  const localRadius = Math.max(
    1,
    Math.round(FARM_WATCH_TERRAIN_FORM_PRODUCT.localTpiRadiusMeters / grid.cell_meters),
  )
  const broadRadius = Math.max(
    localRadius + 1,
    Math.round(FARM_WATCH_TERRAIN_FORM_PRODUCT.broadTpiRadiusMeters / grid.cell_meters),
  )
  const localStats = neighborhoodStats(grid, localRadius)
  const broadStats = neighborhoodStats(grid, broadRadius)
  const localTpi = grid.values.map((value, index) =>
    Number.isFinite(value) && Number.isFinite(localStats.mean[index])
      ? Number(value) - Number(localStats.mean[index])
      : null
  )
  const broadTpi = grid.values.map((value, index) =>
    Number.isFinite(value) && Number.isFinite(broadStats.mean[index])
      ? Number(value) - Number(broadStats.mean[index])
      : null
  )
  const localSd = Math.max(0.01, standardDeviation(localTpi))
  const broadSd = Math.max(0.01, standardDeviation(broadTpi))

  const formCode = new Uint8Array(grid.values.length)
  const flags = new Uint8Array(grid.values.length)
  const slopeBreakDelta = 12

  for (let row = 1; row < grid.height - 1; row += 1) {
    for (let col = 1; col < grid.width - 1; col += 1) {
      const index = row * grid.width + col
      const value = grid.values[index]
      const slope = slopes[index]
      const lt = localTpi[index]
      const bt = broadTpi[index]
      if (![value, slope, lt, bt].every(Number.isFinite)) continue

      const localZ = Number(lt) / localSd
      const broadZ = Number(bt) / broadSd
      const l = grid.values[index - 1]
      const r = grid.values[index + 1]
      const u = grid.values[index - grid.width]
      const d = grid.values[index + grid.width]
      const dxx = [l,r,value].every(Number.isFinite)
        ? Number(l) - 2 * Number(value) + Number(r)
        : 0
      const dyy = [u,d,value].every(Number.isFinite)
        ? Number(u) - 2 * Number(value) + Number(d)
        : 0

      let neighborSlopeSum = 0
      let neighborSlopeCount = 0
      for (const other of neighbors8(grid.width, grid.height, index)) {
        if (!Number.isFinite(slopes[other])) continue
        neighborSlopeSum += Number(slopes[other])
        neighborSlopeCount += 1
      }
      const neighborSlopeMean = neighborSlopeCount ? neighborSlopeSum / neighborSlopeCount : Number(slope)
      const isRidge = broadZ >= 1 && localZ >= 0.5
      const isDraw = broadZ <= -1 && localZ <= -0.5
      const isSaddle =
        Math.abs(broadZ) <= 0.75 &&
        Math.abs(localZ) <= 0.75 &&
        dxx * dyy < 0 &&
        Math.max(Math.abs(dxx), Math.abs(dyy)) >= 1.5
      const isBench =
        Number(slope) <= 10 &&
        Number(broadStats.relief[index] || 0) >= 30 &&
        Math.abs(broadZ) <= 0.75
      const isSlopeBreak = Math.abs(Number(slope) - neighborSlopeMean) >= slopeBreakDelta

      if (isRidge) flags[index] |= 1
      if (isDraw) flags[index] |= 2
      if (isSaddle) flags[index] |= 4
      if (isBench) flags[index] |= 8
      if (isSlopeBreak) flags[index] |= 16

      formCode[index] = isSaddle
        ? 4
        : isBench
          ? 5
          : isRidge
            ? 2
            : isDraw
              ? 3
              : isSlopeBreak
                ? 6
                : 1
    }
  }

  return {
    localTpi,
    broadTpi,
    reliefBroad: broadStats.relief,
    formCode,
    flags,
    thresholds: {
      local_tpi_radius_m: FARM_WATCH_TERRAIN_FORM_PRODUCT.localTpiRadiusMeters,
      broad_tpi_radius_m: FARM_WATCH_TERRAIN_FORM_PRODUCT.broadTpiRadiusMeters,
      ridge_like: { broad_tpi_z_min: 1, local_tpi_z_min: 0.5 },
      draw_like: { broad_tpi_z_max: -1, local_tpi_z_max: -0.5 },
      saddle_like: {
        absolute_broad_tpi_z_max: 0.75,
        absolute_local_tpi_z_max: 0.75,
        orthogonal_second_difference_sign: 'opposed',
        minimum_axis_second_difference_ft: 1.5,
      },
      bench_like: {
        slope_percent_max: 10,
        broad_relief_ft_min: 30,
        absolute_broad_tpi_z_max: 0.75,
      },
      slope_break: { local_vs_8_neighbor_mean_delta_percent_min: slopeBreakDelta },
      local_tpi_sd_ft: localSd,
      broad_tpi_sd_ft: broadSd,
    },
    legend: {
      0: 'unavailable',
      1: 'unclassified_surface',
      2: 'ridge_like_candidate',
      3: 'draw_like_candidate',
      4: 'saddle_like_candidate',
      5: 'bench_like_candidate',
      6: 'slope_break_candidate',
    },
    flag_legend: {
      1: 'ridge_like_candidate',
      2: 'draw_like_candidate',
      4: 'saddle_like_candidate',
      8: 'bench_like_candidate',
      16: 'slope_break_candidate',
    },
  }
}

function terrainCost(slopePercent: number | null) {
  if (!Number.isFinite(slopePercent)) return null
  const scenario = FARM_WATCH_TERRAIN_FORM_PRODUCT.permeabilityScenario
  const boundedSlope = Math.min(scenario.slope_cap_percent, Math.max(0, Number(slopePercent)))
  return scenario.base_cost +
    scenario.slope_weight *
    (boundedSlope / scenario.slope_reference_percent) ** scenario.exponent
}

function encodeU8(values: Uint8Array) {
  return Buffer.from(values.buffer, values.byteOffset, values.byteLength).toString('base64')
}
function encodeU16(values: Uint16Array) {
  return Buffer.from(values.buffer, values.byteOffset, values.byteLength).toString('base64')
}
function encodeI16(values: Int16Array) {
  return Buffer.from(values.buffer, values.byteOffset, values.byteLength).toString('base64')
}
function encodeU32(values: Uint32Array) {
  return Buffer.from(values.buffer, values.byteOffset, values.byteLength).toString('base64')
}
function decodeU8(value: string) {
  const bytes = Buffer.from(value, 'base64')
  return new Uint8Array(bytes.buffer, bytes.byteOffset, bytes.byteLength).slice()
}

function encodedTerrainGrid(
  grid: MetricGrid,
  slopes: Array<number | null>,
  forms: ReturnType<typeof deriveTerrainForms> | null,
) {
  const validElevation = grid.values.filter((value): value is number => Number.isFinite(value))
  const elevationOffset = Math.floor(Math.min(...validElevation))
  const elevation = new Uint16Array(grid.values.length)
  const slope = new Uint16Array(grid.values.length)
  const localTpi = new Int16Array(grid.values.length)
  const broadTpi = new Int16Array(grid.values.length)
  const broadRelief = new Uint16Array(grid.values.length)
  const cost = new Uint16Array(grid.values.length)
  const permeability = new Uint8Array(grid.values.length)

  for (let index = 0; index < grid.values.length; index += 1) {
    if (!grid.domain_valid[index]) continue
    const value = grid.values[index]
    const s = slopes[index]
    if (Number.isFinite(value)) {
      elevation[index] = Math.max(0, Math.min(65535, Math.round((Number(value) - elevationOffset) * 10)))
    }
    if (Number.isFinite(s)) {
      slope[index] = Math.max(0, Math.min(65535, Math.round(Number(s) * 100)))
      const cellCost = terrainCost(s)
      if (cellCost !== null) {
        cost[index] = Math.max(1, Math.min(65535, Math.round(cellCost * 100)))
        permeability[index] = Math.max(1, Math.min(255, Math.round(255 / cellCost)))
      }
    }
    if (forms) {
      const lt = forms.localTpi[index]
      const bt = forms.broadTpi[index]
      const relief = forms.reliefBroad[index]
      if (Number.isFinite(lt)) localTpi[index] = Math.max(-32768, Math.min(32767, Math.round(Number(lt) * 10)))
      if (Number.isFinite(bt)) broadTpi[index] = Math.max(-32768, Math.min(32767, Math.round(Number(bt) * 10)))
      if (Number.isFinite(relief)) broadRelief[index] = Math.max(0, Math.min(65535, Math.round(Number(relief) * 10)))
    }
  }

  return {
    native_crs: grid.native_crs,
    bbox: grid.bbox,
    cell_meters: grid.cell_meters,
    width: grid.width,
    height: grid.height,
    encoding: 'base64-packed-little-endian-v1',
    elevation_offset_ft: elevationOffset,
    domain_valid_base64: encodeU8(grid.domain_valid),
    elevation_tenths_ft_u16_base64: encodeU16(elevation),
    slope_centipercent_u16_base64: encodeU16(slope),
    ...(forms ? {
      tpi_local_tenths_ft_i16_base64: encodeI16(localTpi),
      tpi_broad_tenths_ft_i16_base64: encodeI16(broadTpi),
      relief_broad_tenths_ft_u16_base64: encodeU16(broadRelief),
      form_code_u8_base64: encodeU8(forms.formCode),
      form_flags_u8_base64: encodeU8(forms.flags),
    } : {}),
    cost_x100_u16_base64: encodeU16(cost),
    permeability_u8_base64: encodeU8(permeability),
  }
}

function summarizeForms(forms: ReturnType<typeof deriveTerrainForms>) {
  const counts: Record<string, number> = {}
  for (const code of forms.formCode) {
    const label = String((forms.legend as any)[code] || 'unknown')
    counts[label] = (counts[label] || 0) + 1
  }
  return counts
}

export async function buildTerrainFormArtifact(args: {
  localGeometry: GeoJsonGeometry
  landscapeGeometry: GeoJsonGeometry
  domainIdentitySha256: string
  domainAlgorithmVersion: string
  landscapePhysicalIdentitySha256: string
  fetchImpl?: typeof fetch
}) {
  const fetchImpl = args.fetchImpl || fetch
  const localGrid = await sampleMetricGrid(
    buildMetricGrid(args.localGeometry, FARM_WATCH_TERRAIN_FORM_PRODUCT.localCellMeters),
    FARM_WATCH_TERRAIN_FORM_PRODUCT.sourceUrl,
    {},
    fetchImpl,
  )
  const landscapeGrid = await sampleMetricGrid(
    buildMetricGrid(args.landscapeGeometry, FARM_WATCH_TERRAIN_FORM_PRODUCT.landscapeCellMeters),
    FARM_WATCH_TERRAIN_FORM_PRODUCT.sourceUrl,
    {},
    fetchImpl,
  )
  const localSlope = deriveSlope(localGrid)
  const landscapeSlope = deriveSlope(landscapeGrid)
  const forms = deriveTerrainForms(localGrid, localSlope)
  const sampledSourceSha256 = await sha256Hex(JSON.stringify({
    local: localGrid.values,
    landscape: landscapeGrid.values,
  }))

  const artifact = {
    schema: FARM_WATCH_TERRAIN_FORM_PRODUCT.outputSchemaVersion,
    method: FARM_WATCH_TERRAIN_FORM_PRODUCT.algorithmVersion,
    status: 'available',
    evidence_class: FARM_WATCH_TERRAIN_FORM_PRODUCT.evidenceClass,
    domain: {
      identity_sha256: args.domainIdentitySha256,
      algorithm_version: args.domainAlgorithmVersion,
      local_radius_m: FARM_WATCH_TERRAIN_FORM_PRODUCT.localDomainMeters,
      landscape_radius_m: FARM_WATCH_TERRAIN_FORM_PRODUCT.landscapeDomainMeters,
      barrier_aware: true,
    },
    dependencies: {
      landscape_physical_identity_sha256: args.landscapePhysicalIdentitySha256,
    },
    local_form_grid: encodedTerrainGrid(localGrid, localSlope, forms),
    landscape_cost_grid: encodedTerrainGrid(landscapeGrid, landscapeSlope, null),
    form_contract: {
      method: 'explicit_tpi_slope_curvature_thresholds_v1',
      thresholds: forms.thresholds,
      legend: forms.legend,
      flag_legend: forms.flag_legend,
    },
    permeability_scenario: {
      ...FARM_WATCH_TERRAIN_FORM_PRODUCT.permeabilityScenario,
      cost_semantics:
        'Dimensionless reference friction: 1 + slope_weight * (bounded_slope / slope_reference)^exponent.',
      permeability_encoding:
        'u8 round(255 / cost); outside-domain and unavailable-slope cells remain 0.',
    },
    summary: {
      local_valid_cell_count: localGrid.domain_valid.reduce((sum, value) => sum + value, 0),
      landscape_valid_cell_count: landscapeGrid.domain_valid.reduce((sum, value) => sum + value, 0),
      local_slope_percent: distribution(localSlope),
      landscape_slope_percent: distribution(landscapeSlope),
      local_tpi_ft: distribution(forms.localTpi),
      broad_tpi_ft: distribution(forms.broadTpi),
      broad_relief_ft: distribution(forms.reliefBroad),
      local_form_cell_counts: summarizeForms(forms),
    },
    source_provenance: {
      authority: 'Kentucky Division of Geographic Information / KyFromAbove',
      source: 'KyFromAbove Phase 3 DEM',
      source_url: FARM_WATCH_TERRAIN_FORM_PRODUCT.sourceUrl,
      operation: 'ImageServer/getSamples',
      input_srid: 4326,
      analysis_crs: EPSG_32616,
      sampled_source_sha256: sampledSourceSha256,
    },
    scoring_performed: false,
    behavioral_inference_performed: false,
    interpretation_boundary:
      'Neutral terrain geometry and a named reference friction scenario only. No animal movement, travel preference, funnel, bedding, habitat, or hunting inference is performed.',
  }
  return { artifact, sampledSourceSha256 }
}

type PatchMetrics = {
  patchIds: Uint32Array
  patches: Array<{
    id: number
    class_code: number
    cell_count: number
    area_m2: number
    perimeter_m: number
  }>
  class_summary: Record<string, any>
  transition_edge_m: number
  transition_edge_density_m_per_ha: number | null
  adjacency_edge_m: Record<string, number>
}

export function categoricalPatchMetrics(
  classes: Uint8Array,
  valid: Uint8Array,
  width: number,
  height: number,
  cellMeters: number,
  neighborRule = 8,
): PatchMetrics {
  if (classes.length !== valid.length || classes.length !== width * height) {
    throw new Error('categorical patch grid dimensions are invalid')
  }
  const patchIds = new Uint32Array(classes.length)
  const patches: PatchMetrics['patches'] = []
  let nextId = 1
  const offsets = neighborRule === 8
    ? [[-1,-1],[0,-1],[1,-1],[-1,0],[1,0],[-1,1],[0,1],[1,1]]
    : [[0,-1],[-1,0],[1,0],[0,1]]

  for (let start = 0; start < classes.length; start += 1) {
    if (!valid[start] || patchIds[start]) continue
    const classCode = classes[start]
    const queue = [start]
    patchIds[start] = nextId
    let cells = 0
    let perimeterSides = 0
    for (let cursor = 0; cursor < queue.length; cursor += 1) {
      const index = queue[cursor]
      cells += 1
      const row = Math.floor(index / width)
      const col = index % width
      for (const [dx,dy] of [[0,-1],[-1,0],[1,0],[0,1]]) {
        const other = cardinalNeighbor(width,height,row,col,dx,dy)
        if (other < 0 || !valid[other] || classes[other] !== classCode) perimeterSides += 1
      }
      for (const [dx,dy] of offsets) {
        const r = row + dy
        const c = col + dx
        if (r < 0 || r >= height || c < 0 || c >= width) continue
        const other = r * width + c
        if (!valid[other] || patchIds[other] || classes[other] !== classCode) continue
        patchIds[other] = nextId
        queue.push(other)
      }
    }
    patches.push({
      id: nextId,
      class_code: classCode,
      cell_count: cells,
      area_m2: cells * cellMeters * cellMeters,
      perimeter_m: perimeterSides * cellMeters,
    })
    nextId += 1
  }

  let transitionEdgeM = 0
  const adjacency: Record<string, number> = {}
  let validCellCount = 0
  for (let row = 0; row < height; row += 1) {
    for (let col = 0; col < width; col += 1) {
      const index = row * width + col
      if (!valid[index]) continue
      validCellCount += 1
      for (const [dx,dy] of [[1,0],[0,1]]) {
        const other = cardinalNeighbor(width,height,row,col,dx,dy)
        if (other < 0 || !valid[other] || classes[other] === classes[index]) continue
        transitionEdgeM += cellMeters
        const a = Math.min(classes[index], classes[other])
        const b = Math.max(classes[index], classes[other])
        const key = a + ':' + b
        adjacency[key] = (adjacency[key] || 0) + cellMeters
      }
    }
  }

  const classSummary: Record<string, any> = {}
  const classCodes = [...new Set(patches.map((patch) => patch.class_code))]
  for (const classCode of classCodes) {
    const rows = patches.filter((patch) => patch.class_code === classCode)
    const areas = rows.map((patch) => patch.area_m2).sort((a,b)=>a-b)
    const totalArea = areas.reduce((sum,value)=>sum+value,0)
    classSummary[String(classCode)] = {
      patch_count: rows.length,
      total_area_m2: totalArea,
      largest_patch_area_m2: areas.length ? areas[areas.length-1] : 0,
      median_patch_area_m2: areas.length ? areas[Math.floor(areas.length/2)] : 0,
    }
  }
  const hectares = validCellCount * cellMeters * cellMeters / 10000
  return {
    patchIds,
    patches,
    class_summary: classSummary,
    transition_edge_m: transitionEdgeM,
    transition_edge_density_m_per_ha: hectares > 0 ? transitionEdgeM / hectares : null,
    adjacency_edge_m: adjacency,
  }
}

function pointSegmentDistance(
  px: number, py: number,
  ax: number, ay: number,
  bx: number, by: number,
) {
  const dx = bx - ax
  const dy = by - ay
  if (!dx && !dy) return Math.hypot(px - ax, py - ay)
  const t = Math.max(0, Math.min(1, ((px-ax)*dx + (py-ay)*dy)/(dx*dx+dy*dy)))
  return Math.hypot(px-(ax+t*dx), py-(ay+t*dy))
}

function lineSegmentsProjected(geometry: any) {
  if (!geometry) return [] as Array<[number,number,number,number]>
  const lines = geometry.type === 'LineString'
    ? [geometry.coordinates]
    : geometry.type === 'MultiLineString'
      ? geometry.coordinates
      : []
  const segments: Array<[number,number,number,number]> = []
  for (const line of lines) {
    for (let index=1; index<line.length; index+=1) {
      const a=proj4('EPSG:4326',EPSG_32616,[Number(line[index-1][0]),Number(line[index-1][1])])
      const b=proj4('EPSG:4326',EPSG_32616,[Number(line[index][0]),Number(line[index][1])])
      segments.push([Number(a[0]),Number(a[1]),Number(b[0]),Number(b[1])])
    }
  }
  return segments
}

function mappedFieldPattern(
  grid: MetricGrid,
  fieldAreaGeometry: GeoJsonGeometry | null,
  fieldEdgeGeometry: any,
) {
  const fieldMask = new Uint8Array(grid.values.length)
  const distance = new Uint16Array(grid.values.length)
  const segments = lineSegmentsProjected(fieldEdgeGeometry)
  for (let row=0; row<grid.height; row+=1) {
    const y=grid.bbox.north-(row+0.5)*grid.cell_meters
    for (let col=0; col<grid.width; col+=1) {
      const index=row*grid.width+col
      if(!grid.domain_valid[index]) continue
      const point=grid.lon_lat[index]
      if(fieldAreaGeometry && point && pointInPolygonGeometry(point[0],point[1],fieldAreaGeometry)) {
        fieldMask[index]=1
      }
      let min=Infinity
      const x=grid.bbox.west+(col+0.5)*grid.cell_meters
      for(const [ax,ay,bx,by] of segments) {
        min=Math.min(min,pointSegmentDistance(x,y,ax,ay,bx,by))
      }
      distance[index]=Number.isFinite(min)
        ? Math.max(0,Math.min(65535,Math.round(min)))
        : 65535
    }
  }
  return { fieldMask, distance, segmentCount: segments.length }
}

function decodeStructureGrid(artifact: any) {
  const grid=artifact?.combined_grid
  const width=Number(grid?.width)
  const height=Number(grid?.height)
  const count=width*height
  const domain=decodeU8(String(grid?.domain_valid_base64||''))
  const lidarValid=decodeU8(String(grid?.lidar_valid_base64||''))
  const lidarDominant=decodeU8(String(grid?.lidar_dominant_band_base64||''))
  const leafValid=decodeU8(String(grid?.leaf_valid_base64||''))
  const leafScore=decodeU8(String(grid?.leaf_score_base64||''))
  const shares=(grid?.lidar_band_shares_base64||[]).map((value:string)=>decodeU8(value))
  if(
    !Number.isInteger(width) || !Number.isInteger(height) || count<=0 ||
    domain.length!==count || lidarValid.length!==count || lidarDominant.length!==count ||
    leafValid.length!==count || leafScore.length!==count ||
    !shares.length || shares.some((values:Uint8Array)=>values.length!==count)
  ) throw new Error('landscape structure compact grid is invalid')
  return { grid,width,height,count,domain,lidarValid,lidarDominant,leafValid,leafScore,shares }
}

function structureTransitionPattern(artifact:any) {
  const decoded=decodeStructureGrid(artifact)
  const leafTransition=new Uint8Array(decoded.count)
  const lidarTransition=new Uint8Array(decoded.count)

  for(let index=0; index<decoded.count; index+=1) {
    if(!decoded.domain[index]) continue
    let leafSum=0,leafCount=0,lidarSum=0,lidarCount=0
    for(const other of neighbors8(decoded.width,decoded.height,index)) {
      if(!decoded.domain[other]) continue
      if(decoded.leafValid[index] && decoded.leafValid[other]) {
        leafSum+=Math.abs(decoded.leafScore[index]-decoded.leafScore[other])
        leafCount+=1
      }
      if(decoded.lidarValid[index] && decoded.lidarValid[other]) {
        let l1=0
        for(const band of decoded.shares) l1+=Math.abs(band[index]-band[other])
        lidarSum+=Math.min(255,l1/2)
        lidarCount+=1
      }
    }
    if(leafCount) leafTransition[index]=Math.round(leafSum/leafCount)
    if(lidarCount) lidarTransition[index]=Math.round(lidarSum/lidarCount)
  }

  const leafClass=new Uint8Array(decoded.count)
  for(let i=0;i<decoded.count;i+=1) {
    if(!decoded.leafValid[i]) continue
    const score=decoded.leafScore[i]
    leafClass[i]=score<64?1:score<128?2:score<192?3:4
  }
  const leafPatch=categoricalPatchMetrics(
    leafClass,decoded.leafValid,decoded.width,decoded.height,
    FARM_WATCH_SPATIAL_PATTERN_PRODUCT.structureCellMeters,
    FARM_WATCH_SPATIAL_PATTERN_PRODUCT.patchNeighborRule,
  )
  const lidarClass=new Uint8Array(decoded.count)
  for(let i=0;i<decoded.count;i+=1) {
    if(decoded.lidarValid[i]) lidarClass[i]=decoded.lidarDominant[i]+1
  }
  const lidarPatch=categoricalPatchMetrics(
    lidarClass,decoded.lidarValid,decoded.width,decoded.height,
    FARM_WATCH_SPATIAL_PATTERN_PRODUCT.structureCellMeters,
    FARM_WATCH_SPATIAL_PATTERN_PRODUCT.patchNeighborRule,
  )

  return {
    grid:{
      native_crs:String(decoded.grid.native_crs),
      bbox:decoded.grid.bbox,
      cell_meters:Number(decoded.grid.cell_meters),
      width:decoded.width,
      height:decoded.height,
      encoding:'base64-packed-little-endian-v1',
      domain_valid_base64:encodeU8(decoded.domain),
      leaf_transition_u8_base64:encodeU8(leafTransition),
      lidar_profile_transition_u8_base64:encodeU8(lidarTransition),
      leaf_quartile_patch_id_u32_base64:encodeU32(leafPatch.patchIds),
      lidar_band_patch_id_u32_base64:encodeU32(lidarPatch.patchIds),
    },
    summary:{
      leaf_transition_byte:distribution([...leafTransition].map((value,index)=>decoded.leafValid[index]?value:null)),
      lidar_profile_transition_byte:distribution([...lidarTransition].map((value,index)=>decoded.lidarValid[index]?value:null)),
      leaf_quartile_patches:{
        class_summary:leafPatch.class_summary,
        transition_edge_m:leafPatch.transition_edge_m,
        transition_edge_density_m_per_ha:leafPatch.transition_edge_density_m_per_ha,
        adjacency_edge_m:leafPatch.adjacency_edge_m,
      },
      lidar_dominant_band_patches:{
        class_summary:lidarPatch.class_summary,
        transition_edge_m:lidarPatch.transition_edge_m,
        transition_edge_density_m_per_ha:lidarPatch.transition_edge_density_m_per_ha,
        adjacency_edge_m:lidarPatch.adjacency_edge_m,
      },
    },
  }
}

export async function buildSpatialPatternArtifact(args:{
  localGeometry:GeoJsonGeometry
  domainIdentitySha256:string
  domainAlgorithmVersion:string
  landscapePhysicalIdentitySha256:string
  resourceEdgeIdentitySha256:string
  resourceEdgeContext:any
  landscapeStructureIdentitySha256:string
  landscapeStructureArtifactSha256:string
  landscapeStructureArtifact:any
  fetchImpl?:typeof fetch
}) {
  const fetchImpl=args.fetchImpl||fetch
  const canopyGrid=await sampleMetricGrid(
    buildMetricGrid(args.localGeometry,FARM_WATCH_SPATIAL_PATTERN_PRODUCT.canopyCellMeters),
    FARM_WATCH_SPATIAL_PATTERN_PRODUCT.canopySourceUrl,
    {
      mosaicRule:JSON.stringify({
        mosaicMethod:'esriMosaicNorthwest',
        where:'beginyear = ' + FARM_WATCH_SPATIAL_PATTERN_PRODUCT.canopyYear,
      }),
    },
    fetchImpl,
  )
  const canopyPercent=new Uint8Array(canopyGrid.values.length)
  const canopyClass=new Uint8Array(canopyGrid.values.length)
  const canopyValid=new Uint8Array(canopyGrid.values.length)
  for(let i=0;i<canopyGrid.values.length;i+=1) {
    const value=canopyGrid.values[i]
    if(!canopyGrid.domain_valid[i] || !Number.isFinite(value)) continue
    const bounded=Math.max(0,Math.min(100,Math.round(Number(value))))
    canopyValid[i]=1
    canopyPercent[i]=bounded
    canopyClass[i]=bounded<=FARM_WATCH_SPATIAL_PATTERN_PRODUCT.canopyClassBreaks[0]
      ? 1
      : bounded<=FARM_WATCH_SPATIAL_PATTERN_PRODUCT.canopyClassBreaks[1]
        ? 2
        : 3
  }
  const canopyPatches=categoricalPatchMetrics(
    canopyClass,canopyValid,canopyGrid.width,canopyGrid.height,
    FARM_WATCH_SPATIAL_PATTERN_PRODUCT.canopyCellMeters,
    FARM_WATCH_SPATIAL_PATTERN_PRODUCT.patchNeighborRule,
  )
  const field=mappedFieldPattern(
    canopyGrid,
    args.resourceEdgeContext?.field_area_geojson || null,
    args.resourceEdgeContext?.field_edge_geojson || null,
  )
  const structure=structureTransitionPattern(args.landscapeStructureArtifact)
  const sampledSourceSha256=await sha256Hex(JSON.stringify({
    canopy:canopyGrid.values,
    resource_edge_identity:args.resourceEdgeIdentitySha256,
    landscape_structure_artifact_sha256:args.landscapeStructureArtifactSha256,
  }))

  const artifact={
    schema:FARM_WATCH_SPATIAL_PATTERN_PRODUCT.outputSchemaVersion,
    method:FARM_WATCH_SPATIAL_PATTERN_PRODUCT.algorithmVersion,
    status:'available',
    evidence_class:FARM_WATCH_SPATIAL_PATTERN_PRODUCT.evidenceClass,
    domain:{
      identity_sha256:args.domainIdentitySha256,
      algorithm_version:args.domainAlgorithmVersion,
      radius_m:500,
      barrier_aware:true,
    },
    dependencies:{
      landscape_physical_identity_sha256:args.landscapePhysicalIdentitySha256,
      resource_edge_identity_sha256:args.resourceEdgeIdentitySha256,
      landscape_structure_identity_sha256:args.landscapeStructureIdentitySha256,
      landscape_structure_artifact_sha256:args.landscapeStructureArtifactSha256,
    },
    canopy_pattern:{
      source:{
        authority:'USDA Forest Service / Multi-Resolution Land Characteristics Consortium',
        product:'National Annual Tree Canopy Cover (NLCD TCC) CONUS',
        year:FARM_WATCH_SPATIAL_PATTERN_PRODUCT.canopyYear,
        product_version:FARM_WATCH_SPATIAL_PATTERN_PRODUCT.canopyProductVersion,
        class_breaks_percent:FARM_WATCH_SPATIAL_PATTERN_PRODUCT.canopyClassBreaks,
      },
      grid:{
        native_crs:canopyGrid.native_crs,
        bbox:canopyGrid.bbox,
        cell_meters:canopyGrid.cell_meters,
        width:canopyGrid.width,
        height:canopyGrid.height,
        encoding:'base64-packed-little-endian-v1',
        domain_valid_base64:encodeU8(canopyGrid.domain_valid),
        canopy_percent_u8_base64:encodeU8(canopyPercent),
        canopy_class_u8_base64:encodeU8(canopyClass),
        patch_id_u32_base64:encodeU32(canopyPatches.patchIds),
        mapped_field_mask_u8_base64:encodeU8(field.fieldMask),
        mapped_field_edge_distance_m_u16_base64:encodeU16(field.distance),
      },
      patch_metrics:{
        neighbor_rule:FARM_WATCH_SPATIAL_PATTERN_PRODUCT.patchNeighborRule,
        class_summary:canopyPatches.class_summary,
        transition_edge_m:canopyPatches.transition_edge_m,
        transition_edge_density_m_per_ha:canopyPatches.transition_edge_density_m_per_ha,
        adjacency_edge_m:canopyPatches.adjacency_edge_m,
      },
      field_edge_context:{
        projected_segment_count:field.segmentCount,
        source_boundary_quality:args.resourceEdgeContext?.context?.boundary_quality || [],
        nearest_mapped_field:args.resourceEdgeContext?.context?.nearest_mapped_field || null,
        interpretation_boundary:
          'Distance is to currently mapped field-edge geometry only and inherits the source boundary precision.',
      },
    },
    structure_pattern:structure,
    source_provenance:{
      canopy_operation:'ImageServer/getSamples',
      analysis_crs:EPSG_32616,
      sampled_source_sha256:sampledSourceSha256,
      structure_reuse:'existing central landscape-structure artifact only; no COPC or imagery recomputation',
    },
    scoring_performed:false,
    behavioral_inference_performed:false,
    interpretation_boundary:
      'Neutral canopy, mapped-field, and physical-structure patch/edge/transition geometry only. No security-cover, corridor, funnel, forage, bedding, habitat, animal-use, or hunting inference is performed.',
  }
  return {artifact,sampledSourceSha256}
}
