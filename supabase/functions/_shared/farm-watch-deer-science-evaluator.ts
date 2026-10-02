import {
  FARM_WATCH_DEER_INPUT_PRODUCT_CATALOG,
  FARM_WATCH_DEER_RELATIONSHIPS,
  deerMeasurementEvidenceFidelityClass,
  deerRelationshipStudyFidelityStatus,
  type DeerEvidenceFidelityClass,
  type DeerRelationshipEvidenceState,
  type DeerRelationshipProductKey,
  type DeerRelationshipRecord,
  type DeerRelationshipScale,
} from './farm-watch-deer-relationship-registry.ts'
import type {
  FarmWatchDeerAgeClass,
  FarmWatchDeerMovementState,
  FarmWatchDeerReproductiveState,
  FarmWatchDeerSex,
} from './farm-watch-diel-biological-state-contract.ts'

export const FARM_WATCH_DEER_SCIENCE_CONTEXT_PRODUCT = Object.freeze({
  key: 'deer-science-context',
  algorithmVersion: 'farm-watch-deer-science-evaluator-v4',
  outputSchemaVersion: 'deer-science-context-v4',
  species: 'Odocoileus virginianus',
  statusVocabulary: Object.freeze([
    'active',
    'not_applicable',
    'insufficient_input',
    'blocked_measurement_alignment',
  ] as const),
})

export type FarmWatchDeerScienceRelationshipStatus =
  typeof FARM_WATCH_DEER_SCIENCE_CONTEXT_PRODUCT.statusVocabulary[number]

export const FARM_WATCH_DEER_DECISION_RELEVANCE = Object.freeze([
  'directional_relationship_context',
  'mechanism_context',
  'negative_constraint',
  'abstained',
] as const)

export type FarmWatchDeerDecisionRelevance =
  typeof FARM_WATCH_DEER_DECISION_RELEVANCE[number]

export type FarmWatchDeerEvaluatorEvidence = {
  product_key: DeerRelationshipProductKey
  evidence_state: DeerRelationshipEvidenceState
  scales: DeerRelationshipScale[]
  values?: Record<string, unknown>
  evidence_class?: string | null
  source_status?: string | null
  identity_sha256?: string | null
  as_of?: string | null
}

export type FarmWatchDeerScienceScenario = {
  property_slug: string
  state_code: string
  at: string
  sex: FarmWatchDeerSex
  age_class: FarmWatchDeerAgeClass
  movement_state: FarmWatchDeerMovementState
  individual_reproductive_state: FarmWatchDeerReproductiveState
  season: string
  diel_period: string
  regional_reproductive_context: string
}

type GateEvaluation = {
  status: 'pass' | 'not_applicable' | 'insufficient_input'
  missing_dimensions: string[]
  mismatches: Array<{
    dimension: string
    actual: string
    allowed: string[]
  }>
}

type InputEvaluation = {
  key: string
  status: 'satisfied' | 'missing_or_incompatible'
  match: 'any' | 'all'
  freshness_policy: 'current_required' | 'state_explicit' | 'static_context_ok'
  allowed_product_keys: DeerRelationshipProductKey[]
  allowed_evidence_states: DeerRelationshipEvidenceState[]
  allowed_scales: DeerRelationshipScale[]
  matched: Array<{
    product_key: DeerRelationshipProductKey
    evidence_state: DeerRelationshipEvidenceState
    scales: DeerRelationshipScale[]
    evidence_class?: string | null
    source_status?: string | null
    identity_sha256?: string | null
    as_of?: string | null
  }>
  offered: Array<{
    product_key: DeerRelationshipProductKey
    evidence_state: DeerRelationshipEvidenceState
    scales: DeerRelationshipScale[]
    source_status?: string | null
    as_of?: string | null
  }>
}

type ConstraintEvaluation = {
  id: string
  binding_key: string
  field: string
  operator: string
  values: string[]
  status: 'satisfied' | 'failed' | 'unresolved'
  observed_values: unknown[]
  rationale: string
}

type DeerMeasurementRelationshipUse =
  | 'supports_activation'
  | 'context_only'
  | 'blocks_relationship'
  | 'not_applicable'

type DeerMeasurementCurrentBindingStatus =
  | 'satisfied'
  | 'missing_or_incompatible'
  | 'not_bound'
  | 'not_applicable'

type DeerMeasurementFidelityMatrixRow = {
  measurement_id: string
  study_variable: string
  study_protocol: string
  binding_key: string | null
  activation_requirement: 'required' | 'context_only' | 'not_applicable'
  registry_alignment: string
  fidelity_class: DeerEvidenceFidelityClass
  relationship_use: DeerMeasurementRelationshipUse
  current_binding_status: DeerMeasurementCurrentBindingStatus
  permitted_use: string
  limitations: string[]
  accepted_products: DeerRelationshipProductKey[]
  accepted_evidence_states: DeerRelationshipEvidenceState[]
  accepted_scales: DeerRelationshipScale[]
  matched_evidence: InputEvaluation['matched']
  proxy_inflation_guard: string
}

type PropertyDirectionalObservation = {
  scale: DeerRelationshipScale
  value: number
  unit: string
}

type PropertyDirectionalEvidenceEvaluation = {
  status:
    | 'not_applicable'
    | 'not_configured'
    | 'insufficient_measurement'
    | 'measured_no_contrast'
    | 'hypothesis_available'
  evaluated: boolean
  reason_codes: string[]
  interpretation_boundary: string
  conditioning_rule_id?: string | null
  metric_label?: string | null
  support_geometry?: string | null
  observations?: PropertyDirectionalObservation[]
  contrast?: {
    lower_scale: DeerRelationshipScale
    lower_value: number
    higher_scale: DeerRelationshipScale
    higher_value: number
    absolute_difference: number
    unit: string
  } | null
  hypothesis?: {
    source_response_variable: string
    source_relationship_direction: string
    higher_covariate_scale: DeerRelationshipScale
    higher_covariate_value: number
    lower_covariate_scale: DeerRelationshipScale
    lower_covariate_value: number
    interpretation: string
    behavioral_response_inferred: false
    coefficient_transfer_performed: false
  } | null
  limitations?: string[]
}

