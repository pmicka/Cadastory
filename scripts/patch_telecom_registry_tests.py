from pathlib import Path

root=Path('supabase/functions/scout-component-sandbox-mcp')
path=root/'foundation_test.mjs'
text=path.read_text()
old='''const [view, server, generated, buildView, connectGateway, contractGateway, template, designContract, mapContract] = await Promise.all([
  readFile(new URL("view.ts", directory), "utf8"),'''
new='''const [view, server, generated, buildView, connectGateway, contractGateway, template, designContract, mapContract, singleSiteRegistry] = await Promise.all([
  readFile(new URL("view.ts", directory), "utf8"),'''
if old not in text: raise RuntimeError('foundation Promise header not found')
text=text.replace(old,new,1)
old='''  readFile(new URL("MAP_CONTRACT.md", directory), "utf8"),
]);'''
new='''  readFile(new URL("MAP_CONTRACT.md", directory), "utf8"),
  readFile(new URL("single_site_registry.ts", directory), "utf8"),
]);'''
if old not in text: raise RuntimeError('foundation Promise tail not found')
text=text.replace(old,new,1)
old='''assert.ok(view.includes("mountScoutSingleSiteMap"));
assert.ok(view.includes("mountScoutWaterTankMap"));
assert.ok(view.includes("normalizeScoutSandboxWaterTankMap"));'''
new='''assert.ok(view.includes("scoutSandboxSingleSiteViewImplementation"));
assert.ok(server.includes("scoutSandboxSingleSiteImplementation"));
assert.ok(server.includes("assertScoutSandboxSingleSiteImplementationCoverage"));'''
if old not in text: raise RuntimeError('foundation direct single-site assertions not found')
text=text.replace(old,new,1)
for old_line in [
    'assert.ok(server.includes("scout_get_component_sandbox_opportunity_v1_internal"));',
    'assert.ok(server.includes("scout_get_component_sandbox_premium_exterior_map_v1_internal"));',
    'assert.ok(server.includes("scout_get_component_sandbox_water_tank_map_v1_internal"));',
]:
    if old_line not in text: raise RuntimeError(f'foundation direct RPC assertion not found: {old_line}')
    text=text.replace(old_line,'',1)
anchor='''assert.equal(server.includes("scout_get_component_sandbox_map_targets_v3_internal"), false);'''
addition='''assert.equal(server.includes("scout_get_component_sandbox_map_targets_v3_internal"), false);
assert.ok(singleSiteRegistry.includes("scout_get_component_sandbox_opportunity_v1_internal"));
assert.ok(singleSiteRegistry.includes("scout_get_component_sandbox_premium_exterior_map_v1_internal"));
assert.ok(singleSiteRegistry.includes("scout_get_component_sandbox_water_tank_map_v1_internal"));
assert.ok(singleSiteRegistry.includes("scout_get_component_sandbox_swppp_site_map_v1_internal"));
assert.ok(singleSiteRegistry.includes("scout_get_component_sandbox_telecom_change_v1_internal"));'''
if anchor not in text: raise RuntimeError('foundation RPC registry anchor not found')
text=text.replace(anchor,addition,1)
path.write_text(text)
print('Updated foundation invariants for single-site registry and RPC ownership.')
