export const FARM_WATCH_TERRAIN_PRODUCT = Object.freeze({
  key: 'terrain',
  productKind: 'terrain-analysis',
  algorithmVersion: 'phase3-dem-61x61-conditioned-flow-v2',
  outputSchemaVersion: 'terrain-analysis-v2',
  evidenceClass: 'deterministic_derived',
  artifactBucket: 'farm-watch-derived',
  artifactFormat: 'farm-watch-terrain-json-v2',
  artifactMimeType: 'application/json',
  sourceUrl: 'https://kyraster.ky.gov/arcgis/rest/services/ElevationServices/Ky_DEM_KYAPED_2FT_Phase3_WGS84WM/ImageServer',
  sourceSlug: 'kyfromabove-phase3-dem',
  sourceRevisionStatus: 'provider_service_revision_unresolved',
  gridSize: 61,
  sampleBatchSize: 900,
  boundsPaddingFraction: 0.08,
  flowMinContributingAreaAcres: 0.5,
  flowMaxTraces: 12,
  refreshDays: 30,
})

export const FARM_WATCH_TERRAIN_SOURCE_SIGNATURE = [
  'source=kyfromabove-phase3-dem',
  'service=Ky_DEM_KYAPED_2FT_Phase3_WGS84WM',
  'operation=getSamples',
  'input_srid=4326',
  'grid=61x61',
  'bounds_padding_fraction=0.08',
  'returnFirstValueOnly=true',
  'provider_revision=unresolved',
].join('|')

export const FARM_WATCH_TERRAIN_LIMITATIONS = Object.freeze([
  'The 61×61 grid is a coarse deterministic sampling product and is not the canonical parcel elevation distribution.',
  'D8 routing uses deterministic priority-flood depression conditioning on the sampled grid. Filled sampled cells are routing aids, not evidence that physical depressions, culverts, channels, or impoundments are absent.',
  'Derived flow traces use a minimum contributing-area threshold and metric D8 routing; they are terrain-drainage hypotheses, not mapped streams or field-verified channels.',
  'Outlet acreage is a sampled-cell proportion applied to stated property acreage, not a surveyed drainage-area measurement.',
  'The upstream ImageServer does not expose an immutable revision identifier in this contract, so source freshness is bounded by an explicit rebuild interval.',
])

export function terrainArtifactPath(propertyId: string, inputSignature: string, artifactSha256: string) {
  return [
    'properties',
    propertyId,
    FARM_WATCH_TERRAIN_PRODUCT.productKind,
    inputSignature,
    artifactSha256 + '.json',
  ].join('/')
}
