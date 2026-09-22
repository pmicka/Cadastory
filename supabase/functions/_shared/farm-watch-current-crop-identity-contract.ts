export const FARM_WATCH_CURRENT_CROP_IDENTITY_PRODUCT = Object.freeze({
  key: 'current-crop-identity',
  schemaVersion: 'current-crop-identity-v1',
  methodStatus: 'candidate_not_production',
  method: 'zhang-hls-transformer-2025',
  paperDoi: '10.1016/j.rse.2025.114950',
  modelRecordDoi: '10.5281/zenodo.14715402',
  modelFile: 'v1_70.layer4.METHOD2.BATCH64.LR0.0002.EPOCH30.L20.1.i0.model.h5',
  modelMd5: '75b13ac5743d1d3449ffe5e2425e6ece',
  codeRepository: 'hankui/In-season-crop-type-mapper',
  codeCommit: '8c6f24465829542e822fde98655fedd57770ae3b',
  codeLicense: 'Apache-2.0',
  paperLicense: 'CC-BY-4.0',
  modelArtifactReuseStatus: 'blocked_pending_explicit_rights_verification',
  years: 2,
  fillValue: -9999,
  modelClasses: 50,
  cropClasses: 37,
  landsat: Object.freeze({
    product: 'HLSL30.v2.0',
    collection: 'hls2-l30',
    assets: Object.freeze(['B01','B02','B03','B04','B05','B06','B07','Fmask'] as const),
    modelBands: Object.freeze(['B01','B02','B03','B04','B05','B06','B07'] as const),
    thermalBandsUsedByModel: false,
  }),
  sentinel2: Object.freeze({
    product: 'HLSS30.v2.0',
    collection: 'hls2-s30',
    assets: Object.freeze(['B01','B02','B03','B04','B8A','B11','B12','B05','B06','B07','B08','Fmask'] as const),
    modelBands: Object.freeze(['B01','B02','B03','B04','B8A','B11','B12','B05','B06','B07','B08'] as const),
  }),
  qaExclusions: Object.freeze([
    'fill',
    'cloud',
    'adjacent_cloud_or_shadow',
    'cloud_shadow',
    'snow_or_ice',
  ] as const),
  qaNotExplicitlyExcludedByPublishedApplication: Object.freeze([
    'water',
    'high_aerosol',
  ] as const),
  normalization: Object.freeze({
    dayOfYear: 'year_offset + (doy - 1) / 366; range 0..2 across previous/current year',
    landsat: Object.freeze({
      B01: Object.freeze({ mean: 0.033744857, std: 0.034485396 }),
      B02: Object.freeze({ mean: 0.044795606, std: 0.038920645 }),
      B03: Object.freeze({ mean: 0.056982443, std: 0.055416185 }),
      B04: Object.freeze({ mean: 0.08267706, std: 0.064781055 }),
      B05: Object.freeze({ mean: 0.17750777, std: 0.1184702 }),
      B06: Object.freeze({ mean: 0.17539509, std: 0.11218612 }),
      B07: Object.freeze({ mean: 0.122399144, std: 0.09915003 }),
    }),
    sentinel2: Object.freeze({
      B01: Object.freeze({ mean: 0.02791544, std: 0.036259905 }),
      B02: Object.freeze({ mean: 0.029266676, std: 0.043152064 }),
      B03: Object.freeze({ mean: 0.0495067, std: 0.054938238 }),
      B04: Object.freeze({ mean: 0.056533907, std: 0.074629895 }),
      B8A: Object.freeze({ mean: 0.11535108, std: 0.1386856 }),
      B11: Object.freeze({ mean: 0.110029705, std: 0.14791493 }),
      B12: Object.freeze({ mean: 0.10856465, std: 0.10264611 }),
      B05: Object.freeze({ mean: 0.060848773, std: 0.08423215 }),
      B06: Object.freeze({ mean: 0.10886431, std: 0.09529256 }),
      B07: Object.freeze({ mean: 0.11124648, std: 0.12159706 }),
      B08: Object.freeze({ mean: 0.11155568, std: 0.12414841 }),
    }),
  }),
  fieldIdentityStates: Object.freeze([
    'candidate_only',
    'accepted',
    'abstained',
    'unavailable',
    'blocked',
  ] as const),
  confidenceState: 'uncalibrated',
}) as const

