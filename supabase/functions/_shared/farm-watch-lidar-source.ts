export const FARM_WATCH_LIDAR_SOURCE_PRODUCT = Object.freeze({
  key: 'lidar-source-coverage',
  productKind: 'lidar-source-coverage',
  algorithmVersion: 'kyfromabove-stac-coverage-plan-v1',
  outputSchemaVersion: 'lidar-source-coverage-v1',
  evidenceClass: 'deterministic_derived',
  artifactBucket: 'farm-watch-derived',
  artifactFormat: 'farm-watch-lidar-source-json-v1',
  artifactMimeType: 'application/json',
  stacRoot: 'https://spved5ihrl.execute-api.us-west-2.amazonaws.com/',
  collections: [
    { id: 'laz-phase3', label: 'Phase 3' },
    { id: 'laz-phase2', label: 'Phase 2' },
  ],
  coverageSampleGridSize: 41,
  searchLimit: 100,
  refreshDays: 30,
})

export const FARM_WATCH_LIDAR_SOURCE_SIGNATURE = [
  'source=kyfromabove-lidar-stac',
  'stac_root=https://spved5ihrl.execute-api.us-west-2.amazonaws.com/',
  'collections=laz-phase3,laz-phase2',
  'search=POST:/search',
  'limit=100',
  'selection=all-intersecting-usable-item-footprints',
  'coverage_sample_grid=41x41',
  'provider_revision=unresolved',
].join('|')

export const FARM_WATCH_LIDAR_SOURCE_LIMITATIONS = Object.freeze([
  'STAC footprint coverage is source-selection context, not a point-density or structural-quality assessment.',
  'Sampled parcel coverage is deterministic QA for the selected footprints, not an exact polygon-union area measurement.',
  'A multi-item coverage plan does not imply that downstream multi-asset COPC processing has been completed.',
  'The KyFromAbove STAC service does not expose an immutable catalog revision in this contract, so freshness is bounded by an explicit rebuild interval.',
])

function flattenPositions(value: unknown, out: Array<[number, number]> = []) {
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
  for (const [lon, lat] of points) {
    west = Math.min(west, lon)
    south = Math.min(south, lat)
    east = Math.max(east, lon)
    north = Math.max(north, lat)
  }
  return [west, south, east, north]
}

function pointInRing(lon: number, lat: number, ring: any[]) {
  let inside = false
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const xi = Number(ring[i][0])
    const yi = Number(ring[i][1])
    const xj = Number(ring[j][0])
    const yj = Number(ring[j][1])
    const crosses = ((yi > lat) !== (yj > lat)) &&
      (lon < ((xj - xi) * (lat - yi)) / ((yj - yi) || Number.EPSILON) + xi)
    if (crosses) inside = !inside
  }
  return inside
}

function pointInGeometry(lon: number, lat: number, geometry: any) {
  const polygons = geometry?.type === 'Polygon'
    ? [geometry.coordinates]
    : geometry?.type === 'MultiPolygon'
      ? geometry.coordinates
      : []
  return polygons.some((polygon: any[]) => {
    const [outer, ...holes] = polygon || []
    if (!outer || !pointInRing(lon, lat, outer)) return false
    return !holes.some((hole) => pointInRing(lon, lat, hole))
  })
}

function geometryRings(geometry: any) {
  if (geometry?.type === 'Polygon') return geometry.coordinates || []
  if (geometry?.type === 'MultiPolygon') return (geometry.coordinates || []).flat()
  return []
}

function bboxIntersects(a: number[] | null, b: number[] | null) {
  if (!a || !b || a.length < 4 || b.length < 4) return false
  return !(a[2] < b[0] || b[2] < a[0] || a[3] < b[1] || b[3] < a[1])
}

function orientation(a: number[], b: number[], c: number[]) {
  const value = (Number(b[1]) - Number(a[1])) * (Number(c[0]) - Number(b[0])) -
    (Number(b[0]) - Number(a[0])) * (Number(c[1]) - Number(b[1]))
  if (Math.abs(value) < 1e-12) return 0
  return value > 0 ? 1 : 2
}

function onSegment(a: number[], b: number[], c: number[]) {
  return Number(b[0]) <= Math.max(Number(a[0]), Number(c[0])) + 1e-12 &&
    Number(b[0]) + 1e-12 >= Math.min(Number(a[0]), Number(c[0])) &&
    Number(b[1]) <= Math.max(Number(a[1]), Number(c[1])) + 1e-12 &&
    Number(b[1]) + 1e-12 >= Math.min(Number(a[1]), Number(c[1]))
}

