import {
  FARM_WATCH_DEER_BLOCKED_UNIVERSAL_ASSUMPTIONS,
  FARM_WATCH_DEER_LEDGER_IDS,
  FARM_WATCH_DEER_RELATIONSHIPS,
  applicableBiologicalStateLedgerIds,
  getDeerRelationship,
  relationshipsForLedgerId,
  validateDeerRelationshipRecord,
  validateDeerRelationshipRegistry,
  validateRelationshipModuleDefinition,
} from './farm-watch-deer-relationship-registry.ts'

function assert(condition: unknown, message = 'assertion failed'): asserts condition {
  if (!condition) throw new Error(message)
}

Deno.test('Batch 9 registry validates as a whole', () => {
  assert(validateDeerRelationshipRegistry())
  assert(FARM_WATCH_DEER_RELATIONSHIPS.length >= 23)
})

Deno.test('every durable deer ledger entry has machine-readable relationship coverage', async () => {
  const ledger = await Deno.readTextFile('docs/FARM_WATCH_DEER_SCIENCE_EVIDENCE_LEDGER.md')
  const documentIds = [...ledger.matchAll(/^## (FW-D\d+)\s+—/gm)]
    .map((match) => match[1])
    .sort()
  assert(documentIds.length >= 23)
  assert(JSON.stringify(documentIds) === JSON.stringify(FARM_WATCH_DEER_LEDGER_IDS))
  for (const ledgerId of documentIds) {
    assert(relationshipsForLedgerId(ledgerId).length > 0, ledgerId + ' is not represented')
  }
})

Deno.test('numeric coefficients are rejected when coefficient transfer is not authorized', () => {
  const relationship = getDeerRelationship('FW-R09-male-breeding-age-movement')
  assert(relationship)
  assert(relationship.coefficient_transfer.status === 'not_supported')
  assert(!validateRelationshipModuleDefinition({
    relationship_id: relationship.relationship_id,
    ledger_ids: relationship.ledger_ids,
    input_bindings: [{
      key: 'biological_state',
      product_key: 'deer-biological-state',
      evidence_state: 'available',
      scale: 'individual_scenario',
    }],
    coefficient_transfer_status: 'not_supported',
    numeric_parameters: [1.25],
  }))
})

Deno.test('relationship records without ledger provenance are rejected', () => {
  const relationship = getDeerRelationship('FW-R01-summer-thermal-resource-tradeoff')
  assert(relationship)
  assert(!validateDeerRelationshipRecord({
    ...relationship,
    relationship_id: 'FW-R99-invalid-no-ledger',
    ledger_ids: [],
  }))
})

Deno.test('conditional biological gates must declare the state dimensions they require', () => {
  const relationship = getDeerRelationship('FW-R09-male-breeding-age-movement')
  assert(relationship)
  assert(!validateDeerRelationshipRecord({
    ...relationship,
    relationship_id: 'FW-R99-invalid-biological-gate',
    biological_state_gates: {
      ...relationship.biological_state_gates,
      required_explicit_dimensions: [],
    },
  }))
})

Deno.test('blocked universal assumptions cannot enter a future relationship module', () => {
  const relationship = getDeerRelationship('FW-R09-male-breeding-age-movement')
  assert(relationship)
  assert(FARM_WATCH_DEER_BLOCKED_UNIVERSAL_ASSUMPTIONS.includes('moon_phase_generic_movement'))
  assert(!validateRelationshipModuleDefinition({
    relationship_id: relationship.relationship_id,
    ledger_ids: relationship.ledger_ids,
    input_bindings: [{
      key: 'biological_state',
      product_key: 'deer-biological-state',
      evidence_state: 'available',
      scale: 'individual_scenario',
    }],
    coefficient_transfer_status: 'not_supported',
    numeric_parameters: [],
    universal_assumption_ids: ['moon_phase_generic_movement'],
  }))
})

Deno.test('stale required inputs are not silently accepted', () => {
  const relationship = getDeerRelationship('FW-R09-male-breeding-age-movement')
  assert(relationship)
  assert(!validateRelationshipModuleDefinition({
    relationship_id: relationship.relationship_id,
    ledger_ids: relationship.ledger_ids,
    input_bindings: [{
      key: 'biological_state',
      product_key: 'deer-biological-state',
      evidence_state: 'stale',
      scale: 'individual_scenario',
    }],
    coefficient_transfer_status: 'not_supported',
    numeric_parameters: [],
  }))
})

Deno.test('input scale mismatch is rejected', () => {
  const relationship = getDeerRelationship('FW-R09-male-breeding-age-movement')
  assert(relationship)
  assert(!validateRelationshipModuleDefinition({
    relationship_id: relationship.relationship_id,
    ledger_ids: relationship.ledger_ids,
    input_bindings: [{
      key: 'biological_state',
      product_key: 'deer-biological-state',
      evidence_state: 'available',
      scale: 'local_500m',
    }],
    coefficient_transfer_status: 'not_supported',
    numeric_parameters: [],
  }))
})

Deno.test('Batch 6 general viewshed is not silently substituted for FW-D04 low concealment', () => {
  const relationships = relationshipsForLedgerId('FW-D04')
  assert(relationships.length === 2)
  for (const relationship of relationships) {
    const concealment = relationship.required_inputs.find((row) => row.key === 'concealment_measurement')
    assert(concealment)
    assert(concealment.product_keys.includes('low-height-concealment-context'))
    assert(!concealment.product_keys.includes('horizontal-visibility-context'))
  }
})

Deno.test('existing Batch 3 relationship annotations are registry-driven', () => {
  const base = applicableBiologicalStateLedgerIds({
    stateCode: 'KY',
    sex: 'unknown',
    ageClass: 'unknown',
    regionalBreedingPhase: 'outside_documented_breeding_season',
  })
  assert(base.includes('FW-D05'))
  assert(base.includes('FW-D21'))
  assert(!base.includes('FW-D06'))
  assert(!base.includes('FW-D22'))

  const male = applicableBiologicalStateLedgerIds({
    stateCode: 'KY',
    sex: 'male',
    ageClass: 'adult',
    regionalBreedingPhase: 'within_peak_month_context',
  })
  assert(male.includes('FW-D05'))
  assert(male.includes('FW-D06'))
  assert(male.includes('FW-D21'))

  const female = applicableBiologicalStateLedgerIds({
    stateCode: 'KY',
    sex: 'female',
    ageClass: 'juvenile',
    regionalBreedingPhase: 'within_peak_month_context',
  })
  assert(female.includes('FW-D05'))
  assert(female.includes('FW-D21'))
  assert(female.includes('FW-D22'))
})

Deno.test('Batch 9 remains a relationship contract and does not produce a universal deer score', () => {
  const encoded = JSON.stringify(FARM_WATCH_DEER_RELATIONSHIPS)
  for (const forbidden of ['deer_score','habitat_score','movement_score','bedding_score']) {
    assert(!encoded.includes(forbidden))
  }
})
