export const FARM_WATCH_FIELD_PHENOLOGY_PRODUCT = Object.freeze({
  key: 'field-phenology-context',
  algorithmVersion: 'farm-watch-field-phenology-resolver-v1',
  outputSchemaVersion: 'field-phenology-context-v1',
  evidenceClass: 'deterministic_derived',
  fieldObservationSchemaVersion: 'hls-field-vegetation-observation-v1',
  scopeVocabulary: Object.freeze(['property','local_500m','landscape_1500m','broad_3000m'] as const),
  evidenceStateVocabulary: Object.freeze(['known','proxy','stale','unavailable'] as const),
  phenologyStateVocabulary: Object.freeze([
    'green_up','vegetative','mature_senescing','probable_harvest_transition',
    'post_harvest_residual','unknown',
  ] as const),
  trajectoryVocabulary: Object.freeze([
    'increasing','stable','declining','insufficient_observations','unknown',
  ] as const),
  observationFreshDays: 10,
  trajectoryLookbackDays: 45,
  minimumValidFraction: 0.30,
})

export const FARM_WATCH_FIELD_PHENOLOGY_LIMITATIONS = Object.freeze([
  'CDL/CSB establishes mapped crop identity and field geometry, not current standing crop, harvest state, forage quality, or wildlife use.',
  'HLS vegetation observations are remotely sensed field summaries with cloud/data-quality limits; missing or poor-quality scenes remain explicit rather than being imputed.',
  'NASS crop progress is regional context only and never promotes a field-level state by itself.',
  'Batch 4A does not assign harvest from a generic NDVI drop threshold. Harvest-specific inference remains unknown until an evidence-backed field-level method has sufficient observations and its transfer contract is satisfied.',
  'The product performs no deer-use, movement, bedding, attraction, habitat-quality, or management scoring.',
])

function sha(value: unknown) {
  return /^[0-9a-f]{64}$/.test(String(value || ''))
}

export function validateFarmWatchFieldPhenologyContext(value: any) {
  if (
    value?.schema !== FARM_WATCH_FIELD_PHENOLOGY_PRODUCT.outputSchemaVersion ||
    value?.method !== FARM_WATCH_FIELD_PHENOLOGY_PRODUCT.algorithmVersion ||
    value?.evidence_class !== FARM_WATCH_FIELD_PHENOLOGY_PRODUCT.evidenceClass ||
    value?.scoring_performed !== false || value?.behavioral_inference_performed !== false ||
    !/^\d{4}-\d{2}-\d{2}$/.test(String(value?.as_of_date || '')) ||
    !Array.isArray(value?.fields) || !value?.scope_counts || !sha(value?.source_fingerprint_sha256)
  ) return false

  for (const field of value.fields) {
    if (!/^[0-9a-f-]{36}$/i.test(String(field?.field_id || ''))) return false
    if (!FARM_WATCH_FIELD_PHENOLOGY_PRODUCT.evidenceStateVocabulary.includes(field?.evidence_state)) return false
    if (!FARM_WATCH_FIELD_PHENOLOGY_PRODUCT.phenologyStateVocabulary.includes(field?.phenology_state)) return false
    if (!FARM_WATCH_FIELD_PHENOLOGY_PRODUCT.trajectoryVocabulary.includes(field?.trajectory_state)) return false
    if (!Array.isArray(field?.scopes) || field.scopes.some((scope: unknown) =>
      !FARM_WATCH_FIELD_PHENOLOGY_PRODUCT.scopeVocabulary.includes(scope as any))) return false
  }
  return true
}

export function validateFarmWatchFieldPhenologyResponse(value: any) {
  if (!['available','partial','unavailable','missing','stale'].includes(String(value?.status || ''))) return false
  if (value?.status === 'missing' || value?.status === 'stale') return value?.context == null
  if (value?.status === 'unavailable' && value?.context == null) {
    return typeof value?.unavailable_reason === 'string' && value.unavailable_reason.length > 0
  }
  if (!validateFarmWatchFieldPhenologyContext(value?.context)) return false
  const identity = value?.identity
  return Boolean(
    identity && sha(identity.boundary_sha256) && sha(identity.landscape_domain_identity_sha256) &&
    sha(identity.source_signature_sha256) && sha(identity.identity_sha256) &&
    identity.algorithm_version === FARM_WATCH_FIELD_PHENOLOGY_PRODUCT.algorithmVersion &&
    identity.output_schema_version === FARM_WATCH_FIELD_PHENOLOGY_PRODUCT.outputSchemaVersion
  )
}
