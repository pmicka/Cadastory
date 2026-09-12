import { readFile, writeFile } from 'node:fs/promises'

const path = 'supabase/functions/scout-component-sandbox-mcp/foundation_test.mjs'
let text = await readFile(path, 'utf8')

function replaceOnce(before, after) {
  const index = text.indexOf(before)
  if (index < 0) throw new Error(`Missing expected foundation text: ${before}`)
  if (text.indexOf(before, index + before.length) >= 0) throw new Error(`Expected unique foundation text: ${before}`)
  text = text.slice(0, index) + after + text.slice(index + before.length)
}

replaceOnce(
  'assert.ok(view.includes("structuredContent?.opportunity"));\nassert.ok(view.includes("structuredContent?.map"));\nassert.ok(view.includes("mountScoutSingleSiteMap"));',
  'assert.ok(view.includes("structured?.opportunity"));\nassert.ok(view.includes("structured?.map"));\nassert.ok(view.includes("mountScoutSingleSiteMap"));\nassert.ok(view.includes("mountScoutWaterTankMap"));\nassert.ok(view.includes("normalizeScoutSandboxWaterTankMap"));',
)

replaceOnce(
  'assert.ok(server.includes("scout_get_component_sandbox_names_v1_internal"));\nassert.ok(server.includes("scout_get_component_sandbox_opportunity_v1_internal"));',
  'assert.equal(server.includes("scout_get_component_sandbox_names_v1_internal"), false);\nassert.ok(server.includes("scout_get_component_sandbox_opportunity_v1_internal"));',
)
replaceOnce(
  'assert.ok(server.includes("scout_get_component_sandbox_premium_exterior_map_v1_internal"));\nassert.ok(server.includes("names: z.array"));\nassert.ok(server.includes("opportunity: z.object"));\nassert.ok(server.includes("map: sandboxMapSchema"));',
  'assert.ok(server.includes("scout_get_component_sandbox_premium_exterior_map_v1_internal"));\nassert.ok(server.includes("scout_get_component_sandbox_water_tank_map_v1_internal"));\nassert.equal(server.includes("names: z.array"), false);\nassert.ok(server.includes("premiumOpportunitySchema"));\nassert.ok(server.includes("waterTankOpportunitySchema"));\nassert.ok(server.includes("z.discriminatedUnion(\\\'opportunity_type\\\'"));',
)
replaceOnce(
  'assert.ok(connectGateway.includes("opportunity:{type:\'object\'"));\nassert.ok(contractGateway.includes("opportunity:{type:\'object\'"));\nassert.ok(connectGateway.includes("map:sandboxMapSchema()"));\nassert.ok(contractGateway.includes("map:sandboxMapSchema()"));',
  'assert.ok(connectGateway.includes("sandboxWaterTankOpportunitySchema"));\nassert.ok(contractGateway.includes("sandboxWaterTankOpportunitySchema"));\nassert.ok(connectGateway.includes("sandboxWaterTankMapSchema"));\nassert.ok(contractGateway.includes("sandboxWaterTankMapSchema"));\nassert.ok(connectGateway.includes("outputSchema:sandboxResultSchema()"));\nassert.ok(contractGateway.includes("outputSchema:sandboxResultSchema()"));',
)

replaceOnce(
`const {
  SCOUT_SANDBOX_MAX_NAMES,
  normalizeScoutSandboxNames,
  normalizeScoutSandboxOpportunity,
  normalizeScoutSandboxSingleSiteMap,
} = await import(contractUrl);
assert.deepEqual(normalizeScoutSandboxNames(["  Denton Floyd  ", "PNC Tower"]), ["Denton Floyd", "PNC Tower"]);
assert.deepEqual(normalizeScoutSandboxNames([null, "", "x".repeat(161), "Valid"]), ["Valid"]);
assert.equal(normalizeScoutSandboxNames(Array.from({ length: 10 }, (_, i) => \`Name \${i}\`)).length, SCOUT_SANDBOX_MAX_NAMES);`,
`const {
  normalizeScoutSandboxOpportunity,
  normalizeScoutSandboxSingleSiteMap,
  normalizeScoutSandboxWaterTankMap,
  buildScoutSandboxWaterTankOpportunity,
} = await import(contractUrl);`,
)

replaceOnce(
  'assert.deepEqual(normalizeScoutSandboxOpportunity(exemplar), exemplar);',
  'assert.deepEqual(normalizeScoutSandboxOpportunity(exemplar), { opportunity_type: "premium_exterior", ...exemplar });',
)

replaceOnce(
  'for (const version of ["v1", "v2", "v3", "v4", "v5", "v6", "v7", "v8", "v9", "v10", "v11", "v12", "v13", "v14", "v15"]) {',
  'for (const version of ["v1", "v2", "v3", "v4", "v5", "v6", "v7", "v8", "v9", "v10", "v11", "v12", "v13", "v14", "v15", "v16"]) {',
)

replaceOnce(
  'assert.ok(generated.includes("Site map for"));\nassert.ok(generated.includes("Scout guardrail:"));',
  'assert.ok(generated.includes("Site map for"));\nassert.ok(generated.includes("Scout guardrail:"));\nassert.ok(generated.includes("water_tank_single_site_map_v1"));\nassert.ok(generated.includes("Rehab signal"));',
)

replaceOnce(
  'assert.ok(mapContract.includes("one opportunity type at a time"));',
  'assert.ok(mapContract.includes("one opportunity type at a time"));\nassert.ok(mapContract.includes("Water-tank Batch 3 integration scope"));\nassert.ok(mapContract.includes("ui://scout/component-sandbox/v16"));',
)

await writeFile(path, text)
