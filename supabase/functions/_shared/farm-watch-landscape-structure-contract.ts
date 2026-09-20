import { FARM_WATCH_LIDAR_PHYSICAL_PRODUCT } from './farm-watch-lidar-physical-contract.ts'
import { FARM_WATCH_LEAF_OFF_PRODUCT } from './farm-watch-leaf-off-contract.ts'

export const FARM_WATCH_LANDSCAPE_STRUCTURE_PRODUCT = Object.freeze({
  key: 'landscape-structure-context',
  productKind: 'landscape-structure-context',
  algorithmVersion: 'local500m-phase3-lidar-2024-leafoff-structure-v1',
  outputSchemaVersion: 'landscape-structure-context-v1',
  evidenceClass: 'deterministic_derived',
  artifactBucket: 'farm-watch-derived',
  artifactFormat: 'farm-watch-landscape-structure-context-json-v1',
  artifactMimeType: 'application/json',
  domainMeters: 500,
  lidarStructureCellMeters: FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.structureCellMeters,
  lidarGroundCellMeters: FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.groundCellMeters,
  lidarGroundSupportRadiusMeters: FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.groundSupportRadiusMeters,
  lidarThresholdsFt: FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.thresholdsFt,
  leafSourceId: 'ky-phase3',
  leafTargetNeighborhoodMeters: FARM_WATCH_LEAF_OFF_PRODUCT.targetNeighborhoodMeters,
  leafImageryTargetPixelMeters: FARM_WATCH_LEAF_OFF_PRODUCT.imageryTargetPixelMeters,
  leafTerrainTargetPixelMeters: FARM_WATCH_LEAF_OFF_PRODUCT.terrainTargetPixelMeters,
  leafMaxImageryDimension: FARM_WATCH_LEAF_OFF_PRODUCT.maxImageryDimension,
  leafMaxTerrainDimension: FARM_WATCH_LEAF_OFF_PRODUCT.maxTerrainDimension,
  leafAnalysisPadMeters: FARM_WATCH_LEAF_OFF_PRODUCT.analysisPadMeters,
  refreshDays: 30,
})

export const FARM_WATCH_LANDSCAPE_STRUCTURE_LIMITATIONS = Object.freeze([
  'The analysis domain is the exact barrier-aware local_500m landscape domain, including the selected property. It is not a simple circular buffer.',
  'LiDAR height bands remain neutral height-above-ground strata. They do not identify species, understory, habitat quality, bedding, security cover, or animal use.',
  'The 2024 leaf-off layer remains experimental horizontal woody-pattern context. It does not measure stem density, regeneration, species, habitat quality, or animal use.',
  'The landscape leaf-off score is normalized within the local_500m domain. It is a separate product and must not replace or silently overwrite the canonical parcel-normalized leaf-off artifact.',
  'Cross-boundary continuity statistics describe structural similarity or contrast across adjacent cells. They are not deer-movement observations or route predictions.',
  'Operator field observations may later calibrate interpretation, but they remain separate evidence and do not convert derived terrain or vegetation products into authoritative source data.',
])

