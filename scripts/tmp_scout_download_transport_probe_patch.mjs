import fs from 'node:fs'

function read(path){ return fs.readFileSync(path, 'utf8') }
function write(path, value){ fs.writeFileSync(path, value) }
function replaceOne(path, before, after, label){
  const source = read(path)
  const first = source.indexOf(before)
  if(first < 0) throw new Error(`Missing anchor for ${label}`)
  if(source.indexOf(before, first + before.length) >= 0) throw new Error(`Anchor is not unique for ${label}`)
  write(path, source.replace(before, after))
}

const schemaPath = 'supabase/functions/_shared/scout_sandbox_contract_schema.ts'
replaceOne(
  schemaPath,
  "export function sandboxOpportunityTypeInputSchema(){return {type:'object',properties:{opportunity_type:{type:'string',enum:[...SCOUT_SANDBOX_OPPORTUNITY_TYPES]}},additionalProperties:false}}",
  "export function sandboxOpportunityTypeInputSchema(){return {type:'object',properties:{opportunity_type:{type:'string',enum:[...SCOUT_SANDBOX_OPPORTUNITY_TYPES]},download_probe:{type:'boolean',description:'Temporary owner-only diagnostic. Set true only when the owner explicitly requests the MCP Apps file-download transport canary.'}},additionalProperties:false}}",
  'download probe input schema',
)

const indexPath = 'supabase/functions/scout-component-sandbox-mcp/index.ts'
replaceOne(indexPath, "version: '2.3.11'", "version: '2.3.12'", 'component server version')
replaceOne(
  indexPath,
  'description: scoutSandboxToolDescription(),',
  "description: `${scoutSandboxToolDescription()} Temporary owner-only diagnostic: set download_probe=true only when the owner explicitly requests the MCP Apps file-download transport canary.`,",
  'temporary probe tool description',
)
replaceOne(indexPath, 'async ({ opportunity_type }) => {', 'async ({ opportunity_type, download_probe }) => {', 'probe tool argument')
replaceOne(
  indexPath,
  "      const selectedType = opportunity_type ?? 'premium_exterior'\n",
  "      const selectedType = opportunity_type ?? 'premium_exterior'\n      const includeDownloadProbe = download_probe === true\n",
  'probe request flag',
)
replaceOne(
  indexPath,
  "          structuredContent: { surface: 'scout_component_sandbox', opportunity_type: selectedType, opportunity, map },\n          _meta: { 'scout/rasterTiles': await loadEmbeddedRasterTilesForSelection(selectedType, map) },",
  "          structuredContent: { surface: 'scout_component_sandbox', opportunity_type: selectedType, opportunity, map },\n          _meta: { 'scout/rasterTiles': await loadEmbeddedRasterTilesForSelection(selectedType, map), ...(includeDownloadProbe ? { 'scout/downloadProbe': true } : {}) },",
  'portfolio probe result metadata',
)
replaceOne(
  indexPath,
  "        structuredContent: { surface: 'scout_component_sandbox', opportunity_type: selectedType, opportunity, map: implementation.toResultMap(map) },\n        _meta: { 'scout/rasterTiles': await loadEmbeddedRasterTilesForSelection(selectedType, map) },",
  "        structuredContent: { surface: 'scout_component_sandbox', opportunity_type: selectedType, opportunity, map: implementation.toResultMap(map) },\n        _meta: { 'scout/rasterTiles': await loadEmbeddedRasterTilesForSelection(selectedType, map), ...(includeDownloadProbe ? { 'scout/downloadProbe': true } : {}) },",
  'single-site probe result metadata',
)

const viewPath = 'supabase/functions/scout-component-sandbox-mcp/view.ts'
replaceOne(
  viewPath,
  "const mapState = document.querySelector<HTMLElement>('[data-scout-map-state]')\n",
  "const mapState = document.querySelector<HTMLElement>('[data-scout-map-state]')\nconst primaryAction = document.querySelector<HTMLButtonElement>('.action-primary')\n",
  'probe action handle',
)
replaceOne(
  viewPath,
  "let carouselResizeObserver: ResizeObserver | null = null\n",
  "let carouselResizeObserver: ResizeObserver | null = null\nlet downloadProbeRequested = false\nlet downloadProbeRunning = false\n",
  'probe state',
)
replaceOne(viewPath, "version: '2.21.0'", "version: '2.22.0'", 'view app version')

