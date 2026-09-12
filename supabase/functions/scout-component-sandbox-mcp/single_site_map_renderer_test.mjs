import { readFile } from 'node:fs/promises'
import assert from 'node:assert/strict'
import { build, transform } from 'esbuild'

const directory = new URL('./', import.meta.url)
const [
  view,
  server,
  rendererSource,
  generated,
  template,
  mapContract,
  designContract,
  packageJsonText,
] = await Promise.all([
  readFile(new URL('view.ts', directory), 'utf8'),
  readFile(new URL('index.ts', directory), 'utf8'),
  readFile(new URL('single_site_map_renderer.ts', directory), 'utf8'),
  readFile(new URL('view.generated.ts', directory), 'utf8'),
  readFile(new URL('view.template.html', directory), 'utf8'),
  readFile(new URL('MAP_CONTRACT.md', directory), 'utf8'),
  readFile(new URL('DESIGN_CONTRACT.md', directory), 'utf8'),
  readFile(new URL('package.json', directory), 'utf8'),
])

const packageJson = JSON.parse(packageJsonText)
assert.equal('maplibre-gl' in packageJson.dependencies, false)
assert.equal(packageJson.dependencies['@modelcontextprotocol/ext-apps'], '2.0.0')

const deprecatedPatterns = [
  'window.openai',
  'window.message',
  'openai/outputTemplate',
  'openai/widgetAccessible',
  'openai/widgetDescription',
  'openai/widgetCSP',
]
for (const source of [rendererSource, view]) {
  for (const pattern of deprecatedPatterns) assert.equal(source.includes(pattern), false)
}

for (const retired of ['maplibre', 'MapLibre', 'WebGL', 'new Worker', '<svg']) {
  assert.equal(rendererSource.includes(retired), false)
}
assert.ok(rendererSource.includes("document.createElement('img')"))
assert.ok(rendererSource.includes("image.referrerPolicy = 'origin'"))
assert.ok(rendererSource.includes('buildScoutSingleSiteRasterFrame'))
assert.ok(rendererSource.includes('replaceChildren()'))
assert.ok(rendererSource.includes('lastFrameWidth'))
assert.ok(rendererSource.includes('lastFrameHeight'))
assert.ok(rendererSource.includes('render(true)'))
assert.ok(rendererSource.includes('render(false)'))
assert.ok(view.includes("https://tile.openstreetmap.org/{z}/{x}/{y}.png"))
assert.ok(view.includes('mountScoutSingleSiteMap'))
assert.equal(view.includes('tiles.openfreemap.org'), false)
assert.equal(view.includes('SCOUT_MAP_STYLE'), false)
assert.equal(server.includes('tiles.openfreemap.org'), false)
assert.ok(server.includes("const MAP_TILE_ORIGIN = 'https://tile.openstreetmap.org'"))
assert.ok(server.includes('csp: { resourceDomains: [MAP_TILE_ORIGIN] }'))
assert.equal(server.includes('connectDomains: [MAP_TILE_ORIGIN]'), false)
assert.ok(server.includes("const RESOURCE_URI = 'ui://scout/component-sandbox/v15'"))
assert.ok(template.includes('<meta name="referrer" content="origin" />'))
assert.ok(template.includes('.scout-map img'))
assert.ok(template.includes('.scout-site-marker'))
assert.ok(template.includes('.scout-map-attribution'))
assert.ok(template.includes('pointer-events: none;'))
assert.equal(template.includes('maplibregl'), false)
assert.equal(template.includes('__SCOUT_VIEW_STYLE__'), false)

// Current MCP Apps lifecycle hardening: host context and actual layout changes
// both schedule the same bounded resize path, and teardown removes observers.
assert.ok(view.includes('app.onhostcontextchanged'))
assert.ok(view.indexOf('app.onhostcontextchanged') < view.indexOf('app.connect('))
assert.ok(view.includes('new ResizeObserver'))
assert.ok(view.includes('carouselResizeObserver.observe(carousel)'))
assert.ok(view.includes('carouselResizeObserver?.disconnect()'))
assert.ok(view.includes('requestAnimationFrame(flushLayoutRefresh)'))
assert.ok(view.includes('cancelAnimationFrame(layoutFrame)'))
assert.ok(view.includes('activeCarouselIndex'))
assert.ok(view.includes('carousel.scrollLeft = targetScrollLeft'))

