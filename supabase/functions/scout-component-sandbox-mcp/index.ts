import 'jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.115.0'
import { createMcpHandler, McpServer } from 'npm:@modelcontextprotocol/server@2.0.0'
import { registerAppResource, registerAppTool, RESOURCE_MIME_TYPE } from 'npm:@modelcontextprotocol/ext-apps@2.0.0/server'
import * as z from 'npm:zod@4.2.0/v4'
import { normalizeScoutSandboxNames, type ScoutSandboxResult } from './contract.ts'
import { SCOUT_VIEW_HTML } from './view.generated.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
let SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
try {
  const keys = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') || '{}')
  SERVICE_KEY = keys.default || SERVICE_KEY
} catch { /* legacy fallback */ }
if (!SERVICE_KEY) throw new Error('Scout sandbox service credential is unavailable')

const admin = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
})

const RESOURCE_URI = 'ui://scout/component-sandbox/v9'
const COMPATIBILITY_RESOURCE_URIS = [
  'ui://scout/component-sandbox/v8',
  'ui://scout/component-sandbox/v7',
  'ui://scout/component-sandbox/v6',
  'ui://scout/component-sandbox/v5',
  'ui://scout/component-sandbox/v4',
  'ui://scout/component-sandbox/v3',
  'ui://scout/component-sandbox/v2',
  'ui://scout/component-sandbox/v1',
] as const
const TOOL_NAME = 'scout_preview_component_sandbox'
const PRIVACY_CONTRACT = 'privacy-contract-v2'
const EXPOSURE_CONTRACT = 'scout-exposure-v1'
const ENUMERATION_CONTRACT = 'scout-enumeration-v1'
async function loadScoutSandboxNames() {
  const { data, error } = await admin.rpc('scout_get_component_sandbox_names_v1_internal')
  if (error) throw new Error('Scout exemplar names are unavailable')
  return normalizeScoutSandboxNames(data)
}

async function isOwnerConnection(connectionId: string) {
  const { data, error } = await admin.rpc('scout_is_owner_connection_internal', {
    p_connection_id: connectionId,
  })
  return !error && data === true
}

async function authenticateOwner(req: Request) {
  const match = (req.headers.get('authorization') || '').match(/^Bearer\s+(.+)$/i)
  if (!match) return null
  const { data, error } = await admin.auth.getUser(match[1].trim())
  if (!error && data.user?.id) {
    const { data: owner, error: ownerError } = await admin.rpc('scout_is_owner_user_internal', {
      p_user_id: data.user.id,
    })
    if (!ownerError && owner === true) return data.user
  }
  const { data: connection, error: connectionError } = await admin.rpc('scout_resolve_agent_connection_v4', {
    p_token: match[1].trim(),
    p_privacy_contract: PRIVACY_CONTRACT,
    p_exposure_contract: EXPOSURE_CONTRACT,
    p_enumeration_contract: ENUMERATION_CONTRACT,
  })
  if (connectionError || !connection?.connection_id) return null
  return await isOwnerConnection(String(connection.connection_id)) ? connection : null
}

function makeServer() {
  const server = new McpServer({ name: 'Scout UI Foundation', version: '2.0.0' })

  registerAppResource(
    server,
    'scout-ui-foundation',
    RESOURCE_URI,
    { mimeType: RESOURCE_MIME_TYPE },
    async () => ({
      contents: [{
        uri: RESOURCE_URI,
        mimeType: RESOURCE_MIME_TYPE,
        text: SCOUT_VIEW_HTML,
        _meta: {
          ui: {
            prefersBorder: false,
            csp: { connectDomains: [], resourceDomains: [] },
          },
        },
      }],
    }),
  )

  for (const compatibilityUri of COMPATIBILITY_RESOURCE_URIS) {
    registerAppResource(
      server,
      `scout-ui-foundation-${compatibilityUri.endsWith('/v2') ? 'v2' : 'v1'}-compatibility`,
      compatibilityUri,
      { mimeType: RESOURCE_MIME_TYPE },
      async () => ({
        contents: [{
          uri: compatibilityUri,
          mimeType: RESOURCE_MIME_TYPE,
          text: SCOUT_VIEW_HTML,
          _meta: {
            ui: {
              prefersBorder: false,
              csp: { connectDomains: [], resourceDomains: [] },
            },
          },
        }],
      }),
    )
  }

  registerAppTool(
    server,
    TOOL_NAME,
    {
      title: 'Preview Scout UI Foundation',
      description: 'Owner-only read-only developer tool that renders the minimal Scout MCP Apps View. Call only when the Scout owner explicitly asks to test or preview the Scout sandbox UI foundation.',
      inputSchema: z.object({}),
      outputSchema: z.object({
        surface: z.literal('scout_component_sandbox'),
        names: z.array(z.string().min(1).max(160)).max(2),
      }),
      annotations: {
        readOnlyHint: true,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false,
      },
      _meta: { ui: { resourceUri: RESOURCE_URI } },
    },
    async () => {
      const names = await loadScoutSandboxNames()
      const structuredContent: ScoutSandboxResult = {
        surface: 'scout_component_sandbox',
        names,
      }
      return {
        content: [{ type: 'text', text: `Scout returned ${names.length} real exemplar name${names.length === 1 ? '' : 's'}.` }],
        structuredContent,
      }
    },
  )

  return server
}

const mcpHandler = createMcpHandler(() => makeServer())

function responseHeaders(base?: HeadersInit) {
  const headers = new Headers(base)
  headers.set('access-control-allow-origin', '*')
  headers.set('access-control-allow-headers', 'authorization,content-type,accept,mcp-protocol-version,mcp-session-id,x-request-id,last-event-id')
  headers.set('access-control-expose-headers', 'mcp-session-id,content-type')
  headers.set('access-control-allow-methods', 'GET,POST,DELETE,OPTIONS')
  headers.set('cache-control', 'no-store, max-age=0')
  headers.set('x-content-type-options', 'nosniff')
  headers.set('referrer-policy', 'no-referrer')
  return headers
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: responseHeaders() })
  if (!(await authenticateOwner(req))) {
    return Response.json({ error: 'not found' }, { status: 404, headers: responseHeaders() })
  }
  try {
    const response = await mcpHandler.fetch(req)
    return new Response(response.body, {
      status: response.status,
      statusText: response.statusText,
      headers: responseHeaders(response.headers),
    })
  } catch (error) {
    console.error('Scout UI foundation MCP error', error)
    return Response.json({ error: 'Scout UI foundation request failed' }, {
      status: 500,
      headers: responseHeaders(),
    })
  }
})
