import { Buffer } from 'node:buffer'
import proj4 from 'npm:proj4@2.12.1'
import {
  FARM_WATCH_SOLAR_EXPOSURE_PRODUCT,
  FARM_WATCH_SOLAR_TERRAIN_PRODUCT,
  requireSolarDate,
} from './farm-watch-solar-exposure-contract.ts'
import { sha256Hex } from './farm-watch-terrain.ts'

const EPSG_32616 = 'EPSG:32616'
proj4.defs(
  EPSG_32616,
  '+proj=utm +zone=16 +datum=WGS84 +units=m +no_defs +type=crs',
)

type BBox = { west: number; east: number; south: number; north: number }

type DecodedTerrainGrid = {
  native_crs: string
  bbox: BBox
  cell_meters: number
  width: number
  height: number
  domain: Uint8Array
  elevation_ft: Float64Array
  elevation_offset_ft: number
}

type DecodedCanopyGrid = {
  native_crs: string
  bbox: BBox
  cell_meters: number
  width: number
  height: number
  valid: Uint8Array
  percent: Uint8Array
}

type SupportGrid = {
  bbox: BBox
  cell_meters: number
  width: number
  height: number
  values_ft: Float64Array
  source_mask: Uint8Array
  required_cell_count: number
  available_required_cell_count: number
  primary_required_cell_count: number
  fallback_required_cell_count: number
}

function decodeU8(value: string) {
  const bytes = Buffer.from(value, 'base64')
  return new Uint8Array(bytes.buffer, bytes.byteOffset, bytes.byteLength).slice()
}

function decodeU16(value: string) {
  const bytes = Buffer.from(value, 'base64')
  if (bytes.byteLength % 2) throw new Error('u16 base64 payload has odd byte length')
  const copy = Uint8Array.from(bytes)
  return new Uint16Array(copy.buffer)
}

function encodeU8(values: Uint8Array) {
  return Buffer.from(values.buffer, values.byteOffset, values.byteLength).toString('base64')
}

function encodeU16(values: Uint16Array) {
  return Buffer.from(values.buffer, values.byteOffset, values.byteLength).toString('base64')
}

function finite(value: unknown): number | null {
  const n = Number(value)
  return Number.isFinite(n) ? n : null
}

function requireGridShape(grid: any) {
  const width = Number(grid?.width)
  const height = Number(grid?.height)
  const cell = Number(grid?.cell_meters)
  const bbox = grid?.bbox
  if (
    grid?.native_crs !== EPSG_32616 ||
    !Number.isInteger(width) || width <= 0 ||
    !Number.isInteger(height) || height <= 0 ||
    !Number.isFinite(cell) || cell <= 0 ||
    !bbox ||
    ![bbox.west,bbox.east,bbox.south,bbox.north].every(Number.isFinite)
  ) throw new Error('solar dependency grid shape is invalid')
  return { width, height, cell, bbox: bbox as BBox }
}

export function decodeTerrainGrid(grid: any): DecodedTerrainGrid {
  const shape = requireGridShape(grid)
  const domain = decodeU8(String(grid.domain_valid_base64 || ''))
  const packed = decodeU16(String(grid.elevation_tenths_ft_u16_base64 || ''))
  const count = shape.width * shape.height
  const offset = Number(grid.elevation_offset_ft)
  if (domain.length !== count || packed.length !== count || !Number.isFinite(offset)) {
    throw new Error('solar terrain dependency encoding is invalid')
  }
  const elevations = new Float64Array(count)
  elevations.fill(Number.NaN)
  for (let i = 0; i < count; i += 1) {
    if (domain[i]) elevations[i] = offset + packed[i] / 10
  }
  return {
    native_crs: EPSG_32616,
    bbox: shape.bbox,
    cell_meters: shape.cell,
    width: shape.width,
    height: shape.height,
    domain,
    elevation_ft: elevations,
    elevation_offset_ft: offset,
  }
}

export function decodeCanopyGrid(grid: any): DecodedCanopyGrid {
  const shape = requireGridShape(grid)
  const domain = decodeU8(String(grid.domain_valid_base64 || ''))
  const percent = decodeU8(String(grid.canopy_percent_u8_base64 || ''))
  const count = shape.width * shape.height
  if (domain.length !== count || percent.length !== count) {
    throw new Error('solar canopy dependency encoding is invalid')
  }
  return {
    native_crs: EPSG_32616,
    bbox: shape.bbox,
    cell_meters: shape.cell,
    width: shape.width,
    height: shape.height,
    valid: domain,
    percent,
  }
}

function cellCenter(grid: { bbox: BBox; cell_meters: number; width: number }, index: number) {
  const row = Math.floor(index / grid.width)
  const col = index % grid.width
  return {
    x: grid.bbox.west + (col + 0.5) * grid.cell_meters,
    y: grid.bbox.north - (row + 0.5) * grid.cell_meters,
  }
}

function pointIndex(grid: { bbox: BBox; cell_meters: number; width: number; height: number }, x: number, y: number) {
  const col = Math.floor((x - grid.bbox.west) / grid.cell_meters)
  const row = Math.floor((grid.bbox.north - y) / grid.cell_meters)
  if (col < 0 || col >= grid.width || row < 0 || row >= grid.height) return -1
  return row * grid.width + col
}

function targetPoints(
  grid: { bbox: BBox; cell_meters: number; width: number; height: number },
  valid: Uint8Array,
) {
  const rows: Array<{ index: number; lon: number; lat: number }> = []
  for (let index = 0; index < valid.length; index += 1) {
    if (!valid[index]) continue
    const { x, y } = cellCenter(grid, index)
    const [lon, lat] = proj4(EPSG_32616, 'EPSG:4326', [x, y])
    rows.push({ index, lon: Number(lon), lat: Number(lat) })
  }
  return rows
}

