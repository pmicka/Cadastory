from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    if old not in text:
        raise SystemExit(f'pattern not found in {path}: {old[:160]!r}')
    p.write_text(text.replace(old, new, 1))


component = 'supabase/functions/scout-component-sandbox-mcp/index.ts'
replace_once(component,
"""import {
  buildScoutSandboxWaterUtilityPortfolioOpportunity,
  normalizeScoutSandboxWaterUtilityPortfolioMap,
} from './water_portfolio_map_model.ts'
""",
"""import {
  buildScoutSandboxWaterUtilityPortfolioOpportunity,
  normalizeScoutSandboxWaterUtilityPortfolioMap,
} from './water_portfolio_map_model.ts'
import {
  buildScoutSandboxDealershipPortfolioOpportunity,
  normalizeScoutSandboxDealershipPortfolioMap,
} from './dealership_portfolio_map_model.ts'
""")
replace_once(component,
"import { buildScoutWaterUtilityPortfolioRasterFrame } from './water_portfolio_map_renderer.ts'\n",
"import { buildScoutWaterUtilityPortfolioRasterFrame } from './water_portfolio_map_renderer.ts'\nimport { buildScoutDealershipPortfolioRasterFrame } from './dealership_portfolio_map_renderer.ts'\n")
replace_once(component,
"const RESOURCE_URI = 'ui://scout/component-sandbox/v29'\nconst COMPATIBILITY_RESOURCE_URIS = [\n  'ui://scout/component-sandbox/v28',",
"const RESOURCE_URI = 'ui://scout/component-sandbox/v30'\nconst COMPATIBILITY_RESOURCE_URIS = [\n  'ui://scout/component-sandbox/v29',\n  'ui://scout/component-sandbox/v28',")
replace_once(component,
"const WARREN_PORTFOLIO_TILE_BOUNDS = { z: 9, minX: 131, maxX: 134, minY: 198, maxY: 199 } as const\n",
"const WARREN_PORTFOLIO_TILE_BOUNDS = { z: 9, minX: 131, maxX: 134, minY: 198, maxY: 199 } as const\nconst DEALERSHIP_PORTFOLIO_TILE_BOUNDS = { z: 8, minX: 66, maxX: 68, minY: 98, maxY: 99 } as const\n")
replace_once(component,
"""async function loadScoutSandboxWaterUtilityPortfolioMap() {
  const { data, error } = await admin.rpc('scout_get_component_sandbox_water_portfolio_v1_internal')
  if (error) throw new Error('Scout sandbox water-utility portfolio map is unavailable')
  const map = normalizeScoutSandboxWaterUtilityPortfolioMap(data)
  if (!map) throw new Error('Scout sandbox water-utility portfolio map did not satisfy the bounded contract')
  return map
}
""",
"""async function loadScoutSandboxWaterUtilityPortfolioMap() {
  const { data, error } = await admin.rpc('scout_get_component_sandbox_water_portfolio_v1_internal')
  if (error) throw new Error('Scout sandbox water-utility portfolio map is unavailable')
  const map = normalizeScoutSandboxWaterUtilityPortfolioMap(data)
  if (!map) throw new Error('Scout sandbox water-utility portfolio map did not satisfy the bounded contract')
  return map
}

async function loadScoutSandboxDealershipPortfolioMap() {
  const { data, error } = await admin.rpc('scout_get_component_sandbox_dealership_portfolio_v1_internal')
  if (error) throw new Error('Scout sandbox dealership portfolio map is unavailable')
  const map = normalizeScoutSandboxDealershipPortfolioMap(data)
  if (!map) throw new Error('Scout sandbox dealership portfolio map did not satisfy the bounded contract')
  return map
}
""")
replace_once(component,
"""  const [premiumMap, waterTankMap, swpppMap, portfolioMap] = await Promise.all([
    loadScoutSandboxSingleSiteMap(),
    loadScoutSandboxWaterTankMap(),
    loadScoutSandboxSwpppSiteMap(),
    loadScoutSandboxWaterUtilityPortfolioMap(),
  ])
  const frames = [
    buildScoutSingleSiteRasterFrame(premiumMap, 456, 210, { tileUrlTemplate }),
    buildScoutWaterTankRasterFrame(waterTankMap, 456, 210, { tileUrlTemplate }),
    buildScoutSwpppSiteRasterFrame(swpppMap, 456, 210, { tileUrlTemplate }),
    buildScoutWaterUtilityPortfolioRasterFrame(portfolioMap, 456, 210, { tileUrlTemplate }),
  ]
""",
"""  const [premiumMap, waterTankMap, swpppMap, portfolioMap, dealershipMap] = await Promise.all([
    loadScoutSandboxSingleSiteMap(),
    loadScoutSandboxWaterTankMap(),
    loadScoutSandboxSwpppSiteMap(),
    loadScoutSandboxWaterUtilityPortfolioMap(),
    loadScoutSandboxDealershipPortfolioMap(),
  ])
  const frames = [
    buildScoutSingleSiteRasterFrame(premiumMap, 456, 210, { tileUrlTemplate }),
    buildScoutWaterTankRasterFrame(waterTankMap, 456, 210, { tileUrlTemplate }),
    buildScoutSwpppSiteRasterFrame(swpppMap, 456, 210, { tileUrlTemplate }),
    buildScoutWaterUtilityPortfolioRasterFrame(portfolioMap, 456, 210, { tileUrlTemplate }),
    buildScoutDealershipPortfolioRasterFrame(dealershipMap, 456, 210, { tileUrlTemplate }),
  ]
""")

