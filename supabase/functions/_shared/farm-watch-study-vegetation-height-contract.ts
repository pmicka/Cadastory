import { FARM_WATCH_LIDAR_SOURCE_SIGNATURE } from './farm-watch-lidar-source.ts'

export const FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT = Object.freeze({
  key: 'study-aligned-vegetation-height-context',
  productKind: 'study-aligned-vegetation-height-context',
  algorithmVersion: 'wiemers-first-return-minus-ground-local500m-v1',
  outputSchemaVersion: 'study-aligned-vegetation-height-context-v2',
  evidenceClass: 'deterministic_derived',
  artifactBucket: 'farm-watch-derived',
  artifactFormat: 'farm-watch-study-aligned-vegetation-height-json-v1',
  artifactMimeType: 'application/json',
  sourceCollection: 'laz-phase3',
  nativeCrs: 'EPSG:6473',
  domainMeters: 500,
  cellMeters: 1.2,
  groundSupportRadiusMeters: 10,
  firstReturnSupportRadiusMeters: 2.4,
  heightEncoding: 'u16-centimeters+u8-support-flags-v1',
  refreshDays: 30,
})

export const FARM_WATCH_STUDY_VEGETATION_HEIGHT_LIMITATIONS = Object.freeze([
  'This is a neutral physical vegetation-height surface aligned to the Wiemers et al. first-return-elevation minus bare-ground-elevation definition. It is not a deer-use, bedding, habitat-quality, forage-quality, concealment, or thermal-selection surface.',
  'Wiemers et al. created 1.2 m DEMs from first-return and bare-ground TINs. Farm Watch preserves the 1.2 m support and first-return-minus-ground semantic variable but uses deterministic cell-mean surfaces with bounded local inverse-distance filling rather than the original ArcMap TIN interpolation.',
  'Ground elevation uses clean LAS Class 2 returns. First-return elevation uses LAS ReturnNumber = 1 while excluding withheld, overlap, and noise-class points.',
  'The exact barrier-aware local_500m domain is used so study-aligned height can be compared at the same relationship scale without turning ownership boundaries into processing boundaries.',
  'Phase 3 acquisition-time provenance inherits the current KyFromAbove source metadata discrepancy documented in FARM_WATCH_STRUCTURE_EVIDENCE_LEDGER.md; do not use this product to make unsupported temporal-change claims.',
])

export function studyVegetationHeightSourceSignature(args: {
  landscapeDomainIdentitySha256: string
  landscapeDomainAlgorithmVersion: string
}) {
  const domainIdentity = String(args.landscapeDomainIdentitySha256 || '').trim().toLowerCase()
  if (!/^[0-9a-f]{64}$/.test(domainIdentity)) {
    throw new Error('study vegetation-height domain identity is invalid')
  }
  return [
    'product=' + FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.productKind,
    'domain=barrier-aware-local-500m',
    'landscape_domain_identity_sha256=' + domainIdentity,
    'landscape_domain_algorithm=' + String(args.landscapeDomainAlgorithmVersion || ''),
    'lidar_source_contract=' + FARM_WATCH_LIDAR_SOURCE_SIGNATURE,
    'source_collection=' + FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.sourceCollection,
    'native_crs=' + FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.nativeCrs,
    'cell_m=' + FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.cellMeters,
    'ground_support_radius_m=' + FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.groundSupportRadiusMeters,
    'first_return_support_radius_m=' + FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.firstReturnSupportRadiusMeters,
    'first_return=LAS_ReturnNumber_1',
    'ground=LAS_Class_2',
    'surface=cell_mean_then_local_idw_v1',
    'height=first_return_minus_ground',
    'support_flags=available|first_filled|negative_clamped|ground_direct_v1',
    'qa=negative_raw_height_magnitude_and_output_grid_support_v1',
  ].join('|')
}

function decodedBase64Length(value: unknown) {
  if (typeof value !== 'string' || !value) return -1
  try {
    return atob(value).length
  } catch {
    return -1
  }
}

export function validateStudyVegetationHeightArtifact(value: any) {
  const grid = value?.grid
  const width = Number(grid?.width)
  const height = Number(grid?.height)
  const expectedCells = width * height
  if (
    value?.schema !== FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.outputSchemaVersion ||
    value?.method !== FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.algorithmVersion ||
    value?.status !== 'available' ||
    value?.source_collection !== FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.sourceCollection ||
    value?.native_crs !== FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.nativeCrs ||
    Number(value?.cell_meters) !== FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.cellMeters ||
    value?.height_unit !== 'm' ||
    value?.encoding !== FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.heightEncoding ||
    !/^[0-9a-f]{64}$/.test(String(value?.domain?.identity_sha256 || '')) ||
    Number(value?.domain?.radius_m) !== FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.domainMeters ||
    !Array.isArray(value?.processing_item_ids) ||
    value.processing_item_ids.length === 0 ||
    !/^[0-9a-f]{64}$/.test(String(value?.source_plan_artifact_sha256 || '')) ||
    !Number.isInteger(width) || width <= 0 ||
    !Number.isInteger(height) || height <= 0 ||
    !Array.isArray(grid?.bbox) || grid.bbox.length !== 4 ||
    Number(grid?.cell_meters) !== FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.cellMeters ||
    grid?.encoding !== FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.heightEncoding ||
    expectedCells <= 0
  ) return false

  if (
    decodedBase64Length(grid?.height_cm_u16_base64) !== expectedCells * 2 ||
    decodedBase64Length(grid?.support_u8_base64) !== expectedCells
  ) return false

  return Boolean(
    value?.summary?.domain &&
    value?.summary?.property &&
    value?.summary?.local_ring &&
    Number(value?.processing_summary?.first_return_point_count) > 0 &&
    Number(value?.processing_summary?.ground_point_count) > 0 &&
    value?.processing_source_fingerprint
  )
}

export function studyVegetationHeightArtifactPath(
  propertyId: string,
  inputSignature: string,
  artifactSha256: string,
) {
  return [
    'properties',
    propertyId,
    FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.productKind,
    inputSignature,
    artifactSha256 + '.json',
  ].join('/')
}
