import {
  FARM_WATCH_DEER_MEASUREMENT_RESOLUTION_DECISIONS,
  blockedDeerStudyMeasurements,
  getDeerMeasurementResolutionDecision,
  validateDeerMeasurementResolutionDecisions,
} from './farm-watch-deer-measurement-resolution.ts'

function assert(condition: unknown, message = 'assertion failed'): asserts condition {
  if (!condition) throw new Error(message)
}

Deno.test('every currently blocked deer study measurement has exactly one resolution decision', () => {
  assert(validateDeerMeasurementResolutionDecisions())
  const blocked = blockedDeerStudyMeasurements()
  assert(blocked.length === 37, 'expected 37 blocked study measurements')
  assert(FARM_WATCH_DEER_MEASUREMENT_RESOLUTION_DECISIONS.length === blocked.length)
  const decisionIds = FARM_WATCH_DEER_MEASUREMENT_RESOLUTION_DECISIONS
    .map((row) => row.measurement_id)
    .sort()
  assert(JSON.stringify(decisionIds) === JSON.stringify(blocked.map((row) => row.id).sort()))
})

Deno.test('measurement resolution portfolio preserves the three explicit dispositions', () => {
  const counts = FARM_WATCH_DEER_MEASUREMENT_RESOLUTION_DECISIONS.reduce(
    (acc, row) => {
      acc[row.disposition] += 1
      return acc
    },
    { reproduce: 0, calibrated_proxy: 0, remain_unavailable: 0 },
  )
  assert(counts.reproduce === 22)
  assert(counts.calibrated_proxy === 9)
  assert(counts.remain_unavailable === 6)
})

Deno.test('Wiemers vegetation height is reproducible while forage chemistry remains unavailable', () => {
  const height = getDeerMeasurementResolutionDecision('FW-M02-vegetation-height')
  const forage = getDeerMeasurementResolutionDecision('FW-M03-forage-index')
  assert(height?.disposition === 'reproduce')
  assert(height?.target_product === 'study-aligned-vegetation-height-context')
  assert(forage?.disposition === 'remain_unavailable')
  assert(forage?.target_product === null)
})

Deno.test('Gallina concealment remains a field-calibrated physical proxy', () => {
  for (const id of ['FW-M11-gallina-concealment-profile','FW-M13-gallina-low-strata']) {
    const decision = getDeerMeasurementResolutionDecision(id)
    assert(decision?.disposition === 'calibrated_proxy')
    assert(decision?.target_product === 'low-height-concealment-context')
    assert(decision.validation.some((value) => /validat|field|target/i.test(value)))
  }
})

Deno.test('stand vulnerability uses calibrated viewshed rather than a generic radius', () => {
  const decision = getDeerMeasurementResolutionDecision('FW-M26-stand-vulnerability-zone')
  assert(decision?.disposition === 'calibrated_proxy')
  assert(decision?.target_product === 'stand-vulnerability-zone-context')
  assert(/viewshed/i.test(decision.rationale))
  assert(/range/i.test(decision.validation.join(' ')))
})

Deno.test('low hunting pressure is reproduced as explicit effort and not a universal threshold', () => {
  const decision = getDeerMeasurementResolutionDecision('FW-M33-low-hunting-pressure')
  assert(decision?.disposition === 'reproduce')
  assert(decision?.target_product === 'human-activity-context')
  assert(/effort density/i.test(decision.rationale + ' ' + decision.implementation_boundary))
  assert(/universal.*threshold/i.test(decision.rationale + ' ' + decision.implementation_boundary))
})

Deno.test('hunting food relationships bind to explicit managed food features', () => {
  for (const id of ['FW-M29-food-opportunity','FW-M32-abundant-food-risk']) {
    const decision = getDeerMeasurementResolutionDecision(id)
    assert(decision?.disposition === 'reproduce')
    assert(decision?.target_product === 'managed-food-feature-context')
  }
})

Deno.test('weak substitutions remain unavailable', () => {
  const unavailable = [
    'FW-M03-forage-index',
    'FW-M23-woody-twig-density',
    'FW-M40-d16-escape-cover-types',
    'FW-M42-human-footprint-composition',
    'FW-M44-wolf-occurrence',
    'FW-M53-male-reproductive-phase',
  ]
  for (const id of unavailable) {
    const decision = getDeerMeasurementResolutionDecision(id)
    assert(decision?.disposition === 'remain_unavailable', id)
    assert(decision?.target_product === null, id)
  }
})

Deno.test('resolution decisions do not authorize deer scoring or silent inference', () => {
  const encoded = JSON.stringify(FARM_WATCH_DEER_MEASUREMENT_RESOLUTION_DECISIONS)
  for (const forbidden of [
    'deer_score',
    'habitat_score',
    'bedding_score',
    'movement_score',
    'infer exact age',
    'infer individual rut',
  ]) {
    assert(!encoded.includes(forbidden), forbidden)
  }
})
