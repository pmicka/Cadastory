from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMP = ROOT / 'supabase/functions/scout-component-sandbox-mcp'
SHARED = ROOT / 'supabase/functions/_shared'


def replace_once(path: Path, old: str, new: str):
    text = path.read_text()
    if old not in text:
        raise RuntimeError(f'anchor not found in {path}: {old[:120]!r}')
    path.write_text(text.replace(old, new, 1))


# Resource revision forces ChatGPT to fetch the repaired static shell rather than the broken v37 resource.
manifest = SHARED / 'scout_sandbox_manifest.ts'
replace_once(
    manifest,
    'export const SCOUT_SANDBOX_RESOURCE_VERSION = 37 as const',
    'export const SCOUT_SANDBOX_RESOURCE_VERSION = 38 as const',
)

index = COMP / 'index.ts'
text = index.read_text()
text = text.replace('  SCOUT_SANDBOX_OPPORTUNITY_TYPES,\n', '')
text = text.replace('  SCOUT_SANDBOX_PORTFOLIO_TYPES,\n', '')
text = text.replace('  scoutSandboxCompatibilityUsesEmbeddedRaster,\n', '')
text = text.replace(
    '  SCOUT_SANDBOX_PORTFOLIO_MANIFEST,\n',
    '  SCOUT_SANDBOX_OPPORTUNITY_MANIFEST,\n  SCOUT_SANDBOX_PORTFOLIO_MANIFEST,\n',
    1,
)
text = text.replace(
    '  type ScoutSandboxPortfolioType,\n',
    '  type ScoutSandboxOpportunityType,\n  type ScoutSandboxPortfolioType,\n',
    1,
)

old_block = '''type EmbeddedRasterTile = { z: number; x: number; y: number; url: string }\nconst MAX_EMBEDDED_RASTER_TILES = SCOUT_SANDBOX_MAX_EMBEDDED_RASTER_TILES\n\nasync function loadEmbeddedRasterTile(tile: EmbeddedRasterTile) {\n  const response = await fetch(`${MAP_TILE_UPSTREAM}/${tile.z}/${tile.x}/${tile.y}.png`, {\n    headers: { 'user-agent': 'Scout-by-Cadastory-Sandbox/1.0 (+https://github.com/pmicka/Cadastory)' },\n  })\n  if (!response.ok || !String(response.headers.get('content-type')).startsWith('image/png')) {\n    throw new Error('Scout sandbox raster tile is unavailable')\n  }\n  const bytes = new Uint8Array(await response.arrayBuffer())\n  let binary = ''\n  for (const byte of bytes) binary += String.fromCharCode(byte)\n  return { url: tile.url, data_url: `data:image/png;base64,${btoa(binary)}` }\n}\n\nasync function loadEmbeddedSandboxTiles() {\n  assertScoutSandboxPortfolioImplementationCoverage()\n  const tileUrlTemplate = `${SUPABASE_URL}/functions/v1/scout-component-sandbox-mcp/map-tile/{z}/{x}/{y}.png`\n  const [premiumMap, waterTankMap, swpppMap] = await Promise.all([\n    loadScoutSandboxSingleSiteMap(),\n    loadScoutSandboxWaterTankMap(),\n    loadScoutSandboxSwpppSiteMap(),\n  ])\n  const frames: Array<{ tiles: EmbeddedRasterTile[] }> = [\n    buildScoutSingleSiteRasterFrame(premiumMap, 456, 210, { tileUrlTemplate }),\n    buildScoutWaterTankRasterFrame(waterTankMap, 456, 210, { tileUrlTemplate }),\n    buildScoutSwpppSiteRasterFrame(swpppMap, 456, 210, { tileUrlTemplate }),\n  ]\n  for (const type of SCOUT_SANDBOX_PORTFOLIO_TYPES) {\n    const map = await loadScoutSandboxPortfolioMap(type)\n    const implementation = scoutSandboxPortfolioImplementation(type)\n    for (const frameSize of SCOUT_SANDBOX_PORTFOLIO_MANIFEST[type].rasterFrames) {\n      frames.push(implementation.buildRasterFrame(map, frameSize.width, frameSize.height, { tileUrlTemplate }))\n    }\n  }\n  const uniqueTiles = new Map<string, EmbeddedRasterTile>()\n  for (const frame of frames) {\n    for (const tile of frame.tiles) uniqueTiles.set(tile.url, tile)\n  }\n  if (uniqueTiles.size > MAX_EMBEDDED_RASTER_TILES) {\n    throw new Error(`Scout sandbox embedded raster requires ${uniqueTiles.size} tiles, exceeding bounded budget ${MAX_EMBEDDED_RASTER_TILES}`)\n  }\n  return await Promise.all(Array.from(uniqueTiles.values(), loadEmbeddedRasterTile))\n}\n\nlet scoutViewHtmlPromise: Promise<string> | null = null\n\nfunction loadScoutViewHtml() {\n  if (!scoutViewHtmlPromise) {\n    scoutViewHtmlPromise = (async () => {\n      const tiles = await loadEmbeddedSandboxTiles()\n      return SCOUT_VIEW_HTML.replace('__SCOUT_EMBEDDED_RASTER_TILES__', JSON.stringify(tiles))\n    })().catch((error) => {\n      scoutViewHtmlPromise = null\n      throw error\n    })\n  }\n  return scoutViewHtmlPromise\n}\n'''