schema_block = r'''
const dealershipPortfolioMemberSchema = z.object({
  id: z.string().min(1).max(80),
  name: z.string().min(1).max(200),
  address: z.string().min(1).max(240),
  city: z.string().min(1).max(120),
  state_code: z.string().min(1).max(8),
  brands: z.array(z.string().min(1).max(80)).max(16),
  point: z.union([
    z.object({ type: z.literal('Point'), coordinates: z.tuple([z.number().min(-180).max(180), z.number().min(-90).max(90)]) }),
    z.object({ type: z.literal('unresolved') }),
  ]),
  resolution_state: z.enum(['single_building_resolved', 'multi_building_resolved', 'unresolved']),
  resolved_building_count: z.number().int().min(0).max(20),
  link_confidence: z.number().min(0).max(1).nullable(),
  within_pilot_radius: z.boolean(),
  observed_at: z.string().min(1).max(80),
})

const dealershipPortfolioMapSchema = z.object({
  contract_version: z.literal('dealership_group_portfolio_map_v1'),
  opportunity_type: z.literal('dealership_group_portfolio'),
  group_kind: z.literal('portfolio'),
  account_name: z.string().min(1).max(200),
  organization_id: z.string().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i),
  scope: z.literal('documented_operating_roster'),
  source_slug: z.literal('don-franklin-auto-locations'),
  relationship: z.literal('operates'),
  target_kind: z.literal('site_member'),
  map_semantics: z.literal('documented_operating_site_portfolio'),
  evidence_boundary: z.literal('first-party dealership roster plus resolved building crosswalks'),
  generated_at: z.string().min(1).max(80),
  observed_at: z.string().min(1).max(80),
  member_count: z.number().int().min(1).max(100),
  resolved_member_count: z.number().int().min(1).max(100),
  resolved_building_count: z.number().int().min(1).max(200),
  contact_route_available: z.boolean(),
  operations_route_available: z.boolean(),
  procurement_route_available: z.boolean(),
  vendor_route_proven: z.boolean(),
  current_need_scan_complete: z.boolean(),
  bounds: z.object({
    west: z.number().min(-180).max(180), south: z.number().min(-90).max(90),
    east: z.number().min(-180).max(180), north: z.number().min(-90).max(90),
  }),
  members: z.array(dealershipPortfolioMemberSchema).min(1).max(100),
  guardrail: z.string().min(1).max(1600),
})

const dealershipPortfolioOpportunitySchema = z.object({
  opportunity_type: z.literal('dealership_group_portfolio'),
  name: z.string().min(1).max(200),
  member_count: z.number().int().min(1).max(100),
  resolved_member_count: z.number().int().min(1).max(100),
  resolved_building_count: z.number().int().min(1).max(200),
  unresolved_member_count: z.number().int().min(0).max(100),
  observed_at: z.string().min(1).max(80),
  contact_route_available: z.boolean(),
  operations_route_available: z.boolean(),
  procurement_route_available: z.boolean(),
  vendor_route_proven: z.boolean(),
  current_need_scan_complete: z.boolean(),
  map_semantics: z.literal('documented_operating_site_portfolio'),
  evidence_boundary: z.literal('first-party dealership roster plus resolved building crosswalks'),
  why_investigate: z.string().min(1).max(1000),
  guardrail: z.string().min(1).max(1600),
})

const dealershipPortfolioResultSchema = z.object({
  surface: z.literal('scout_component_sandbox'),
  opportunity_type: z.literal('dealership_group_portfolio'),
  opportunity: dealershipPortfolioOpportunitySchema,
  map: dealershipPortfolioMapSchema,
})
'''
replace_once(component,
"""const waterUtilityPortfolioResultSchema = z.object({
  surface: z.literal('scout_component_sandbox'),
  opportunity_type: z.literal('water_utility_portfolio'),
  opportunity: waterUtilityPortfolioOpportunitySchema,
  map: waterUtilityPortfolioMapSchema,
})

function makeServer() {
""",
"""const waterUtilityPortfolioResultSchema = z.object({
  surface: z.literal('scout_component_sandbox'),
  opportunity_type: z.literal('water_utility_portfolio'),
  opportunity: waterUtilityPortfolioOpportunitySchema,
  map: waterUtilityPortfolioMapSchema,
})

""" + schema_block + "\nfunction makeServer() {\n")
replace_once(component,
"const server = new McpServer({ name: 'Scout UI Foundation', version: '2.2.9' })",
"const server = new McpServer({ name: 'Scout UI Foundation', version: '2.3.0' })")
replace_once(component,
"compatibilityUri === 'ui://scout/component-sandbox/v27' || compatibilityUri === 'ui://scout/component-sandbox/v28')",
"compatibilityUri === 'ui://scout/component-sandbox/v27' || compatibilityUri === 'ui://scout/component-sandbox/v28' || compatibilityUri === 'ui://scout/component-sandbox/v29')")
replace_once(component,
"description: 'Owner-only read-only developer tool that renders one bounded Scout MCP Apps opportunity card and matching map. Select premium_exterior, water_tank, swppp_site, or the Warren County water_utility_portfolio exemplar; omission preserves the PNC Tower compatibility default.',",
"description: 'Owner-only read-only developer tool that renders one bounded Scout MCP Apps opportunity card and matching map. Select premium_exterior, water_tank, swppp_site, the Warren County water_utility_portfolio exemplar, or the Don Franklin Auto dealership_group_portfolio exemplar; omission preserves the PNC Tower compatibility default.',")
replace_once(component,
"opportunity_type: z.enum(['premium_exterior', 'water_tank', 'swppp_site', 'water_utility_portfolio']).optional(),",
"opportunity_type: z.enum(['premium_exterior', 'water_tank', 'swppp_site', 'water_utility_portfolio', 'dealership_group_portfolio']).optional(),")
replace_once(component,
"outputSchema: z.discriminatedUnion('opportunity_type', [premiumResultSchema, waterTankResultSchema, swpppSiteResultSchema, waterUtilityPortfolioResultSchema]),",
"outputSchema: z.discriminatedUnion('opportunity_type', [premiumResultSchema, waterTankResultSchema, swpppSiteResultSchema, waterUtilityPortfolioResultSchema, dealershipPortfolioResultSchema]),")
replace_once(component,
"""      if (selectedType === 'water_utility_portfolio') {
""",
"""      if (selectedType === 'dealership_group_portfolio') {
        const map = await loadScoutSandboxDealershipPortfolioMap()
        const opportunity = buildScoutSandboxDealershipPortfolioOpportunity(map)
        if (map.account_name !== opportunity.name || map.member_count !== opportunity.member_count || map.resolved_member_count !== opportunity.resolved_member_count) {
          throw new Error('Scout sandbox dealership portfolio opportunity and map identity do not match')
        }
        return {
          content: [{ type: 'text', text: `Scout returned the bounded ${opportunity.name} dealership-group portfolio card with ${opportunity.resolved_member_count} mapped sites from ${opportunity.member_count} documented operating locations.` }],
          structuredContent: {
            surface: 'scout_component_sandbox',
            opportunity_type: 'dealership_group_portfolio',
            opportunity,
            map,
          },
        }
      }

      if (selectedType === 'water_utility_portfolio') {
""")
replace_once(component,
"if (!Number.isInteger(z) || z < 9 || z > 18 || x < 0 || y < 0 || x >= count || y >= count) return null",
"if (!Number.isInteger(z) || z < 8 || z > 18 || x < 0 || y < 0 || x >= count || y >= count) return null")
replace_once(component,
"""  if (z === WARREN_PORTFOLIO_TILE_BOUNDS.z
    && x >= WARREN_PORTFOLIO_TILE_BOUNDS.minX && x <= WARREN_PORTFOLIO_TILE_BOUNDS.maxX
    && y >= WARREN_PORTFOLIO_TILE_BOUNDS.minY && y <= WARREN_PORTFOLIO_TILE_BOUNDS.maxY) return { z, x, y }
  if (z < 12) return null
""",
"""  if (z === WARREN_PORTFOLIO_TILE_BOUNDS.z
    && x >= WARREN_PORTFOLIO_TILE_BOUNDS.minX && x <= WARREN_PORTFOLIO_TILE_BOUNDS.maxX
    && y >= WARREN_PORTFOLIO_TILE_BOUNDS.minY && y <= WARREN_PORTFOLIO_TILE_BOUNDS.maxY) return { z, x, y }
  if (z === DEALERSHIP_PORTFOLIO_TILE_BOUNDS.z
    && x >= DEALERSHIP_PORTFOLIO_TILE_BOUNDS.minX && x <= DEALERSHIP_PORTFOLIO_TILE_BOUNDS.maxX
    && y >= DEALERSHIP_PORTFOLIO_TILE_BOUNDS.minY && y <= DEALERSHIP_PORTFOLIO_TILE_BOUNDS.maxY) return { z, x, y }
  if (z < 12) return null
""")

