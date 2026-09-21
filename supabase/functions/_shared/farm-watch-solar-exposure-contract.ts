export const FARM_WATCH_SOLAR_TERRAIN_PRODUCT = Object.freeze({
  key: 'solar-terrain-context',
  productKind: 'solar-terrain-context',
  algorithmVersion: 'terrain-horizon-canopy-context-v1',
  outputSchemaVersion: 'solar-terrain-context-v1',
  evidenceClass: 'deterministic_derived',
  artifactBucket: 'farm-watch-derived',
  artifactMimeType: 'application/json',
  localCellMeters: 10,
  landscapeCellMeters: 30,
  horizonSectorCount: 24,
  horizonSearchRadiusMeters: 3000,
  horizonRayStepMeters: 90,
  supportCellMeters: 30,
  canopyYear: 2025,
  canopyProductVersion: 'v2025-6',
  canopySourceUrl:
    'https://imagery.geoplatform.gov/iipp/rest/services/Vegetation/USFS_EDW_NLCD_TCC_CONUS/ImageServer',
  demSourceUrl:
    'https://kyraster.ky.gov/arcgis/rest/services/ElevationServices/Ky_DEM_KYAPED_2FT_Phase3_WGS84WM/ImageServer',
  refreshDays: 30,
})

export const FARM_WATCH_SOLAR_EXPOSURE_PRODUCT = Object.freeze({
  key: 'solar-exposure-context',
  productKind: 'solar-exposure-context',
  algorithmVersion: 'terrain-canopy-potential-solar-exposure-v1',
  outputSchemaVersion: 'solar-exposure-context-v1',
  evidenceClass: 'deterministic_derived',
  artifactBucket: 'farm-watch-derived',
  artifactMimeType: 'application/json',
  integrationStepMinutes: 15,
  daylightWindowRule: 'equal_daylight_thirds_v1',
  refreshDays: 3650,
})

export const FARM_WATCH_SOLAR_TERRAIN_LIMITATIONS = Object.freeze([
  'Terrain horizon is a deterministic line-of-sight estimate from the KyFromAbove DEM using the stated azimuth sectors, ray step, support resolution, and search radius. Features outside the search radius cannot contribute to the horizon.',
  'Horizon support is intentionally not clipped by Farm Watch hydrologic/barrier domains because off-domain terrain can still obstruct sunlight.',
  'Slope and aspect are deterministic finite-difference terrain derivatives and are resolution dependent.',
  'NLCD Tree Canopy Cover is modeled percent tree-canopy cover at the stated year and grain. It is not leaf area index, gap fraction, crown transmissivity, species, or measured optical attenuation.',
  'The local canopy grid reuses the current canonical spatial-edge-patch-context artifact. Landscape canopy is sampled from the same authoritative TCC product only where the canonical local artifact does not provide coverage.',
  'This product contains physical terrain/canopy context only and performs no wildlife, habitat, thermal-refuge, bedding, travel, or management inference.',
])

export const FARM_WATCH_SOLAR_EXPOSURE_LIMITATIONS = Object.freeze([
  'Solar exposure is dimensionless direct-beam terrain-incidence potential integrated through the named daylight windows. It is not measured or modeled irradiance in W/m².',
  'Terrain shadow is based on the finite horizon contract of the referenced solar-terrain artifact.',
  'The canopy-screened field uses a transparent linear proxy of 1 - TCC/100. Tree-canopy cover is not radiative transmittance, so the screened value must not be interpreted as measured under-canopy shortwave radiation.',
  'Diffuse sky radiation, multiple scattering, canopy architecture, seasonal leaf state, buildings, and sub-grid terrain are not represented in v1.',
  'Morning, midday, and evening are equal thirds of geometric daylight. They are neutral solar windows, not deer diel-state labels.',
  'This product is neutral physical context and performs no wildlife, habitat, thermal-refuge, bedding, travel, or management inference.',
])

function requireSha(value: string, label: string) {
  const normalized = String(value || '').trim().toLowerCase()
  if (!/^[0-9a-f]{64}$/.test(normalized)) throw new Error(label + ' is invalid')
  return normalized
}

