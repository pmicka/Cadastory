from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def read(rel):
    return (ROOT / rel).read_text()


def write(rel, text):
    (ROOT / rel).write_text(text)


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{label}: expected exactly one literal match, found {count}')
    return text.replace(old, new, 1)


def sub_once(text, pattern, replacement, label, flags=0):
    updated, count = re.subn(pattern, replacement, text, count=1, flags=flags)
    if count != 1:
        raise RuntimeError(f'{label}: expected exactly one regex match, found {count}')
    return updated


# Build one shared JSON-schema surface from the already-released contract gateway definitions.
contract_gateway_path = 'supabase/functions/scout-mcp-contract/index.ts'
contract_gateway = read(contract_gateway_path)
start = contract_gateway.index('function sandboxPremiumMapSchema(){')
end = contract_gateway.index('function sandboxTool(){', start)
schema_block = contract_gateway[start:end]
schema_block = re.sub(r'(?m)^function (sandbox[A-Za-z0-9]+Schema)\(', r'export function \1(', schema_block)
shared_schema = """import { sandboxSwpppSiteMapSchema, sandboxSwpppSiteOpportunitySchema } from './scout_sandbox_swppp_schema.ts'\nimport { sandboxWaterUtilityPortfolioMapSchema, sandboxWaterUtilityPortfolioOpportunitySchema } from './scout_sandbox_water_portfolio_schema.ts'\nimport { sandboxDealershipPortfolioMapSchema, sandboxDealershipPortfolioOpportunitySchema } from './scout_sandbox_dealership_portfolio_schema.ts'\nimport { sandboxHotelPortfolioMapSchema, sandboxHotelPortfolioOpportunitySchema } from './scout_sandbox_hotel_portfolio_schema.ts'\nimport { SCOUT_SANDBOX_OPPORTUNITY_TYPES } from './scout_sandbox_manifest.ts'\n\n""" + schema_block
shared_schema += """\nexport function sandboxOpportunityTypeInputSchema(){return {type:'object',properties:{opportunity_type:{type:'string',enum:[...SCOUT_SANDBOX_OPPORTUNITY_TYPES]}},additionalProperties:false}}\n"""
write('supabase/functions/_shared/scout_sandbox_contract_schema.ts', shared_schema)

# Make both public wrappers consume the same manifest and output schema.
for gateway_path in ['supabase/functions/scout-mcp-contract/index.ts', 'supabase/functions/scout-connect/index.ts']:
    source = read(gateway_path)
    source = re.sub(
        r"import \{ sandboxSwpppSiteMapSchema, sandboxSwpppSiteOpportunitySchema \} from '../_shared/scout_sandbox_swppp_schema\.ts'\n"
        r"import \{ sandboxWaterUtilityPortfolioMapSchema, sandboxWaterUtilityPortfolioOpportunitySchema \} from '../_shared/scout_sandbox_water_portfolio_schema\.ts'\n"
        r"import \{ sandboxDealershipPortfolioMapSchema, sandboxDealershipPortfolioOpportunitySchema \} from '../_shared/scout_sandbox_dealership_portfolio_schema\.ts'\n"
        r"import \{ sandboxHotelPortfolioMapSchema, sandboxHotelPortfolioOpportunitySchema \} from '../_shared/scout_sandbox_hotel_portfolio_schema\.ts'\n",
        "import { SCOUT_SANDBOX_OPPORTUNITY_TYPES, SCOUT_SANDBOX_RESOURCE_URI, scoutSandboxCompatibilityResourceUris, scoutSandboxToolDescription } from '../_shared/scout_sandbox_manifest.ts'\nimport { sandboxOpportunityTypeInputSchema, sandboxResultSchema } from '../_shared/scout_sandbox_contract_schema.ts'\n",
        source,
        count=1,
    )
    if "scout_sandbox_contract_schema.ts" not in source:
        raise RuntimeError(f'{gateway_path}: shared schema imports were not installed')
    source = re.sub(r"const SANDBOX_RESOURCE_URI = 'ui://scout/component-sandbox/v\d+'", "const SANDBOX_RESOURCE_URI = SCOUT_SANDBOX_RESOURCE_URI", source, count=1)
    source = re.sub(r"const SANDBOX_COMPATIBILITY_RESOURCE_URIS = \[[^\n]*\]", "const SANDBOX_COMPATIBILITY_RESOURCE_URIS = scoutSandboxCompatibilityResourceUris()", source, count=1)
    local_start = source.index('function sandboxPremiumMapSchema(){')
    local_end = source.index('function sandboxTool(){', local_start)
    source = source[:local_start] + source[local_end:]
    source = re.sub(r"description:'Owner-only read-only developer tool that renders one bounded Scout MCP Apps opportunity card and matching map\.[^']*compatibility default\.'", "description:scoutSandboxToolDescription()", source, count=1)
    source = re.sub(r"inputSchema:\{type:'object',properties:\{opportunity_type:\{type:'string',enum:\[[^\]]+\]\}\},additionalProperties:false\}", "inputSchema:sandboxOpportunityTypeInputSchema()", source, count=1)
    write(gateway_path, source)

