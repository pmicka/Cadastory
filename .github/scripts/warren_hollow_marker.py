from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    if old not in text:
        raise SystemExit(f'pattern not found in {path}: {old[:140]!r}')
    p.write_text(text.replace(old, new, 1))

mount = 'supabase/functions/scout-component-sandbox-mcp/water_portfolio_map_mount.ts'
replace_once(
    mount,
    "      marker.style.left = `${markerData.left}px`\n      marker.style.top = `${markerData.top}px`\n      marker.style.backgroundColor = morphology.color\n",
    "      marker.style.left = `${markerData.left}px`\n      marker.style.top = `${markerData.top}px`\n      marker.style.setProperty('--scout-portfolio-marker-color', morphology.color)\n      marker.style.backgroundColor = markerData.serviceState === 'documented_not_in_service' ? '#ffffff' : morphology.color\n",
)
replace_once(
    mount,
    "    statusKey.textContent = 'Ring = historical rehab · Slash = not in service'\n",
    "    statusKey.textContent = 'Halo = historical rehab · Hollow = not in service'\n",
)

template = 'supabase/functions/scout-component-sandbox-mcp/view.template.html'
replace_once(
    template,
    """      .scout-portfolio-marker--not-in-service { opacity: .68; }\n      .scout-portfolio-marker--not-in-service::after {\n        content: '';\n        position: absolute;\n        left: 1px;\n        top: 4px;\n        width: 7px;\n        height: 2px;\n        border-radius: 1px;\n        background: rgba(255,255,255,.96);\n        transform: rotate(-45deg);\n        transform-origin: center;\n      }\n""",
    """      .scout-portfolio-marker--not-in-service {\n        width: 13px;\n        height: 13px;\n        border: 3px solid var(--scout-portfolio-marker-color, #747d73);\n        background: #ffffff;\n      }\n""",
)

component = 'supabase/functions/scout-component-sandbox-mcp/index.ts'
replace_once(
    component,
    "const RESOURCE_URI = 'ui://scout/component-sandbox/v28'\nconst COMPATIBILITY_RESOURCE_URIS = [\n  'ui://scout/component-sandbox/v27',",
    "const RESOURCE_URI = 'ui://scout/component-sandbox/v29'\nconst COMPATIBILITY_RESOURCE_URIS = [\n  'ui://scout/component-sandbox/v28',\n  'ui://scout/component-sandbox/v27',",
)
replace_once(component, "const server = new McpServer({ name: 'Scout UI Foundation', version: '2.2.8' })", "const server = new McpServer({ name: 'Scout UI Foundation', version: '2.2.9' })")
replace_once(
    component,
    "compatibilityUri === 'ui://scout/component-sandbox/v26' || compatibilityUri === 'ui://scout/component-sandbox/v27')",
    "compatibilityUri === 'ui://scout/component-sandbox/v26' || compatibilityUri === 'ui://scout/component-sandbox/v27' || compatibilityUri === 'ui://scout/component-sandbox/v28')",
)

view = 'supabase/functions/scout-component-sandbox-mcp/view.ts'
replace_once(view, "const app = new App({ name: 'scout-ui-foundation', version: '2.8.0' })", "const app = new App({ name: 'scout-ui-foundation', version: '2.9.0' })")

for gateway in ['supabase/functions/scout-connect/index.ts', 'supabase/functions/scout-mcp-contract/index.ts']:
    replace_once(
        gateway,
        "const SANDBOX_RESOURCE_URI = 'ui://scout/component-sandbox/v28'\nconst SANDBOX_COMPATIBILITY_RESOURCE_URIS = ['ui://scout/component-sandbox/v27',",
        "const SANDBOX_RESOURCE_URI = 'ui://scout/component-sandbox/v29'\nconst SANDBOX_COMPATIBILITY_RESOURCE_URIS = ['ui://scout/component-sandbox/v28','ui://scout/component-sandbox/v27',",
    )

for test_path in Path('supabase/functions/scout-component-sandbox-mcp').glob('*test.mjs'):
    text = test_path.read_text()
    text = text.replace("const RESOURCE_URI = 'ui://scout/component-sandbox/v28'", "const RESOURCE_URI = 'ui://scout/component-sandbox/v29'")
    text = text.replace("const SANDBOX_RESOURCE_URI = 'ui://scout/component-sandbox/v28'", "const SANDBOX_RESOURCE_URI = 'ui://scout/component-sandbox/v29'")
    text = text.replace("version: '2.8.0'", "version: '2.9.0'")
    test_path.write_text(text)

portfolio_test = Path('supabase/functions/scout-component-sandbox-mcp/water_portfolio_map_renderer_test.mjs')
text = portfolio_test.read_text()
anchor = "assert.ok(mountSource.includes('MORPHOLOGY_STYLES'))\n"
if anchor not in text:
    raise SystemExit('portfolio test anchor missing')
text = text.replace(anchor, anchor + "assert.ok(mountSource.includes('Hollow = not in service'))\nassert.equal(mountSource.includes('Slash = not in service'), false)\n", 1)
portfolio_test.write_text(text)

for contract_path in [
    'supabase/functions/scout-component-sandbox-mcp/DESIGN_CONTRACT.md',
    'supabase/functions/scout-component-sandbox-mcp/WATER_UTILITY_PORTFOLIO_MAP_CONTRACT.md',
]:
    p = Path(contract_path)
    text = p.read_text()
    text = text.replace('ui://scout/component-sandbox/v28', 'ui://scout/component-sandbox/v29')
    text = text.replace('slash', 'hollow marker')
    text = text.replace('Slash', 'Hollow marker')
    p.write_text(text)
