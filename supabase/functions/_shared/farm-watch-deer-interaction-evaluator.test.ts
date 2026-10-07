import {
  evaluateDeerScienceContext,
  type FarmWatchDeerEvaluatorEvidence,
  type FarmWatchDeerScienceScenario,
} from './farm-watch-deer-science-evaluator.ts'
import {
  FARM_WATCH_DEER_INPUT_PRODUCT_CATALOG,
  getDeerRelationship,
  type DeerRelationshipEvidenceState,
  type DeerRelationshipScale,
} from './farm-watch-deer-relationship-registry.ts'
import { getDeerInteraction } from './farm-watch-deer-interaction-registry.ts'

function assert(condition: unknown, message = 'assertion failed'): asserts condition {
  if (!condition) throw new Error(message)
}

function scenario(patch: Partial<FarmWatchDeerScienceScenario> = {}): FarmWatchDeerScienceScenario {
  return {
    property_slug: 'validation-property-01',
    state_code: 'KY',
    at: '2026-10-02T12:00:00.000Z',
    sex: 'female',
    age_class: 'adult',
    movement_state: 'resident',
    individual_reproductive_state: 'nonbreeding',
    season: 'fall',
    diel_period: 'day',
    regional_reproductive_context: 'outside_documented_breeding_season',
    ...patch,
  }
}

function evidenceForRelationship(
  relationshipId: string,
  skipInputKey?: string,
  overrides: Record<string, Record<string, unknown>> = {},
): FarmWatchDeerEvaluatorEvidence[] {
  const relationship = getDeerRelationship(relationshipId)
  assert(relationship, relationshipId)
  return relationship.required_inputs
    .filter((input) => input.key !== skipInputKey)
    .flatMap((input) => {
      const productKey = input.product_keys[0]
      const product = FARM_WATCH_DEER_INPUT_PRODUCT_CATALOG[productKey]
      const productStates = product.evidence_states as readonly string[]
      const productScales = product.scales as readonly string[]
      const state = input.allowed_evidence_states.find((value) => productStates.includes(value))
      const scale = input.allowed_scales.find((value) => productScales.includes(value))
      if (!state || !scale) throw new Error('No compatible test evidence for ' + input.key)
      return [{
        product_key: productKey,
        evidence_state: state as DeerRelationshipEvidenceState,
        scales: [scale] as DeerRelationshipScale[],
        values: overrides[input.key] || {},
        evidence_class: 'interaction-regression',
        source_status: 'available',
      }]
    })
}

function interactionResult(result: ReturnType<typeof evaluateDeerScienceContext>, id: string) {
  const row = result.interaction_evaluation.interactions.find((item) => item.interaction_id === id)
  assert(row, id + ' missing from evaluator output')
  return row
}

Deno.test('unknown movement state blocks dispersal interaction activation', () => {
  const result = evaluateDeerScienceContext({
    scenario: scenario({ sex: 'male', age_class: 'juvenile', movement_state: 'unknown' }),
    evidence: [],
  })
  const row = interactionResult(result, 'FW-I09-dispersal-terrain-landscape-state')
  assert(row.status === 'blocked_by_state')
  assert(row.state_gate_result.missing_biological_dimensions.includes('movement_state'))
})

Deno.test('known incompatible sex is not applicable to the juvenile-male dispersal interaction', () => {
  const result = evaluateDeerScienceContext({
    scenario: scenario({ sex: 'female', age_class: 'juvenile', movement_state: 'dispersal' }),
    evidence: [],
  })
  const row = interactionResult(result, 'FW-I09-dispersal-terrain-landscape-state')
  assert(row.status === 'not_applicable')
})

Deno.test('available mechanism-only terrain context cannot satisfy a required interaction measurement', () => {
  const evidence = evidenceForRelationship('FW-R18-terrain-movement-context')
  const result = evaluateDeerScienceContext({
    scenario: scenario({ sex: 'male', age_class: 'juvenile', movement_state: 'dispersal' }),
    evidence,
  })
  const row = interactionResult(result, 'FW-I09-dispersal-terrain-landscape-state')
  assert(row.status === 'blocked_by_fidelity')
  const terrain = row.evidence_bindings.find((item) => item.measurement_id === 'FW-M34-dispersal-terrain-form')
  assert(terrain?.current_binding_status === 'satisfied')
  assert(terrain?.fidelity_class === 'mechanism_only')
})