export function requireSolarDate(value: string) {
  const raw = String(value || '').trim()
  if (!/^\d{4}-\d{2}-\d{2}$/.test(raw)) throw new Error('solar date is invalid')
  const parsed = new Date(raw + 'T00:00:00Z')
  if (!Number.isFinite(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== raw) {
    throw new Error('solar date is invalid')
  }
  return raw
}

export function solarTerrainSourceSignature(args: {
  terrainMaterializationIdentitySha256: string
  terrainArtifactSha256: string
  spatialPatternMaterializationIdentitySha256: string
  spatialPatternArtifactSha256: string
}) {
  const p = FARM_WATCH_SOLAR_TERRAIN_PRODUCT
  return [
    'product=' + p.productKind,
    'terrain_materialization_identity_sha256=' +
      requireSha(args.terrainMaterializationIdentitySha256, 'terrain materialization identity'),
    'terrain_artifact_sha256=' + requireSha(args.terrainArtifactSha256, 'terrain artifact'),
    'spatial_pattern_materialization_identity_sha256=' +
      requireSha(args.spatialPatternMaterializationIdentitySha256, 'spatial pattern identity'),
    'spatial_pattern_artifact_sha256=' +
      requireSha(args.spatialPatternArtifactSha256, 'spatial pattern artifact'),
    'dem_source=kyfromabove-phase3-dem',
    'dem_support_cell_m=' + p.supportCellMeters,
    'horizon_sector_count=' + p.horizonSectorCount,
    'horizon_search_radius_m=' + p.horizonSearchRadiusMeters,
    'horizon_ray_step_m=' + p.horizonRayStepMeters,
    'canopy_source=nlcd-tcc-' + p.canopyProductVersion,
    'canopy_year=' + p.canopyYear,
    'local_target_cell_m=' + p.localCellMeters,
    'landscape_target_cell_m=' + p.landscapeCellMeters,
  ].join('|')
}

export function solarExposureSourceSignature(args: {
  solarTerrainMaterializationIdentitySha256: string
  solarTerrainArtifactSha256: string
  solarDate: string
}) {
  const p = FARM_WATCH_SOLAR_EXPOSURE_PRODUCT
  return [
    'product=' + p.productKind,
    'solar_terrain_materialization_identity_sha256=' +
      requireSha(args.solarTerrainMaterializationIdentitySha256, 'solar terrain identity'),
    'solar_terrain_artifact_sha256=' +
      requireSha(args.solarTerrainArtifactSha256, 'solar terrain artifact'),
    'solar_date=' + requireSolarDate(args.solarDate),
    'integration_step_min=' + p.integrationStepMinutes,
    'window_rule=' + p.daylightWindowRule,
    'solar_geometry=noaa-style-geometric-v1',
    'canopy_screening=linear-open-fraction-from-tcc-v1',
  ].join('|')
}

function artifactPath(
  propertyId: string,
  productKind: string,
  inputSignature: string,
  artifactSha256: string,
) {
  return ['properties', propertyId, productKind, inputSignature, artifactSha256 + '.json'].join('/')
}

export function solarTerrainArtifactPath(
  propertyId: string,
  inputSignature: string,
  artifactSha256: string,
) {
  return artifactPath(
    propertyId,
    FARM_WATCH_SOLAR_TERRAIN_PRODUCT.productKind,
    inputSignature,
    artifactSha256,
  )
}

export function solarExposureArtifactPath(
  propertyId: string,
  inputSignature: string,
  artifactSha256: string,
) {
  return artifactPath(
    propertyId,
    FARM_WATCH_SOLAR_EXPOSURE_PRODUCT.productKind,
    inputSignature,
    artifactSha256,
  )
}

function gridCommon(grid: any, cellMeters: number) {
  return Boolean(
    grid &&
    grid.native_crs === 'EPSG:32616' &&
    Number(grid.cell_meters) === cellMeters &&
    Number.isInteger(Number(grid.width)) &&
    Number(grid.width) > 0 &&
    Number.isInteger(Number(grid.height)) &&
    Number(grid.height) > 0 &&
    typeof grid.domain_valid_base64 === 'string' &&
    grid.domain_valid_base64.length > 0
  )
}

export function validateSolarTerrainArtifact(value: any) {
  const p = FARM_WATCH_SOLAR_TERRAIN_PRODUCT
  const local = value?.local_grid
  const landscape = value?.landscape_grid
  const fieldsValid = (grid: any, cellMeters: number) => Boolean(
    gridCommon(grid, cellMeters) &&
    typeof grid.elevation_tenths_ft_u16_base64 === 'string' &&
    Number.isFinite(Number(grid.elevation_offset_ft)) &&
    typeof grid.slope_tenths_degree_u16_base64 === 'string' &&
    typeof grid.aspect_tenths_degree_u16_base64 === 'string' &&
    typeof grid.orientation_valid_u8_base64 === 'string' &&
    typeof grid.canopy_valid_u8_base64 === 'string' &&
    typeof grid.canopy_percent_u8_base64 === 'string' &&
    Array.isArray(grid.horizon_half_degree_u8_base64) &&
    grid.horizon_half_degree_u8_base64.length === p.horizonSectorCount &&
    grid.horizon_half_degree_u8_base64.every((x: unknown) => typeof x === 'string') &&
    typeof grid.horizon_mean_half_degree_u8_base64 === 'string' &&
    typeof grid.horizon_max_half_degree_u8_base64 === 'string'
  )
  return Boolean(
    value?.schema === p.outputSchemaVersion &&
    value?.method === p.algorithmVersion &&
    value?.status === 'available' &&
    value?.evidence_class === p.evidenceClass &&
    /^[0-9a-f]{64}$/.test(String(value?.dependencies?.terrain_artifact_sha256 || '')) &&
    /^[0-9a-f]{64}$/.test(String(value?.dependencies?.spatial_pattern_artifact_sha256 || '')) &&
    fieldsValid(local, p.localCellMeters) &&
    fieldsValid(landscape, p.landscapeCellMeters) &&
    Number(value?.horizon_contract?.sector_count) === p.horizonSectorCount &&
    Number(value?.horizon_contract?.search_radius_m) === p.horizonSearchRadiusMeters &&
    value?.scoring_performed === false &&
    value?.behavioral_inference_performed === false
  )
}

export function validateSolarExposureArtifact(value: any) {
  const p = FARM_WATCH_SOLAR_EXPOSURE_PRODUCT
  const gridValid = (grid: any, expectedCellMeters: number) => Boolean(
    gridCommon(grid, expectedCellMeters) &&
    typeof grid.orientation_valid_u8_base64 === 'string' &&
    typeof grid.canopy_valid_u8_base64 === 'string' &&
    typeof grid.terrain_shadow_fraction_u8_base64 === 'string' &&
    ['full_day','morning','midday','evening'].every((window) =>
      typeof grid?.windows?.[window]?.terrain_potential_milli_sun_hours_u16_base64 === 'string' &&
      typeof grid?.windows?.[window]?.canopy_screened_potential_milli_sun_hours_u16_base64 === 'string'
    )
  )
  return Boolean(
    value?.schema === p.outputSchemaVersion &&
    value?.method === p.algorithmVersion &&
    value?.status === 'available' &&
    value?.evidence_class === p.evidenceClass &&
    /^\d{4}-\d{2}-\d{2}$/.test(String(value?.solar_date || '')) &&
    /^[0-9a-f]{64}$/.test(String(value?.dependencies?.solar_terrain_artifact_sha256 || '')) &&
    Number(value?.solar_day?.integration_step_minutes) === p.integrationStepMinutes &&
    value?.solar_day?.window_rule === p.daylightWindowRule &&
    gridValid(value?.local_grid, FARM_WATCH_SOLAR_TERRAIN_PRODUCT.localCellMeters) &&
    gridValid(value?.landscape_grid, FARM_WATCH_SOLAR_TERRAIN_PRODUCT.landscapeCellMeters) &&
    value?.scoring_performed === false &&
    value?.behavioral_inference_performed === false
  )
}
