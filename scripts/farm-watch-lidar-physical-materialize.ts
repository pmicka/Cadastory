#!/usr/bin/env -S deno run --allow-env --allow-net

import proj4 from 'npm:proj4@2.12.1'
import { Copc, Las } from 'https://esm.unpkg.com/copc@0.0.9?target=es2022'
import { FARM_WATCH_GITHUB_OIDC_AUDIENCE } from '../supabase/functions/_shared/github-actions-oidc.ts'

const EDGE_URL =
  'https://ufpkjaadmmpmeogzhrcq.supabase.co/functions/v1/farm-watch-lidar-worker'
const LAZ_PERF_VERSION = '0.0.7'
const LAZ_PERF_ASSET_BASE =
  'https://cdn.jsdelivr.net/npm/laz-perf@' + LAZ_PERF_VERSION + '/lib/'
const LAZ_PERF_WASM_URL = LAZ_PERF_ASSET_BASE + 'laz-perf.wasm'
const US_SURVEY_FEET_PER_METER = 3937 / 1200
const NOISE_CLASSIFICATIONS = new Set([7, 18])
const CRS_DEFS: Record<string, string> = {
  'EPSG:3089':
    '+proj=lcc +lat_0=36.3333333333333 +lon_0=-85.75 +lat_1=37.0833333333333 +lat_2=38.6666666667 +x_0=1500000 +y_0=999999.999898399 +datum=NAD83 +units=us-ft +no_defs +type=crs',
  'EPSG:6473':
    '+proj=lcc +lat_0=36.3333333333333 +lon_0=-85.75 +lat_1=37.0833333333333 +lat_2=38.6666666667 +x_0=1500000 +y_0=999999.9998984 +ellps=GRS80 +units=us-ft +no_defs +type=crs',
}
for (const [code, definition] of Object.entries(CRS_DEFS)) proj4.defs(code, definition)

function arg(name: string, fallback: string | null = null) {
  const index = Deno.args.indexOf(name)
  if (index < 0) return fallback
  const value = Deno.args[index + 1]
  if (!value || value.startsWith('--')) throw new Error(name + ' requires a value')
  return value
}
const propertySlug = arg('--property', 'validation-property-01')!

function flattenPositions(value: any, out: Array<[number, number]> = []) {
  if (!Array.isArray(value)) return out
  if (
    value.length >= 2 &&
    Number.isFinite(Number(value[0])) &&
    Number.isFinite(Number(value[1]))
  ) {
    out.push([Number(value[0]), Number(value[1])])
    return out
  }
  for (const child of value) flattenPositions(child, out)
  return out
}

function geometryBbox(geometry: any) {
  const points = flattenPositions(geometry?.coordinates)
  if (!points.length) return null
  let west = Infinity
  let south = Infinity
  let east = -Infinity
  let north = -Infinity
  for (const [x, y] of points) {
    west = Math.min(west, x)
    south = Math.min(south, y)
    east = Math.max(east, x)
    north = Math.max(north, y)
  }
  return [west, south, east, north]
}

function projectCoordinates(value: any, crs: string): any {
  if (!Array.isArray(value)) return value
  if (
    value.length >= 2 &&
    Number.isFinite(Number(value[0])) &&
    Number.isFinite(Number(value[1]))
  ) {
    return proj4('EPSG:4326', crs, [Number(value[0]), Number(value[1])])
  }
  return value.map((child) => projectCoordinates(child, crs))
}

function projectGeometry(geometry: any, crs: string) {
  return { type: geometry.type, coordinates: projectCoordinates(geometry.coordinates, crs) }
}

function pointInRing(x: number, y: number, ring: any[]) {
  let inside = false
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const xi = Number(ring[i][0])
    const yi = Number(ring[i][1])
    const xj = Number(ring[j][0])
    const yj = Number(ring[j][1])
    const crosses = ((yi > y) !== (yj > y)) &&
      (x < ((xj - xi) * (y - yi)) / ((yj - yi) || Number.EPSILON) + xi)
    if (crosses) inside = !inside
  }
  return inside
}

