import {
  evaluateDeerRelationship,
  evaluateDeerScienceContext,
  type FarmWatchDeerEvaluatorEvidence,
  type FarmWatchDeerScienceScenario,
} from './farm-watch-deer-science-evaluator.ts'
import {
  getDeerRelationship,
  type DeerRelationshipProductKey,
  type DeerRelationshipEvidenceState,
  type DeerRelationshipScale,
} from './farm-watch-deer-relationship-registry.ts'

function assert(condition: unknown, message = 'assertion failed'): asserts condition {
  if (!condition) throw new Error(message)
}

function scenario(
  patch: Partial<FarmWatchDeerScienceScenario> = {},
): FarmWatchDeerScienceScenario {
  return {
    property_slug: 'validation-property-01',
    state_code: 'KY',
    at: '2026-09-26T12:00:00.000Z',
    sex: 'male',
    age_class: 'adult',
    movement_state: 'resident',
    individual_reproductive_state: 'nonbreeding',
    season: 'fall',
    diel_period: 'day',
    regional_reproductive_context: 'outside_documented_breeding_season',
    ...patch,
  }
}

function evidence(
  product_key: DeerRelationshipProductKey,
  evidence_state: DeerRelationshipEvidenceState,
  scales: DeerRelationshipScale[],
  values: Record<string, unknown> = {},
): FarmWatchDeerEvaluatorEvidence {
  return {
    product_key,
    evidence_state,
    scales,
    values,
    evidence_class: 'test',
    source_status: evidence_state,
  }
}

function relationship(id: string) {
  const row = getDeerRelationship(id)
  assert(row, id + ' missing')
  return row
}

Deno.test('unknown required biological dimension abstains before property interpretation', () => {
  const row = evaluateDeerRelationship({
    relationship: relationship('FW-R19-juvenile-male-dispersal-ag-riparian'),
    scenario: scenario({
      sex: 'male',
      age_class: 'juvenile',
      movement_state: 'unknown',
    }),
    evidence: [],
  })
  assert(row.status === 'insufficient_input')
  assert(row.reason_codes.includes('biological_state_unknown'))
  assert(row.biological_gate.missing_dimensions.includes('movement_state'))
})

Deno.test('known biological mismatch is not applicable rather than missing input', () => {
  const row = evaluateDeerRelationship({
    relationship: relationship('FW-R19-juvenile-male-dispersal-ag-riparian'),
    scenario: scenario({
      sex: 'male',
      age_class: 'adult',
      movement_state: 'resident',
    }),
    evidence: [],
  })
  assert(row.status === 'not_applicable')
  assert(row.reason_codes.includes('biological_gate_mismatch'))
})

Deno.test('study-fidelity blocker cannot be bypassed with otherwise explicit scenario', () => {
  const row = evaluateDeerRelationship({
    relationship: relationship('FW-R01-summer-thermal-resource-tradeoff'),
    scenario: scenario({
      sex: 'male',
      age_class: 'adult',
      movement_state: 'resident',
      season: 'summer',
      diel_period: 'day',
    }),
    evidence: [],
  })
  assert(row.status === 'blocked_measurement_alignment')
  assert(row.reason_codes.includes('required_measurement_alignment_blocked'))
  assert(row.fidelity.blocker_ids.includes('FW-M04-woody-canopy'))
})

Deno.test('context-only fidelity cannot emit an ordinal mast result', () => {
  const row = evaluateDeerRelationship({
    relationship: relationship('FW-R11-mast-fall-space-use'),
    scenario: scenario({
      sex: 'female',
      age_class: 'adult',
      season: 'fall',
    }),
    evidence: [
      evidence('deer-biological-state', 'available', ['individual_scenario']),
      evidence('mast-capacity', 'available', ['property']),
      evidence('annual-mast-state', 'proxy', ['regional']),
    ],
  })
  assert(row.fidelity.status === 'context_only')
  assert(row.output_kind === 'ordinal_directional')
  assert(row.status === 'blocked_measurement_alignment')
  assert(row.reason_codes.includes(
    'context_only_measurement_cannot_emit_requested_output_kind',
  ))
})

