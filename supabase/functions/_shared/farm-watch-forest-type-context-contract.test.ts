import {
  FARM_WATCH_FOREST_TYPE_CONTEXT_PRODUCT,
  validateFarmWatchForestTypeContext,
} from './farm-watch-forest-type-context-contract.ts'

function assert(condition: unknown, message = 'assertion failed'): asserts condition {
  if (!condition) throw new Error(message)
}

function row(key: string, status: 'available' | 'right_censored' | 'unavailable' = 'available') {
  return {
    study_class_key: key,
    status,
    distance_m: status === 'available' ? 125.5 : null,
    distance_lower_bound_m: status === 'right_censored' ? 3000 : null,
  }
}

function validContext() {
  return {
    schema: 'forest-type-context-v1',
    method: 'abernathy-habitat-distance-source-reconciliation-v1',
    evidence_class: 'deterministic_derived',
    evidence_state: 'proxy',
    source_reconciliation: {
      search_radius_m: 3000,
      annual_nlcd: { spatial_resolution_m: 30 },
    },
    habitat_distances: FARM_WATCH_FOREST_TYPE_CONTEXT_PRODUCT.studyClasses.map((key) => row(key)),
    deer_inference_performed: false,
    coefficient_transfer_performed: false,
    scoring_performed: false,
  }
}

Deno.test('M47 contract requires the exact six Abernathy habitat-distance classes', () => {
  const value = validContext()
  assert(validateFarmWatchForestTypeContext(value))
  assert(JSON.stringify(FARM_WATCH_FOREST_TYPE_CONTEXT_PRODUCT.studyClasses) === JSON.stringify([
    'pine_forest','hardwood_swamp','marsh','prairie','shrub','hardwood_hammock',
  ]))
  assert(!validateFarmWatchForestTypeContext({
    ...value,
    habitat_distances: value.habitat_distances.slice(0, 5),
  }))
})

Deno.test('M47 contract preserves proxy source-substitution semantics', () => {
  const value = validContext()
  assert(!validateFarmWatchForestTypeContext({ ...value, evidence_state: 'available' }))
  assert(!validateFarmWatchForestTypeContext({ ...value, deer_inference_performed: true }))
  assert(!validateFarmWatchForestTypeContext({ ...value, coefficient_transfer_performed: true }))
  assert(!validateFarmWatchForestTypeContext({ ...value, scoring_performed: true }))
  assert(!validateFarmWatchForestTypeContext({
    ...value,
    source_reconciliation: {
      ...value.source_reconciliation,
      annual_nlcd: { spatial_resolution_m: 10 },
    },
  }))
})

Deno.test('M47 right-censoring is explicit at the fixed 3 km search boundary', () => {
  const value = validContext()
  value.habitat_distances[0] = row('pine_forest', 'right_censored')
  assert(validateFarmWatchForestTypeContext(value))
  value.habitat_distances[0].distance_lower_bound_m = 2500
  assert(!validateFarmWatchForestTypeContext(value))
})
