export type ScoutDealershipPortfolioPoint =
  | { type: 'Point'; coordinates: [number, number] }
  | { type: 'unresolved' }

export type ScoutDealershipPortfolioResolutionState =
  | 'single_building_resolved'
  | 'multi_building_resolved'
  | 'unresolved'

export type ScoutDealershipPortfolioMember = {
  id: string
  name: string
  address: string
  city: string
  state_code: string
  brands: string[]
  point: ScoutDealershipPortfolioPoint
  resolution_state: ScoutDealershipPortfolioResolutionState
  resolved_building_count: number
  link_confidence: number | null
  within_pilot_radius: boolean
  observed_at: string
}

export type ScoutSandboxDealershipPortfolioMap = {
  contract_version: 'dealership_group_portfolio_map_v1'
  opportunity_type: 'dealership_group_portfolio'
  group_kind: 'portfolio'
  account_name: string
  organization_id: string
  scope: 'documented_operating_roster'
  source_slug: 'don-franklin-auto-locations'
  relationship: 'operates'
  target_kind: 'site_member'
  map_semantics: 'documented_operating_site_portfolio'
  evidence_boundary: 'first-party dealership roster plus resolved building crosswalks'
  generated_at: string
  observed_at: string
  member_count: number
  resolved_member_count: number
  resolved_building_count: number
  contact_route_available: boolean
  operations_route_available: boolean
  procurement_route_available: boolean
  vendor_route_proven: boolean
  current_need_scan_complete: boolean
  bounds: { west: number; south: number; east: number; north: number }
  members: ScoutDealershipPortfolioMember[]
  guardrail: string
}

export type ScoutSandboxDealershipPortfolioOpportunity = {
  opportunity_type: 'dealership_group_portfolio'
  name: string
  member_count: number
  resolved_member_count: number
  resolved_building_count: number
  unresolved_member_count: number
  observed_at: string
  contact_route_available: boolean
  operations_route_available: boolean
  procurement_route_available: boolean
  vendor_route_proven: boolean
  current_need_scan_complete: boolean
  map_semantics: 'documented_operating_site_portfolio'
  evidence_boundary: 'first-party dealership roster plus resolved building crosswalks'
  why_investigate: string
  guardrail: string
}

const DEALERSHIP_PORTFOLIO_GUARDRAIL = 'This is a documented operating dealership roster and building-resolution context, not proof of current exterior-cleaning need or centralized procurement. Resolved site points are derived from matched building records; unresolved roster members are not mapped. Confirm facilities ownership, vendor authority, service scope, access, and current need before outreach.'

function cleanString(value: unknown, maxLength = 1000) {
  if (typeof value !== 'string') return null
  const text = value.trim()
  return text.length > 0 && text.length <= maxLength ? text : null
}

function cleanBoolean(value: unknown) {
  return typeof value === 'boolean' ? value : null
}

function cleanInteger(value: unknown, minimum: number, maximum: number) {
  return typeof value === 'number' && Number.isInteger(value) && value >= minimum && value <= maximum
    ? value
    : null
}

function cleanNumber(value: unknown, minimum: number, maximum: number) {
  return typeof value === 'number' && Number.isFinite(value) && value >= minimum && value <= maximum
    ? value
    : null
}

function cleanCoordinate(value: unknown, minimum: number, maximum: number) {
  return typeof value === 'number' && Number.isFinite(value) && value >= minimum && value <= maximum
    ? value
    : null
}

function normalizeTimestamp(value: unknown) {
  const text = cleanString(value, 80)
  if (!text) return null
  const date = new Date(text)
  return Number.isNaN(date.valueOf()) ? null : date.toISOString()
}

function normalizePoint(value: unknown): ScoutDealershipPortfolioPoint | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null
  const point = value as Record<string, unknown>
  if (point.type === 'unresolved') return { type: 'unresolved' }
  if (point.type !== 'Point' || !Array.isArray(point.coordinates) || point.coordinates.length !== 2) return null
  const lon = cleanCoordinate(point.coordinates[0], -180, 180)
  const lat = cleanCoordinate(point.coordinates[1], -90, 90)
  if (lon === null || lat === null) return null
  return { type: 'Point', coordinates: [lon, lat] }
}

function normalizeBrands(value: unknown) {
  if (!Array.isArray(value) || value.length > 16) return null
  const brands: string[] = []
  for (const item of value) {
    const brand = cleanString(item, 80)
    if (!brand) return null
    brands.push(brand)
  }
  return brands
}

function normalizeResolutionState(value: unknown): ScoutDealershipPortfolioResolutionState | null {
  return value === 'single_building_resolved' || value === 'multi_building_resolved' || value === 'unresolved'
    ? value
    : null
}