function knownDimension(value: string | null | undefined) {
  const normalized = String(value || '').trim()
  return Boolean(
    normalized &&
    normalized !== 'unknown' &&
    normalized !== 'unavailable' &&
    normalized !== 'not_resolved'
  )
}

function gateDimensionValue(
  scenario: FarmWatchDeerScienceScenario,
  dimension: string,
) {
  switch (dimension) {
    case 'sex':
      return scenario.sex
    case 'age_class':
      return scenario.age_class
    case 'movement_state':
      return scenario.movement_state
    case 'reproductive_state':
      return scenario.individual_reproductive_state
    case 'season':
      return scenario.season
    case 'diel_period':
      return scenario.diel_period
    case 'regional_reproductive_context':
      return scenario.regional_reproductive_context
    default:
      return ''
  }
}

function evaluateBiologicalGate(
  relationship: DeerRelationshipRecord,
  scenario: FarmWatchDeerScienceScenario,
): GateEvaluation {
  const missing = relationship.biological_state_gates.required_explicit_dimensions
    .filter((dimension) => !knownDimension(gateDimensionValue(scenario, dimension)))

  const mismatches: GateEvaluation['mismatches'] = []
  const checks: Array<[string, string, readonly string[] | null]> = [
    ['sex', scenario.sex, relationship.biological_state_gates.sex],
    ['age_class', scenario.age_class, relationship.biological_state_gates.age_class],
    ['movement_state', scenario.movement_state, relationship.biological_state_gates.movement_state],
    [
      'reproductive_state',
      scenario.individual_reproductive_state,
      relationship.biological_state_gates.reproductive_state,
    ],
    ['season', scenario.season, relationship.biological_state_gates.seasons],
    ['diel_period', scenario.diel_period, relationship.biological_state_gates.diel_periods],
    [
      'regional_reproductive_context',
      scenario.regional_reproductive_context,
      relationship.biological_state_gates.regional_reproductive_context,
    ],
  ]

  for (const [dimension, actual, allowed] of checks) {
    if (!allowed?.length || !knownDimension(actual)) continue
    if (!(allowed as readonly string[]).includes(actual)) {
      mismatches.push({ dimension, actual, allowed: [...allowed] })
    }
  }

  const annotation = relationship.biological_state_annotation
  if (annotation?.state_codes?.length) {
    const actual = String(scenario.state_code || '').toUpperCase()
    if (!annotation.state_codes.includes(actual)) {
      mismatches.push({
        dimension: 'state_code',
        actual,
        allowed: [...annotation.state_codes],
      })
    }
  }
  if (annotation?.sex?.length && knownDimension(scenario.sex)) {
    if (!annotation.sex.includes(scenario.sex)) {
      mismatches.push({
        dimension: 'sex',
        actual: scenario.sex,
        allowed: [...annotation.sex],
      })
    }
  }
  if (annotation?.require_known_age && !knownDimension(scenario.age_class)) {
    if (!missing.includes('age_class')) missing.push('age_class')
  }
  if (
    annotation?.regional_reproductive_context?.length &&
    knownDimension(scenario.regional_reproductive_context) &&
    !annotation.regional_reproductive_context.includes(
      scenario.regional_reproductive_context,
    )
  ) {
    mismatches.push({
      dimension: 'regional_reproductive_context',
      actual: scenario.regional_reproductive_context,
      allowed: [...annotation.regional_reproductive_context],
    })
  }

  return {
    status: mismatches.length
      ? 'not_applicable'
      : missing.length
        ? 'insufficient_input'
        : 'pass',
    missing_dimensions: [...new Set(missing)].sort(),
    mismatches,
  }
}

function evidenceForProduct(
  evidence: readonly FarmWatchDeerEvaluatorEvidence[],
  productKey: DeerRelationshipProductKey,
) {
  return evidence.filter((row) => row.product_key === productKey)
}

function evaluateInputs(
  relationship: DeerRelationshipRecord,
  evidence: readonly FarmWatchDeerEvaluatorEvidence[],
) {
  const selected = new Map<string, FarmWatchDeerEvaluatorEvidence[]>()
  const rows: InputEvaluation[] = relationship.required_inputs.map((requirement) => {
    const offered = requirement.product_keys.flatMap((productKey) =>
      evidenceForProduct(evidence, productKey)
    )
    const matches = offered.filter((candidate) =>
      requirement.allowed_evidence_states.includes(candidate.evidence_state) &&
      candidate.scales.some((scale) => requirement.allowed_scales.includes(scale))
    )

    const satisfied = requirement.match === 'all'
      ? requirement.product_keys.every((productKey) =>
          matches.some((candidate) => candidate.product_key === productKey)
        )
      : matches.length > 0

    selected.set(requirement.key, satisfied ? matches : [])

    return {
      key: requirement.key,
      status: satisfied ? 'satisfied' : 'missing_or_incompatible',
      match: requirement.match,
      freshness_policy: requirement.freshness_policy,
      allowed_product_keys: [...requirement.product_keys],
      allowed_evidence_states: [...requirement.allowed_evidence_states],
      allowed_scales: [...requirement.allowed_scales],
      matched: matches.map((candidate) => ({
        product_key: candidate.product_key,
        evidence_state: candidate.evidence_state,
        scales: [...candidate.scales],
        evidence_class: candidate.evidence_class,
        source_status: candidate.source_status,
        identity_sha256: candidate.identity_sha256,
        as_of: candidate.as_of,
      })),
      offered: offered.map((candidate) => ({
        product_key: candidate.product_key,
        evidence_state: candidate.evidence_state,
        scales: [...candidate.scales],
        source_status: candidate.source_status,
        as_of: candidate.as_of,
      })),
    }
  })

  return { rows, selected }
}

function candidateValues(
  rows: readonly FarmWatchDeerEvaluatorEvidence[],
  field: string,
) {
  const values: unknown[] = []
  for (const row of rows) {
    const value = row.values?.[field]
    if (Array.isArray(value)) values.push(...value)
    else if (value !== undefined) values.push(value)
  }
  return values
}

