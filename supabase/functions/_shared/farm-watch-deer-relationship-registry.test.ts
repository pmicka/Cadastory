import {
  FARM_WATCH_DEER_BLOCKED_UNIVERSAL_ASSUMPTIONS,
  FARM_WATCH_DEER_INPUT_PRODUCT_CATALOG,
  FARM_WATCH_DEER_LEDGER_IDS,
  FARM_WATCH_DEER_RELATIONSHIPS,
  applicableBiologicalStateLedgerIds,
  deerRelationshipStudyFidelityStatus,
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
  assert(FARM_WATCH_DEER_RELATIONSHIPS.length >= 31)
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

Deno.test('active biological relationships carry explicit study-measurement contracts', () => {
  for (const relationship of FARM_WATCH_DEER_RELATIONSHIPS) {
    if (
      relationship.output_kind === 'negative_constraint' ||
      relationship.output_kind === 'not_applicable' ||
      relationship.module_family === 'architecture_context'
    ) continue
    assert(
      relationship.study_measurements.length > 0,
      relationship.relationship_id + ' has no study-measurement contract',
    )
  }
})

Deno.test('FW-R01 vegetation height is bound only to the production-validated study-aligned product', () => {
  const product = FARM_WATCH_DEER_INPUT_PRODUCT_CATALOG[
    'study-aligned-vegetation-height-context'
  ]
  assert(product)
  assert(product.status === 'production_validated_neutral_measurement')
  assert(JSON.stringify(product.scales) === JSON.stringify(['local_500m']))
  assert(JSON.stringify(product.evidence_states) === JSON.stringify(['available']))

  const relationship = getDeerRelationship('FW-R01-summer-thermal-resource-tradeoff')
  assert(relationship)
  const requirement = relationship.required_inputs.find((row) => row.key === 'vegetation_height')
  assert(requirement)
  assert(
    JSON.stringify(requirement.product_keys) ===
      JSON.stringify(['study-aligned-vegetation-height-context']),
  )
  assert(!requirement.product_keys.includes('lidar-physical-structure' as any))

  const measurement = relationship.study_measurements.find(
    (row) => row.id === 'FW-M02-vegetation-height',
  )
  assert(measurement)
  assert(measurement.alignment === 'derived_equivalent')

  const fidelity = deerRelationshipStudyFidelityStatus(relationship)
  assert(fidelity.status === 'blocked_measurement_alignment')
  assert(
    JSON.stringify(fidelity.blocker_ids) ===
      JSON.stringify([
        'FW-M01-operative-temperature',
        'FW-M03-forage-index',
        'FW-M04-woody-canopy',
        'FW-M05-activity-period',
      ]),
  )
  assert(!fidelity.blocker_ids.includes('FW-M02-vegetation-height'))
})

Deno.test('completed mast products are reconciled without promoting regional survey state to property mast abundance', () => {
  assert(FARM_WATCH_DEER_INPUT_PRODUCT_CATALOG['mast-capacity'].status === 'production')
  assert(
    FARM_WATCH_DEER_INPUT_PRODUCT_CATALOG['annual-mast-state'].status ===
      'production_exact_year_regional_proxy',
  )

  const relationship = getDeerRelationship('FW-R11-mast-fall-space-use')
  assert(relationship)
  const annual = relationship.study_measurements.find(
    (row) => row.id === 'FW-M17-annual-mast-fall',
  )
  assert(annual)
  assert(annual.alignment === 'calibrated_proxy')
  assert(/regional proxy/i.test(annual.permitted_use))
  assert(/property.*abundance/i.test(annual.limitations.join(' ')))
  assert(!deerRelationshipStudyFidelityStatus(relationship).blocker_ids.includes(
    'FW-M17-annual-mast-fall',
  ))
})

Deno.test('production Tier 1 context measurements are promoted without biological overreach', () => {
  assert(
    FARM_WATCH_DEER_INPUT_PRODUCT_CATALOG['human-footprint-context'].status ===
      'production_neutral_measurement',
  )
  assert(
    FARM_WATCH_DEER_INPUT_PRODUCT_CATALOG['road-focal-context'].status ===
      'production_on_demand_neutral_measurement',
  )
  assert(
    FARM_WATCH_DEER_INPUT_PRODUCT_CATALOG['multiscale-cover-context'].status ===
      'production_neutral_measurement',
  )
  assert(
    FARM_WATCH_DEER_INPUT_PRODUCT_CATALOG['extreme-weather-event-context'].status ===
      'production_authoritative_event_gate',
  )

  const expected = new Map([
    ['FW-M24-building-density', 'FW-R13-winter-food-configuration-activity'],
    ['FW-M36-road-landscape-context', 'FW-R18-terrain-movement-context'],
    ['FW-M39-d16-study-scales', 'FW-R20-multiscale-cover-food-context'],
    ['FW-M45-extreme-hurricane-event', 'FW-R22-extreme-storm-refuge'],
  ])
  for (const [measurementId, relationshipId] of expected) {
    const relationship = getDeerRelationship(relationshipId)
    assert(relationship, relationshipId)
    const measurement = relationship.study_measurements.find((row) => row.id === measurementId)
    assert(measurement, measurementId)
    assert(measurement.alignment === 'derived_equivalent', measurementId)
  }

  const road = getDeerRelationship('FW-R18-terrain-movement-context')
  assert(road)
  const roadReq = road.required_inputs.find((row) => row.key === 'road_context')
  assert(roadReq)
  assert(JSON.stringify(roadReq.product_keys) === JSON.stringify(['road-focal-context']))
  const roadMeasurement = road.study_measurements.find(
    (row) => row.id === 'FW-M36-road-landscape-context',
  )
  assert(roadMeasurement)
  assert(/10 m distance-to-nearest-road/i.test(roadMeasurement.permitted_use))
  assert(/30\/90\/270 m/i.test(roadMeasurement.permitted_use))

  const multiscale = getDeerRelationship('FW-R20-multiscale-cover-food-context')
  assert(multiscale)
  const scaleReq = multiscale.required_inputs.find((row) => row.key === 'study_scales')
  assert(scaleReq)
  assert(JSON.stringify(scaleReq.product_keys) === JSON.stringify(['multiscale-cover-context']))

  const storm = getDeerRelationship('FW-R22-extreme-storm-refuge')
  assert(storm)
  assert(deerRelationshipStudyFidelityStatus(storm).blocker_ids.includes(
    'FW-M47-forest-refuge-type',
  ))
  assert(!deerRelationshipStudyFidelityStatus(storm).blocker_ids.includes(
    'FW-M45-extreme-hurricane-event',
  ))
})

Deno.test('numeric coefficients are rejected when coefficient transfer is not authorized', () => {
  const relationship = getDeerRelationship('FW-R25-kentucky-breeding-context')
  assert(relationship)
  assert(relationship.coefficient_transfer.status === 'not_supported')
  assert(!validateRelationshipModuleDefinition({
    relationship_id: relationship.relationship_id,
    ledger_ids: relationship.ledger_ids,
    input_bindings: [{
      key: 'biological_state',
      product_key: 'deer-biological-state',
      evidence_state: 'available',
      scale: 'statewide',
    }],
    coefficient_transfer_status: 'not_supported',
    numeric_parameters: [1.25],
    study_measurement_ids: ['FW-M50-kentucky-regional-breeding'],
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
  const relationship = getDeerRelationship('FW-R25-kentucky-breeding-context')
  assert(relationship)
  assert(FARM_WATCH_DEER_BLOCKED_UNIVERSAL_ASSUMPTIONS.includes('moon_phase_generic_movement'))
  assert(!validateRelationshipModuleDefinition({
    relationship_id: relationship.relationship_id,
    ledger_ids: relationship.ledger_ids,
    input_bindings: [{
      key: 'biological_state',
      product_key: 'deer-biological-state',
      evidence_state: 'available',
      scale: 'statewide',
    }],
    coefficient_transfer_status: 'not_supported',
    numeric_parameters: [],
    universal_assumption_ids: ['moon_phase_generic_movement'],
    study_measurement_ids: ['FW-M50-kentucky-regional-breeding'],
  }))
})

Deno.test('stale required inputs are not silently accepted', () => {
  const relationship = getDeerRelationship('FW-R25-kentucky-breeding-context')
  assert(relationship)
  assert(!validateRelationshipModuleDefinition({
    relationship_id: relationship.relationship_id,
    ledger_ids: relationship.ledger_ids,
    input_bindings: [{
      key: 'biological_state',
      product_key: 'deer-biological-state',
      evidence_state: 'stale',
      scale: 'statewide',
    }],
    coefficient_transfer_status: 'not_supported',
    numeric_parameters: [],
    study_measurement_ids: ['FW-M50-kentucky-regional-breeding'],
  }))
})

Deno.test('input scale mismatch is rejected independently of fidelity blockers', () => {
  const relationship = getDeerRelationship('FW-R25-kentucky-breeding-context')
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
    study_measurement_ids: ['FW-M50-kentucky-regional-breeding'],
  }))
})

Deno.test('measurement-aligned module definitions must declare the study measurement contract', () => {
  const relationship = getDeerRelationship('FW-R25-kentucky-breeding-context')
  assert(relationship)
  assert(deerRelationshipStudyFidelityStatus(relationship).status === 'module_eligible')
  const base = {
    relationship_id: relationship.relationship_id,
    ledger_ids: relationship.ledger_ids,
    input_bindings: [{
      key: 'biological_state' as const,
      product_key: 'deer-biological-state' as const,
      evidence_state: 'available' as const,
      scale: 'statewide' as const,
    }],
    coefficient_transfer_status: 'not_supported' as const,
    numeric_parameters: [],
  }
  assert(!validateRelationshipModuleDefinition(base))
  assert(validateRelationshipModuleDefinition({
    ...base,
    study_measurement_ids: ['FW-M50-kentucky-regional-breeding'],
  }))
})

Deno.test('value-level study constraints must be declared by a future module', () => {
  const relationship = getDeerRelationship('FW-R12-crop-phenology-home-range-response')
  assert(relationship)
  assert(relationship.value_constraints.some((row) => row.id === 'FW-C01-crop-is-corn'))
  assert(relationship.value_constraints.some((row) => row.id === 'FW-C02-corn-stage'))
  assert(deerRelationshipStudyFidelityStatus(relationship).status === 'blocked_measurement_alignment')
})

Deno.test('Batch 6 general viewshed is not silently substituted for FW-D04 low concealment', () => {
  const relationships = relationshipsForLedgerId('FW-D04')
  assert(relationships.length === 2)
  for (const relationship of relationships) {
    const concealment = relationship.required_inputs.find((row) => row.key === 'concealment_measurement')
    assert(concealment)
    assert(concealment.product_keys.includes('low-height-concealment-context'))
    assert(!concealment.product_keys.includes('horizontal-visibility-context'))
    assert(deerRelationshipStudyFidelityStatus(relationship).status === 'blocked_measurement_alignment')
  }
})

Deno.test('Hunsaker movement relationship is blocked until two-year versus three-plus age fidelity exists', () => {
  const relationship = getDeerRelationship('FW-R09-male-breeding-age-movement')
  assert(relationship)
  const age = relationship.study_measurements.find((row) => row.id === 'FW-M15-hunsaker-male-age')
  assert(age)
  assert(age.alignment === 'unsupported')
  assert(deerRelationshipStudyFidelityStatus(relationship).status === 'blocked_measurement_alignment')
})

Deno.test('FW-D14 terrain relationship preserves juvenile-male dispersal gate', () => {
  const relationship = getDeerRelationship('FW-R18-terrain-movement-context')
  assert(relationship)
  assert(JSON.stringify(relationship.biological_state_gates.sex) === JSON.stringify(['male']))
  assert(JSON.stringify(relationship.biological_state_gates.age_class) === JSON.stringify(['juvenile']))
  assert(JSON.stringify(relationship.biological_state_gates.movement_state) === JSON.stringify(['dispersal']))
})

Deno.test('FW-D15 keeps spring probability, dispersal distance, and path selection separate', () => {
  const relationships = relationshipsForLedgerId('FW-D15')
  const ids = new Set(relationships.map((row) => row.relationship_id))
  assert(ids.has('FW-R19-juvenile-male-dispersal-ag-riparian'))
  assert(ids.has('FW-R30-spring-juvenile-male-dispersal-probability'))
  assert(ids.has('FW-R31-juvenile-male-dispersal-distance'))

  const path = getDeerRelationship('FW-R19-juvenile-male-dispersal-ag-riparian')
  assert(path)
  const riparian = path.required_inputs.find((row) => row.key === 'riparian_geometry')
  assert(riparian)
  assert(riparian.product_keys.includes('mapped-hydrography-context'))
  assert(!riparian.product_keys.includes('surface-water-state'))

  const spring = getDeerRelationship('FW-R30-spring-juvenile-male-dispersal-probability')
  assert(spring)
  assert(JSON.stringify(spring.biological_state_gates.seasons) === JSON.stringify(['spring']))
})

Deno.test('FW-D13 low-pressure null result requires explicit low pressure', () => {
  const relationship = getDeerRelationship('FW-R17-low-pressure-negative-constraint')
  assert(relationship)
  const pressure = relationship.value_constraints.find((row) => row.id === 'FW-C04-pressure-is-low')
  assert(pressure)
  assert(JSON.stringify(pressure.values) === JSON.stringify(['low']))
  assert(deerRelationshipStudyFidelityStatus(relationship).status === 'blocked_measurement_alignment')
})

Deno.test('FW-D17 preserves female-only sample and predator-occurrence component', () => {
  const relationship = getDeerRelationship('FW-R21-human-footprint-seasonal-context')
  assert(relationship)
  assert(JSON.stringify(relationship.biological_state_gates.sex) === JSON.stringify(['female']))
  const predator = relationship.required_inputs.find((row) => row.key === 'predator_occurrence')
  assert(predator)
  assert(predator.product_keys.includes('predator-occurrence-context'))
  assert(deerRelationshipStudyFidelityStatus(relationship).status === 'blocked_measurement_alignment')
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
