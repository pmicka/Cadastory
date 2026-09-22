import {
  FARM_WATCH_CURRENT_CROP_IDENTITY_PRODUCT,
  validateFarmWatchCurrentCropIdentityEvidence,
} from './farm-watch-current-crop-identity-contract.ts'

function assert(condition: unknown, message = 'assertion failed'): asserts condition {
  if (!condition) throw new Error(message)
}

function candidate(): any {
  return {
    schema_version: 'current-crop-identity-v1',
    field_id: '5407d61e-cd63-4889-aae3-8ebcd30446e3',
    as_of_date: '2026-09-22',
    status: 'candidate_only',
    candidate_crop: { cdl_code: 5, name: 'Soybeans' },
    accepted_crop: null,
    confidence: {
      state: 'uncalibrated',
      calibrated_probability: null,
      field_vote_fraction: 0.84,
      top2_vote_margin: 0.63,
    },
    abstention_reasons: ['field_acceptance_rule_not_validated'],
    provenance: {
      method: 'zhang-hls-transformer-2025',
      model_record_doi: '10.5281/zenodo.14715402',
    },
    scoring_performed: false,
    behavioral_inference_performed: false,
    harvest_inference_performed: false,
  }
}

Deno.test('current crop identity candidate stays explicitly uncalibrated', () => {
  assert(validateFarmWatchCurrentCropIdentityEvidence(candidate()))
})

Deno.test('candidate cannot masquerade as accepted crop identity', () => {
  const value = candidate()
  value.accepted_crop = { cdl_code: 5, name: 'Soybeans' }
  assert(!validateFarmWatchCurrentCropIdentityEvidence(value))
})

Deno.test('calibrated probability is forbidden until separately validated', () => {
  const value = candidate()
  value.confidence.calibrated_probability = 0.91
  assert(!validateFarmWatchCurrentCropIdentityEvidence(value))
})

Deno.test('accepted identity requires no abstention reason', () => {
  const value = candidate()
  value.status = 'accepted'
  value.accepted_crop = { cdl_code: 5, name: 'Soybeans' }
  assert(!validateFarmWatchCurrentCropIdentityEvidence(value))
})

Deno.test('published application contract uses reflective Landsat bands only', () => {
  assert(FARM_WATCH_CURRENT_CROP_IDENTITY_PRODUCT.landsat.thermalBandsUsedByModel === false)
  assert(FARM_WATCH_CURRENT_CROP_IDENTITY_PRODUCT.landsat.modelBands.length === 7)
  assert(FARM_WATCH_CURRENT_CROP_IDENTITY_PRODUCT.sentinel2.modelBands.length === 11)
  assert(FARM_WATCH_CURRENT_CROP_IDENTITY_PRODUCT.years === 2)
})