function normalizeMember(value: unknown): ScoutDealershipPortfolioMember | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null
  const source = value as Record<string, unknown>
  const id = cleanString(source.id, 80)
  const name = cleanString(source.name, 200)
  const address = cleanString(source.address, 240)
  const city = cleanString(source.city, 120)
  const stateCode = cleanString(source.state_code, 8)
  const brands = normalizeBrands(source.brands)
  const point = normalizePoint(source.point)
  const resolutionState = normalizeResolutionState(source.resolution_state)
  const resolvedBuildingCount = cleanInteger(source.resolved_building_count, 0, 20)
  const linkConfidenceValue = source.link_confidence
  const linkConfidence = linkConfidenceValue == null ? null : cleanNumber(linkConfidenceValue, 0, 1)
  const withinPilotRadius = cleanBoolean(source.within_pilot_radius)
  const observedAt = normalizeTimestamp(source.observed_at)
  if (!id || !name || !address || !city || !stateCode || !brands || !point || !resolutionState || resolvedBuildingCount === null || withinPilotRadius === null || !observedAt) return null
  if (linkConfidenceValue != null && linkConfidence === null) return null
  if (resolutionState === 'unresolved' && (point.type !== 'unresolved' || resolvedBuildingCount !== 0 || linkConfidence !== null)) return null
  if (resolutionState === 'single_building_resolved' && (point.type !== 'Point' || resolvedBuildingCount !== 1 || linkConfidence === null)) return null
  if (resolutionState === 'multi_building_resolved' && (point.type !== 'Point' || resolvedBuildingCount < 2 || linkConfidence === null)) return null
  return {
    id,
    name,
    address,
    city,
    state_code: stateCode.toUpperCase(),
    brands,
    point,
    resolution_state: resolutionState,
    resolved_building_count: resolvedBuildingCount,
    link_confidence: linkConfidence,
    within_pilot_radius: withinPilotRadius,
    observed_at: observedAt,
  }
}

function latestTimestamp(values: string[]) {
  let latest: { value: string; time: number } | null = null
  for (const value of values) {
    const time = new Date(value).valueOf()
    if (!Number.isFinite(time)) continue
    if (!latest || time > latest.time) latest = { value, time }
  }
  return latest?.value ?? null
}

export function normalizeScoutSandboxDealershipPortfolioMap(value: unknown): ScoutSandboxDealershipPortfolioMap | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null
  const source = value as Record<string, unknown>
  if (source.contract_version !== 'dealership_group_portfolio_map_v1') return null
  const accountName = cleanString(source.account_name, 200)
  const organizationId = cleanString(source.organization_id, 80)
  const generatedAt = normalizeTimestamp(source.generated_at)
  if (!accountName || !organizationId || !generatedAt) return null
  if (source.scope !== 'documented_operating_roster' || source.source_slug !== 'don-franklin-auto-locations' || source.relationship !== 'operates') return null
  if (source.target_kind !== 'site_member' || source.map_semantics !== 'documented_operating_site_portfolio' || source.evidence_boundary !== 'first-party dealership roster plus resolved building crosswalks') return null
  const contactRouteAvailable = cleanBoolean(source.contact_route_available)
  const operationsRouteAvailable = cleanBoolean(source.operations_route_available)
  const procurementRouteAvailable = cleanBoolean(source.procurement_route_available)
  const vendorRouteProven = cleanBoolean(source.vendor_route_proven)
  const currentNeedScanComplete = cleanBoolean(source.current_need_scan_complete)
  if (contactRouteAvailable === null || operationsRouteAvailable === null || procurementRouteAvailable === null || vendorRouteProven === null || currentNeedScanComplete === null) return null
  if (!Array.isArray(source.members) || source.members.length < 1 || source.members.length > 100) return null

  const members: ScoutDealershipPortfolioMember[] = []
  for (const item of source.members) {
    const member = normalizeMember(item)
    if (!member) return null
    members.push(member)
  }

  const resolved = members.filter((member): member is ScoutDealershipPortfolioMember & { point: { type: 'Point'; coordinates: [number, number] } } => member.point.type === 'Point')
  if (resolved.length < 1) return null
  const longitudes = resolved.map((member) => member.point.coordinates[0])
  const latitudes = resolved.map((member) => member.point.coordinates[1])
  const observedAt = latestTimestamp(members.map((member) => member.observed_at))
  if (!observedAt) return null

  return {
    contract_version: 'dealership_group_portfolio_map_v1',
    opportunity_type: 'dealership_group_portfolio',
    group_kind: 'portfolio',
    account_name: accountName,
    organization_id: organizationId,
    scope: 'documented_operating_roster',
    source_slug: 'don-franklin-auto-locations',
    relationship: 'operates',
    target_kind: 'site_member',
    map_semantics: 'documented_operating_site_portfolio',
    evidence_boundary: 'first-party dealership roster plus resolved building crosswalks',
    generated_at: generatedAt,
    observed_at: observedAt,
    member_count: members.length,
    resolved_member_count: resolved.length,
    resolved_building_count: resolved.reduce((total, member) => total + member.resolved_building_count, 0),
    contact_route_available: contactRouteAvailable,
    operations_route_available: operationsRouteAvailable,
    procurement_route_available: procurementRouteAvailable,
    vendor_route_proven: vendorRouteProven,
    current_need_scan_complete: currentNeedScanComplete,
    bounds: {
      west: Math.min(...longitudes),
      south: Math.min(...latitudes),
      east: Math.max(...longitudes),
      north: Math.max(...latitudes),
    },
    members,
    guardrail: DEALERSHIP_PORTFOLIO_GUARDRAIL,
  }
}

