import {
  FARM_WATCH_DEER_BIOLOGICAL_STATE_PRODUCT,
  validateDeerBiologicalState,
} from './farm-watch-diel-biological-state-contract.ts'
import {
  applicableDeerRelationshipIds,
  buildDeerBiologicalState,
  classifySolarPhase,
  meteorologicalSeason,
  regionalBreedingPhase,
} from './farm-watch-diel-biological-state.ts'

function assert(condition: unknown, message = 'assertion failed'): asserts condition {
  if (!condition) throw new Error(message)
}

Deno.test('solar phase uses physical solar elevation and morning/evening hour-angle sign', () => {
  assert(classifySolarPhase({ solarElevationDeg: 12, hourAngleDeg: -30 }) === 'day')
  assert(
    classifySolarPhase({ solarElevationDeg: -3, hourAngleDeg: -90 }) ===
      'morning_civil_twilight',
  )
  assert(
    classifySolarPhase({ solarElevationDeg: -3, hourAngleDeg: 90 }) ===
      'evening_civil_twilight',
  )
  assert(classifySolarPhase({ solarElevationDeg: -12, hourAngleDeg: 130 }) === 'night')
})

Deno.test('meteorological season is deterministic and species-neutral', () => {
  assert(meteorologicalSeason(1) === 'winter')
  assert(meteorologicalSeason(4) === 'spring')
  assert(meteorologicalSeason(7) === 'summer')
  assert(meteorologicalSeason(10) === 'fall')
})

Deno.test('Kentucky breeding context remains regional and qualitative', () => {
  assert(
    regionalBreedingPhase({
      date: '2026-09-21',
      stateCode: 'KY',
      breedingStartMonth: 10,
      breedingEndMonth: 1,
      peakTimingLabel: 'mid-November',
    }) === 'outside_documented_breeding_season',
  )
  assert(
    regionalBreedingPhase({
      date: '2026-11-15',
      stateCode: 'KY',
      breedingStartMonth: 10,
      breedingEndMonth: 1,
      peakTimingLabel: 'mid-November',
    }) === 'within_peak_month_context',
  )
  assert(
    regionalBreedingPhase({
      date: '2026-12-15',
      stateCode: 'KY',
      breedingStartMonth: 10,
      breedingEndMonth: 1,
      peakTimingLabel: 'mid-November',
    }) === 'within_documented_breeding_season',
  )
})

Deno.test('unknown individual state stays unknown while regional context remains available', () => {
  const value = buildDeerBiologicalState({
    at: '2026-11-15T13:00:00Z',
    stateCode: 'KY',
    diel: {
      solar_phase: 'day',
      solar_elevation_deg: 12,
      solar_azimuth_deg: 155,
    },
    breedingEvidence: {
      breeding_start_month: 10,
      breeding_end_month: 1,
      peak_timing_label: 'mid-November',
      evidence_class: 'authoritative_regional_summary',
      source_ids: ['kdfwr-deer-peak-breeding-reference','uky-white-tailed-deer-biology-kentucky'],
      ledger_ids: ['FW-D21'],
    },
  })
  assert(validateDeerBiologicalState(value))
  assert(value.individual_reproductive_state === 'unknown')
  assert(value.regional_reproductive_context.phase === 'within_peak_month_context')
  assert(value.regional_reproductive_context.individual_state_inferred === false)
  assert(value.state_provenance.individual_reproductive_state === 'unknown')
})

Deno.test('female age context uses relationship form but never transfers Illinois dates as Kentucky coefficients', () => {
  const value = buildDeerBiologicalState({
    at: '2026-11-15T13:00:00Z',
    stateCode: 'KY',
    sex: 'female',
    ageClass: 'juvenile',
    movementState: 'resident',
    diel: {
      solar_phase: 'day',
      solar_elevation_deg: 12,
      solar_azimuth_deg: 155,
    },
    breedingEvidence: {
      breeding_start_month: 10,
      breeding_end_month: 1,
      peak_timing_label: 'mid-November',
      evidence_class: 'authoritative_regional_summary',
      source_ids: ['kdfwr-deer-peak-breeding-reference','uky-white-tailed-deer-biology-kentucky'],
      ledger_ids: ['FW-D21'],
    },
  })
  assert(validateDeerBiologicalState(value))
  assert(value.age_timing_context.source_relationship_id === 'FW-D22')
  assert(value.age_timing_context.coefficient_transfer_authorized === false)
  assert(
    value.age_timing_context.state ===
      'illinois_reference_supports_later_conception_than_yearling_adult',
  )
  assert(value.applicable_relationship_ids.includes('FW-D22'))
})

Deno.test('male rut movement relationship is only applicable with known age and breeding-season context', () => {
  const ids = applicableDeerRelationshipIds({
    stateCode: 'KY',
    sex: 'male',
    ageClass: 'adult',
    regionalBreedingPhase: 'within_peak_month_context',
  })
  assert(ids.includes('FW-D06'))

  const blocked = applicableDeerRelationshipIds({
    stateCode: 'KY',
    sex: 'male',
    ageClass: 'unknown',
    regionalBreedingPhase: 'within_peak_month_context',
  })
  assert(!blocked.includes('FW-D06'))
})

Deno.test('biological-state contract contains no universal deer score', () => {
  const value = buildDeerBiologicalState({
    at: '2026-09-21T13:00:00Z',
    stateCode: 'KY',
    diel: {
      solar_phase: 'day',
      solar_elevation_deg: 32,
      solar_azimuth_deg: 145,
    },
    breedingEvidence: {
      breeding_start_month: 10,
      breeding_end_month: 1,
      peak_timing_label: 'mid-November',
      evidence_class: 'authoritative_regional_summary',
      source_ids: [],
      ledger_ids: ['FW-D21'],
    },
  })
  assert(validateDeerBiologicalState(value))
  assert(value.scoring_performed === false)
  assert(value.behavioral_inference_performed === false)
  assert(FARM_WATCH_DEER_BIOLOGICAL_STATE_PRODUCT.species === 'Odocoileus virginianus')
  const encoded = JSON.stringify(value)
  for (const forbidden of ['deer_score','habitat_score','rut_score','movement_score']) {
    assert(!encoded.includes(forbidden))
  }
})
