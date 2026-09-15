export type ScoutSchoolDistrictPortfolioPoint = { type: 'Point'; coordinates: [number, number] }

export type ScoutSchoolDistrictPortfolioMember = {
  id: string
  name: string
  address: string
  city: string
  state_code: 'IN'
  zip: string
  point: ScoutSchoolDistrictPortfolioPoint
  school_year: '2024-2025'
  observed_at: string
}

export type ScoutSchoolDistrictCapitalSignal = {
  id: string
  kind: 'district_roof_capital_project'
  project_title: 'Roof Project'
  estimated_cost: number
  start_date_text: string
  end_date_text: string
  plan_year: 2027
  plan_id: '10695'
  plan_submitted_at: string
  extraction_confidence: 'high'
  site_attribution: 'district_only_unresolved'
  observed_at: string
}

export type ScoutSandboxSchoolDistrictPortfolioMap = {
  contract_version: 'school_district_portfolio_map_v1'
  opportunity_type: 'school_district_portfolio'
  group_kind: 'portfolio'
  account_name: 'Scott County School District 2'
  district_key: 'IN-7255'
  nces_district_id: '1810020'
  dlgf_unit_id: '1288'
  dlgf_unit_code: '7255'
  scope: 'documented_public_school_roster'
  facility_source_slug: 'nces-edge-public-schools-2425'
  signal_source_slug: 'indiana-dlgf-school-capital-projects'
  relationship: 'district_membership'
  target_kind: 'school_facility_member'
  map_semantics: 'documented_public_school_facility_portfolio'
  evidence_boundary: 'NCES school facility locations plus district-level DLGF capital-plan signals; capital projects are not attributed to individual schools unless explicitly documented'
  generated_at: string
  observed_at: string
  facility_observed_at: string
  capital_plan_observed_at: string
  member_count: number
  resolved_member_count: number
  bounds: { west: number; south: number; east: number; north: number }
  members: ScoutSchoolDistrictPortfolioMember[]
  capital_signals: ScoutSchoolDistrictCapitalSignal[]
  guardrail: string
}

export type ScoutSandboxSchoolDistrictPortfolioOpportunity = {
  opportunity_type: 'school_district_portfolio'
  name: 'Scott County School District 2'
  district_key: 'IN-7255'
  member_count: number
  observed_at: string
  school_year: '2024-2025'
  roof_project_estimated_cost: number
  roof_project_start_text: string
  roof_project_end_text: string
  roof_project_plan_year: 2027
  project_site_attribution: 'district_only_unresolved'
  map_semantics: 'documented_public_school_facility_portfolio'
  evidence_boundary: 'NCES school facility locations plus district-level DLGF capital-plan signals; capital projects are not attributed to individual schools unless explicitly documented'
  why_investigate: string
  guardrail: string
}

const EVIDENCE_BOUNDARY = 'NCES school facility locations plus district-level DLGF capital-plan signals; capital projects are not attributed to individual schools unless explicitly documented' as const
const GUARDRAIL = 'This map is a documented NCES public-school facility roster for Scott County School District 2. The DLGF capital plan separately documents a district-level Roof Project with a $500,000 estimate and Summer 2027–Summer 2029 timing, but the source does not identify which campus or building is associated with that project. Do not treat any mapped school as the roof-project site, and do not treat the plan as a solicitation, award, current cleaning need, approved vendor route, or proof that work is available.'

function cleanString(value: unknown, maxLength = 1000) { if (typeof value !== 'string') return null; const text = value.trim(); return text.length > 0 && text.length <= maxLength ? text : null }
function cleanNumber(value: unknown, minimum: number, maximum: number) { return typeof value === 'number' && Number.isFinite(value) && value >= minimum && value <= maximum ? value : null }
function normalizeTimestamp(value: unknown) { const text = cleanString(value, 80); if (!text) return null; const date = new Date(text); return Number.isNaN(date.valueOf()) ? null : date.toISOString() }
function latestTimestamp(values: string[]) { let latest: { value: string; time: number } | null = null; for (const value of values) { const time = new Date(value).valueOf(); if (Number.isFinite(time) && (!latest || time > latest.time)) latest = { value, time } } return latest?.value ?? null }

