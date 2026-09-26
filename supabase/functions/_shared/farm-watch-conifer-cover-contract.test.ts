import {
  FARM_WATCH_CONIFER_COVER_PRODUCT,
  coniferStudyClass,
  validateFarmWatchConiferCoverContext,
} from './farm-watch-conifer-cover-contract.ts'

function assert(condition: unknown, message = 'assertion failed'): asserts condition {
  if (!condition) throw new Error(message)
}

function domain(overrides: Record<string, unknown> = {}) {
  return {
    status: 'available',
    domain_cell_count: 100,
    valid_pair_cell_count: 100,
    valid_pair_coverage_ratio: 1,
    study_availability: {
      moderately_dense_conifer: { cell_count: 10, percent_of_valid_habitat: 10 },
      dense_conifer: { cell_count: 20, percent_of_valid_habitat: 20 },
      other: { cell_count: 70, percent_of_valid_habitat: 70 },
    },
    diagnostics: {
      open_conifer_cell_count: 4,
      mixed_forest_cell_count: 12,
    },
    ...overrides,
  }
}

function context(): any {
  return {
    schema: FARM_WATCH_CONIFER_COVER_PRODUCT.outputSchemaVersion,
    method: FARM_WATCH_CONIFER_COVER_PRODUCT.algorithmVersion,
    evidence_state: 'proxy',
    measurement_alignment: 'calibrated_proxy',
    source_reconciliation: {
      common_source_year: 2024,
      landcover: { slug: 'usgs-annual-nlcd-land-cover' },
      canopy: { slug: 'nlcd-tree-canopy-cover-2025' },
    },
    raster_support: { pixel_width_m: 30, pixel_height_m: 30 },
    domains: {
      property: domain(),
      local_500m: domain(),
      landscape_1500m: domain(),
      broad_3000m: domain(),
    },
    deer_inference_performed: false,
    coefficient_transfer_performed: false,
    scoring_performed: false,
  }
}

Deno.test('M09 classification preserves source 40 and 70 percent closure thresholds', () => {
  assert(coniferStudyClass(42, 39) === 'other')
  assert(coniferStudyClass(42, 40) === 'moderately_dense_conifer')
  assert(coniferStudyClass(42, 69) === 'moderately_dense_conifer')
  assert(coniferStudyClass(42, 70) === 'dense_conifer')
  assert(coniferStudyClass(42, 100) === 'dense_conifer')
})

Deno.test('M09 never promotes Mixed Forest or non-evergreen classes into conifer bins', () => {
  assert(coniferStudyClass(43, 100) === 'other')
  assert(coniferStudyClass(41, 100) === 'other')
  assert(coniferStudyClass(52, 100) === 'other')
})

Deno.test('M09 context requires proxy semantics, exact domains, and neutral evidence flags', () => {
  const value = context()
  assert(validateFarmWatchConiferCoverContext(value))
  assert(!validateFarmWatchConiferCoverContext({ ...value, evidence_state: 'available' }))
  assert(!validateFarmWatchConiferCoverContext({ ...value, measurement_alignment: 'derived_equivalent' }))
  assert(!validateFarmWatchConiferCoverContext({ ...value, deer_inference_performed: true }))
  assert(!validateFarmWatchConiferCoverContext({ ...value, coefficient_transfer_performed: true }))
  assert(!validateFarmWatchConiferCoverContext({ ...value, scoring_performed: true }))
})

Deno.test('M09 study availability counts must partition all valid paired cells', () => {
  const value = context()
  value.domains.broad_3000m.study_availability.other.cell_count = 69
  assert(!validateFarmWatchConiferCoverContext(value))
})

Deno.test('M09 study availability percentages must sum to 100 percent', () => {
  const value = context()
  value.domains.local_500m.study_availability.other.percent_of_valid_habitat = 69.9
  assert(!validateFarmWatchConiferCoverContext(value))
})
