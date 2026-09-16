from pathlib import Path

root=Path('supabase/functions/scout-component-sandbox-mcp')
path=root/'foundation_test.mjs'
text=path.read_text()
old='''assert.ok(view.includes("mountScoutSingleSiteMap"));
assert.ok(view.includes("mountScoutWaterTankMap"));
assert.ok(view.includes("normalizeScoutSandboxWaterTankMap"));'''
new='''assert.ok(view.includes("scoutSandboxSingleSiteViewImplementation"));
assert.ok(server.includes("scoutSandboxSingleSiteImplementation"));
assert.ok(server.includes("assertScoutSandboxSingleSiteImplementationCoverage"));'''
if old not in text: raise RuntimeError('foundation direct single-site assertions not found')
text=text.replace(old,new,1)
old2='''assert.ok(server.includes("scout_get_component_sandbox_opportunity_v1_internal"));'''
new2='''assert.ok(server.includes("scout_get_component_sandbox_opportunity_v1_internal"));
assert.ok(server.includes("scout_get_component_sandbox_telecom_change_v1_internal"));'''
if old2 not in text: raise RuntimeError('foundation server RPC assertion anchor not found')
path.write_text(text.replace(old2,new2,1))
print('Updated foundation invariants for single-site registry.')