new_block = '''type EmbeddedRasterTile = { z: number; x: number; y: number; url: string }\ntype EmbeddedRasterPayload = { url: string; data_url: string }\nconst MAX_EMBEDDED_RASTER_TILES = SCOUT_SANDBOX_MAX_EMBEDDED_RASTER_TILES\nconst EMBEDDED_RASTER_FETCH_TIMEOUT_MS = 3500\nconst TILE_URL_TEMPLATE = `${SUPABASE_URL}/functions/v1/scout-component-sandbox-mcp/map-tile/{z}/{x}/{y}.png`\n\nasync function loadEmbeddedRasterTile(tile: EmbeddedRasterTile): Promise<EmbeddedRasterPayload | null> {\n  const controller = new AbortController()\n  const timeout = setTimeout(() => controller.abort(), EMBEDDED_RASTER_FETCH_TIMEOUT_MS)\n  try {\n    const response = await fetch(`${MAP_TILE_UPSTREAM}/${tile.z}/${tile.x}/${tile.y}.png`, {\n      headers: { 'user-agent': 'Scout-by-Cadastory-Sandbox/1.0 (+https://github.com/pmicka/Cadastory)' },\n      signal: controller.signal,\n    })\n    if (!response.ok || !String(response.headers.get('content-type')).startsWith('image/png')) return null\n    const bytes = new Uint8Array(await response.arrayBuffer())\n    let binary = ''\n    for (const byte of bytes) binary += String.fromCharCode(byte)\n    return { url: tile.url, data_url: `data:image/png;base64,${btoa(binary)}` }\n  } catch {\n    return null\n  } finally {\n    clearTimeout(timeout)\n  }\n}\n\nfunction selectedRasterFrames(selectedType: ScoutSandboxOpportunityType, map: any) {\n  const registration = SCOUT_SANDBOX_OPPORTUNITY_MANIFEST[selectedType]\n  if (isScoutSandboxPortfolioType(selectedType)) {\n    const implementation = scoutSandboxPortfolioImplementation(selectedType)\n    return registration.rasterFrames.map((frameSize) =>\n      implementation.buildRasterFrame(map, frameSize.width, frameSize.height, { tileUrlTemplate: TILE_URL_TEMPLATE })\n    )\n  }\n  return registration.rasterFrames.map((frameSize) => {\n    if (selectedType === 'swppp_site') return buildScoutSwpppSiteRasterFrame(map, frameSize.width, frameSize.height, { tileUrlTemplate: TILE_URL_TEMPLATE })\n    if (selectedType === 'water_tank') return buildScoutWaterTankRasterFrame(map, frameSize.width, frameSize.height, { tileUrlTemplate: TILE_URL_TEMPLATE })\n    return buildScoutSingleSiteRasterFrame(map, frameSize.width, frameSize.height, { tileUrlTemplate: TILE_URL_TEMPLATE })\n  })\n}\n\nasync function loadEmbeddedRasterTilesForSelection(selectedType: ScoutSandboxOpportunityType, map: any) {\n  if (isScoutSandboxPortfolioType(selectedType)) assertScoutSandboxPortfolioImplementationCoverage()\n  const uniqueTiles = new Map<string, EmbeddedRasterTile>()\n  for (const frame of selectedRasterFrames(selectedType, map)) {\n    for (const tile of frame.tiles) uniqueTiles.set(tile.url, tile)\n  }\n  if (uniqueTiles.size > MAX_EMBEDDED_RASTER_TILES) {\n    throw new Error(`Scout sandbox ${selectedType} raster requires ${uniqueTiles.size} tiles, exceeding bounded per-result budget ${MAX_EMBEDDED_RASTER_TILES}`)\n  }\n  const payloads = await Promise.all(Array.from(uniqueTiles.values(), loadEmbeddedRasterTile))\n  return payloads.filter((payload): payload is EmbeddedRasterPayload => payload !== null)\n}\n\nfunction staticScoutViewHtml(resourceUri: string) {\n  return SCOUT_VIEW_HTML\n    .replace('__SCOUT_EMBEDDED_RASTER_TILES__', '[]')\n    .replace('__SCOUT_DIAGNOSTIC_RESOURCE_URI__', resourceUri)\n}\n'''

