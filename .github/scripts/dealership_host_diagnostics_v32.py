from pathlib import Path

root = Path('.')
component = root / 'supabase/functions/scout-component-sandbox-mcp/index.ts'
view = root / 'supabase/functions/scout-component-sandbox-mcp/view.ts'
connect = root / 'supabase/functions/scout-connect/index.ts'
contract = root / 'supabase/functions/scout-mcp-contract/index.ts'


def replace_once(path: Path, old: str, new: str):
    text = path.read_text()
    if old not in text:
        raise SystemExit(f'missing pattern in {path}: {old[:140]!r}')
    path.write_text(text.replace(old, new, 1))

replace_once(component, "const RESOURCE_URI = 'ui://scout/component-sandbox/v31'", "const RESOURCE_URI = 'ui://scout/component-sandbox/v32'")
replace_once(component, "const COMPATIBILITY_RESOURCE_URIS = [\n  'ui://scout/component-sandbox/v30',", "const COMPATIBILITY_RESOURCE_URIS = [\n  'ui://scout/component-sandbox/v31',\n  'ui://scout/component-sandbox/v30',")
replace_once(component, "  const server = new McpServer({ name: 'Scout UI Foundation', version: '2.3.1' })", "  const server = new McpServer({ name: 'Scout UI Foundation', version: '2.3.2' })")
replace_once(component, "compatibilityUri === 'ui://scout/component-sandbox/v29' || compatibilityUri === 'ui://scout/component-sandbox/v30')", "compatibilityUri === 'ui://scout/component-sandbox/v29' || compatibilityUri === 'ui://scout/component-sandbox/v30' || compatibilityUri === 'ui://scout/component-sandbox/v31')")

for gateway in (connect, contract):
    replace_once(gateway, "const SANDBOX_RESOURCE_URI = 'ui://scout/component-sandbox/v31'", "const SANDBOX_RESOURCE_URI = 'ui://scout/component-sandbox/v32'")
    replace_once(gateway, "const SANDBOX_COMPATIBILITY_RESOURCE_URIS = ['ui://scout/component-sandbox/v30',", "const SANDBOX_COMPATIBILITY_RESOURCE_URIS = ['ui://scout/component-sandbox/v31','ui://scout/component-sandbox/v30',")

