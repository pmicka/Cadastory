from pathlib import Path

root = Path('.')
component = root / 'supabase/functions/scout-component-sandbox-mcp/index.ts'
view = root / 'supabase/functions/scout-component-sandbox-mcp/view.ts'
connect = root / 'supabase/functions/scout-connect/index.ts'
contract = root / 'supabase/functions/scout-mcp-contract/index.ts'
renderer_test = root / 'supabase/functions/scout-component-sandbox-mcp/dealership_portfolio_map_renderer_test.mjs'
gateway_test = root / 'supabase/functions/scout-component-sandbox-mcp/dealership_portfolio_gateway_contract_test.mjs'
water_gateway_test = root / 'supabase/functions/scout-component-sandbox-mcp/water_portfolio_gateway_contract_test.mjs'


def replace_once(path: Path, old: str, new: str):
    text = path.read_text()
    if old not in text:
        raise SystemExit(f'missing pattern in {path}: {old[:120]!r}')
    path.write_text(text.replace(old, new, 1))

# Advance resource URI so ChatGPT cannot reuse the v30 resource payload.
replace_once(component, "const RESOURCE_URI = 'ui://scout/component-sandbox/v30'", "const RESOURCE_URI = 'ui://scout/component-sandbox/v31'")
replace_once(component, "const COMPATIBILITY_RESOURCE_URIS = [\n  'ui://scout/component-sandbox/v29',", "const COMPATIBILITY_RESOURCE_URIS = [\n  'ui://scout/component-sandbox/v30',\n  'ui://scout/component-sandbox/v29',")
replace_once(component, "const DEALERSHIP_PORTFOLIO_TILE_BOUNDS = { z: 8, minX: 66, maxX: 68, minY: 98, maxY: 99 } as const", "const DEALERSHIP_PORTFOLIO_TILE_BOUNDS = { z: 8, minX: 66, maxX: 68, minY: 98, maxY: 99 } as const\nconst DEALERSHIP_PORTFOLIO_NARROW_TILE_BOUNDS = { z: 7, minX: 33, maxX: 34, minY: 49, maxY: 49 } as const")
replace_once(component, "    buildScoutDealershipPortfolioRasterFrame(dealershipMap, 456, 210, { tileUrlTemplate }),\n  ]", "    buildScoutDealershipPortfolioRasterFrame(dealershipMap, 456, 210, { tileUrlTemplate }),\n    buildScoutDealershipPortfolioRasterFrame(dealershipMap, 280, 210, { tileUrlTemplate }),\n  ]")
replace_once(component, "  const server = new McpServer({ name: 'Scout UI Foundation', version: '2.3.0' })", "  const server = new McpServer({ name: 'Scout UI Foundation', version: '2.3.1' })")
replace_once(component, "compatibilityUri === 'ui://scout/component-sandbox/v28' || compatibilityUri === 'ui://scout/component-sandbox/v29')", "compatibilityUri === 'ui://scout/component-sandbox/v28' || compatibilityUri === 'ui://scout/component-sandbox/v29' || compatibilityUri === 'ui://scout/component-sandbox/v30')")
replace_once(component, "if (!Number.isInteger(z) || z < 8 || z > 18", "if (!Number.isInteger(z) || z < 7 || z > 18")
replace_once(component, "  if (z === DEALERSHIP_PORTFOLIO_TILE_BOUNDS.z\n    && x >= DEALERSHIP_PORTFOLIO_TILE_BOUNDS.minX && x <= DEALERSHIP_PORTFOLIO_TILE_BOUNDS.maxX\n    && y >= DEALERSHIP_PORTFOLIO_TILE_BOUNDS.minY && y <= DEALERSHIP_PORTFOLIO_TILE_BOUNDS.maxY) return { z, x, y }\n  if (z < 12) return null", "  if (z === DEALERSHIP_PORTFOLIO_TILE_BOUNDS.z\n    && x >= DEALERSHIP_PORTFOLIO_TILE_BOUNDS.minX && x <= DEALERSHIP_PORTFOLIO_TILE_BOUNDS.maxX\n    && y >= DEALERSHIP_PORTFOLIO_TILE_BOUNDS.minY && y <= DEALERSHIP_PORTFOLIO_TILE_BOUNDS.maxY) return { z, x, y }\n  if (z === DEALERSHIP_PORTFOLIO_NARROW_TILE_BOUNDS.z\n    && x >= DEALERSHIP_PORTFOLIO_NARROW_TILE_BOUNDS.minX && x <= DEALERSHIP_PORTFOLIO_NARROW_TILE_BOUNDS.maxX\n    && y >= DEALERSHIP_PORTFOLIO_NARROW_TILE_BOUNDS.minY && y <= DEALERSHIP_PORTFOLIO_NARROW_TILE_BOUNDS.maxY) return { z, x, y }\n  if (z < 12) return null")
replace_once(view, "version: '2.10.0'", "version: '2.11.0'")