function pointInPolygon(x: number, y: number, rings: any[]) {
  if (!rings?.length || !pointInRing(x, y, rings[0])) return false
  for (let index = 1; index < rings.length; index += 1) {
    if (pointInRing(x, y, rings[index])) return false
  }
  return true
}

function pointInGeometry(x: number, y: number, geometry: any) {
  if (geometry?.type === 'Polygon') return pointInPolygon(x, y, geometry.coordinates)
  if (geometry?.type === 'MultiPolygon') {
    return geometry.coordinates.some((polygon: any[]) => pointInPolygon(x, y, polygon))
  }
  return false
}

function bboxIntersects(a: number[] | null, b: number[] | null) {
  return Boolean(a && b) &&
    Number(a![0]) <= Number(b![2]) && Number(a![2]) >= Number(b![0]) &&
    Number(a![1]) <= Number(b![3]) && Number(a![3]) >= Number(b![1])
}

function bboxContains(bbox: number[], x: number, y: number) {
  return x >= bbox[0] && x <= bbox[2] && y >= bbox[1] && y <= bbox[3]
}

function expandBbox(bbox: number[], distance: number) {
  return [bbox[0] - distance, bbox[1] - distance, bbox[2] + distance, bbox[3] + distance]
}

function detectNativeCrs(wkt: unknown) {
  const value = String(wkt || '')
  if (/\b6473\b/.test(value) || /NAD83\(2011\).*Kentucky.*Single/i.test(value)) return 'EPSG:6473'
  if (/\b3089\b/.test(value) || /NAD83[^\n]*Kentucky.*Single/i.test(value)) return 'EPSG:3089'
  return null
}

function parseKey(key: string) {
  const parts = String(key).split('-').map(Number)
  return parts.length === 4 && parts.every(Number.isFinite) ? parts : null
}

function keyBounds2d(key: string, cube: number[]) {
  const parsed = parseKey(key)
  if (!parsed) return null
  const [depth, x, y] = parsed
  const side = (cube[3] - cube[0]) / (2 ** depth)
  return [
    cube[0] + x * side,
    cube[1] + y * side,
    cube[0] + (x + 1) * side,
    cube[1] + (y + 1) * side,
  ]
}

async function collectIntersectingNodes(assetUrl: string, copc: any, queryBbox: number[]) {
  const nodes = new Map<string, any>()
  const queue = [copc.info.rootHierarchyPage]
  const seenPages = new Set<string>()
  while (queue.length) {
    const page = queue.shift()
    const pageIdentity = page.pageOffset + ':' + page.pageLength
    if (seenPages.has(pageIdentity)) continue
    seenPages.add(pageIdentity)

    const subtree = await Copc.loadHierarchyPage(assetUrl, page)
    for (const [key, node] of Object.entries(subtree.nodes || {})) {
      if (!node || !((node as any).pointCount > 0)) continue
      const bounds = keyBounds2d(key, copc.info.cube)
      if (bboxIntersects(bounds, queryBbox)) nodes.set(key, node)
    }
    for (const [key, childPage] of Object.entries(subtree.pages || {})) {
      if (!childPage) continue
      const bounds = keyBounds2d(key, copc.info.cube)
      if (bboxIntersects(bounds, queryBbox)) queue.push(childPage)
    }
  }
  return nodes
}

function createGroundGrid(bbox: number[], cellSize: number) {
  const width = Math.max(1, Math.ceil((bbox[2] - bbox[0]) / cellSize))
  const height = Math.max(1, Math.ceil((bbox[3] - bbox[1]) / cellSize))
  return {
    bbox, cellSize, width, height,
    sum: new Float64Array(width * height),
    count: new Uint32Array(width * height),
  }
}