if old_block not in text:
    raise RuntimeError('global embedded-raster block not found')
text = text.replace(old_block, new_block, 1)

text = text.replace("const server = new McpServer({ name: 'Scout UI Foundation', version: '2.3.7' })", "const server = new McpServer({ name: 'Scout UI Foundation', version: '2.3.8' })", 1)
text = text.replace("text: (await loadScoutViewHtml()).replace('__SCOUT_DIAGNOSTIC_RESOURCE_URI__', RESOURCE_URI),", "text: staticScoutViewHtml(RESOURCE_URI),", 1)
old_compat = '''          text: (scoutSandboxCompatibilityUsesEmbeddedRaster(compatibilityUri)\n            ? await loadScoutViewHtml()\n            : SCOUT_VIEW_HTML.replace('__SCOUT_EMBEDDED_RASTER_TILES__', '[]'))\n            .replace('__SCOUT_DIAGNOSTIC_RESOURCE_URI__', compatibilityUri),'''
if old_compat not in text:
    raise RuntimeError('compatibility resource raster block not found')
text = text.replace(old_compat, "          text: staticScoutViewHtml(compatibilityUri),", 1)

# Per-result raster metadata: one selected map only, never every registered map.
text = text.replace(
    "          structuredContent: { surface: 'scout_component_sandbox', opportunity_type: selectedType, opportunity, map },\n        }",
    "          structuredContent: { surface: 'scout_component_sandbox', opportunity_type: selectedType, opportunity, map },\n          _meta: { 'scout/rasterTiles': await loadEmbeddedRasterTilesForSelection(selectedType, map) },\n        }",
    1,
)
text = text.replace(
    "          structuredContent,\n        }\n      }\n\n      if (selectedType === 'water_tank')",
    "          structuredContent,\n          _meta: { 'scout/rasterTiles': await loadEmbeddedRasterTilesForSelection('swppp_site', map) },\n        }\n      }\n\n      if (selectedType === 'water_tank')",
    1,
)
text = text.replace(
    "          structuredContent,\n        }\n      }\n\n      const [opportunity, map] = await Promise.all([",
    "          structuredContent,\n          _meta: { 'scout/rasterTiles': await loadEmbeddedRasterTilesForSelection('water_tank', map) },\n        }\n      }\n\n      const [opportunity, map] = await Promise.all([",
    1,
)
text = text.replace(
    "        structuredContent,\n      }\n    },",
    "        structuredContent,\n        _meta: { 'scout/rasterTiles': await loadEmbeddedRasterTilesForSelection('premium_exterior', map) },\n      }\n    },",
    1,
)
index.write_text(text)

