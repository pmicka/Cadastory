import {
  SCOUT_SANDBOX_PORTFOLIO_TYPES,
  type ScoutSandboxPortfolioType,
} from '../_shared/scout_sandbox_manifest.ts'
import {
  buildScoutSandboxWaterUtilityPortfolioOpportunity,
  normalizeScoutSandboxWaterUtilityPortfolioMap,
  normalizeScoutSandboxWaterUtilityPortfolioOpportunity,
} from './water_portfolio_map_model.ts'
import { buildScoutWaterUtilityPortfolioRasterFrame } from './water_portfolio_map_renderer.ts'
import {
  buildScoutSandboxDealershipPortfolioOpportunity,
  normalizeScoutSandboxDealershipPortfolioMap,
  normalizeScoutSandboxDealershipPortfolioOpportunity,
} from './dealership_portfolio_map_model.ts'
import { buildScoutDealershipPortfolioRasterFrame } from './dealership_portfolio_map_renderer.ts'
import {
  buildScoutSandboxHotelPortfolioOpportunity,
  normalizeScoutSandboxHotelPortfolioMap,
  normalizeScoutSandboxHotelPortfolioOpportunity,
} from './hotel_portfolio_map_model.ts'
import { buildScoutHotelPortfolioRasterFrame } from './hotel_portfolio_map_renderer.ts'

export const SCOUT_SANDBOX_PORTFOLIO_IMPLEMENTATIONS = {
  water_utility_portfolio: {
    normalizeMap: normalizeScoutSandboxWaterUtilityPortfolioMap,
    normalizeOpportunity: normalizeScoutSandboxWaterUtilityPortfolioOpportunity,
    buildOpportunity: buildScoutSandboxWaterUtilityPortfolioOpportunity,
    buildRasterFrame: buildScoutWaterUtilityPortfolioRasterFrame,
    identityMatches: (map: any, opportunity: any) => map.account_name === opportunity.name && map.pwsid === opportunity.pwsid && map.member_count === opportunity.member_count,
    responseText: (opportunity: any) => `Scout returned the bounded ${opportunity.name} documented water-utility portfolio card with ${opportunity.member_count} mapped tank records.`,
    ariaLabel: (map: any) => `Documented tank portfolio map for ${map.account_name}`,
  },
  dealership_group_portfolio: {
    normalizeMap: normalizeScoutSandboxDealershipPortfolioMap,
    normalizeOpportunity: normalizeScoutSandboxDealershipPortfolioOpportunity,
    buildOpportunity: buildScoutSandboxDealershipPortfolioOpportunity,
    buildRasterFrame: buildScoutDealershipPortfolioRasterFrame,
    identityMatches: (map: any, opportunity: any) => map.account_name === opportunity.name && map.member_count === opportunity.member_count && map.resolved_member_count === opportunity.resolved_member_count,
    responseText: (opportunity: any) => `Scout returned the bounded ${opportunity.name} dealership-group portfolio card with ${opportunity.resolved_member_count} mapped sites from ${opportunity.member_count} documented operating locations.`,
    ariaLabel: (map: any) => `Documented dealership portfolio map for ${map.account_name}`,
  },
  hotel_management_portfolio: {
    normalizeMap: normalizeScoutSandboxHotelPortfolioMap,
    normalizeOpportunity: normalizeScoutSandboxHotelPortfolioOpportunity,
    buildOpportunity: buildScoutSandboxHotelPortfolioOpportunity,
    buildRasterFrame: buildScoutHotelPortfolioRasterFrame,
    identityMatches: (map: any, opportunity: any) => map.account_name === opportunity.name && map.member_count === opportunity.member_count && map.resolved_member_count === opportunity.resolved_member_count,
    responseText: (opportunity: any) => `Scout returned the bounded ${opportunity.name} hotel-management portfolio card with ${opportunity.resolved_member_count} mapped sites from ${opportunity.member_count} documented operating hotels.`,
    ariaLabel: (map: any) => `Documented hotel portfolio map for ${map.account_name}`,
  },
} as const

export function scoutSandboxPortfolioImplementation(type: ScoutSandboxPortfolioType) {
  return SCOUT_SANDBOX_PORTFOLIO_IMPLEMENTATIONS[type] as any
}

export function assertScoutSandboxPortfolioImplementationCoverage() {
  const implementationTypes = Object.keys(SCOUT_SANDBOX_PORTFOLIO_IMPLEMENTATIONS).sort()
  const registeredTypes = [...SCOUT_SANDBOX_PORTFOLIO_TYPES].sort()
  if (implementationTypes.length !== registeredTypes.length || implementationTypes.some((type, index) => type !== registeredTypes[index])) {
    throw new Error('Scout sandbox portfolio runtime registry does not match the shared opportunity manifest')
  }
}