function gridCellIndex(grid: any, x: number, y: number) {
  const col = Math.floor((x - grid.bbox[0]) / grid.cellSize)
  const row = Math.floor((y - grid.bbox[1]) / grid.cellSize)
  if (col < 0 || row < 0 || col >= grid.width || row >= grid.height) return -1
  return row * grid.width + col
}

function addGroundSample(grid: any, x: number, y: number, z: number) {
  if (!Number.isFinite(z)) return false
  const index = gridCellIndex(grid, x, y)
  if (index < 0) return false
  grid.sum[index] += z
  grid.count[index] += 1
  return true
}

function finalizeGroundSurface(grid: any, radiusNative: number) {
  const length = grid.width * grid.height
  const direct = new Float64Array(length)
  direct.fill(Number.NaN)
  const surface = new Float64Array(length)
  surface.fill(Number.NaN)

  for (let index = 0; index < length; index += 1) {
    if (!grid.count[index]) continue
    const z = grid.sum[index] / grid.count[index]
    direct[index] = z
    surface[index] = z
  }

  const radiusCells = Math.max(1, Math.ceil(radiusNative / grid.cellSize))
  const radiusSquared = radiusCells * radiusCells
  for (let row = 0; row < grid.height; row += 1) {
    for (let col = 0; col < grid.width; col += 1) {
      const targetIndex = row * grid.width + col
      if (Number.isFinite(surface[targetIndex])) continue
      let weightedSum = 0
      let weightTotal = 0
      for (let dy = -radiusCells; dy <= radiusCells; dy += 1) {
        const rr = row + dy
        if (rr < 0 || rr >= grid.height) continue
        for (let dx = -radiusCells; dx <= radiusCells; dx += 1) {
          const d2 = dx * dx + dy * dy
          if (!d2 || d2 > radiusSquared) continue
          const cc = col + dx
          if (cc < 0 || cc >= grid.width) continue
          const z = direct[rr * grid.width + cc]
          if (!Number.isFinite(z)) continue
          const weight = 1 / d2
          weightedSum += z * weight
          weightTotal += weight
        }
      }
      if (weightTotal > 0) surface[targetIndex] = weightedSum / weightTotal
    }
  }
  return { ...grid, direct, surface, radiusNative }
}

function surfaceValueAt(surface: any, x: number, y: number) {
  const centeredX = (x - surface.bbox[0]) / surface.cellSize - 0.5
  const centeredY = (y - surface.bbox[1]) / surface.cellSize - 0.5
  const col0 = Math.floor(centeredX)
  const row0 = Math.floor(centeredY)
  const tx = centeredX - col0
  const ty = centeredY - row0
  if (col0 >= 0 && row0 >= 0 && col0 + 1 < surface.width && row0 + 1 < surface.height) {
    const i00 = row0 * surface.width + col0
    const z00 = surface.surface[i00]
    const z10 = surface.surface[i00 + 1]
    const z01 = surface.surface[i00 + surface.width]
    const z11 = surface.surface[i00 + surface.width + 1]
    if ([z00, z10, z01, z11].every(Number.isFinite)) {
      return z00 * (1 - tx) * (1 - ty) +
        z10 * tx * (1 - ty) +
        z01 * (1 - tx) * ty +
        z11 * tx * ty
    }
  }
  const col = Math.max(0, Math.min(surface.width - 1, Math.round(centeredX)))
  const row = Math.max(0, Math.min(surface.height - 1, Math.round(centeredY)))
  const nearest = surface.surface[row * surface.width + col]
  return Number.isFinite(nearest) ? nearest : null
}

function parcelSurfaceCoverage(surface: any, geometry: any) {
  let parcelCells = 0
  let directCells = 0
  let supportedCells = 0
  for (let row = 0; row < surface.height; row += 1) {
    const y = surface.bbox[1] + (row + 0.5) * surface.cellSize
    for (let col = 0; col < surface.width; col += 1) {
      const x = surface.bbox[0] + (col + 0.5) * surface.cellSize
      if (!pointInGeometry(x, y, geometry)) continue
      parcelCells += 1
      const index = row * surface.width + col
      if (Number.isFinite(surface.direct[index])) directCells += 1
      if (Number.isFinite(surface.surface[index])) supportedCells += 1
    }
  }
  return { parcelCells, directCells, supportedCells }
}

