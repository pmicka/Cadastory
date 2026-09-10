import 'jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.115.0'
import { createMcpHandler, McpServer } from 'npm:@modelcontextprotocol/server@2.0.0'
import { registerAppResource, registerAppTool, RESOURCE_MIME_TYPE } from 'npm:@modelcontextprotocol/ext-apps@2.0.0/server'
import * as z from 'npm:zod@4.2.0/v4'
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

const RESOURCE_URI = 'ui://scout/component-sandbox/v1'
const TOOL_NAME = 'scout_preview_component_sandbox'

async function authenticateOwner(req: Request) {
  const match = (req.headers.get('authorization') || '').match(/^Bearer\s+(.+)$/i)
  if (!match) return null
  const { data, error } = await admin.auth.getUser(match[1].trim())
  if (error || !data.user?.id) return null
  const { data: owner, error: ownerError } = await admin.rpc('scout_is_owner_user_internal', {
    p_user_id: data.user.id,
  })
  return !ownerError && owner === true ? data.user : null
}

function makeServer() {
  const server = new McpServer({ name: 'Scout UI Foundation', version: '1.0.0' })

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

  registerAppTool(
    server,
    TOOL_NAME,
    {
      title: 'Preview Scout UI Foundation',
      description: 'Owner-only read-only developer tool that renders the minimal Scout MCP Apps View. Call only when the Scout owner explicitly asks to test or preview the Scout sandbox UI foundation.',
      inputSchema: z.object({}),
      outputSchema: z.object({
        surface: z.literal('scout_component_sandbox'),
        version: z.literal('v1'),
        business_data: z.literal(false),
        interaction_scope: z.literal('ephemeral_only'),
        foundation: z.literal('ready'),
      }),
      annotations: {
        readOnlyHint: true,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false,
      },
      _meta: { ui: { resourceUri: RESOURCE_URI } },
    },
    async () => ({
      content: [{ type: 'text', text: 'The minimal Scout MCP Apps View is ready to render.' }],
      structuredContent: {
        surface: 'scout_component_sandbox' as const,
        version: 'v1' as const,
        business_data: false as const,
        interaction_scope: 'ephemeral_only' as const,
        foundation: 'ready' as const,
      },
    }),
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
