export type ScoutSandboxSwpppSiteMap = {
  contract_version: 'swppp_site_map_v1'
  opportunity_type: 'swppp_site'
  candidate_key: string
  site_name: string
  location_label: string
  project_reference: string
  site_point: {
    lon: number
    lat: number
    geometry_type: 'Point'
    semantics: 'authoritative_permit_location_point'
    guardrail: string
  }
  permit: {
    evidence_status: 'active_documented_state_construction_permit'
    status: 'ACTIVE'
    type: 'CONSTRUCTION_STORMWATER'
    category: 'GENERAL_CONSTRUCTION'
    permit_number: string
    registry_id: string
    master_permit_number: string
    issue_date: string
    effective_date: string
    expiration_date: string
    termination_date: null
    documented_total_acres: number
    acreage_semantics: string
  }
  source: {
    slug: 'ohio-epa-npdes-construction'
    name: string
    authority: string
    authority_level: 'state'
    source_native_id: string
    source_url: string
    last_seen_at: string
  }
  buyer: {
    classification: 'unresolved'
    organization_id: null
    guardrail: string
  }
  why_investigate: string
  guardrail: string
}

export type ScoutSandboxSwpppSiteOpportunity = {
  opportunity_type: 'swppp_site'
  name: string
  location_label: string
  evidence_status: 'active_documented_state_construction_permit'
  observed_at: string
  permit_number: string
  permit_status: 'ACTIVE'
  permit_type: 'CONSTRUCTION_STORMWATER'
  permit_effective_date: string
  permit_expiration_date: string
  documented_total_acres: number
  project_reference: string
  buyer_resolvability: 'unresolved'
  why_investigate: string
  guardrail: string
}

function boundedString(value: unknown, maxLength: number) {
  if (typeof value !== 'string') return null
  const text = value.trim()
  return text.length > 0 && text.length <= maxLength ? text : null
}

function boundedNumber(value: unknown, minimum: number, maximum: number) {
  return typeof value === 'number' && Number.isFinite(value) && value >= minimum && value <= maximum
    ? value
    : null
}

function boundedLongitude(value: unknown) {
  return boundedNumber(value, -180, 180)
}

function boundedLatitude(value: unknown) {
  return boundedNumber(value, -90, 90)
}

function record(value: unknown): Record<string, unknown> | null {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null
}