function createBandGrid(bbox: number[], cellSize: number, thresholds: number[]) {
  const width = Math.max(1, Math.ceil((bbox[2] - bbox[0]) / cellSize))
  const height = Math.max(1, Math.ceil((bbox[3] - bbox[1]) / cellSize))
  const bandCount = thresholds.length + 1
  return {
    bbox, cellSize, width, height, thresholds: thresholds.slice(), bandCount,
    total: new Uint32Array(width * height),
    counts: new Uint32Array(width * height * bandCount),
  }
}

function addBandSample(grid: any, x: number, y: number, height: number) {
  const index = gridCellIndex(grid, x, y)
  if (index < 0 || !Number.isFinite(height) || height < 0) return false
  let band = grid.thresholds.length
  for (let i = 0; i < grid.thresholds.length; i += 1) {
    if (height < grid.thresholds[i]) {
      band = i
      break
    }
  }
  grid.total[index] += 1
  grid.counts[index * grid.bandCount + band] += 1
  return true
}

function bandLabels(thresholds: number[]) {
  const labels = []
  let lower = 0
  for (const upper of thresholds) {
    labels.push(lower + '–' + upper + 'ft')
    lower = upper
  }
  labels.push(lower + '+ft')
  return labels
}

function sortedQuantile(values: number[], quantile: number) {
  if (!values.length) return null
  const index = (values.length - 1) * quantile
  const lower = Math.floor(index)
  const upper = Math.ceil(index)
  if (lower === upper) return values[lower]
  const weight = index - lower
  return values[lower] * (1 - weight) + values[upper] * weight
}

function summarizeBandGrid(grid: any, geometry: any, minReturns: number) {
  const labels = bandLabels(grid.thresholds)
  const perBandShares = labels.map(() => [] as number[])
  const parcelBandTotals = new Float64Array(grid.bandCount)
  let eligibleCellCount = 0
  let parcelPointCount = 0
  for (let row = 0; row < grid.height; row += 1) {
    const y = grid.bbox[1] + (row + 0.5) * grid.cellSize
    for (let col = 0; col < grid.width; col += 1) {
      const x = grid.bbox[0] + (col + 0.5) * grid.cellSize
      if (!pointInGeometry(x, y, geometry)) continue
      const cellIndex = row * grid.width + col
      const total = grid.total[cellIndex]
      if (total < minReturns) continue
      eligibleCellCount += 1
      parcelPointCount += total
      for (let band = 0; band < grid.bandCount; band += 1) {
        const count = grid.counts[cellIndex * grid.bandCount + band]
        parcelBandTotals[band] += count
        perBandShares[band].push(count / total)
      }
    }
  }
  return {
    thresholds_ft: grid.thresholds.slice(),
    labels,
    minimum_cell_returns: minReturns,
    eligible_cell_count: eligibleCellCount,
    parcel_point_count: parcelPointCount,
    parcel_band_shares: labels.map((label, band) => ({
      band,
      label,
      share: parcelPointCount ? parcelBandTotals[band] / parcelPointCount : 0,
    })),
    cell_share_quantiles: labels.map((label, band) => {
      const values = perBandShares[band].sort((a, b) => a - b)
      return {
        band, label,
        p10: sortedQuantile(values, 0.10),
        p50: sortedQuantile(values, 0.50),
        p90: sortedQuantile(values, 0.90),
      }
    }),
  }
}

function ownerItemId(x: number, y: number, items: any[]) {
  for (const item of items) {
    if (pointInGeometry(x, y, item.projected_geometry)) return item.id
  }
  return null
}