function comparable(value: unknown) {
  if (typeof value === 'string') return value
  if (typeof value === 'number' || typeof value === 'boolean') return String(value)
  return null
}

function evaluateConstraints(
  relationship: DeerRelationshipRecord,
  selected: ReadonlyMap<string, FarmWatchDeerEvaluatorEvidence[]>,
): ConstraintEvaluation[] {
  return relationship.value_constraints.map((constraint) => {
    const rows = selected.get(constraint.binding_key) || []
    const observed = candidateValues(rows, constraint.field)
    const comparableValues = observed
      .map(comparable)
      .filter((value): value is string => value != null)

    let status: ConstraintEvaluation['status'] = 'unresolved'
    if (constraint.operator === 'known') {
      status = comparableValues.some(knownDimension) ? 'satisfied' : 'unresolved'
    } else if (constraint.operator === 'equals' || constraint.operator === 'one_of') {
      if (comparableValues.length) {
        status = comparableValues.some((value) => constraint.values.includes(value))
          ? 'satisfied'
          : 'failed'
      }
    } else if (constraint.operator === 'study_specific') {
      status = 'unresolved'
    }

    return {
      id: constraint.id,
      binding_key: constraint.binding_key,
      field: constraint.field,
      operator: constraint.operator,
      values: [...constraint.values],
      status,
      observed_values: observed,
      rationale: constraint.rationale,
    }
  })
}

function measurementRelationshipUse(
  activationRequirement: 'required' | 'context_only' | 'not_applicable',
  fidelityClass: DeerEvidenceFidelityClass,
): DeerMeasurementRelationshipUse {
  if (activationRequirement === 'not_applicable') return 'not_applicable'
  if (activationRequirement === 'context_only') return 'context_only'
  if (fidelityClass === 'mechanism_only' || fidelityClass === 'unavailable') {
    return 'blocks_relationship'
  }
  return 'supports_activation'
}

function measurementProxyInflationGuard(
  fidelityClass: DeerEvidenceFidelityClass,
  activationRequirement: 'required' | 'context_only' | 'not_applicable',
) {
  if (activationRequirement === 'not_applicable') {
    return 'This source-study variable is not part of relationship activation.'
  }
  switch (fidelityClass) {
    case 'exact':
      return 'The Farm Watch variable is measurement-equivalent for the permitted use, subject to current evidence availability and scale.'
    case 'study_aligned_derivative':
      return 'The Farm Watch variable is a study-aligned deterministic derivative, not a field observation or proof of deer response.'
    case 'calibrated_proxy':
      return 'The Farm Watch variable is a calibrated proxy; preserve the stated calibration and transfer limits and do not relabel it as exact.'
    case 'mechanism_only':
      return 'The available variable can explain physical mechanism/context only and cannot substitute for the source-study measurement in relationship activation.'
    case 'unavailable':
      return 'No authorized Farm Watch substitute exists for this source-study variable; the relationship must abstain when the variable is required.'
  }
}

function evaluateMeasurementFidelityMatrix(
  relationship: DeerRelationshipRecord,
  inputs: readonly InputEvaluation[],
): DeerMeasurementFidelityMatrixRow[] {
  const inputByKey = new Map(inputs.map((input) => [input.key, input]))
  return relationship.study_measurements.map((measurement) => {
    const fidelityClass = deerMeasurementEvidenceFidelityClass(measurement.alignment)
    const relationshipUse = measurementRelationshipUse(
      measurement.activation_requirement,
      fidelityClass,
    )
    const input = measurement.binding_key
      ? inputByKey.get(measurement.binding_key)
      : null

    let currentBindingStatus: DeerMeasurementCurrentBindingStatus = 'not_bound'
    if (measurement.activation_requirement === 'not_applicable') {
      currentBindingStatus = 'not_applicable'
    } else if (input) {
      currentBindingStatus = input.status
    }

    return {
      measurement_id: measurement.id,
      study_variable: measurement.study_variable,
      study_protocol: measurement.study_protocol,
      binding_key: measurement.binding_key,
      activation_requirement: measurement.activation_requirement,
      registry_alignment: measurement.alignment,
      fidelity_class: fidelityClass,
      relationship_use: relationshipUse,
      current_binding_status: currentBindingStatus,
      permitted_use: measurement.permitted_use,
      limitations: [...measurement.limitations],
      accepted_products: input ? [...input.allowed_product_keys] : [],
      accepted_evidence_states: input ? [...input.allowed_evidence_states] : [],
      accepted_scales: input ? [...input.allowed_scales] : [],
      matched_evidence: input ? input.matched.map((row) => ({
        ...row,
        scales: [...row.scales],
      })) : [],
      proxy_inflation_guard: measurementProxyInflationGuard(
        fidelityClass,
        measurement.activation_requirement,
      ),
    }
  })
}

function activeDecisionRelevance(relationship: DeerRelationshipRecord): {
  decision_relevance: FarmWatchDeerDecisionRelevance
  decision_actionable: boolean
} {
  if (
    relationship.output_kind === 'quantitative_relative_selection' ||
    relationship.output_kind === 'ordinal_directional'
  ) {
    return {
      decision_relevance: 'directional_relationship_context',
      decision_actionable: false,
    }
  }
  if (relationship.output_kind === 'mechanism_context') {
    return {
      decision_relevance: 'mechanism_context',
      decision_actionable: false,
    }
  }
  if (relationship.output_kind === 'negative_constraint') {
    return {
      decision_relevance: 'negative_constraint',
      decision_actionable: false,
    }
  }
  return {
    decision_relevance: 'abstained',
    decision_actionable: false,
  }
}