function segmentsIntersect(a: number[], b: number[], c: number[], d: number[]) {
  const o1 = orientation(a, b, c)
  const o2 = orientation(a, b, d)
  const o3 = orientation(c, d, a)
  const o4 = orientation(c, d, b)
  if (o1 !== o2 && o3 !== o4) return true
  if (o1 === 0 && onSegment(a, c, b)) return true
  if (o2 === 0 && onSegment(a, d, b)) return true
  if (o3 === 0 && onSegment(c, a, d)) return true
  if (o4 === 0 && onSegment(c, b, d)) return true
  return false
}

function geometriesIntersect(a: any, b: any) {
  if (!bboxIntersects(geometryBbox(a), geometryBbox(b))) return false
  const aPoints = flattenPositions(a?.coordinates)
  const bPoints = flattenPositions(b?.coordinates)
  if (aPoints.some(([lon, lat]) => pointInGeometry(lon, lat, b))) return true
  if (bPoints.some(([lon, lat]) => pointInGeometry(lon, lat, a))) return true
  for (const aRing of geometryRings(a)) {
    for (let ai = 1; ai < aRing.length; ai += 1) {
      for (const bRing of geometryRings(b)) {
        for (let bi = 1; bi < bRing.length; bi += 1) {
          if (segmentsIntersect(aRing[ai - 1], aRing[ai], bRing[bi - 1], bRing[bi])) return true
        }
      }
    }
  }
  return false
}

function stableAssetIdentity(value: unknown) {
  const raw = String(value || '')
  if (!raw) return null
  try {
    const url = new URL(raw)
    return url.origin + url.pathname
  } catch {
    return raw.split('?')[0].split('#')[0]
  }
}

function summarizeAsset(feature: any) {
  const assets = feature?.assets || {}
  const rows = Object.entries(assets).map(([key, value]) => {
    const asset: any = value || {}
    const href = String(asset.href || '')
    const type = String(asset.type || '')
    const title = String(asset.title || '')
    const lower = (href + ' ' + type + ' ' + title).toLowerCase()
    return {
      key,
      href,
      stable_href: stableAssetIdentity(href),
      type,
      roles: Array.isArray(asset.roles) ? asset.roles : [],
      copc: lower.includes('copc') || lower.includes('.copc.laz'),
      laz: lower.includes('.laz') || lower.includes('laszip'),
    }
  })
  return rows.find((row) => row.copc) ||
    rows.find((row) => row.laz) ||
    rows.find((row) => row.roles.includes('data')) ||
    rows[0] ||
    null
}

function itemSummary(feature: any) {
  const properties = feature?.properties || {}
  const asset = summarizeAsset(feature)
  return {
    id: String(feature?.id || 'unknown'),
    bbox: Array.isArray(feature?.bbox) ? feature.bbox.map(Number) : null,
    geometry: feature?.geometry || null,
    datetime: properties.datetime || null,
    start_datetime: properties.start_datetime || null,
    end_datetime: properties.end_datetime || null,
    created: properties.created || null,
    updated: properties.updated || null,
    pc_count: Number.isFinite(Number(properties['pc:count'])) ? Number(properties['pc:count']) : null,
    pc_density: Number.isFinite(Number(properties['pc:density'])) ? Number(properties['pc:density']) : null,
    pc_type: properties['pc:type'] || null,
    pc_encoding: properties['pc:encoding'] || null,
    primary_asset_key: asset?.key || null,
    primary_asset_href: asset?.href || null,
    primary_asset_identity: asset?.stable_href || null,
    primary_asset_type: asset?.type || null,
  }
}

function sampledCoverage(boundary: any, items: any[]) {
  const bbox = geometryBbox(boundary)
  if (!bbox) return { sample_count: 0, covered_sample_count: 0, sampled_parcel_coverage_percent: null }
  const [west, south, east, north] = bbox
  const size = FARM_WATCH_LIDAR_SOURCE_PRODUCT.coverageSampleGridSize
  let sampleCount = 0
  let coveredCount = 0
  for (let row = 0; row < size; row += 1) {
    const lat = south + ((north - south) * (row + 0.5)) / size
    for (let col = 0; col < size; col += 1) {
      const lon = west + ((east - west) * (col + 0.5)) / size
      if (!pointInGeometry(lon, lat, boundary)) continue
      sampleCount += 1
      if (items.some((item) => pointInGeometry(lon, lat, item.geometry))) coveredCount += 1
    }
  }
  const coveragePercent = sampleCount ? coveredCount / sampleCount * 100 : null
  return {
    sample_count: sampleCount,
    covered_sample_count: coveredCount,
    sampled_parcel_coverage_percent: coveragePercent,
    sampled_analysis_coverage_percent: coveragePercent,
  }
}