# Refactor the component server around the declarative portfolio manifest/runtime registry.
index_path = 'supabase/functions/scout-component-sandbox-mcp/index.ts'
source = read(index_path)
source = replace_once(
    source,
    "import * as z from 'npm:zod@4.2.0/v4'\n",
    "import * as z from 'npm:zod@4.2.0/v4'\nimport {\n  SCOUT_SANDBOX_MAX_EMBEDDED_RASTER_TILES,\n  SCOUT_SANDBOX_OPPORTUNITY_TYPES,\n  SCOUT_SANDBOX_PORTFOLIO_MANIFEST,\n  SCOUT_SANDBOX_PORTFOLIO_TYPES,\n  SCOUT_SANDBOX_RESOURCE_URI,\n  isScoutSandboxPortfolioType,\n  isScoutSandboxRasterTileAllowed,\n  scoutSandboxCompatibilityResourceUris,\n  scoutSandboxCompatibilityUsesEmbeddedRaster,\n  scoutSandboxToolDescription,\n  type ScoutSandboxPortfolioType,\n} from '../_shared/scout_sandbox_manifest.ts'\nimport { assertScoutSandboxPortfolioImplementationCoverage, scoutSandboxPortfolioImplementation } from './portfolio_registry.ts'\n",
    'component manifest imports',
)
for module in ['water_portfolio_map_model', 'dealership_portfolio_map_model', 'hotel_portfolio_map_model']:
    source = sub_once(source, rf"import \{{[\s\S]*?\}} from './{module}\.ts'\n", '', f'remove {module} imports')
for module in ['water_portfolio_map_renderer', 'dealership_portfolio_map_renderer', 'hotel_portfolio_map_renderer']:
    source = re.sub(rf"import \{{[^\n]+\}} from './{module}\.ts'\n", '', source, count=1)