for gateway in (connect, contract):
    replace_once(gateway, "const SANDBOX_RESOURCE_URI = 'ui://scout/component-sandbox/v30'", "const SANDBOX_RESOURCE_URI = 'ui://scout/component-sandbox/v31'")
    replace_once(gateway, "const SANDBOX_COMPATIBILITY_RESOURCE_URIS = ['ui://scout/component-sandbox/v29',", "const SANDBOX_COMPATIBILITY_RESOURCE_URIS = ['ui://scout/component-sandbox/v30','ui://scout/component-sandbox/v29',")

# Update latest-resource assertions while preserving explicit compatibility checks.
for path in [gateway_test, water_gateway_test]:
    text = path.read_text().replace("const RESOURCE_URI = 'ui://scout/component-sandbox/v30'", "const RESOURCE_URI = 'ui://scout/component-sandbox/v31'")
    text = text.replace("const SANDBOX_RESOURCE_URI = 'ui://scout/component-sandbox/v30'", "const SANDBOX_RESOURCE_URI = 'ui://scout/component-sandbox/v31'")
    path.write_text(text)

# Add narrow-frame regression coverage.
text = renderer_test.read_text()
needle = "assert.equal(frame.markers.filter((marker)=>marker.resolutionState==='multi_building_resolved').length,1)\n"
insert = needle + "const narrowFrame=buildScoutDealershipPortfolioRasterFrame(normalized,280,210,{tileUrlTemplate:'https://tile.openstreetmap.org/{z}/{x}/{y}.png',minZoom:5,maxZoom:18})\nassert.equal(narrowFrame.zoom,7)\nassert.deepEqual(narrowFrame.tiles.map((tile)=>`${tile.z}/${tile.x}/${tile.y}`).sort(),['7/33/49','7/34/49'])\nassert.equal(narrowFrame.markers.length,8)\n"
if needle not in text:
    raise SystemExit('renderer narrow-frame insertion point missing')
renderer_test.write_text(text.replace(needle, insert, 1))

text = gateway_test.read_text()
needle = "assert.ok(server.includes(\"const RESOURCE_URI = 'ui://scout/component-sandbox/v31'\"))\n"
if needle not in text:
    # Existing test may inline the assertion without a local constant update.
    needle = "assert.ok(server.includes(\"const RESOURCE_URI = 'ui://scout/component-sandbox/v30'\"))\n"
    if needle in text:
        text = text.replace(needle, "assert.ok(server.includes(\"const RESOURCE_URI = 'ui://scout/component-sandbox/v31'\"))\n", 1)
        needle = "assert.ok(server.includes(\"const RESOURCE_URI = 'ui://scout/component-sandbox/v31'\"))\n"
if needle not in text:
    raise SystemExit('gateway server URI assertion missing')
extra = needle + "assert.ok(server.includes(\"const DEALERSHIP_PORTFOLIO_NARROW_TILE_BOUNDS = { z: 7, minX: 33, maxX: 34, minY: 49, maxY: 49 } as const\"))\nassert.ok(server.includes('buildScoutDealershipPortfolioRasterFrame(dealershipMap, 280, 210'))\nassert.ok(server.includes('DEALERSHIP_PORTFOLIO_NARROW_TILE_BOUNDS.z'))\n"
gateway_test.write_text(text.replace(needle, extra, 1))

# Sweep test expectations that intentionally track only the latest resource URI.
for path in (root / 'supabase/functions/scout-component-sandbox-mcp').glob('*_test.mjs'):
    text = path.read_text()
    text = text.replace("RESOURCE_URI = 'ui://scout/component-sandbox/v30'", "RESOURCE_URI = 'ui://scout/component-sandbox/v31'")
    text = text.replace("const RESOURCE_URI = 'ui://scout/component-sandbox/v30'", "const RESOURCE_URI = 'ui://scout/component-sandbox/v31'")
    text = text.replace("const SANDBOX_RESOURCE_URI = 'ui://scout/component-sandbox/v30'", "const SANDBOX_RESOURCE_URI = 'ui://scout/component-sandbox/v31'")
    path.write_text(text)
