import 'jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.115.0'
import { createMcpHandler, McpServer } from 'npm:@modelcontextprotocol/server@2.0.0'
import { registerAppResource, registerAppTool, RESOURCE_MIME_TYPE } from 'npm:@modelcontextprotocol/ext-apps@2.0.0/server'
import * as z from 'npm:zod@4.2.0/v4'
import {
  normalizeScoutSandboxNames,
  normalizeScoutSandboxOpportunity,
  normalizeScoutSandboxSingleSiteMap,
  type ScoutSandboxResult,
} from './contract.ts'
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

const RESOURCE_URI = 'ui://scout/component-sandbox/v13'
const COMPATIBILITY_RESOURCE_URIS = [
  'ui://scout/component-sandbox/v12',
  'ui://scout/component-sandbox/v11',
  'ui://scout/component-sandbox/v10',
  'ui://scout/component-sandbox/v9',
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
const MAP_RESOURCE_ORIGIN = 'https://tiles.openfreemap.org'

async function loadScoutSandboxNames() {
  const { data, error } = await admin.rpc('scout_get_component_sandbox_names_v1_internal')
  if (error) throw new Error('Scout exemplar names are unavailable')
  return normalizeScoutSandboxNames(data)
}

async function loadScoutSandboxOpportunity() {
  const { data, error } = await admin.rpc('scout_get_component_sandbox_opportunity_v1_internal')
  if (error) throw new Error('Scout sandbox opportunity is unavailable')
  const opportunity = normalizeScoutSandboxOpportunity(data)
  if (!opportunity) throw new Error('Scout sandbox opportunity did not satisfy the bounded contract')
  return opportunity
}

async function loadScoutSandboxSingleSiteMap() {
  const { data, error } = await admin.rpc('scout_get_component_sandbox_premium_exterior_map_v1_internal')
  if (error) throw new Error('Scout sandbox single-site map is unavailable')
  const map = normalizeScoutSandboxSingleSiteMap(data)
  if (!map) throw new Error('Scout sandbox single-site map did not satisfy the bounded contract')
  return map
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

const sandboxMapSchema = z.object({
  contract_version: z.literal('single_site_map_v1'),
  opportunity_type: z.literal('premium_exterior'),
  opportunity_id: z.string().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i),
  name: z.string().min(1).max(160),
  address: z.string().min(1).max(240),
  site_point: z.object({
    lon: z.number().min(-180).max(180),
    lat: z.number().min(-90).max(90),
    source: z.literal('premium_exterior_target_geocode'),
    method: z.string().min(1).max(120),
  }),
  footprint: z.object({
    geometry: z.object({
      type: z.literal('Polygon'),
      coordinates: z.array(z.array(z.tuple([z.number().min(-180).max(180), z.number().min(-90).max(90)])).min(4).max(2048)).min(1).max(8),
    }),
    bounds: z.object({
      west: z.number().min(-180).max(180),
      south: z.number().min(-90).max(90),
      east: z.number().min(-180).max(180),
      north: z.number().min(-90).max(90),
    }),
    footprint_sqft: z.number().min(0).max(1_000_000_000),
    source: z.object({
      slug: z.string().min(1).max(120),
      name: z.string().min(1).max(240),
      native_id: z.string().min(1).max(240),
      image_date: z.string().min(1).max(40),
      validation_method: z.string().min(1).max(120),
    }),
  }),
  linkage: z.object({
    status: z.literal('reconciled_existing_evidence'),
    basis: z.string().min(1).max(1000),
    guardrail: z.string().min(1).max(1000),
    target_to_footprint_m: z.number().min(0).max(10000),
    stored_match_distance_m: z.number().min(0).max(10000),
  }),
})

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
            csp: { connectDomains: [MAP_RESOURCE_ORIGIN], resourceDomains: [MAP_RESOURCE_ORIGIN] },
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
              csp: { connectDomains: [MAP_RESOURCE_ORIGIN], resourceDomains: [MAP_RESOURCE_ORIGIN] },
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
      title: 'Preview Scout opportunity card',
      description: 'Owner-only read-only developer tool that renders the bounded Scout MCP Apps opportunity card. Call only when the Scout owner explicitly asks to test or preview the Scout sandbox UI foundation.',
      inputSchema: z.object({}),
      outputSchema: z.object({
        surface: z.literal('scout_component_sandbox'),
        names: z.array(z.string().min(1).max(160)).max(2),
        opportunity: z.object({
          name: z.string().min(1).max(160),
          address: z.string().min(1).max(240),
          opportunity_tier: z.string().min(1).max(64),
          opportunity_score: z.number().int().min(0).max(100),
          confidence: z.number().min(0).max(1),
          story_count: z.number().int().min(0).max(1000),
          height_m: z.number().min(0).max(10000),
          footprint_sqft: z.number().min(0).max(1_000_000_000),
          glazing_status: z.string().min(1).max(80),
          observed_at: z.string().min(1).max(80),
          target_class: z.string().min(1).max(80),
          target_subclass: z.string().min(1).max(80),
          buyer_resolvability: z.string().min(1).max(120),
          guardrail: z.string().min(1).max(1000),
        }),
        map: sandboxMapSchema,
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
      const [names, opportunity, map] = await Promise.all([
        loadScoutSandboxNames(),
        loadScoutSandboxOpportunity(),
        loadScoutSandboxSingleSiteMap(),
      ])
      if (map.name !== opportunity.name || map.address !== opportunity.address) {
        throw new Error('Scout sandbox opportunity and map identity do not match')
      }
      const structuredContent: ScoutSandboxResult = {
        surface: 'scout_component_sandbox',
        names,
        opportunity,
        map,
      }
      return {
        content: [{ type: 'text', text: `Scout returned the bounded ${opportunity.name} opportunity card with its single-site map.` }],
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