function initialPropertyDirectionalEvidence(
  relationship: DeerRelationshipRecord,
): PropertyDirectionalEvidenceEvaluation {
  const directionalOutput =
    relationship.output_kind === 'quantitative_relative_selection' ||
    relationship.output_kind === 'ordinal_directional'

  if (!directionalOutput) {
    return {
      status: 'not_applicable',
      evaluated: false,
      reason_codes: ['relationship_output_not_directional'],
      interpretation_boundary:
        'This relationship output is not a property-specific directional inference.',
    }
  }

  if (!relationship.property_conditioning) {
    return {
      status: 'not_configured',
      evaluated: false,
      reason_codes: ['property_conditioning_not_configured'],
      interpretation_boundary:
        'The relationship is directionally supported by literature, but no explicit property-conditioning rule is authorized for this relationship.',
    }
  }

  return {
    status: 'insufficient_measurement',
    evaluated: false,
    reason_codes: ['property_covariate_not_evaluated'],
    conditioning_rule_id: relationship.property_conditioning.id,
    metric_label: relationship.property_conditioning.metric_label,
    support_geometry: relationship.property_conditioning.support_geometry,
    limitations: [...relationship.property_conditioning.limitations],
    interpretation_boundary:
      'A property-conditioning rule exists, but the relationship must first pass registry/scenario gates and expose the configured property covariate.',
  }
}

function numericScaleValues(
  rows: readonly FarmWatchDeerEvaluatorEvidence[],
  field: string,
  orderedScales: readonly DeerRelationshipScale[],
) {
  const observations: PropertyDirectionalObservation[] = []
  for (const row of rows) {
    const value = row.values?.[field]
    if (!value || typeof value !== 'object' || Array.isArray(value)) continue
    const record = value as Record<string, unknown>
    for (const scale of orderedScales) {
      if (!row.scales.includes(scale)) continue
      const raw = record[scale]
      if (typeof raw !== 'number' || !Number.isFinite(raw)) continue
      observations.push({
        scale,
        value: raw,
        unit: 'percent',
      })
    }
  }

  const byScale = new Map<DeerRelationshipScale, PropertyDirectionalObservation>()
  for (const observation of observations) {
    if (!byScale.has(observation.scale)) byScale.set(observation.scale, observation)
  }
  return orderedScales
    .map((scale) => byScale.get(scale))
    .filter((row): row is PropertyDirectionalObservation => Boolean(row))
}

function evaluatePropertyDirectionalEvidence(
  relationship: DeerRelationshipRecord,
  selected: ReadonlyMap<string, FarmWatchDeerEvaluatorEvidence[]>,
): PropertyDirectionalEvidenceEvaluation {
  const base = initialPropertyDirectionalEvidence(relationship)
  const rule = relationship.property_conditioning
  if (!rule) return base

  const rows = selected.get(rule.binding_key) || []
  const observations = numericScaleValues(rows, rule.metric_field, rule.ordered_scales)
  if (observations.length < 2) {
    return {
      ...base,
      status: 'insufficient_measurement',
      evaluated: true,
      reason_codes: ['property_covariate_contrast_unavailable'],
      observations,
      contrast: null,
      hypothesis: null,
      interpretation_boundary:
        'The configured property covariate was checked, but fewer than two explicit spatial scales carried numeric values, so no within-property contrast is emitted.',
    }
  }

  let lower = observations[0]
  let higher = observations[0]
  for (const observation of observations.slice(1)) {
    if (observation.value < lower.value) lower = observation
    if (observation.value > higher.value) higher = observation
  }

  const difference = higher.value - lower.value
  if (!(difference > 0)) {
    return {
      ...base,
      status: 'measured_no_contrast',
      evaluated: true,
      reason_codes: ['property_covariate_no_ordered_contrast'],
      observations,
      contrast: {
        lower_scale: lower.scale,
        lower_value: lower.value,
        higher_scale: higher.scale,
        higher_value: higher.value,
        absolute_difference: 0,
        unit: rule.unit,
      },
      hypothesis: null,
      interpretation_boundary:
        'The configured property covariate was measured across explicit scales, but no non-zero contrast was present. No property-conditioned directional hypothesis is emitted.',
    }
  }

  return {
    status: 'hypothesis_available',
    evaluated: true,
    reason_codes: ['property_covariate_contrast_measured'],
    conditioning_rule_id: rule.id,
    metric_label: rule.metric_label,
    support_geometry: rule.support_geometry,
    observations,
    contrast: {
      lower_scale: lower.scale,
      lower_value: lower.value,
      higher_scale: higher.scale,
      higher_value: higher.value,
      absolute_difference: difference,
      unit: rule.unit,
    },
    hypothesis: {
      source_response_variable: relationship.response_variable,
      source_relationship_direction: relationship.direction,
      higher_covariate_scale: higher.scale,
      higher_covariate_value: higher.value,
      lower_covariate_scale: lower.scale,
      lower_covariate_value: lower.value,
      interpretation: rule.hypothesis_interpretation,
      behavioral_response_inferred: false,
      coefficient_transfer_performed: false,
    },
    limitations: [...rule.limitations],
    interpretation_boundary:
      'This is a property-conditioned covariate hypothesis anchored to measured Farm Watch values. It does not establish deer use, dispersal, behavioral probability, or a transferable effect magnitude.',
  }
}

function activeResult(
  relationship: DeerRelationshipRecord,
  fidelity: ReturnType<typeof deerRelationshipStudyFidelityStatus>,
) {
  return {
    output_kind: relationship.output_kind,
    direction: relationship.direction,
    relationship_form: relationship.relationship_form,
    supported_nonlinearity: relationship.supported_nonlinearity,
    fidelity_scope: fidelity.status,
    coefficient_transfer: {
      status: relationship.coefficient_transfer.status,
      numeric_parameters: [...relationship.coefficient_transfer.numeric_parameters],
    },
  }
}

