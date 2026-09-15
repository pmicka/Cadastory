import { readFile } from 'node:fs/promises'
import assert from 'node:assert/strict'

const directory = new URL('./', import.meta.url)
const [server, view, generated, contract, connect, gateway, sharedSchema, mount, template] = await Promise.all([
  readFile(new URL('index.ts', directory), 'utf8'), readFile(new URL('view.ts', directory), 'utf8'),
  readFile(new URL('view.generated.ts', directory), 'utf8'), readFile(new URL('contract.ts', directory), 'utf8'),
  readFile(new URL('../scout-connect/index.ts', directory), 'utf8'), readFile(new URL('../scout-mcp-contract/index.ts', directory), 'utf8'),
  readFile(new URL('../_shared/scout_sandbox_swppp_schema.ts', directory), 'utf8'), readFile(new URL('swppp_site_map_mount.ts', directory), 'utf8'),
  readFile(new URL('view.template.html', directory), 'utf8'),
])

for (const source of [server, connect, gateway]) {







  assert.ok(source.includes('SCOUT_SANDBOX_OPPORTUNITY_TYPES'))
  assert.equal(source.includes('scout_get_component_sandbox_names_v1_internal'), false)
}
assert.ok(server.includes('scout_get_component_sandbox_swppp_site_map_v1_internal'))
assert.ok(server.includes("z.discriminatedUnion('opportunity_type'"))
assert.ok(contract.includes('ScoutSandboxSwpppSiteResult'))
assert.ok(view.includes('normalizeScoutSandboxSwpppSiteOpportunity'))
assert.ok(view.includes('mountScoutSwpppSiteMap'))
assert.ok(view.includes("result?._meta?.['scout/rasterTiles']"))
assert.ok(view.includes('resourceEmbeddedTiles'))
assert.ok(template.includes('scout-embedded-raster-tiles'))
assert.ok(server.includes("text: (await loadScoutViewHtml())"))
assert.ok(server.includes("SCOUT_VIEW_HTML.replace('__SCOUT_EMBEDDED_RASTER_TILES__', JSON.stringify(tiles))"))
assert.equal(server.includes("_meta: { 'scout/rasterTiles': await loadEmbeddedSwpppTiles(map) }"), false)
assert.ok(mount.includes("document.createElement('canvas')"))
assert.ok(mount.includes('createImageBitmap'))
assert.ok(mount.includes("canvas.getContext('2d')"))
assert.ok(mount.includes('context.drawImage'))
assert.equal(mount.includes('image.src = options.embeddedTiles'), false)
assert.ok(view.includes('documented permit acres'))
assert.ok(view.includes('Active permit evidence'))
assert.ok(generated.includes('swppp_site_map_v1'))
assert.ok(generated.includes('authoritative_permit_location_point'))
assert.ok(generated.includes('scout-component-sandbox-mcp/map-tile'))
assert.ok(view.includes("timeZone: 'UTC'"))
assert.ok(sharedSchema.includes("termination_date:{type:'null'}"))
assert.ok(sharedSchema.includes("buyer_resolvability:{type:'string',enum:['unresolved']}"))
assert.ok(mount.includes("document.createElement('img')"))
assert.ok(mount.includes('buildScoutSwpppSiteRasterFrame'))
for (const source of [view, server, generated, mount]) {
  for (const forbidden of ['window.openai', 'MapLibre', 'WebGL', 'new Worker', '<svg']) assert.equal(source.includes(forbidden), false)
}

console.log('Scout SWPPP-site host-visible integration checks passed.')