source = sub_once(
    source,
    r"const RESOURCE_URI = 'ui://scout/component-sandbox/v\d+'\nconst COMPATIBILITY_RESOURCE_URIS = \[[\s\S]*?\] as const",
    "const RESOURCE_URI = SCOUT_SANDBOX_RESOURCE_URI\nconst COMPATIBILITY_RESOURCE_URIS = scoutSandboxCompatibilityResourceUris()",
    'component resource registry',
    flags=re.S,
)
source = sub_once(
    source,
    r"const SANDBOX_MAP_CENTERS = \[[\s\S]*?const HOTEL_PORTFOLIO_TILE_BOUNDS = \{[^\n]+\} as const\n",
    '',
    'remove component tile copies',
    flags=re.S,
)
source = sub_once(
    source,
    r"async function loadScoutSandboxWaterUtilityPortfolioMap\(\) \{[\s\S]*?async function loadScoutSandboxHotelPortfolioMap\(\) \{[\s\S]*?\n\}\n\n",
    "async function loadScoutSandboxPortfolioMap(type: ScoutSandboxPortfolioType) {\n  const registration = SCOUT_SANDBOX_PORTFOLIO_MANIFEST[type]\n  const implementation = scoutSandboxPortfolioImplementation(type)\n  const { data, error } = await admin.rpc(registration.rpc)\n  if (error) throw new Error(`Scout sandbox ${type} map is unavailable`)\n  const map = implementation.normalizeMap(data)\n  if (!map) throw new Error(`Scout sandbox ${type} map did not satisfy the bounded contract`)\n  return map\n}\n\n",
    'generic portfolio loader',
    flags=re.S,
)
source = replace_once(source, 'const MAX_EMBEDDED_RASTER_TILES = 40', 'const MAX_EMBEDDED_RASTER_TILES = SCOUT_SANDBOX_MAX_EMBEDDED_RASTER_TILES', 'embedded raster budget')
source = sub_once(
    source,
    r"async function loadEmbeddedSandboxTiles\(\) \{[\s\S]*?\n\}\n\nlet scoutViewHtmlPromise",
    "async function loadEmbeddedSandboxTiles() {\n  assertScoutSandboxPortfolioImplementationCoverage()\n  const tileUrlTemplate = `${SUPABASE_URL}/functions/v1/scout-component-sandbox-mcp/map-tile/{z}/{x}/{y}.png`\n  const [premiumMap, waterTankMap, swpppMap] = await Promise.all([\n    loadScoutSandboxSingleSiteMap(),\n    loadScoutSandboxWaterTankMap(),\n    loadScoutSandboxSwpppSiteMap(),\n  ])\n  const frames: Array<{ tiles: EmbeddedRasterTile[] }> = [\n    buildScoutSingleSiteRasterFrame(premiumMap, 456, 210, { tileUrlTemplate }),\n    buildScoutWaterTankRasterFrame(waterTankMap, 456, 210, { tileUrlTemplate }),\n    buildScoutSwpppSiteRasterFrame(swpppMap, 456, 210, { tileUrlTemplate }),\n  ]\n  for (const type of SCOUT_SANDBOX_PORTFOLIO_TYPES) {\n    const map = await loadScoutSandboxPortfolioMap(type)\n    const implementation = scoutSandboxPortfolioImplementation(type)\n    for (const frameSize of SCOUT_SANDBOX_PORTFOLIO_MANIFEST[type].rasterFrames) {\n      frames.push(implementation.buildRasterFrame(map, frameSize.width, frameSize.height, { tileUrlTemplate }))\n    }\n  }\n  const uniqueTiles = new Map<string, EmbeddedRasterTile>()\n  for (const frame of frames) {\n    for (const tile of frame.tiles) uniqueTiles.set(tile.url, tile)\n  }\n  if (uniqueTiles.size > MAX_EMBEDDED_RASTER_TILES) {\n    throw new Error(`Scout sandbox embedded raster requires ${uniqueTiles.size} tiles, exceeding bounded budget ${MAX_EMBEDDED_RASTER_TILES}`)\n  }\n  return await Promise.all(Array.from(uniqueTiles.values(), loadEmbeddedRasterTile))\n}\n\nlet scoutViewHtmlPromise",
    'registry-driven embedded rasters',
    flags=re.S,
)
source = sub_once(
    source,
    r"text: \(\(compatibilityUri ===[\s\S]*?\? await loadScoutViewHtml\(\)\n\s*: SCOUT_VIEW_HTML\.replace\('__SCOUT_EMBEDDED_RASTER_TILES__', '\[\]'\)\)\n\s*\.replace\('__SCOUT_DIAGNOSTIC_RESOURCE_URI__', compatibilityUri\)",
    "text: (scoutSandboxCompatibilityUsesEmbeddedRaster(compatibilityUri)\n            ? await loadScoutViewHtml()\n            : SCOUT_VIEW_HTML.replace('__SCOUT_EMBEDDED_RASTER_TILES__', '[]'))\n            .replace('__SCOUT_DIAGNOSTIC_RESOURCE_URI__', compatibilityUri)",
    'compatibility raster policy',
    flags=re.S,
)

hotel_schema_match = re.search(r"const hotelPortfolioResultSchema=z\.object\([^\n]+\)\n", source)
if not hotel_schema_match:
    raise RuntimeError('component result schema insertion point not found')