export function evaluateDeerRelationship(args: {
  relationship: DeerRelationshipRecord
  scenario: FarmWatchDeerScienceScenario
  evidence: readonly FarmWatchDeerEvaluatorEvidence[]
}) {
  const { relationship, scenario, evidence } = args
  const fidelity = deerRelationshipStudyFidelityStatus(relationship)
  const gate = evaluateBiologicalGate(relationship, scenario)
  const inputEvaluation = evaluateInputs(relationship, evidence)
  const constraints = evaluateConstraints(relationship, inputEvaluation.selected)
  const abstainedDecision = {
    decision_relevance: 'abstained' as const,
    decision_actionable: false,
  }

  const base = {
    relationship_id: relationship.relationship_id,
    ledger_ids: [...relationship.ledger_ids],
    title: relationship.title,
    module_family: relationship.module_family,
    response_variable: relationship.response_variable,
    output_kind: relationship.output_kind,
    direction: relationship.direction,
    spatial_scale: {
      relationship_scales: [...relationship.spatial_scale.relationship_scales],
      notes: relationship.spatial_scale.notes,
    },
    temporal_scale: relationship.temporal_scale,
    relationship_form: relationship.relationship_form,
    source_citations: [...relationship.source_citations],
    coefficient_transfer: {
      status: relationship.coefficient_transfer.status,
      numeric_parameters: [...relationship.coefficient_transfer.numeric_parameters],
    },
    fidelity,
    measurement_fidelity_matrix: evaluateMeasurementFidelityMatrix(
      relationship,
      inputEvaluation.rows,
    ),
    property_directional_evidence: initialPropertyDirectionalEvidence(relationship),
    biological_gate: {
      ...gate,
      required_explicit_dimensions: [
        ...relationship.biological_state_gates.required_explicit_dimensions,
      ],
      allowed: {
        sex: relationship.biological_state_gates.sex,
        age_class: relationship.biological_state_gates.age_class,
        movement_state: relationship.biological_state_gates.movement_state,
        reproductive_state: relationship.biological_state_gates.reproductive_state,
        seasons: relationship.biological_state_gates.seasons,
        diel_periods: relationship.biological_state_gates.diel_periods,
        regional_reproductive_context:
          relationship.biological_state_gates.regional_reproductive_context,
      },
    },
    inputs: inputEvaluation.rows,
    value_constraints: constraints,
    limitations: [...relationship.limitations],
    null_or_blocked_conditions: [...relationship.null_or_blocked_conditions],
    blocked_universal_assumptions: [...relationship.blocked_universal_assumptions],
  }

  if (relationship.output_kind === 'not_applicable') {
    return {
      ...base,
      status: 'not_applicable' as const,
      ...abstainedDecision,
      reason_codes: ['registry_not_applicable'],
      result: null,
    }
  }

  if (gate.status === 'not_applicable') {
    return {
      ...base,
      status: 'not_applicable' as const,
      ...abstainedDecision,
      reason_codes: ['biological_gate_mismatch'],
      result: null,
    }
  }
  if (gate.status === 'insufficient_input') {
    return {
      ...base,
      status: 'insufficient_input' as const,
      ...abstainedDecision,
      reason_codes: ['biological_state_unknown'],
      result: null,
    }
  }

  if (fidelity.status === 'blocked_measurement_alignment') {
    return {
      ...base,
      status: 'blocked_measurement_alignment' as const,
      ...abstainedDecision,
      reason_codes: ['required_measurement_alignment_blocked'],
      result: null,
    }
  }
  if (
    fidelity.status === 'context_only' &&
    relationship.output_kind !== 'mechanism_context' &&
    relationship.output_kind !== 'negative_constraint'
  ) {
    return {
      ...base,
      status: 'blocked_measurement_alignment' as const,
      ...abstainedDecision,
      reason_codes: ['context_only_measurement_cannot_emit_requested_output_kind'],
      result: null,
    }
  }

  const unsatisfiedInputs = inputEvaluation.rows.filter(
    (row) => row.status !== 'satisfied',
  )
  if (unsatisfiedInputs.length) {
    return {
      ...base,
      status: 'insufficient_input' as const,
      ...abstainedDecision,
      reason_codes: ['required_product_input_unavailable'],
      result: null,
    }
  }

  const failedConstraints = constraints.filter((row) => row.status === 'failed')
  if (failedConstraints.length) {
    return {
      ...base,
      status: 'not_applicable' as const,
      ...abstainedDecision,
      reason_codes: ['value_constraint_not_satisfied'],
      result: null,
    }
  }
  const unresolvedConstraints = constraints.filter(
    (row) => row.status === 'unresolved',
  )
  if (unresolvedConstraints.length) {
    return {
      ...base,
      status: 'insufficient_input' as const,
      ...abstainedDecision,
      reason_codes: ['value_constraint_unresolved'],
      result: null,
    }
  }

  return {
    ...base,
    status: 'active' as const,
    ...activeDecisionRelevance(relationship),
    property_directional_evidence: evaluatePropertyDirectionalEvidence(
      relationship,
      inputEvaluation.selected,
    ),
    reason_codes: [],
    result: activeResult(relationship, fidelity),
  }
}

function moduleStatus(
  rows: Array<ReturnType<typeof evaluateDeerRelationship>>,
): FarmWatchDeerScienceRelationshipStatus {
  if (rows.some((row) => row.status === 'active')) return 'active'
  if (rows.some((row) => row.status === 'insufficient_input')) {
    return 'insufficient_input'
  }
  if (rows.some((row) => row.status === 'blocked_measurement_alignment')) {
    return 'blocked_measurement_alignment'
  }
  return 'not_applicable'
}

