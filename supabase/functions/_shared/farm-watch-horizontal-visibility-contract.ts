export const FARM_WATCH_HORIZONTAL_VISIBILITY_PRODUCT = Object.freeze({
  key: 'horizontal-visibility-context',
  productKind: 'horizontal-visibility-context',
  algorithmVersion: 'barrier-aware-local500m-horizontal-visibility-v1',
  outputSchemaVersion: 'horizontal-visibility-context-v1',
  evidenceClass: 'deterministic_derived',
  artifactBucket: 'farm-watch-derived',
  artifactFormat: 'farm-watch-horizontal-visibility-context-json-gzip-v1',
  artifactMimeType: 'application/json',
  domainMeters: 500,
  outputCellMeters: 5,
  terrainSourceCellMeters: 10,
  observerHeightScenariosM: Object.freeze([1.5, 3, 6]),
  targetHeightSemantics: 'target_ground_plus_equal_height_above_ground',
  azimuthCount: 16,
  azimuthOrigin: 'north_clockwise_degrees',
  rayStepMeters: 5,
  distanceBandsMeters: Object.freeze([10, 25, 50, 100]),
  maximumDistanceMeters: 100,
  terrainIntersectionEpsilonMeters: 0.02,
  structureSupportThreshold: 0.05,
  refreshDays: 30,
})

export const FARM_WATCH_HORIZONTAL_VISIBILITY_LIMITATIONS = Object.freeze([
  'The analysis domain is the exact barrier-aware local_500m landscape domain. It is not a circular buffer or a broad 3 km visibility analysis.',
  'Terrain geometry is sampled from the current 10 m terrain-form elevation grid. Bilinear interpolation is used only when all four source cells are supported; missing support produces explicit unsupported directions.',
  'Structural obstruction uses the current 5 m LiDAR neutral height-band return-share representation. Return share is a physical support proxy, not an exact continuous vegetation volume or within-cell horizontal point geometry.',
  'Observer and target heights are generic physical scenarios. They are not deer eye heights, body heights, concealment classes, bedding classes, security cover, or animal-use predictions.',
  'Visible distance and obstruction metrics describe geometric ray behavior under the named grid, sampling, and support rules. They do not predict deer visibility, deer use, movement, habitat quality, hunting quality, or stand suitability.',
  'Directions that leave the exact domain or lack required terrain/structural support are counted as unsupported rather than treated as open.',
])

function requireSha(value: string, label: string) {
  const normalized = String(value || '').trim().toLowerCase()
  if (!/^[0-9a-f]{64}$/.test(normalized)) throw new Error(label + ' is invalid')
  return normalized
}

export function horizontalVisibilitySourceSignature(args: {
  landscapeDomainIdentitySha256: string
  landscapeStructureIdentitySha256: string
  landscapeStructureArtifactSha256: string
  terrainFormIdentitySha256: string
  terrainFormArtifactSha256: string
}) {
  const p = FARM_WATCH_HORIZONTAL_VISIBILITY_PRODUCT
  return [
    'product=' + p.productKind,
    'scope=barrier-aware-local-500m',
    'landscape_domain_identity_sha256=' +
      requireSha(args.landscapeDomainIdentitySha256, 'landscape domain identity'),
    'landscape_structure_identity_sha256=' +
      requireSha(args.landscapeStructureIdentitySha256, 'landscape structure identity'),
    'landscape_structure_artifact_sha256=' +
      requireSha(args.landscapeStructureArtifactSha256, 'landscape structure artifact'),
    'terrain_form_identity_sha256=' +
      requireSha(args.terrainFormIdentitySha256, 'terrain form identity'),
    'terrain_form_artifact_sha256=' +
      requireSha(args.terrainFormArtifactSha256, 'terrain form artifact'),
    'output_grid_m=' + p.outputCellMeters,
    'terrain_source_grid_m=' + p.terrainSourceCellMeters,
    'observer_heights_m=' + p.observerHeightScenariosM.join(','),
    'target_height_semantics=' + p.targetHeightSemantics,
    'azimuth_count=' + p.azimuthCount,
    'azimuth_origin=' + p.azimuthOrigin,
    'ray_step_m=' + p.rayStepMeters,
    'distance_bands_m=' + p.distanceBandsMeters.join(','),
    'maximum_distance_m=' + p.maximumDistanceMeters,
    'terrain_intersection_epsilon_m=' + p.terrainIntersectionEpsilonMeters,
    'structure_support_threshold=' + p.structureSupportThreshold,
    'structure_support_method=neutral-lidar-band-share-at-ray-height-v1',
    'terrain_resampling=complete-four-cell-bilinear-v1',
    'domain_edge_policy=unsupported-not-open-v1',
    'artifact_storage_encoding=gzip-v1',
    'artifact_storage_mime=application/json',
    'protected_completion_claim_normalization=v1',
  ].join('|')
}

export function horizontalVisibilityArtifactPath(
  propertyId: string,
  inputSignature: string,
  artifactSha256: string,
) {
  return [
    'properties',
    propertyId,
    FARM_WATCH_HORIZONTAL_VISIBILITY_PRODUCT.productKind,
    inputSignature,
    artifactSha256 + '.json',
  ].join('/')
}

