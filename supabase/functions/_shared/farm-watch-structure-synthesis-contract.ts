export const FARM_WATCH_STRUCTURE_SYNTHESIS_PRODUCT = Object.freeze({
  key: 'structure-complementarity',
  productKind: 'structure-complementarity',
  algorithmVersion: 'current-leaf-off-lidar-complementarity-v1',
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