async function rasterSamples(
  sourceUrl: string,
  points: Array<[number, number]>,
  extra: Record<string, string>,
  fetchImpl: typeof fetch,
) {
  const body = new URLSearchParams({
    geometryType: 'esriGeometryMultipoint',
    geometry: JSON.stringify({ points, spatialReference: { wkid: 4326 } }),
    returnFirstValueOnly: 'true',
    f: 'json',
    ...extra,
  })
  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), 20_000)
  try {
    const response = await fetchImpl(sourceUrl.replace(/\/$/, '') + '/getSamples', {
      method: 'POST',
      signal: controller.signal,
      headers: {
        'content-type': 'application/x-www-form-urlencoded;charset=UTF-8',
        accept: 'application/json',
        'user-agent': 'Cadastory-Farm-Watch-Solar/1.0',
      },
      body,
    })
    if (!response.ok) throw new Error('solar raster samples returned ' + response.status)
    const payload = await response.json()
    if (payload?.error) throw new Error(payload.error.message || 'solar raster sample failed')
    if (!Array.isArray(payload?.samples)) throw new Error('solar raster samples unavailable')
    return payload.samples
  } finally {
    clearTimeout(timeout)
  }
}

export async function sampleTargetGrid(
  grid: { bbox: BBox; cell_meters: number; width: number; height: number },
  valid: Uint8Array,
  sourceUrl: string,
  extra: Record<string, string>,
  fetchImpl: typeof fetch,
  minimumCoverage = 0.97,
) {
  const work = targetPoints(grid, valid)
  const values = new Float64Array(valid.length)
  values.fill(Number.NaN)

  const sampleRows = async (
    rows: typeof work,
    batchSize: number,
    concurrency: number,
    tolerateBatchErrors = false,
  ) => {
    const batches: Array<typeof work> = []
    for (let offset = 0; offset < rows.length; offset += batchSize) {
      batches.push(rows.slice(offset, offset + batchSize))
    }
    for (let cursor = 0; cursor < batches.length; cursor += concurrency) {
      const group = batches.slice(cursor, cursor + concurrency)
      const results = await Promise.all(group.map(async (batch) => {
        try {
          return {
            batch,
            samples: await rasterSamples(
              sourceUrl,
              batch.map((row) => [row.lon, row.lat]),
              extra,
              fetchImpl,
            ),
          }
        } catch (error) {
          if (!tolerateBatchErrors) throw error
          return { batch, samples: [] as any[] }
        }
      }))
      for (const result of results) {
        for (const sample of result.samples) {
          const local = Number(sample.locationId)
          const target = result.batch[local]
          const value = finite(sample.value)
          if (target && value !== null) values[target.index] = value
        }
      }
    }
  }

  await sampleRows(work, 900, 4, false)

  for (const retry of [
    { batchSize: 250, concurrency: 2 },
    { batchSize: 50, concurrency: 1 },
  ]) {
    const missing = work.filter((row) => !Number.isFinite(values[row.index]))
    if (!missing.length) break
    await sampleRows(missing, retry.batchSize, retry.concurrency, true)
  }

  const available = work.reduce(
    (sum, row) => sum + (Number.isFinite(values[row.index]) ? 1 : 0),
    0,
  )
  if (
    !work.length ||
    (minimumCoverage > 0 && available / work.length < minimumCoverage)
  ) {
    throw new Error('solar raster target coverage incomplete: ' + available + '/' + work.length)
  }
  return values
}

function requiredDemSupportMask(
  target: DecodedTerrainGrid,
  support: { bbox: BBox; cell_meters: number; width: number; height: number },
) {
  const p = FARM_WATCH_SOLAR_TERRAIN_PRODUCT
  const required = new Uint8Array(support.width * support.height)

  const mark = (x: number, y: number) => {
    const index = pointIndex(support, x, y)
    if (index >= 0) required[index] = 1
  }

  const sectorAzimuths = Array.from(
    { length: p.horizonSectorCount },
    (_, index) => index * 360 / p.horizonSectorCount,
  )

  for (let index = 0; index < target.domain.length; index += 1) {
    if (!target.domain[index] || !Number.isFinite(target.elevation_ft[index])) continue
    const center = cellCenter(target, index)

    // Boundary slope/aspect derivatives may require one unmasked neighbor.
    mark(center.x - target.cell_meters, center.y)
    mark(center.x + target.cell_meters, center.y)
    mark(center.x, center.y - target.cell_meters)
    mark(center.x, center.y + target.cell_meters)

    for (const azimuthDeg of sectorAzimuths) {
      const azimuth = azimuthDeg * Math.PI / 180
      for (
        let distance = p.horizonRayStepMeters;
        distance <= p.horizonSearchRadiusMeters;
        distance += p.horizonRayStepMeters
      ) {
        mark(
          center.x + Math.sin(azimuth) * distance,
          center.y + Math.cos(azimuth) * distance,
        )
      }
    }
  }

  return required
}