Deno.test('one missing required winter covariate blocks the complete snow-conifer interaction', () => {
  const result = evaluateDeerScienceContext({
    scenario: scenario({ sex: 'female', season: 'winter' }),
    evidence: evidenceForRelationship('FW-R03-winter-snow-conifer-context', 'conifer_cover'),
  })
  const row = interactionResult(result, 'FW-I02-winter-snow-conifer-availability')
  assert(row.status === 'insufficient_input')
  assert(row.fidelity_result.missing_binding_measurement_ids.includes('FW-M09-dense-conifer-cover'))
})

Deno.test('winter snow-conifer context becomes eligible only with winter state and aligned snow plus calibrated conifer evidence', () => {
  const result = evaluateDeerScienceContext({
    scenario: scenario({ sex: 'female', season: 'winter' }),
    evidence: evidenceForRelationship('FW-R03-winter-snow-conifer-context'),
  })
  const row = interactionResult(result, 'FW-I02-winter-snow-conifer-availability')
  assert(row.status === 'eligible_context')
  assert(row.state_gate_result.status === 'pass')
  assert(row.fidelity_result.required_measurement_ids.includes('FW-M08-snow-depth-severity'))
  assert(row.fidelity_result.required_measurement_ids.includes('FW-M09-dense-conifer-cover'))
  assert(!row.fidelity_result.required_measurement_ids.includes('FW-M10-winter-solar-context'))
  assert(row.fidelity_result.context_only_measurement_ids.includes('FW-M10-winter-solar-context'))
})

Deno.test('static mast capacity cannot substitute for exact-year annual mast state', () => {
  const result = evaluateDeerScienceContext({
    scenario: scenario({ sex: 'female', season: 'fall' }),
    evidence: evidenceForRelationship('FW-R11-mast-fall-space-use', 'annual_mast_state'),
  })
  const row = interactionResult(result, 'FW-I08-mast-annual-state-fall')
  assert(row.status === 'insufficient_input')
  assert(row.fidelity_result.missing_binding_measurement_ids.includes('FW-M17-annual-mast-fall'))
})

Deno.test('known corn identity without a known field stage remains insufficient input', () => {
  const evidence = evidenceForRelationship('FW-R12-crop-phenology-home-range-response', undefined, {
    current_crop_identity: { crop_name: 'Corn' },
  })
  const result = evaluateDeerScienceContext({
    scenario: scenario({ sex: 'female' }),
    evidence,
  })
  const row = interactionResult(result, 'FW-I04-corn-identity-stage-harvest')
  assert(row.status === 'insufficient_input')
  assert(row.state_gate_result.unresolved_state_constraint_ids.includes('FW-C02-corn-stage'))
})

Deno.test('interaction evaluation stays separate from property-conditioned deer-use hypotheses', () => {
  const result = evaluateDeerScienceContext({ scenario: scenario(), evidence: [] })
  assert(result.interaction_evaluation.scoring_performed === false)
  assert(result.interaction_evaluation.behavioral_probability_inferred === false)
  assert(result.interaction_evaluation.decision_actionable === false)
  for (const row of result.interaction_evaluation.interactions) {
    assert(row.property_conditioned_interaction_hypothesis_available === false)
    assert(row.decision_actionable === false)
    assert(row.behavioral_probability_inferred === false)
    assert(row.scoring_performed === false)
  }
})

Deno.test('interaction records retain source form without transferring coefficients or a numeric score', () => {
  const row = getDeerInteraction('FW-I01-thermal-vegetation-forage-activity-period')
  assert(row)
  assert(row.structure === 'source_statistical_interaction')
  assert(row.coefficient_transfer_disposition === 'not_authorized')
  const output = evaluateDeerScienceContext({
    scenario: scenario({ sex: 'male', age_class: 'adult', season: 'summer' }),
    evidence: evidenceForRelationship('FW-R01-summer-thermal-resource-tradeoff'),
  })
  const evaluated = interactionResult(output, row.interaction_id)
  assert(evaluated.status === 'blocked_by_fidelity')
  assert(!('score' in evaluated))
  assert(!('numeric_formula' in evaluated))
  assert(evaluated.coefficient_transfer_disposition === 'not_authorized')
})
