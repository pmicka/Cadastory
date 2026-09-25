import {
  FARM_WATCH_MAST_RESOURCE_CONTEXT_PRODUCT,
  validateFarmWatchMastResourceContext,
} from './farm-watch-mast-resource-context-contract.ts'
import {
  FARM_WATCH_MAST_CAPACITY_PRODUCT,
} from './farm-watch-mast-capacity-contract.ts'

function assert(condition: unknown, message = 'assertion failed'): asserts condition {
  if (!condition) throw new Error(message)
}

function group(rating = 'good') {
  return {
    trees_surveyed: 100,
    pca_median_pct: 10,
    pca_iqr_low_pct: 0,
    pca_iqr_high_pct: 30,
    pba_pct: 65,
    rating,
  }
}

function base() {
  const sha = 'a'.repeat(64)
  return {
    schema: FARM_WATCH_MAST_RESOURCE_CONTEXT_PRODUCT.outputSchemaVersion,
    method: FARM_WATCH_MAST_RESOURCE_CONTEXT_PRODUCT.algorithmVersion,
    evidence_class: FARM_WATCH_MAST_RESOURCE_CONTEXT_PRODUCT.evidenceClass,
    survey_year: 2025,
    mast_capacity: {
      status: 'available',
      product_kind: 'mast-capacity',
      identity_sha256: sha,
      artifact_sha256: sha,
    },
    annual_mast_proxy: {
      status: 'available',
      evidence_class: FARM_WATCH_MAST_RESOURCE_CONTEXT_PRODUCT.annualProxyEvidenceClass,
      survey_year: 2025,
      report_url: 'https://fw.ky.gov/Hunt/Documents/2025-mast-report.pdf',
      publication_date: '2025-09-29',
      statewide: {
        groups: {
          white_oak: group('good'),
          red_oak: group('good'),
          hickory: group('average'),
          beech: group('good'),
        },
      },
      regional: {
        region: 'west',
        groups: {
          white_oak: group('good'),
          red_oak: group('good'),
          hickory: group('average'),
          beech: group('average'),
        },
      },
    },
    property_observations: [],
    source_fingerprint: {},
    source_fingerprint_sha256: sha,
    scoring_performed: false,
    behavioral_inference_performed: false,
    deer_mast_response_inferred: false,
  }
}

Deno.test('Batch 5B uses the same four mast groups as Batch 5A', () => {
  assert(
    JSON.stringify(FARM_WATCH_MAST_RESOURCE_CONTEXT_PRODUCT.groupOrder) ===
      JSON.stringify(FARM_WATCH_MAST_CAPACITY_PRODUCT.groupOrder),
  )
})

Deno.test('available exact-year annual mast proxy validates', () => {
  assert(validateFarmWatchMastResourceContext(base()))
})

Deno.test('prior-year mast ratings cannot be carried forward as current state', () => {
  const value = base()
  value.survey_year = 2026
  value.annual_mast_proxy = {
    status: 'unavailable',
    requested_survey_year: 2026,
    latest_available_survey_year: 2025,
    applied_prior_year: false,
  } as any
  assert(validateFarmWatchMastResourceContext(value))

  value.annual_mast_proxy.applied_prior_year = true
  assert(!validateFarmWatchMastResourceContext(value))
})

Deno.test('unavailable annual state cannot smuggle prior-year group results', () => {
  const value = base()
  value.survey_year = 2026
  value.annual_mast_proxy = {
    status: 'unavailable',
    requested_survey_year: 2026,
    latest_available_survey_year: 2025,
    applied_prior_year: false,
    statewide: {
      groups: base().annual_mast_proxy.statewide.groups,
    },
  } as any
  assert(!validateFarmWatchMastResourceContext(value))
})

Deno.test('mast resource contract contains no composite food or deer score', () => {
  const encoded = JSON.stringify(FARM_WATCH_MAST_RESOURCE_CONTEXT_PRODUCT)
  for (const forbidden of ['food_score','mast_score','deer_score','attraction_score']) {
    assert(!encoded.includes(forbidden))
  }
})
