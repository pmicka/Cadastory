import assert from 'node:assert/strict'
import { build } from 'esbuild'
import { readFile } from 'node:fs/promises'

const directory = new URL('./', import.meta.url)
const [contractSource, serverSource, viewSource, mapContract] = await Promise.all([
  readFile(new URL('contract.ts', directory), 'utf8'),
  readFile(new URL('index.ts', directory), 'utf8'),
  readFile(new URL('view.ts', directory), 'utf8'),
  readFile(new URL('MAP_CONTRACT.md', directory), 'utf8'),
])

const bundled = await build({
  entryPoints: [new URL('contract.ts', directory).pathname],
  bundle: true,
  format: 'esm',
  platform: 'node',
  target: 'node24',
  write: false,
})
const moduleUrl = `data:text/javascript;base64,${Buffer.from(bundled.outputFiles[0].text).toString('base64')}`
const { normalizeScoutSandboxWaterTankMap } = await import(moduleUrl)

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

const normalized = normalizeScoutSandboxWaterTankMap(exemplar)
assert.deepEqual(normalized, exemplar)

for (const mutate of [
  (x) => { x.contract_version = 'single_site_map_v1' },
  (x) => { x.site_point.source = 'premium_exterior_target_geocode' },
  (x) => { x.site_point.lon = 999 },
  (x) => { x.asset.tank_type = 'STANDPIPE' },
  (x) => { x.asset.out_of_service = true },
  (x) => { x.geometry.support_geometry = 'multi_column' },
  (x) => { x.geometry.cross_bracing_status = 'present' },
  (x) => { x.geometry.operator_assessment = 'challenging' },
  (x) => { x.geometry.evidence_kind = 'visual_review' },
  (x) => { x.geometry.media_retained = true },
  (x) => { x.project_linkage.status = 'COMPLETE' },
  (x) => { x.candidate_key = 'water_tank:wrong' },
]) {
  const invalid = structuredClone(exemplar)
  mutate(invalid)
  assert.equal(normalizeScoutSandboxWaterTankMap(invalid), null)
}

// Batch 1 is data-contract only. The live sandbox result/View must not expose or render it yet.
assert.ok(contractSource.includes('normalizeScoutSandboxWaterTankMap'))
assert.equal(serverSource.includes('scout_get_component_sandbox_water_tank_map_v1_internal'), false)
assert.equal(viewSource.includes('normalizeScoutSandboxWaterTankMap'), false)
assert.equal(viewSource.includes('water_tank_single_site_map_v1'), false)

for (const deprecated of [
  'window.openai',
  'openai/outputTemplate',
  'openai/widgetAccessible',
  'openai/widgetDescription',
  'openai/widgetCSP',
]) {
  assert.equal(contractSource.includes(deprecated), false)
}

assert.ok(mapContract.includes('SOUTH PRESSURE ZONE TANK'))
assert.ok(mapContract.includes('water_tank_single_site_map_v1'))
assert.ok(mapContract.includes('data-contract-only'))

console.log('Scout water-tank single-site map contract checks passed.')
