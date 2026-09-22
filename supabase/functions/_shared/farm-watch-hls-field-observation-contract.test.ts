import {
  validateFarmWatchHlsCompletion,
  validateFarmWatchHlsObservationRow,
} from './farm-watch-hls-field-observation-contract.ts'

function assert(condition: unknown, message = 'assertion failed'): asserts condition {
  if (!condition) throw new Error(message)
}

function observation() {
  return {
    field_id: '5407d61e-cd63-4889-aae3-8ebcd30446e3',
    source_product: 'HLSS30.v2.0',
    source_granule_id: 'HLS.S30.T16SEH.2026263T160000.v2.0',
    observed_at: '2026-09-20T16:00:00Z',
    ndvi_mean: 0.63,
    ndvi_median: 0.65,
    evi_mean: 0.38,
    evi_median: 0.39,
    nir_mean: 0.31,
    valid_pixel_count: 8,
    total_pixel_count: 10,
    valid_fraction: 0.8,
    cloud_fraction: 0.1,
    qa_context: {
      distribution_provider: 'Microsoft Planetary Computer',
      stac_collection: 'hls2-s30',
    },
    source_url: 'https://planetarycomputer.microsoft.com/api/stac/v1/collections/hls2-s30/items/example',
    source_sha256: 'a'.repeat(64),
  }
}

Deno.test('HLS observation accepts quality-qualified neutral row', () => {
  assert(validateFarmWatchHlsObservationRow(observation()))
})

Deno.test('HLS observation rejects invalid pixel support', () => {
  const value = observation()
  value.valid_pixel_count = 11
  assert(!validateFarmWatchHlsObservationRow(value))
})

Deno.test('HLS completion accepts available neutral result', () => {
  assert(validateFarmWatchHlsCompletion({
    status: 'available',
    target_fields: 1,
    discovered_items: 3,
    complete_asset_items: 3,
    sampled_items: 3,
    stored_observations: 3,
    current_quality_fields: 1,
    observations: [observation()],
    scoring_performed: false,
    behavioral_inference_performed: false,
  }))
})

Deno.test('HLS completion rejects behavioral inference', () => {
  assert(!validateFarmWatchHlsCompletion({
    status: 'partial',
    target_fields: 1,
    discovered_items: 3,
    complete_asset_items: 2,
    sampled_items: 2,
    stored_observations: 2,
    current_quality_fields: 1,
    observations: [observation()],
    scoring_performed: false,
    behavioral_inference_performed: true,
  }))
})
