import { readFile } from 'node:fs/promises'
import assert from 'node:assert/strict'

const directory = new URL('./', import.meta.url)
const [
  contract,
  server,
  view,
  generated,
  connectGateway,
  contractGateway,
  mount,
  mapContract,
  designContract,
] = await Promise.all([
  readFile(new URL('contract.ts', directory), 'utf8'),
  readFile(new URL('index.ts', directory), 'utf8'),
  readFile(new URL('view.ts', directory), 'utf8'),
  readFile(new URL('view.generated.ts', directory), 'utf8'),
  readFile(new URL('../scout-connect/index.ts', directory), 'utf8'),
  readFile(new URL('../scout-mcp-contract/index.ts', directory), 'utf8'),
  readFile(new URL('water_tank_map_mount.ts', directory), 'utf8'),
  readFile(new URL('MAP_CONTRACT.md', directory), 'utf8'),
  readFile(new URL('DESIGN_CONTRACT.md', directory), 'utf8'),
])

for (const source of [server, connectGateway, contractGateway]) {
  assert.ok(source.includes('ui://scout/component-sandbox/v19'))
  assert.ok(source.includes('ui://scout/component-sandbox/v18'))
  assert.ok(source.includes('ui://scout/component-sandbox/v17'))
  assert.ok(source.includes('ui://scout/component-sandbox/v16'))
  assert.ok(source.includes('ui://scout/component-sandbox/v15'))
  assert.ok(source.includes("opportunity_type"))
  assert.ok(source.includes("premium_exterior"))
  assert.ok(source.includes("water_tank"))
  assert.equal(source.includes('scout_get_component_sandbox_names_v1_internal'), false)
}

assert.ok(server.includes('scout_get_component_sandbox_water_tank_map_v1_internal'))
assert.ok(server.includes("opportunity_type: z.enum(['premium_exterior', 'water_tank', 'swppp_site']).optional()"))
assert.ok(server.includes("z.discriminatedUnion('opportunity_type'"))
assert.ok(server.includes("const selectedType = opportunity_type ?? 'premium_exterior'"))
assert.ok(server.includes('buildScoutSandboxWaterTankOpportunity'))
assert.equal(server.includes('names: z.array'), false)

assert.ok(contract.includes("export type ScoutSandboxResult = ScoutSandboxPremiumExteriorResult | ScoutSandboxWaterTankResult | ScoutSandboxSwpppSiteResult"))
assert.ok(contract.includes('buildScoutSandboxWaterTankOpportunity'))
assert.equal(contract.includes('normalizeScoutSandboxNames'), false)
assert.equal(contract.includes('SCOUT_SANDBOX_MAX_NAMES'), false)

assert.ok(view.includes('mountScoutSingleSiteMap'))
assert.ok(view.includes('mountScoutWaterTankMap'))
assert.ok(view.includes('normalizeScoutSandboxWaterTankMap'))
assert.ok(view.includes("version: '2.5.2'"))
assert.ok(view.includes("opportunityType === 'water_tank'"))
assert.ok(view.includes('Rehab signal'))
assert.ok(view.includes('morphology confidence'))
assert.ok(view.includes('Project source updated'))
assert.ok(view.includes('system_name'))
assert.ok(view.includes('capacity_gallons'))

assert.ok(mount.includes("document.createElement('img')"))
assert.ok(mount.includes("image.referrerPolicy = 'origin'"))
assert.ok(mount.includes('buildScoutWaterTankRasterFrame'))
assert.ok(mount.includes('replaceChildren()'))
assert.ok(mount.includes('lastFrameWidth'))
assert.ok(mount.includes('lastFrameHeight'))
assert.ok(mount.includes('render(true)'))
assert.ok(mount.includes('render(false)'))
for (const forbidden of ['maplibre', 'MapLibre', 'WebGL', 'new Worker', '<svg']) {
  assert.equal(mount.includes(forbidden), false)
}

for (const source of [view, server, mount]) {
  for (const forbidden of ['window.openai', 'openai/outputTemplate', 'openai/widgetAccessible', 'openai/widgetDescription', 'openai/widgetCSP']) {
    assert.equal(source.includes(forbidden), false)
  }
}

assert.ok(generated.includes('water_tank_single_site_map_v1'))
assert.ok(generated.includes('mountScoutWaterTankMap') || generated.includes('Rehab signal'))
assert.ok(generated.includes('scout-component-sandbox-mcp/map-tile'))
assert.equal(generated.includes('maplibre'), false)
assert.equal(generated.includes('tiles.openfreemap.org'), false)

assert.ok(mapContract.includes('Water-tank Batch 3 integration scope'))
assert.ok(mapContract.includes('ui://scout/component-sandbox/v16'))
assert.ok(mapContract.includes('obsolete `names` field'))
assert.ok(designContract.includes('SOUTH PRESSURE ZONE TANK'))
assert.ok(designContract.includes('The card and map must always describe the same opportunity'))

console.log('Scout water-tank Batch 3 integration checks passed.')
