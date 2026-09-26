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
  assert(blocked.length === 24, 'expected 24 blocked study measurements')
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
  assert(counts.reproduce === 11)
  assert(counts.calibrated_proxy === 7)
  assert(counts.remain_unavailable === 6)
})

Deno.test('production Tier 1 measurements leave the blocked resolution queue', () => {
  const blocked = blockedDeerStudyMeasurements()
  for (const id of [
    'FW-M24-building-density',
    'FW-M36-road-landscape-context',
    'FW-M39-d16-study-scales',
    'FW-M45-extreme-hurricane-event',
  ]) {
    assert(!blocked.some((row) => row.id === id), id)
    assert(getDeerMeasurementResolutionDecision(id) === null, id)
  }
})

Deno.test('production M35 multiscale forest context leaves the blocked resolution queue', () => {
  const blocked = blockedDeerStudyMeasurements()
  assert(!blocked.some((row) => row.id === 'FW-M35-forest-landscape-context'))
  assert(getDeerMeasurementResolutionDecision('FW-M35-forest-landscape-context') === null)
})

Deno.test('production M47 habitat-distance context leaves the blocked resolution queue', () => {
  const blocked = blockedDeerStudyMeasurements()
  assert(!blocked.some((row) => row.id === 'FW-M47-forest-refuge-type'))
  assert(getDeerMeasurementResolutionDecision('FW-M47-forest-refuge-type') === null)
})

Deno.test('production M08 snow/winter severity context leaves the blocked resolution queue', () => {
  const blocked = blockedDeerStudyMeasurements()
  assert(!blocked.some((row) => row.id === 'FW-M08-snow-depth-severity'))
  assert(getDeerMeasurementResolutionDecision('FW-M08-snow-depth-severity') === null)
})

Deno.test('production M09 conifer-cover proxy leaves the blocked resolution queue', () => {
  const blocked = blockedDeerStudyMeasurements()
  assert(!blocked.some((row) => row.id === 'FW-M09-dense-conifer-cover'))
  assert(getDeerMeasurementResolutionDecision('FW-M09-dense-conifer-cover') === null)
})

Deno.test('completed Batch 5 mast annual state leaves the blocked resolution queue as a regional calibrated proxy', () => {
  const blocked = blockedDeerStudyMeasurements()
  const mast = getDeerMeasurementResolutionDecision('FW-M17-annual-mast-fall')
  assert(!blocked.some((row) => row.id === 'FW-M17-annual-mast-fall'))
  assert(mast === null)
})

Deno.test('2026 operating posture parks individual-state and manual/non-core measurements without changing science dispositions', () => {
  const counts = FARM_WATCH_DEER_MEASUREMENT_RESOLUTION_DECISIONS.reduce(
    (acc, row) => {
      acc[row.operational_posture] += 1
      return acc
    },
    {
      active: 0,
      parked_2026_individual_state: 0,
      parked_2026_manual_or_noncore: 0,
    },
  )
  assert(counts.active === 4)
  assert(counts.parked_2026_individual_state === 3)
  assert(counts.parked_2026_manual_or_noncore === 17)

  for (const id of [
    'FW-M15-hunsaker-male-age',
    'FW-M51-maternal-age-category',
    'FW-M54-female-parturition-phase',
  ]) {
    const row = getDeerMeasurementResolutionDecision(id)
    assert(row?.operational_posture === 'parked_2026_individual_state', id)
  }

  for (const id of [
    'FW-M01-operative-temperature',
    'FW-M03-forage-index',
    'FW-M05-activity-period',
    'FW-M19-current-corn-identity',
    'FW-M20-corn-stage-harvest',
    'FW-M23-woody-twig-density',
    'FW-M25-discrete-stand-hunt',
    'FW-M28-daily-hunter-activity',
    'FW-M31-frequent-hunt-risk',
    'FW-M33-low-hunting-pressure',
    'FW-M40-d16-escape-cover-types',
    'FW-M41-d16-winter-food',
    'FW-M42-human-footprint-composition',
    'FW-M44-wolf-occurrence',
    'FW-M43-intact-deciduous-forest',
    'FW-M53-male-reproductive-phase',
    'FW-M56-potential-path-agriculture',
  ]) {
    const row = getDeerMeasurementResolutionDecision(id)
    assert(row?.operational_posture === 'parked_2026_manual_or_noncore', id)
  }
})

Deno.test('resolved Wiemers vegetation height leaves the blocked resolution queue while forage chemistry remains unavailable', () => {
  const blocked = blockedDeerStudyMeasurements()
  const height = getDeerMeasurementResolutionDecision('FW-M02-vegetation-height')
  const forage = getDeerMeasurementResolutionDecision('FW-M03-forage-index')
  assert(!blocked.some((row) => row.id === 'FW-M02-vegetation-height'))
  assert(height === null)
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

Deno.test('production managed-food context closes M29 and M32 measurement blockers', () => {
  const blocked = blockedDeerStudyMeasurements()
  for (const id of ['FW-M29-food-opportunity','FW-M32-abundant-food-risk']) {
    assert(!blocked.some((row) => row.id === id), id)
    assert(getDeerMeasurementResolutionDecision(id) === null, id)
  }
})

Deno.test('production managed-water context closes M48 measurement blocker', () => {
  const blocked = blockedDeerStudyMeasurements()
  assert(!blocked.some((row) => row.id === 'FW-M48-usable-water-source'))
  assert(getDeerMeasurementResolutionDecision('FW-M48-usable-water-source') === null)
})

Deno.test('FW-M43 requires species-specific overstorey composition rather than generic forest structure', () => {
  const decision = getDeerMeasurementResolutionDecision('FW-M43-intact-deciduous-forest')
  assert(decision?.disposition === 'reproduce')
  assert(decision?.target_product === 'forest-type-context')
  assert(/eight leading tree species/i.test(decision.rationale))
  assert(/Generic Trees/i.test(decision.implementation_boundary))
  assert(/fragmentation/i.test(decision.implementation_boundary))
  assert(/unresolved/i.test(decision.implementation_boundary))
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
  ]) {
    assert(!encoded.includes(forbidden), forbidden)
  }
})