export function evaluateDeerScienceContext(args: {
  scenario: FarmWatchDeerScienceScenario
  evidence: readonly FarmWatchDeerEvaluatorEvidence[]
  relationships?: readonly DeerRelationshipRecord[]
}) {
  const relationships = args.relationships || FARM_WATCH_DEER_RELATIONSHIPS
  const evaluations = relationships.map((relationship) =>
    evaluateDeerRelationship({
      relationship,
      scenario: args.scenario,
      evidence: args.evidence,
    })
  )

  const families = [...new Set(evaluations.map((row) => row.module_family))].sort()
  const modules = families.map((family) => {
    const rows = evaluations.filter((row) => row.module_family === family)
    return {
      module_family: family,
      status: moduleStatus(rows),
      active_relationship_ids: rows
        .filter((row) => row.status === 'active')
        .map((row) => row.relationship_id),
      insufficient_relationship_ids: rows
        .filter((row) => row.status === 'insufficient_input')
        .map((row) => row.relationship_id),
      blocked_relationship_ids: rows
        .filter((row) => row.status === 'blocked_measurement_alignment')
        .map((row) => row.relationship_id),
      not_applicable_relationship_ids: rows
        .filter((row) => row.status === 'not_applicable')
        .map((row) => row.relationship_id),
    }
  })

  const counts = FARM_WATCH_DEER_SCIENCE_CONTEXT_PRODUCT.statusVocabulary
    .reduce((out, status) => {
      out[status] = evaluations.filter((row) => row.status === status).length
      return out
    }, {} as Record<FarmWatchDeerScienceRelationshipStatus, number>)

  const decision_relevance_counts = FARM_WATCH_DEER_DECISION_RELEVANCE
    .reduce((out, relevance) => {
      out[relevance] = evaluations.filter(
        (row) => row.decision_relevance === relevance,
      ).length
      return out
    }, {} as Record<FarmWatchDeerDecisionRelevance, number>)

  const decision_actionable_relationship_ids = evaluations
    .filter((row) => row.decision_actionable)
    .map((row) => row.relationship_id)

  const directional_relationship_context_ids = evaluations
    .filter((row) => row.decision_relevance === 'directional_relationship_context')
    .map((row) => row.relationship_id)

  const property_directional_evidence_relationship_ids = evaluations
    .filter((row) => row.property_directional_evidence.evaluated)
    .map((row) => row.relationship_id)

  const property_conditioned_hypothesis_relationship_ids = evaluations
    .filter((row) =>
      row.property_directional_evidence.status === 'hypothesis_available'
    )
    .map((row) => row.relationship_id)

  const measurement_fidelity_rows = evaluations.flatMap(
    (row) => row.measurement_fidelity_matrix,
  )
  const measurement_fidelity_counts = [
    'exact',
    'study_aligned_derivative',
    'calibrated_proxy',
    'mechanism_only',
    'unavailable',
  ].reduce((out, fidelityClass) => {
    out[fidelityClass] = measurement_fidelity_rows.filter(
      (row) => row.fidelity_class === fidelityClass,
    ).length
    return out
  }, {} as Record<string, number>)
  const measurement_binding_counts = [
    'satisfied',
    'missing_or_incompatible',
    'not_bound',
    'not_applicable',
  ].reduce((out, status) => {
    out[status] = measurement_fidelity_rows.filter(
      (row) => row.current_binding_status === status,
    ).length
    return out
  }, {} as Record<string, number>)

  return {
    schema: FARM_WATCH_DEER_SCIENCE_CONTEXT_PRODUCT.outputSchemaVersion,
    method: FARM_WATCH_DEER_SCIENCE_CONTEXT_PRODUCT.algorithmVersion,
    species: FARM_WATCH_DEER_SCIENCE_CONTEXT_PRODUCT.species,
    property: {
      slug: args.scenario.property_slug,
      state_code: args.scenario.state_code,
    },
    at: args.scenario.at,
    scenario: {
      sex: args.scenario.sex,
      age_class: args.scenario.age_class,
      movement_state: args.scenario.movement_state,
      individual_reproductive_state: args.scenario.individual_reproductive_state,
      season: args.scenario.season,
      diel_period: args.scenario.diel_period,
      regional_reproductive_context: args.scenario.regional_reproductive_context,
    },
    status: counts.active > 0 ? 'available' : 'abstained',
    counts,
    decision_relevance_counts,
    decision_actionable_relationship_count:
      decision_actionable_relationship_ids.length,
    decision_actionable_relationship_ids,
    directional_relationship_context_count:
      directional_relationship_context_ids.length,
    directional_relationship_context_ids,
    property_directional_evidence_evaluated:
      property_directional_evidence_relationship_ids.length > 0,
    property_directional_evidence_relationship_count:
      property_directional_evidence_relationship_ids.length,
    property_directional_evidence_relationship_ids,
    property_conditioned_hypothesis_count:
      property_conditioned_hypothesis_relationship_ids.length,
    property_conditioned_hypothesis_relationship_ids,
    measurement_fidelity_matrix_row_count: measurement_fidelity_rows.length,
    measurement_fidelity_counts,
    measurement_binding_counts,
    evaluator_active_relationship_ids: evaluations
      .filter((row) => row.status === 'active')
      .map((row) => row.relationship_id),
    modules,
    relationships: evaluations,
    scoring_performed: false,
    coefficient_synthesis_performed: false,
    behavioral_probability_inferred: false,
    interpretation_boundary:
      'Registry-driven property/date/scenario applicability plus explicitly authorized property-conditioning only. Every source-study variable is exposed through a measurement-fidelity matrix that keeps exact measurements, study-aligned derivatives, calibrated proxies, mechanism-only context, and unavailable variables distinct. An active quantitative or ordinal relationship is literature-supported directional context. A property-conditioned hypothesis is emitted only when the registry declares a conditioning rule and the configured property covariate has a measured multi-scale contrast. Such a hypothesis remains non-actionable and does not infer deer use, dispersal, behavioral probability, or effect magnitude. Mechanism context and negative constraints remain separate. Outputs are not combined into a universal deer score or probability, and numeric coefficients are emitted only if separately authorized by the relationship registry.',
  }
}

const VALID_EVIDENCE_STATES = new Set<DeerRelationshipEvidenceState>([
  'available',
  'known',
  'proxy',
  'accepted',
  'candidate_only',
  'stale',
  'unavailable',
  'blocked',
  'abstained',
])

function explicitEvidenceState(value: any): DeerRelationshipEvidenceState | null {
  for (const candidate of [
    value?.evidence_state,
    value?.context?.evidence_state,
    value?.context?.state,
  ]) {
    if (VALID_EVIDENCE_STATES.has(candidate)) return candidate
  }
  return null
}

function statusEvidenceState(value: any): DeerRelationshipEvidenceState {
  const explicit = explicitEvidenceState(value)
  if (explicit) return explicit
  const status = String(value?.status || '')
  if (status === 'available') return 'available'
  if (status === 'known') return 'known'
  if (status === 'proxy') return 'proxy'
  if (status === 'stale') return 'stale'
  if (status === 'inactive' && value?.context?.applicability_state === 'not_applicable') {
    return 'known'
  }
  return 'unavailable'
}

function identitySha(value: any) {
  return value?.identity_sha256 ||
    value?.identity?.identity_sha256 ||
    value?.context?.identity_sha256 ||
    null
}

function evidenceClass(value: any) {
  return value?.evidence_class ||
    value?.context?.evidence_class ||
    null
}