view = 'supabase/functions/scout-component-sandbox-mcp/view.ts'
replace_once(view,
"""import { mountScoutWaterUtilityPortfolioMap } from './water_portfolio_map_mount.ts'
""",
"""import { mountScoutWaterUtilityPortfolioMap } from './water_portfolio_map_mount.ts'
import {
  normalizeScoutSandboxDealershipPortfolioMap,
  normalizeScoutSandboxDealershipPortfolioOpportunity,
} from './dealership_portfolio_map_model.ts'
import { mountScoutDealershipPortfolioMap } from './dealership_portfolio_map_mount.ts'
""")
replace_once(view,
"type ScoutViewOpportunityType = ScoutSandboxOpportunityType | 'water_utility_portfolio'",
"type ScoutViewOpportunityType = ScoutSandboxOpportunityType | 'water_utility_portfolio' | 'dealership_group_portfolio'")
replace_once(view,
"""function renderOpportunity(opportunityType: ScoutViewOpportunityType, value: unknown) {
  if (opportunityType === 'water_utility_portfolio') {
""",
"""function renderOpportunity(opportunityType: ScoutViewOpportunityType, value: unknown) {
  if (opportunityType === 'dealership_group_portfolio') {
    const opportunity = normalizeScoutSandboxDealershipPortfolioOpportunity(value)
    if (!opportunity) {
      renderUnavailableOpportunity()
      return
    }
    if (title) title.textContent = opportunity.name
    if (tier) tier.textContent = 'Portfolio evidence'
    if (meta) meta.textContent = `${formatNumber(opportunity.member_count)} documented operating dealership sites  •  First-party roster observed ${formatObserved(opportunity.observed_at)}`
    if (address) address.textContent = 'Kentucky pilot portfolio'
    if (summary) {
      const route = opportunity.operations_route_available || opportunity.procurement_route_available
        ? 'Operations / procurement route available'
        : opportunity.contact_route_available ? 'Contact route available; operations / procurement route unresolved' : 'Account route unresolved'
      summary.textContent = `${formatNumber(opportunity.resolved_member_count)} sites physically crosswalked  •  ${formatNumber(opportunity.resolved_building_count)} resolved buildings  •  ${formatNumber(opportunity.unresolved_member_count)} roster sites not mapped  •  ${route}  •  ${opportunity.why_investigate}`
    }
    if (guardrail) guardrail.textContent = `Scout guardrail: ${opportunity.guardrail}`
    setState(`Scout portfolio ready: ${opportunity.name}`)
    return
  }

  if (opportunityType === 'water_utility_portfolio') {
""")
view_text = Path(view).read_text()
view_text = view_text.replace("opportunityType === 'water_utility_portfolio' ? 'Loading portfolio map…' : 'Loading site map…'", "(opportunityType === 'water_utility_portfolio' || opportunityType === 'dealership_group_portfolio') ? 'Loading portfolio map…' : 'Loading site map…'")
view_text = view_text.replace("opportunityType === 'water_utility_portfolio' ? 'Scout portfolio map ready' : 'Scout site map ready'", "(opportunityType === 'water_utility_portfolio' || opportunityType === 'dealership_group_portfolio') ? 'Scout portfolio map ready' : 'Scout site map ready'")
view_text = view_text.replace("opportunityType === 'water_utility_portfolio' ? 'Portfolio map unavailable' : 'Site map unavailable'", "(opportunityType === 'water_utility_portfolio' || opportunityType === 'dealership_group_portfolio') ? 'Portfolio map unavailable' : 'Site map unavailable'")
Path(view).write_text(view_text)
replace_once(view,
"""  try {
    if (opportunityType === 'water_utility_portfolio') {
""",
"""  try {
    if (opportunityType === 'dealership_group_portfolio') {
      const mapData = normalizeScoutSandboxDealershipPortfolioMap(value)
      if (!mapData) {
        mapState.textContent = 'Portfolio map unavailable'
        setState('Scout dealership portfolio map result failed validation')
        return
      }
      mapContainer.setAttribute('role', 'img')
      mapContainer.setAttribute('aria-label', `Documented dealership portfolio map for ${mapData.account_name}`)
      mapHandle = mountScoutDealershipPortfolioMap(mapContainer, mapData, { ...mapOptions, embeddedTiles })
    } else if (opportunityType === 'water_utility_portfolio') {
""")
replace_once(view,
"const app = new App({ name: 'scout-ui-foundation', version: '2.9.0' })",
"const app = new App({ name: 'scout-ui-foundation', version: '2.10.0' })")
replace_once(view,
"if (opportunityType !== 'premium_exterior' && opportunityType !== 'water_tank' && opportunityType !== 'swppp_site' && opportunityType !== 'water_utility_portfolio') {",
"if (opportunityType !== 'premium_exterior' && opportunityType !== 'water_tank' && opportunityType !== 'swppp_site' && opportunityType !== 'water_utility_portfolio' && opportunityType !== 'dealership_group_portfolio') {")

