import { FARM_WATCH_LIDAR_SOURCE_PRODUCT } from './farm-watch-lidar-source.ts'

export const FARM_WATCH_LIDAR_PHYSICAL_PRODUCT = Object.freeze({
  key: 'lidar-physical-structure',
  productKind: 'lidar-physical-structure',
  algorithmVersion: 'phase3-copc-physical-v3-multiasset',
  outputSchemaVersion: 'lidar-physical-structure-v1',
  evidenceClass: 'deterministic_derived',
  artifactBucket: 'farm-watch-derived',
  artifactFormat: 'farm-watch-lidar-physical-json-v1',
  artifactMimeType: 'application/json',
  sourceCollection: 'laz-phase3',
  nativeCrs: 'EPSG:6473',
  groundCellMeters: 2,
  groundSupportRadiusMeters: 10,
  structureCellMeters: 5,
  minimumCellReturns: 10,
  thresholdsFt: [4, 16, 32, 64],
  refreshDays: 30,
})

export const FARM_WATCH_LIDAR_PHYSICAL_LIMITATIONS = Object.freeze([
  'Height bands are neutral physical height-above-ground strata, not vegetation species, understory, habitat, bedding, mast, or animal-use classes.',
  'Ground normalization uses clean Class 2 returns and deterministic local interpolation; it is not a field-surveyed terrain surface.',
  'COPC assets are combined according to the central Phase 3 coverage plan. Overlapping source footprints use deterministic item ownership to avoid duplicate counting.',
  'The product is current Phase 3 physical structure only. Historical Phase 2 comparison and temporal QA have a separate identity and lifecycle.',
])

export function lidarPhysicalSourceDescriptor(sourceArtifact: any, sourceArtifactSha256: string) {
  const collection = sourceArtifact?.collections?.find(
    (row: any) => row?.id === FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.sourceCollection,
  )
  const items = Array.isArray(collection?.processing_items)
    ? collection.processing_items.slice().sort((a: any, b: any) => String(a.id).localeCompare(String(b.id)))
    : []

  return {
    source_plan_schema: sourceArtifact?.schema || null,
    source_plan_method: sourceArtifact?.method || null,
    source_plan_artifact_sha256: sourceArtifactSha256,
    source_collection: FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.sourceCollection,
    coverage_status: collection?.coverage?.coverage_status || null,
    processing_mode: collection?.coverage?.processing_mode || null,
    sampled_parcel_coverage_percent:
      Number.isFinite(Number(collection?.coverage?.sampled_parcel_coverage_percent))
        ? Number(collection.coverage.sampled_parcel_coverage_percent)
        : null,
    items: items.map((item: any) => ({
      id: item.id,
      bbox: item.bbox || null,
      datetime: item.datetime || null,
      updated: item.updated || null,
      pc_count: item.pc_count ?? null,
      pc_density: item.pc_density ?? null,
      primary_asset_key: item.primary_asset_key || null,
      primary_asset_identity: item.primary_asset_identity || item.primary_asset_href || null,
    })),
  }
}

export function lidarPhysicalSourceSignature(sourceArtifact: any, sourceArtifactSha256: string) {
  const descriptor = lidarPhysicalSourceDescriptor(sourceArtifact, sourceArtifactSha256)
  return [
    'source_product=' + FARM_WATCH_LIDAR_SOURCE_PRODUCT.productKind,
    'source_collection=' + FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.sourceCollection,
    'source_descriptor=' + JSON.stringify(descriptor),
  ].join('|')
}

export function validateLidarPhysicalArtifact(value: any) {
  const grid = value?.grid
  const expectedLength = Number(grid?.width) * Number(grid?.height)
  return Boolean(
    value?.schema === FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.outputSchemaVersion &&
    value?.method === FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.algorithmVersion &&
    value?.source_collection === FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.sourceCollection &&
    value?.native_crs === FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.nativeCrs &&
    Array.isArray(value?.processing_item_ids) &&
    value.processing_item_ids.length > 0 &&
    /^[0-9a-f]{64}$/.test(String(value?.source_plan_artifact_sha256 || '')) &&
    grid &&
    Number.isInteger(Number(grid.width)) &&
    Number(grid.width) > 0 &&
    Number.isInteger(Number(grid.height)) &&
    Number(grid.height) > 0 &&
    Number(grid.bandCount) === FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.thresholdsFt.length + 1 &&
    Array.isArray(grid.thresholds) &&
    JSON.stringify(grid.thresholds) === JSON.stringify(FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.thresholdsFt) &&
    Array.isArray(grid.total) &&
    grid.total.length === expectedLength &&
    Array.isArray(grid.counts) &&
    grid.counts.length === expectedLength * Number(grid.bandCount) &&
    value?.current_summary &&
    Array.isArray(value.current_summary.parcel_band_shares)
  )
}

export function lidarPhysicalArtifactPath(
  propertyId: string,
  inputSignature: string,
  artifactSha256: string,
) {
  return [
    'properties',
    propertyId,
    FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.productKind,
    inputSignature,
    artifactSha256 + '.json',
  ].join('/')
}