async function buildDemSupport(
  target: DecodedTerrainGrid,
  fetchImpl: typeof fetch,
): Promise<SupportGrid> {
  const p = FARM_WATCH_SOLAR_TERRAIN_PRODUCT
  const cell = p.supportCellMeters
  const radius = p.horizonSearchRadiusMeters
  const bbox = {
    west: Math.floor((target.bbox.west - radius) / cell) * cell,
    east: Math.ceil((target.bbox.east + radius) / cell) * cell,
    south: Math.floor((target.bbox.south - radius) / cell) * cell,
    north: Math.ceil((target.bbox.north + radius) / cell) * cell,
  }
  const width = Math.ceil((bbox.east - bbox.west) / cell)
  const height = Math.ceil((bbox.north - bbox.south) / cell)
  const count = width * height
  if (count <= 0 || count > 180_000) throw new Error('solar DEM support grid exceeds bounded cell budget')

  const supportShape = { bbox, cell_meters: cell, width, height }
  const required = requiredDemSupportMask(target, supportShape)
  const requiredCount = required.reduce((sum, value) => sum + (value ? 1 : 0), 0)
  if (!requiredCount) throw new Error('solar DEM support requirement mask is empty')

  const values = await sampleTargetGrid(
    supportShape,
    required,
    p.demSourceUrl,
    {},
    fetchImpl,
    0,
  )
  const sourceMask = new Uint8Array(count)
  const fallbackRequired = new Uint8Array(count)
  let primaryRequiredCount = 0

  for (let index = 0; index < count; index += 1) {
    if (!required[index]) continue
    if (Number.isFinite(values[index])) {
      sourceMask[index] = 1
      primaryRequiredCount += 1
    } else {
      fallbackRequired[index] = 1
    }
  }

  const fallbackNeededCount = fallbackRequired.reduce(
    (sum, value) => sum + (value ? 1 : 0),
    0,
  )

  let fallbackRequiredCount = 0
  if (fallbackNeededCount > 0) {
    const fallbackMeters = await sampleTargetGrid(
      supportShape,
      fallbackRequired,
      p.demFallbackSourceUrl,
      {},
      fetchImpl,
      0,
    )
    for (let index = 0; index < count; index += 1) {
      if (!fallbackRequired[index] || !Number.isFinite(fallbackMeters[index])) continue
      values[index] = fallbackMeters[index] * p.demFallbackMetersToFeet
      sourceMask[index] = 2
      fallbackRequiredCount += 1
    }
  }

  const availableRequired = primaryRequiredCount + fallbackRequiredCount
  if (availableRequired !== requiredCount) {
    throw new Error(
      'solar DEM required horizon support coverage is incomplete after authoritative fallback: ' +
      availableRequired + '/' + requiredCount,
    )
  }

  return {
    bbox,
    cell_meters: cell,
    width,
    height,
    values_ft: values,
    source_mask: sourceMask,
    required_cell_count: requiredCount,
    available_required_cell_count: availableRequired,
    primary_required_cell_count: primaryRequiredCount,
    fallback_required_cell_count: fallbackRequiredCount,
  }
}

function mapExistingCanopy(
  target: DecodedTerrainGrid,
  source: DecodedCanopyGrid,
) {
  const valid = new Uint8Array(target.domain.length)
  const percent = new Uint8Array(target.domain.length)
  for (let i = 0; i < target.domain.length; i += 1) {
    if (!target.domain[i]) continue
    const { x, y } = cellCenter(target, i)
    const sourceIndex = pointIndex(source, x, y)
    if (sourceIndex < 0 || !source.valid[sourceIndex]) continue
    valid[i] = 1
    percent[i] = source.percent[sourceIndex]
  }
  return { valid, percent }
}

async function sampleCanopy(
  target: DecodedTerrainGrid,
  fetchImpl: typeof fetch,
) {
  const p = FARM_WATCH_SOLAR_TERRAIN_PRODUCT
  const values = await sampleTargetGrid(
    target,
    target.domain,
    p.canopySourceUrl,
    {
      mosaicRule: JSON.stringify({
        mosaicMethod: 'esriMosaicNorthwest',
        where: 'beginyear = ' + p.canopyYear,
      }),
    },
    fetchImpl,
  )
  const valid = new Uint8Array(target.domain.length)
  const percent = new Uint8Array(target.domain.length)
  for (let i = 0; i < target.domain.length; i += 1) {
    if (!target.domain[i] || !Number.isFinite(values[i])) continue
    valid[i] = 1
    percent[i] = Math.max(0, Math.min(100, Math.round(values[i])))
  }
  return { valid, percent, sampled: values }
}

function neighborElevation(
  grid: DecodedTerrainGrid,
  row: number,
  col: number,
) {
  if (row < 0 || row >= grid.height || col < 0 || col >= grid.width) return null
  const index = row * grid.width + col
  return grid.domain[index] && Number.isFinite(grid.elevation_ft[index])
    ? grid.elevation_ft[index]
    : null
}

function supportElevation(grid: SupportGrid, x: number, y: number) {
  const index = pointIndex(grid, x, y)
  if (index < 0) return null
  const value = grid.values_ft[index]
  return Number.isFinite(value) ? value : null
}