export function normalizeScoutSandboxSwpppSiteMap(value: unknown): ScoutSandboxSwpppSiteMap | null {
  const source = record(value)
  if (!source || source.contract_version !== 'swppp_site_map_v1' || source.opportunity_type !== 'swppp_site') return null

  const sitePoint = record(source.site_point)
  const permit = record(source.permit)
  const sourceInfo = record(source.source)
  const buyer = record(source.buyer)
  if (!sitePoint || !permit || !sourceInfo || !buyer) return null

  const candidateKey = boundedString(source.candidate_key, 160)
  const siteName = boundedString(source.site_name, 200)
  const locationLabel = boundedString(source.location_label, 160)
  const projectReference = boundedString(source.project_reference, 80)
  const lon = boundedLongitude(sitePoint.lon)
  const lat = boundedLatitude(sitePoint.lat)
  const siteGuardrail = boundedString(sitePoint.guardrail, 1000)

  const permitNumber = boundedString(permit.permit_number, 80)
  const registryId = boundedString(permit.registry_id, 80)
  const masterPermitNumber = boundedString(permit.master_permit_number, 80)
  const issueDate = boundedString(permit.issue_date, 40)
  const effectiveDate = boundedString(permit.effective_date, 40)
  const expirationDate = boundedString(permit.expiration_date, 40)
  const documentedTotalAcres = boundedNumber(permit.documented_total_acres, 1, 10_000_000)
  const acreageSemantics = boundedString(permit.acreage_semantics, 1000)

  const sourceName = boundedString(sourceInfo.name, 240)
  const sourceAuthority = boundedString(sourceInfo.authority, 240)
  const sourceNativeId = boundedString(sourceInfo.source_native_id, 240)
  const sourceUrl = boundedString(sourceInfo.source_url, 1000)
  const lastSeenAt = boundedString(sourceInfo.last_seen_at, 80)
  const buyerGuardrail = boundedString(buyer.guardrail, 1000)
  const whyInvestigate = boundedString(source.why_investigate, 1000)
  const guardrail = boundedString(source.guardrail, 1000)

  if (!candidateKey || !siteName || !locationLabel || !projectReference) return null
  if (lon === null || lat === null || sitePoint.geometry_type !== 'Point' || sitePoint.semantics !== 'authoritative_permit_location_point' || !siteGuardrail) return null
  if (permit.evidence_status !== 'active_documented_state_construction_permit' || permit.status !== 'ACTIVE') return null
  if (permit.type !== 'CONSTRUCTION_STORMWATER' || permit.category !== 'GENERAL_CONSTRUCTION' || permit.termination_date !== null) return null
  if (!permitNumber || !registryId || !masterPermitNumber || !issueDate || !effectiveDate || !expirationDate || documentedTotalAcres === null || !acreageSemantics) return null
  if (sourceInfo.slug !== 'ohio-epa-npdes-construction' || sourceInfo.authority_level !== 'state') return null
  if (!sourceName || !sourceAuthority || !sourceNativeId || !sourceUrl || !lastSeenAt) return null
  if (candidateKey !== `swppp_site:${sourceNativeId}`) return null
  if (buyer.classification !== 'unresolved' || buyer.organization_id !== null || !buyerGuardrail) return null
  if (!whyInvestigate || !guardrail) return null

  return {
    contract_version: 'swppp_site_map_v1',
    opportunity_type: 'swppp_site',
    candidate_key: candidateKey,
    site_name: siteName,
    location_label: locationLabel,
    project_reference: projectReference,
    site_point: {
      lon,
      lat,
      geometry_type: 'Point',
      semantics: 'authoritative_permit_location_point',
      guardrail: siteGuardrail,
    },
    permit: {
      evidence_status: 'active_documented_state_construction_permit',
      status: 'ACTIVE',
      type: 'CONSTRUCTION_STORMWATER',
      category: 'GENERAL_CONSTRUCTION',
      permit_number: permitNumber,
      registry_id: registryId,
      master_permit_number: masterPermitNumber,
      issue_date: issueDate,
      effective_date: effectiveDate,
      expiration_date: expirationDate,
      termination_date: null,
      documented_total_acres: documentedTotalAcres,
      acreage_semantics: acreageSemantics,
    },
    source: {
      slug: 'ohio-epa-npdes-construction',
      name: sourceName,
      authority: sourceAuthority,
      authority_level: 'state',
      source_native_id: sourceNativeId,
      source_url: sourceUrl,
      last_seen_at: lastSeenAt,
    },
    buyer: {
      classification: 'unresolved',
      organization_id: null,
      guardrail: buyerGuardrail,
    },
    why_investigate: whyInvestigate,
    guardrail,
  }
}

export function buildScoutSandboxSwpppSiteOpportunity(map: ScoutSandboxSwpppSiteMap): ScoutSandboxSwpppSiteOpportunity {
  return {
    opportunity_type: 'swppp_site',
    name: map.site_name,
    location_label: map.location_label,
    evidence_status: map.permit.evidence_status,
    observed_at: map.source.last_seen_at,
    permit_number: map.permit.permit_number,
    permit_status: map.permit.status,
    permit_type: map.permit.type,
    permit_effective_date: map.permit.effective_date,
    permit_expiration_date: map.permit.expiration_date,
    documented_total_acres: map.permit.documented_total_acres,
    project_reference: map.project_reference,
    buyer_resolvability: map.buyer.classification,
    why_investigate: map.why_investigate,
    guardrail: map.guardrail,
  }
}
