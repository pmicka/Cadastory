import {
  FARM_WATCH_SEASONAL_STATE_PRODUCT,
  validateFarmWatchSeasonalStateContext,
  validateFarmWatchSeasonalStateResponse,
} from './farm-watch-seasonal-state-contract.ts'

function assert(condition: unknown, message = 'assertion failed'): asserts condition {
  if (!condition) throw new Error(message)
}

function context() {
  const componentStates = Object.fromEntries(
    FARM_WATCH_SEASONAL_STATE_PRODUCT.componentKeys.map((key) => [key, 'proxy']),
  )
  componentStates.drought = 'known'
  componentStates.precipitation = 'unavailable'
  componentStates.mapped_crop_context = 'stale'
  return {
    schema: FARM_WATCH_SEASONAL_STATE_PRODUCT.outputSchemaVersion,
    method: FARM_WATCH_SEASONAL_STATE_PRODUCT.algorithmVersion,
    as_of_date: '2026-09-21',
    evidence_class: FARM_WATCH_SEASONAL_STATE_PRODUCT.evidenceClass,
    component_state_vocabulary: ['known','proxy','stale','unavailable'],
    component_states: componentStates,
    component_counts: { current_or_proxy: 5, stale: 2, unavailable: 1 },
    components: Object.fromEntries(
      Object.entries(componentStates).map(([key,state]) => [key,{state}]),
    ),
    source_fingerprint_sha256: 'a'.repeat(64),
    scoring_performed: false,
    behavioral_inference_performed: false,
    interpretation_boundary: 'neutral dated evidence only',
  }
}

Deno.test('seasonal context accepts mixed explicit evidence states', () => {
  assert(validateFarmWatchSeasonalStateContext(context()))
})

Deno.test('seasonal context rejects a component state mismatch', () => {
  const value = context()
  value.components.stream.state = 'known'
  assert(!validateFarmWatchSeasonalStateContext(value))
})

Deno.test('seasonal response validates identity and preserves neutral semantics', () => {
  const value = {
    status: 'partial',
    as_of_date: '2026-09-21',
    context: context(),
    identity: {
      boundary_sha256: 'b'.repeat(64),
      source_signature_sha256: 'c'.repeat(64),
      algorithm_version: FARM_WATCH_SEASONAL_STATE_PRODUCT.algorithmVersion,
      output_schema_version: FARM_WATCH_SEASONAL_STATE_PRODUCT.outputSchemaVersion,
      identity_sha256: 'd'.repeat(64),
    },
  }
  assert(validateFarmWatchSeasonalStateResponse(value))
  const encoded = JSON.stringify(value)
  assert(!encoded.includes('deer_score'))
  assert(!encoded.includes('bedding_score'))
})

Deno.test('missing and stale responses must withhold context', () => {
  assert(validateFarmWatchSeasonalStateResponse({status:'missing',context:null}))
  assert(validateFarmWatchSeasonalStateResponse({status:'stale',context:null}))
  assert(!validateFarmWatchSeasonalStateResponse({status:'stale',context:context()}))
})
