import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const directory = new URL('./', import.meta.url)
const [server, connectGateway, contractGateway, sharedSchema] = await Promise.all([
  readFile(new URL('index.ts', directory), 'utf8'),
  readFile(new URL('../scout-connect/index.ts', directory), 'utf8'),
  readFile(new URL('../scout-mcp-contract/index.ts', directory), 'utf8'),
  readFile(new URL('../_shared/scout_sandbox_dealership_portfolio_schema.ts', directory), 'utf8'),
])

assert.ok(sharedSchema.includes('sandboxDealershipPortfolioMapSchema'))
assert.ok(sharedSchema.includes('sandboxDealershipPortfolioOpportunitySchema'))
assert.ok(sharedSchema.includes('dealership_group_portfolio_map_v1'))
assert.ok(sharedSchema.includes('documented_operating_site_portfolio'))
assert.ok(sharedSchema.includes('single_building_resolved'))
assert.ok(sharedSchema.includes('multi_building_resolved'))
assert.ok(sharedSchema.includes('unresolved'))

assert.ok(server.includes("const RESOURCE_URI = 'ui://scout/component-sandbox/v32'"))
assert.ok(server.includes("const DEALERSHIP_PORTFOLIO_NARROW_TILE_BOUNDS = { z: 7, minX: 33, maxX: 34, minY: 49, maxY: 49 } as const"))
assert.ok(server.includes('buildScoutDealershipPortfolioRasterFrame(dealershipMap, 280, 210'))
assert.ok(server.includes('DEALERSHIP_PORTFOLIO_NARROW_TILE_BOUNDS.z'))
assert.ok(server.includes("'dealership_group_portfolio'"))
assert.ok(server.includes('dealershipPortfolioResultSchema'))
assert.ok(server.includes("selectedType === 'dealership_group_portfolio'"))
assert.ok(server.includes('DEALERSHIP_PORTFOLIO_TILE_BOUNDS'))

for (const gateway of [connectGateway, contractGateway]) {
  assert.ok(gateway.includes('sandboxDealershipPortfolioMapSchema, sandboxDealershipPortfolioOpportunitySchema'))
  assert.ok(gateway.includes("const SANDBOX_RESOURCE_URI = 'ui://scout/component-sandbox/v32'"))
  assert.ok(gateway.includes("'ui://scout/component-sandbox/v29'"))
  assert.ok(gateway.includes("'dealership_group_portfolio'"))
  assert.ok(gateway.includes("opportunity_type:{type:'string',enum:['dealership_group_portfolio']}"))
  assert.ok(gateway.includes('opportunity:sandboxDealershipPortfolioOpportunitySchema()'))
  assert.ok(gateway.includes('map:sandboxDealershipPortfolioMapSchema()'))
  assert.ok(gateway.includes('Don Franklin Auto dealership_group_portfolio exemplar'))
}

console.log('Scout dealership portfolio gateway visibility contract checks passed.')