function terrainOrientation(target: DecodedTerrainGrid, support: SupportGrid) {
  const slope = new Uint16Array(target.domain.length)
  const aspect = new Uint16Array(target.domain.length)
  const valid = new Uint8Array(target.domain.length)
  const ftToM = 0.3048

  for (let index = 0; index < target.domain.length; index += 1) {
    if (!target.domain[index] || !Number.isFinite(target.elevation_ft[index])) continue
    const row = Math.floor(index / target.width)
    const col = index % target.width
    const center = cellCenter(target, index)
    const zc = target.elevation_ft[index]
    const left = neighborElevation(target, row, col - 1) ??
      supportElevation(support, center.x - target.cell_meters, center.y)
    const right = neighborElevation(target, row, col + 1) ??
      supportElevation(support, center.x + target.cell_meters, center.y)
    const up = neighborElevation(target, row - 1, col) ??
      supportElevation(support, center.x, center.y + target.cell_meters)
    const down = neighborElevation(target, row + 1, col) ??
      supportElevation(support, center.x, center.y - target.cell_meters)

    let dzdx: number | null = null
    let dzdyNorth: number | null = null
    if (left !== null && right !== null) {
      dzdx = ((right - left) * ftToM) / (2 * target.cell_meters)
    } else if (right !== null) {
      dzdx = ((right - zc) * ftToM) / target.cell_meters
    } else if (left !== null) {
      dzdx = ((zc - left) * ftToM) / target.cell_meters
    }
    if (down !== null && up !== null) {
      dzdyNorth = ((up - down) * ftToM) / (2 * target.cell_meters)
    } else if (up !== null) {
      dzdyNorth = ((up - zc) * ftToM) / target.cell_meters
    } else if (down !== null) {
      dzdyNorth = ((zc - down) * ftToM) / target.cell_meters
    }
    if (dzdx === null || dzdyNorth === null) continue

    const rise = Math.hypot(dzdx, dzdyNorth)
    const slopeDeg = Math.atan(rise) * 180 / Math.PI
    let aspectDeg = 0
    if (rise > 1e-9) {
      // Downslope direction, clockwise from north.
      aspectDeg = Math.atan2(-dzdx, -dzdyNorth) * 180 / Math.PI
      if (aspectDeg < 0) aspectDeg += 360
    }
    valid[index] = 1
    slope[index] = Math.max(0, Math.min(900, Math.round(slopeDeg * 10)))
    aspect[index] = Math.max(0, Math.min(3599, Math.round(aspectDeg * 10)))
  }
  return { slope, aspect, valid }
}

function terrainHorizons(target: DecodedTerrainGrid, support: SupportGrid) {
  const p = FARM_WATCH_SOLAR_TERRAIN_PRODUCT
  const sectors = Array.from(
    { length: p.horizonSectorCount },
    (_, i) => i * 360 / p.horizonSectorCount,
  )
  const horizons = sectors.map(() => new Uint8Array(target.domain.length))
  const mean = new Uint8Array(target.domain.length)
  const max = new Uint8Array(target.domain.length)
  const ftToM = 0.3048

  for (let index = 0; index < target.domain.length; index += 1) {
    if (!target.domain[index] || !Number.isFinite(target.elevation_ft[index])) continue
    const center = cellCenter(target, index)
    const z0 = target.elevation_ft[index]
    let sumHalfDegrees = 0
    let maxHalfDegrees = 0
    for (let sector = 0; sector < sectors.length; sector += 1) {
      const az = sectors[sector] * Math.PI / 180
      let horizonDeg = 0
      for (
        let distance = p.horizonRayStepMeters;
        distance <= p.horizonSearchRadiusMeters;
        distance += p.horizonRayStepMeters
      ) {
        const x = center.x + Math.sin(az) * distance
        const y = center.y + Math.cos(az) * distance
        const z = supportElevation(support, x, y)
        if (z === null) continue
        const angle = Math.atan2((z - z0) * ftToM, distance) * 180 / Math.PI
        if (angle > horizonDeg) horizonDeg = angle
      }
      const encoded = Math.max(0, Math.min(180, Math.round(horizonDeg * 2)))
      horizons[sector][index] = encoded
      sumHalfDegrees += encoded
      maxHalfDegrees = Math.max(maxHalfDegrees, encoded)
    }
    mean[index] = Math.round(sumHalfDegrees / sectors.length)
    max[index] = maxHalfDegrees
  }
  return { sectors, horizons, mean, max }
}

function encodeSolarTerrainGrid(args: {
  target: DecodedTerrainGrid
  orientation: ReturnType<typeof terrainOrientation>
  canopy: { valid: Uint8Array; percent: Uint8Array }
  horizons: ReturnType<typeof terrainHorizons>
}) {
  const packedElevation = new Uint16Array(args.target.domain.length)
  for (let i = 0; i < packedElevation.length; i += 1) {
    if (!args.target.domain[i] || !Number.isFinite(args.target.elevation_ft[i])) continue
    packedElevation[i] = Math.max(
      0,
      Math.min(65535, Math.round((args.target.elevation_ft[i] - args.target.elevation_offset_ft) * 10)),
    )
  }
  return {
    native_crs: args.target.native_crs,
    bbox: args.target.bbox,
    cell_meters: args.target.cell_meters,
    width: args.target.width,
    height: args.target.height,
    encoding: 'base64-packed-little-endian-v1',
    elevation_offset_ft: args.target.elevation_offset_ft,
    domain_valid_base64: encodeU8(args.target.domain),
    elevation_tenths_ft_u16_base64: encodeU16(packedElevation),
    slope_tenths_degree_u16_base64: encodeU16(args.orientation.slope),
    aspect_tenths_degree_u16_base64: encodeU16(args.orientation.aspect),
    orientation_valid_u8_base64: encodeU8(args.orientation.valid),
    canopy_valid_u8_base64: encodeU8(args.canopy.valid),
    canopy_percent_u8_base64: encodeU8(args.canopy.percent),
    horizon_half_degree_u8_base64: args.horizons.horizons.map(encodeU8),
    horizon_mean_half_degree_u8_base64: encodeU8(args.horizons.mean),
    horizon_max_half_degree_u8_base64: encodeU8(args.horizons.max),
  }
}

function average(values: Uint8Array, valid: Uint8Array, scale = 1) {
  let sum = 0
  let count = 0
  for (let i = 0; i < values.length; i += 1) {
    if (!valid[i]) continue
    sum += values[i] * scale
    count += 1
  }
  return count ? sum / count : null
}

