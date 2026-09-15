export const SCOUT_SANDBOX_RESOURCE_VERSION = 35 as const
export const SCOUT_SANDBOX_RESOURCE_URI = `ui://scout/component-sandbox/v${SCOUT_SANDBOX_RESOURCE_VERSION}` as const
export const SCOUT_SANDBOX_EMBEDDED_RASTER_COMPATIBILITY_MIN_VERSION = 22 as const
export const SCOUT_SANDBOX_MAX_EMBEDDED_RASTER_TILES = 40 as const

export const SCOUT_SANDBOX_BASE_OPPORTUNITY_TYPES = [
  'premium_exterior',
  'water_tank',
  'swppp_site',
] as const

export const SCOUT_SANDBOX_PORTFOLIO_TYPES = [
  'water_utility_portfolio',
  'dealership_group_portfolio',
  'hotel_management_portfolio',
] as const

export const SCOUT_SANDBOX_OPPORTUNITY_TYPES = [
  ...SCOUT_SANDBOX_BASE_OPPORTUNITY_TYPES,
  ...SCOUT_SANDBOX_PORTFOLIO_TYPES,
] as const

export type ScoutSandboxOpportunityType = typeof SCOUT_SANDBOX_OPPORTUNITY_TYPES[number]
export type ScoutSandboxPortfolioType = typeof SCOUT_SANDBOX_PORTFOLIO_TYPES[number]
export type ScoutSandboxMapKind = 'single_site' | 'portfolio'
export type ScoutSandboxHostNormalizationRule = 'strict' | 'unresolved_link_confidence_null_elision'

export type ScoutSandboxRasterFrameSize = Readonly<{ width: number; height: number }>
export type ScoutSandboxTileRange = Readonly<{ z: number; minX: number; maxX: number; minY: number; maxY: number }>
export type ScoutSandboxTileCenter = Readonly<{ lon: number; lat: number; minZoom: number; maxZoom: number; toleranceDegrees: number }>

export type ScoutSandboxOpportunityManifestEntry = Readonly<{
  slug: ScoutSandboxOpportunityType
  label: string
  mapKind: ScoutSandboxMapKind
  markerSemantics: string
  hostNormalization: ScoutSandboxHostNormalizationRule
  rasterFrames: readonly ScoutSandboxRasterFrameSize[]
  tileRanges: readonly ScoutSandboxTileRange[]
  tileCenters: readonly ScoutSandboxTileCenter[]
}>

export type ScoutSandboxPortfolioManifestEntry = ScoutSandboxOpportunityManifestEntry & Readonly<{
  slug: ScoutSandboxPortfolioType
  rpc: string
  contractVersion: string
}>

const singleSiteCenter = (
  lon: number,
  lat: number,
): readonly ScoutSandboxTileCenter[] => [{ lon, lat, minZoom: 12, maxZoom: 18, toleranceDegrees: 0.12 }] as const

export const SCOUT_SANDBOX_OPPORTUNITY_MANIFEST = {
  premium_exterior: {
    slug: 'premium_exterior',
    label: 'premium exterior',
    mapKind: 'single_site',
    markerSemantics: 'documented target point plus reconciled building footprint',
    hostNormalization: 'strict',
    rasterFrames: [{ width: 456, height: 210 }],
    tileRanges: [],
    tileCenters: singleSiteCenter(-85.758115986691, 38.256732011411),
  },
  water_tank: {
    slug: 'water_tank',
    label: 'water tank',
    mapKind: 'single_site',
    markerSemantics: 'documented WRIS tank point with engineering morphology evidence',
    hostNormalization: 'strict',
    rasterFrames: [{ width: 456, height: 210 }],
    tileRanges: [],
    tileCenters: singleSiteCenter(-86.4781456168917, 36.9655317362621),
  },
  swppp_site: {
    slug: 'swppp_site',
    label: 'SWPPP site',
    mapKind: 'single_site',
    markerSemantics: 'authoritative permit-location point only',
    hostNormalization: 'strict',
    rasterFrames: [{ width: 456, height: 210 }],
    tileRanges: [],
    tileCenters: singleSiteCenter(-84.521, 39.097),
  },
  water_utility_portfolio: {
    slug: 'water_utility_portfolio',
    label: 'Warren County water utility portfolio',
    mapKind: 'portfolio',
    markerSemantics: 'flat 2D morphology-coded documented tank members; unresolved members are not mapped',
    hostNormalization: 'strict',
    rasterFrames: [{ width: 456, height: 210 }],
    tileRanges: [{ z: 9, minX: 131, maxX: 134, minY: 198, maxY: 199 }],
    tileCenters: [],
    rpc: 'scout_get_component_sandbox_water_portfolio_v1_internal',
    contractVersion: 'water_utility_portfolio_map_v1',
  },
  dealership_group_portfolio: {
    slug: 'dealership_group_portfolio',
    label: 'Don Franklin Auto dealership portfolio',
    mapKind: 'portfolio',
    markerSemantics: 'resolved operating sites with single/multi-building resolution depth; unresolved roster members are not mapped',
    hostNormalization: 'unresolved_link_confidence_null_elision',
    rasterFrames: [{ width: 456, height: 210 }, { width: 280, height: 210 }],
    tileRanges: [
      { z: 8, minX: 66, maxX: 68, minY: 98, maxY: 99 },
      { z: 7, minX: 33, maxX: 34, minY: 49, maxY: 49 },
    ],
    tileCenters: [],
    rpc: 'scout_get_component_sandbox_dealership_portfolio_v1_internal',
    contractVersion: 'dealership_group_portfolio_map_v1',
  },
  hotel_management_portfolio: {
    slug: 'hotel_management_portfolio',
    label: 'Commonwealth Hotels management portfolio',
    mapKind: 'portfolio',
    markerSemantics: 'resolved operating hotels with brand-family context; unresolved roster members are not mapped',
    hostNormalization: 'unresolved_link_confidence_null_elision',
    rasterFrames: [{ width: 456, height: 210 }, { width: 280, height: 210 }],
    tileRanges: [{ z: 7, minX: 32, maxX: 34, minY: 48, maxY: 49 }],
    tileCenters: [],
    rpc: 'scout_get_component_sandbox_hotel_portfolio_v1_internal',
    contractVersion: 'hotel_management_portfolio_map_v1',
  },
} as const satisfies Record<ScoutSandboxOpportunityType, ScoutSandboxOpportunityManifestEntry | ScoutSandboxPortfolioManifestEntry>

