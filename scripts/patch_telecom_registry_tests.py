from pathlib import Path

root=Path('supabase/functions/scout-component-sandbox-mcp')

# Foundation owns broad lifecycle/registry invariants.
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
path.write_text(text.replace(anchor,addition,1))

# Legacy renderer/integration tests should validate registry routing, not direct imports in view/server.
replacements={
 'single_site_map_renderer_test.mjs':[
  ("assert.ok(view.includes('mountScoutSingleSiteMap'))","assert.ok(view.includes('scoutSandboxSingleSiteViewImplementation'))"),
  ("assert.ok(view.includes('mountScoutSingleSiteMap(mapContainer, mapData, { ...mapOptions, embeddedTiles })'))","assert.ok(view.includes('implementation.mount(mapContainer, mapData, mountOptions)'))"),
 ],
 'water_tank_map_renderer_test.mjs':[
  ("assert.ok(view.includes('mountScoutWaterTankMap'))","assert.ok(view.includes('scoutSandboxSingleSiteViewImplementation'))"),
  ("assert.ok(view.includes('mountScoutWaterTankMap(mapContainer, mapData, { ...mapOptions, embeddedTiles })'))","assert.ok(view.includes('implementation.mount(mapContainer, mapData, mountOptions)'))"),
  ("assert.ok(view.includes('normalizeScoutSandboxWaterTankMap'))","assert.ok(view.includes('scoutSandboxSingleSiteViewImplementation'))"),
  ("assert.ok(server.includes('scout_get_component_sandbox_water_tank_map_v1_internal'))","assert.ok(server.includes('scoutSandboxSingleSiteImplementation'))"),
 ],
 'water_tank_map_contract_test.mjs':[
  ("assert.ok(serverSource.includes('scout_get_component_sandbox_water_tank_map_v1_internal'))","assert.ok(serverSource.includes('scoutSandboxSingleSiteImplementation'))"),
  ("assert.ok(viewSource.includes('normalizeScoutSandboxWaterTankMap'))","assert.ok(viewSource.includes('scoutSandboxSingleSiteViewImplementation'))"),
  ("assert.ok(viewSource.includes('mountScoutWaterTankMap'))","assert.ok(viewSource.includes('scoutSandboxSingleSiteViewImplementation'))"),
 ],
 'water_tank_map_integration_test.mjs':[
  ("assert.ok(server.includes('scout_get_component_sandbox_water_tank_map_v1_internal'))","assert.ok(server.includes('scoutSandboxSingleSiteImplementation'))"),
  ("assert.ok(server.includes('buildScoutSandboxWaterTankOpportunity'))","assert.ok(server.includes('loadScoutSandboxSingleSiteOpportunity'))"),
  ("assert.ok(view.includes('mountScoutSingleSiteMap'))","assert.ok(view.includes('scoutSandboxSingleSiteViewImplementation'))"),
  ("assert.ok(view.includes('mountScoutWaterTankMap'))","assert.ok(view.includes('scoutSandboxSingleSiteViewImplementation'))"),
  ("assert.ok(view.includes('normalizeScoutSandboxWaterTankMap'))","assert.ok(view.includes('scoutSandboxSingleSiteViewImplementation'))"),
 ],
 'swppp_site_map_contract_test.mjs':[
  ("assert.equal(serverSource.includes('scout_get_component_sandbox_swppp_site_map_v1_internal'), true)","assert.equal(serverSource.includes('scoutSandboxSingleSiteImplementation'), true)"),
 ],
 'swppp_site_map_integration_test.mjs':[
  ("assert.ok(server.includes('scout_get_component_sandbox_swppp_site_map_v1_internal'))","assert.ok(server.includes('scoutSandboxSingleSiteImplementation'))"),
  ("assert.ok(view.includes('mountScoutSwpppSiteMap'))","assert.ok(view.includes('scoutSandboxSingleSiteViewImplementation'))"),
  ("assert.ok(server.includes(\"_meta: { 'scout/rasterTiles': await loadEmbeddedRasterTilesForSelection('swppp_site', map) }\"))","assert.ok(server.includes(\"_meta: { 'scout/rasterTiles': await loadEmbeddedRasterTilesForSelection(selectedType, map) }\"))"),
 ],
 'swppp_site_map_renderer_test.mjs':[
  ("assert.equal(serverSource.includes('buildScoutSwpppSiteRasterFrame'), true)","assert.equal(serverSource.includes('scoutSandboxSingleSiteImplementation'), true)"),
 ],
 'sandbox_raster_transport_test.mjs':[
  ("assert.ok(serverSource.includes(\"'scout/rasterTiles': await loadEmbeddedRasterTilesForSelection('swppp_site', map)\"))","assert.ok(serverSource.includes('isScoutSandboxSingleSiteType(selectedType)'))"),
  ("assert.ok(serverSource.includes(\"'scout/rasterTiles': await loadEmbeddedRasterTilesForSelection('water_tank', map)\"))","assert.ok(serverSource.includes('scoutSandboxSingleSiteImplementation(selectedType)'))"),
  ("assert.ok(serverSource.includes(\"'scout/rasterTiles': await loadEmbeddedRasterTilesForSelection('premium_exterior', map)\"))","assert.ok(serverSource.includes(\"'scout/rasterTiles': await loadEmbeddedRasterTilesForSelection(selectedType, map)\"))"),
 ],
}
for name,pairs in replacements.items():
    p=root/name
    t=p.read_text()
    for old,new in pairs:
        if old not in t: raise RuntimeError(f'{name}: missing legacy assertion {old}')
        t=t.replace(old,new,1)
    p.write_text(t)

print('Updated legacy single-site wiring tests for registry ownership.')
