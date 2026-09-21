export const FARM_WATCH_SEASONAL_STATE_PRODUCT = Object.freeze({
  key: 'seasonal-state',
  algorithmVersion: 'farm-watch-seasonal-state-resolver-v1',
  outputSchemaVersion: 'farm-watch-seasonal-state-v1',
  evidenceClass: 'deterministic_derived',
  stateVocabulary: Object.freeze(['known','proxy','stale','unavailable'] as const),
  componentKeys: Object.freeze([
    'precipitation',
    'drought',
    'stream',
    'rootzone_soil_moisture',
    'state_fieldwork',
    'regional_crop_progress',
    'state_crop_stage',
    'mapped_crop_context',
  ] as const),
})

export type FarmWatchSeasonalEvidenceState =
  typeof FARM_WATCH_SEASONAL_STATE_PRODUCT.stateVocabulary[number]

export const FARM_WATCH_SEASONAL_STATE_LIMITATIONS = Object.freeze([
  'Seasonal-state components retain their own spatial scope, observation date, and freshness. A proxy must not be promoted to property-level observed truth.',
  'Stale or unavailable inputs remain explicit and must not be silently imputed by a later biological model.',
  'Mapped CDL crop identity does not establish standing crop, forage availability, harvest state, access, or animal use.',
  'Nearest-gauge discharge and nearby Crop-CASMA soil moisture are off-property proxies, not measurements of water or soil conditions on the selected property.',
  'Regional crop-progress and fieldwork products do not establish field-level phenology, condition, or management state.',
  'This product performs no deer-use, movement, bedding, forage-use, water-use, hunting-pressure, habitat-quality, or management inference.',
])

function isState(value: unknown): value is FarmWatchSeasonalEvidenceState {
  return FARM_WATCH_SEASONAL_STATE_PRODUCT.stateVocabulary.includes(
    value as FarmWatchSeasonalEvidenceState,
  )
}

export function validateFarmWatchSeasonalStateContext(value: any) {
  if (
    value?.schema !== FARM_WATCH_SEASONAL_STATE_PRODUCT.outputSchemaVersion ||
    value?.method !== FARM_WATCH_SEASONAL_STATE_PRODUCT.algorithmVersion ||
    value?.evidence_class !== FARM_WATCH_SEASONAL_STATE_PRODUCT.evidenceClass ||
    value?.scoring_performed !== false ||
    value?.behavioral_inference_performed !== false ||
    !/^\d{4}-\d{2}-\d{2}$/.test(String(value?.as_of_date || '')) ||
    !value?.component_states ||
    !value?.components ||
    !/^[0-9a-f]{64}$/.test(String(value?.source_fingerprint_sha256 || ''))
  ) return false

  for (const key of FARM_WATCH_SEASONAL_STATE_PRODUCT.componentKeys) {
    if (!isState(value.component_states[key])) return false
    if (value.components[key]?.state !== value.component_states[key]) return false
  }
  return true
}

export function validateFarmWatchSeasonalStateResponse(value: any) {
  if (!['available','partial','unavailable','missing','stale'].includes(String(value?.status || ''))) {
    return false
  }
  if (value?.status === 'missing' || value?.status === 'stale') {
    return value?.context == null
  }
  if (!validateFarmWatchSeasonalStateContext(value?.context)) return false
  const identity = value?.identity
  return Boolean(
    identity &&
    /^[0-9a-f]{64}$/.test(String(identity.boundary_sha256 || '')) &&
    /^[0-9a-f]{64}$/.test(String(identity.source_signature_sha256 || '')) &&
    identity.algorithm_version === FARM_WATCH_SEASONAL_STATE_PRODUCT.algorithmVersion &&
    identity.output_schema_version === FARM_WATCH_SEASONAL_STATE_PRODUCT.outputSchemaVersion &&
    /^[0-9a-f]{64}$/.test(String(identity.identity_sha256 || ''))
  )
}
