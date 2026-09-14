import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const directory = new URL('./', import.meta.url)
const [server, connectGateway, contractGateway, sharedSchema] = await Promise.all([
  readFile(new URL('index.ts', directory), 'utf8'),
  readFile(new URL('../scout-connect/index.ts', directory), 'utf8'),
  readFile(new URL('../scout-mcp-contract/index.ts', directory), 'utf8'),
  readFile(new URL('../_shared/scout_sandbox_water_portfolio_schema.ts', directory), 'utf8'),
])

assert.ok(sharedSchema.includes('sandboxWaterUtilityPortfolioMapSchema'))
assert.ok(sharedSchema.includes('sandboxWaterUtilityPortfolioOpportunitySchema'))
assert.ok(sharedSchema.includes('water_utility_portfolio_map_v1'))
assert.ok(sharedSchema.includes('documented_asset_portfolio'))
assert.ok(sharedSchema.includes('documented_not_in_service'))
assert.ok(sharedSchema.includes('historical_rehab_record'))

assert.ok(server.includes("const RESOURCE_URI = 'ui://scout/component-sandbox/v27'"))
assert.ok(server.includes("opportunity_type: z.enum(['premium_exterior', 'water_tank', 'swppp_site', 'water_utility_portfolio']).optional()"))
assert.ok(server.includes('waterUtilityPortfolioResultSchema'))
assert.ok(server.includes("selectedType === 'water_utility_portfolio'"))

for (const gateway of [connectGateway, contractGateway]) {
  assert.ok(gateway.includes("sandboxWaterUtilityPortfolioMapSchema, sandboxWaterUtilityPortfolioOpportunitySchema"))
  assert.ok(gateway.includes("const SANDBOX_RESOURCE_URI = 'ui://scout/component-sandbox/v27'"))
  assert.ok(gateway.includes("'ui://scout/component-sandbox/v26'"))
  assert.ok(gateway.includes("enum:['premium_exterior','water_tank','swppp_site','water_utility_portfolio']"))
  assert.ok(gateway.includes("opportunity_type:{type:'string',enum:['water_utility_portfolio']}"))
  assert.ok(gateway.includes('opportunity:sandboxWaterUtilityPortfolioOpportunitySchema()'))
  assert.ok(gateway.includes('map:sandboxWaterUtilityPortfolioMapSchema()'))
  assert.ok(gateway.includes('Warren County water_utility_portfolio exemplar'))
  assert.equal(gateway.includes('Select premium_exterior, water_tank, or swppp_site; omission'), false)
}

console.log('Scout Warren portfolio gateway visibility contract checks passed.')
