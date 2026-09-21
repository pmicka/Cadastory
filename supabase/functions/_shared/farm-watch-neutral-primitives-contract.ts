export const FARM_WATCH_TERRAIN_FORM_PRODUCT = Object.freeze({
  key: 'terrain-form-permeability',
  productKind: 'terrain-form-permeability',
  algorithmVersion: 'barrier-aware-phase3-dem-terrain-form-permeability-v1',
  outputSchemaVersion: 'terrain-form-permeability-v1',
  evidenceClass: 'deterministic_derived',
  artifactBucket: 'farm-watch-derived',
  artifactFormat: 'farm-watch-terrain-form-permeability-json-v1',
  artifactMimeType: 'application/json',
  sourceUrl: 'https://kyraster.ky.gov/arcgis/rest/services/ElevationServices/Ky_DEM_KYAPED_2FT_Phase3_WGS84WM/ImageServer',
  sourceSlug: 'kyfromabove-phase3-dem',
  localDomainMeters: 500,
  landscapeDomainMeters: 1500,
  localCellMeters: 10,
  landscapeCellMeters: 30,
  localTpiRadiusMeters: 30,
  broadTpiRadiusMeters: 90,
  refreshDays: 30,
  permeabilityScenario: Object.freeze({
    id: 'reference-slope-only-v1',
    base_cost: 1,
    slope_reference_percent: 30,
    slope_weight: 1,
    exponent: 1.5,
    slope_cap_percent: 100,
    hydrology_policy: 'configured-hard-barrier-domain-only',
  }),
})

export const FARM_WATCH_TERRAIN_FORM_LIMITATIONS = Object.freeze([
  'Terrain-form labels are deterministic geometric candidates derived from a fixed-resolution DEM grid. They are not field-surveyed landform boundaries.',
  'Ridge-like, draw-like, saddle-like, bench-like, and slope-break flags use explicit computational thresholds and must not be interpreted as animal travel, habitat, bedding, funnel, or stand-location evidence.',
  'The reference permeability surface is a slope-only modeled friction scenario with explicit parameters. It is not measured movement resistance and is not calibrated to deer or any other species.',
  'Configured hard barriers are represented only through the current barrier-aware analysis domain. Other mapped hydrology remains contextual unless a future scenario explicitly assigns it a cost.',
  'The existing 61x61 conditioned D8 terrain product remains a separate drainage hypothesis and is not relabeled or reused as a movement surface.',
])

function requireSha(value: string, label: string) {
  const normalized = String(value || '').trim().toLowerCase()
  if (!/^[0-9a-f]{64}$/.test(normalized)) throw new Error(label + ' is invalid')
  return normalized
}

export function terrainFormSourceSignature(args: {
  landscapeDomainIdentitySha256: string
  landscapePhysicalIdentitySha256: string
}) {
  const domainIdentity = requireSha(args.landscapeDomainIdentitySha256, 'landscape domain identity')
  const physicalIdentity = requireSha(args.landscapePhysicalIdentitySha256, 'landscape physical identity')
  const scenario = FARM_WATCH_TERRAIN_FORM_PRODUCT.permeabilityScenario
  return [
    'product=terrain-form-permeability',
    'source=kyfromabove-phase3-dem',
    'service=Ky_DEM_KYAPED_2FT_Phase3_WGS84WM',
    'operation=getSamples',
    'landscape_domain_identity_sha256=' + domainIdentity,
    'landscape_physical_identity_sha256=' + physicalIdentity,
    'local_domain_m=' + FARM_WATCH_TERRAIN_FORM_PRODUCT.localDomainMeters,
    'landscape_domain_m=' + FARM_WATCH_TERRAIN_FORM_PRODUCT.landscapeDomainMeters,
    'local_cell_m=' + FARM_WATCH_TERRAIN_FORM_PRODUCT.localCellMeters,
    'landscape_cell_m=' + FARM_WATCH_TERRAIN_FORM_PRODUCT.landscapeCellMeters,
    'tpi_local_radius_m=' + FARM_WATCH_TERRAIN_FORM_PRODUCT.localTpiRadiusMeters,
    'tpi_broad_radius_m=' + FARM_WATCH_TERRAIN_FORM_PRODUCT.broadTpiRadiusMeters,
    'forms=explicit_tpi_slope_curvature_thresholds_v1',
    'permeability_scenario=' + scenario.id,
    'permeability_base_cost=' + scenario.base_cost,
    'permeability_slope_reference_percent=' + scenario.slope_reference_percent,
    'permeability_slope_weight=' + scenario.slope_weight,
    'permeability_exponent=' + scenario.exponent,
    'permeability_slope_cap_percent=' + scenario.slope_cap_percent,
    'hydrology_policy=' + scenario.hydrology_policy,
  ].join('|')
}