# App bundle revision.
view = COMP / 'view.ts'
replace_once(
    view,
    "const app = new App({ name: 'scout-ui-foundation', version: '2.17.0' })",
    "const app = new App({ name: 'scout-ui-foundation', version: '2.18.0' })",
)

# Regression test reproduces the 42 > 40 global-bundle failure and guards the new transport boundary.
transport_test = COMP / 'sandbox_raster_transport_test.mjs'
transport_test.write_text(r'''import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { build } from 'esbuild'
import { makePortfolioPayload } from './sandbox_portfolio_test_fixtures.mjs'

const directory = new URL('./', import.meta.url)
async function bundleModule(path) {
  const result = await build({ entryPoints: [new URL(path, directory).pathname], bundle: true, format: 'esm', platform: 'node', target: 'node22', write: false })
  return await import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`)
}
const manifest = await bundleModule('../_shared/scout_sandbox_manifest.ts')
const runtime = await bundleModule('portfolio_registry.ts')
const single = await bundleModule('single_site_map_renderer.ts')
const tank = await bundleModule('water_tank_map_renderer.ts')
const swppp = await bundleModule('swppp_site_map_renderer.ts')
const serverSource = await readFile(new URL('./index.ts', import.meta.url), 'utf8')

const tileUrlTemplate = 'https://sandbox.invalid/map-tile/{z}/{x}/{y}.png'
const selections = new Map()
const premiumMap = { footprint: { bounds: { west:-85.7581632620074,south:38.2559260667489,east:-85.7567941378868,north:38.2565851603231 } } }
const waterTankMap = { tank_id:'x',candidate_key:'x',name:'SOUTH PRESSURE ZONE TANK',system_name:'BOWLING GREEN MUNICIPAL UTILITIES',site_point:{lon:-86.4781456168917,lat:36.9655317362621,source_name:'x',source_authority:'x',source_native_id:'x',wris_fid:'x',pwsid:'x',retrieved_at:'2026-09-06T00:00:00Z'} }
const swpppMap = { candidate_key:'x',site_name:'HAM-Brent Spence Project',location_label:'Hamilton County, Ohio',project_reference:'PID 116649',site_point:{lon:-84.521,lat:39.097},source:{authority:'Ohio EPA',source_native_id:'x',last_seen_at:'2026-09-15T00:00:00Z'},permit:{permit_number:'1GC10896*AG'} }

selections.set('premium_exterior', single.buildScoutSingleSiteRasterFrame(premiumMap,456,210,{tileUrlTemplate}).tiles)
selections.set('water_tank', tank.buildScoutWaterTankRasterFrame(waterTankMap,456,210,{tileUrlTemplate}).tiles)
selections.set('swppp_site', swppp.buildScoutSwpppSiteRasterFrame(swpppMap,456,210,{tileUrlTemplate}).tiles)
for (const type of manifest.SCOUT_SANDBOX_PORTFOLIO_TYPES) {
  const implementation = runtime.SCOUT_SANDBOX_PORTFOLIO_IMPLEMENTATIONS[type]
  const map = implementation.normalizeMap(makePortfolioPayload(type))
  assert.ok(map, `missing normalized fixture for ${type}`)
  const tiles = new Map()
  for (const frameSize of manifest.SCOUT_SANDBOX_PORTFOLIO_MANIFEST[type].rasterFrames) {
    const frame = implementation.buildRasterFrame(map,frameSize.width,frameSize.height,{tileUrlTemplate})
    for (const tile of frame.tiles) tiles.set(tile.url,tile)
  }
  selections.set(type,[...tiles.values()])
}

const historicalGlobalBundle = new Set()
for (const tiles of selections.values()) for (const tile of tiles) historicalGlobalBundle.add(tile.url)
assert.ok(historicalGlobalBundle.size > manifest.SCOUT_SANDBOX_MAX_EMBEDDED_RASTER_TILES, `regression fixture must prove the former global bundle exceeds ${manifest.SCOUT_SANDBOX_MAX_EMBEDDED_RASTER_TILES}; got ${historicalGlobalBundle.size}`)
for (const [type,tiles] of selections) {
  assert.ok(tiles.length <= manifest.SCOUT_SANDBOX_MAX_EMBEDDED_RASTER_TILES, `${type} exceeds per-result embedded raster budget`)
}
assert.equal(historicalGlobalBundle.size,42,'expected v37 regression geometry to require 42 global embedded tiles')
assert.equal(serverSource.includes('async function loadEmbeddedSandboxTiles()'),false,'resource must not aggregate all registered maps')
assert.equal(serverSource.includes('loadScoutViewHtml()'),false,'resource must not depend on raster fetch completion')
assert.ok(serverSource.includes(".replace('__SCOUT_EMBEDDED_RASTER_TILES__', '[]')"),'resource shell must be raster-independent')
assert.ok(serverSource.includes("'scout/rasterTiles': await loadEmbeddedRasterTilesForSelection(selectedType, map)"),'portfolio result must carry selected raster metadata')
assert.ok(serverSource.includes("'scout/rasterTiles': await loadEmbeddedRasterTilesForSelection('swppp_site', map)"))
assert.ok(serverSource.includes("'scout/rasterTiles': await loadEmbeddedRasterTilesForSelection('water_tank', map)"))
assert.ok(serverSource.includes("'scout/rasterTiles': await loadEmbeddedRasterTilesForSelection('premium_exterior', map)"))
console.log(`Scout per-result raster transport checks passed: former global bundle ${historicalGlobalBundle.size}/${manifest.SCOUT_SANDBOX_MAX_EMBEDDED_RASTER_TILES}, selected maps remain bounded.`)
''')

