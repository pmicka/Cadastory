import { Buffer } from 'node:buffer'
import proj4 from 'npm:proj4@2.12.1'
import {
  FARM_WATCH_HORIZONTAL_VISIBILITY_LIMITATIONS,
  FARM_WATCH_HORIZONTAL_VISIBILITY_PRODUCT as P,
} from './farm-watch-horizontal-visibility-contract.ts'
import { sha256Hex } from './farm-watch-terrain.ts'

const EPSG_32616 = 'EPSG:32616'
const EPSG_6473 = 'EPSG:6473'
const EPSG_6473_DEF =
  '+proj=lcc +lat_0=36.3333333333333 +lon_0=-85.75 +lat_1=37.0833333333333 +lat_2=38.6666666667 +x_0=1500000 +y_0=999999.9998984 +ellps=GRS80 +units=us-ft +no_defs +type=crs'
proj4.defs(EPSG_6473, EPSG_6473_DEF)

const US_SURVEY_FOOT_M = 0.3048006096012192

type BBox = { west: number; east: number; south: number; north: number }

type TerrainGrid = {
  bbox: BBox
  cell_meters: number
  width: number
  height: number
  domain: Uint8Array
  elevation: Float64Array
}

type StructureGrid = {
  bbox: [number, number, number, number]
  cell_size_native: number
  width: number
  height: number
  domain: Uint8Array
  property: Uint8Array
  lidarValid: Uint8Array
  bandShares: Uint8Array[]
}

type AffineTransform = {
  originX: number
  originY: number
  originNativeX: number
  originNativeY: number
  nativePerMetricX: [number, number]
  nativePerMetricY: [number, number]
  metricPerNativeX: [number, number]
  metricPerNativeY: [number, number]
}

function decodeU8(value: unknown) {
  const bytes = Buffer.from(String(value || ''), 'base64')
  return Uint8Array.from(bytes)
}

function decodeU16(value: unknown) {
  const bytes = Uint8Array.from(Buffer.from(String(value || ''), 'base64'))
  if (bytes.byteLength % 2) throw new Error('visibility u16 payload has odd byte length')
  return new Uint16Array(bytes.buffer)
}

function encodeU8(values: Uint8Array) {
  return Buffer.from(values).toString('base64')
}

function encodeU16(values: Uint16Array) {
  return Buffer.from(new Uint8Array(values.buffer, values.byteOffset, values.byteLength)).toString('base64')
}

function quantile(values: number[], q: number) {
  if (!values.length) return null
  const sorted = values.slice().sort((a, b) => a - b)
  const position = (sorted.length - 1) * q
  const lower = Math.floor(position)
  const upper = Math.ceil(position)
  if (lower === upper) return sorted[lower]
  const weight = position - lower
  return sorted[lower] * (1 - weight) + sorted[upper] * weight
}

function distribution(values: number[]) {
  const clean = values.filter(Number.isFinite)
  return {
    count: clean.length,
    p10: quantile(clean, 0.10),
    median: quantile(clean, 0.50),
    p90: quantile(clean, 0.90),
  }
}

function decodeTerrainGrid(value: any): TerrainGrid {
  const grid = value?.local_form_grid
  const width = Number(grid?.width)
  const height = Number(grid?.height)
  const count = width * height
  const domain = decodeU8(grid?.domain_valid_base64)
  const packed = decodeU16(grid?.elevation_tenths_ft_u16_base64)
  const offset = Number(grid?.elevation_offset_ft)
  if (
    grid?.native_crs !== EPSG_32616 ||
    !Number.isInteger(width) || width <= 1 ||
    !Number.isInteger(height) || height <= 1 ||
    Number(grid?.cell_meters) !== P.terrainSourceCellMeters ||
    !grid?.bbox ||
    ![grid.bbox.west, grid.bbox.east, grid.bbox.south, grid.bbox.north].every(Number.isFinite) ||
    domain.length !== count || packed.length !== count || !Number.isFinite(offset)
  ) throw new Error('horizontal visibility terrain dependency is invalid')

  const elevation = new Float64Array(count)
  elevation.fill(Number.NaN)
  for (let index = 0; index < count; index += 1) {
    if (domain[index]) elevation[index] = offset + packed[index] / 10
  }
  return {
    bbox: grid.bbox,
    cell_meters: Number(grid.cell_meters),
    width,
    height,
    domain,
    elevation,
  }
}

