import { normalizePortfolio } from './model.ts'
export function buildPortfolioResult(value: unknown) {
  const map = normalizePortfolio(value)
  if (!map) throw new Error('Invalid portfolio contract')
  return { opportunity_type:'water_tank' as const, view_scope:'portfolio' as const,
    opportunity:{organization_id:map.organization_id,name:map.account_name,pwsid:map.pwsid}, map }
}
export function normalizePortfolioResult(value: unknown) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null
  const source = value as Record<string,any>, map = normalizePortfolio(source.map)
  if (source.opportunity_type !== 'water_tank' || source.view_scope !== 'portfolio' || !map ||
      source.opportunity?.organization_id !== map.organization_id || source.opportunity?.name !== map.account_name || source.opportunity?.pwsid !== map.pwsid) return null
  return buildPortfolioResult(map)
}
