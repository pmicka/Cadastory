export type ScoutWaterUtilityPortfolioSignal = {
  id: string
  kind: 'historical_rehab_record'
  observed_at: string
}

export type ScoutWaterUtilityPortfolioPoint =
  | { type: 'Point'; coordinates: [number, number] }
  | { type: 'unresolved' }

export type ScoutWaterUtilityPortfolioMember = {
  id: string
  name: string
  pwsid: string
  point: ScoutWaterUtilityPortfolioPoint
  service_state: 'unverified' | 'documented_not_in_service'
  within_pilot_radius: boolean
  source_modified_at: string
  signals: ScoutWaterUtilityPortfolioSignal[]
}

export type ScoutSandboxWaterUtilityPortfolioMap = {
  contract_version: 'water_utility_portfolio_map_v1'
  opportunity_type: 'water_utility_portfolio'
  group_kind: 'portfolio'
  account_name: string
  organization_id: string
  pwsid: string
  scope: 'documented_roster'
  source_slug: 'ky-kia-water-tanks'
  relationship: 'system_membership'
  target_kind: 'asset_member'
  map_semantics: 'documented_asset_portfolio'
  evidence_boundary: 'linked water-system tank records only'
  generated_at: string
  source_modified_at: string
  member_count: number
  resolved_member_count: number
  bounds: { west: number; south: number; east: number; north: number }
  members: ScoutWaterUtilityPortfolioMember[]
  guardrail: string
}

export type ScoutSandboxWaterUtilityPortfolioOpportunity = {
  opportunity_type: 'water_utility_portfolio'
  name: string
  pwsid: string
  member_count: number
  not_in_service_count: number
  historical_project_signal_count: number
  source_modified_at: string
  map_semantics: 'documented_asset_portfolio'
  evidence_boundary: 'linked water-system tank records only'
  why_investigate: string
  guardrail: string
}

const PORTFOLIO_GUARDRAIL = 'This is a documented water-system asset portfolio, not proof of current service need. Historical rehab records remain historical, documented not-in-service assets are not promoted as active targets, and all other current service states require verification before outreach.'

function cleanString(value: unknown, maxLength = 1000) {
  if (typeof value !== 'string') return null
  const text = value.trim()
  return text.length > 0 && text.length <= maxLength ? text : null
}

function cleanBoolean(value: unknown) {
  return typeof value === 'boolean' ? value : null
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

function normalizeGeneratedAt(source: Record<string, unknown>) {
  const generated = normalizeTimestamp(source.generated_at)
  if (generated) return generated
  const observedOn = cleanString(source.observed_on, 40)
  if (!observedOn) return null
  return normalizeTimestamp(`${observedOn}T00:00:00Z`)
}

function normalizePoint(value: unknown): ScoutWaterUtilityPortfolioPoint | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null
  const point = value as Record<string, unknown>
  if (point.type === 'unresolved') return { type: 'unresolved' }
  if (point.type !== 'Point' || !Array.isArray(point.coordinates) || point.coordinates.length !== 2) return null
  const lon = cleanCoordinate(point.coordinates[0], -180, 180)
  const lat = cleanCoordinate(point.coordinates[1], -90, 90)
  if (lon === null || lat === null) return null
  return { type: 'Point', coordinates: [lon, lat] }
}

function normalizeSignals(value: unknown): ScoutWaterUtilityPortfolioSignal[] | null {
  if (!Array.isArray(value) || value.length > 10) return null
  const signals: ScoutWaterUtilityPortfolioSignal[] = []
  for (const item of value) {
    if (!item || typeof item !== 'object' || Array.isArray(item)) return null
    const signal = item as Record<string, unknown>
    const id = cleanString(signal.id, 160)
    const observedAt = normalizeTimestamp(signal.observed_at)
    if (!id || signal.kind !== 'historical_rehab_record' || !observedAt) return null
    signals.push({ id, kind: 'historical_rehab_record', observed_at: observedAt })
  }
  return signals
}