function decodeStructureGrid(value: any): StructureGrid {
  const grid = value?.combined_grid
  const width = Number(grid?.width)
  const height = Number(grid?.height)
  const count = width * height
  const domain = decodeU8(grid?.domain_valid_base64)
  const property = decodeU8(grid?.property_mask_base64)
  const lidarValid = decodeU8(grid?.lidar_valid_base64)
  const bandShares = Array.isArray(grid?.lidar_band_shares_base64)
    ? grid.lidar_band_shares_base64.map((value: unknown) => decodeU8(value))
    : []
  const bbox = grid?.bbox
  const cellSizeNative = Number(grid?.cell_size_native)
  if (
    grid?.native_crs !== EPSG_6473 ||
    !Array.isArray(bbox) || bbox.length !== 4 || !bbox.every(Number.isFinite) ||
    !Number.isFinite(cellSizeNative) || cellSizeNative <= 0 ||
    Number(grid?.cell_meters) !== P.outputCellMeters ||
    !Number.isInteger(width) || width <= 0 || !Number.isInteger(height) || height <= 0 ||
    domain.length !== count || property.length !== count || lidarValid.length !== count ||
    bandShares.length !== 5 || bandShares.some((band) => band.length !== count)
  ) throw new Error('horizontal visibility structure dependency is invalid')
  return {
    bbox: bbox as [number, number, number, number],
    cell_size_native: cellSizeNative,
    width,
    height,
    domain,
    property,
    lidarValid,
    bandShares,
  }
}

function buildAffine(): AffineTransform {
  const originX = 680000
  const originY = 4240000
  const origin = proj4(EPSG_32616, EPSG_6473, [originX, originY])
  const xStep = proj4(EPSG_32616, EPSG_6473, [originX + 1000, originY])
  const yStep = proj4(EPSG_32616, EPSG_6473, [originX, originY + 1000])
  const nx = [
    (Number(xStep[0]) - Number(origin[0])) / 1000,
    (Number(yStep[0]) - Number(origin[0])) / 1000,
  ] as [number, number]
  const ny = [
    (Number(xStep[1]) - Number(origin[1])) / 1000,
    (Number(yStep[1]) - Number(origin[1])) / 1000,
  ] as [number, number]
  const determinant = nx[0] * ny[1] - nx[1] * ny[0]
  if (!Number.isFinite(determinant) || Math.abs(determinant) < 1e-12) {
    throw new Error('horizontal visibility CRS transform is degenerate')
  }
  return {
    originX,
    originY,
    originNativeX: Number(origin[0]),
    originNativeY: Number(origin[1]),
    nativePerMetricX: nx,
    nativePerMetricY: ny,
    metricPerNativeX: [ny[1] / determinant, -nx[1] / determinant],
    metricPerNativeY: [-ny[0] / determinant, nx[0] / determinant],
  }
}

function metricToNative(transform: AffineTransform, x: number, y: number) {
  const dx = x - transform.originX
  const dy = y - transform.originY
  return [
    transform.originNativeX + transform.nativePerMetricX[0] * dx + transform.nativePerMetricX[1] * dy,
    transform.originNativeY + transform.nativePerMetricY[0] * dx + transform.nativePerMetricY[1] * dy,
  ] as [number, number]
}