const appAnchor = "const app = new App({ name: 'scout-ui-foundation', version: '2.22.0' })\n"
const probeHelpers = `const app = new App({ name: 'scout-ui-foundation', version: '2.22.0' })\n\nfunction downloadProbeSupported() {\n  return Boolean(app.getHostCapabilities?.()?.downloadFile)\n}\n\nfunction configureDownloadProbeControl() {\n  if (!primaryAction) return\n  primaryAction.onclick = null\n  primaryAction.disabled = true\n  primaryAction.textContent = 'Investigate'\n  primaryAction.title = 'Investigate behavior is not wired in this sandbox'\n  if (!downloadProbeRequested) return\n\n  const supported = downloadProbeSupported()\n  primaryAction.textContent = supported ? 'Test file download' : 'Host lacks download'\n  primaryAction.title = supported\n    ? 'Run the synthetic MCP Apps file-download transport probe'\n    : 'This host did not advertise the MCP Apps downloadFile capability'\n  primaryAction.disabled = !supported\n  primaryAction.onclick = supported ? () => { void runDownloadProbe() } : null\n  setState(supported\n    ? 'Scout download probe ready; host advertises downloadFile'\n    : 'Scout download probe unavailable; host does not advertise downloadFile')\n}\n\nasync function runDownloadProbe() {\n  if (!downloadProbeRequested || downloadProbeRunning || !primaryAction) return\n  if (!downloadProbeSupported()) {\n    configureDownloadProbeControl()\n    return\n  }\n\n  downloadProbeRunning = true\n  primaryAction.disabled = true\n  primaryAction.textContent = 'Requesting download…'\n  setState('Scout download probe request started')\n  try {\n    const result = await app.downloadFile({\n      contents: [{\n        type: 'resource',\n        resource: {\n          uri: 'file:///scout-download-probe.txt',\n          mimeType: 'text/plain',\n          text: 'Scout MCP Apps download transport probe.\\r\\n',\n        },\n      }],\n    })\n    if (result?.isError) {\n      primaryAction.textContent = 'Download cancelled'\n      setState('Scout download probe was cancelled, denied, or rejected by the host')\n      return\n    }\n    primaryAction.textContent = 'Repeat download probe'\n    setState('Scout download probe handed the synthetic file to the host')\n  } catch (error) {\n    primaryAction.textContent = 'Download probe failed'\n    setState(\`Scout download probe failed: \${error instanceof Error ? error.message : String(error)}\`)\n  } finally {\n    downloadProbeRunning = false\n    primaryAction.disabled = !downloadProbeSupported()\n  }\n}\n`
replaceOne(viewPath, appAnchor, probeHelpers, 'single-root App download probe helpers')
replaceOne(
  viewPath,
  "app.ontoolresult = (result) => {\n  const structured = result?.structuredContent\n",
  "app.ontoolresult = (result) => {\n  const structured = result?.structuredContent\n  downloadProbeRequested = result?._meta?.['scout/downloadProbe'] === true\n  configureDownloadProbeControl()\n",
  'probe result activation',
)

const designPath = 'supabase/functions/scout-component-sandbox-mcp/DESIGN_CONTRACT.md'
replaceOne(
  designPath,
  '# Scout component sandbox design contract\n',
  "## Temporary owner approval — 2026-09-17 download transport canary\n\nFor the owner-requested MCP Apps file-download transport diagnostic only, the existing disabled `Investigate` action may become a synthetic download-probe control when and only when `scout_preview_component_sandbox` is explicitly invoked with `download_probe=true`. The probe MUST use the already-connected root `App` instance and `App.downloadFile()`, MUST first require the host-advertised `downloadFile` capability, and MUST send only the fixed synthetic `scout-download-probe.txt` payload. It MUST NOT contain Scout contact data, create a second `App`, use `window.openai`, browser Blob/object-URL download, `navigator.share`, an app-only tool, a new RPC, an external download URL, persistent storage, or new CSP domains. Normal sandbox results remain visually and behaviorally unchanged. Remove this temporary diagnostic after the text-file and synthetic-vCard host canaries are resolved.\n\n# Scout component sandbox design contract\n",
  'temporary download canary owner approval',
)

const testPath = 'supabase/functions/scout-component-sandbox-mcp/download_transport_probe_test.mjs'
write(testPath, `import assert from 'node:assert/strict'\nimport fs from 'node:fs'\n\nconst schema = fs.readFileSync('../_shared/scout_sandbox_contract_schema.ts', 'utf8')\nconst index = fs.readFileSync('./index.ts', 'utf8')\nconst view = fs.readFileSync('./view.ts', 'utf8')\nconst template = fs.readFileSync('./view.template.html', 'utf8')\nconst design = fs.readFileSync('./DESIGN_CONTRACT.md', 'utf8')\n\nassert.match(schema, /download_probe:\\{type:'boolean'/, 'input schema must expose only the temporary boolean diagnostic flag')\nassert.match(index, /download_probe=true only when the owner explicitly requests/, 'tool description must constrain the canary to explicit owner requests')\nassert.match(index, /'scout\\/downloadProbe': true/, 'tool result must activate the View through private result metadata')\nassert.equal((view.match(/new App\\(/g) || []).length, 1, 'download probe must reuse the one root App lifecycle')\nassert.match(view, /app\\.getHostCapabilities\\?\\.\\(\\)\\?\\.downloadFile/, 'probe must gate on the host-advertised download capability')\nassert.match(view, /await app\\.downloadFile\\(/, 'probe must use the MCP Apps downloadFile method on the existing root App')\nassert.match(view, /file:\\/\\/\\/scout-download-probe\\.txt/, 'probe filename must remain fixed and synthetic')\nassert.match(view, /Scout MCP Apps download transport probe\\.\\\\r\\\\n/, 'probe payload must remain fixed synthetic text')\nassert.doesNotMatch(view, /window\\.openai/, 'probe must not restore ChatGPT-specific window APIs')\nassert.doesNotMatch(view, /navigator\\.share/, 'probe must not use device-share fallback')\nassert.doesNotMatch(view, /URL\\.createObjectURL/, 'probe must not use browser object-URL downloads')\nassert.doesNotMatch(view, /new Blob\\(/, 'probe must not create browser Blob download payloads')\nassert.doesNotMatch(view, /import\\(['\"]https?:\\/\\//, 'probe must not dynamically import a second MCP Apps SDK')\nassert.match(template, /title=\"Investigate behavior is not wired in this sandbox\" disabled>Investigate<\\/button>/, 'normal card action must remain inert in the template')\nassert.match(design, /Temporary owner approval — 2026-09-17 download transport canary/, 'temporary owner approval must be durable and explicit')\n\nconsole.log('Scout download transport probe regression passed')\n`)

const packagePath = 'supabase/functions/scout-component-sandbox-mcp/package.json'
replaceOne(
  packagePath,
  '"test": "node foundation_test.mjs &&',
  '"test": "node download_transport_probe_test.mjs && node foundation_test.mjs &&',
  'probe regression test registration',
)

console.log('Applied isolated Scout MCP Apps download transport probe patch')
