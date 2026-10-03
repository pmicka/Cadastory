import { readFileSync } from 'node:fs'

function assert(condition, message) {
  if (!condition) throw new Error(message)
}

const migration = readFileSync(
  'supabase/migrations/20261003190000_add_scout_address_opportunity_resolver.sql',
  'utf8',
)
const edge = readFileSync('supabase/functions/scout-mcp/index.ts', 'utf8')

for (const required of [
  'scout_resolve_connection_site_opportunities_v1',
  'scout_resolve_site_opportunities',
  'authoritative_site_address_alias',
  'canonical_spine_address',
  'resolution_status',
  'needs_confirmation',
  'not_found',
  'primary_base',
  'related_derived',
  'derived_from_candidate_key is null',
  'derived_from_candidate_key is not null',
  'scout.get_opportunity_spine_projection_v2',
  'scout_guard_opportunity_request',
  'assert_tool_registry_integrity_v1',
  'assert_architecture_doctrine_v1',
  'assert_tool_routing_integrity',
  'assert_routing_eval_fixtures',
]) {
  assert(migration.includes(required), 'missing resolver invariant: ' + required)
}

assert(
  migration.includes('p_limit integer default 5') &&
    migration.includes('least(greatest(coalesce(p_limit,5),1),5)'),
  'resolver must keep a small bounded limit',
)

assert(
  migration.includes("regexp_replace(lower(v_city), '[^a-z0-9]+', '', 'g')") &&
    migration.includes('s.state_code = v_state_code') &&
    migration.includes("regexp_replace(lower(coalesce(s.details->>'city','')), '[^a-z0-9]+', '', 'g') = v_city_key"),
  'resolver must constrain ordinary address matches by city/state',
)

assert(
  !migration.includes('http://') &&
    !migration.includes('https://') &&
    !migration.match(/\b(st_makepoint|st_geocode|geocoder_url|geocoder_api)\b/i),
  'resolver must not introduce external geocoding calls or URL lookup',
)

assert(
  migration.includes("'address','city','state_code','limit'") &&
    migration.includes('bulk address lists') &&
    /discovery_batch\s*,\s*updated_at/.test(migration) &&
    /true\s*,\s*true\s*,\s*false\s*,\s*now\(\)/.test(migration),
  'resolver privacy/exposure contract must reject bulk enumeration',
)

assert(
  migration.includes('address_resolution.witherspoon_known_site') &&
    migration.includes('100 Witherspoon St, Louisville, KY') &&
    migration.includes("array['scout_match_media_asset','scout_find_opportunities"),
  'routing eval must cover Witherspoon and forbid adjacent first tools',
)

assert(
  edge.includes('const siteOpportunityResolutionInput=') &&
    edge.includes('address:z.string().min(1).max(300)') &&
    edge.includes('city:z.string().min(1).max(120)') &&
    edge.includes('state_code:z.string().regex(/^[A-Za-z]{2}$/)') &&
    edge.includes('limit:z.number().int().min(1).max(5).optional()'),
  'MCP input schema must remain narrow',
)

assert(
  edge.includes("server.registerTool('scout_resolve_site_opportunities'") &&
    edge.includes("requireScope(connection,'opportunities:read')") &&
    edge.includes("requireScope(connection,'profile:read')") &&
    edge.includes('scout_resolve_connection_site_opportunities_v1'),
  'MCP tool must use normal scopes and resolver RPC',
)

assert(
  edge.includes('Use scout_match_media_asset to identify a likely facility/business from media clues, not to resolve a known street address into opportunities.'),
  'MCP instructions must preserve media matcher semantics',
)

const resolverRegistration = edge.slice(edge.indexOf("server.registerTool('scout_resolve_site_opportunities'"))
const resolverBlock = resolverRegistration.slice(0, resolverRegistration.indexOf("server.registerTool('scout_find_opportunities'"))
for (const forbidden of [
  'scout_match_connection_media_asset_v2',
  'scout_find_connection_opportunities_v2',
]) {
  assert(
    !resolverBlock.includes(forbidden),
    'resolver tool must not delegate to adjacent tool RPC: ' + forbidden,
  )
}

console.log('Scout address opportunity resolver contract checks passed')