function nativeToMetric(transform: AffineTransform, x: number, y: number) {
  const dx = x - transform.originNativeX
  const dy = y - transform.originNativeY
  return [
    transform.originX + transform.metricPerNativeX[0] * dx + transform.metricPerNativeX[1] * dy,
    transform.originY + transform.metricPerNativeY[0] * dx + transform.metricPerNativeY[1] * dy,
  ] as [number, number]
}

function structureIndex(
  grid: StructureGrid,
  transform: AffineTransform,
  x: number,
  y: number,
) {
  const [nativeX, nativeY] = metricToNative(transform, x, y)
  const col = Math.floor((nativeX - grid.bbox[0]) / grid.cell_size_native)
  const row = Math.floor((nativeY - grid.bbox[1]) / grid.cell_size_native)
  if (col < 0 || col >= grid.width || row < 0 || row >= grid.height) return -1
  return row * grid.width + col
}

function terrainElevation(grid: TerrainGrid, x: number, y: number) {
  if (
    x < grid.bbox.west || x > grid.bbox.east ||
    y < grid.bbox.south || y > grid.bbox.north
  ) return null
  const colFloat = (x - grid.bbox.west) / grid.cell_meters - 0.5
  const rowFloat = (grid.bbox.north - y) / grid.cell_meters - 0.5
  const col0 = Math.max(0, Math.min(grid.width - 2, Math.floor(colFloat)))
  const row0 = Math.max(0, Math.min(grid.height - 2, Math.floor(rowFloat)))
  const tx = Math.max(0, Math.min(1, colFloat - col0))
  const ty = Math.max(0, Math.min(1, rowFloat - row0))
  const indexes = [
    row0 * grid.width + col0,
    row0 * grid.width + col0 + 1,
    (row0 + 1) * grid.width + col0,
    (row0 + 1) * grid.width + col0 + 1,
  ]
  if (indexes.some((index) => !grid.domain[index] || !Number.isFinite(grid.elevation[index]))) return null
  const top = grid.elevation[indexes[0]] * (1 - tx) + grid.elevation[indexes[1]] * tx
  const bottom = grid.elevation[indexes[2]] * (1 - tx) + grid.elevation[indexes[3]] * tx
  return top * (1 - ty) + bottom * ty
}

function structureSupportFraction(grid: StructureGrid, index: number, rayAglM: number) {
  if (index < 0 || !grid.domain[index] || !grid.lidarValid[index]) return null
  const heightFt = Math.max(0, rayAglM / 0.3048)
  const thresholds = [4, 16, 32, 64]
  let firstBand = thresholds.findIndex((upper) => heightFt < upper)
  if (firstBand < 0) firstBand = thresholds.length
  let total = 0
  for (let band = firstBand; band < grid.bandShares.length; band += 1) {
    total += grid.bandShares[band][index] / 255
  }
  return Math.max(0, Math.min(1, total))
}

function medianOrNull(values: number[]) {
  return quantile(values, 0.5)
}

function encodeDistance(values: number[], target: number) {
  const median = medianOrNull(values)
  return median == null ? 0 : Math.max(0, Math.min(65535, Math.round(Math.min(target, median) * 10)))
}

function byteFraction(value: number | null) {
  return value == null ? 0 : Math.max(0, Math.min(255, Math.round(value * 255)))
}

function makeArray(count: number, heightCount: number, bandCount: number) {
  return {
    terrainValid: new Uint8Array(count * heightCount),
    structureValid: new Uint8Array(count * heightCount),
    terrainObstruction: new Uint8Array(count * heightCount * bandCount),
    structuralObstruction: new Uint8Array(count * heightCount * bandCount),
    combinedObstruction: new Uint8Array(count * heightCount * bandCount),
    angularOpenness: new Uint8Array(count * heightCount * bandCount),
    validDirections: new Uint8Array(count * heightCount * bandCount),
    unsupportedDirections: new Uint8Array(count * heightCount * bandCount),
    terrainVisibleDistance: new Uint16Array(count * heightCount),
    combinedVisibleDistance: new Uint16Array(count * heightCount),
  }
}

