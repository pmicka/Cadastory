from pathlib import Path

path = Path(__file__).with_name('bootstrap_sandbox_registry_hardening.py')
text = path.read_text()

old_import = r'''rf"import \{{[\s\S]*?\}} from './{module}\.ts'\n"'''
new_import = r'''rf"import \{{[^}}]+\}} from './{module}\.ts'\n"'''
count = text.count(old_import)
if count != 2:
    raise RuntimeError(f'expected two broad import matchers, found {count}')
text = text.replace(old_import, new_import)

old_subn = "updated, count = re.subn(pattern, replacement, text, count=1, flags=flags)"
new_subn = "updated, count = re.subn(pattern, lambda _match: replacement, text, count=1, flags=flags)"
if text.count(old_subn) != 1:
    raise RuntimeError('expected one bootstrap sub_once implementation')
text = text.replace(old_subn, new_subn)

old_dispatch_pattern = r'''r"    if \(opportunityType === 'dealership_group_portfolio'\) \{[\s\S]*?\n    \} else if \(opportunityType === 'swppp_site'\) \{"'''
new_dispatch_pattern = r'''r"  try \{\n    if \(opportunityType === 'dealership_group_portfolio'\) \{[\s\S]*?\n    \} else if \(opportunityType === 'swppp_site'\) \{"'''
if text.count(old_dispatch_pattern) != 1:
    raise RuntimeError('expected one unscoped portfolio View dispatch matcher')
text = text.replace(old_dispatch_pattern, new_dispatch_pattern)

old_dispatch_replacement = r'''"    if (isScoutSandboxPortfolioType(opportunityType)) {\n      const implementation = scoutSandboxPortfolioImplementation(opportunityType)'''
new_dispatch_replacement = r'''"  try {\n    if (isScoutSandboxPortfolioType(opportunityType)) {\n      const implementation = scoutSandboxPortfolioImplementation(opportunityType)'''
if text.count(old_dispatch_replacement) != 1:
    raise RuntimeError('expected one portfolio View dispatch replacement')
text = text.replace(old_dispatch_replacement, new_dispatch_replacement)
path.write_text(text)

root = path.parents[1]
component_dir = root / 'supabase/functions/scout-component-sandbox-mcp'

# Convert legacy source-string checks to registry invariants instead of restoring duplicated constants.
test_path = component_dir / 'single_site_map_renderer_test.mjs'
test = test_path.read_text()
replacements = {
    "assert.ok(server.includes('SANDBOX_MAP_CENTERS'))": "assert.ok(server.includes('isScoutSandboxRasterTileAllowed'))",
    "assert.ok(server.includes('WARREN_PORTFOLIO_TILE_BOUNDS'))": "assert.ok(server.includes('SCOUT_SANDBOX_PORTFOLIO_MANIFEST'))",
    "assert.ok(server.includes('MAX_EMBEDDED_RASTER_TILES = 40'))": "assert.ok(server.includes('SCOUT_SANDBOX_MAX_EMBEDDED_RASTER_TILES'))",
    "assert.ok(server.includes('buildScoutWaterUtilityPortfolioRasterFrame(portfolioMap, 456, 210'))": "assert.ok(server.includes('for (const type of SCOUT_SANDBOX_PORTFOLIO_TYPES)'))",
    "assert.ok(server.includes(\"const RESOURCE_URI = 'ui://scout/component-sandbox/v34'\"))": "assert.ok(server.includes('const RESOURCE_URI = SCOUT_SANDBOX_RESOURCE_URI'))",
    "assert.ok(server.includes(\"'ui://scout/component-sandbox/v26'\"))": "assert.ok(server.includes('scoutSandboxCompatibilityResourceUris()'))",
    "assert.ok(server.includes(\"'ui://scout/component-sandbox/v15'\"))": "assert.ok(server.includes('scoutSandboxCompatibilityUsesEmbeddedRaster(compatibilityUri)'))",
}
for old, new in replacements.items():
    if test.count(old) != 1:
        raise RuntimeError(f'expected one single-site legacy assertion: {old}')
    test = test.replace(old, new)
test_path.write_text(test)

# Eliminate copied selector lists everywhere in the sandbox suites. The generic registry parity test owns exact exposure coverage.
old_selector = "opportunity_type: z.enum(['premium_exterior', 'water_tank', 'swppp_site', 'water_utility_portfolio', 'dealership_group_portfolio', 'hotel_management_portfolio']).optional()"
new_selector = "opportunity_type: z.enum(SCOUT_SANDBOX_OPPORTUNITY_TYPES).optional()"
selector_replacements = 0
for test_path in component_dir.glob('*_test.mjs'):
    source = test_path.read_text()
    if old_selector in source:
        selector_replacements += source.count(old_selector)
        test_path.write_text(source.replace(old_selector, new_selector))
if selector_replacements < 2:
    raise RuntimeError(f'expected at least two duplicated selector assertions, found {selector_replacements}')

print(f'Tightened bootstrap transforms and replaced {selector_replacements} duplicated selector assertions with registry invariants.')