insert = hotel_schema_match.group(0) + "\nconst componentResultSchemaByType = {\n  premium_exterior: premiumResultSchema,\n  water_tank: waterTankResultSchema,\n  swppp_site: swpppSiteResultSchema,\n  water_utility_portfolio: waterUtilityPortfolioResultSchema,\n  dealership_group_portfolio: dealershipPortfolioResultSchema,\n  hotel_management_portfolio: hotelPortfolioResultSchema,\n} as const\n"
source = source[:hotel_schema_match.start()] + insert + source[hotel_schema_match.end():]
source = source.replace("const server = new McpServer({ name: 'Scout UI Foundation', version: '2.3.4' })", "const server = new McpServer({ name: 'Scout UI Foundation', version: '2.3.5' })")
source = re.sub(r"description: 'Owner-only read-only developer tool that renders one bounded Scout MCP Apps opportunity card and matching map\.[^']*compatibility default\.'", "description: scoutSandboxToolDescription()", source, count=1)
source = re.sub(r"opportunity_type: z\.enum\(\[[^\]]+\]\)\.optional\(\)", "opportunity_type: z.enum(SCOUT_SANDBOX_OPPORTUNITY_TYPES).optional()", source, count=1)
source = replace_once(
    source,
    "outputSchema: z.discriminatedUnion('opportunity_type', [premiumResultSchema, waterTankResultSchema, swpppSiteResultSchema, waterUtilityPortfolioResultSchema, dealershipPortfolioResultSchema, hotelPortfolioResultSchema]),",
    "outputSchema: z.discriminatedUnion('opportunity_type', SCOUT_SANDBOX_OPPORTUNITY_TYPES.map((type) => componentResultSchemaByType[type]) as any),",
    'component output registry',
)
source = sub_once(
    source,
    r"\n      if \(selectedType === 'hotel_management_portfolio'\) \{[\s\S]*?\n      if \(selectedType === 'swppp_site'\) \{",
    "\n      if (isScoutSandboxPortfolioType(selectedType)) {\n        const map = await loadScoutSandboxPortfolioMap(selectedType)\n        const implementation = scoutSandboxPortfolioImplementation(selectedType)\n        const opportunity = implementation.buildOpportunity(map)\n        if (!implementation.identityMatches(map, opportunity)) throw new Error(`Scout sandbox ${selectedType} opportunity and map identity do not match`)\n        return {\n          content: [{ type: 'text', text: implementation.responseText(opportunity) }],\n          structuredContent: { surface: 'scout_component_sandbox', opportunity_type: selectedType, opportunity, map },\n        }\n      }\n\n      if (selectedType === 'swppp_site') {",
    'generic portfolio invocation',
    flags=re.S,
)
source = sub_once(
    source,
    r"function tileCenter\([\s\S]*?\nasync function serveSandboxTile",
    "function parseSandboxTile(url: URL) {\n  const match = url.pathname.match(/\\/map-tile\\/(\\d{1,2})\\/(\\d{1,8})\\/(\\d{1,8})\\.png$/)\n  if (!match) return null\n  const z = Number(match[1]), x = Number(match[2]), y = Number(match[3])\n  const count = Math.pow(2, z)\n  if (!Number.isInteger(z) || z < 7 || z > 18 || x < 0 || y < 0 || x >= count || y >= count) return null\n  return isScoutSandboxRasterTileAllowed(z, x, y) ? { z, x, y } : null\n}\n\nasync function serveSandboxTile",
    'manifest tile allowlist',
    flags=re.S,
)
write(index_path, source)

# Repair the source View and make its supported-type/map dispatch derive from the shared manifest.
view_path = 'supabase/functions/scout-component-sandbox-mcp/view.ts'
view = read(view_path)
view = replace_once(
    view,
    "import { App, PostMessageTransport } from '@modelcontextprotocol/ext-apps'\n",
    "import { App, PostMessageTransport } from '@modelcontextprotocol/ext-apps'\nimport {\n  SCOUT_SANDBOX_MAX_EMBEDDED_RASTER_TILES,\n  isScoutSandboxOpportunityType,\n  isScoutSandboxPortfolioType,\n  type ScoutSandboxOpportunityType as ScoutViewOpportunityType,\n} from '../_shared/scout_sandbox_manifest.ts'\nimport { scoutSandboxPortfolioImplementation } from './portfolio_registry.ts'\n",
    'view manifest imports',
)
for module in ['water_portfolio_map_model', 'dealership_portfolio_map_model', 'hotel_portfolio_map_model']:
    view = re.sub(rf"import \{{[\s\S]*?\}} from './{module}\.ts'\n", '', view, count=1)
