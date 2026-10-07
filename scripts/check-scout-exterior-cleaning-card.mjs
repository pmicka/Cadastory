import { readFileSync } from 'node:fs'

function assert(condition, message) {
  if (!condition) throw new Error(message)
}

const migration = readFileSync(
  'supabase/migrations/20261006170000_add_scout_exterior_cleaning_opportunity_card.sql',
  'utf8',
)
const edge = readFileSync('supabase/functions/scout-mcp/index.ts', 'utf8')

for (const required of [
  'scout_get_connection_exterior_cleaning_opportunity_card_v1',
  'scout_get_exterior_cleaning_opportunity_card',
  'exterior_cleaning_opportunity_card_v1',
  'exterior_cleaning_site_map_v1',
  'agent_contract.output_schema_families',
  'exterior_cleaning:*',
  'primary_base',
  'related_timing_context',
  'source_kind = \'exterior_cleaning\'',
  'primary_service_slug = \'exterior-cleaning\'',
  'derived_from_candidate_key is null',
  'derived_from_candidate_key = v_candidate_key',
  'scout_guard_opportunity_request',
  'v_opportunity_spine_cards',
  'v_opportunity_spine_map',
  'commercial_scale',
  'responsible_party',
  'access_context',
  'evidence',
  'unknowns',
  'base_vs_derived_policy',
  'assert_tool_registry_integrity_v1',
  'assert_architecture_doctrine_v1',
  'assert_tool_routing_integrity',
  'assert_routing_eval_fixtures',
]) {
  assert(migration.includes(required), 'missing exterior-cleaning card invariant: ' + required)
}

for (const forbidden of [
  'scout.get_opportunity_spine_projection_v2',
  'scout_get_connection_lead_work_package_v2',
  'scout_match_connection_media_asset_v2',
  'scout_find_connection_opportunities_v2',
  'statement_timeout',
]) {
  assert(!migration.includes(forbidden), 'card migration must not use heavyweight/adjacent path: ' + forbidden)
}

assert(
  migration.includes('agent_exposure.exposures') &&
    migration.includes('unknown_or_inaccessible_candidate') &&
    migration.includes('do not probe arbitrary candidate identifiers'),
  'card RPC must require a known exposed candidate and fail closed for unknown keys',
)

assert(
  migration.includes("allowed_root_keys") &&
    migration.includes("array['candidate_key']::text[]") &&
    migration.includes('bulk candidate arrays') &&
    migration.includes('agent_free_text_allowed') &&
    migration.includes('false'),
  'privacy contract must keep the input narrow and reject bulk/free-text paths',
)

assert(
  migration.includes('exterior_cleaning_card.witherspoon_address_flow') &&
    migration.includes('100 Witherspoon St, Louisville, KY') &&
    migration.includes("array['scout_resolve_site_opportunities','scout_get_exterior_cleaning_opportunity_card']"),
  'routing fixtures must cover address-to-card handoff for Witherspoon',
)

assert(
  migration.includes('exterior_cleaning_card.exact_candidate') &&
    migration.includes('exterior_cleaning:b6c401a0-97da-4a9d-bbf6-b06d7b745e3b'),
  'routing fixtures must cover exact Witherspoon candidate regression',
)

assert(
  edge.includes('const exteriorCleaningCardInput=') &&
    edge.includes("regex(/^exterior_cleaning:[0-9a-fA-F-]{36}$/)") &&
    edge.includes("server.registerTool('scout_get_exterior_cleaning_opportunity_card'") &&
    edge.includes("requireScope(connection,'opportunities:read')") &&
    edge.includes("requireScope(connection,'profile:read')") &&
    edge.includes('scout_get_connection_exterior_cleaning_opportunity_card_v1'),
  'MCP tool must expose a narrow exact-candidate schema with normal Scout read scopes',
)

const cardRegistration = edge.slice(
  edge.indexOf("server.registerTool('scout_get_exterior_cleaning_opportunity_card'"),
)
const cardBlock = cardRegistration.slice(
  0,
  cardRegistration.indexOf("server.registerTool('scout_find_opportunities'"),
)
for (const forbidden of [
  'scout_get_connection_lead_work_package_v2',
  'scout_match_connection_media_asset_v2',
  'scout_find_connection_opportunities_v2',
]) {
  assert(!cardBlock.includes(forbidden), 'card tool must not delegate to adjacent RPC: ' + forbidden)
}

assert(
  edge.includes('For address questions about exterior-cleaning intelligence, call the resolver first') &&
    edge.includes('Never use derived event_detailing:* candidates as the card subject'),
  'MCP instructions must route address-to-card and preserve derived-candidate semantics',
)

console.log('Scout exterior-cleaning opportunity card contract checks passed')