export async function buildSolarTerrainArtifact(args: {
  terrainArtifact: any
  terrainMaterializationIdentitySha256: string
  terrainArtifactSha256: string
  spatialPatternArtifact: any
  spatialPatternMaterializationIdentitySha256: string
  spatialPatternArtifactSha256: string
  fetchImpl?: typeof fetch
}) {
  const fetchImpl = args.fetchImpl || fetch
  const p = FARM_WATCH_SOLAR_TERRAIN_PRODUCT
  const local = decodeTerrainGrid(args.terrainArtifact?.local_form_grid)
  const landscape = decodeTerrainGrid(args.terrainArtifact?.landscape_cost_grid)
  const existingCanopy = decodeCanopyGrid(args.spatialPatternArtifact?.canopy_pattern?.grid)

  if (local.cell_meters !== p.localCellMeters || landscape.cell_meters !== p.landscapeCellMeters) {
    throw new Error('solar terrain dependencies use unexpected target resolution')
  }

  const support = await buildDemSupport(landscape, fetchImpl)
  const localCanopy = mapExistingCanopy(local, existingCanopy)
  const landscapeCanopy = await sampleCanopy(landscape, fetchImpl)

  const localOrientation = terrainOrientation(local, support)
  const landscapeOrientation = terrainOrientation(landscape, support)
  const localHorizons = terrainHorizons(local, support)
  const landscapeHorizons = terrainHorizons(landscape, support)

  const localGrid = encodeSolarTerrainGrid({
    target: local,
    orientation: localOrientation,
    canopy: localCanopy,
    horizons: localHorizons,
  })
  const landscapeGrid = encodeSolarTerrainGrid({
    target: landscape,
    orientation: landscapeOrientation,
    canopy: landscapeCanopy,
    horizons: landscapeHorizons,
  })

  const [anchorLon, anchorLat] = proj4(EPSG_32616, 'EPSG:4326', [
    (local.bbox.west + local.bbox.east) / 2,
    (local.bbox.south + local.bbox.north) / 2,
  ])

  const supportSourceMaskSha256 = await sha256Hex(support.source_mask)
  const sampledSourceSha256 = await sha256Hex(JSON.stringify({
    dem_support: [...support.values_ft],
    dem_support_source_mask: [...support.source_mask],
    landscape_canopy: [...landscapeCanopy.sampled],
    terrain_artifact_sha256: args.terrainArtifactSha256,
    spatial_pattern_artifact_sha256: args.spatialPatternArtifactSha256,
  }))

  const artifact = {
    schema: p.outputSchemaVersion,
    method: p.algorithmVersion,
    status: 'available',
    evidence_class: p.evidenceClass,
    dependencies: {
      terrain_materialization_identity_sha256: args.terrainMaterializationIdentitySha256,
      terrain_artifact_sha256: args.terrainArtifactSha256,
      spatial_pattern_materialization_identity_sha256:
        args.spatialPatternMaterializationIdentitySha256,
      spatial_pattern_artifact_sha256: args.spatialPatternArtifactSha256,
    },
    solar_anchor: {
      latitude: Number(anchorLat),
      longitude: Number(anchorLon),
      basis: 'center of canonical local 500 m target grid',
    },
    horizon_contract: {
      sector_count: p.horizonSectorCount,
      sector_azimuth_deg: localHorizons.sectors,
      search_radius_m: p.horizonSearchRadiusMeters,
      ray_step_m: p.horizonRayStepMeters,
      dem_support_cell_m: p.supportCellMeters,
      azimuth_convention: 'degrees clockwise from true north',
      elevation_encoding: 'unsigned half degrees; 0 means unobstructed geometric horizon',
    },
    canopy_contract: {
      source: 'National Annual Tree Canopy Cover (NLCD TCC) CONUS',
      year: p.canopyYear,
      product_version: p.canopyProductVersion,
      semantics: 'percent modeled tree canopy cover; not optical transmittance',
      local_reuse: 'canonical spatial-edge-patch-context canopy grid',
      landscape_extension: 'same authoritative TCC ImageServer sampled at 30 m target centers',
    },
    local_grid: localGrid,
    landscape_grid: landscapeGrid,
    summary: {
      local_valid_cell_count: local.domain.reduce((sum, value) => sum + value, 0),
      landscape_valid_cell_count: landscape.domain.reduce((sum, value) => sum + value, 0),
      local_orientation_valid_cell_count:
        localOrientation.valid.reduce((sum, value) => sum + value, 0),
      landscape_orientation_valid_cell_count:
        landscapeOrientation.valid.reduce((sum, value) => sum + value, 0),
      local_canopy_valid_cell_count: localCanopy.valid.reduce((sum, value) => sum + value, 0),
      landscape_canopy_valid_cell_count:
        landscapeCanopy.valid.reduce((sum, value) => sum + value, 0),
      local_mean_canopy_percent: average(localCanopy.percent, localCanopy.valid),
      landscape_mean_canopy_percent: average(landscapeCanopy.percent, landscapeCanopy.valid),
      local_mean_horizon_deg: average(localHorizons.mean, local.domain, 0.5),
      landscape_mean_horizon_deg: average(landscapeHorizons.mean, landscape.domain, 0.5),
      support_dem_grid_cell_count: support.values_ft.length,
      support_dem_required_cell_count: support.required_cell_count,
      support_dem_available_required_cell_count: support.available_required_cell_count,
      support_dem_primary_required_cell_count: support.primary_required_cell_count,
      support_dem_fallback_required_cell_count: support.fallback_required_cell_count,
    },
    source_provenance: {
      terrain_target_reuse:
        'canonical terrain-form-permeability elevation grids; no target DEM resampling',
      terrain_horizon_support:
        'KyFromAbove Phase 3 DEM is primary for required orientation/horizon support. Required cells unresolved after the documented retry policy use USGS 3DEP Dynamic Elevation; combined required support must be complete.',
      dem_primary_source_url: p.demSourceUrl,
      dem_fallback_source_url: p.demFallbackSourceUrl,
      dem_fallback_meters_to_feet: p.demFallbackMetersToFeet,
      dem_support_source_mask_semantics: {
        '0': 'not required or unresolved',
        '1': 'KyFromAbove Phase 3 DEM',
        '2': 'USGS 3DEP Dynamic Elevation converted meters to feet',
      },
      dem_support_source_mask_sha256: supportSourceMaskSha256,
      canopy_source_url: p.canopySourceUrl,
      analysis_crs: EPSG_32616,
      sampled_source_sha256: sampledSourceSha256,
    },
    scoring_performed: false,
    behavioral_inference_performed: false,
    interpretation_boundary:
      'Neutral terrain orientation, geometric terrain horizon, and modeled tree-canopy-cover context only. No thermal-refuge, wildlife-use, habitat, bedding, travel, or management inference is performed.',
  }

  return { artifact, sampledSourceSha256 }
}