view = re.sub(r"import \{ buildScoutDealershipPortfolioRasterFrame \} from './dealership_portfolio_map_renderer\.ts'\n", '', view, count=1)
view = re.sub(r"\ntype ScoutViewOpportunityType = ScoutSandboxOpportunityType \| 'water_utility_portfolio' \| 'dealership_group_portfolio' \| 'hotel_management_portfolio'\n", '\n', view, count=1)
view = replace_once(view, "const SCOUT_RASTER_ATTRIBUTION_URL = 'https://www.openstreetmap.org/copyright'\n", "const SCOUT_RASTER_ATTRIBUTION_URL = 'https://www.openstreetmap.org/copyright'\nconst SCOUT_SANDBOX_PORTFOLIO_MOUNTS = {\n  water_utility_portfolio: mountScoutWaterUtilityPortfolioMap,\n  dealership_group_portfolio: mountScoutDealershipPortfolioMap,\n  hotel_management_portfolio: mountScoutHotelPortfolioMap,\n} as const\n", 'view portfolio mount registry')
view = replace_once(view, 'if (!Array.isArray(value) || value.length > 40) return undefined', 'if (!Array.isArray(value) || value.length > SCOUT_SANDBOX_MAX_EMBEDDED_RASTER_TILES) return undefined', 'view embedded budget')
view = view.replace('normalizeScoutSandboxHotelPortfolioOpportunity(value)', "scoutSandboxPortfolioImplementation('hotel_management_portfolio').normalizeOpportunity(value)")
view = view.replace('normalizeScoutSandboxDealershipPortfolioOpportunity(value)', "scoutSandboxPortfolioImplementation('dealership_group_portfolio').normalizeOpportunity(value)")
view = view.replace('normalizeScoutSandboxWaterUtilityPortfolioOpportunity(value)', "scoutSandboxPortfolioImplementation('water_utility_portfolio').normalizeOpportunity(value)")
view = view.replace("(opportunityType === 'water_utility_portfolio' || opportunityType === 'dealership_group_portfolio' || opportunityType === 'hotel_management_portfolio')", 'isScoutSandboxPortfolioType(opportunityType)')
view = sub_once(
    view,
    r"\n      if \(opportunityType === 'hotel_management_portfolio'\) \{[\s\S]*?\} else if \(opportunityType === 'dealership_group_portfolio'\) \{ diagnostic\(\{ dealershipReady: true, dealershipError: 'none' \}\); diagnosticOverlay\(mapState\) \}",
    "\n      if (opportunityType === 'dealership_group_portfolio') { diagnostic({ dealershipReady: true, dealershipError: 'none' }); diagnosticOverlay(mapState) }",
    'repair hotel onReady drift',
    flags=re.S,
)
view = sub_once(
    view,
    r"    if \(opportunityType === 'dealership_group_portfolio'\) \{[\s\S]*?\n    \} else if \(opportunityType === 'swppp_site'\) \{",
    "    if (isScoutSandboxPortfolioType(opportunityType)) {\n      const implementation = scoutSandboxPortfolioImplementation(opportunityType)\n      const mapData = implementation.normalizeMap(value)\n      if (!mapData) {\n        if (opportunityType === 'dealership_group_portfolio') diagnostic({ dealershipNormalizer: 'failed' })\n        mapState.textContent = 'Portfolio map unavailable'\n        setState(`Scout ${opportunityType} map result failed validation`)\n        return\n      }\n      if (opportunityType === 'dealership_group_portfolio') {\n        const diagnosticFrame = implementation.buildRasterFrame(mapData, mapContainer.clientWidth, mapContainer.clientHeight, mapOptions)\n        const matchingEmbeddedTiles = embeddedTiles ? diagnosticFrame.tiles.filter((tile: any) => Boolean(embeddedTiles[tile.url])).length : 0\n        diagnostic({ dealershipNormalizer: 'passed', dealershipContainerWidth: mapContainer.clientWidth, dealershipContainerHeight: mapContainer.clientHeight, dealershipFrameWidth: diagnosticFrame.width, dealershipFrameHeight: diagnosticFrame.height, dealershipZoom: diagnosticFrame.zoom, dealershipRequiredTiles: diagnosticFrame.tiles.length, dealershipMatchingEmbeddedTiles: matchingEmbeddedTiles, dealershipMarkers: diagnosticFrame.markers.length, dealershipTileSource: embeddedTiles ? 'embedded_available' : 'embedded_missing', dealershipReady: false, dealershipError: 'not_yet' })\n      }\n      mapContainer.setAttribute('role', 'img')\n      mapContainer.setAttribute('aria-label', implementation.ariaLabel(mapData))\n      const mount = SCOUT_SANDBOX_PORTFOLIO_MOUNTS[opportunityType] as any\n      mapHandle = mount(mapContainer, mapData, { ...mapOptions, embeddedTiles })\n    } else if (opportunityType === 'swppp_site') {",
    'registry portfolio map dispatch',
    flags=re.S,
)
view = sub_once(
    view,
    r"  if \(opportunityType !== 'premium_exterior' && opportunityType !== 'water_tank' && opportunityType !== 'swppp_site' && opportunityType !== 'water_utility_portfolio' && opportunityType !== 'dealership_group_portfolio'\) \{",
    "  if (!isScoutSandboxOpportunityType(opportunityType)) {",
    'view supported-type guard',
)
view = view.replace("const app = new App({ name: 'scout-ui-foundation', version: '2.14.0' })", "const app = new App({ name: 'scout-ui-foundation', version: '2.15.0' })")
write(view_path, view)