export function buildScoutSandboxDealershipPortfolioOpportunity(
  map: ScoutSandboxDealershipPortfolioMap,
): ScoutSandboxDealershipPortfolioOpportunity {
  return {
    opportunity_type: 'dealership_group_portfolio',
    name: map.account_name,
    member_count: map.member_count,
    resolved_member_count: map.resolved_member_count,
    resolved_building_count: map.resolved_building_count,
    unresolved_member_count: map.member_count - map.resolved_member_count,
    observed_at: map.observed_at,
    contact_route_available: map.contact_route_available,
    operations_route_available: map.operations_route_available,
    procurement_route_available: map.procurement_route_available,
    vendor_route_proven: map.vendor_route_proven,
    current_need_scan_complete: map.current_need_scan_complete,
    map_semantics: 'documented_operating_site_portfolio',
    evidence_boundary: 'first-party dealership roster plus resolved building crosswalks',
    why_investigate: 'Treat the account as a portfolio-level exterior-services verification target: confirm whether facilities and vendor decisions are centralized, then prioritize resolved sites only after current exterior condition and access are verified.',
    guardrail: map.guardrail,
  }
}

export function normalizeScoutSandboxDealershipPortfolioOpportunity(value: unknown): ScoutSandboxDealershipPortfolioOpportunity | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null
  const source = value as Record<string, unknown>
  const name = cleanString(source.name, 200)
  const memberCount = cleanInteger(source.member_count, 1, 100)
  const resolvedMemberCount = cleanInteger(source.resolved_member_count, 1, 100)
  const resolvedBuildingCount = cleanInteger(source.resolved_building_count, 1, 200)
  const unresolvedMemberCount = cleanInteger(source.unresolved_member_count, 0, 100)
  const observedAt = normalizeTimestamp(source.observed_at)
  const contactRouteAvailable = cleanBoolean(source.contact_route_available)
  const operationsRouteAvailable = cleanBoolean(source.operations_route_available)
  const procurementRouteAvailable = cleanBoolean(source.procurement_route_available)
  const vendorRouteProven = cleanBoolean(source.vendor_route_proven)
  const currentNeedScanComplete = cleanBoolean(source.current_need_scan_complete)
  const whyInvestigate = cleanString(source.why_investigate, 1000)
  const guardrail = cleanString(source.guardrail, 1600)
  if (source.opportunity_type !== 'dealership_group_portfolio' || !name || memberCount === null || resolvedMemberCount === null || resolvedBuildingCount === null || unresolvedMemberCount === null || !observedAt) return null
  if (contactRouteAvailable === null || operationsRouteAvailable === null || procurementRouteAvailable === null || vendorRouteProven === null || currentNeedScanComplete === null || !whyInvestigate || !guardrail) return null
  if (resolvedMemberCount > memberCount || unresolvedMemberCount !== memberCount - resolvedMemberCount || resolvedBuildingCount < resolvedMemberCount) return null
  if (source.map_semantics !== 'documented_operating_site_portfolio' || source.evidence_boundary !== 'first-party dealership roster plus resolved building crosswalks') return null
  return {
    opportunity_type: 'dealership_group_portfolio',
    name,
    member_count: memberCount,
    resolved_member_count: resolvedMemberCount,
    resolved_building_count: resolvedBuildingCount,
    unresolved_member_count: unresolvedMemberCount,
    observed_at: observedAt,
    contact_route_available: contactRouteAvailable,
    operations_route_available: operationsRouteAvailable,
    procurement_route_available: procurementRouteAvailable,
    vendor_route_proven: vendorRouteProven,
    current_need_scan_complete: currentNeedScanComplete,
    map_semantics: 'documented_operating_site_portfolio',
    evidence_boundary: 'first-party dealership roster plus resolved building crosswalks',
    why_investigate: whyInvestigate,
    guardrail,
  }
}
