import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { readFile } from 'node:fs/promises'
import { build } from 'esbuild'

const directory = new URL('./', import.meta.url)

async function bundleModule(path) {
  const result = await build({
    entryPoints: [new URL(path, directory).pathname],
    bundle: true,
    format: 'esm',
    platform: 'node',
    target: 'node22',
    write: false,
  })
  return await import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`)
}

const manifest = await bundleModule('../_shared/scout_sandbox_manifest.ts')
const schemas = await bundleModule('../_shared/scout_sandbox_contract_schema.ts')
const packageJson = JSON.parse(await readFile(new URL('package.json', directory), 'utf8'))
const [component, contractGateway, connectGateway] = await Promise.all([
  readFile(new URL('index.ts', directory), 'utf8'),
  readFile(new URL('../scout-mcp-contract/index.ts', directory), 'utf8'),
  readFile(new URL('../scout-connect/index.ts', directory), 'utf8'),
])

const registered = [...manifest.SCOUT_SANDBOX_OPPORTUNITY_TYPES]
const advertisedInput = schemas.sandboxOpportunityTypeInputSchema().properties.opportunity_type.enum
const advertisedOutput = schemas.sandboxResultSchema().oneOf.map((branch) => branch.properties.opportunity_type.enum[0])
assert.deepEqual(advertisedInput, registered, 'tools/list input enum must derive from the sandbox manifest')
assert.deepEqual(advertisedOutput, registered, 'tools/list output branches must derive from the sandbox manifest')

for (const source of [component, contractGateway, connectGateway]) {
  assert.ok(source.includes('SCOUT_SANDBOX_RESOURCE_URI'), 'wrapper must use the registered resource URI')
  assert.ok(source.includes('SCOUT_SANDBOX_OPPORTUNITY_TYPES'), 'wrapper must use the registered opportunity list')
}
assert.ok(component.includes('registerAppTool('), 'component must register the MCP Apps tool')
assert.ok(component.includes('registerAppResource('), 'component must register the MCP Apps resource')
assert.ok(component.includes('for (const compatibilityUri of COMPATIBILITY_RESOURCE_URIS)'), 'component must register compatibility resources from policy')
assert.ok(component.includes("_meta: { ui: { resourceUri: RESOURCE_URI } }"), 'tool must advertise the registered UI resource')
assert.ok(component.includes('inputSchema: componentInputSchema'), 'component input schema must use shared contract schema')
assert.ok(component.includes('outputSchema: componentOutputSchema'), 'component output schema must use shared contract schema')
assert.ok(component.includes('fromJsonSchema(sandboxResultSchema())'), 'component output validator must derive from shared JSON schema')
assert.equal(component.includes('async function loadEmbeddedSandboxTiles()'), false, 'resource must not globally aggregate raster tiles')
assert.ok(component.includes(".replace('__SCOUT_EMBEDDED_RASTER_TILES__', '[]')"), 'resource must remain a static raster-independent shell')
assert.ok(component.includes('loadEmbeddedRasterTilesForSelection'), 'tool results must load only selected raster tiles')
for (const gateway of [contractGateway, connectGateway]) {
  assert.ok(gateway.includes('sandboxOpportunityTypeInputSchema()'), 'gateway tools/list input schema must use shared contract schema')
  assert.ok(gateway.includes('sandboxResultSchema()'), 'gateway tools/list output schema must use shared contract schema')
  assert.ok(gateway.includes('scoutSandboxCompatibilityResourceUris()'), 'gateway resource registration must use compatibility policy')
}

const smokeTestByType = {
  premium_exterior: 'single_site_map_renderer_test.mjs',
  water_tank: 'water_tank_map_integration_test.mjs',
  swppp_site: 'swppp_site_map_integration_test.mjs',
  telecom_change: 'telecom_change_map_renderer_test.mjs',
  water_utility_portfolio: 'water_portfolio_map_renderer_test.mjs',
  dealership_group_portfolio: 'dealership_portfolio_map_renderer_test.mjs',
  hotel_management_portfolio: 'hotel_portfolio_map_renderer_test.mjs',
  school_district_portfolio: 'school_district_portfolio_map_renderer_test.mjs',
  municipal_facilities_portfolio: 'municipal_facilities_portfolio_map_renderer_test.mjs',
}
assert.deepEqual(Object.keys(smokeTestByType), registered, 'every registered sandbox type must have one canonical smoke fixture')

for (const type of registered) {
  const testFile = smokeTestByType[type]
  assert.ok(packageJson.scripts.test.includes(testFile), `${type} smoke fixture must remain in the complete sandbox suite`)
  const run = spawnSync(process.execPath, [testFile], {
    cwd: new URL('.', directory),
    encoding: 'utf8',
    stdio: 'pipe',
  })
  assert.equal(run.status, 0, `${type} smoke invocation failed:\n${run.stdout}\n${run.stderr}`)
}

for (const invariantTest of [
  'sandbox_portfolio_contract_test.mjs',
  'sandbox_raster_registry_test.mjs',
  'sandbox_registry_contract_test.mjs',
  'generated_view_parity_test.mjs',
]) {
  const run = spawnSync(process.execPath, [invariantTest], {
    cwd: new URL('.', directory),
    encoding: 'utf8',
    stdio: 'pipe',
  })
  assert.equal(run.status, 0, `${invariantTest} failed:\n${run.stdout}\n${run.stderr}`)
}

console.log(`Scout predeploy smoke passed: tools/list + resource registration + ${registered.length} registered type fixtures + renderer/registry parity.`)