async function freshOidcToken() {
  const requestUrl = Deno.env.get('ACTIONS_ID_TOKEN_REQUEST_URL') || ''
  const requestToken = Deno.env.get('ACTIONS_ID_TOKEN_REQUEST_TOKEN') || ''
  if (!requestUrl || !requestToken) throw new Error('GitHub Actions OIDC environment unavailable')
  const url = new URL(requestUrl)
  url.searchParams.set('audience', FARM_WATCH_GITHUB_OIDC_AUDIENCE)
  const response = await fetch(url, {
    headers: { authorization: 'Bearer ' + requestToken, accept: 'application/json' },
  })
  if (!response.ok) throw new Error('GitHub OIDC token request failed: ' + response.status)
  const payload = await response.json()
  if (!payload?.value) throw new Error('GitHub OIDC token response was empty')
  return String(payload.value)
}

async function workerRequest(body: any) {
  const token = await freshOidcToken()
  const response = await fetch(EDGE_URL, {
    method: 'POST',
    headers: {
      authorization: 'Bearer ' + token,
      'content-type': 'application/json',
      accept: 'application/json',
    },
    body: JSON.stringify({ property: propertySlug, product: 'lidar-physical-structure', ...body }),
  })
  const payload = await response.json().catch(() => ({}))
  if (!response.ok) {
    throw new Error(payload?.detail || payload?.error || ('worker API returned ' + response.status))
  }
  return payload
}

async function loadLazPerf() {
  const response = await fetch(LAZ_PERF_WASM_URL)
  if (!response.ok) throw new Error('laz-perf WASM fetch failed: ' + response.status)
  const wasmBinary = new Uint8Array(await response.arrayBuffer())
  return Las.PointData.createLazPerf({
    wasmBinary,
    locateFile: (file: string) => LAZ_PERF_ASSET_BASE + file,
  })
}

