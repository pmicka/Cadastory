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

Deno.test('production M08 preserves daily snow and minimum temperature without promoting Minnesota severity to Kentucky', () => {
  const product = FARM_WATCH_DEER_INPUT_PRODUCT_CATALOG['snow-winter-severity-context']
  assert(product)
  assert(product.status === 'production_source_substituted_neutral_measurement')

  const relationship = getDeerRelationship('FW-R03-winter-snow-conifer-context')
  assert(relationship)
  const snow = relationship.study_measurements.find(
    (row) => row.id === 'FW-M08-snow-depth-severity',
  )
  assert(snow)
  assert(snow.alignment === 'derived_equivalent')
  assert(/daily snow depth/i.test(snow.study_variable))
  assert(/minimum daily temperature/i.test(snow.study_variable))
  assert(/NOHRSC/i.test(snow.permitted_use))
  assert(/HRRR/i.test(snow.permitted_use))
  assert(/provenance\/context/i.test(snow.permitted_use))
  assert(/75%/i.test(snow.limitations.join(' ')))

  const fidelity = deerRelationshipStudyFidelityStatus(relationship)
  assert(!fidelity.blocker_ids.includes('FW-M08-snow-depth-severity'))
  assert(!fidelity.blocker_ids.includes('FW-M09-dense-conifer-cover'))
  assert(fidelity.status === 'context_only')
  assert(fidelity.context_only_ids.includes('FW-M10-winter-solar-context'))
})