export function landscapeStructureSourceSignature(args: {
  landscapeDomainIdentitySha256: string
  landscapeDomainAlgorithmVersion: string
  lidarSourceContractSignature: string
}) {
  const domainIdentity = String(args.landscapeDomainIdentitySha256 || '').trim().toLowerCase()
  if (!/^[0-9a-f]{64}$/.test(domainIdentity)) {
    throw new Error('landscape structure domain identity is invalid')
  }
  return [
    'product=landscape-structure-context',
    'scope=barrier-aware-local-500m',
    'landscape_domain_identity_sha256=' + domainIdentity,
    'landscape_domain_algorithm=' + String(args.landscapeDomainAlgorithmVersion || ''),
    'lidar_source_contract=' + String(args.lidarSourceContractSignature || ''),
    'lidar_method=' + FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.algorithmVersion,
    'lidar_ground_cell_m=' + FARM_WATCH_LANDSCAPE_STRUCTURE_PRODUCT.lidarGroundCellMeters,
    'lidar_ground_support_radius_m=' + FARM_WATCH_LANDSCAPE_STRUCTURE_PRODUCT.lidarGroundSupportRadiusMeters,
    'lidar_structure_cell_m=' + FARM_WATCH_LANDSCAPE_STRUCTURE_PRODUCT.lidarStructureCellMeters,
    'lidar_thresholds_ft=' + FARM_WATCH_LANDSCAPE_STRUCTURE_PRODUCT.lidarThresholdsFt.join(','),
    'leaf_method=' + FARM_WATCH_LEAF_OFF_PRODUCT.algorithmVersion,
    'leaf_source_id=' + FARM_WATCH_LANDSCAPE_STRUCTURE_PRODUCT.leafSourceId,
    'leaf_neighborhood_m=' + FARM_WATCH_LANDSCAPE_STRUCTURE_PRODUCT.leafTargetNeighborhoodMeters,
    'leaf_imagery_target_pixel_m=' + FARM_WATCH_LANDSCAPE_STRUCTURE_PRODUCT.leafImageryTargetPixelMeters,
    'leaf_terrain_target_pixel_m=' + FARM_WATCH_LANDSCAPE_STRUCTURE_PRODUCT.leafTerrainTargetPixelMeters,
    'leaf_max_imagery_dimension=' + FARM_WATCH_LANDSCAPE_STRUCTURE_PRODUCT.leafMaxImageryDimension,
    'leaf_max_terrain_dimension=' + FARM_WATCH_LANDSCAPE_STRUCTURE_PRODUCT.leafMaxTerrainDimension,
    'leaf_analysis_pad_m=' + FARM_WATCH_LANDSCAPE_STRUCTURE_PRODUCT.leafAnalysisPadMeters,
    'boundary_adjacency=cross_boundary_8_neighbor_profile_and_texture_contrast_v1',
    'inside_outside_summary=property_vs_local_ring_v1',
  ].join('|')
}

export function validateLandscapeStructureArtifact(value: any) {
  if (
    value?.schema !== FARM_WATCH_LANDSCAPE_STRUCTURE_PRODUCT.outputSchemaVersion ||
    value?.method !== FARM_WATCH_LANDSCAPE_STRUCTURE_PRODUCT.algorithmVersion ||
    value?.status !== 'available'
  ) return false

  if (
    !/^[0-9a-f]{64}$/.test(String(value?.domain?.identity_sha256 || '')) ||
    Number(value?.domain?.radius_m) !== FARM_WATCH_LANDSCAPE_STRUCTURE_PRODUCT.domainMeters ||
    !value?.source_provenance?.lidar ||
    !value?.source_provenance?.leaf_off
  ) return false

  const grid = value?.combined_grid
  const width = Number(grid?.width)
  const height = Number(grid?.height)
  if (
    !Number.isInteger(width) || width <= 0 ||
    !Number.isInteger(height) || height <= 0 ||
    Number(grid?.cell_meters) !== FARM_WATCH_LANDSCAPE_STRUCTURE_PRODUCT.lidarStructureCellMeters ||
    grid?.encoding !== 'base64-u8-v1'
  ) return false

  const expectedLength = width * height
  for (const key of [
    'domain_valid_base64',
    'property_mask_base64',
    'lidar_valid_base64',
    'lidar_dominant_band_base64',
    'leaf_valid_base64',
    'leaf_score_base64',
  ]) {
    if (typeof grid?.[key] !== 'string' || grid[key].length === 0) return false
  }

  return Boolean(
    Number(value?.summary?.domain_cell_count) > 0 &&
    Number(value?.summary?.property_cell_count) > 0 &&
    Number(value?.summary?.local_ring_cell_count) > 0 &&
    value?.summary?.lidar?.property &&
    value?.summary?.lidar?.local_ring &&
    value?.summary?.leaf_off?.property &&
    value?.summary?.leaf_off?.local_ring &&
    value?.summary?.cross_boundary_adjacency &&
    expectedLength > 0
  )
}

export function landscapeStructureArtifactPath(
  propertyId: string,
  inputSignature: string,
  artifactSha256: string,
) {
  return [
    'properties',
    propertyId,
    FARM_WATCH_LANDSCAPE_STRUCTURE_PRODUCT.productKind,
    inputSignature,
    artifactSha256 + '.json',
  ].join('/')
}
