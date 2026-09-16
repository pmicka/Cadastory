import assert from 'node:assert/strict'
import { build } from 'esbuild'
import { readFile } from 'node:fs/promises'

const directory = new URL('./', import.meta.url)
async function bundleModule(path) {
  const result = await build({ entryPoints: [new URL(path, directory).pathname], bundle: true, format: 'esm', platform: 'node', target: 'node22', write: false })
  return await import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`)
}
const manifest = await bundleModule('../_shared/scout_sandbox_manifest.ts')
const schemas = await bundleModule('../_shared/scout_sandbox_contract_schema.ts')
const [component, contractGateway, connectGateway, view, viewRegistrySource, singleSiteRegistry, singleSiteViewRegistry] = await Promise.all([
  readFile(new URL('index.ts', directory), 'utf8'),
  readFile(new URL('../scout-mcp-contract/index.ts', directory), 'utf8'),
  readFile(new URL('../scout-connect/index.ts', directory), 'utf8'),
  readFile(new URL('view.ts', directory), 'utf8'),
  readFile(new URL('portfolio_view_registry.ts', directory), 'utf8'),
  readFile(new URL('single_site_registry.ts', directory), 'utf8'),
  readFile(new URL('single_site_view_registry.ts', directory), 'utf8'),
])

const registered = [...manifest.SCOUT_SANDBOX_OPPORTUNITY_TYPES]
const outputSchema = schemas.sandboxResultSchema()
const outputTypes = outputSchema.oneOf.map((branch) => branch.properties.opportunity_type.enum[0])
assert.deepEqual(outputTypes, registered, 'shared output schema branches must follow the registered opportunity manifest')
assert.deepEqual(schemas.sandboxOpportunityTypeInputSchema().properties.opportunity_type.enum, registered)

for (const source of [component, contractGateway, connectGateway]) {
  assert.ok(source.includes('SCOUT_SANDBOX_OPPORTUNITY_TYPES'))
  assert.ok(source.includes('SCOUT_SANDBOX_RESOURCE_URI'))
}
for (const source of [contractGateway, connectGateway]) {
  assert.ok(source.includes("../_shared/scout_sandbox_contract_schema.ts"))
  assert.ok(source.includes('sandboxResultSchema()'))
  assert.equal(source.includes("enum:['premium_exterior','water_tank','swppp_site','water_utility_portfolio','dealership_group_portfolio','hotel_management_portfolio']"), false)
}
assert.ok(component.includes('SCOUT_SANDBOX_PORTFOLIO_MANIFEST'))
assert.ok(component.includes("fromJsonSchema(sandboxOpportunityTypeInputSchema())"))
assert.ok(component.includes("fromJsonSchema(sandboxResultSchema())"))
assert.equal(component.includes('componentResultSchemaByType'), false)
assert.ok(component.includes('scoutSandboxPortfolioImplementation'))
assert.ok(component.includes('scoutSandboxSingleSiteImplementation'))
assert.ok(view.includes('scoutSandboxSingleSiteViewImplementation'))
for (const type of manifest.SCOUT_SANDBOX_SINGLE_SITE_TYPES) {
  assert.ok(singleSiteRegistry.includes(`${type}:`), `single-site runtime registry missing ${type}`)
  assert.ok(singleSiteViewRegistry.includes(`${type}:`), `single-site view registry missing ${type}`)
}
assert.ok(view.includes('isScoutSandboxOpportunityType'))
assert.ok(view.includes('isScoutSandboxPortfolioType'))
assert.ok(view.includes('scoutSandboxPortfolioViewImplementation'))
assert.ok(viewRegistrySource.includes('groupedViewImplementations'))
const viewRegistryModule = await bundleModule('portfolio_view_registry.ts')
assert.deepEqual(Object.keys(viewRegistryModule.SCOUT_SANDBOX_PORTFOLIO_VIEW_IMPLEMENTATIONS).sort(),[...manifest.SCOUT_SANDBOX_PORTFOLIO_TYPES].sort(),'portfolio view runtime registry must cover the shared manifest')
assert.equal(view.includes("opportunityType !== 'premium_exterior' && opportunityType !== 'water_tank'"), false)

const compatibility = manifest.scoutSandboxCompatibilityResourceUris()
assert.equal(compatibility[0], `ui://scout/component-sandbox/v${manifest.SCOUT_SANDBOX_RESOURCE_VERSION - 1}`)
assert.equal(compatibility.at(-1), 'ui://scout/component-sandbox/v1')
assert.equal(new Set(compatibility).size, compatibility.length)
console.log(`Scout registry parity checks passed for ${registered.length} registered sandbox opportunity types.`)
