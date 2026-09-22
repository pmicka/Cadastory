export const FARM_WATCH_HLS_FIELD_PRODUCT = Object.freeze({
  key: 'hls-field-observations',
  algorithmVersion: 'farm-watch-hls-field-sampler-v1',
  outputSchemaVersion: 'hls-field-vegetation-observation-v1',
  evidenceClass: 'remote_sensing_observation',
  distributionProvider: 'Microsoft Planetary Computer',
  distributionEndpoint: 'https://planetarycomputer.microsoft.com/api/stac/v1/',
  sourceAuthority: 'NASA LP DAAC',
  lookbackDays: 45,
  freshnessDays: 10,
  minimumValidFraction: 0.30,
  collections: Object.freeze({
    'hls2-l30': Object.freeze({
      sourceProduct: 'HLSL30.v2.0',
      redAsset: 'B04',
      nirAsset: 'B05',
      blueAsset: 'B02',
      qaAsset: 'Fmask',
      doi: '10.5067/HLS/HLSL30.002',
    }),
    'hls2-s30': Object.freeze({
      sourceProduct: 'HLSS30.v2.0',
      redAsset: 'B04',
      nirAsset: 'B8A',
      blueAsset: 'B02',
      qaAsset: 'Fmask',
      doi: '10.5067/HLS/HLSS30.002',
    }),
  }),
  collectionStatuses: Object.freeze([
    'processing',
    'available',
    'partial',
    'no_valid_observation',
    'catalog_incomplete',
    'download_error',
    'processing_error',
  ] as const),
})

export type FarmWatchHlsCollectionStatus =
  typeof FARM_WATCH_HLS_FIELD_PRODUCT.collectionStatuses[number]

export const FARM_WATCH_HLS_FIELD_LIMITATIONS = Object.freeze([
  'The Microsoft Planetary Computer is a distribution host for NASA-generated HLS v2.0; NASA LP DAAC remains the source authority.',
  'Field summaries are 30 m remote-sensing observations clipped to USDA field geometry. They are not in-field measurements.',
  'Cloud, adjacent-cloud/shadow, cloud-shadow, snow, water, and high-aerosol QA conditions are screened before vegetation-index summaries are calculated.',
  'A quality-qualified HLS observation does not by itself establish standing crop, harvest, forage value, deer use, attraction, or habitat quality.',
  'Catalog, download, and processing failures are persisted as collection outcomes and must not be translated into a no-vegetation or no-harvest state.',
  'Batch 4B stores NDVI, EVI, and NIR trajectories only. Harvest classification remains disabled until a separately validated evidence-backed method is implemented.',
])

function isSha(value: unknown) {
  return /^[0-9a-f]{64}$/.test(String(value || ''))
}

function isFiniteOrNull(value: unknown) {
  return value == null || Number.isFinite(Number(value))
}

export function validateFarmWatchHlsObservationRow(value: any) {
  const allowedProducts = Object.values(FARM_WATCH_HLS_FIELD_PRODUCT.collections)
    .map((collection) => collection.sourceProduct)
  const valid = Number(value?.valid_pixel_count)
  const total = Number(value?.total_pixel_count)
  const fraction = Number(value?.valid_fraction)
  if (
    !/^[0-9a-f-]{36}$/i.test(String(value?.field_id || '')) ||
    !allowedProducts.includes(String(value?.source_product || '') as any) ||
    typeof value?.source_granule_id !== 'string' ||
    value.source_granule_id.length < 8 ||
    !Number.isFinite(Date.parse(String(value?.observed_at || ''))) ||
    !Number.isInteger(valid) || valid < 0 ||
    !Number.isInteger(total) || total <= 0 || valid > total ||
    !Number.isFinite(fraction) || fraction < 0 || fraction > 1 ||
    Math.abs(fraction - valid / total) > 0.02 ||
    !isFiniteOrNull(value?.ndvi_mean) ||
    !isFiniteOrNull(value?.ndvi_median) ||
    !isFiniteOrNull(value?.evi_mean) ||
    !isFiniteOrNull(value?.evi_median) ||
    !isFiniteOrNull(value?.nir_mean) ||
    !isFiniteOrNull(value?.cloud_fraction) ||
    (value?.cloud_fraction != null &&
      (Number(value.cloud_fraction) < 0 || Number(value.cloud_fraction) > 1)) ||
    !isSha(value?.source_sha256) ||
    typeof value?.qa_context !== 'object' ||
    value?.qa_context == null
  ) return false
  return true
}

export function validateFarmWatchHlsCompletion(value: any) {
  const status = String(value?.status || '') as FarmWatchHlsCollectionStatus
  if (
    status === 'processing' ||
    !FARM_WATCH_HLS_FIELD_PRODUCT.collectionStatuses.includes(status)
  ) return false
  for (const key of [
    'target_fields',
    'discovered_items',
    'complete_asset_items',
    'sampled_items',
    'stored_observations',
    'current_quality_fields',
  ]) {
    const number = Number(value?.[key])
    if (!Number.isInteger(number) || number < 0) return false
  }
  if (!Array.isArray(value?.observations)) return false
  if (value.observations.some((row: unknown) => !validateFarmWatchHlsObservationRow(row))) {
    return false
  }
  return Boolean(
    value?.scoring_performed === false &&
    value?.behavioral_inference_performed === false
  )
}