// NOAA-style geometric solar position. Refraction is intentionally omitted.
export function solarPositionUtc(instant: Date, latitude: number, longitude: number) {
  const rad = Math.PI / 180
  const jd = instant.getTime() / 86_400_000 + 2440587.5
  const t = (jd - 2451545.0) / 36525
  const l0 = ((280.46646 + t * (36000.76983 + t * 0.0003032)) % 360 + 360) % 360
  const m = 357.52911 + t * (35999.05029 - 0.0001537 * t)
  const e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
  const c =
    Math.sin(m * rad) * (1.914602 - t * (0.004817 + 0.000014 * t)) +
    Math.sin(2 * m * rad) * (0.019993 - 0.000101 * t) +
    Math.sin(3 * m * rad) * 0.000289
  const trueLong = l0 + c
  const omega = 125.04 - 1934.136 * t
  const apparentLong = trueLong - 0.00569 - 0.00478 * Math.sin(omega * rad)
  const meanObliq =
    23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
  const obliq = meanObliq + 0.00256 * Math.cos(omega * rad)
  const declination = Math.asin(
    Math.sin(obliq * rad) * Math.sin(apparentLong * rad),
  ) / rad
  const y = Math.tan((obliq * rad) / 2) ** 2
  const eqTime = 4 / rad * (
    y * Math.sin(2 * l0 * rad) -
    2 * e * Math.sin(m * rad) +
    4 * e * y * Math.sin(m * rad) * Math.cos(2 * l0 * rad) -
    0.5 * y * y * Math.sin(4 * l0 * rad) -
    1.25 * e * e * Math.sin(2 * m * rad)
  )

  const minutesUtc =
    instant.getUTCHours() * 60 +
    instant.getUTCMinutes() +
    instant.getUTCSeconds() / 60 +
    instant.getUTCMilliseconds() / 60000
  let trueSolarMinutes = (minutesUtc + eqTime + 4 * longitude) % 1440
  if (trueSolarMinutes < 0) trueSolarMinutes += 1440
  let hourAngle = trueSolarMinutes / 4 - 180
  if (hourAngle < -180) hourAngle += 360

  const lat = latitude * rad
  const dec = declination * rad
  const ha = hourAngle * rad
  const cosZenith = Math.max(
    -1,
    Math.min(1, Math.sin(lat) * Math.sin(dec) + Math.cos(lat) * Math.cos(dec) * Math.cos(ha)),
  )
  const elevation = 90 - Math.acos(cosZenith) / rad
  let azimuth = Math.atan2(
    Math.sin(ha),
    Math.cos(ha) * Math.sin(lat) - Math.tan(dec) * Math.cos(lat),
  ) / rad + 180
  azimuth = ((azimuth % 360) + 360) % 360

  return { elevation_deg: elevation, azimuth_deg: azimuth, declination_deg: declination, equation_of_time_min: eqTime }
}

export function geometricSolarDay(solarDate: string, latitude: number, longitude: number) {
  const date = requireSolarDate(solarDate)
  const noon = new Date(date + 'T12:00:00Z')
  const position = solarPositionUtc(noon, latitude, longitude)
  const rad = Math.PI / 180
  const lat = latitude * rad
  const dec = position.declination_deg * rad
  const cosHour = -Math.tan(lat) * Math.tan(dec)

  let sunriseMinutes = 0
  let sunsetMinutes = 1440
  if (cosHour >= 1) {
    sunriseMinutes = 720
    sunsetMinutes = 720
  } else if (cosHour <= -1) {
    sunriseMinutes = 0
    sunsetMinutes = 1440
  } else {
    const hourAngle = Math.acos(cosHour) / rad
    const solarNoon = 720 - 4 * longitude - position.equation_of_time_min
    sunriseMinutes = solarNoon - 4 * hourAngle
    sunsetMinutes = solarNoon + 4 * hourAngle
  }

  const base = Date.parse(date + 'T00:00:00Z')
  const sunrise = new Date(base + sunriseMinutes * 60_000)
  const sunset = new Date(base + sunsetMinutes * 60_000)
  const solarNoonMinutes = (sunriseMinutes + sunsetMinutes) / 2
  const daylightMinutes = Math.max(0, sunsetMinutes - sunriseMinutes)
  const third = daylightMinutes / 3
  return {
    sunrise,
    solarNoon: new Date(base + solarNoonMinutes * 60_000),
    sunset,
    daylightMinutes,
    windows: {
      morning: [sunriseMinutes, sunriseMinutes + third] as const,
      midday: [sunriseMinutes + third, sunriseMinutes + 2 * third] as const,
      evening: [sunriseMinutes + 2 * third, sunsetMinutes] as const,
      full_day: [sunriseMinutes, sunsetMinutes] as const,
    },
  }
}