# Keep foundation assertions focused on architecture instead of copied enum/resource lists.
foundation_path = 'supabase/functions/scout-component-sandbox-mcp/foundation_test.mjs'
foundation = read(foundation_path)
foundation = re.sub(r"assert\.ok\(connectGateway\.includes\(\"sandboxWaterTankOpportunitySchema\"\)\);\nassert\.ok\(contractGateway\.includes\(\"sandboxWaterTankOpportunitySchema\"\)\);\nassert\.ok\(connectGateway\.includes\(\"sandboxWaterTankMapSchema\"\)\);\nassert\.ok\(contractGateway\.includes\(\"sandboxWaterTankMapSchema\"\)\);\n", "assert.ok(connectGateway.includes('SCOUT_SANDBOX_OPPORTUNITY_TYPES'));\nassert.ok(contractGateway.includes('SCOUT_SANDBOX_OPPORTUNITY_TYPES'));\nassert.ok(connectGateway.includes('../_shared/scout_sandbox_contract_schema.ts'));\nassert.ok(contractGateway.includes('../_shared/scout_sandbox_contract_schema.ts'));\n", foundation, count=1)
foundation = re.sub(r"\nfor \(const source of \[server, connectGateway, contractGateway\]\) \{\n  for \(const version of \[[\s\S]*?\n  \}\n\}\n", "\nassert.ok(server.includes('scoutSandboxCompatibilityResourceUris()'));\nassert.ok(connectGateway.includes('scoutSandboxCompatibilityResourceUris()'));\nassert.ok(contractGateway.includes('scoutSandboxCompatibilityResourceUris()'));\n", foundation, count=1)
write(foundation_path, foundation)

# Replace type-specific gateway folklore with generic registry coverage in the test command.
package_path = 'supabase/functions/scout-component-sandbox-mcp/package.json'
package = read(package_path)
package = package.replace(
    'node water_portfolio_map_renderer_test.mjs && node water_portfolio_gateway_contract_test.mjs && node dealership_portfolio_map_renderer_test.mjs && node dealership_portfolio_gateway_contract_test.mjs && node hotel_portfolio_map_renderer_test.mjs && node hotel_portfolio_gateway_contract_test.mjs && node gateway_syntax_test.mjs',
    'node water_portfolio_map_renderer_test.mjs && node dealership_portfolio_map_renderer_test.mjs && node hotel_portfolio_map_renderer_test.mjs && node sandbox_portfolio_contract_test.mjs && node sandbox_raster_registry_test.mjs && node sandbox_registry_contract_test.mjs && node generated_view_parity_test.mjs && node gateway_syntax_test.mjs',
)
write(package_path, package)

for stale in [
    'supabase/functions/scout-component-sandbox-mcp/water_portfolio_gateway_contract_test.mjs',
    'supabase/functions/scout-component-sandbox-mcp/dealership_portfolio_gateway_contract_test.mjs',
    'supabase/functions/scout-component-sandbox-mcp/hotel_portfolio_gateway_contract_test.mjs',
]:
    path = ROOT / stale
    if path.exists():
        path.unlink()

print('Scout sandbox registry hardening bootstrap applied.')
