import {
  buildDeerEvaluatorEvidenceFromFarmWatch,
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

Deno.test('R08 does not emit crepuscular context at night', () => {
  const row = evaluateDeerRelationship({
    relationship: relationship('FW-R08-reproductive-diel-movement-context'),
    scenario: scenario({ diel_period: 'night' }),
    evidence: [
      evidence('deer-biological-state', 'available', ['individual_scenario']),
      evidence('diel-photoperiod-context', 'available', ['property']),
    ],
  })
  assert(row.status === 'not_applicable')
  assert(row.reason_codes.includes('biological_gate_mismatch'))
  const mismatch = row.biological_gate.mismatches.find(
    (item) => item.dimension === 'diel_period',
  )
  assert(mismatch)
  assert(mismatch.allowed.includes('morning_civil_twilight'))
  assert(mismatch.allowed.includes('evening_civil_twilight'))
  assert(row.decision_relevance === 'abstained')
  assert(row.decision_actionable === false)
})

Deno.test('R08 may emit mechanism context only during the transparent civil-twilight proxy', () => {
  const row = evaluateDeerRelationship({
    relationship: relationship('FW-R08-reproductive-diel-movement-context'),
    scenario: scenario({ diel_period: 'morning_civil_twilight' }),
    evidence: [
      evidence('deer-biological-state', 'available', ['individual_scenario']),
      evidence('diel-photoperiod-context', 'available', ['property']),
    ],
  })
  assert(row.status === 'active')
  assert(row.decision_relevance === 'mechanism_context')
  assert(row.decision_actionable === false)
  assert(row.result?.output_kind === 'mechanism_context')
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

Deno.test('juvenile-male dispersal path relationship can be active without becoming a property directional conclusion', () => {
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
  assert(row.decision_relevance === 'directional_relationship_context')
  assert(row.decision_actionable === false)
  assert(row.property_directional_evidence.status === 'not_configured')
  assert(row.property_directional_evidence.evaluated === false)
  assert(
    row.property_directional_evidence.reason_codes.includes(
      'property_conditioning_not_configured',
    ),
  )
})

Deno.test('active ordinal relationships remain relationship context until property covariates are evaluated', () => {
  const result = evaluateDeerScienceContext({
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
    relationships: [
      relationship('FW-R19-juvenile-male-dispersal-ag-riparian'),
    ],
  })

  assert(result.status === 'available')
  assert(result.counts.active === 1)
  assert(result.decision_relevance_counts.directional_relationship_context === 1)
  assert(result.directional_relationship_context_count === 1)
  assert(
    result.directional_relationship_context_ids.includes(
      'FW-R19-juvenile-male-dispersal-ag-riparian',
    ),
  )
  assert(result.decision_actionable_relationship_count === 0)
  assert(result.decision_actionable_relationship_ids.length === 0)
  assert(result.property_directional_evidence_evaluated === false)
  assert(result.property_directional_evidence_relationship_count === 0)

  const row = result.relationships[0]
  assert(row.status === 'active')
  assert(row.decision_relevance === 'directional_relationship_context')
  assert(row.decision_actionable === false)
  assert(row.property_directional_evidence.status === 'not_configured')
})

Deno.test('R30 emits a property-conditioned agriculture hypothesis only after measuring an explicit multi-scale contrast', () => {
  const result = evaluateDeerScienceContext({
    scenario: scenario({
      sex: 'male',
      age_class: 'juvenile',
      movement_state: 'resident',
      season: 'spring',
    }),
    evidence: [
      evidence('deer-biological-state', 'available', ['individual_scenario']),
      evidence(
        'agriculture-landcover-context',
        'known',
        ['local_500m','landscape_1500m','broad_3000m'],
        {
          mapped_agriculture_fraction_percent_by_scale: {
            local_500m: 0.66,
            landscape_1500m: 2.53,
            broad_3000m: 3.89,
          },
        },
      ),
    ],
    relationships: [
      relationship('FW-R30-spring-juvenile-male-dispersal-probability'),
    ],
  })

  assert(result.status === 'available')
  assert(result.directional_relationship_context_count === 1)
  assert(result.property_directional_evidence_evaluated === true)
  assert(result.property_directional_evidence_relationship_count === 1)
  assert(result.property_conditioned_hypothesis_count === 1)
  assert(
    result.property_conditioned_hypothesis_relationship_ids.includes(
      'FW-R30-spring-juvenile-male-dispersal-probability',
    ),
  )
  assert(result.decision_actionable_relationship_count === 0)
  assert(result.behavioral_probability_inferred === false)

  const row = result.relationships[0]
  assert(row.status === 'active')
  assert(row.decision_relevance === 'directional_relationship_context')
  assert(row.decision_actionable === false)
  assert(row.property_directional_evidence.status === 'hypothesis_available')
  assert(row.property_directional_evidence.evaluated === true)
  assert(row.property_directional_evidence.conditioning_rule_id === 'FW-P01-r30-agriculture-scale-contrast')
  assert(row.property_directional_evidence.observations?.length === 3)
  assert(row.property_directional_evidence.contrast?.lower_scale === 'local_500m')
  assert(row.property_directional_evidence.contrast?.higher_scale === 'broad_3000m')
  assert(
    Math.abs(
      Number(row.property_directional_evidence.contrast?.absolute_difference) - 3.23,
    ) < 0.000001,
  )
  assert(row.property_directional_evidence.hypothesis?.behavioral_response_inferred === false)
  assert(row.property_directional_evidence.hypothesis?.coefficient_transfer_performed === false)
})

Deno.test('R30 remains measured-but-insufficient when only one explicit agriculture scale exists', () => {
  const row = evaluateDeerRelationship({
    relationship: relationship('FW-R30-spring-juvenile-male-dispersal-probability'),
    scenario: scenario({
      sex: 'male',
      age_class: 'juvenile',
      season: 'spring',
    }),
    evidence: [
      evidence('deer-biological-state', 'available', ['individual_scenario']),
      evidence(
        'agriculture-landcover-context',
        'known',
        ['landscape_1500m'],
        {
          mapped_agriculture_fraction_percent_by_scale: {
            landscape_1500m: 2.53,
          },
        },
      ),
    ],
  })

  assert(row.status === 'active')
  assert(row.property_directional_evidence.status === 'insufficient_measurement')
  assert(row.property_directional_evidence.evaluated === true)
  assert(
    row.property_directional_evidence.reason_codes.includes(
      'property_covariate_contrast_unavailable',
    ),
  )
  assert(row.decision_actionable === false)
})

Deno.test('R30 ignores numeric scale values not declared by the evidence row', () => {
  const row = evaluateDeerRelationship({
    relationship: relationship('FW-R30-spring-juvenile-male-dispersal-probability'),
    scenario: scenario({ sex: 'male', age_class: 'juvenile', season: 'spring' }),
    evidence: [
      evidence('deer-biological-state', 'available', ['individual_scenario']),
      evidence(
        'agriculture-landcover-context',
        'known',
        ['local_500m'],
        {
          mapped_agriculture_fraction_percent_by_scale: {
            local_500m: 1,
            broad_3000m: 9,
          },
        },
      ),
    ],
  })

  assert(row.status === 'active')
  assert(row.property_directional_evidence.status === 'insufficient_measurement')
  assert(row.property_directional_evidence.evaluated === true)
  assert(row.property_directional_evidence.observations?.length === 1)
  assert(row.property_directional_evidence.observations?.[0].scale === 'local_500m')
})

Deno.test('Farm Watch evidence adapter derives mapped agriculture fractions from existing landscape context', () => {
  const adapted = buildDeerEvaluatorEvidenceFromFarmWatch({
    scenario: scenario(),
    deer_context: {
      deer_biological_state: { status: 'available' },
      diel_photoperiod: { status: 'available' },
      seasonal_state: { status: 'available', context: { component_states: {} } },
      field_phenology: { status: 'available', context: { fields: [] } },
    },
    deer_evidence_stack: { products: {} },
    landscape_context: {
      status: 'available',
      identity_sha256: 'landscape-test',
      evidence_class: 'deterministic_derived',
      domain: {
        areas_acres: {
          '500': 423.07,
          '1500': 1456.5,
          '3000': 5286.42,
        },
      },
      agriculture: {
        field_context_by_zone: [
          { radius_m: 500, field_count: 1, intersected_field_acres: 2.79 },
          { radius_m: 1500, field_count: 12, intersected_field_acres: 36.82 },
          { radius_m: 3000, field_count: 37, intersected_field_acres: 205.73 },
        ],
      },
    },
  })

  const agriculture = adapted.find(
    (row) => row.product_key === 'agriculture-landcover-context',
  )
  assert(agriculture)
  assert(agriculture.evidence_state === 'known')
  assert(agriculture.scales.includes('local_500m'))
  assert(agriculture.scales.includes('landscape_1500m'))
  assert(agriculture.scales.includes('broad_3000m'))
  const fractions = agriculture.values?.mapped_agriculture_fraction_percent_by_scale as Record<string, number>
  assert(Math.abs(fractions.local_500m - (2.79 / 423.07 * 100)) < 0.000001)
  assert(Math.abs(fractions.landscape_1500m - (36.82 / 1456.5 * 100)) < 0.000001)
  assert(Math.abs(fractions.broad_3000m - (205.73 / 5286.42 * 100)) < 0.000001)
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
  assert(row.decision_relevance === 'mechanism_context')
  assert(row.decision_actionable === false)
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
  assert(row.decision_relevance === 'negative_constraint')
  assert(row.decision_actionable === false)
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
  assert(result.decision_relevance_counts.directional_relationship_context === 0)
  assert(result.decision_relevance_counts.mechanism_context === 0)
  assert(result.decision_relevance_counts.negative_constraint === 3)
  assert(result.decision_relevance_counts.abstained === 0)
  assert(result.decision_actionable_relationship_count === 0)
  assert(result.decision_actionable_relationship_ids.length === 0)
  assert(result.directional_relationship_context_count === 0)
  assert(result.directional_relationship_context_ids.length === 0)
  assert(result.property_directional_evidence_evaluated === false)
  assert(result.property_directional_evidence_relationship_count === 0)
  assert(result.property_directional_evidence_relationship_ids.length === 0)
  assert(result.evaluator_active_relationship_ids.length === 3)
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
