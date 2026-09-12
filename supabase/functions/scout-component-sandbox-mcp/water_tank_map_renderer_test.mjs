import { readFile } from 'node:fs/promises'
import assert from 'node:assert/strict'
import { build, transform } from 'esbuild'

const directory = new URL('./', import.meta.url)
const [
  view,
  server,
  generated,
  sharedRendererSource,
  modelSource,
  rendererSource,
  mountSource,
  mapContract,
  packageJsonText,
] = await Promise.all([
  readFile(new URL('view.ts', directory), 'utf8'),
  readFile(new URL('index.ts', directory), 'utf8'),
  readFile(new URL('view.generated.ts', directory), 'utf8'),
  readFile(new URL('single_site_map_renderer.ts', directory), 'utf8'),
  readFile(new URL('water_tank_map_model.ts', directory), 'utf8'),
  readFile(new URL('water_tank_map_renderer.ts', directory), 'utf8'),
  readFile(new URL('water_tank_map_mount.ts', directory), 'utf8'),
  readFile(new URL('MAP_CONTRACT.md', directory), 'utf8'),
  readFile(new URL('package.json', directory), 'utf8'),
])

const packageJson = JSON.parse(packageJsonText)
assert.ok(packageJson.scripts.test.includes('water_tank_map_renderer_test.mjs'))
assert.ok(packageJson.scripts.test.includes('water_tank_map_integration_test.mjs'))
assert.equal(sharedRendererSource.includes('buildScoutCenteredPointRasterFrame'), false)
assert.equal(sharedRendererSource.includes('water_tank'), false)
assert.equal(rendererSource.includes('single_site_map_renderer'), false)
assert.ok(rendererSource.includes('MAX_MERCATOR_LAT = 85.05112878'))
assert.ok(rendererSource.includes('TILE_SIZE = 256'))
assert.ok(rendererSource.includes('ScoutWaterTankRasterFrame'))
assert.ok(modelSource.includes('SCOUT_WATER_TANK_POINT_ZOOM = 17'))
assert.ok(mountSource.includes('buildScoutWaterTankRasterFrame'))

for (const source of [modelSource, rendererSource]) {
  assert.equal(source.includes('time_sensitive'), false)
  assert.equal(source.includes('document.createElement'), false)
  assert.equal(source.includes('ResizeObserver'), false)
  assert.equal(source.includes('window.openai'), false)
  assert.equal(source.includes('maplibre'), false)
  assert.equal(source.includes('WebGL'), false)
}

// Batch 3 wires the isolated point renderer into the selected water-tank View path.
assert.ok(view.includes('mountScoutWaterTankMap'))
assert.ok(view.includes('normalizeScoutSandboxWaterTankMap'))
assert.ok(server.includes('scout_get_component_sandbox_water_tank_map_v1_internal'))
assert.ok(server.includes("opportunity_type: z.enum(['premium_exterior', 'water_tank']).optional()"))
assert.ok(generated.includes('water_tank_single_site_map_v1'))
assert.ok(generated.includes('Rehab signal'))

// The render model/frame remains point-only. It must not manufacture domain geometry.
for (const forbidden of ['footprint', 'service_radius', 'property_boundary', 'access_area', 'tank_diameter']) {
  assert.equal(modelSource.includes(forbidden), false)
  assert.equal(rendererSource.includes(forbidden), false)
}

const exemplar = {
  contract_version: 'water_tank_single_site_map_v1',
  opportunity_type: 'water_tank',
  tank_id: 'a5ffa1cd-626f-4735-b1a3-5849a443b0ee',
  candidate_key: 'water_tank:a5ffa1cd-626f-4735-b1a3-5849a443b0ee',
  name: 'SOUTH PRESSURE ZONE TANK',
  system_name: 'BOWLING GREEN MUNICIPAL UTILITIES',
  site_point: {
    lon: -86.4781456168917,
    lat: 36.9655317362621,
    source: 'kentucky_wris_water_tank',
    source_slug: 'ky-kia-water-tanks',
    source_name: 'Kentucky WRIS Water Tanks',
    source_authority: 'Kentucky Infrastructure Authority / WRIS',
    source_native_id: 'SOUTH PRESSURE ZONE TANK',
    wris_fid: '00AB7B0C8D56F05717FDFCF0B4000001',
    pwsid: 'KY1140038',
    retrieved_at: '2026-09-06T02:22:13.294139+00:00',
  },
  asset: {
    tank_type: 'ELEVATED',
    capacity_gallons: 1000000,
    construction_date: '2022-07-15',
    last_cleaning_date: '2022-07-15',
    last_inspection_date: '2022-07-15',
    out_of_service: false,
  },
  geometry: {
    morphology_class: 'composite_elevated',
    support_geometry: 'single_pedestal',
    cross_bracing_status: 'none',
    support_leg_count: null,
    operator_assessment: 'favorable',
    operator_assessment_basis: 'Trusted pilot-operator field expertise: single-pedestal geometry is comparatively favorable for drone cleaning.',
    evidence_kind: 'engineering_document',
    confidence: 0.995,
    source_authority: 'BGMU RFB# 2020-22 project description / ConstructConnect public project record',
    source_url: 'https://projects.constructconnect.com/details/5237030-4868-construction-of-the-south-pressure-zone-spz-1-million-gallon-elevated-water-storage-tank%26find_loc%3DKY-42101',
    observed_on: '2026-09-07',
    media_retained: false,
    guardrail: 'Morphology is evidence-backed, while cleaning favorability reflects trusted operator field expertise; verify site-specific access and current physical conditions before planning work.',
  },
  project_linkage: {
    project_id: '828f06ab-f309-4216-9129-253897a85e88',
    pnum: 'WX21227115',
    status: 'REHAB',
    purpose: 'OTHER',
    other_purpose: 'TANK IMPROVEMENTS',
    match_method: 'same_pwsid_nearest',
    match_distance_m: 0.0000353,
    source_modified_at: '2026-01-20T14:03:03+00:00',
    guardrail: 'The linked REHAB / tank-improvements record is a current maintenance signal, not proof of an active cleaning procurement opportunity; verify current project scope, status, contracting path and buyer need before outreach.',
  },
}

