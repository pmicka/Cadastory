import assert from 'node:assert/strict'
import { build } from 'esbuild'
import { readFile } from 'node:fs/promises'

const directory = new URL('./', import.meta.url)
const [migration, locationCorrection, mapContract, serverSource, viewSource] = await Promise.all([
  readFile(new URL('../../migrations/20260912145117_add_component_sandbox_swppp_site_map_v1.sql', directory), 'utf8'),
  readFile(new URL('../../migrations/20260912145346_correct_component_sandbox_swppp_site_location_label.sql', directory), 'utf8'),
  readFile(new URL('MAP_CONTRACT.md', directory), 'utf8'),
  readFile(new URL('index.ts', directory), 'utf8'),
  readFile(new URL('view.ts', directory), 'utf8'),
])

assert.ok(migration.includes('scout_get_component_sandbox_swppp_site_map_v1_internal'))
assert.ok(migration.includes("'contract_version', 'swppp_site_map_v1'"))
assert.ok(migration.includes("'opportunity_type', 'swppp_site'"))
assert.ok(migration.includes("e.source_native_id = 'ohio-epa:1GC10896*AG'"))
assert.ok(migration.includes("e.registry_id = 'OHGC18548'"))
assert.ok(migration.includes("e.permit_status_desc = 'ACTIVE'"))
assert.ok(migration.includes("e.storm_water_area_acres = 135"))
assert.ok(migration.includes("extensions.st_geometrytype(e.location::extensions.geometry) = 'ST_Point'"))
assert.ok(migration.includes("'semantics', 'authoritative_permit_location_point'"))
assert.ok(migration.includes("'classification', 'unresolved'"))
assert.ok(migration.includes('not proof of an active procurement opportunity'))
assert.ok(migration.includes('not a project boundary'))
assert.ok(migration.includes('revoke all on function public.scout_get_component_sandbox_swppp_site_map_v1_internal() from public'))
assert.ok(migration.includes('grant execute on function public.scout_get_component_sandbox_swppp_site_map_v1_internal() to service_role'))
assert.ok(locationCorrection.includes("pg_catalog.concat(t.attributes ->> 'county', ' County, Ohio')"))
assert.ok(locationCorrection.includes('scout_get_component_sandbox_swppp_site_map_v1_internal'))

assert.ok(mapContract.includes('SWPPP-site bounded data contract'))
assert.ok(mapContract.includes('HAM-Brent Spence Project (PID 116649)'))
assert.ok(mapContract.includes('isolated database groundwork only'))
assert.ok(mapContract.includes('must not fabricate a project polygon'))

// Batch C must not change the live sandbox tool or View.
assert.equal(serverSource.includes('scout_get_component_sandbox_swppp_site_map_v1_internal'), false)
assert.equal(viewSource.includes("opportunityType === 'swppp_site'"), false)

console.log('Scout SWPPP-site isolated database contract checks passed.')

const bundled = await build({
  entryPoints: [new URL('swppp_site_map_model.ts', directory).pathname],
  bundle: true,
  format: 'esm',
  platform: 'node',
  target: 'node24',
  write: false,
})
const moduleUrl = `data:text/javascript;base64,${Buffer.from(bundled.outputFiles[0].text).toString('base64')}`
const { normalizeScoutSandboxSwpppSiteMap, buildScoutSandboxSwpppSiteOpportunity } = await import(moduleUrl)

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
    guardrail: 'The Ohio EPA record supplies a location point only. It is not a project boundary, disturbance polygon, parcel boundary, ownership boundary, or site-access area.',
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
    acreage_semantics: 'Ohio EPA total_acres is stored as documented state permit acreage; do not substitute building square footage or infer disturbed acreage.',
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
    guardrail: 'Scout has not resolved a project owner, developer, contracting agency, buyer, or contact route for this permit record.',
  },
  why_investigate: 'Ohio EPA documents an active construction-stormwater permit with 135 total permit acres and a project identifier; verify present project activity, SWPPP documentation needs, contracting path, and responsible organization.',
  guardrail: 'Construction-stormwater permit evidence identifies a potentially relevant active site or compliance/documentation need, but it is not proof of an active procurement opportunity, buyer intent, current service need, site access, ownership, or contract availability.',
}

assert.deepEqual(normalizeScoutSandboxSwpppSiteMap(exemplar), exemplar)

for (const mutate of [
  (x) => { x.contract_version = 'water_tank_single_site_map_v1' },
  (x) => { x.opportunity_type = 'water_tank' },
  (x) => { x.candidate_key = 'swppp_site:wrong' },
  (x) => { x.site_point.lon = 999 },
  (x) => { x.site_point.geometry_type = 'Polygon' },
  (x) => { x.site_point.semantics = 'project_boundary' },
  (x) => { x.permit.evidence_status = 'nearby_current_stormwater_permit_candidate' },
  (x) => { x.permit.status = 'TERMINATED' },
  (x) => { x.permit.termination_date = '2026-09-10' },
  (x) => { x.permit.documented_total_acres = 0 },
  (x) => { x.source.slug = 'epa-echo-cwa-facilities' },
  (x) => { x.source.authority_level = 'federal' },
  (x) => { x.buyer.classification = 'resolved' },
  (x) => { x.buyer.organization_id = 'invented' },
]) {
  const invalid = structuredClone(exemplar)
  mutate(invalid)
  assert.equal(normalizeScoutSandboxSwpppSiteMap(invalid), null)
}

assert.deepEqual(buildScoutSandboxSwpppSiteOpportunity(exemplar), {
  opportunity_type: 'swppp_site',
  name: 'HAM-Brent Spence Project (PID 116649)',
  location_label: 'Hamilton County, Ohio',
  evidence_status: 'active_documented_state_construction_permit',
  observed_at: '2026-09-10T11:50:17.289218+00:00',
  permit_number: '1GC10896*AG',
  permit_status: 'ACTIVE',
  permit_type: 'CONSTRUCTION_STORMWATER',
  permit_effective_date: '2026-03-12',
  permit_expiration_date: '2028-04-22',
  documented_total_acres: 135,
  project_reference: 'PID 116649',
  buyer_resolvability: 'unresolved',
  why_investigate: exemplar.why_investigate,
  guardrail: exemplar.guardrail,
})

assert.equal('confidence' in buildScoutSandboxSwpppSiteOpportunity(exemplar), false)
assert.equal('project_type' in buildScoutSandboxSwpppSiteOpportunity(exemplar), false)
assert.equal('time_sensitive' in buildScoutSandboxSwpppSiteOpportunity(exemplar), false)

console.log('Scout SWPPP-site isolated model and normalizer checks passed.')