function validPackedGrid(grid: any, expectedCellMeters: number, expectedCrs: string) {
  return Boolean(
    grid &&
    grid.native_crs === expectedCrs &&
    Number(grid.cell_meters) === expectedCellMeters &&
    Number.isInteger(Number(grid.width)) && Number(grid.width) > 0 &&
    Number.isInteger(Number(grid.height)) && Number(grid.height) > 0 &&
    typeof grid.domain_valid_base64 === 'string' && grid.domain_valid_base64.length > 0
  )
}

export function validateHorizontalVisibilityArtifact(value: any) {
  const p = FARM_WATCH_HORIZONTAL_VISIBILITY_PRODUCT
  const grid = value?.grid
  const count = Number(grid?.width) * Number(grid?.height)
  const heightCount = p.observerHeightScenariosM.length
  const bandCount = p.distanceBandsMeters.length
  if (
    value?.schema !== p.outputSchemaVersion ||
    value?.method !== p.algorithmVersion ||
    value?.status !== 'available' ||
    value?.evidence_class !== p.evidenceClass ||
    value?.scoring_performed !== false ||
    value?.behavioral_inference_performed !== false ||
    !Number.isInteger(count) || count <= 0 ||
    Number(value?.domain?.radius_m) !== p.domainMeters ||
    !/^[0-9a-f]{64}$/.test(String(value?.domain?.identity_sha256 || '')) ||
    !validPackedGrid(grid, p.outputCellMeters, 'EPSG:6473') ||
    Number(grid?.cell_size_native) <= 0 ||
    !Array.isArray(value?.observer_height_scenarios) ||
    value.observer_height_scenarios.length !== heightCount ||
    value.observer_height_scenarios.every((row: any, index: number) =>
      Number(row?.observer_height_m) === p.observerHeightScenariosM[index] &&
      Number(row?.target_height_m) === p.observerHeightScenariosM[index]
    ) === false
  ) return false

  for (const key of [
    'domain_valid_base64',
    'property_mask_base64',
    'terrain_valid_base64',
    'structure_valid_base64',
  ]) {
    if (typeof grid[key] !== 'string' || !grid[key].length) return false
  }

  const expectedU8 = count * heightCount * bandCount
  const expectedHeight = count * heightCount
  for (const key of [
    'terrain_obstruction_fraction_by_band_u8_base64',
    'structural_obstruction_fraction_by_band_u8_base64',
    'combined_obstruction_fraction_by_band_u8_base64',
    'angular_openness_by_band_u8_base64',
    'valid_direction_count_by_band_u8_base64',
    'unsupported_direction_count_by_band_u8_base64',
  ]) {
    if (typeof grid[key] !== 'string' || !grid[key].length) return false
  }
  for (const key of [
    'terrain_visible_distance_p50_tenths_m_u16_base64',
    'combined_visible_distance_p50_tenths_m_u16_base64',
  ]) {
    if (typeof grid[key] !== 'string' || !grid[key].length) return false
  }

  const expectedBase64Bytes = (value: string, bytes: number) => {
    try {
      const decoded = Uint8Array.from(atob(value), (char) => char.charCodeAt(0))
      return decoded.byteLength === bytes
    } catch {
      return false
    }
  }
  if (!expectedBase64Bytes(grid.domain_valid_base64, count)) return false
  if (!expectedBase64Bytes(grid.property_mask_base64, count)) return false
  if (!expectedBase64Bytes(grid.terrain_valid_base64, count * heightCount)) return false
  if (!expectedBase64Bytes(grid.structure_valid_base64, count * heightCount)) return false
  for (const key of [
    'terrain_obstruction_fraction_by_band_u8_base64',
    'structural_obstruction_fraction_by_band_u8_base64',
    'combined_obstruction_fraction_by_band_u8_base64',
    'angular_openness_by_band_u8_base64',
    'valid_direction_count_by_band_u8_base64',
    'unsupported_direction_count_by_band_u8_base64',
  ]) if (!expectedBase64Bytes(grid[key], expectedU8)) return false
  for (const key of [
    'terrain_visible_distance_p50_tenths_m_u16_base64',
    'combined_visible_distance_p50_tenths_m_u16_base64',
  ]) if (!expectedBase64Bytes(grid[key], expectedHeight * 2)) return false

  return Boolean(
    value?.dependencies?.landscape_structure_artifact_sha256 &&
    value?.dependencies?.terrain_form_artifact_sha256 &&
    typeof value?.source_provenance?.source_signature === 'string' &&
    value.source_provenance.source_signature.startsWith('product=horizontal-visibility-context|') &&
    value?.ray_contract?.azimuth_count === p.azimuthCount &&
    value?.ray_contract?.ray_step_m === p.rayStepMeters &&
    value?.ray_contract?.maximum_distance_m === p.maximumDistanceMeters &&
    Array.isArray(value?.ray_contract?.distance_bands_m) &&
    JSON.stringify(value.ray_contract.distance_bands_m) === JSON.stringify(p.distanceBandsMeters) &&
    Number(value?.summary?.domain_cell_count) > 0 &&
    Number(value?.summary?.height_scenario_count) === heightCount
  )
}