Deno.test('production M09 preserves source conifer availability classes as a calibrated proxy', () => {
  const product = FARM_WATCH_DEER_INPUT_PRODUCT_CATALOG['conifer-cover-context']
  assert(product)
  assert(product.status === 'production_calibrated_proxy')
  assert(product.scales.includes('broad_3000m'))

  const relationship = getDeerRelationship('FW-R03-winter-snow-conifer-context')
  assert(relationship)
  const requirement = relationship.required_inputs.find((row) => row.key === 'conifer_cover')
  assert(requirement)
  assert(JSON.stringify(requirement.allowed_scales) === JSON.stringify(['broad_3000m']))
  assert(requirement.freshness_policy === 'static_context_ok')

  const conifer = relationship.study_measurements.find(
    (row) => row.id === 'FW-M09-dense-conifer-cover',
  )
  assert(conifer)
  assert(conifer.alignment === 'calibrated_proxy')
  assert(/40% to <70%/i.test(conifer.study_variable))
  assert(/>=70%/i.test(conifer.study_variable))
  assert(/Annual NLCD Evergreen Forest/i.test(conifer.permitted_use))
  assert(/Tree Canopy Cover/i.test(conifer.permitted_use))
  assert(/Mixed Forest \(43\).*other/i.test(conifer.permitted_use))
  assert(/broad_3000m/i.test(conifer.permitted_use))
  assert(/KyFromAbove imagery/i.test(conifer.permitted_use))
  assert(/calibrated proxy/i.test(conifer.limitations.join(' ')))
  assert(/open-conifer.*not locally image-validated/i.test(conifer.limitations.join(' ')))

  const fidelity = deerRelationshipStudyFidelityStatus(relationship)
  assert(!fidelity.blocker_ids.includes('FW-M09-dense-conifer-cover'))
  assert(fidelity.status === 'context_only')
  assert(fidelity.context_only_ids.includes('FW-M10-winter-solar-context'))
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

Deno.test('M29 and M32 use explicit managed-food configuration rather than generic greenness', () => {
  const product = FARM_WATCH_DEER_INPUT_PRODUCT_CATALOG['managed-food-feature-context']
  assert(product)
  assert(product.status === 'production_static_configured')
  assert(product.evidence_states.includes('known'))

  for (const [relationshipId, measurementId, remainingBlocker] of [
    ['FW-R15-adult-male-hunter-space-time','FW-M29-food-opportunity','FW-M28-daily-hunter-activity'],
    ['FW-R16-sex-risk-food-tradeoff','FW-M32-abundant-food-risk','FW-M31-frequent-hunt-risk'],
  ] as const) {
    const relationship = getDeerRelationship(relationshipId)
    assert(relationship)
    const resource = relationship.required_inputs.find((row) => row.key === 'resource_state')
    assert(resource)
    assert(JSON.stringify(resource.product_keys) === JSON.stringify(['managed-food-feature-context']))
    assert(resource.allowed_evidence_states.includes('known'))

    const measurement = relationship.study_measurements.find((row) => row.id === measurementId)
    assert(measurement)
    assert(measurement.alignment === 'derived_equivalent')
    assert(/managed-food-feature-context/i.test(measurement.permitted_use))
    assert(!deerRelationshipStudyFidelityStatus(relationship).blocker_ids.includes(measurementId))
    assert(deerRelationshipStudyFidelityStatus(relationship).blocker_ids.includes(remainingBlocker))
  }
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
    FARM_WATCH_DEER_INPUT_PRODUCT_CATALOG['multiscale-forest-context'].status ===
      'production_on_demand_neutral_measurement',
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

  const buildingRelationship = getDeerRelationship('FW-R13-winter-food-configuration-activity')
  assert(buildingRelationship)
  const buildingMeasurement = buildingRelationship.study_measurements.find(
    (row) => row.id === 'FW-M24-building-density',
  )
  assert(buildingMeasurement)
  assert(/production\/imagery vintage/i.test(buildingMeasurement.permitted_use))
  assert(/450 sq ft/i.test(buildingMeasurement.permitted_use))
  assert(/not treated as a census-complete inventory/i.test(
    buildingMeasurement.limitations.join(' '),
  ))

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

  const forestReq = road.required_inputs.find((row) => row.key === 'forest_context')
  assert(forestReq)
  assert(JSON.stringify(forestReq.product_keys) === JSON.stringify(['multiscale-forest-context']))
  const forestMeasurement = road.study_measurements.find(
    (row) => row.id === 'FW-M35-forest-landscape-context',
  )
  assert(forestMeasurement)
  assert(forestMeasurement.alignment === 'derived_equivalent')
  assert(/10 m support/i.test(forestMeasurement.permitted_use))
  assert(/30\/90\/270 m/i.test(forestMeasurement.permitted_use))
  assert(/source.*substitution/i.test(forestMeasurement.limitations.join(' ')))

  const multiscale = getDeerRelationship('FW-R20-multiscale-cover-food-context')
  assert(multiscale)
  const scaleReq = multiscale.required_inputs.find((row) => row.key === 'study_scales')
  assert(scaleReq)
  assert(JSON.stringify(scaleReq.product_keys) === JSON.stringify(['multiscale-cover-context']))

  const storm = getDeerRelationship('FW-R22-extreme-storm-refuge')
  assert(storm)
  const stormMeasurement = storm.study_measurements.find(
    (row) => row.id === 'FW-M45-extreme-hurricane-event',
  )
  assert(stormMeasurement)
  assert(/healthy poll with no qualifying intersection is explicitly not applicable/i.test(
    stormMeasurement.permitted_use,
  ))
  assert(/source failure, stale polling, or unresolved qualifying alert geometry is unavailable/i.test(
    stormMeasurement.permitted_use,
  ))
  const forestRefuge = storm.study_measurements.find(
    (row) => row.id === 'FW-M47-forest-refuge-type',
  )
  assert(forestRefuge)
  assert(forestRefuge.alignment === 'derived_equivalent')
  assert(/Euclidean distance/i.test(forestRefuge.study_variable))
  for (const expected of ['pine forest','hardwood swamp','marsh','prairie','shrub','hardwood hammock']) {
    assert(forestRefuge.study_variable.toLowerCase().includes(expected), expected)
  }
  assert(/Annual NLCD/i.test(forestRefuge.permitted_use))
  assert(/NWI/i.test(forestRefuge.permitted_use))
  assert(/proxy evidence state/i.test(forestRefuge.permitted_use))
  assert(!deerRelationshipStudyFidelityStatus(storm).blocker_ids.includes(
    'FW-M47-forest-refuge-type',
  ))
  assert(!deerRelationshipStudyFidelityStatus(storm).blocker_ids.includes(
    'FW-M45-extreme-hurricane-event',
  ))
  assert(deerRelationshipStudyFidelityStatus(storm).status === 'module_eligible')
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

Deno.test('FW-D17 preserves female-only sample, source-aligned forest composition, and predator occurrence', () => {
  const relationship = getDeerRelationship('FW-R21-human-footprint-seasonal-context')
  assert(relationship)
  assert(JSON.stringify(relationship.biological_state_gates.sex) === JSON.stringify(['female']))

  const resource = relationship.required_inputs.find((row) => row.key === 'resource_context')
  assert(resource)
  assert(JSON.stringify(resource.product_keys) === JSON.stringify(['forest-type-context']))
  assert(!resource.product_keys.includes('field-phenology-context' as any))
  assert(!resource.product_keys.includes('browse-resource-context' as any))

  const forest = relationship.study_measurements.find(
    (row) => row.id === 'FW-M43-intact-deciduous-forest',
  )
  assert(forest)
  assert(/species-specific overstorey canopy composition/i.test(forest.study_variable))
  assert(/eight leading tree species/i.test(forest.study_protocol))
  assert(/fragmentation/i.test(forest.permitted_use))

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
