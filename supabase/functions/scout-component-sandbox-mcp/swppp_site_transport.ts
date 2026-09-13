import { normalizeScoutSandboxSwpppSiteMap, type ScoutSandboxSwpppSiteMap, type SwpppMapRejection } from './swppp_site_map_model.ts'

export type ScoutSwpppSiteTransport = ScoutSandboxSwpppSiteMap & {
  transport_contract: 'swppp_site_transport_v1'
  permit: ScoutSandboxSwpppSiteMap['permit'] & { termination_state: 'not_recorded' }
  buyer: ScoutSandboxSwpppSiteMap['buyer'] & { organization_resolution_state: 'unresolved' }
}

// Server boundary: only the strict database contract can issue these assertions.
export function buildScoutSwpppSiteTransport(value: unknown): ScoutSwpppSiteTransport {
  const map = normalizeScoutSandboxSwpppSiteMap(value)
  if (!map) throw new Error('Scout SWPPP transport requires a validated source map')
  return { ...map, transport_contract: 'swppp_site_transport_v1',
    permit: { ...map.permit, termination_state: 'not_recorded' },
    buyer: { ...map.buyer, organization_resolution_state: 'unresolved' } }
}

function record(value: unknown): Record<string, unknown> | null {
  return value && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : null
}

// View boundary: missing nulls alone never authorize a map. Non-null contradictions fail.
export function normalizeScoutSwpppSiteTransport(value: unknown, onReject?: (detail: SwpppMapRejection) => void): ScoutSandboxSwpppSiteMap | null {
  const reject = (field: string, actual: unknown): null => {
    try { onReject?.({ field, check: 'transport_assertion', actualType: actual === null ? 'null' : Array.isArray(actual) ? 'array' : typeof actual,
      stringShape: typeof actual === 'string' ? (actual.trim() ? 'nonempty' : 'empty') : 'not_string' }) } catch { /* observer only */ }
    return null
  }
  const map = record(value)
  if (!map || map.transport_contract !== 'swppp_site_transport_v1') return reject('transport_contract', map?.transport_contract)
  const permit = record(map.permit), buyer = record(map.buyer)
  if (!permit || permit.termination_state !== 'not_recorded') return reject('permit.termination_state', permit?.termination_state)
  if (!buyer || buyer.organization_resolution_state !== 'unresolved') return reject('buyer.organization_resolution_state', buyer?.organization_resolution_state)
  if (permit.termination_date !== null && permit.termination_date !== undefined) return reject('permit.termination_date', permit.termination_date)
  if (buyer.organization_id !== null && buyer.organization_id !== undefined) return reject('buyer.organization_id', buyer.organization_id)
  return normalizeScoutSandboxSwpppSiteMap({ ...map,
    permit: { ...permit, termination_date: null }, buyer: { ...buyer, organization_id: null } }, onReject)
}