export function decodeSolarTerrainGrid(grid: any) {
  const shape = requireGridShape(grid)
  const count = shape.width * shape.height
  const domain = decodeU8(String(grid.domain_valid_base64 || ''))
  const orientationValid = decodeU8(String(grid.orientation_valid_u8_base64 || ''))
  const canopyValid = decodeU8(String(grid.canopy_valid_u8_base64 || ''))
  const canopyPercent = decodeU8(String(grid.canopy_percent_u8_base64 || ''))
  const slope = decodeU16(String(grid.slope_tenths_degree_u16_base64 || ''))
  const aspect = decodeU16(String(grid.aspect_tenths_degree_u16_base64 || ''))
  const horizons = Array.isArray(grid.horizon_half_degree_u8_base64)
    ? grid.horizon_half_degree_u8_base64.map((value: string) => decodeU8(value))
    : []
  if (
    domain.length !== count || orientationValid.length !== count ||
    canopyValid.length !== count || canopyPercent.length !== count ||
    slope.length !== count || aspect.length !== count ||
    horizons.length !== FARM_WATCH_SOLAR_TERRAIN_PRODUCT.horizonSectorCount ||
    horizons.some((values: Uint8Array) => values.length !== count)
  ) throw new Error('solar terrain artifact grid encoding is invalid')
  return {
    native_crs: EPSG_32616,
    bbox: shape.bbox,
    cell_meters: shape.cell,
    width: shape.width,
    height: shape.height,
    domain,
    orientationValid,
    canopyValid,
    canopyPercent,
    slope,
    aspect,
    horizons,
  }
}

export function interpolatedHorizonDeg(
  horizonHalfDegrees: readonly number[],
  azimuthDeg: number,
) {
  const count = horizonHalfDegrees.length
  if (!count) return 0
  const step = 360 / count
  const normalized = ((azimuthDeg % 360) + 360) % 360
  const base = normalized / step
  const i0 = Math.floor(base) % count
  const i1 = (i0 + 1) % count
  const fraction = base - Math.floor(base)
  return (horizonHalfDegrees[i0] * (1 - fraction) + horizonHalfDegrees[i1] * fraction) * 0.5
}

export function directTerrainIncidence(
  solarElevationDeg: number,
  solarAzimuthDeg: number,
  slopeDeg: number,
  aspectDeg: number,
  horizonDeg: number,
) {
  if (solarElevationDeg <= 0 || solarElevationDeg <= horizonDeg) return 0
  const rad = Math.PI / 180
  const e = solarElevationDeg * rad
  const s = slopeDeg * rad
  const azDiff = (solarAzimuthDeg - aspectDeg) * rad
  return Math.max(
    0,
    Math.sin(e) * Math.cos(s) + Math.cos(e) * Math.sin(s) * Math.cos(azDiff),
  )
}

function exposureGrid(
  grid: ReturnType<typeof decodeSolarTerrainGrid>,
  solarDate: string,
  latitude: number,
  longitude: number,
) {
  const p = FARM_WATCH_SOLAR_EXPOSURE_PRODUCT
  const day = geometricSolarDay(solarDate, latitude, longitude)
  const base = Date.parse(solarDate + 'T00:00:00Z')
  const stepMinutes = p.integrationStepMinutes
  const stepHours = stepMinutes / 60
  const daylightStart = day.windows.full_day[0]
  const daylightEnd = day.windows.full_day[1]
  const windows = ['full_day','morning','midday','evening'] as const
  const terrain = Object.fromEntries(windows.map((window) => [
    window,
    new Float64Array(grid.domain.length),
  ])) as Record<typeof windows[number], Float64Array>
  let daylightSamples = 0
  const shadowed = new Uint16Array(grid.domain.length)

  for (let start = daylightStart; start < daylightEnd; start += stepMinutes) {
    const duration = Math.min(stepMinutes, daylightEnd - start)
    if (duration <= 0) continue
    const midpoint = start + duration / 2
    const instant = new Date(base + midpoint * 60_000)
    const sun = solarPositionUtc(instant, latitude, longitude)
    if (sun.elevation_deg <= 0) continue
    daylightSamples += 1
    const named =
      midpoint < day.windows.morning[1] ? 'morning' :
      midpoint < day.windows.midday[1] ? 'midday' : 'evening'
    for (let index = 0; index < grid.domain.length; index += 1) {
      if (!grid.domain[index] || !grid.orientationValid[index]) continue
      const horizonValues = grid.horizons.map((values: Uint8Array) => values[index])
      const horizon = interpolatedHorizonDeg(horizonValues, sun.azimuth_deg)
      if (sun.elevation_deg <= horizon) shadowed[index] += 1
      const incidence = directTerrainIncidence(
        sun.elevation_deg,
        sun.azimuth_deg,
        grid.slope[index] / 10,
        grid.aspect[index] / 10,
        horizon,
      )
      const contribution = incidence * (duration / 60)
      terrain.full_day[index] += contribution
      terrain[named][index] += contribution
    }
  }

  const encodedWindows: Record<string, any> = {}
  for (const window of windows) {
    const terrainPacked = new Uint16Array(grid.domain.length)
    const canopyPacked = new Uint16Array(grid.domain.length)
    for (let i = 0; i < grid.domain.length; i += 1) {
      if (!grid.domain[i] || !grid.orientationValid[i]) continue
      terrainPacked[i] = Math.max(0, Math.min(65535, Math.round(terrain[window][i] * 1000)))
      if (grid.canopyValid[i]) {
        const openFraction = 1 - grid.canopyPercent[i] / 100
        canopyPacked[i] = Math.max(
          0,
          Math.min(65535, Math.round(terrain[window][i] * openFraction * 1000)),
        )
      }
    }
    encodedWindows[window] = {
      terrain_potential_milli_sun_hours_u16_base64: encodeU16(terrainPacked),
      canopy_screened_potential_milli_sun_hours_u16_base64: encodeU16(canopyPacked),
    }
  }

  const shadowFraction = new Uint8Array(grid.domain.length)
  if (daylightSamples) {
    for (let i = 0; i < grid.domain.length; i += 1) {
      if (!grid.domain[i] || !grid.orientationValid[i]) continue
      shadowFraction[i] = Math.max(
        0,
        Math.min(255, Math.round(255 * shadowed[i] / daylightSamples)),
      )
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
      terrain_shadow_fraction_u8_base64: encodeU8(shadowFraction),
      windows: encodedWindows,
    },
    raw: { terrain, shadowFraction, daylightSamples },
    day,
  }
}

