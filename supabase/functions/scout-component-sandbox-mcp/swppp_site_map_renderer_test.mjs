import assert from 'node:assert/strict'
import { build, transform } from 'esbuild'
import { readFile } from 'node:fs/promises'

const directory = new URL('./', import.meta.url)
const [modelSource, rendererSource, mapContract, serverSource, viewSource, generatedView] = await Promise.all([
  readFile(new URL('swppp_site_point_map_model.ts', directory), 'utf8'),
  readFile(new URL('swppp_site_map_renderer.ts', directory), 'utf8'),
  readFile(new URL('MAP_CONTRACT.md', directory), 'utf8'),
  readFile(new URL('index.ts', directory), 'utf8'),
  readFile(new URL('view.ts', directory), 'utf8'),
  readFile(new URL('view.generated.ts', directory), 'utf8'),
])

for (const source of [modelSource, rendererSource]) {
  assert.equal(source.includes('document.createElement'), false)
  assert.equal(source.includes('ResizeObserver'), false)
  assert.equal(source.includes('window.openai'), false)
  assert.equal(source.toLowerCase().includes('maplibre'), false)
  assert.equal(source.includes('WebGL'), false)
  assert.equal(source.includes('Worker'), false)
}

for (const forbidden of ['footprint', 'service_radius', 'property_boundary', 'access_area', 'disturbance_polygon']) {
  assert.equal(modelSource.includes(forbidden), false)
  assert.equal(rendererSource.includes(forbidden), false)
}

const exemplar = {
  contract_version: 'swppp_site_map_v1',
  opportunity_type: 'swppp_site',
  candidate_key: 'swppp_site:ohio-epa:1GC10896*AG',
  site_name: 'HAM-Brent Spence Project (PID 116649)',
  location_label: 'Hamilton County, Ohio',
  project_reference: 'PID 116649',
  site_point: {
    lon: -84.521,
    lat: 39.097,
    geometry_type: 'Point',
    semantics: 'authoritative_permit_location_point',
    guardrail: 'Point-only Ohio EPA permit location.',
  },
  permit: {
    evidence_status: 'active_documented_state_construction_permit',
    status: 'ACTIVE',
    type: 'CONSTRUCTION_STORMWATER',
    category: 'GENERAL_CONSTRUCTION',
    permit_number: '1GC10896*AG',
    registry_id: 'OHGC18548',
    master_permit_number: 'OHC000006',
    issue_date: '2026-03-12',
    effective_date: '2026-03-12',
    expiration_date: '2028-04-22',
    termination_date: null,
    documented_total_acres: 135,
    acreage_semantics: 'Documented total permit acreage only.',
  },
  source: {
    slug: 'ohio-epa-npdes-construction',
    name: 'Ohio EPA Construction Permits (NPDES)',
    authority: 'Ohio Environmental Protection Agency',
    authority_level: 'state',
    source_native_id: 'ohio-epa:1GC10896*AG',
    source_url: 'https://geo.epa.ohio.gov/arcgis/rest/services/SurfaceWater/NPDES/FeatureServer/3',
    last_seen_at: '2026-09-10T11:50:17.289218+00:00',
  },
  buyer: {
    classification: 'unresolved',
    organization_id: null,
    guardrail: 'Buyer unresolved.',
  },
  why_investigate: 'Active documented construction-stormwater permit.',
  guardrail: 'Not proof of active procurement or buyer intent.',
}

const modelBuild = await build({
  entryPoints: [new URL('swppp_site_point_map_model.ts', directory).pathname],
  bundle: true,
  format: 'esm',
  platform: 'node',
  target: 'node24',
  write: false,
})
const modelUrl = `data:text/javascript;base64,${Buffer.from(modelBuild.outputFiles[0].text).toString('base64')}`
const { buildScoutSwpppSitePointMapModel, SCOUT_SWPPP_SITE_POINT_ZOOM } = await import(modelUrl)
const model = buildScoutSwpppSitePointMapModel(exemplar)

assert.equal(SCOUT_SWPPP_SITE_POINT_ZOOM, 15)
assert.deepEqual(model.center, { lon: exemplar.site_point.lon, lat: exemplar.site_point.lat })
assert.equal(model.marker.lon, exemplar.site_point.lon)
assert.equal(model.marker.lat, exemplar.site_point.lat)
assert.equal(model.marker.geometry_type, 'Point')
assert.equal(model.marker.semantics, 'authoritative_permit_location_point')
assert.equal(model.marker.source_native_id, exemplar.source.source_native_id)
assert.equal(model.marker.permit_number, exemplar.permit.permit_number)
assert.equal(model.zoom, 15)
assert.equal('bounds' in model, false)
assert.equal('radius' in model, false)

const rendererBuild = await build({
  entryPoints: [new URL('swppp_site_map_renderer.ts', directory).pathname],
  bundle: true,
  format: 'esm',
  platform: 'node',
  target: 'node24',
  write: false,
})
const rendererUrl = `data:text/javascript;base64,${Buffer.from(rendererBuild.outputFiles[0].text).toString('base64')}`
const { buildScoutSwpppSiteRasterFrame } = await import(rendererUrl)

const viewportCases = [
  { width: 280, height: 210 },
  { width: 320, height: 210 },
  { width: 366, height: 210 },
  { width: 406, height: 210 },
]
for (const expected of viewportCases) {
  const frame = buildScoutSwpppSiteRasterFrame(exemplar, expected.width, expected.height, {
    tileUrlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  })
  assert.equal(frame.zoom, 15)
  assert.equal(frame.width, expected.width)
  assert.equal(frame.height, expected.height)
  assert.ok(frame.tiles.length >= 4 && frame.tiles.length <= 6)
  assert.ok(frame.tiles.every((tile) => /^https:\/\/tile\.openstreetmap\.org\/15\/\d+\/\d+\.png$/.test(tile.url)))
  assert.equal(frame.marker.left, frame.width / 2)
  assert.equal(frame.marker.top, frame.height / 2)
}

const clampedFrame = buildScoutSwpppSiteRasterFrame(exemplar, 320, 210, {
  tileUrlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  maxZoom: 14,
})
assert.equal(clampedFrame.zoom, 14)

const browserBuild = await build({
  entryPoints: [new URL('swppp_site_map_renderer.ts', directory).pathname],
  bundle: true,
  format: 'esm',
  platform: 'browser',
  target: 'es2022',
  write: false,
  minify: true,
  legalComments: 'none',
})
const rendererJs = browserBuild.outputFiles[0]?.text
assert.ok(rendererJs)
await transform(rendererJs, { loader: 'js', format: 'esm', target: 'es2022' })
assert.equal(rendererJs.toLowerCase().includes('maplibre'), false)
assert.equal(rendererJs.includes('Worker'), false)
assert.equal(rendererJs.includes('document.createElement'), false)

// This batch is pure renderer groundwork, not live integration.
assert.equal(serverSource.includes('buildScoutSwpppSiteRasterFrame'), false)
assert.equal(viewSource.includes('buildScoutSwpppSiteRasterFrame'), false)
assert.equal(generatedView.includes('swppp_site_map_v1'), true)
assert.ok(mapContract.includes('SWPPP-site isolated point renderer'))

console.log(`Scout SWPPP-site point raster checks passed across ${viewportCases.length} viewport widths. JS ${rendererJs.length} bytes.`)