function normalizeMember(value: unknown): ScoutWaterUtilityPortfolioMember | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null
  const source = value as Record<string, unknown>
  const id = cleanString(source.id, 120)
  const name = cleanString(source.name, 200)
  const pwsid = cleanString(source.pwsid, 40)
  const point = normalizePoint(source.point)
  const withinPilotRadius = cleanBoolean(source.within_pilot_radius)
  const sourceModifiedAt = normalizeTimestamp(source.source_modified_at)
  const signals = normalizeSignals(source.signals)
  if (!id || !name || !pwsid || !point || withinPilotRadius === null || !sourceModifiedAt || !signals) return null
  if (source.service_state !== 'unverified' && source.service_state !== 'documented_not_in_service') return null
  return {
    id,
    name,
    pwsid,
    point,
    service_state: source.service_state,
    within_pilot_radius: withinPilotRadius,
    source_modified_at: sourceModifiedAt,
    signals,
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

export function normalizeScoutSandboxWaterUtilityPortfolioMap(value: unknown): ScoutSandboxWaterUtilityPortfolioMap | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null
  const source = value as Record<string, unknown>
  if (source.contract_version !== 'water_utility_portfolio_map_v1') return null
  const accountName = cleanString(source.account_name, 200)
  const organizationId = cleanString(source.organization_id, 80)
  const pwsid = cleanString(source.pwsid, 40)
  const generatedAt = normalizeGeneratedAt(source)
  if (!accountName || !organizationId || !pwsid || !generatedAt) return null
  if (source.scope !== 'documented_roster' || source.source_slug !== 'ky-kia-water-tanks' || source.relationship !== 'system_membership') return null
  if (!Array.isArray(source.members) || source.members.length < 1 || source.members.length > 100) return null

  const members: ScoutWaterUtilityPortfolioMember[] = []
  for (const item of source.members) {
    const member = normalizeMember(item)
    if (!member || member.pwsid !== pwsid) return null
    members.push(member)
  }

  const resolved = members.filter((member): member is ScoutWaterUtilityPortfolioMember & { point: { type: 'Point'; coordinates: [number, number] } } => member.point.type === 'Point')
  if (resolved.length < 1) return null
  const longitudes = resolved.map((member) => member.point.coordinates[0])
  const latitudes = resolved.map((member) => member.point.coordinates[1])
  const sourceModifiedAt = latestTimestamp(members.map((member) => member.source_modified_at))
  if (!sourceModifiedAt) return null

  return {
    contract_version: 'water_utility_portfolio_map_v1',
    opportunity_type: 'water_utility_portfolio',
    group_kind: 'portfolio',
    account_name: accountName,
    organization_id: organizationId,
    pwsid,
    scope: 'documented_roster',
    source_slug: 'ky-kia-water-tanks',
    relationship: 'system_membership',
    target_kind: 'asset_member',
    map_semantics: 'documented_asset_portfolio',
    evidence_boundary: 'linked water-system tank records only',
    generated_at: generatedAt,
    source_modified_at: sourceModifiedAt,
    member_count: members.length,
    resolved_member_count: resolved.length,
    bounds: {
      west: Math.min(...longitudes),
      south: Math.min(...latitudes),
      east: Math.max(...longitudes),
      north: Math.max(...latitudes),
    },
    members,
    guardrail: PORTFOLIO_GUARDRAIL,
  }
}

export function buildScoutSandboxWaterUtilityPortfolioOpportunity(
  map: ScoutSandboxWaterUtilityPortfolioMap,
): ScoutSandboxWaterUtilityPortfolioOpportunity {
  const notInServiceCount = map.members.filter((member) => member.service_state === 'documented_not_in_service').length
  const historicalProjectSignalCount = map.members.filter((member) => member.signals.some((signal) => signal.kind === 'historical_rehab_record')).length
  return {
    opportunity_type: 'water_utility_portfolio',
    name: map.account_name,
    pwsid: map.pwsid,
    member_count: map.member_count,
    not_in_service_count: notInServiceCount,
    historical_project_signal_count: historicalProjectSignalCount,
    source_modified_at: map.source_modified_at,
    map_semantics: 'documented_asset_portfolio',
    evidence_boundary: 'linked water-system tank records only',
    why_investigate: 'Treat the account as a portfolio-level verification target: confirm current tank service state, maintenance ownership, and procurement route before selecting any individual asset for outreach.',
    guardrail: map.guardrail,
  }
}

export function normalizeScoutSandboxWaterUtilityPortfolioOpportunity(value: unknown): ScoutSandboxWaterUtilityPortfolioOpportunity | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null
  const source = value as Record<string, unknown>
  const name = cleanString(source.name, 200)
  const pwsid = cleanString(source.pwsid, 40)
  const memberCount = typeof source.member_count === 'number' && Number.isInteger(source.member_count) ? source.member_count : null
  const notInServiceCount = typeof source.not_in_service_count === 'number' && Number.isInteger(source.not_in_service_count) ? source.not_in_service_count : null
  const historicalCount = typeof source.historical_project_signal_count === 'number' && Number.isInteger(source.historical_project_signal_count) ? source.historical_project_signal_count : null
  const sourceModifiedAt = normalizeTimestamp(source.source_modified_at)
  const whyInvestigate = cleanString(source.why_investigate, 1000)
  const guardrail = cleanString(source.guardrail, 1600)
  if (source.opportunity_type !== 'water_utility_portfolio' || !name || !pwsid || memberCount === null || notInServiceCount === null || historicalCount === null || !sourceModifiedAt || !whyInvestigate || !guardrail) return null
  if (memberCount < 1 || memberCount > 100 || notInServiceCount < 0 || notInServiceCount > memberCount || historicalCount < 0 || historicalCount > memberCount) return null
  if (source.map_semantics !== 'documented_asset_portfolio' || source.evidence_boundary !== 'linked water-system tank records only') return null
  return {
    opportunity_type: 'water_utility_portfolio',
    name,
    pwsid,
    member_count: memberCount,
    not_in_service_count: notInServiceCount,
    historical_project_signal_count: historicalCount,
    source_modified_at: sourceModifiedAt,
    map_semantics: 'documented_asset_portfolio',
    evidence_boundary: 'linked water-system tank records only',
    why_investigate: whyInvestigate,
    guardrail,
  }
}
