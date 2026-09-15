import { readFile } from 'node:fs/promises'
import assert from 'node:assert/strict'
import { build, transform } from 'esbuild'

const directory = new URL('./', import.meta.url)
const [modelSource, rendererSource, mountSource] = await Promise.all([
  readFile(new URL('dealership_portfolio_map_model.ts', directory), 'utf8'),
  readFile(new URL('dealership_portfolio_map_renderer.ts', directory), 'utf8'),
  readFile(new URL('dealership_portfolio_map_mount.ts', directory), 'utf8'),
])

for (const source of [modelSource, rendererSource]) {
  assert.equal(source.includes('service_radius'), false)
  assert.equal(source.includes('county_boundary'), false)
  assert.equal(source.includes('property_boundary'), false)
  assert.equal(source.includes('maplibre'), false)
  assert.equal(source.includes('WebGL'), false)
}
assert.ok(modelSource.includes('documented_operating_site_portfolio'))
assert.ok(modelSource.includes('first-party dealership roster plus resolved building crosswalks'))
assert.ok(mountSource.includes('buildScoutDealershipPortfolioRasterFrame'))
assert.ok(mountSource.includes("document.createElement('canvas')"))
assert.ok(mountSource.includes('createImageBitmap'))
assert.ok(mountSource.includes('unresolvedCount'))
assert.ok(mountSource.includes('unresolved · not mapped'))

const resolvedSites = [
  ['Don Franklin Bardstown Buick Chevrolet', '120 W John Rowan Blvd', 'Bardstown', ['Buick','Chevrolet'], [-85.465896369,37.828143466], 1, 0.99],
  ['Don Franklin Campbellsville Chevrolet GMC', '200 N Bypass Rd', 'Campbellsville', ['Chevrolet','GMC'], [-85.361848036,37.345356171], 1, 0.99],
  ['Don Franklin Hardin County Ford', '461 S Dixie Blvd', 'Radcliff', ['Ford'], [-85.934878659,37.835096407], 1, 0.99],
  ['Don Franklin Lexington Buick GMC', '3340 Richmond Rd', 'Lexington', ['Buick','GMC'], [-84.443683735,37.997225146], 1, 0.99],
  ['Don Franklin Lexington Nissan', '3360 Richmond Rd', 'Lexington', ['Nissan'], [-84.442756947,37.996630551], 1, 0.99],
  ['Don Franklin Nicholasville Hyundai', '3035 Lexington Rd', 'Nicholasville', ['Hyundai'], [-84.549950311,37.931937449], 1, 0.99],
  ['Don Franklin Nicholasville Mitsubishi', '3001 Lexington Road', 'Nicholasville', ['Mitsubishi'], [-84.5501594795,37.9303893345], 2, 0.97],
  ['Genesis of Lexington', '3390 Richmond Rd', 'Lexington', ['Genesis'], [-84.441854524,37.996077895], 1, 0.99],
]
const unresolvedSites = [
  ['Don Franklin Campbellsville Chrysler Dodge Jeep Ram', '915 Meader St', 'Campbellsville', ['Chrysler','Dodge','Jeep','Ram']],
  ['Don Franklin Lexington Hyundai', '3440 Richmond Road', 'Lexington', ['Hyundai']],
  ['Don Franklin Lincoln Elizabethtown', '1505 North Dixie Highway', 'Elizabethtown', ['Lincoln']],
]
const members = [
  ...resolvedSites.map(([name,address,city,brands,coordinates,count,confidence], index) => ({
    id: `00000000-0000-4000-8000-${String(index + 1).padStart(12,'0')}`,
    name,address,city,state_code:'KY',brands,
    point:{type:'Point',coordinates},
    resolution_state: count === 1 ? 'single_building_resolved' : 'multi_building_resolved',
    resolved_building_count: count,
    link_confidence: confidence,
    within_pilot_radius:true,
    observed_at:'2026-09-07T20:36:51.981315+00:00',
  })),
  ...unresolvedSites.map(([name,address,city,brands], index) => ({
    id: `00000000-0000-4000-8000-${String(index + 20).padStart(12,'0')}`,
    name,address,city,state_code:'KY',brands,
    point:{type:'unresolved'},
    resolution_state:'unresolved',
    resolved_building_count:0,
    link_confidence:null,
    within_pilot_radius:true,
    observed_at:'2026-09-07T20:36:51.981315+00:00',
  })),
]

const rawPayload = {
  contract_version:'dealership_group_portfolio_map_v1',
  account_name:'Don Franklin Auto',
  organization_id:'046baf25-53b3-4524-91d0-b115bb62161e',
  scope:'documented_operating_roster',
  source_slug:'don-franklin-auto-locations',
  relationship:'operates',
  target_kind:'site_member',
  map_semantics:'documented_operating_site_portfolio',
  evidence_boundary:'first-party dealership roster plus resolved building crosswalks',
  generated_at:'2026-09-14T21:00:00+00:00',
  observed_at:'2026-09-07T20:36:51.981315+00:00',
  contact_route_available:true,
  operations_route_available:false,
  procurement_route_available:false,
  vendor_route_proven:false,
  current_need_scan_complete:true,
  members,
}