function coveragePlan(boundary: any, items: any[]) {
  const processingItems = items
    .filter((item) => item?.primary_asset_href && item?.geometry && geometriesIntersect(boundary, item.geometry))
    .slice()
    .sort((a, b) => String(a.id).localeCompare(String(b.id)))
  const sampled = sampledCoverage(boundary, processingItems)
  const pct = sampled.sampled_parcel_coverage_percent
  return {
    method: 'all_intersecting_stac_item_footprints_v1',
    matched_item_count: items.length,
    intersecting_usable_item_count: processingItems.length,
    processing_item_ids: processingItems.map((item) => item.id),
    processing_items: processingItems,
    sample_grid_size: FARM_WATCH_LIDAR_SOURCE_PRODUCT.coverageSampleGridSize,
    ...sampled,
    coverage_status: processingItems.length === 0
      ? 'unavailable'
      : Number.isFinite(pct) && Number(pct) >= 99.5
        ? 'complete_sampled'
        : 'partial_or_unresolved',
    processing_mode: processingItems.length === 1
      ? 'single_asset_ready'
      : processingItems.length > 1
        ? 'multi_asset_required'
        : 'unavailable',
  }
}

async function searchCollection(collectionId: string, bbox: number[], fetchImpl: typeof fetch = fetch) {
  const response = await fetchImpl(FARM_WATCH_LIDAR_SOURCE_PRODUCT.stacRoot + 'search', {
    method: 'POST',
    headers: {
      accept: 'application/geo+json, application/json',
      'content-type': 'application/json',
      'user-agent': 'Cadastory-Farm-Watch-Materializer/1.0',
    },
    body: JSON.stringify({
      collections: [collectionId],
      bbox,
      limit: FARM_WATCH_LIDAR_SOURCE_PRODUCT.searchLimit,
    }),
  })
  if (!response.ok) throw new Error(`LiDAR STAC search returned ${response.status}`)
  const payload = await response.json()
  return Array.isArray(payload?.features) ? payload.features : []
}

export async function sha256Hex(value: string | Uint8Array) {
  const bytes = typeof value === 'string' ? new TextEncoder().encode(value) : value
  const owned = new Uint8Array(bytes.byteLength)
  owned.set(bytes)
  const digest = await crypto.subtle.digest('SHA-256', owned.buffer)
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('')
}

export function lidarSourceArtifactPath(propertyId: string, inputSignature: string, artifactSha256: string) {
  return [
    'properties',
    propertyId,
    FARM_WATCH_LIDAR_SOURCE_PRODUCT.productKind,
    inputSignature,
    artifactSha256 + '.json',
  ].join('/')
}

export async function buildLidarSourceArtifact(
  boundary: any,
  fetchImpl: typeof fetch = fetch,
  collectionIds: string[] | null = null,
) {
  const bbox = geometryBbox(boundary)
  if (!bbox) throw new Error('Analysis boundary bbox unavailable')
  const requestedCollections = collectionIds == null
    ? FARM_WATCH_LIDAR_SOURCE_PRODUCT.collections
    : FARM_WATCH_LIDAR_SOURCE_PRODUCT.collections.filter((collection) =>
      collectionIds.includes(collection.id)
    )
  if (!requestedCollections.length) throw new Error('No supported LiDAR collections requested')
  if (
    collectionIds != null &&
    requestedCollections.length !== new Set(collectionIds).size
  ) {
    throw new Error('One or more requested LiDAR collections are unsupported')
  }
  const collections = []
  for (const collection of requestedCollections) {
    const features = await searchCollection(collection.id, bbox, fetchImpl)
    const items = features.map(itemSummary)
    const coverage = coveragePlan(boundary, items)
    collections.push({
      id: collection.id,
      label: collection.label,
      matched_item_count: items.length,
      coverage,
      processing_items: coverage.processing_items,
      items,
    })
  }

  const artifact = {
    schema: FARM_WATCH_LIDAR_SOURCE_PRODUCT.outputSchemaVersion,
    method: FARM_WATCH_LIDAR_SOURCE_PRODUCT.algorithmVersion,
    stac_root: FARM_WATCH_LIDAR_SOURCE_PRODUCT.stacRoot,
    bbox,
    collections,
    interpretation_boundary:
      'Central source/coverage plan only. Every usable intersecting STAC footprint is retained; no first-item fallback is permitted. Coverage does not establish point-density adequacy, physical structure, or downstream multi-asset processing completeness.',
  }
  const sampledSourceSha256 = await sha256Hex(JSON.stringify(collections.map((collection) => ({
    id: collection.id,
    items: collection.processing_items.map((item: any) => ({
      id: item.id,
      updated: item.updated,
      pc_count: item.pc_count,
      pc_density: item.pc_density,
      primary_asset_key: item.primary_asset_key,
      primary_asset_identity: item.primary_asset_identity,
      bbox: item.bbox,
    })),
  }))))

  return { artifact, sampledSourceSha256 }
}
