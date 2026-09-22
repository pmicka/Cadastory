import {
  FARM_WATCH_FIELD_PHENOLOGY_PRODUCT,
  validateFarmWatchFieldPhenologyContext,
  validateFarmWatchFieldPhenologyResponse,
} from './farm-watch-field-phenology-contract.ts'

function assert(condition: unknown, message = 'assertion failed'): asserts condition {
  if (!condition) throw new Error(message)
}

function context() {
  return {
    schema: FARM_WATCH_FIELD_PHENOLOGY_PRODUCT.outputSchemaVersion,
    method: FARM_WATCH_FIELD_PHENOLOGY_PRODUCT.algorithmVersion,
    evidence_class: FARM_WATCH_FIELD_PHENOLOGY_PRODUCT.evidenceClass,
    as_of_date: '2026-09-21',
    scope_counts: { property: 0, local_500m: 1, landscape_1500m: 12, broad_3000m: 37 },
    fields: [{
      field_id: '5407d61e-cd63-4889-aae3-8ebcd30446e3',
      scopes: ['local_500m','landscape_1500m','broad_3000m'],
      evidence_state: 'unavailable',
      phenology_state: 'unknown',
      trajectory_state: 'insufficient_observations',
      crop_identity: { crop_year: 2025, crop_name: 'Grassland/Pasture', state: 'stale' },
      observations: [],
    }],
    source_fingerprint_sha256: 'a'.repeat(64),
    scoring_performed: false,
    behavioral_inference_performed: false,
    interpretation_boundary: 'neutral field state only',
  }
}

Deno.test('field phenology accepts explicit unknown harvest state', () => {
  assert(validateFarmWatchFieldPhenologyContext(context()))
})

Deno.test('field phenology rejects unsupported harvest promotion', () => {
  const value = context()
  value.fields[0].phenology_state = 'harvested' as any
  assert(!validateFarmWatchFieldPhenologyContext(value))
})

Deno.test('response requires landscape-domain identity', () => {
  const value = {
    status: 'partial',
    context: context(),
    identity: {
      boundary_sha256: 'b'.repeat(64),
      landscape_domain_identity_sha256: 'c'.repeat(64),
      source_signature_sha256: 'd'.repeat(64),
      algorithm_version: FARM_WATCH_FIELD_PHENOLOGY_PRODUCT.algorithmVersion,
      output_schema_version: FARM_WATCH_FIELD_PHENOLOGY_PRODUCT.outputSchemaVersion,
      identity_sha256: 'e'.repeat(64),
    },
  }
  assert(validateFarmWatchFieldPhenologyResponse(value))
  const missingDomainIdentity = {
    ...value,
    identity: { ...value.identity, landscape_domain_identity_sha256: undefined },
  }
  assert(!validateFarmWatchFieldPhenologyResponse(missingDomainIdentity))
})
