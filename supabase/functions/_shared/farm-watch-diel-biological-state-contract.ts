export const FARM_WATCH_DIEL_PHOTOPERIOD_PRODUCT = Object.freeze({
  key: 'diel-photoperiod-context',
  algorithmVersion: 'farm-watch-diel-photoperiod-v1',
  outputSchemaVersion: 'diel-photoperiod-context-v1',
  evidenceClass: 'deterministic_derived',
  solarPhaseVocabulary: Object.freeze([
    'night',
    'morning_civil_twilight',
    'day',
    'evening_civil_twilight',
  ] as const),
})

export const FARM_WATCH_DEER_BIOLOGICAL_STATE_PRODUCT = Object.freeze({
  key: 'deer-biological-state',
  algorithmVersion: 'farm-watch-deer-biological-state-v1',
  outputSchemaVersion: 'deer-biological-state-v1',
  species: 'Odocoileus virginianus',
  sexVocabulary: Object.freeze(['male','female','unknown'] as const),
  ageVocabulary: Object.freeze(['juvenile','yearling','adult','unknown'] as const),
  movementVocabulary: Object.freeze(['resident','dispersal','unknown'] as const),
  reproductiveVocabulary: Object.freeze([
    'unknown',
    'nonbreeding',
    'estrus',
    'pregnant',
    'parturition',
    'lactation',
  ] as const),
  regionalBreedingVocabulary: Object.freeze([
    'outside_documented_breeding_season',
    'within_documented_breeding_season',
    'within_peak_month_context',
    'unavailable',
  ] as const),
})

export const FARM_WATCH_DIEL_BIOLOGICAL_STATE_LIMITATIONS = Object.freeze([
  'Solar phase is deterministic physical context. Civil twilight is a transparent transition proxy and is not itself a measured deer activity period.',
  'Population breeding phenology is regional context and must not be promoted to an individual deer estrus, conception, pregnancy, or mating state.',
  'Kentucky v1 uses a statewide qualitative breeding summary because the annual KDFWR physiographic-region map has not yet been captured as a source-controlled machine-readable dataset.',
  'Published Illinois age-specific conception dates support age gating but are not copied as Kentucky date coefficients.',
  'Movement state, sex, age class, and individual reproductive state remain explicit scenario inputs. Unknown values remain unknown.',
  'No moon-phase, barometric-pressure, generic cold-front, ridge/draw/saddle, hunting-pressure, bedding, or habitat-quality inference is performed.',
])

export type FarmWatchDeerSex =
  typeof FARM_WATCH_DEER_BIOLOGICAL_STATE_PRODUCT.sexVocabulary[number]
export type FarmWatchDeerAgeClass =
  typeof FARM_WATCH_DEER_BIOLOGICAL_STATE_PRODUCT.ageVocabulary[number]
export type FarmWatchDeerMovementState =
  typeof FARM_WATCH_DEER_BIOLOGICAL_STATE_PRODUCT.movementVocabulary[number]
export type FarmWatchDeerReproductiveState =
  typeof FARM_WATCH_DEER_BIOLOGICAL_STATE_PRODUCT.reproductiveVocabulary[number]

function oneOf<T extends readonly string[]>(value: unknown, values: T): value is T[number] {
  return values.includes(String(value) as T[number])
}

export function validateDielPhotoperiodContext(value: any) {
  const p = FARM_WATCH_DIEL_PHOTOPERIOD_PRODUCT
  return Boolean(
    value?.schema === p.outputSchemaVersion &&
    value?.method === p.algorithmVersion &&
    value?.evidence_class === p.evidenceClass &&
    /^\d{4}-\d{2}-\d{2}$/.test(String(value?.solar_date || '')) &&
    Number.isFinite(Number(value?.anchor?.latitude)) &&
    Number.isFinite(Number(value?.anchor?.longitude)) &&
    Number.isFinite(Date.parse(String(value?.events?.civil_dawn || ''))) &&
    Number.isFinite(Date.parse(String(value?.events?.sunrise || ''))) &&
    Number.isFinite(Date.parse(String(value?.events?.solar_noon || ''))) &&
    Number.isFinite(Date.parse(String(value?.events?.sunset || ''))) &&
    Number.isFinite(Date.parse(String(value?.events?.civil_dusk || ''))) &&
    Number.isFinite(Number(value?.events?.daylight_minutes)) &&
    value?.scoring_performed === false &&
    value?.behavioral_inference_performed === false
  )
}

export function validateResolvedDielState(value: any) {
  const p = FARM_WATCH_DIEL_PHOTOPERIOD_PRODUCT
  return Boolean(
    value?.status === 'available' &&
    validateDielPhotoperiodContext(value?.context) &&
    oneOf(value?.diel?.solar_phase, p.solarPhaseVocabulary) &&
    Number.isFinite(Number(value?.diel?.solar_elevation_deg)) &&
    Number.isFinite(Number(value?.diel?.solar_azimuth_deg))
  )
}

export function validateDeerBiologicalState(value: any) {
  const p = FARM_WATCH_DEER_BIOLOGICAL_STATE_PRODUCT
  if (
    value?.schema !== p.outputSchemaVersion ||
    value?.method !== p.algorithmVersion ||
    value?.species !== p.species ||
    !Number.isFinite(Date.parse(String(value?.at || ''))) ||
    !oneOf(value?.sex, p.sexVocabulary) ||
    !oneOf(value?.age_class, p.ageVocabulary) ||
    !oneOf(value?.movement_state, p.movementVocabulary) ||
    !oneOf(value?.individual_reproductive_state, p.reproductiveVocabulary) ||
    !oneOf(
      value?.regional_reproductive_context?.phase,
      p.regionalBreedingVocabulary,
    ) ||
    !Array.isArray(value?.applicable_relationship_ids) ||
    value?.scoring_performed !== false ||
    value?.behavioral_inference_performed !== false
  ) return false

  if (
    value.individual_reproductive_state === 'unknown' &&
    value?.state_provenance?.individual_reproductive_state !== 'unknown'
  ) return false

  return true
}
