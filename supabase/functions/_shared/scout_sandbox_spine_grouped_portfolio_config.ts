export const SCOUT_SPINE_GROUPED_PORTFOLIO_TYPES = [
  'bridge_agency_portfolio',
  'railroad_crossing_network',
  'construction_contractor_portfolio',
  'telecom_registration_portfolio',
] as const

export type ScoutSpineGroupedPortfolioType = typeof SCOUT_SPINE_GROUPED_PORTFOLIO_TYPES[number]
export type ScoutSpineGroupedPortfolioConfig = Readonly<{
  label: string
  sourceKind: string
  accountName: string
  groupKind: string
  relationshipLabel: string
  geographicLabel: string
  statusLabel: string
  markerSemantics: string
  minZoom: number
  maxZoom: number
  tileRange: Readonly<{ z:number; minX:number; maxX:number; minY:number; maxY:number }>
  whyInvestigate: string
  guardrail: string
}>

export const SCOUT_SPINE_GROUPED_PORTFOLIO_CONFIG: Record<ScoutSpineGroupedPortfolioType, ScoutSpineGroupedPortfolioConfig> = {
  bridge_agency_portfolio: {
    label: 'Louisville Metro Public Works bridge portfolio',
    sourceKind: 'bridge',
    accountName: 'Louisville Metro Department of Public Works',
    groupKind: 'agency_asset_portfolio',
    relationshipLabel: 'resolved transportation-agency relationship on current bridge evidence',
    geographicLabel: 'Louisville / Jefferson County, Kentucky',
    statusLabel: 'Bridge agency portfolio signal',
    markerSemantics: 'documented bridge source points grouped by resolved transportation-agency relationship; no ownership polygon, access envelope, or structural judgment implied',
    minZoom: 7, maxZoom: 12,
    tileRange: { z:9, minX:133, maxX:135, minY:196, maxY:197 },
    whyInvestigate: 'Use the grouped condition and inspection evidence to prioritize account research across the agency bridge set without treating condition records as procurement or work availability.',
    guardrail: 'Bridge condition and inspection evidence supports qualification only. The resolved buyer relationship is recorded as bridge owner or transportation agency and must not be narrowed to legal ownership without separate evidence. Scout is not making a structural-engineering determination or asserting procurement, access, buyer intent, or work availability.',
  },
  railroad_crossing_network: {
    label: 'Louisville & Indiana Railroad crossing network',
    sourceKind: 'rail_crossing_context',
    accountName: 'Louisville & Indiana Railroad Company',
    groupKind: 'railroad_crossing_network',
    relationshipLabel: 'resolved railroad relationship on current crossing evidence',
    geographicLabel: 'Louisville-to-Indianapolis corridor crossing evidence',
    statusLabel: 'Railroad crossing network signal',
    markerSemantics: 'documented FRA crossing points grouped by resolved railroad relationship; points are not connected into inferred track topology or right-of-way',
    minZoom: 7, maxZoom: 10,
    tileRange: { z:7, minX:32, maxX:34, minY:48, maxY:49 },
    whyInvestigate: 'Use crossing traffic, train-movement, protection, and incident-history context to prioritize account and inspection research across the documented crossing set.',
    guardrail: 'FRA crossing records support account and inspection research only. Point membership does not define railroad property, track topology, right-of-way, safe operating airspace, maintenance need, access permission, procurement, or authorization to work near rail operations.',
  },
  construction_contractor_portfolio: {
    label: 'Miranda Construction project portfolio',
    sourceKind: 'construction_window',
    accountName: 'Miranda Construction LLC',
    groupKind: 'contractor_project_portfolio',
    relationshipLabel: 'permit-named contractor relationship on current construction evidence',
    geographicLabel: 'Louisville / Jefferson County construction projects',
    statusLabel: 'Contractor project portfolio signal',
    markerSemantics: 'permit-derived project points grouped by resolved contractor relationship; no site polygon, project-control boundary, access area, or field-progress claim implied',
    minZoom: 7, maxZoom: 12,
    tileRange: { z:10, minX:267, maxX:269, minY:393, maxY:394 },
    whyInvestigate: 'Use the deduplicated permit-derived project set to research repeat account potential and project timing without converting permit status into field-observed progress or buyer intent.',
    guardrail: 'The relationship is based on contractor naming in permit-derived evidence. It does not prove prime-contract authority, project control, active drone scope, field-observed stage, procurement, site access, buyer intent, or work availability.',
  },
  telecom_registration_portfolio: {
    label: 'The Towers FCC registration portfolio',
    sourceKind: 'telecom_change',
    accountName: 'The Towers, LLC',
    groupKind: 'telecom_registration_portfolio',
    relationshipLabel: 'FCC-record owner/operator relationship on current registration evidence',
    geographicLabel: 'Kentucky / Indiana FCC ASR registration evidence',
    statusLabel: 'Telecom registration portfolio signal',
    markerSemantics: 'exact FCC ASR registration points grouped by resolved registered owner/operator relationship; no service radius, guy-wire footprint, ownership polygon, or access envelope implied',
    minZoom: 7, maxZoom: 10,
    tileRange: { z:7, minX:32, maxX:34, minY:48, maxY:49 },
    whyInvestigate: 'Use recent registration and construction timing as account-qualification context while keeping raw FCC status codes descriptive and unresolved unless separately decoded from authoritative evidence.',
    guardrail: 'FCC registration and recent-construction records are qualifying signals only. The buyer role is registered owner or operator and must not be narrowed further without separate evidence. Scout is not asserting an inspection need, procurement, access, service radius, ownership boundary, guy-wire footprint, buyer intent, or work availability.',
  },
}

export function isScoutSpineGroupedPortfolioType(value: unknown): value is ScoutSpineGroupedPortfolioType {
  return typeof value === 'string' && (SCOUT_SPINE_GROUPED_PORTFOLIO_TYPES as readonly string[]).includes(value)
}