export type FarmWatchCurrentCropIdentityState =
  typeof FARM_WATCH_CURRENT_CROP_IDENTITY_PRODUCT.fieldIdentityStates[number]

export const FARM_WATCH_CURRENT_CROP_IDENTITY_LIMITATIONS = Object.freeze([
  'The published model is a 30 m pixel classifier. It does not publish a validated field-level consensus threshold for accepting one crop identity for an entire USDA field polygon.',
  'The released model returns raw 50-class logits and the application uses argmax. Softmax(logits), logit magnitude, or a logit margin must not be described as a calibrated crop probability without a separate calibration study.',
  'Field vote fraction, top-two vote margin, class entropy, and input-support counts are neutral diagnostics only until an acceptance/abstention rule is validated.',
  'The training pipeline discarded records with fewer than four HLS observations across two years. That is a training-data filter, not a Farm Watch sufficiency threshold.',
  'The published application QA excludes fill, cloud, adjacent cloud/shadow, cloud shadow, and snow/ice. It does not explicitly exclude water or high aerosol, so the crop-identity spectral collector must remain separate from the existing vegetation-index sampler unless model-equivalence is validated.',
  'The model artifact is publicly downloadable, but its exact Zenodo record-level reuse license was not verified during this spike. Do not vendor, redistribute, or operationally execute the model artifact until that rights gate is resolved.',
  'Current crop identity is neutral agricultural evidence. It does not establish harvest, forage value, deer use, attraction, habitat quality, or management action.',
])

function isUuid(value: unknown) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(String(value || ''))
}

function finiteUnit(value: unknown) {
  const number = Number(value)
  return Number.isFinite(number) && number >= 0 && number <= 1
}

export function validateFarmWatchCurrentCropIdentityEvidence(value: any) {
  const state = String(value?.status || '') as FarmWatchCurrentCropIdentityState
  if (!FARM_WATCH_CURRENT_CROP_IDENTITY_PRODUCT.fieldIdentityStates.includes(state)) return false
  if (!isUuid(value?.field_id)) return false
  if (!/^\d{4}-\d{2}-\d{2}$/.test(String(value?.as_of_date || ''))) return false
  if (value?.schema_version !== FARM_WATCH_CURRENT_CROP_IDENTITY_PRODUCT.schemaVersion) return false

  if (
    value?.scoring_performed !== false ||
    value?.behavioral_inference_performed !== false ||
    value?.harvest_inference_performed !== false
  ) return false

  if (value?.confidence?.state !== 'uncalibrated') return false
  if (value?.confidence?.calibrated_probability != null) return false

  for (const key of ['field_vote_fraction','top2_vote_margin']) {
    if (value?.confidence?.[key] != null && !finiteUnit(value.confidence[key])) return false
  }

  if (!Array.isArray(value?.abstention_reasons)) return false
  if (!value?.provenance || typeof value.provenance !== 'object') return false

  if (state === 'accepted') {
    if (!Number.isInteger(Number(value?.accepted_crop?.cdl_code))) return false
    if (typeof value?.accepted_crop?.name !== 'string' || !value.accepted_crop.name) return false
    if (value.abstention_reasons.length !== 0) return false
  } else {
    if (value?.accepted_crop != null) return false
  }

  if (value?.candidate_crop != null) {
    if (!Number.isInteger(Number(value.candidate_crop?.cdl_code))) return false
    if (typeof value.candidate_crop?.name !== 'string' || !value.candidate_crop.name) return false
  }

  return true
}