const exemplar = {
  contract_version: 'single_site_map_v1',
  opportunity_type: 'premium_exterior',
  opportunity_id: '0edb82cd-7487-4f72-a036-8faa8a40bd54',
  name: 'PNC Tower',
  address: '101 S 5th St, Louisville, KY 40202',
  site_point: {
    lon: -85.758115986691,
    lat: 38.256732011411,
    source: 'premium_exterior_target_geocode',
    method: 'US Census exact address match',
  },
  footprint: {
    geometry: {
      type: 'Polygon',
      coordinates: [[
        [-85.756794, 38.256496],
        [-85.757636, 38.256585],
        [-85.758163, 38.255961],
        [-85.756887, 38.255947],
        [-85.756794, 38.256496],
      ]],
    },
    bounds: {
      west: -85.7581632620074,
      south: 38.2559260667489,
      east: -85.7567941378868,
      north: 38.2565851603231,
    },
    footprint_sqft: 71721.90625,
    source: {
      slug: 'ky-ornl-building-footprints',
      name: 'Kentucky ORNL / FEMA USA Structures Building Footprints',
      native_id: '{0927eebf-03a7-40c5-99c8-1cd889ec008e}',
      image_date: '2011-07-06',
      validation_method: 'Unverified',
    },
  },
  linkage: {
    status: 'reconciled_existing_evidence',
    basis: 'first_party_story_count corroborated by matched OSM/Overture building evidence',
    guardrail: 'Facility geocode is not itself building identity; link selected by corroborating physical evidence.',
    target_to_footprint_m: 24.21606122,
    stored_match_distance_m: 76.97888474,
  },
}

const nodeBuild = await build({
  entryPoints: [new URL('single_site_map_renderer.ts', directory).pathname],
  bundle: true,
  format: 'esm',
  platform: 'node',
  target: 'node24',
  write: false,
})
const moduleUrl = `data:text/javascript;base64,${Buffer.from(nodeBuild.outputFiles[0].text).toString('base64')}`
const { buildScoutSingleSiteRasterFrame } = await import(moduleUrl)

const viewportCases = [
  { width: 280, height: 210, zoom: 17, tiles: 4 },
  { width: 320, height: 210, zoom: 17, tiles: 4 },
  { width: 366, height: 210, zoom: 17, tiles: 6 },
  { width: 406, height: 210, zoom: 17, tiles: 6 },
]
for (const expected of viewportCases) {
  const frame = buildScoutSingleSiteRasterFrame(exemplar, expected.width, expected.height, {
    tileUrlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  })
  assert.equal(frame.zoom, expected.zoom)
  assert.equal(frame.width, expected.width)
  assert.equal(frame.height, expected.height)
  assert.equal(frame.tiles.length, expected.tiles)
  assert.ok(frame.tiles.every((tile) => /^https:\/\/tile\.openstreetmap\.org\/17\/\d+\/\d+\.png$/.test(tile.url)))
  assert.ok(frame.marker.left > 0 && frame.marker.left < frame.width)
  assert.ok(frame.marker.top > 0 && frame.marker.top < frame.height)
  assert.ok(Math.abs(frame.marker.left - frame.width / 2) < 0.01)
  assert.ok(Math.abs(frame.marker.top - frame.height / 2) < 0.01)
}

const rendererBuild = await build({
  entryPoints: [new URL('single_site_map_renderer.ts', directory).pathname],
  bundle: true,
  format: 'esm',
  platform: 'browser',
  target: 'es2022',
  write: false,
  minify: true,
  legalComments: 'none',
})
const rendererJs = rendererBuild.outputFiles[0]?.text
assert.ok(rendererJs)
await transform(rendererJs, { loader: 'js', format: 'esm', target: 'es2022' })
assert.equal(rendererJs.includes('maplibre'), false)
assert.equal(rendererJs.includes('Worker'), false)

assert.ok(generated.includes('tile.openstreetmap.org'))
assert.ok(generated.includes('scout-site-marker'))
assert.ok(generated.includes('onhostcontextchanged'))
assert.ok(generated.includes('ResizeObserver'))
assert.equal(generated.includes('maplibre'), false)
assert.ok(mapContract.includes('Proven raster-tile renderer'))
assert.ok(mapContract.includes('tile.openstreetmap.org'))
assert.ok(mapContract.includes('no Web Worker'))
assert.ok(mapContract.includes('mobile ChatGPT host: **verified working**'))
assert.ok(mapContract.includes('desktop ChatGPT host: still requires explicit visual verification'))
assert.ok(designContract.includes('proven raster-tile technique'))
assert.equal(designContract.includes('MapLibre non-interactive'), false)

console.log(`Scout single-site raster hardening checks passed across ${viewportCases.length} viewport widths. JS ${rendererJs.length} bytes.`)