for gateway in ['supabase/functions/scout-connect/index.ts', 'supabase/functions/scout-mcp-contract/index.ts']:
    replace_once(gateway,
        "import { sandboxWaterUtilityPortfolioMapSchema, sandboxWaterUtilityPortfolioOpportunitySchema } from '../_shared/scout_sandbox_water_portfolio_schema.ts'\n",
        "import { sandboxWaterUtilityPortfolioMapSchema, sandboxWaterUtilityPortfolioOpportunitySchema } from '../_shared/scout_sandbox_water_portfolio_schema.ts'\nimport { sandboxDealershipPortfolioMapSchema, sandboxDealershipPortfolioOpportunitySchema } from '../_shared/scout_sandbox_dealership_portfolio_schema.ts'\n")
    replace_once(gateway,
        "const SANDBOX_RESOURCE_URI = 'ui://scout/component-sandbox/v29'\nconst SANDBOX_COMPATIBILITY_RESOURCE_URIS = ['ui://scout/component-sandbox/v28',",
        "const SANDBOX_RESOURCE_URI = 'ui://scout/component-sandbox/v30'\nconst SANDBOX_COMPATIBILITY_RESOURCE_URIS = ['ui://scout/component-sandbox/v29','ui://scout/component-sandbox/v28',")
    replace_once(gateway,
        "{type:'object',properties:{surface:{type:'string',enum:['scout_component_sandbox']},opportunity_type:{type:'string',enum:['water_utility_portfolio']},opportunity:sandboxWaterUtilityPortfolioOpportunitySchema(),map:sandboxWaterUtilityPortfolioMapSchema()},required:['surface','opportunity_type','opportunity','map'],additionalProperties:false}]}}",
        "{type:'object',properties:{surface:{type:'string',enum:['scout_component_sandbox']},opportunity_type:{type:'string',enum:['water_utility_portfolio']},opportunity:sandboxWaterUtilityPortfolioOpportunitySchema(),map:sandboxWaterUtilityPortfolioMapSchema()},required:['surface','opportunity_type','opportunity','map'],additionalProperties:false},{type:'object',properties:{surface:{type:'string',enum:['scout_component_sandbox']},opportunity_type:{type:'string',enum:['dealership_group_portfolio']},opportunity:sandboxDealershipPortfolioOpportunitySchema(),map:sandboxDealershipPortfolioMapSchema()},required:['surface','opportunity_type','opportunity','map'],additionalProperties:false}]}}")
    replace_once(gateway,
        "description:'Owner-only read-only developer tool that renders one bounded Scout MCP Apps opportunity card and matching map. Select premium_exterior, water_tank, swppp_site, or the Warren County water_utility_portfolio exemplar; omission preserves the PNC Tower compatibility default.'",
        "description:'Owner-only read-only developer tool that renders one bounded Scout MCP Apps opportunity card and matching map. Select premium_exterior, water_tank, swppp_site, the Warren County water_utility_portfolio exemplar, or the Don Franklin Auto dealership_group_portfolio exemplar; omission preserves the PNC Tower compatibility default.'")
    replace_once(gateway,
        "enum:['premium_exterior','water_tank','swppp_site','water_utility_portfolio']",
        "enum:['premium_exterior','water_tank','swppp_site','water_utility_portfolio','dealership_group_portfolio']")