export function terrainFormArtifactPath(
  propertyId: string,
  inputSignature: string,
  artifactSha256: string,
) {
  return [
    'properties',
    propertyId,
    FARM_WATCH_TERRAIN_FORM_PRODUCT.productKind,
    inputSignature,
    artifactSha256 + '.json',
  ].join('/')
}

export const FARM_WATCH_SPATIAL_PATTERN_PRODUCT = Object.freeze({
  key: 'spatial-edge-patch-context',
  productKind: 'spatial-edge-patch-context',
  algorithmVersion: 'local500m-canopy-field-structure-pattern-v1',
  outputSchemaVersion: 'spatial-edge-patch-context-v1',
  evidenceClass: 'deterministic_derived',
  artifactBucket: 'farm-watch-derived',
  artifactFormat: 'farm-watch-spatial-edge-patch-context-json-v1',
  artifactMimeType: 'application/json',
  canopySourceUrl: 'https://imagery.geoplatform.gov/iipp/rest/services/Vegetation/USFS_EDW_NLCD_TCC_CONUS/ImageServer',
  canopyYear: 2025,
  canopyProductVersion: 'v2025-6',
  canopyCellMeters: 30,
  canopyClassBreaks: Object.freeze([20, 60]),
  structureCellMeters: 5,
  patchNeighborRule: 8,
  refreshDays: 30,
})

export const FARM_WATCH_SPATIAL_PATTERN_LIMITATIONS = Object.freeze([
  'Canopy classes are fixed bins of modeled 2025 NLCD percent tree-canopy cover. Patch and edge metrics are scale- and grain-dependent physical summaries, not habitat or cover-quality classifications.',
  'Mapped field edges inherit the source boundary quality and CDL limitations of the current resource-edge product. Proximity to a mapped field edge is not forage availability, access permission, or animal-use evidence.',
  'Five-meter structural transitions are derived only from the existing canonical local landscape-structure artifact. No COPC or imagery source is downloaded or recomputed by this product.',
  'LiDAR dominant-band patches and leaf-off score-quartile patches describe measurement continuity at the product grain. They are not security cover, corridor, bedding, regeneration, or species classes.',
  'Transition intensity and patch adjacency are descriptive spatial discontinuity measures. They do not establish movement routes, funnels, or behavioral preference.',
])

export function spatialPatternSourceSignature(args: {
  landscapeDomainIdentitySha256: string
  landscapePhysicalIdentitySha256: string
  resourceEdgeIdentitySha256: string
  landscapeStructureIdentitySha256: string
  landscapeStructureArtifactSha256: string
}) {
  const domainIdentity = requireSha(args.landscapeDomainIdentitySha256, 'landscape domain identity')
  const physicalIdentity = requireSha(args.landscapePhysicalIdentitySha256, 'landscape physical identity')
  const resourceIdentity = requireSha(args.resourceEdgeIdentitySha256, 'resource edge identity')
  const structureIdentity = requireSha(args.landscapeStructureIdentitySha256, 'landscape structure identity')
  const structureArtifact = requireSha(args.landscapeStructureArtifactSha256, 'landscape structure artifact')
  return [
    'product=spatial-edge-patch-context',
    'scope=barrier-aware-local-500m',
    'landscape_domain_identity_sha256=' + domainIdentity,
    'landscape_physical_identity_sha256=' + physicalIdentity,
    'resource_edge_identity_sha256=' + resourceIdentity,
    'landscape_structure_identity_sha256=' + structureIdentity,
    'landscape_structure_artifact_sha256=' + structureArtifact,
    'canopy_source=nlcd-tcc-v2025-6',
    'canopy_year=' + FARM_WATCH_SPATIAL_PATTERN_PRODUCT.canopyYear,
    'canopy_cell_m=' + FARM_WATCH_SPATIAL_PATTERN_PRODUCT.canopyCellMeters,
    'canopy_class_breaks=' + FARM_WATCH_SPATIAL_PATTERN_PRODUCT.canopyClassBreaks.join(','),
    'patch_neighbor_rule=' + FARM_WATCH_SPATIAL_PATTERN_PRODUCT.patchNeighborRule,
    'structure_cell_m=' + FARM_WATCH_SPATIAL_PATTERN_PRODUCT.structureCellMeters,
    'structure_transition=8_neighbor_leaf_absdiff_and_lidar_profile_tv_v1',
    'field_edge=resource_edge_geometry_distance_v1',
  ].join('|')
}

export function spatialPatternArtifactPath(
  propertyId: string,
  inputSignature: string,
  artifactSha256: string,
) {
  return [
    'properties',
    propertyId,
    FARM_WATCH_SPATIAL_PATTERN_PRODUCT.productKind,
    inputSignature,
    artifactSha256 + '.json',
  ].join('/')
}