export function computeHorizontalVisibility(
  structure: StructureGrid,
  terrain: TerrainGrid,
) {
  const transform = buildAffine()
  const count = structure.width * structure.height
  const heightCount = P.observerHeightScenariosM.length
  const bandCount = P.distanceBandsMeters.length
  const out = makeArray(count, heightCount, bandCount)
  const domainMetricX = new Float64Array(count)
  const domainMetricY = new Float64Array(count)
  for (let row = 0; row < structure.height; row += 1) {
    for (let col = 0; col < structure.width; col += 1) {
      const index = row * structure.width + col
      const nativeX = structure.bbox[0] + (col + 0.5) * structure.cell_size_native
      const nativeY = structure.bbox[1] + (row + 0.5) * structure.cell_size_native
      const [x, y] = nativeToMetric(transform, nativeX, nativeY)
      domainMetricX[index] = x
      domainMetricY[index] = y
    }
  }

  const summaryRows = P.observerHeightScenariosM.map(() => ({
    terrainVisible: [] as number[],
    combinedVisible: [] as number[],
    combinedObstruction: Array.from({ length: bandCount }, () => [] as number[]),
    angularOpenness: Array.from({ length: bandCount }, () => [] as number[]),
    validDirections: Array.from({ length: bandCount }, () => 0),
    unsupportedDirections: Array.from({ length: bandCount }, () => 0),
  }))

  for (let index = 0; index < count; index += 1) {
    if (!structure.domain[index]) continue
    const observerGroundFt = terrainElevation(terrain, domainMetricX[index], domainMetricY[index])
    if (observerGroundFt == null) continue

    for (let heightIndex = 0; heightIndex < heightCount; heightIndex += 1) {
      const heightM = P.observerHeightScenariosM[heightIndex]
      const heightArrayIndex = index * heightCount + heightIndex
      const terrainDistances = Array.from({ length: bandCount }, () => [] as number[])
      const combinedDistances = Array.from({ length: bandCount }, () => [] as number[])
      const terrainObstruction = Array.from({ length: bandCount }, () => [] as number[])
      const structuralObstruction = Array.from({ length: bandCount }, () => [] as number[])
      const combinedObstruction = Array.from({ length: bandCount }, () => [] as number[])
      const terrainValidDirections = new Uint8Array(bandCount)
      const combinedValidDirections = new Uint8Array(bandCount)

      for (let azimuthIndex = 0; azimuthIndex < P.azimuthCount; azimuthIndex += 1) {
        const angle = azimuthIndex * 360 / P.azimuthCount * Math.PI / 180
        const dx = Math.sin(angle)
        const dy = Math.cos(angle)
        for (let band = 0; band < bandCount; band += 1) {
          const endpoint = P.distanceBandsMeters[band]
          const targetX = domainMetricX[index] + dx * endpoint
          const targetY = domainMetricY[index] + dy * endpoint
          const targetStructureIndex = structureIndex(structure, transform, targetX, targetY)
          const targetGroundFt = terrainElevation(terrain, targetX, targetY)
          const targetInDomain = targetStructureIndex >= 0 && Boolean(structure.domain[targetStructureIndex])
          let terrainUsable = targetInDomain && targetGroundFt != null
          let structureUsable = terrainUsable
          let terrainBlocked = false
          let structuralMax = 0
          let terrainBlockDistance: number | null = null
          let structuralBlockDistance: number | null = null

          if (terrainUsable) {
            const observerFt = observerGroundFt + heightM / 0.3048
            const targetFt = Number(targetGroundFt) + heightM / 0.3048
            for (let distance = P.rayStepMeters; distance < endpoint; distance += P.rayStepMeters) {
              const x = domainMetricX[index] + dx * distance
              const y = domainMetricY[index] + dy * distance
              const structureIndexValue = structureIndex(structure, transform, x, y)
              const terrainFt = terrainElevation(terrain, x, y)
              const inDomain = structureIndexValue >= 0 && Boolean(structure.domain[structureIndexValue])
              if (!inDomain || terrainFt == null) {
                terrainUsable = false
                structureUsable = false
                break
              }
              const rayFt = observerFt + (targetFt - observerFt) * distance / endpoint
              if (terrainFt + P.terrainIntersectionEpsilonMeters / 0.3048 >= rayFt) {
                terrainBlocked = true
                if (terrainBlockDistance == null) terrainBlockDistance = distance
              }
              if (structureUsable) {
                const rayAglM = Math.max(0, (rayFt - terrainFt) * 0.3048)
                const support = structureSupportFraction(structure, structureIndexValue, rayAglM)
                if (support == null) structureUsable = false
                else {
                  structuralMax = Math.max(structuralMax, support)
                  if (support >= P.structureSupportThreshold && structuralBlockDistance == null) {
                    structuralBlockDistance = distance
                  }
                }
              }
            }
          }

          if (terrainUsable) {
            const visible = terrainBlockDistance ?? endpoint
            terrainDistances[band].push(visible)
            terrainObstruction[band].push(terrainBlocked ? 1 : 0)
            terrainValidDirections[band] += 1
          }
          if (terrainUsable && structureUsable) {
            const structural = structuralMax
            const combined = Math.max(terrainBlocked ? 1 : 0, structural)
            const combinedVisible = Math.min(
              terrainBlockDistance ?? endpoint,
              structuralBlockDistance ?? endpoint,
            )
            combinedDistances[band].push(combinedVisible)
            structuralObstruction[band].push(structural)
            combinedObstruction[band].push(combined)
            combinedValidDirections[band] += 1
          }
        }
      }

      out.terrainValid[heightArrayIndex] = terrainValidDirections.some((value) => value > 0) ? 1 : 0
      out.structureValid[heightArrayIndex] = combinedValidDirections.some((value) => value > 0) ? 1 : 0
      for (let band = 0; band < bandCount; band += 1) {
        const offset = (heightArrayIndex * bandCount) + band
        const terrainValues = terrainObstruction[band]
        const structuralValues = structuralObstruction[band]
        const combinedValues = combinedObstruction[band]
        const valid = combinedValues.length
        out.terrainObstruction[offset] = byteFraction(terrainValues.length ?
          terrainValues.reduce((sum, value) => sum + value, 0) / terrainValues.length : null)
        out.structuralObstruction[offset] = byteFraction(structuralValues.length ?
          structuralValues.reduce((sum, value) => sum + value, 0) / structuralValues.length : null)
        out.combinedObstruction[offset] = byteFraction(valid ?
          combinedValues.reduce((sum, value) => sum + value, 0) / valid : null)
        out.angularOpenness[offset] = byteFraction(valid ?
          combinedValues.filter((value) => value < P.structureSupportThreshold).length / valid : null)
        out.validDirections[offset] = combinedValidDirections[band]
        out.unsupportedDirections[offset] = P.azimuthCount - combinedValidDirections[band]
        out.terrainVisibleDistance[heightArrayIndex] = encodeDistance(
          terrainDistances[band], P.distanceBandsMeters[band],
        )
        out.combinedVisibleDistance[heightArrayIndex] = encodeDistance(
          combinedDistances[band], P.distanceBandsMeters[band],
        )
        const rowSummary = summaryRows[heightIndex]
        if (band === bandCount - 1) {
          rowSummary.terrainVisible.push(quantile(terrainDistances[band], 0.5) || 0)
          rowSummary.combinedVisible.push(quantile(combinedDistances[band], 0.5) || 0)
        }
        if (combinedValues.length) rowSummary.combinedObstruction[band].push(
          combinedValues.reduce((sum, value) => sum + value, 0) / combinedValues.length,
        )
        if (valid) rowSummary.angularOpenness[band].push(
          combinedValues.filter((value) => value < P.structureSupportThreshold).length / valid,
        )
        rowSummary.validDirections[band] += combinedValidDirections[band]
        rowSummary.unsupportedDirections[band] += P.azimuthCount - combinedValidDirections[band]
      }
    }
  }

  return { out, domainMetricX, domainMetricY, summaryRows }
}

