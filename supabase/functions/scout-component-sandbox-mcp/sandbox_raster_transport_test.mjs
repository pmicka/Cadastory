import assert from 'node:assert/strict'
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
