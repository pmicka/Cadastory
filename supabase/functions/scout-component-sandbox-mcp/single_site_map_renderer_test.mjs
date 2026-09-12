import { readFile } from 'node:fs/promises'
import assert from 'node:assert/strict'
import { build, transform } from 'esbuild'

const directory = new URL('./', import.meta.url)
const [
  view,
  server,
  rendererSource,
  modelSource,
  generated,
  template,
  mapContract,
  designContract,
  packageJsonText,
] = await Promise.all([
  readFile(new URL('view.ts', directory), 'utf8'),
  readFile(new URL('index.ts', directory), 'utf8'),
  readFile(new URL('single_site_map_renderer.ts', directory), 'utf8'),
  readFile(new URL('single_site_map_model.ts', directory), 'utf8'),
  readFile(new URL('view.generated.ts', directory), 'utf8'),
  readFile(new URL('view.template.html', directory), 'utf8'),
  readFile(new URL('MAP_CONTRACT.md', directory), 'utf8'),
  readFile(new URL('DESIGN_CONTRACT.md', directory), 'utf8'),
  readFile(new URL('package.json', directory), 'utf8'),
])

const packageJson = JSON.parse(packageJsonText)
assert.equal(packageJson.dependencies['maplibre-gl'], '6.9.0')

const deprecatedPatterns = [
  'window.openai',
  'window.message',
  'openai/outputTemplate',
  'openai/widgetAccessible',
  'openai/widgetDescription',
  'openai/widgetCSP',
]
for (const source of [rendererSource, modelSource]) {
  for (const pattern of deprecatedPatterns) assert.equal(source.includes(pattern), false)
}

assert.ok(rendererSource.includes("import { Map as MapLibreMap"))
assert.ok(rendererSource.includes("from 'maplibre-gl'"))
assert.ok(rendererSource.includes("maplibre-gl/dist/maplibre-gl.css"))
assert.ok(rendererSource.includes('interactive: false'))
assert.ok(rendererSource.includes('attributionControl: {}'))
assert.ok(rendererSource.includes('trackResize: true'))
assert.ok(rendererSource.includes('renderWorldCopies: false'))
assert.ok(rendererSource.includes('map.fitBounds(model.bounds'))
assert.ok(rendererSource.includes('duration: 0'))
assert.ok(rendererSource.includes('map.remove()'))
assert.equal(rendererSource.includes('new maplibregl.Marker'), false)
assert.equal(rendererSource.includes('.addControl('), false)
assert.equal(rendererSource.includes('cluster:'), false)
assert.equal(rendererSource.includes('scout_get_component_sandbox_map_targets'), false)

const modelBuild = await build({
  entryPoints: [new URL('single_site_map_model.ts', directory).pathname],
  bundle: true,
  format: 'esm',
  platform: 'node',
  target: 'node24',
  write: false,
})
const modelUrl = `data:text/javascript;base64,${Buffer.from(modelBuild.outputFiles[0].text).toString('base64')}`
const { buildScoutSingleSiteMapRenderModel } = await import(modelUrl)

const mapExemplar = {
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

const model = buildScoutSingleSiteMapRenderModel(mapExemplar)
assert.deepEqual(model.bounds, [
  [-85.7581632620074, 38.2559260667489],
  [-85.7567941378868, 38.2565851603231],
])
assert.deepEqual(model.center, [
  (-85.7581632620074 + -85.7567941378868) / 2,
  (38.2559260667489 + 38.2565851603231) / 2,
])
assert.equal(model.footprint.type, 'FeatureCollection')
assert.equal(model.footprint.features.length, 1)
assert.equal(model.footprint.features[0].geometry.type, 'Polygon')
assert.equal(model.footprint.features[0].properties.opportunity_id, mapExemplar.opportunity_id)
assert.equal(model.footprint.features[0].properties.geometry_source_slug, 'ky-ornl-building-footprints')
assert.equal(model.footprint.features[0].properties.linkage_status, 'reconciled_existing_evidence')
assert.equal(JSON.stringify(model.footprint).includes('site_point'), false)
assert.equal(JSON.stringify(model.footprint).includes('38.256732011411'), false)

const rendererBuild = await build({
  entryPoints: [new URL('single_site_map_renderer.ts', directory).pathname],
  bundle: true,
  format: 'esm',
  platform: 'browser',
  target: 'es2022',
  outdir: 'out',
  write: false,
  minify: true,
  legalComments: 'none',
  loader: { '.css': 'css' },
})
const rendererJs = rendererBuild.outputFiles.find((file) => file.path.endsWith('.js'))
const rendererCss = rendererBuild.outputFiles.find((file) => file.path.endsWith('.css'))
assert.ok(rendererJs?.text)
assert.ok(rendererCss?.text)
await transform(rendererJs.text, { loader: 'js', format: 'esm', target: 'es2022' })
assert.ok(rendererCss.text.includes('.maplibregl-map'))
assert.ok(rendererCss.text.includes('.maplibregl-canvas'))
assert.equal(rendererJs.text.includes('window.openai'), false)
assert.equal(rendererJs.text.includes('openai/outputTemplate'), false)

// Batch 2 is renderer-only. The production View/server must remain untouched.
assert.ok(view.includes('single_site_map_renderer'))
assert.ok(view.includes('mountScoutSingleSiteMap'))
assert.ok(server.includes('scout_get_component_sandbox_premium_exterior_map_v1_internal'))
assert.ok(template.includes('data-scout-map'))
assert.ok(generated.includes('maplibre'))
assert.ok(generated.includes('scout-single-site-footprint'))

assert.ok(mapContract.includes('Batch 2 adds the isolated renderer implementation only'))
assert.ok(mapContract.includes('Batch 3 integration scope'))
assert.ok(mapContract.includes('https://tiles.openfreemap.org/styles/positron'))
assert.ok(mapContract.includes('maplibre-gl` pinned to `6.9.0'))
assert.ok(mapContract.includes('never use `maplibre-gl <= 6.4.0`'))
assert.ok(mapContract.includes('GHSA-jrc7-96c5-q579'))
assert.ok(mapContract.includes('interactive: false'))
assert.ok(mapContract.includes('map.remove()'))
assert.ok(mapContract.includes('does **not**'))
assert.ok(designContract.includes('Owner-approved map direction'))
assert.ok(designContract.includes('Batch 2 implements the renderer only'))
assert.ok(designContract.includes('Batch 3 integrates exactly one map tile'))

console.log(`Scout Batch 2 single-site MapLibre renderer checks passed. JS ${rendererJs.text.length} bytes; CSS ${rendererCss.text.length} bytes.`)