const modelBuild = await build({entryPoints:[new URL('dealership_portfolio_map_model.ts',directory).pathname],bundle:true,format:'esm',platform:'node',target:'node24',write:false})
const modelUrl=`data:text/javascript;base64,${Buffer.from(modelBuild.outputFiles[0].text).toString('base64')}`
const {normalizeScoutSandboxDealershipPortfolioMap,buildScoutSandboxDealershipPortfolioOpportunity}=await import(modelUrl)
const normalized=normalizeScoutSandboxDealershipPortfolioMap(rawPayload)
assert.ok(normalized)
assert.equal(normalized.opportunity_type,'dealership_group_portfolio')
assert.equal(normalized.member_count,11)
assert.equal(normalized.resolved_member_count,8)
assert.equal(normalized.resolved_building_count,9)
assert.equal(normalized.members.filter((member)=>member.resolution_state==='multi_building_resolved').length,1)
assert.equal(normalized.members.filter((member)=>member.resolution_state==='unresolved').length,3)
assert.equal(normalized.contact_route_available,true)
assert.equal(normalized.operations_route_available,false)
assert.equal(normalized.procurement_route_available,false)
assert.equal(normalized.vendor_route_proven,false)
assert.equal(normalized.current_need_scan_complete,true)

const hostProjectedPayload = structuredClone(rawPayload)
for (const member of hostProjectedPayload.members) {
  if (member.resolution_state === 'unresolved') delete member.link_confidence
}
const hostProjected = normalizeScoutSandboxDealershipPortfolioMap(hostProjectedPayload)
assert.ok(hostProjected)
assert.equal(hostProjected.members.filter((member)=>member.resolution_state==='unresolved').every((member)=>member.link_confidence===null), true)
const invalidResolvedProjection = structuredClone(rawPayload)
delete invalidResolvedProjection.members[0].link_confidence
assert.equal(normalizeScoutSandboxDealershipPortfolioMap(invalidResolvedProjection), null)

const opportunity=buildScoutSandboxDealershipPortfolioOpportunity(normalized)
assert.equal(opportunity.name,'Don Franklin Auto')
assert.equal(opportunity.member_count,11)
assert.equal(opportunity.resolved_member_count,8)
assert.equal(opportunity.resolved_building_count,9)
assert.equal(opportunity.unresolved_member_count,3)
assert.match(opportunity.guardrail,/not proof of current exterior-cleaning need/i)
assert.match(opportunity.why_investigate,/centralized/i)

const rendererBuild=await build({entryPoints:[new URL('dealership_portfolio_map_renderer.ts',directory).pathname],bundle:true,format:'esm',platform:'node',target:'node24',write:false})
const rendererUrl=`data:text/javascript;base64,${Buffer.from(rendererBuild.outputFiles[0].text).toString('base64')}`
const {buildScoutDealershipPortfolioRasterFrame}=await import(rendererUrl)
const frame=buildScoutDealershipPortfolioRasterFrame(normalized,456,210,{tileUrlTemplate:'https://tile.openstreetmap.org/{z}/{x}/{y}.png',minZoom:5,maxZoom:18})
assert.equal(frame.zoom,8)
assert.equal(frame.tiles.length,6)
assert.equal(frame.markers.length,8)
assert.equal(frame.markers.filter((marker)=>marker.resolutionState==='multi_building_resolved').length,1)
const narrowFrame=buildScoutDealershipPortfolioRasterFrame(normalized,280,210,{tileUrlTemplate:'https://tile.openstreetmap.org/{z}/{x}/{y}.png',minZoom:5,maxZoom:18})
assert.equal(narrowFrame.zoom,7)
assert.deepEqual(narrowFrame.tiles.map((tile)=>`${tile.z}/${tile.x}/${tile.y}`).sort(),['7/33/49','7/34/49'])
assert.equal(narrowFrame.markers.length,8)
assert.ok(frame.markers.every((marker)=>marker.left>=0&&marker.left<=frame.width&&marker.top>=0&&marker.top<=frame.height))
assert.ok(mountSource.includes('Single-building site'))
assert.ok(mountSource.includes('Multi-building site'))
assert.equal(mountSource.includes('unresolved') && mountSource.includes('not mapped'),true)

const browserBuild=await build({entryPoints:[new URL('dealership_portfolio_map_renderer.ts',directory).pathname],bundle:true,format:'esm',platform:'browser',target:'es2022',write:false,minify:true,legalComments:'none'})
const rendererJs=browserBuild.outputFiles[0]?.text
assert.ok(rendererJs)
await transform(rendererJs,{loader:'js',format:'esm',target:'es2022'})
assert.equal(rendererJs.includes('maplibre'),false)
assert.equal(rendererJs.includes('Worker'),false)
assert.equal(rendererJs.includes('document.createElement'),false)

console.log(`Scout dealership portfolio checks passed: ${frame.markers.length} mapped sites, ${opportunity.unresolved_member_count} unresolved, zoom ${frame.zoom}, ${frame.tiles.length} raster tiles.`)
