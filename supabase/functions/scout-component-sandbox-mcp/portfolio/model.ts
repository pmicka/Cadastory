// Isolated foundation. Not imported by the live View or registered as a tool.
export type Member = {
  id: string; pwsid: string; name: string;
  point: { type: 'Point'; coordinates: [number, number] } | { type: 'unresolved' };
  service_state: 'documented_not_in_service' | 'unverified'; within_pilot_radius: boolean;
  source_modified_at: string;
  signals: { id: string; kind: 'historical_rehab_record'; observed_at: string }[];
}
export type Portfolio = {
  contract_version: 'water_utility_portfolio_map_v1'; scope: 'documented_roster';
  source_slug: 'ky-kia-water-tanks'; relationship: 'system_membership';
  organization_id: string; account_name: string; pwsid: string; observed_on: string; members: Member[];
}
const obj = (v: unknown): v is Record<string, any> => !!v && typeof v === 'object' && !Array.isArray(v)
const str = (v: unknown, max = 200): v is string => typeof v === 'string' && v.trim().length > 0 && v.length <= max
const date = (v: unknown) => str(v, 80) && Number.isFinite(Date.parse(v))
export function normalizePortfolio(value: unknown): Portfolio | null {
  if (!obj(value) || value.contract_version !== 'water_utility_portfolio_map_v1' || value.scope !== 'documented_roster') return null
  if (value.source_slug !== 'ky-kia-water-tanks' || value.relationship !== 'system_membership') return null
  if (!str(value.organization_id, 80) || !str(value.account_name) || !str(value.pwsid, 40) || !date(value.observed_on)) return null
  if (!Array.isArray(value.members) || !value.members.length || value.members.length > 100) return null
  const ids = new Set<string>(), signalIds = new Set<string>(), members: Member[] = []
  for (const m of value.members) {
    if (!obj(m) || !str(m.id, 80) || ids.has(m.id) || m.pwsid !== value.pwsid || !str(m.name)) return null
    ids.add(m.id)
    if (!['documented_not_in_service','unverified'].includes(m.service_state) || typeof m.within_pilot_radius !== 'boolean' || !date(m.source_modified_at)) return null
    if (!obj(m.point)) return null
    let point: Member['point']
    if (m.point.type === 'unresolved') point = { type: 'unresolved' }
    else {
      const c = m.point.coordinates
      if (m.point.type !== 'Point' || !Array.isArray(c) || c.length !== 2 || !c.every(Number.isFinite) || Math.abs(c[0]) > 180 || Math.abs(c[1]) > 85.05112878) return null
      point = { type: 'Point', coordinates: [c[0],c[1]] }
    }
    if (!Array.isArray(m.signals) || m.signals.length > 10) return null
    const signals: Member['signals'] = []
    for (const s of m.signals) {
      if (!obj(s) || !str(s.id, 160) || signalIds.has(s.id) || s.kind !== 'historical_rehab_record' || !date(s.observed_at)) return null
      signalIds.add(s.id); signals.push({id:s.id,kind:'historical_rehab_record',observed_at:s.observed_at})
    }
    members.push({id:m.id,pwsid:m.pwsid,name:m.name,point,service_state:m.service_state,within_pilot_radius:m.within_pilot_radius,source_modified_at:m.source_modified_at,signals})
  }
  return {contract_version:'water_utility_portfolio_map_v1',scope:'documented_roster',source_slug:'ky-kia-water-tanks',relationship:'system_membership',organization_id:value.organization_id,account_name:value.account_name,pwsid:value.pwsid,observed_on:value.observed_on,members}
}
export function portfolioCounts(p: Portfolio) {
  return { total:p.members.length, mapped:p.members.filter(m=>m.point.type==='Point').length,
    unresolved:p.members.filter(m=>m.point.type==='unresolved').length, omitted:0,
    documentedNotInService:p.members.filter(m=>m.service_state==='documented_not_in_service').length,
    membersWithHistoricalSignals:p.members.filter(m=>m.signals.length>0).length }
}