function distribution(values: number[]) {
  const sorted = values.filter(Number.isFinite).sort((a, b) => a - b)
  if (!sorted.length) return { count: 0, min: null, median: null, mean: null, max: null }
  const sum = sorted.reduce((a, b) => a + b, 0)
  return {
    count: sorted.length,
    min: sorted[0],
    median: sorted[Math.floor(sorted.length / 2)],
    mean: sum / sorted.length,
    max: sorted[sorted.length - 1],
  }
}

function windowDistribution(
  grid: ReturnType<typeof decodeSolarTerrainGrid>,
  raw: ReturnType<typeof exposureGrid>['raw'],
  window: 'full_day'|'morning'|'midday'|'evening',
) {
  const terrain: number[] = []
  const canopy: number[] = []
  for (let i = 0; i < grid.domain.length; i += 1) {
    if (!grid.domain[i] || !grid.orientationValid[i]) continue
    terrain.push(raw.terrain[window][i])
    if (grid.canopyValid[i]) {
      canopy.push(raw.terrain[window][i] * (1 - grid.canopyPercent[i] / 100))
    }
  }
  return {
    terrain_potential_sun_hours: distribution(terrain),
    canopy_screened_proxy_sun_hours: distribution(canopy),
  }
}

export async function buildSolarExposureArtifact(args: {
  solarDate: string
  solarTerrainArtifact: any
  solarTerrainMaterializationIdentitySha256: string
  solarTerrainArtifactSha256: string
}) {
  const solarDate = requireSolarDate(args.solarDate)
  const p = FARM_WATCH_SOLAR_EXPOSURE_PRODUCT
  const anchor = args.solarTerrainArtifact?.solar_anchor
  const latitude = Number(anchor?.latitude)
  const longitude = Number(anchor?.longitude)
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    throw new Error('solar terrain anchor is invalid')
  }

  const local = decodeSolarTerrainGrid(args.solarTerrainArtifact?.local_grid)
  const landscape = decodeSolarTerrainGrid(args.solarTerrainArtifact?.landscape_grid)
  const localExposure = exposureGrid(local, solarDate, latitude, longitude)
  const landscapeExposure = exposureGrid(landscape, solarDate, latitude, longitude)
  const day = localExposure.day

  const sampledSourceSha256 = await sha256Hex(JSON.stringify({
    solar_date: solarDate,
    solar_terrain_artifact_sha256: args.solarTerrainArtifactSha256,
    anchor: { latitude, longitude },
    solar_day: {
      sunrise: day.sunrise.toISOString(),
      solar_noon: day.solarNoon.toISOString(),
      sunset: day.sunset.toISOString(),
    },
  }))

  const artifact = {
    schema: p.outputSchemaVersion,
    method: p.algorithmVersion,
    status: 'available',
    evidence_class: p.evidenceClass,
    solar_date: solarDate,
    dependencies: {
      solar_terrain_materialization_identity_sha256:
        args.solarTerrainMaterializationIdentitySha256,
      solar_terrain_artifact_sha256: args.solarTerrainArtifactSha256,
    },
    solar_anchor: { latitude, longitude },
    solar_day: {
      sunrise_utc: day.sunrise.toISOString(),
      solar_noon_utc: day.solarNoon.toISOString(),
      sunset_utc: day.sunset.toISOString(),
      daylight_minutes: day.daylightMinutes,
      integration_step_minutes: p.integrationStepMinutes,
      window_rule: p.daylightWindowRule,
      windows_minutes_utc_from_date_midnight: day.windows,
      geometry: 'NOAA-style geometric solar position; atmospheric refraction omitted',
    },
    canopy_screening_proxy: {
      formula: 'terrain_potential * (1 - TCC_percent / 100)',
      semantics:
        'transparent linear canopy-open proxy only; not canopy optical transmittance or measured under-canopy irradiance',
    },
    local_grid: localExposure.encoded,
    landscape_grid: landscapeExposure.encoded,
    summary: {
      local: Object.fromEntries(
        (['full_day','morning','midday','evening'] as const).map((window) => [
          window,
          windowDistribution(local, localExposure.raw, window),
        ]),
      ),
      landscape: Object.fromEntries(
        (['full_day','morning','midday','evening'] as const).map((window) => [
          window,
          windowDistribution(landscape, landscapeExposure.raw, window),
        ]),
      ),
    },
    source_provenance: {
      solar_geometry: 'deterministic NOAA-style equations implemented locally',
      sampled_source_sha256: sampledSourceSha256,
      static_context_reuse: 'solar-terrain-context artifact only; no DEM or canopy resampling',
    },
    scoring_performed: false,
    behavioral_inference_performed: false,
    interpretation_boundary:
      'Neutral potential direct solar exposure and an explicitly linear canopy-screened proxy only. No thermal-refuge, operative-temperature, wildlife-use, habitat, bedding, travel, or management inference is performed.',
  }

  return { artifact, sampledSourceSha256 }
}