function productScales(productKey: DeerRelationshipProductKey) {
  return [...FARM_WATCH_DEER_INPUT_PRODUCT_CATALOG[productKey].scales] as DeerRelationshipScale[]
}

function addEvidence(
  out: FarmWatchDeerEvaluatorEvidence[],
  productKey: DeerRelationshipProductKey,
  source: any,
  options: {
    evidence_state?: DeerRelationshipEvidenceState
    scales?: DeerRelationshipScale[]
    values?: Record<string, unknown>
    as_of?: string | null
  } = {},
) {
  out.push({
    product_key: productKey,
    evidence_state: options.evidence_state || statusEvidenceState(source),
    scales: options.scales || productScales(productKey),
    values: options.values || {},
    evidence_class: evidenceClass(source),
    source_status: source?.status || null,
    identity_sha256: identitySha(source),
    as_of: options.as_of || source?.as_of_date || source?.as_of_at || null,
  })
}

function fieldScopes(fieldPhenology: any) {
  const fields = fieldPhenology?.context?.fields
  const values = Array.isArray(fields)
    ? fields.flatMap((field: any) => Array.isArray(field?.scopes) ? field.scopes : [])
    : []
  const known = [...new Set(values)]
    .filter((value): value is DeerRelationshipScale =>
      [
        'field',
        'property',
        'local_500m',
        'landscape_1500m',
        'broad_3000m',
      ].includes(String(value))
    )
  return known.length ? known : productScales('field-phenology-context')
}

function fieldPhenologyStates(fieldPhenology: any) {
  const fields = Array.isArray(fieldPhenology?.context?.fields)
    ? fieldPhenology.context.fields
    : []
  return fields
    .map((field: any) => field?.phenology_state)
    .filter((value: unknown) => knownDimension(String(value || '')))
}

function currentCropNames(fieldPhenology: any) {
  const fields = Array.isArray(fieldPhenology?.context?.fields)
    ? fieldPhenology.context.fields
    : []
  const accepted = fields.filter((field: any) =>
    field?.crop_identity?.state === 'accepted'
  )
  return accepted
    .map((field: any) => field?.crop_identity?.crop_name)
    .filter((value: unknown) => typeof value === 'string' && value.length)
}

function annualMastEvidenceState(mast: any): DeerRelationshipEvidenceState {
  const annual = mast?.context?.annual_mast_proxy
  if (!annual) return 'unavailable'
  if (annual?.status === 'available' || annual?.status === 'known') return 'proxy'
  if (annual?.status === 'stale') return 'stale'
  return 'unavailable'
}

function seasonalPrecipitationState(seasonal: any): DeerRelationshipEvidenceState {
  const state = seasonal?.context?.component_states?.precipitation
  return VALID_EVIDENCE_STATES.has(state) ? state : statusEvidenceState(seasonal)
}

function surfaceWaterPresence(value: any) {
  return value?.context?.current_presence_state ||
    value?.context?.observation_state ||
    value?.current_presence_state ||
    null
}

function agricultureScaleMetrics(landscapeContext: any) {
  if (landscapeContext?.status !== 'available') {
    return {
      scales: [] as DeerRelationshipScale[],
      fractionByScale: {} as Record<string, number>,
      fieldAreaByScale: {} as Record<string, number>,
      domainAreaByScale: {} as Record<string, number>,
      fieldCountByScale: {} as Record<string, number>,
    }
  }

  const zones = Array.isArray(landscapeContext?.agriculture?.field_context_by_zone)
    ? landscapeContext.agriculture.field_context_by_zone
    : []
  const areas = landscapeContext?.domain?.areas_acres || {}
  const scaleByRadius: Record<string, DeerRelationshipScale> = {
    '500': 'local_500m',
    '1500': 'landscape_1500m',
    '3000': 'broad_3000m',
  }
  const fractionByScale: Record<string, number> = {}
  const fieldAreaByScale: Record<string, number> = {}
  const domainAreaByScale: Record<string, number> = {}
  const fieldCountByScale: Record<string, number> = {}

  for (const zone of zones) {
    const radius = String(Number(zone?.radius_m))
    const scale = scaleByRadius[radius]
    const fieldArea = Number(zone?.intersected_field_acres)
    const domainArea = Number(areas?.[radius])
    if (!scale || !Number.isFinite(fieldArea) || !Number.isFinite(domainArea) || !(domainArea > 0)) {
      continue
    }
    fractionByScale[scale] = fieldArea / domainArea * 100
    fieldAreaByScale[scale] = fieldArea
    domainAreaByScale[scale] = domainArea
    const count = Number(zone?.field_count)
    if (Number.isFinite(count)) fieldCountByScale[scale] = count
  }

  const scales = Object.keys(fractionByScale)
    .filter((scale): scale is DeerRelationshipScale =>
      ['local_500m','landscape_1500m','broad_3000m'].includes(scale)
    )

  return {
    scales,
    fractionByScale,
    fieldAreaByScale,
    domainAreaByScale,
    fieldCountByScale,
  }
}