export const SCOUT_SANDBOX_PORTFOLIO_MANIFEST = Object.fromEntries(
  SCOUT_SANDBOX_PORTFOLIO_TYPES.map((type) => [type, SCOUT_SANDBOX_OPPORTUNITY_MANIFEST[type]]),
) as Record<ScoutSandboxPortfolioType, ScoutSandboxPortfolioManifestEntry>

export function isScoutSandboxOpportunityType(value: unknown): value is ScoutSandboxOpportunityType {
  return typeof value === 'string' && (SCOUT_SANDBOX_OPPORTUNITY_TYPES as readonly string[]).includes(value)
}

export function isScoutSandboxPortfolioType(value: unknown): value is ScoutSandboxPortfolioType {
  return typeof value === 'string' && (SCOUT_SANDBOX_PORTFOLIO_TYPES as readonly string[]).includes(value)
}

export function scoutSandboxCompatibilityResourceUris() {
  return Array.from(
    { length: SCOUT_SANDBOX_RESOURCE_VERSION - 1 },
    (_, index) => `ui://scout/component-sandbox/v${SCOUT_SANDBOX_RESOURCE_VERSION - 1 - index}`,
  )
}

export function scoutSandboxCompatibilityUsesEmbeddedRaster(uri: string) {
  const match = uri.match(/\/v(\d+)$/)
  if (!match) return false
  const version = Number(match[1])
  return Number.isInteger(version)
    && version >= SCOUT_SANDBOX_EMBEDDED_RASTER_COMPATIBILITY_MIN_VERSION
    && version < SCOUT_SANDBOX_RESOURCE_VERSION
}

function tileCenter(z: number, x: number, y: number) {
  const count = Math.pow(2, z)
  const lon = (x + 0.5) / count * 360 - 180
  const mercator = Math.PI * (1 - 2 * (y + 0.5) / count)
  const lat = Math.atan(Math.sinh(mercator)) * 180 / Math.PI
  return { lon, lat }
}

export function isScoutSandboxRasterTileAllowed(z: number, x: number, y: number) {
  for (const entry of Object.values(SCOUT_SANDBOX_OPPORTUNITY_MANIFEST)) {
    for (const range of entry.tileRanges) {
      if (z === range.z && x >= range.minX && x <= range.maxX && y >= range.minY && y <= range.maxY) return true
    }
    for (const centerPolicy of entry.tileCenters) {
      if (z < centerPolicy.minZoom || z > centerPolicy.maxZoom) continue
      const center = tileCenter(z, x, y)
      if (Math.abs(center.lon - centerPolicy.lon) <= centerPolicy.toleranceDegrees
        && Math.abs(center.lat - centerPolicy.lat) <= centerPolicy.toleranceDegrees) return true
    }
  }
  return false
}

export function scoutSandboxToolDescription() {
  const choices = SCOUT_SANDBOX_OPPORTUNITY_TYPES.map((type) => SCOUT_SANDBOX_OPPORTUNITY_MANIFEST[type].label).join(', ')
  return `Owner-only read-only developer tool that renders one bounded Scout MCP Apps opportunity card and matching map. Registered sandbox choices: ${choices}; omission preserves the premium-exterior compatibility default.`
}