package = COMP / 'package.json'
replace_once(
    package,
    'node sandbox_raster_registry_test.mjs && node sandbox_registry_contract_test.mjs',
    'node sandbox_raster_registry_test.mjs && node sandbox_raster_transport_test.mjs && node sandbox_registry_contract_test.mjs',
)

# Permanent smoke must assert static resources plus per-result raster metadata.
pre = COMP / 'sandbox_predeploy_smoke_test.mjs'
pre_text = pre.read_text()
anchor = "assert.ok(component.includes('fromJsonSchema(sandboxResultSchema())'), 'component output validator must derive from shared JSON schema')"
if anchor not in pre_text:
    raise RuntimeError('predeploy shared-schema anchor not found')
pre_text = pre_text.replace(anchor, anchor + "\nassert.equal(component.includes('async function loadEmbeddedSandboxTiles()'), false, 'resource must not globally aggregate raster tiles')\nassert.ok(component.includes(\".replace('__SCOUT_EMBEDDED_RASTER_TILES__', '[]')\"), 'resource must remain a static raster-independent shell')\nassert.ok(component.includes('loadEmbeddedRasterTilesForSelection'), 'tool results must load only selected raster tiles')", 1)
pre.write_text(pre_text)

# Durable design note for future portfolio additions.
map_contract = COMP / 'MAP_CONTRACT.md'
map_text = map_contract.read_text()
marker = '## Per-result raster transport hardening (owner-approved 2026-09-16)'
if marker not in map_text:
    map_text = map_text.rstrip() + r'''

## Per-result raster transport hardening (owner-approved 2026-09-16)

Raster PNG payloads must not be aggregated across every registered sandbox opportunity inside the MCP Apps resource HTML. The resource is a static shell. Each tool result may carry only the bounded raster tiles required for that selected opportunity via result `_meta['scout/rasterTiles']`; the existing allowlisted Scout tile proxy remains the fallback when an embedded tile is unavailable. The per-result tile set must remain at or below `SCOUT_SANDBOX_MAX_EMBEDDED_RASTER_TILES`.

This invariant prevents portfolio growth from increasing every resource read and specifically guards the v37 failure where 24 portfolio tiles plus three six-tile single-site maps required 42 global embedded tiles against a 40-tile ceiling.
''' + '\n'
    map_contract.write_text(map_text)

print('Applied per-result raster transport hardening.')