export function buildDeerEvaluatorEvidenceFromFarmWatch(args: {
  scenario: FarmWatchDeerScienceScenario
  deer_context: any
  deer_evidence_stack: any
  managed_food_feature_context?: any
  managed_water_source_context?: any
  hydrology?: any
  landscape_context?: any
  road_focal_context?: any
}) {
  const out: FarmWatchDeerEvaluatorEvidence[] = []
  const stack = args.deer_evidence_stack || {}
  const products = stack.products || {}
  const deerContext = args.deer_context || {}
  const biological = deerContext.deer_biological_state || {}
  const diel = deerContext.diel_photoperiod || {}
  const seasonal = deerContext.seasonal_state || {}
  const phenology = deerContext.field_phenology || {}

  addEvidence(out, 'deer-biological-state', biological, {
    evidence_state: biological?.status === 'available' ? 'available' : 'unavailable',
    scales: ['individual_scenario', 'statewide'],
    values: {
      sex: args.scenario.sex,
      age_class: args.scenario.age_class,
      movement_state: args.scenario.movement_state,
      reproductive_state: args.scenario.individual_reproductive_state,
      season: args.scenario.season,
      diel_period: args.scenario.diel_period,
      regional_reproductive_context: args.scenario.regional_reproductive_context,
      state_code: args.scenario.state_code,
    },
    as_of: args.scenario.at,
  })

  addEvidence(out, 'diel-photoperiod-context', diel, {
    evidence_state: diel?.status === 'available' ? 'available' : 'unavailable',
    scales: ['property'],
    values: {
      solar_phase: args.scenario.diel_period,
    },
    as_of: args.scenario.at,
  })

  addEvidence(out, 'seasonal-state', seasonal, {
    evidence_state: seasonalPrecipitationState(seasonal),
    values: {
      precipitation_state: seasonal?.context?.component_states?.precipitation,
      precipitation: seasonal?.context?.components?.precipitation || null,
    },
  })

  const phenologyStates = fieldPhenologyStates(phenology)
  addEvidence(out, 'field-phenology-context', phenology, {
    evidence_state: phenology?.status === 'available' ? 'known' : 'unavailable',
    scales: fieldScopes(phenology),
    values: {
      phenology_state: phenologyStates,
    },
  })

  const fields = Array.isArray(phenology?.context?.fields)
    ? phenology.context.fields
    : []
  const landscape = args.landscape_context || {}
  const agricultureMetrics = agricultureScaleMetrics(landscape)
  const agricultureSource = agricultureMetrics.scales.length ? landscape : phenology
  addEvidence(out, 'agriculture-landcover-context', agricultureSource, {
    evidence_state:
      agricultureMetrics.scales.length || fields.length ? 'known' : 'unavailable',
    scales: agricultureMetrics.scales.length
      ? agricultureMetrics.scales
      : fieldScopes(phenology),
    values: {
      mapped_field_count: fields.length,
      mapped_agriculture_fraction_percent_by_scale:
        agricultureMetrics.fractionByScale,
      mapped_agriculture_area_acres_by_scale:
        agricultureMetrics.fieldAreaByScale,
      landscape_domain_area_acres_by_scale:
        agricultureMetrics.domainAreaByScale,
      mapped_field_count_by_scale:
        agricultureMetrics.fieldCountByScale,
      support_geometry:
        agricultureMetrics.scales.length
          ? 'barrier-aware fixed-radius landscape domains'
          : null,
    },
  })

  const acceptedCropNames = currentCropNames(phenology)
  addEvidence(out, 'current-crop-identity', phenology, {
    evidence_state: acceptedCropNames.length ? 'accepted' : 'unavailable',
    scales: fieldScopes(phenology),
    values: {
      crop_name: acceptedCropNames,
    },
  })

  for (const productKey of [
    'thermal-exposure-context',
    'terrain-form-permeability',
    'lidar-physical-structure',
    'study-aligned-vegetation-height-context',
    'spatial-edge-patch-context',
    'horizontal-visibility-context',
    'mast-capacity',
  ] as const) {
    addEvidence(out, productKey, products[productKey] || { status: 'unavailable' })
  }

  const mast = stack.mast_resource_context
  addEvidence(out, 'annual-mast-state', mast || { status: 'unavailable' }, {
    evidence_state: annualMastEvidenceState(mast),
    values: {
      annual_mast_proxy_status: mast?.context?.annual_mast_proxy?.status || 'unavailable',
      annual_mast_proxy: mast?.context?.annual_mast_proxy || null,
    },
  })

  for (const [productKey, sourceKey] of [
    ['conifer-cover-context', 'conifer_cover_context'],
    ['forest-type-context', 'forest_type_context'],
    ['human-footprint-context', 'human_footprint_context'],
    ['multiscale-cover-context', 'multiscale_cover_context'],
    ['multiscale-forest-context', 'multiscale_forest_context'],
    ['snow-winter-severity-context', 'snow_winter_severity_context'],
  ] as const) {
    addEvidence(
      out,
      productKey,
      stack[sourceKey] || { status: 'unavailable' },
    )
  }

  const extreme = stack.extreme_weather_event_context
  addEvidence(out, 'extreme-weather-event-context', extreme || { status: 'unavailable' }, {
    values: {
      applicability_state: extreme?.context?.applicability_state || null,
      event_active: extreme?.context?.event_active ?? null,
    },
  })

  const surfaceWater = stack.surface_water_state
  addEvidence(out, 'surface-water-state', surfaceWater || { status: 'unavailable' }, {
    values: {
      current_presence_state: surfaceWaterPresence(surfaceWater),
    },
  })

  const managedFood = args.managed_food_feature_context || stack.managed_food_feature_context
  addEvidence(out, 'managed-food-feature-context', managedFood || { status: 'unavailable' }, {
    values: {
      inventory_status: managedFood?.inventory_status || 'unknown',
      managed_food_present: managedFood?.managed_food_present ?? null,
      active_feature_count: managedFood?.active_feature_count ?? null,
    },
  })

  const managedWater = args.managed_water_source_context || stack.managed_water_source_context
  addEvidence(out, 'managed-water-source-context', managedWater || { status: 'unavailable' }, {
    values: {
      inventory_status: managedWater?.inventory_status || 'unknown',
      current_presence_state:
        managedWater?.current_presence_state || 'managed_source_state_unknown',
      known_usable_count: managedWater?.known_usable_count ?? null,
    },
  })

  const hydrology = args.hydrology || {}
  addEvidence(out, 'mapped-hydrography-context', hydrology, {
    evidence_state: hydrology?.status === 'available' ? 'available' : 'unavailable',
    values: {
      feature_count: Array.isArray(hydrology?.feature_collection?.features)
        ? hydrology.feature_collection.features.length
        : null,
    },
  })

  addEvidence(out, 'road-focal-context', args.road_focal_context || { status: 'unavailable' })

  const represented = new Set(out.map((row) => row.product_key))
  for (const productKey of Object.keys(FARM_WATCH_DEER_INPUT_PRODUCT_CATALOG) as DeerRelationshipProductKey[]) {
    if (represented.has(productKey)) continue
    addEvidence(out, productKey, { status: 'unavailable' })
  }

  return out
}
