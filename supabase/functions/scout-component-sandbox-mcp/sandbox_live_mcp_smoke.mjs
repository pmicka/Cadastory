import assert from 'node:assert/strict'
import { build } from 'esbuild'

const directory = new URL('./', import.meta.url)
const endpoint = process.env.SCOUT_SANDBOX_ENDPOINT?.trim()
const bearer = process.env.SCOUT_SANDBOX_BEARER_TOKEN?.trim()
if (!endpoint || !bearer) {
  throw new Error('Set SCOUT_SANDBOX_ENDPOINT and SCOUT_SANDBOX_BEARER_TOKEN for the live MCP smoke test')
}

const manifestBuild = await build({
  entryPoints: [new URL('../_shared/scout_sandbox_manifest.ts', directory).pathname],
  bundle: true,
  format: 'esm',
  platform: 'node',
  target: 'node22',
  write: false,
})
const manifest = await import(`data:text/javascript;base64,${Buffer.from(manifestBuild.outputFiles[0].text).toString('base64')}`)
const registered = [...manifest.SCOUT_SANDBOX_OPPORTUNITY_TYPES]
const expectedResourceUri = manifest.SCOUT_SANDBOX_RESOURCE_URI
const protocolVersion = process.env.SCOUT_MCP_PROTOCOL_VERSION?.trim() || '2025-06-18'
let sessionId = null
let nextId = 1

function parseEventStream(text, expectedId) {
  const messages = []
  for (const block of text.split(/\r?\n\r?\n/)) {
    const data = block.split(/\r?\n/)
      .filter((line) => line.startsWith('data:'))
      .map((line) => line.slice(5).trim())
      .join('\n')
    if (!data) continue
    try { messages.push(JSON.parse(data)) } catch { /* ignore keepalive/non-JSON events */ }
  }
  return messages.find((message) => message?.id === expectedId) ?? messages.at(-1) ?? null
}

async function post(message, expectedId = null) {
  const headers = {
    authorization: `Bearer ${bearer}`,
    accept: 'application/json, text/event-stream',
    'content-type': 'application/json',
    'mcp-protocol-version': protocolVersion,
  }
  if (sessionId) headers['mcp-session-id'] = sessionId
  const response = await fetch(endpoint, { method: 'POST', headers, body: JSON.stringify(message) })
  if (response.headers.get('mcp-session-id')) sessionId = response.headers.get('mcp-session-id')
  const text = await response.text()
  assert.ok(response.ok, `MCP HTTP ${response.status}: ${text.slice(0, 1000)}`)
  if (!text.trim()) return null
  const contentType = response.headers.get('content-type') || ''
  const payload = contentType.includes('text/event-stream')
    ? parseEventStream(text, expectedId)
    : JSON.parse(text)
  if (payload?.error) throw new Error(`MCP ${payload.error.code}: ${payload.error.message}`)
  return payload
}

async function rpc(method, params = {}) {
  const id = nextId++
  const payload = await post({ jsonrpc: '2.0', id, method, params }, id)
  assert.equal(payload?.id, id, `${method} returned an unexpected JSON-RPC id`)
  return payload.result
}

const initialized = await rpc('initialize', {
  protocolVersion,
  capabilities: {},
  clientInfo: { name: 'scout-sandbox-live-smoke', version: '1.0.0' },
})
assert.ok(initialized?.protocolVersion, 'initialize did not negotiate an MCP protocol version')
await post({ jsonrpc: '2.0', method: 'notifications/initialized', params: {} })

const toolsResult = await rpc('tools/list')
const tool = toolsResult?.tools?.find((candidate) => candidate.name === 'scout_preview_component_sandbox')
assert.ok(tool, 'tools/list did not advertise scout_preview_component_sandbox')
assert.deepEqual(tool.inputSchema?.properties?.opportunity_type?.enum, registered, 'live tools/list selector differs from the registered manifest')
const toolOutputTypes = tool.outputSchema?.oneOf?.map((branch) => branch.properties?.opportunity_type?.enum?.[0])
assert.deepEqual(toolOutputTypes, registered, 'live tools/list output branches differ from the registered manifest')
assert.equal(tool._meta?.ui?.resourceUri, expectedResourceUri, 'live tool advertises the wrong UI resource URI')

const resourcesResult = await rpc('resources/list')
const resourceUris = (resourcesResult?.resources || []).map((resource) => resource.uri)
assert.ok(resourceUris.includes(expectedResourceUri), `resources/list did not advertise ${expectedResourceUri}`)
const resourceResult = await rpc('resources/read', { uri: expectedResourceUri })
const resource = resourceResult?.contents?.find((content) => content.uri === expectedResourceUri)
assert.ok(resource?.text?.includes('scout_component_sandbox') || resource?.text?.includes('Scout'), 'resources/read returned an unexpected sandbox resource')

for (const type of registered) {
  const call = await rpc('tools/call', {
    name: 'scout_preview_component_sandbox',
    arguments: { opportunity_type: type },
  })
  assert.equal(call?.isError, undefined, `${type} returned an MCP tool error`)
  const structured = call?.structuredContent
  assert.equal(structured?.surface, 'scout_component_sandbox', `${type} returned the wrong structuredContent surface`)
  assert.equal(structured?.opportunity_type, type, `${type} returned the wrong structuredContent discriminator`)
  assert.equal(structured?.opportunity?.opportunity_type, type, `${type} opportunity discriminator mismatch`)
  assert.equal(structured?.map?.opportunity_type, type, `${type} map discriminator mismatch`)
}

console.log(JSON.stringify({
  endpoint,
  negotiated_protocol_version: initialized.protocolVersion,
  session_id_present: Boolean(sessionId),
  resource_uri: expectedResourceUri,
  registered_types: registered,
  tools_list_verified: true,
  resources_list_verified: true,
  resource_read_verified: true,
  tool_calls_verified: registered.length,
}, null, 2))