async function main() {
  const claim = await workerRequest({ operation: 'claim' })
  if (claim?.action === 'reuse') {
    console.log(JSON.stringify({ status: 'reused', build: claim.build || null }, null, 2))
    return
  }
  if (claim?.action !== 'build') {
    console.log(JSON.stringify({ status: claim?.action || 'not_claimed', build: claim.build || null }, null, 2))
    return
  }

  const buildId = String(claim.build_id)
  const leaseToken = String(claim.lease_token)
  try {
    const contract = claim.contract
    const sourceItems = Array.isArray(claim?.phase3?.processing_items)
      ? claim.phase3.processing_items.slice().sort((a: any, b: any) => String(a.id).localeCompare(String(b.id)))
      : []
    if (!sourceItems.length) throw new Error('Phase 3 processing item list is empty')

    const lazPerf = await loadLazPerf()
    const opened = []
    for (const item of sourceItems) {
      const assetUrl = String(item.primary_asset_href || '')
      if (!assetUrl) throw new Error('Phase 3 asset URL unavailable for ' + item.id)
      const copc = await Copc.create(assetUrl)
      const nativeCrs = detectNativeCrs(copc.wkt)
      if (!nativeCrs) throw new Error('native CRS unresolved for ' + item.id)
      if (nativeCrs !== contract.native_crs) {
        throw new Error('unexpected native CRS ' + nativeCrs + ' for ' + item.id)
      }
      opened.push({
        id: String(item.id),
        asset_url: assetUrl,
        asset_identity: String(item.primary_asset_identity || item.primary_asset_href || ''),
        item,
        copc,
        native_crs: nativeCrs,
        projected_geometry: projectGeometry(item.geometry, nativeCrs),
      })
    }

    const nativeCrs = String(contract.native_crs)
    const propertyGeometry = projectGeometry(claim.boundary_geojson, nativeCrs)
    const queryBbox = geometryBbox(propertyGeometry)
    if (!queryBbox) throw new Error('projected property bbox unavailable')
    const groundCellNative = Number(contract.ground_cell_meters) * US_SURVEY_FEET_PER_METER
    const groundRadiusNative = Number(contract.ground_support_radius_meters) * US_SURVEY_FEET_PER_METER
    const structureCellNative = Number(contract.structure_cell_meters) * US_SURVEY_FEET_PER_METER
    const supportBbox = expandBbox(queryBbox, groundRadiusNative)
    const groundGrid = createGroundGrid(supportBbox, groundCellNative)
    const bandGrid = createBandGrid(queryBbox, structureCellNative, contract.thresholds_ft)

    for (const source of opened) {
      source.nodes = await collectIntersectingNodes(source.asset_url, source.copc, supportBbox)
      source.candidate_point_count = [...source.nodes.values()]
        .reduce((sum: number, node: any) => sum + Number(node.pointCount || 0), 0)
    }

    let supportGroundPointCount = 0
    for (const source of opened) {
      for (const node of source.nodes.values()) {
        const view = await Copc.loadPointDataView(source.asset_url, source.copc, node, {
          lazPerf,
          include: ['X', 'Y', 'Z', 'Classification', 'Overlap', 'Withheld'],
        })
        const getX = view.getter('X')
        const getY = view.getter('Y')
        const getZ = view.getter('Z')
        const getClassification = view.getter('Classification')
        const getOverlap = view.getter('Overlap')
        const getWithheld = view.getter('Withheld')
        for (let index = 0; index < view.pointCount; index += 1) {
          const x = Number(getX(index))
          const y = Number(getY(index))
          if (
            !bboxContains(supportBbox, x, y) ||
            ownerItemId(x, y, opened) !== source.id
          ) continue
          const classification = Number(getClassification(index))
          const overlap = Number(getOverlap(index))
          const withheld = Number(getWithheld(index))
          const z = Number(getZ(index))
          if (
            classification === 2 &&
            !withheld &&
            !overlap &&
            addGroundSample(groundGrid, x, y, z)
          ) supportGroundPointCount += 1
        }
      }
    }

    const groundSurface = finalizeGroundSurface(groundGrid, groundRadiusNative)
    const groundCoverage = parcelSurfaceCoverage(groundSurface, propertyGeometry)

    let primaryStructurePointCount = 0
    let normalizedStructurePointCount = 0
    let normalizationUnavailableCount = 0
    let negativeHeightCount = 0
    let belowMinusOneFootCount = 0

    for (const source of opened) {
      for (const node of source.nodes.values()) {
        const view = await Copc.loadPointDataView(source.asset_url, source.copc, node, {
          lazPerf,
          include: ['X', 'Y', 'Z', 'Classification', 'Overlap', 'Withheld'],
        })
        const getX = view.getter('X')
        const getY = view.getter('Y')
        const getZ = view.getter('Z')
        const getClassification = view.getter('Classification')
        const getOverlap = view.getter('Overlap')
        const getWithheld = view.getter('Withheld')

        for (let index = 0; index < view.pointCount; index += 1) {
          const x = Number(getX(index))
          const y = Number(getY(index))
          if (
            !pointInGeometry(x, y, propertyGeometry) ||
            ownerItemId(x, y, opened) !== source.id
          ) continue
          const z = Number(getZ(index))
          const classification = Number(getClassification(index))
          const overlap = Number(getOverlap(index))
          const withheld = Number(getWithheld(index))
          const primaryStructure =
            classification !== 2 &&
            !NOISE_CLASSIFICATIONS.has(classification) &&
            !withheld &&
            !overlap &&
            Number.isFinite(z)
          if (!primaryStructure) continue

          primaryStructurePointCount += 1
          const groundZ = surfaceValueAt(groundSurface, x, y)
          if (!Number.isFinite(groundZ)) {
            normalizationUnavailableCount += 1
            continue
          }
          const height = z - Number(groundZ)
          normalizedStructurePointCount += 1
          if (height < 0) negativeHeightCount += 1
          if (height < -1) belowMinusOneFootCount += 1
          if (height >= 0) addBandSample(bandGrid, x, y, height)
        }
      }
    }

    const currentSummary = summarizeBandGrid(
      bandGrid,
      propertyGeometry,
      Number(contract.minimum_cell_returns),
    )
    const itemDatetimes = sourceItems
      .map((item: any) => Date.parse(String(item.datetime || '')))
      .filter(Number.isFinite)
      .sort((a: number, b: number) => a - b)
    const acquisitionUtcRange = itemDatetimes.length
      ? [
          new Date(itemDatetimes[0]).toISOString(),
          new Date(itemDatetimes[itemDatetimes.length - 1]).toISOString(),
        ]
      : null

    const processingFingerprint = {
      method: 'multiasset_copc_header_and_node_selection_v1',
      source_plan_artifact_sha256: claim.source_plan_artifact_sha256,
      items: opened.map((source) => ({
        id: source.id,
        asset_identity: source.asset_identity,
        native_crs: source.native_crs,
        copc_header_point_count: Number(source.copc.header.pointCount),
        candidate_node_count: source.nodes.size,
        candidate_point_count: source.candidate_point_count,
      })),
    }

    const supportedPercent = groundCoverage.parcelCells
      ? groundCoverage.supportedCells / groundCoverage.parcelCells * 100
      : null
    const artifact = {
      schema: contract.schema,
      method: contract.method,
      source_collection: contract.source_collection,
      source_plan_artifact_sha256: claim.source_plan_artifact_sha256,
      processing_item_ids: opened.map((source) => source.id),
      native_crs: nativeCrs,
      height_unit: 'US survey ft',
      cell_meters: Number(contract.structure_cell_meters),
      minimum_cell_returns: Number(contract.minimum_cell_returns),
      acquisition_utc_range: acquisitionUtcRange,
      acquisition_time_basis: 'central STAC item datetime metadata',
      grid: {
        bbox: bandGrid.bbox,
        cellSize: bandGrid.cellSize,
        width: bandGrid.width,
        height: bandGrid.height,
        thresholds: bandGrid.thresholds,
        bandCount: bandGrid.bandCount,
        total: Array.from(bandGrid.total),
        counts: Array.from(bandGrid.counts),
      },
      current_summary: currentSummary,
      processing_summary: {
        support_ground_point_count: supportGroundPointCount,
        parcel_ground_cell_count: groundCoverage.parcelCells,
        parcel_direct_ground_cell_count: groundCoverage.directCells,
        parcel_supported_ground_cell_count: groundCoverage.supportedCells,
        ground_supported_parcel_percent: supportedPercent,
        primary_structure_point_count: primaryStructurePointCount,
        normalized_structure_point_count: normalizedStructurePointCount,
        normalization_unavailable_count: normalizationUnavailableCount,
        negative_height_count: negativeHeightCount,
        below_minus_one_foot_count: belowMinusOneFootCount,
        overlap_policy:
          'For overlapping selected item footprints, each source point is counted only by the lexicographically first selected item footprint containing that XY location.',
      },
      processing_source_fingerprint: processingFingerprint,
      interpretation_boundary:
        'Current Phase 3 physical height-above-ground evidence only. Height bands are neutral physical strata, not species, understory, habitat, bedding, mast, or animal-use classes. Historical comparison and aerial imagery are not fused into this product.',
    }

    const completed = await workerRequest({
      operation: 'complete',
      build_id: buildId,
      lease_token: leaseToken,
      artifact,
    })
    console.log(JSON.stringify({
      status: 'available',
      property: propertySlug,
      processing_item_ids: artifact.processing_item_ids,
      grid: {
        width: artifact.grid.width,
        height: artifact.grid.height,
        eligible_cell_count: artifact.current_summary.eligible_cell_count,
      },
      processing_summary: artifact.processing_summary,
      completion: completed,
    }, null, 2))
  } catch (error) {
    try {
      await workerRequest({
        operation: 'fail',
        build_id: buildId,
        lease_token: leaseToken,
        error: error instanceof Error ? error.stack || error.message : String(error),
      })
    } catch (failError) {
      console.error('Failed to report LiDAR worker failure:', failError)
    }
    throw error
  }
}

await main()
