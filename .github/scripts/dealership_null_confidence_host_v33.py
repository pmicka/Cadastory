from pathlib import Path

root = Path('.')
model = root / 'supabase/functions/scout-component-sandbox-mcp/dealership_portfolio_map_model.ts'
component = root / 'supabase/functions/scout-component-sandbox-mcp/index.ts'
view = root / 'supabase/functions/scout-component-sandbox-mcp/view.ts'
connect = root / 'supabase/functions/scout-connect/index.ts'
contract = root / 'supabase/functions/scout-mcp-contract/index.ts'
test = root / 'supabase/functions/scout-component-sandbox-mcp/dealership_portfolio_map_renderer_test.mjs'

def replace_once(path: Path, old: str, new: str):
    text = path.read_text()
    if old not in text:
        raise SystemExit(f'missing pattern in {path}: {old[:140]!r}')
    path.write_text(text.replace(old, new, 1))

# Host compatibility: unresolved members semantically have no link confidence. Some host projections may omit null-valued properties.
replace_once(model,
"  const linkConfidence = source.link_confidence === null ? null : cleanNumber(source.link_confidence, 0, 1)\n",
"  const linkConfidenceValue = source.link_confidence\n  const linkConfidence = linkConfidenceValue == null ? null : cleanNumber(linkConfidenceValue, 0, 1)\n")
replace_once(model,
"  if (source.link_confidence !== null && linkConfidence === null) return null\n",
"  if (linkConfidenceValue != null && linkConfidence === null) return null\n")

# Advance resource/version so the host receives the corrected View bundle.
replace_once(component, "const RESOURCE_URI = 'ui://scout/component-sandbox/v32'", "const RESOURCE_URI = 'ui://scout/component-sandbox/v33'")
replace_once(component, "const COMPATIBILITY_RESOURCE_URIS = [\n  'ui://scout/component-sandbox/v31',", "const COMPATIBILITY_RESOURCE_URIS = [\n  'ui://scout/component-sandbox/v32',\n  'ui://scout/component-sandbox/v31',")
replace_once(component, "  const server = new McpServer({ name: 'Scout UI Foundation', version: '2.3.2' })", "  const server = new McpServer({ name: 'Scout UI Foundation', version: '2.3.3' })")
replace_once(component, "compatibilityUri === 'ui://scout/component-sandbox/v30' || compatibilityUri === 'ui://scout/component-sandbox/v31')", "compatibilityUri === 'ui://scout/component-sandbox/v30' || compatibilityUri === 'ui://scout/component-sandbox/v31' || compatibilityUri === 'ui://scout/component-sandbox/v32')")
replace_once(view, "const app = new App({ name: 'scout-ui-foundation', version: '2.12.0' })", "const app = new App({ name: 'scout-ui-foundation', version: '2.13.0' })")
for gateway in (connect, contract):
    replace_once(gateway, "const SANDBOX_RESOURCE_URI = 'ui://scout/component-sandbox/v32'", "const SANDBOX_RESOURCE_URI = 'ui://scout/component-sandbox/v33'")
    replace_once(gateway, "const SANDBOX_COMPATIBILITY_RESOURCE_URIS = ['ui://scout/component-sandbox/v31',", "const SANDBOX_COMPATIBILITY_RESOURCE_URIS = ['ui://scout/component-sandbox/v32','ui://scout/component-sandbox/v31',")

# Regression: simulate a host bridge omitting null link_confidence on unresolved members.
text = test.read_text()
needle = "assert.equal(normalized.current_need_scan_complete,true)\n"
insert = needle + "\nconst hostProjectedPayload = structuredClone(rawPayload)\nfor (const member of hostProjectedPayload.members) {\n  if (member.resolution_state === 'unresolved') delete member.link_confidence\n}\nconst hostProjected = normalizeScoutSandboxDealershipPortfolioMap(hostProjectedPayload)\nassert.ok(hostProjected)\nassert.equal(hostProjected.members.filter((member)=>member.resolution_state==='unresolved').every((member)=>member.link_confidence===null), true)\nconst invalidResolvedProjection = structuredClone(rawPayload)\ndelete invalidResolvedProjection.members[0].link_confidence\nassert.equal(normalizeScoutSandboxDealershipPortfolioMap(invalidResolvedProjection), null)\n"
if needle not in text:
    raise SystemExit('renderer regression insertion point missing')
test.write_text(text.replace(needle, insert, 1))

# Sweep latest-resource/view-version expectations only.
for path in (root / 'supabase/functions/scout-component-sandbox-mcp').glob('*_test.mjs'):
    text = path.read_text()
    text = text.replace("ui://scout/component-sandbox/v32", "ui://scout/component-sandbox/v33")
    text = text.replace("version: '2.12.0'", "version: '2.13.0'")
    path.write_text(text)
