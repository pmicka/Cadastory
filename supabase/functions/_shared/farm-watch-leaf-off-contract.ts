export const FARM_WATCH_LEAF_OFF_PRODUCT = Object.freeze({
  key: 'leaf-off-structure',
  productKind: 'leaf-off-woody-structure',
  algorithmVersion: 'leaf_off_structure_v1_2_7m',
  outputSchemaVersion: 'leaf-off-woody-structure-v1',
  evidenceClass: 'experimental_derived',
  artifactBucket: 'farm-watch-derived',
  artifactFormat: 'farm-watch-leaf-off-woody-structure-json-v1',
  artifactMimeType: 'application/json',
  targetNeighborhoodMeters: 7,
  imageryTargetPixelMeters: 1,
  terrainTargetPixelMeters: 2,
  maxImageryDimension: 1800,
  maxTerrainDimension: 1000,
  analysisPadMeters: 10,
  refreshDays: 90,
  demUrl:
    'https://kyraster.ky.gov/arcgis/rest/services/ElevationServices/Ky_DEM_KYAPED_2FT_Phase3_WGS84WM/ImageServer',
  sources: [
    {
      id: 'ky-phase3',
      year: 2024,
      label: 'KyFromAbove Phase 3 · 2024 Season 1',
      imageryUrl:
        'https://kyraster.ky.gov/arcgis/rest/services/ImageServices/Ky_KYAPED_Phase3_3IN_WGS84WM/ImageServer',
      infraredUrl:
        'https://kyraster.ky.gov/arcgis/rest/services/ImageServices/Ky_KYAPED_Phase3_3IN_IR/ImageServer',
      sourceTile: 'N071E278_2024_Season1',
      acquisitionDate: '2024-02-14',
      acquisitionTimestamp: '2024-02-14T11:00:27-05:00',
      acquisitionNote:
        'Nearest documented Phase 3 color frame was acquired 2024-02-14 at approximately 11:00 EST.',
      solarMode: 'documented',
      frameTimeBasis: 'documented local time',
    },
    {
      id: 'ky-franklin-2019',
      year: 2019,
      label: 'KyFromAbove Phase 2 · Franklin 2019',
      imageryUrl:
        'https://kyraster.ky.gov/arcgis/rest/services/ImageServices/Ky_KYAPED_Phase2_6IN_WGS84WM/ImageServer',
      infraredUrl:
        'https://kyraster.ky.gov/arcgis/rest/services/ImageServices/Ky_KYAPED_Phase2_6IN_IR/ImageServer',
      sourceTile: 'N071E278_2019',
      acquisitionDate: '2019-03-27',
      acquisitionTimestamp: null,
      acquisitionNote:
        'Overlapping Phase 2 frames 09_861–09_863 are dated 2019-03-27 with DB_Time 19:27:49–19:28:05; the frame service does not document the DB_Time timezone, so solar geometry is intentionally not inferred.',
      solarMode: 'unresolved_time_basis',
      frameTimeBasis: 'DB_Time timezone undocumented',
    },
  ],
})

export const FARM_WATCH_LEAF_OFF_SOURCE_SIGNATURE = [
  'product=leaf-off-woody-structure',
  'phase3_rgb=Ky_KYAPED_Phase3_3IN_WGS84WM',
  'phase3_ir=Ky_KYAPED_Phase3_3IN_IR',
  'phase3_tile=N071E278_2024_Season1',
  'phase3_acquisition=2024-02-14T11:00:27-05:00',
  'phase2_rgb=Ky_KYAPED_Phase2_6IN_WGS84WM',
  'phase2_ir=Ky_KYAPED_Phase2_6IN_IR',
  'phase2_tile=N071E278_2019',
  'phase2_acquisition=2019-03-27',
  'dem=Ky_DEM_KYAPED_2FT_Phase3_WGS84WM',
  'export_image_srid=3857',
  'imagery_target_pixel_m=1',
  'terrain_target_pixel_m=2',
  'max_imagery_dimension=1800',
  'max_terrain_dimension=1000',
  'analysis_pad_m=10',
  'neighborhood_m=7',
  'texture_weights=std:0.45,gradient:0.55',
  'terrain_surface_factor=1/sqrt(1+(slope_percent/100)^2)',
  'provider_revision=unresolved',
].join('|')

export const FARM_WATCH_LEAF_OFF_LIMITATIONS = Object.freeze([
  'This is experimental horizontal woody-pattern context derived from leaf-off aerial texture. It complements LiDAR vertical structure but does not measure understory density, stem density, regeneration, species, habitat quality, management condition, or animal use.',
  '2019 and 2024 observations are independently normalized. Their transfer diagnostic describes recurring spatial rank structure; disagreement is not classified as vegetation change.',
  'Phase 3 observation support uses documented solar geometry and false-color support. The 2019 source frame time basis is unresolved, so solar hillshade is intentionally not inferred for that acquisition.',
  'The upstream imagery and DEM services do not expose immutable revision identifiers in this contract. Source freshness is therefore bounded by the materialization rebuild interval and per-raster content hashes.',
  'Field verification is required before ecological interpretation beyond the supported horizontal spatial-organization use.',
])

export function validateLeafOffArtifact(value: any) {
  if (
    value?.schema !== FARM_WATCH_LEAF_OFF_PRODUCT.outputSchemaVersion ||
    value?.method !== FARM_WATCH_LEAF_OFF_PRODUCT.algorithmVersion ||
    !Array.isArray(value?.products) ||
    value.products.length !== FARM_WATCH_LEAF_OFF_PRODUCT.sources.length
  ) return false

  const expectedIds = new Set(FARM_WATCH_LEAF_OFF_PRODUCT.sources.map((source) => source.id))
  for (const product of value.products) {
    if (!expectedIds.has(String(product?.sourceId || ''))) return false
    const grid = product?.grid
    const width = Number(grid?.width)
    const height = Number(grid?.height)
    if (
      !Number.isInteger(width) || width <= 0 ||
      !Number.isInteger(height) || height <= 0 ||
      grid?.encoding !== 'base64-u8-v1'
    ) return false
    for (const key of [
      'score_base64',
      'confidence_base64',
      'spectral_support_base64',
      'valid_base64',
      'slope_percent_base64',
      'illumination_base64',
    ]) {
      if (typeof grid?.[key] !== 'string' || grid[key].length === 0) return false
    }
    if (!product?.scoreDistribution || !product?.normalization) return false
  }

  return Boolean(
    value?.transfer_diagnostic &&
    typeof value.transfer_diagnostic.status === 'string' &&
    value?.processing_source_fingerprint &&
    Array.isArray(value.processing_source_fingerprint.sources)
  )
}

export function leafOffArtifactPath(
  propertyId: string,
  inputSignature: string,
  artifactSha256: string,
) {
  return [
    'properties',
    propertyId,
    FARM_WATCH_LEAF_OFF_PRODUCT.productKind,
    inputSignature,
    artifactSha256 + '.json',
  ].join('/')
}
