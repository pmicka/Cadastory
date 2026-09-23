import {
  FARM_WATCH_SURFACE_WATER_STATE_PRODUCT,
  classifyMappedWaterPersistence,
  validateFarmWatchSurfaceWaterStateContext,
} from './farm-watch-surface-water-state-contract.ts'

function assert(condition: unknown, message = 'assertion failed'): asserts condition {
  if (!condition) throw new Error(message)
}

Deno.test('NWI mapped persistence uses only explicit water-regime attributes', () => {
  assert(classifyMappedWaterPersistence({
    sourceSlug: 'usfws-nwi', featureKind: 'wetland',
    properties: { water_regime_name: 'Permanently Flooded' },
  }) === 'mapped_persistent')
  assert(classifyMappedWaterPersistence({
    sourceSlug: 'usfws-nwi', featureKind: 'wetland',
    properties: { water_regime_name: 'Seasonally Flooded' },
  }) === 'mapped_seasonal')
  assert(classifyMappedWaterPersistence({
    sourceSlug: 'usfws-nwi', featureKind: 'wetland',
    properties: { water_regime_name: 'Temporary Flooded' },
  }) === 'mapped_temporary')
})

Deno.test('3DHP geometry does not invent persistence', () => {
  for (const featureKind of ['flowline','waterbody']) {
    assert(classifyMappedWaterPersistence({
      sourceSlug: 'usgs-3dhp', featureKind,
      properties: { feature_type: 'Lake' },
    }) === 'mapped_unknown_persistence')
  }
})

Deno.test('generic or missing NWI regime remains unknown persistence', () => {
  assert(classifyMappedWaterPersistence({
    sourceSlug: 'usfws-nwi', featureKind: 'wetland',
    properties: { wetland_type: 'Riverine' },
  }) === 'mapped_unknown_persistence')
})

Deno.test('surface-water context requires current observations to be date exact', () => {
  const sha = 'a'.repeat(64)
  const value = {
    schema: FARM_WATCH_SURFACE_WATER_STATE_PRODUCT.outputSchemaVersion,
    method: FARM_WATCH_SURFACE_WATER_STATE_PRODUCT.algorithmVersion,
    evidence_class: 'deterministic_derived',
    as_of_date: '2026-09-22',
    mapped_features: [{
      feature_key: 'usgs-3dhp:flowline:abc',
      source_slug: 'usgs-3dhp',
      feature_kind: 'flowline',
      mapped_persistence_state: 'mapped_unknown_persistence',
      current_presence: {
        state: 'observed_present',
        evidence_class: 'operator_field_observation',
        observed_date: '2026-09-21',
      },
    }],
    dynamic_wetness_context: {
      qualitative_wetness_state: 'not_classified',
      precipitation: { state: 'proxy' },
      drought: { state: 'known' },
      stream: { state: 'proxy' },
      rootzone_soil_moisture: { state: 'proxy' },
    },
    dem_drainage: {
      status: 'available',
      state: 'geometry_only',
      materialization_identity_sha256: sha,
      artifact_sha256: sha,
      water_presence_inferred: false,
    },
    source_fingerprint: {},
    source_fingerprint_sha256: sha,
    scoring_performed: false,
    behavioral_inference_performed: false,
    deer_water_preference_inferred: false,
  }
  assert(!validateFarmWatchSurfaceWaterStateContext(value))
  value.mapped_features[0].current_presence.observed_date = '2026-09-22'
  assert(validateFarmWatchSurfaceWaterStateContext(value))
})

Deno.test('D8 drainage must remain geometry-only', () => {
  const encoded = JSON.stringify(FARM_WATCH_SURFACE_WATER_STATE_PRODUCT)
  assert(encoded.includes('geometry_only'))
  for (const forbidden of ['deer_water_score','water_preference','attraction_score']) {
    assert(!encoded.includes(forbidden))
  }
})