function validGridCommon(grid: any) {
  return Boolean(
    grid &&
    grid.native_crs === 'EPSG:32616' &&
    Number.isInteger(Number(grid.width)) &&
    Number(grid.width) > 0 &&
    Number.isInteger(Number(grid.height)) &&
    Number(grid.height) > 0 &&
    typeof grid.domain_valid_base64 === 'string' &&
    grid.domain_valid_base64.length > 0
  )
}

export function validateTerrainFormArtifact(value: any) {
  const local = value?.local_form_grid
  const landscape = value?.landscape_cost_grid
  return Boolean(
    value?.schema === FARM_WATCH_TERRAIN_FORM_PRODUCT.outputSchemaVersion &&
    value?.method === FARM_WATCH_TERRAIN_FORM_PRODUCT.algorithmVersion &&
    value?.status === 'available' &&
    value?.evidence_class === FARM_WATCH_TERRAIN_FORM_PRODUCT.evidenceClass &&
    /^[0-9a-f]{64}$/.test(String(value?.domain?.identity_sha256 || '')) &&
    validGridCommon(local) &&
    Number(local.cell_meters) === FARM_WATCH_TERRAIN_FORM_PRODUCT.localCellMeters &&
    typeof local.elevation_tenths_ft_u16_base64 === 'string' &&
    typeof local.slope_centipercent_u16_base64 === 'string' &&
    typeof local.tpi_local_tenths_ft_i16_base64 === 'string' &&
    typeof local.tpi_broad_tenths_ft_i16_base64 === 'string' &&
    typeof local.relief_broad_tenths_ft_u16_base64 === 'string' &&
    typeof local.form_code_u8_base64 === 'string' &&
    typeof local.form_flags_u8_base64 === 'string' &&
    typeof local.cost_x100_u16_base64 === 'string' &&
    typeof local.permeability_u8_base64 === 'string' &&
    validGridCommon(landscape) &&
    Number(landscape.cell_meters) === FARM_WATCH_TERRAIN_FORM_PRODUCT.landscapeCellMeters &&
    typeof landscape.slope_centipercent_u16_base64 === 'string' &&
    typeof landscape.cost_x100_u16_base64 === 'string' &&
    typeof landscape.permeability_u8_base64 === 'string' &&
    value?.permeability_scenario?.id ===
      FARM_WATCH_TERRAIN_FORM_PRODUCT.permeabilityScenario.id &&
    value?.behavioral_inference_performed === false &&
    value?.scoring_performed === false
  )
}

export function validateSpatialPatternArtifact(value: any) {
  const canopy = value?.canopy_pattern
  const structure = value?.structure_pattern
  return Boolean(
    value?.schema === FARM_WATCH_SPATIAL_PATTERN_PRODUCT.outputSchemaVersion &&
    value?.method === FARM_WATCH_SPATIAL_PATTERN_PRODUCT.algorithmVersion &&
    value?.status === 'available' &&
    value?.evidence_class === FARM_WATCH_SPATIAL_PATTERN_PRODUCT.evidenceClass &&
    /^[0-9a-f]{64}$/.test(String(value?.domain?.identity_sha256 || '')) &&
    /^[0-9a-f]{64}$/.test(String(value?.dependencies?.landscape_structure_artifact_sha256 || '')) &&
    validGridCommon(canopy?.grid) &&
    Number(canopy?.grid?.cell_meters) === FARM_WATCH_SPATIAL_PATTERN_PRODUCT.canopyCellMeters &&
    typeof canopy?.grid?.canopy_percent_u8_base64 === 'string' &&
    typeof canopy?.grid?.canopy_class_u8_base64 === 'string' &&
    typeof canopy?.grid?.patch_id_u32_base64 === 'string' &&
    typeof canopy?.grid?.mapped_field_mask_u8_base64 === 'string' &&
    typeof canopy?.grid?.mapped_field_edge_distance_m_u16_base64 === 'string' &&
    validGridCommon(structure?.grid) &&
    Number(structure?.grid?.cell_meters) === FARM_WATCH_SPATIAL_PATTERN_PRODUCT.structureCellMeters &&
    typeof structure?.grid?.leaf_transition_u8_base64 === 'string' &&
    typeof structure?.grid?.lidar_profile_transition_u8_base64 === 'string' &&
    typeof structure?.grid?.leaf_quartile_patch_id_u32_base64 === 'string' &&
    typeof structure?.grid?.lidar_band_patch_id_u32_base64 === 'string' &&
    value?.behavioral_inference_performed === false &&
    value?.scoring_performed === false
  )
}
