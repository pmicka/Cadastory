export const FARM_WATCH_STRUCTURE_SYNTHESIS_PRODUCT = Object.freeze({
  key: 'structure-complementarity',
  productKind: 'structure-complementarity',
  algorithmVersion: 'current-leaf-off-lidar-complementarity-v4',
  outputSchemaVersion: 'structure-complementarity-v1',
  evidenceClass: 'deterministic_derived',
  artifactBucket: 'farm-watch-derived',
  artifactFormat: 'farm-watch-structure-complementarity-json-v1',
  artifactMimeType: 'application/json',
  refreshDays: 30,
  leafSourceId: 'ky-phase3',
  minimumUpperShare: 0.10,
})

export const FARM_WATCH_STRUCTURE_SYNTHESIS_LIMITATIONS = Object.freeze([
  'This product combines current Phase 3 LiDAR height-above-ground strata with the independently derived 2024 leaf-off horizontal woody-pattern signal. It is a structural complementarity product, not a habitat or site-quality score.',
  'The 2024 aerial observation and 2025 LiDAR acquisition are not contemporaneous. Associations are descriptive and must not be interpreted as vegetation change or causation.',
  'Leaf-off texture is a relative within-acquisition spatial signal. It does not measure understory density, stem density, regeneration, species, habitat quality, management condition, bedding cover, mast availability, or animal use.',
  'LiDAR bands are neutral physical height strata. A dominant band does not identify vegetation type or ecological function.',
  'Canopy, terrain, and soil context may be displayed alongside this product, but they remain separate source-specific evidence and are not fused into an ecological score.',
  'Model adequacy is stress-tested on the same five held-out east-west spatial blocks using the linear ridge baseline, a fixed quadratic/interaction ridge expansion, and a deterministic shallow CART model. These are bounded model checks, not a proof that all possible LiDAR representations have been exhausted.',
  'Residual spatial organization is evaluated against deterministic block-permutation nulls at 15 m, 20 m, and 30 m block scales. The nulls preserve within-block selected-cell structure while disrupting between-block adjacency; they are not a universal spatial-randomness test.',
])

export function structureSynthesisSourceSignature(
  lidarPhysicalArtifactSha256: string,
  leafOffArtifactSha256: string,
) {
  const lidarSha = String(lidarPhysicalArtifactSha256 || '').trim().toLowerCase()
  const leafSha = String(leafOffArtifactSha256 || '').trim().toLowerCase()
  if (!/^[0-9a-f]{64}$/.test(lidarSha) || !/^[0-9a-f]{64}$/.test(leafSha)) {
    throw new Error('structure synthesis dependency SHA is invalid')
  }
  return [
    'product=structure-complementarity',
    'lidar_physical_artifact_sha256=' + lidarSha,
    'leaf_off_artifact_sha256=' + leafSha,
    'leaf_source_id=' + FARM_WATCH_STRUCTURE_SYNTHESIS_PRODUCT.leafSourceId,
    'aggregation=leaf_cells_to_lidar_5m_grid_by_center_v1',
    'minimum_leaf_support=50pct_expected_samples',
    'dominant_band_variance_partition=v1',
    'overstory_conditioned_lower_share=v1',
    'vertical_horizontal_matrix=dominant_band_x_leaf_quintile_v1',
    'full_vertical_profile_model=blocked_5fold_vertical_profile_ridge_v1',
    'out_of_fold_residual_spatial=best_tested_profile_residual_spatial_v2',
    'model_adequacy=blocked_5fold_ridge_quadratic_cart_v1',
    'spatial_null=block_permutation_selected_mask_v1:blocks=3,4,6:iterations=299',
  ].join('|')
}

export function validateStructureSynthesisArtifact(value: any) {
  if (
    value?.schema !== FARM_WATCH_STRUCTURE_SYNTHESIS_PRODUCT.outputSchemaVersion ||
    value?.method !== FARM_WATCH_STRUCTURE_SYNTHESIS_PRODUCT.algorithmVersion ||
    value?.status !== 'available' ||
    !value?.source_pairing ||
    !value?.summary ||
    !value?.combined_grid
  ) return false

  const grid = value.combined_grid
  const width = Number(grid.width)
  const height = Number(grid.height)
  if (
    !Number.isInteger(width) || width <= 0 ||
    !Number.isInteger(height) || height <= 0 ||
    !Array.isArray(grid.bbox) || grid.bbox.length !== 4 ||
    !Array.isArray(grid.thresholds_ft) ||
    grid.encoding !== 'base64-u8-v1'
  ) return false

  for (const key of [
    'valid_base64',
    'dominant_band_base64',
    'leaf_score_base64',
    'leaf_quintile_base64',
    'lower_4_32_share_base64',
    'upper_32plus_share_base64',
  ]) {
    if (typeof grid[key] !== 'string' || !grid[key].length) return false
  }

  return Boolean(
    Number(value.summary.shared_cell_count) > 0 &&
    Array.isArray(value.summary.dominant_band_texture_distribution) &&
    value.summary.dominant_band_variance_partition &&
    value.summary.overstory_conditioned &&
    value.summary.full_vertical_profile_model?.status === 'available' &&
    value.summary.model_adequacy_stress_test?.status === 'available' &&
    value.summary.out_of_fold_residual_spatial?.status === 'available' &&
    value.summary.out_of_fold_residual_spatial?.spatial_null?.status === 'available' &&
    Array.isArray(value.summary.vertical_horizontal_matrix)
  )
}

export function structureSynthesisArtifactPath(
  propertyId: string,
  inputSignature: string,
  artifactSha256: string,
) {
  return [
    'properties',
    propertyId,
    FARM_WATCH_STRUCTURE_SYNTHESIS_PRODUCT.productKind,
    inputSignature,
    artifactSha256 + '.json',
  ].join('/')
}