Deno.test('known inactive extreme-event state makes hurricane relationship not applicable', () => {
  const row = evaluateDeerRelationship({
    relationship: relationship('FW-R22-extreme-storm-refuge'),
    scenario: scenario(),
    evidence: [
      evidence(
        'extreme-weather-event-context',
        'known',
        ['property'],
        { applicability_state: 'not_applicable', event_active: false },
      ),
      evidence('terrain-form-permeability', 'available', ['local_500m']),
      evidence('forest-type-context', 'proxy', ['property']),
      evidence('surface-water-state', 'known', ['local_500m']),
    ],
  })
  assert(row.status === 'not_applicable')
  assert(row.reason_codes.includes('value_constraint_not_satisfied'))
  const gate = row.value_constraints.find(
    (constraint) => constraint.id === 'FW-C06-extreme-event-active',
  )
  assert(gate?.status === 'failed')
})

Deno.test('known absence of managed artificial water makes summer water-visitation relationship not applicable', () => {
  const row = evaluateDeerRelationship({
    relationship: relationship('FW-R23-water-rainfall-context'),
    scenario: scenario({ season: 'summer' }),
    evidence: [
      evidence(
        'managed-water-source-context',
        'known',
        ['property'],
        {
          current_presence_state: 'known_managed_source_absent',
          inventory_status: 'confirmed_none',
        },
      ),
      evidence('seasonal-state', 'proxy', ['property']),
    ],
  })
  assert(row.status === 'not_applicable')
  assert(row.reason_codes.includes('value_constraint_not_satisfied'))
  const gate = row.value_constraints.find(
    (constraint) => constraint.id === 'FW-C05-water-present',
  )
  assert(gate?.status === 'failed')
})

Deno.test('juvenile-male dispersal path relationship activates only with explicit scenario and aligned inputs', () => {
  const row = evaluateDeerRelationship({
    relationship: relationship('FW-R19-juvenile-male-dispersal-ag-riparian'),
    scenario: scenario({
      sex: 'male',
      age_class: 'juvenile',
      movement_state: 'dispersal',
    }),
    evidence: [
      evidence('deer-biological-state', 'available', ['individual_scenario']),
      evidence('agriculture-landcover-context', 'known', ['landscape_1500m']),
      evidence('mapped-hydrography-context', 'available', ['landscape_1500m']),
    ],
  })
  assert(row.status === 'active')
  assert(row.result?.output_kind === 'ordinal_directional')
  assert(row.result?.direction === 'interaction')
  assert(row.coefficient_transfer.status === 'not_supported')
  assert(row.coefficient_transfer.numeric_parameters.length === 0)
})

Deno.test('juvenile-male dispersal terrain relationship emits conditional mechanism context, never a ridge/road sign', () => {
  const row = evaluateDeerRelationship({
    relationship: relationship('FW-R18-terrain-movement-context'),
    scenario: scenario({
      sex: 'male',
      age_class: 'juvenile',
      movement_state: 'dispersal',
    }),
    evidence: [
      evidence('deer-biological-state', 'available', ['individual_scenario']),
      evidence('terrain-form-permeability', 'available', ['local_500m']),
      evidence('multiscale-forest-context', 'available', ['multiscale']),
      evidence('road-focal-context', 'available', ['local_500m']),
    ],
  })
  assert(row.status === 'active')
  assert(row.result?.output_kind === 'mechanism_context')
  assert(row.result?.direction === 'conditional')
  assert(row.blocked_universal_assumptions.includes('ridge_generic_corridor'))
  assert(row.blocked_universal_assumptions.includes('roads_generic_selection'))
})

Deno.test('negative constraints remain first-class evaluator outputs', () => {
  const row = evaluateDeerRelationship({
    relationship: relationship('FW-R06-moon-phase-negative-constraint'),
    scenario: scenario(),
    evidence: [],
  })
  assert(row.status === 'active')
  assert(row.result?.output_kind === 'negative_constraint')
  assert(row.result?.direction === 'null_constraint')
  assert(row.blocked_universal_assumptions.includes('moon_phase_generic_movement'))
})

Deno.test('science context remains a relationship vector without synthesized score or probability', () => {
  const result = evaluateDeerScienceContext({
    scenario: scenario(),
    evidence: [],
    relationships: [
      relationship('FW-R06-moon-phase-negative-constraint'),
      relationship('FW-R07-routine-weather-negative-constraint'),
      relationship('FW-R10-firearm-opening-negative-constraint'),
    ],
  })
  assert(result.status === 'available')
  assert(result.counts.active === 3)
  assert(result.scoring_performed === false)
  assert(result.coefficient_synthesis_performed === false)
  assert(result.behavioral_probability_inferred === false)

  const encoded = JSON.stringify(result)
  for (const forbidden of [
    'deer_score',
    'habitat_score',
    'bedding_score',
    'movement_score',
    'water_preference_score',
  ]) {
    assert(!encoded.includes(forbidden), forbidden)
  }
})