function normalizeMember(value: unknown): ScoutSchoolDistrictPortfolioMember | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null
  const source = value as Record<string, unknown>
  const id = cleanString(source.id, 40), name = cleanString(source.name, 200), address = cleanString(source.address, 240), city = cleanString(source.city, 120), zip = cleanString(source.zip, 16)
  const state = cleanString(source.state_code, 8), schoolYear = cleanString(source.school_year, 20), observedAt = normalizeTimestamp(source.observed_at)
  if (!source.point || typeof source.point !== 'object' || Array.isArray(source.point)) return null
  const point = source.point as Record<string, unknown>
  if (point.type !== 'Point' || !Array.isArray(point.coordinates) || point.coordinates.length !== 2) return null
  const lon = cleanNumber(point.coordinates[0], -180, 180), lat = cleanNumber(point.coordinates[1], -90, 90)
  if (!id || !name || !address || !city || !zip || state?.toUpperCase() !== 'IN' || schoolYear !== '2024-2025' || !observedAt || lon === null || lat === null) return null
  return { id, name, address, city, state_code: 'IN', zip, point: { type: 'Point', coordinates: [lon, lat] }, school_year: '2024-2025', observed_at: observedAt }
}

function normalizeSignal(value: unknown): ScoutSchoolDistrictCapitalSignal | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null
  const source = value as Record<string, unknown>
  const id = cleanString(source.id, 120), title = cleanString(source.project_title, 200), start = cleanString(source.start_date_text, 120), end = cleanString(source.end_date_text, 120)
  const planSubmitted = normalizeTimestamp(source.plan_submitted_at), observedAt = normalizeTimestamp(source.observed_at), cost = cleanNumber(source.estimated_cost, 1, 1_000_000_000)
  if (!id || source.kind !== 'district_roof_capital_project' || title !== 'Roof Project' || cost === null || !start || !end || source.plan_year !== 2027 || source.plan_id !== '10695' || !planSubmitted || source.extraction_confidence !== 'high' || source.site_attribution !== 'district_only_unresolved' || !observedAt) return null
  return { id, kind: 'district_roof_capital_project', project_title: 'Roof Project', estimated_cost: cost, start_date_text: start, end_date_text: end, plan_year: 2027, plan_id: '10695', plan_submitted_at: planSubmitted, extraction_confidence: 'high', site_attribution: 'district_only_unresolved', observed_at: observedAt }
}

export function normalizeScoutSandboxSchoolDistrictPortfolioMap(value: unknown): ScoutSandboxSchoolDistrictPortfolioMap | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null
  const source = value as Record<string, unknown>
  if (source.contract_version !== 'school_district_portfolio_map_v1' || source.account_name !== 'Scott County School District 2' || source.district_key !== 'IN-7255' || source.nces_district_id !== '1810020' || source.dlgf_unit_id !== '1288' || source.dlgf_unit_code !== '7255') return null
  if (source.scope !== 'documented_public_school_roster' || source.facility_source_slug !== 'nces-edge-public-schools-2425' || source.signal_source_slug !== 'indiana-dlgf-school-capital-projects' || source.relationship !== 'district_membership') return null
  const generatedAt = normalizeTimestamp(source.generated_at), facilityObservedAt = normalizeTimestamp(source.facility_observed_at), capitalPlanObservedAt = normalizeTimestamp(source.capital_plan_observed_at)
  if (!generatedAt || !facilityObservedAt || !capitalPlanObservedAt || !Array.isArray(source.members) || source.members.length < 1 || source.members.length > 100 || !Array.isArray(source.capital_signals) || source.capital_signals.length < 1 || source.capital_signals.length > 20) return null
  const members: ScoutSchoolDistrictPortfolioMember[] = []
  const ids = new Set<string>()
  for (const item of source.members) { const member = normalizeMember(item); if (!member || ids.has(member.id)) return null; ids.add(member.id); members.push(member) }
  const signals: ScoutSchoolDistrictCapitalSignal[] = []
  for (const item of source.capital_signals) { const signal = normalizeSignal(item); if (!signal) return null; signals.push(signal) }
  const roofSignals = signals.filter((signal) => signal.kind === 'district_roof_capital_project')
  if (roofSignals.length !== 1) return null
  const lons = members.map((member) => member.point.coordinates[0]), lats = members.map((member) => member.point.coordinates[1])
  const observedAt = latestTimestamp([facilityObservedAt, capitalPlanObservedAt, ...members.map((member) => member.observed_at), ...signals.map((signal) => signal.observed_at)])
  if (!observedAt) return null
  return {
    contract_version: 'school_district_portfolio_map_v1', opportunity_type: 'school_district_portfolio', group_kind: 'portfolio', account_name: 'Scott County School District 2', district_key: 'IN-7255', nces_district_id: '1810020', dlgf_unit_id: '1288', dlgf_unit_code: '7255', scope: 'documented_public_school_roster', facility_source_slug: 'nces-edge-public-schools-2425', signal_source_slug: 'indiana-dlgf-school-capital-projects', relationship: 'district_membership', target_kind: 'school_facility_member', map_semantics: 'documented_public_school_facility_portfolio', evidence_boundary: EVIDENCE_BOUNDARY, generated_at: generatedAt, observed_at: observedAt, facility_observed_at: facilityObservedAt, capital_plan_observed_at: capitalPlanObservedAt, member_count: members.length, resolved_member_count: members.length, bounds: { west: Math.min(...lons), south: Math.min(...lats), east: Math.max(...lons), north: Math.max(...lats) }, members, capital_signals: signals, guardrail: GUARDRAIL,
  }
}