package = 'supabase/functions/scout-component-sandbox-mcp/package.json'
replace_once(package,
"node water_portfolio_map_renderer_test.mjs && node water_portfolio_gateway_contract_test.mjs && node gateway_syntax_test.mjs",
"node water_portfolio_map_renderer_test.mjs && node water_portfolio_gateway_contract_test.mjs && node dealership_portfolio_map_renderer_test.mjs && node dealership_portfolio_gateway_contract_test.mjs && node gateway_syntax_test.mjs")

# Resource and View version assertions in existing regression tests.
for test in Path('supabase/functions/scout-component-sandbox-mcp').glob('*test.mjs'):
    text = test.read_text()
    text = text.replace("const RESOURCE_URI = 'ui://scout/component-sandbox/v29'", "const RESOURCE_URI = 'ui://scout/component-sandbox/v30'")
    text = text.replace("const SANDBOX_RESOURCE_URI = 'ui://scout/component-sandbox/v29'", "const SANDBOX_RESOURCE_URI = 'ui://scout/component-sandbox/v30'")
    text = text.replace("version: '2.9.0'", "version: '2.10.0'")
    text = text.replace("z.enum(['premium_exterior', 'water_tank', 'swppp_site', 'water_utility_portfolio']).optional()", "z.enum(['premium_exterior', 'water_tank', 'swppp_site', 'water_utility_portfolio', 'dealership_group_portfolio']).optional()")
    text = text.replace("enum:['premium_exterior','water_tank','swppp_site','water_utility_portfolio']", "enum:['premium_exterior','water_tank','swppp_site','water_utility_portfolio','dealership_group_portfolio']")
    test.write_text(text)
