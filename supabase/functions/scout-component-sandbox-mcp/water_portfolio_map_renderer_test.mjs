import { readFile } from 'node:fs/promises'
import assert from 'node:assert/strict'
import { build, transform } from 'esbuild'

const directory = new URL('./', import.meta.url)
const [modelSource, rendererSource, mountSource] = await Promise.all([
  readFile(new URL('water_portfolio_map_model.ts', directory), 'utf8'),
  readFile(new URL('water_portfolio_map_renderer.ts', directory), 'utf8'),
  readFile(new URL('water_portfolio_map_mount.ts', directory), 'utf8'),
])

for (const source of [modelSource, rendererSource]) {
  assert.equal(source.includes('service_radius'), false)
  assert.equal(source.includes('county_boundary'), false)
  assert.equal(source.includes('property_boundary'), false)
  assert.equal(source.includes('maplibre'), false)
  assert.equal(source.includes('WebGL'), false)
}
assert.ok(modelSource.includes('documented_asset_portfolio'))
assert.ok(modelSource.includes('linked water-system tank records only'))
assert.ok(mountSource.includes('buildScoutWaterUtilityPortfolioRasterFrame'))
assert.ok(mountSource.includes("document.createElement('canvas')"))
assert.ok(mountSource.includes('createImageBitmap'))

const west = -86.604253186103
const east = -86.1720916450137
const south = 36.9089936423351
const north = 37.1328579829601
const names = Array.from({ length: 24 }, (_, index) => `WARREN TANK ${String(index + 1).padStart(2, '0')}`)
names[3] = 'BRIGGS HILL TANK (NOT IN SERVICE)'
names[11] = 'MIZPAH'
names[16] = 'OAKLAND TANK (NOT IN SERVICE)'
names[20] = 'PLEASANT HILL TANK'

const members = names.map((name, index) => {
  const fraction = index / (names.length - 1)
  const sourceModifiedAt = index === 23 ? '2023-06-12T10:17:05+00:00' : '2023-06-11T10:17:05+00:00'
  const historical = name === 'MIZPAH' || name === 'PLEASANT HILL TANK'
  return {
    id: `WRIS-${String(index + 1).padStart(2, '0')}`,
    name,
    pwsid: 'KY1140487',
    morphology: index < 12 ? 'elevated' : index < 18 ? 'ground_storage' : index < 23 ? 'standpipe' : 'fluted_column',
    point: {
      type: 'Point',
      coordinates: [west + (east - west) * fraction, south + (north - south) * (1 - fraction)],
    },
    service_state: name.includes('NOT IN SERVICE') ? 'documented_not_in_service' : 'unverified',
    within_pilot_radius: true,
    source_modified_at: sourceModifiedAt,
    signals: historical ? [{ id: `water_tank:${index}`, kind: 'historical_rehab_record', observed_at: '2021-12-10T09:40:38+00:00' }] : [],
  }
})

const rawPayload = {
  contract_version: 'water_utility_portfolio_map_v1',
  account_name: 'Warren County Water District',
  organization_id: '046baf25-53b3-4524-91d0-b115bb62161e',
  pwsid: 'KY1140487',
  scope: 'documented_roster',
  source_slug: 'ky-kia-water-tanks',
  relationship: 'system_membership',
  generated_at: '2026-09-14T14:30:00+00:00',
  source_modified_at: '2023-06-12T10:17:05+00:00',
  members,
}

const modelBuild = await build({
  entryPoints: [new URL('water_portfolio_map_model.ts', directory).pathname],
  bundle: true,
  format: 'esm',
  platform: 'node',
  target: 'node24',
  write: false,
})
const modelUrl = `data:text/javascript;base64,${Buffer.from(modelBuild.outputFiles[0].text).toString('base64')}`
const {
  normalizeScoutSandboxWaterUtilityPortfolioMap,
  buildScoutSandboxWaterUtilityPortfolioOpportunity,
} = await import(modelUrl)

const normalized = normalizeScoutSandboxWaterUtilityPortfolioMap(rawPayload)
assert.ok(normalized)
assert.equal(normalized.opportunity_type, 'water_utility_portfolio')
assert.equal(normalized.group_kind, 'portfolio')
assert.equal(normalized.member_count, 24)
assert.equal(normalized.resolved_member_count, 24)
assert.equal(normalized.source_modified_at, '2023-06-12T10:17:05.000Z')
assert.deepEqual(normalized.bounds, { west, south, east, north })
assert.equal(normalized.map_semantics, 'documented_asset_portfolio')
assert.equal(normalized.evidence_boundary, 'linked water-system tank records only')
assert.equal(normalized.members.filter((member) => member.morphology === 'elevated').length, 12)
assert.equal(normalized.members.filter((member) => member.morphology === 'ground_storage').length, 6)
assert.equal(normalized.members.filter((member) => member.morphology === 'standpipe').length, 5)
assert.equal(normalized.members.filter((member) => member.morphology === 'fluted_column').length, 1)

const opportunity = buildScoutSandboxWaterUtilityPortfolioOpportunity(normalized)
assert.equal(opportunity.name, 'Warren County Water District')
assert.equal(opportunity.pwsid, 'KY1140487')
assert.equal(opportunity.member_count, 24)
assert.equal(opportunity.not_in_service_count, 2)
assert.equal(opportunity.historical_project_signal_count, 2)
assert.match(opportunity.guardrail, /not proof of current service need/i)
assert.match(opportunity.why_investigate, /current tank service state/i)

const rendererBuild = await build({
  entryPoints: [new URL('water_portfolio_map_renderer.ts', directory).pathname],
  bundle: true,
  format: 'esm',
  platform: 'node',
  target: 'node24',
  write: false,
})
const rendererUrl = `data:text/javascript;base64,${Buffer.from(rendererBuild.outputFiles[0].text).toString('base64')}`
const { buildScoutWaterUtilityPortfolioRasterFrame } = await import(rendererUrl)
const frame = buildScoutWaterUtilityPortfolioRasterFrame(normalized, 456, 210, {
  tileUrlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  minZoom: 5,
  maxZoom: 18,
})
assert.equal(frame.zoom, 9)
assert.equal(frame.tiles.length, 6)
assert.equal(frame.markers.length, 24)
assert.equal(frame.markers.filter((marker) => marker.serviceState === 'documented_not_in_service').length, 2)
assert.equal(frame.markers.filter((marker) => marker.historicalRehab).length, 2)
assert.equal(frame.markers.filter((marker) => marker.morphology === 'elevated').length, 12)
assert.equal(frame.markers.filter((marker) => marker.morphology === 'ground_storage').length, 6)
assert.equal(frame.markers.filter((marker) => marker.morphology === 'standpipe').length, 5)
assert.equal(frame.markers.filter((marker) => marker.morphology === 'fluted_column').length, 1)
assert.ok(mountSource.includes('MORPHOLOGY_STYLES'))
assert.ok(mountSource.includes('scout-portfolio-marker'))
assert.ok(mountSource.includes('scout-portfolio-legend'))
assert.ok(frame.markers.every((marker) => marker.left >= 0 && marker.left <= frame.width && marker.top >= 0 && marker.top <= frame.height))

const browserBuild = await build({
  entryPoints: [new URL('water_portfolio_map_renderer.ts', directory).pathname],
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

console.log(`Scout Warren County portfolio checks passed: ${frame.markers.length} markers, zoom ${frame.zoom}, ${frame.tiles.length} raster tiles.`)