export function buildScoutSandboxSchoolDistrictPortfolioOpportunity(map: ScoutSandboxSchoolDistrictPortfolioMap): ScoutSandboxSchoolDistrictPortfolioOpportunity {
  const roof = map.capital_signals.find((signal) => signal.kind === 'district_roof_capital_project')!
  return { opportunity_type: 'school_district_portfolio', name: 'Scott County School District 2', district_key: 'IN-7255', member_count: map.member_count, observed_at: map.observed_at, school_year: '2024-2025', roof_project_estimated_cost: roof.estimated_cost, roof_project_start_text: roof.start_date_text, roof_project_end_text: roof.end_date_text, roof_project_plan_year: 2027, project_site_attribution: 'district_only_unresolved', map_semantics: 'documented_public_school_facility_portfolio', evidence_boundary: EVIDENCE_BOUNDARY, why_investigate: 'Scout has a defensible district-level portfolio context: six documented NCES school facilities and a high-confidence DLGF capital-plan Roof Project estimated at $500,000 for Summer 2027 through Summer 2029. Use the capital signal to qualify the district account and investigate facilities, procurement, and current exterior needs; do not assign the roof project to a mapped campus without new evidence.', guardrail: map.guardrail }
}

export function normalizeScoutSandboxSchoolDistrictPortfolioOpportunity(value: unknown): ScoutSandboxSchoolDistrictPortfolioOpportunity | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null
  const source = value as Record<string, unknown>
  const observedAt = normalizeTimestamp(source.observed_at), count = cleanNumber(source.member_count, 1, 100), cost = cleanNumber(source.roof_project_estimated_cost, 1, 1_000_000_000), start = cleanString(source.roof_project_start_text, 120), end = cleanString(source.roof_project_end_text, 120), why = cleanString(source.why_investigate, 1400), guardrail = cleanString(source.guardrail, 2000)
  if (source.opportunity_type !== 'school_district_portfolio' || source.name !== 'Scott County School District 2' || source.district_key !== 'IN-7255' || count === null || !Number.isInteger(count) || !observedAt || source.school_year !== '2024-2025' || cost === null || !start || !end || source.roof_project_plan_year !== 2027 || source.project_site_attribution !== 'district_only_unresolved' || source.map_semantics !== 'documented_public_school_facility_portfolio' || source.evidence_boundary !== EVIDENCE_BOUNDARY || !why || !guardrail) return null
  return { opportunity_type: 'school_district_portfolio', name: 'Scott County School District 2', district_key: 'IN-7255', member_count: count, observed_at: observedAt, school_year: '2024-2025', roof_project_estimated_cost: cost, roof_project_start_text: start, roof_project_end_text: end, roof_project_plan_year: 2027, project_site_attribution: 'district_only_unresolved', map_semantics: 'documented_public_school_facility_portfolio', evidence_boundary: EVIDENCE_BOUNDARY, why_investigate: why, guardrail }
}
