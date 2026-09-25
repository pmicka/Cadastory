import {
  FARM_WATCH_MAST_CAPACITY_PRODUCT,
} from './farm-watch-mast-capacity-contract.ts'

export const FARM_WATCH_MAST_RESOURCE_CONTEXT_PRODUCT = Object.freeze({
  key: 'mast-resource-context',
  algorithmVersion: 'kdfwr-mast-survey-context-v1',
  outputSchemaVersion: 'mast-resource-context-v1',
  evidenceClass: 'deterministic_derived',
  annualProxyEvidenceClass: 'authoritative_regional_proxy',
  operatorObservationKind: 'mast_resource',
  surveyAuthority: 'Kentucky Department of Fish and Wildlife Resources (KDFWR)',
  surveyIndexUrl: 'https://fw.ky.gov/Hunt/Pages/Deer-Hunting-Stats.aspx',
  groupOrder: FARM_WATCH_MAST_CAPACITY_PRODUCT.groupOrder,
  publishedRatingVocabulary: Object.freeze([
    'failure',
    'poor',
    'average',
    'good',
    'bumper',
  ] as const),
  componentStatusVocabulary: Object.freeze([
    'available',
    'stale',
    'unavailable',
  ] as const),
}) 

export const FARM_WATCH_MAST_RESOURCE_CONTEXT_LIMITATIONS = Object.freeze([
  'KDFWR annual mast survey results are authoritative survey evidence at statewide, East, West, or individual survey-site scope. They are not property-specific measurements unless the property itself was surveyed.',
  'Published PBA is the percentage of surveyed trees bearing any mast. It is a presence/absence metric and must not be interpreted as acorn or nut abundance, crop mass, or ground availability.',
  'Published PCA is the estimated percentage of a surveyed tree crown bearing mast. Even PCA does not establish mast availability on the ground at the selected property.',
  'KDFWR notes that mast production can vary substantially among nearby survey sites. Regional or statewide results therefore remain proxies for an unsurveyed property.',
  'KDFWR cautions that American beech production values are uncertain because beechnut viability is not routinely checked with float tests.',
  'Published report ratings are preserved as published rather than recomputed from PBA because report text and historical editions do not present perfectly uniform category-boundary wording.',
  'A prior-year mast survey is never carried forward as current-year mast state. If the requested survey-year report is unavailable, annual mast state is unavailable for that year.',
  'The product keeps modeled mast-species capacity, annual survey proxy, and property field observations separate. It does not multiply them into a food score.',
  'The product performs no deer attraction, movement, selection, bedding, hunting, habitat-quality, or management inference.',
])

export type FarmWatchMastPublishedRating =
  typeof FARM_WATCH_MAST_RESOURCE_CONTEXT_PRODUCT.publishedRatingVocabulary[number]

function sha(value: unknown) {
  return /^[0-9a-f]{64}$/.test(String(value || ''))
}

function validGroupResult(value: any) {
  const rating = String(value?.rating || '').toLowerCase()
  return Boolean(
    Number.isInteger(Number(value?.trees_surveyed)) &&
    Number(value?.trees_surveyed) > 0 &&
    Number.isFinite(Number(value?.pba_pct)) &&
    Number(value?.pba_pct) >= 0 &&
    Number(value?.pba_pct) <= 100 &&
    FARM_WATCH_MAST_RESOURCE_CONTEXT_PRODUCT.publishedRatingVocabulary.includes(
      rating as FarmWatchMastPublishedRating,
    )
  )
}

export function validateFarmWatchMastResourceContext(value: any) {
  const p = FARM_WATCH_MAST_RESOURCE_CONTEXT_PRODUCT
  if (
    value?.schema !== p.outputSchemaVersion ||
    value?.method !== p.algorithmVersion ||
    value?.evidence_class !== p.evidenceClass ||
    !Number.isInteger(Number(value?.survey_year)) ||
    Number(value?.survey_year) < 2007 ||
    !value?.mast_capacity ||
    !value?.annual_mast_proxy ||
    !Array.isArray(value?.property_observations) ||
    !value?.source_fingerprint ||
    !sha(value?.source_fingerprint_sha256) ||
    value?.scoring_performed !== false ||
    value?.behavioral_inference_performed !== false ||
    value?.deer_mast_response_inferred !== false
  ) return false

  if (!p.componentStatusVocabulary.includes(value.mast_capacity.status)) return false
  if (!p.componentStatusVocabulary.includes(value.annual_mast_proxy.status)) return false

  if (value.mast_capacity.status === 'available') {
    if (
      value.mast_capacity.product_kind !== 'mast-capacity' ||
      !sha(value.mast_capacity.identity_sha256) ||
      !sha(value.mast_capacity.artifact_sha256)
    ) return false
  }

  const annual = value.annual_mast_proxy
  if (annual.status === 'available') {
    if (
      Number(annual.survey_year) !== Number(value.survey_year) ||
      annual.evidence_class !== p.annualProxyEvidenceClass ||
      typeof annual.report_url !== 'string' ||
      !/^\d{4}-\d{2}-\d{2}$/.test(String(annual.publication_date || '')) ||
      !annual.statewide?.groups
    ) return false

    for (const group of p.groupOrder) {
      if (!validGroupResult(annual.statewide.groups[group])) return false
    }

    if (annual.regional?.groups) {
      if (!['east','west'].includes(String(annual.regional.region || ''))) return false
      for (const group of p.groupOrder) {
        if (!validGroupResult(annual.regional.groups[group])) return false
      }
    }
  } else {
    if (annual.applied_prior_year === true) return false
    if (annual.statewide?.groups || annual.regional?.groups) return false
  }

  return true
}

export function validateFarmWatchMastResourceContextResponse(value: any) {
  if (!['available','partial','unavailable','missing','stale'].includes(String(value?.status || ''))) {
    return false
  }
  if (value?.status === 'missing' || value?.status === 'stale') return value?.context == null
  if (!validateFarmWatchMastResourceContext(value?.context)) return false
  const identity = value?.identity
  return Boolean(
    identity &&
    sha(identity.boundary_sha256) &&
    sha(identity.source_signature_sha256) &&
    sha(identity.identity_sha256) &&
    identity.algorithm_version === FARM_WATCH_MAST_RESOURCE_CONTEXT_PRODUCT.algorithmVersion &&
    identity.output_schema_version === FARM_WATCH_MAST_RESOURCE_CONTEXT_PRODUCT.outputSchemaVersion
  )
}
