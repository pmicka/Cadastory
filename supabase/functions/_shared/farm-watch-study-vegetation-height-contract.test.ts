import {
  FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT,
  studyVegetationHeightSourceSignature,
  validateStudyVegetationHeightArtifact,
} from './farm-watch-study-vegetation-height-contract.ts'

function assert(condition: unknown, message = 'assertion failed'): asserts condition {
  if (!condition) throw new Error(message)
}

function b64(bytes: number[]) {
  return btoa(String.fromCharCode(...bytes))
}

function artifact() {
  return {
    schema: FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.outputSchemaVersion,
    method: FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.algorithmVersion,
    status: 'available',
    evidence_class: 'deterministic_derived',
    source_collection: FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.sourceCollection,
    source_plan_artifact_sha256: 'a'.repeat(64),
    processing_item_ids: ['phase3-a'],
    native_crs: FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.nativeCrs,
    height_unit: 'm',
    cell_meters: 1.2,
    encoding: FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.heightEncoding,
    domain: {
      radius_m: 500,
      identity_sha256: 'b'.repeat(64),
      algorithm_version: 'domain-v1',
      output_schema_version: 'domain-schema-v1',
      barrier_aware: true,
    },
    grid: {
      bbox: [0, 0, 4.8, 1.2],
      width: 4,
      height: 1,
      cell_meters: 1.2,
      encoding: FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.heightEncoding,
      height_cm_u16_base64: b64([0, 0, 100, 0, 200, 0, 44, 1]),
      support_u8_base64: b64([1, 1, 2, 0]),
    },
    summary: {
      domain: { cell_count: 4, valid_cell_count: 3 },
      property: { cell_count: 2, valid_cell_count: 2 },
      local_ring: { cell_count: 2, valid_cell_count: 1 },
    },
    processing_summary: {
      first_return_point_count: 20,
      ground_point_count: 10,
    },
    processing_source_fingerprint: { items: [{ id: 'phase3-a' }] },
  }
}

Deno.test('study vegetation-height source signature binds domain and published support', () => {
  const a = studyVegetationHeightSourceSignature({
    landscapeDomainIdentitySha256: 'a'.repeat(64),
    landscapeDomainAlgorithmVersion: 'barrier-aware-v1',
  })
  const b = studyVegetationHeightSourceSignature({
    landscapeDomainIdentitySha256: 'b'.repeat(64),
    landscapeDomainAlgorithmVersion: 'barrier-aware-v1',
  })
  assert(a !== b)
  assert(a.includes('cell_m=1.2'))
  assert(a.includes('first_return=LAS_ReturnNumber_1'))
  assert(a.includes('height=first_return_minus_ground'))
  assert(a.includes('qa=negative_raw_height_magnitude_and_output_grid_support_v1'))
  assert(a.includes('support_flags=available|first_filled|negative_clamped|ground_direct_v1'))
})

Deno.test('study vegetation-height artifact validates encoded grid lengths', () => {
  const value = artifact()
  assert(validateStudyVegetationHeightArtifact(value))
  assert(!validateStudyVegetationHeightArtifact({
    ...value,
    grid: {
      ...value.grid,
      height_cm_u16_base64: b64([0, 0]),
    },
  }))
})

Deno.test('study vegetation-height product remains neutral physical evidence', () => {
  const encoded = JSON.stringify(FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT)
  for (const forbidden of ['deer_score', 'habitat_score', 'bedding_score', 'movement_score']) {
    assert(!encoded.includes(forbidden))
  }
})
