import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const read = (path) => readFile(new URL(path, import.meta.url), 'utf8')
const [sandbox, connect, contract, shared, migration] = await Promise.all([
  read('../index.ts'),
  read('../../scout-connect/index.ts'),
  read('../../scout-mcp-contract/index.ts'),
  read('../../_shared/scout_sandbox_portfolio_contract.ts'),
  read('../../../migrations/20260914122500_component_sandbox_warren_water_portfolio_v1.sql'),
])

const tool = 'scout_preview_component_sandbox_portfolio'
const resource = 'ui://scout/component-sandbox/warren-water-portfolio/v1'

assert.match(shared, new RegExp(tool))
assert.match(shared, new RegExp(resource.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')))
assert.match(shared, /additionalProperties:\s*false/)
assert.match(shared, /Warren County Water District/)
assert.match(shared, /KY1140487/)

assert.match(sandbox, /registerPortfolioMcp\(server, admin, SCOUT_VIEW_HTML\)/)
assert.match(sandbox, /const RESOURCE_URI = 'ui:\/\/scout\/component-sandbox\/v26'/)
assert.match(sandbox, /'ui:\/\/scout\/component-sandbox\/v25'/)
assert.match(sandbox, /z < 12 \|\| z > 18/)
assert.doesNotMatch(sandbox, /SANDBOX_MAP_CENTERS[\s\S]*zoom 9/i)

for (const gateway of [connect, contract]) {
  assert.match(gateway, /SANDBOX_PORTFOLIO_TOOL/)
  assert.match(gateway, /SANDBOX_PORTFOLIO_RESOURCE_URI/)
  assert.match(gateway, /sandboxPortfolioTool/)
  assert.match(gateway, /sandboxPortfolioResource/)
  assert.match(gateway, /ui:\/\/scout\/component-sandbox\/v26/)
  assert.match(gateway, /ui:\/\/scout\/component-sandbox\/v25/)
  assert.match(gateway, /\[SANDBOX_TOOL,SANDBOX_PORTFOLIO_TOOL\]/)
  assert.match(gateway, /SANDBOX_RESOURCE_URI,SANDBOX_PORTFOLIO_RESOURCE_URI/)
}
assert.match(connect, /!owner&&\[SANDBOX_TOOL,SANDBOX_PORTFOLIO_TOOL\]\.includes/)

assert.match(migration, /create or replace function public\.scout_get_component_sandbox_water_portfolio_v1_internal\(\)/)
assert.match(migration, /revoke all on function public\.scout_get_component_sandbox_water_portfolio_v1_internal\(\) from public, anon, authenticated/)
assert.match(migration, /grant execute on function public\.scout_get_component_sandbox_water_portfolio_v1_internal\(\) to service_role/)
assert.match(migration, /'ui_component_sandbox_portfolio'/)
assert.match(migration, new RegExp(tool))
assert.match(migration, new RegExp(resource.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')))
assert.match(migration, /evidence_visibility[\s\S]*'collapsed'/)
assert.doesNotMatch(migration, /evidence_visibility\s*=\s*'summary'|\n\s*'summary', 'one_plus_secondary'/)
assert.match(migration, /select agent_contract\.assert_tool_registry_integrity_v1\(\)/)
assert.match(migration, /select agent_contract\.assert_architecture_doctrine_v1\(\)/)

console.log('Portfolio owner-routing and tracked-migration checks passed')