export async function buildHorizontalVisibilityArtifact(args: {
  landscapeStructureArtifact: any
  terrainFormArtifact: any
  landscapeDomainIdentitySha256: string
  landscapeStructureIdentitySha256: string
  landscapeStructureArtifactSha256: string
  terrainFormIdentitySha256: string
  terrainFormArtifactSha256: string
  sourceSignature: string
}) {
  const structure = decodeStructureGrid(args.landscapeStructureArtifact)
  const terrain = decodeTerrainGrid(args.terrainFormArtifact)
  const result = computeHorizontalVisibility(structure, terrain)
  const heightCount = P.observerHeightScenariosM.length
  const bandCount = P.distanceBandsMeters.length
  const sourceFingerprint = {
    landscape_domain_identity_sha256: args.landscapeDomainIdentitySha256,
    landscape_structure_identity_sha256: args.landscapeStructureIdentitySha256,
    landscape_structure_artifact_sha256: args.landscapeStructureArtifactSha256,
    terrain_form_identity_sha256: args.terrainFormIdentitySha256,
    terrain_form_artifact_sha256: args.terrainFormArtifactSha256,
    structure_grid: {
      native_crs: EPSG_6473,
      bbox: structure.bbox,
      cell_size_native: structure.cell_size_native,
      width: structure.width,
      height: structure.height,
    },
    terrain_grid: {
      native_crs: EPSG_32616,
      bbox: terrain.bbox,
      cell_meters: terrain.cell_meters,
      width: terrain.width,
      height: terrain.height,
    },
  }
  const sampledSourceSha256 = await sha256Hex(JSON.stringify(sourceFingerprint))
  const summary = {
    domain_cell_count: structure.domain.reduce((sum, value) => sum + value, 0),
    property_cell_count: structure.property.reduce((sum, value, index) =>
      sum + (structure.domain[index] && value ? 1 : 0), 0),
    structure_valid_cell_count: structure.lidarValid.reduce((sum, value, index) =>
      sum + (structure.domain[index] && value ? 1 : 0), 0),
    terrain_source_cell_meters: P.terrainSourceCellMeters,
    output_cell_meters: P.outputCellMeters,
    height_scenario_count: heightCount,
    height_scenarios: P.observerHeightScenariosM.map((height, index) => ({
      observer_height_m: height,
      target_height_m: height,
      terrain_visible_distance_m_p50_at_100m: quantile(result.summaryRows[index].terrainVisible, 0.5),
      combined_visible_distance_m_p50_at_100m: quantile(result.summaryRows[index].combinedVisible, 0.5),
      combined_obstruction_fraction_by_band: result.summaryRows[index].combinedObstruction.map(
        (values) => values.length ? values.reduce((sum, value) => sum + value, 0) / values.length : null,
      ),
      angular_openness_by_band: result.summaryRows[index].angularOpenness.map(
        (values) => values.length ? values.reduce((sum, value) => sum + value, 0) / values.length : null,
      ),
      valid_direction_total_by_band: result.summaryRows[index].validDirections,
      unsupported_direction_total_by_band: result.summaryRows[index].unsupportedDirections,
    })),
    terrain_visible_distance_distribution_m: distribution(
      result.summaryRows.flatMap((row) => row.terrainVisible),
    ),
    combined_visible_distance_distribution_m: distribution(
      result.summaryRows.flatMap((row) => row.combinedVisible),
    ),
  }
  const artifact = {
    schema: P.outputSchemaVersion,
    method: P.algorithmVersion,
    status: 'available',
    evidence_class: P.evidenceClass,
    domain: {
      identity_sha256: args.landscapeDomainIdentitySha256,
      radius_m: P.domainMeters,
      geometry: 'exact barrier-aware local_500m domain from landscape-structure-context',
    },
    dependencies: {
      landscape_structure_identity_sha256: args.landscapeStructureIdentitySha256,
      landscape_structure_artifact_sha256: args.landscapeStructureArtifactSha256,
      terrain_form_identity_sha256: args.terrainFormIdentitySha256,
      terrain_form_artifact_sha256: args.terrainFormArtifactSha256,
    },
    observer_height_scenarios: P.observerHeightScenariosM.map((height) => ({
      observer_height_m: height,
      target_height_m: height,
      semantics: P.targetHeightSemantics,
    })),
    ray_contract: {
      azimuth_count: P.azimuthCount,
      azimuth_origin: P.azimuthOrigin,
      ray_step_m: P.rayStepMeters,
      maximum_distance_m: P.maximumDistanceMeters,
      distance_bands_m: P.distanceBandsMeters,
      terrain_intersection_epsilon_m: P.terrainIntersectionEpsilonMeters,
      structure_support_threshold: P.structureSupportThreshold,
      direction_rule: '16 equally spaced azimuths; north=0 degrees; clockwise positive',
      target_rule: 'target absolute elevation is target terrain elevation plus target height; intermediate ray is linear in absolute elevation',
      structure_rule: 'maximum neutral LiDAR return-share support along the path at the ray height; bands are not interpolated into point geometry',
      missing_support_rule: 'unsupported direction is excluded from continuous summaries and is never treated as open',
    },
    grid: {
      native_crs: EPSG_6473,
      bbox: structure.bbox,
      cell_size_native: structure.cell_size_native,
      cell_meters: P.outputCellMeters,
      width: structure.width,
      height: structure.height,
      encoding: 'base64-packed-little-endian-v1',
      domain_valid_base64: encodeU8(structure.domain),
      property_mask_base64: encodeU8(structure.property),
      terrain_valid_base64: encodeU8(result.out.terrainValid),
      structure_valid_base64: encodeU8(result.out.structureValid),
      terrain_obstruction_fraction_by_band_u8_base64: encodeU8(result.out.terrainObstruction),
      structural_obstruction_fraction_by_band_u8_base64: encodeU8(result.out.structuralObstruction),
      combined_obstruction_fraction_by_band_u8_base64: encodeU8(result.out.combinedObstruction),
      angular_openness_by_band_u8_base64: encodeU8(result.out.angularOpenness),
      valid_direction_count_by_band_u8_base64: encodeU8(result.out.validDirections),
      unsupported_direction_count_by_band_u8_base64: encodeU8(result.out.unsupportedDirections),
      terrain_visible_distance_p50_tenths_m_u16_base64: encodeU16(result.out.terrainVisibleDistance),
      combined_visible_distance_p50_tenths_m_u16_base64: encodeU16(result.out.combinedVisibleDistance),
    },
    source_provenance: {
      source_signature: args.sourceSignature,
      source_fingerprint: sourceFingerprint,
      source_fingerprint_sha256: sampledSourceSha256,
      landscape_domain: 'exact current barrier-aware local_500m domain',
      structural_input: 'landscape-structure-context-v1 current compact 5 m neutral LiDAR band-share grid',
      terrain_input: 'terrain-form-permeability-v1 current local 10 m elevation grid',
      raw_lidar_processing: false,
      browser_recomputation: false,
    },
    summary,
    limitations: [...FARM_WATCH_HORIZONTAL_VISIBILITY_LIMITATIONS],
    scoring_performed: false,
    behavioral_inference_performed: false,
    interpretation_boundary:
      'Neutral physical line-of-sight and obstruction geometry only. No deer interpretation, habitat label, cover label, movement inference, or score is produced.',
  }
  return { artifact, sampledSourceSha256 }
}