const modelBuild = await build({
  entryPoints: [new URL('water_tank_map_model.ts', directory).pathname],
  bundle: true,
  format: 'esm',
  platform: 'node',
  target: 'node24',
  write: false,
})
const modelUrl = `data:text/javascript;base64,${Buffer.from(modelBuild.outputFiles[0].text).toString('base64')}`
const { buildScoutWaterTankPointMapModel, SCOUT_WATER_TANK_POINT_ZOOM } = await import(modelUrl)
const model = buildScoutWaterTankPointMapModel(exemplar)
assert.equal(SCOUT_WATER_TANK_POINT_ZOOM, 17)
assert.deepEqual(model.center, { lon: exemplar.site_point.lon, lat: exemplar.site_point.lat })
assert.equal(model.marker.lon, exemplar.site_point.lon)
assert.equal(model.marker.lat, exemplar.site_point.lat)
assert.equal(model.marker.source, 'kentucky_wris_water_tank')
assert.equal(model.marker.wris_fid, exemplar.site_point.wris_fid)
assert.equal(model.zoom, 17)
assert.equal('bounds' in model, false)
assert.equal('radius' in model, false)

const rendererBuild = await build({
  entryPoints: [new URL('water_tank_map_renderer.ts', directory).pathname],
  bundle: true,
  format: 'esm',
  platform: 'node',
  target: 'node24',
  write: false,
})
const rendererUrl = `data:text/javascript;base64,${Buffer.from(rendererBuild.outputFiles[0].text).toString('base64')}`
const { buildScoutWaterTankRasterFrame } = await import(rendererUrl)

const viewportCases = [
  { width: 280, height: 210, tiles: 4 },
  { width: 320, height: 210, tiles: 4 },
  { width: 366, height: 210, tiles: 4 },
  { width: 406, height: 210, tiles: 6 },
]
for (const expected of viewportCases) {
  const frame = buildScoutWaterTankRasterFrame(exemplar, expected.width, expected.height, {
    tileUrlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  })
  assert.equal(frame.zoom, 17)
  assert.equal(frame.width, expected.width)
  assert.equal(frame.height, expected.height)
  assert.equal(frame.tiles.length, expected.tiles)
  assert.ok(frame.tiles.every((tile) => /^https:\/\/tile\.openstreetmap\.org\/17\/\d+\/\d+\.png$/.test(tile.url)))
  assert.equal(frame.marker.left, frame.width / 2)
  assert.equal(frame.marker.top, frame.height / 2)
}

const clampedFrame = buildScoutWaterTankRasterFrame(exemplar, 320, 210, {
  tileUrlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  maxZoom: 16,
})
assert.equal(clampedFrame.zoom, 16)

const browserBuild = await build({
  entryPoints: [new URL('water_tank_map_renderer.ts', directory).pathname],
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
assert.equal(rendererJs.includes('maplibre'), false)
assert.equal(rendererJs.includes('Worker'), false)
assert.equal(rendererJs.includes('document.createElement'), false)

assert.ok(mapContract.includes('SOUTH PRESSURE ZONE TANK'))
assert.ok(mapContract.includes('render-only zoom `17`'))
assert.ok(mapContract.includes('does not define a service radius'))
assert.ok(mapContract.includes('Water-tank Batch 3 integration scope'))

console.log(`Scout water-tank point raster checks passed across ${viewportCases.length} viewport widths. JS ${rendererJs.length} bytes.`)