replace_once(view, "import { mountScoutDealershipPortfolioMap } from './dealership_portfolio_map_mount.ts'", "import { mountScoutDealershipPortfolioMap } from './dealership_portfolio_map_mount.ts'\nimport { buildScoutDealershipPortfolioRasterFrame } from './dealership_portfolio_map_renderer.ts'")
replace_once(view, "      if (opportunityType === 'swppp_site') { diagnostic({ viewReady: true }); diagnosticOverlay(mapState) }\n      setState((opportunityType === 'water_utility_portfolio' || opportunityType === 'dealership_group_portfolio') ? 'Scout portfolio map ready' : 'Scout site map ready')", "      if (opportunityType === 'swppp_site') { diagnostic({ viewReady: true }); diagnosticOverlay(mapState) }\n      if (opportunityType === 'dealership_group_portfolio') { diagnostic({ dealershipReady: true, dealershipError: 'none' }); diagnosticOverlay(mapState) }\n      setState((opportunityType === 'water_utility_portfolio' || opportunityType === 'dealership_group_portfolio') ? 'Scout portfolio map ready' : 'Scout site map ready')")
replace_once(view, "      if (opportunityType === 'swppp_site') { diagnostic({ viewError: true }); diagnosticOverlay(mapState) }\n      setState(`Scout map error: ${error.message}`)", "      if (opportunityType === 'swppp_site') { diagnostic({ viewError: true }); diagnosticOverlay(mapState) }\n      if (opportunityType === 'dealership_group_portfolio') { diagnostic({ dealershipReady: false, dealershipError: error.message.slice(0, 180) }); diagnosticOverlay(mapState) }\n      setState(`Scout map error: ${error.message}`)")
replace_once(view, "      if (!mapData) {\n        mapState.textContent = 'Portfolio map unavailable'\n        setState('Scout dealership portfolio map result failed validation')\n        return\n      }\n      mapContainer.setAttribute('role', 'img')", "      if (!mapData) {\n        diagnostic({ dealershipNormalizer: 'failed' })\n        mapState.textContent = 'Portfolio map unavailable'\n        setState('Scout dealership portfolio map result failed validation')\n        return\n      }\n      const diagnosticFrame = buildScoutDealershipPortfolioRasterFrame(mapData, mapContainer.clientWidth, mapContainer.clientHeight, mapOptions)\n      const matchingEmbeddedTiles = embeddedTiles ? diagnosticFrame.tiles.filter((tile) => Boolean(embeddedTiles[tile.url])).length : 0\n      diagnostic({ dealershipNormalizer: 'passed', dealershipContainerWidth: mapContainer.clientWidth, dealershipContainerHeight: mapContainer.clientHeight, dealershipFrameWidth: diagnosticFrame.width, dealershipFrameHeight: diagnosticFrame.height, dealershipZoom: diagnosticFrame.zoom, dealershipRequiredTiles: diagnosticFrame.tiles.length, dealershipMatchingEmbeddedTiles: matchingEmbeddedTiles, dealershipMarkers: diagnosticFrame.markers.length, dealershipTileSource: embeddedTiles ? 'embedded_available' : 'embedded_missing', dealershipReady: false, dealershipError: 'not_yet' })\n      mapContainer.setAttribute('role', 'img')")
replace_once(view, "  if (control) control.hidden = opportunityType !== 'swppp_site'", "  if (control) control.hidden = opportunityType !== 'swppp_site' && opportunityType !== 'dealership_group_portfolio'")
replace_once(view, "const app = new App({ name: 'scout-ui-foundation', version: '2.11.0' })", "const app = new App({ name: 'scout-ui-foundation', version: '2.12.0' })")
replace_once(view, "  if (opportunityType === 'swppp_site') diagnostic({ rejectedField: 'none', rejectedCheck: 'none', receivedType: 'not_checked', receivedStringShape: 'not_checked', resultCount: ++diagnosticResultCount, branch: 'not_entered', initializationError: 'none', mapNormalizer: 'not_entered', requiredTiles: 0, matchingTiles: 0, generation: 0, loadedTiles: 0, decodedTiles: 0, decodeFailed: 0, drawFailed: 0, imageFailed: 0, rendererReady: false, timeout: false, context2d: 'not_attempted', lastError: 'none', payloadSource: metadataTiles ? 'metadata' : resourceEmbeddedTiles ? 'resource' : 'none', identityMatch: structured?.map?.site_name === structured?.opportunity?.name && structured?.map?.location_label === structured?.opportunity?.location_label })", "  if (opportunityType === 'swppp_site') diagnostic({ rejectedField: 'none', rejectedCheck: 'none', receivedType: 'not_checked', receivedStringShape: 'not_checked', resultCount: ++diagnosticResultCount, branch: 'not_entered', initializationError: 'none', mapNormalizer: 'not_entered', requiredTiles: 0, matchingTiles: 0, generation: 0, loadedTiles: 0, decodedTiles: 0, decodeFailed: 0, drawFailed: 0, imageFailed: 0, rendererReady: false, timeout: false, context2d: 'not_attempted', lastError: 'none', payloadSource: metadataTiles ? 'metadata' : resourceEmbeddedTiles ? 'resource' : 'none', identityMatch: structured?.map?.site_name === structured?.opportunity?.name && structured?.map?.location_label === structured?.opportunity?.location_label })\n  if (opportunityType === 'dealership_group_portfolio') diagnostic({ dealershipResultCount: ++diagnosticResultCount, dealershipPayloadSource: metadataTiles ? 'metadata' : resourceEmbeddedTiles ? 'resource' : 'none', dealershipIdentityMatch: structured?.map?.account_name === structured?.opportunity?.name, dealershipNormalizer: 'not_entered', dealershipReady: false, dealershipError: 'none' })")

for path in (root / 'supabase/functions/scout-component-sandbox-mcp').glob('*_test.mjs'):
    text = path.read_text().replace("ui://scout/component-sandbox/v31", "ui://scout/component-sandbox/v32").replace("version: '2.11.0'", "version: '2.12.0'")
    path.write_text(text)

gateway_test = root / 'supabase/functions/scout-component-sandbox-mcp/dealership_portfolio_gateway_contract_test.mjs'
text = gateway_test.read_text()
anchor = "console.log('Scout dealership-portfolio gateway visibility checks passed.')"
if anchor not in text:
    raise SystemExit('dealership gateway test anchor missing')
checks = "assert.ok(view.includes(\"opportunityType !== 'swppp_site' && opportunityType !== 'dealership_group_portfolio'\"))\nassert.ok(view.includes('dealershipMatchingEmbeddedTiles'))\nassert.ok(view.includes('dealershipPayloadSource'))\nassert.ok(view.includes('dealershipError'))\n"
gateway_test.write_text(text.replace(anchor, checks + anchor, 1))
