import 'jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.115.0'
import { createMcpHandler, McpServer } from 'npm:@modelcontextprotocol/server@2.0.0'
import { registerAppResource, registerAppTool, RESOURCE_MIME_TYPE } from 'npm:@modelcontextprotocol/ext-apps@2.0.0/server'
import * as z from 'npm:zod@4.2.0/v4'
import {
  buildScoutSandboxWaterTankOpportunity,
  normalizeScoutSandboxOpportunity,
  normalizeScoutSandboxSingleSiteMap,
  normalizeScoutSandboxWaterTankMap,
  type ScoutSandboxResult,
} from './contract.ts'
import { buildScoutSandboxSwpppSiteOpportunity, normalizeScoutSandboxSwpppSiteMap } from './swppp_site_map_model.ts'
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

const RESOURCE_URI = 'ui://scout/component-sandbox/v19'
const COMPATIBILITY_RESOURCE_URIS = [
  'ui://scout/component-sandbox/v18',
  'ui://scout/component-sandbox/v17',
  'ui://scout/component-sandbox/v16',
  'ui://scout/component-sandbox/v15',
  'ui://scout/component-sandbox/v14',
  'ui://scout/component-sandbox/v13',
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
const MAP_TILE_ORIGIN = SUPABASE_URL
const MAP_TILE_UPSTREAM = 'https://a.tile.openstreetmap.fr/hot'
const SANDBOX_MAP_CENTERS = [
  { lon: -85.758115986691, lat: 38.256732011411 },
  { lon: -86.4781456168917, lat: 36.9655317362621 },
  { lon: -84.521, lat: 39.097 },
] as const

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

async function loadScoutSandboxWaterTankMap() {
  const { data, error } = await admin.rpc('scout_get_component_sandbox_water_tank_map_v1_internal')
  if (error) throw new Error('Scout sandbox water-tank map is unavailable')
  const map = normalizeScoutSandboxWaterTankMap(data)
  if (!map) throw new Error('Scout sandbox water-tank map did not satisfy the bounded contract')
  return map
}

async function loadScoutSandboxSwpppSiteMap() {
  const { data, error } = await admin.rpc('scout_get_component_sandbox_swppp_site_map_v1_internal')
  if (error) throw new Error('Scout sandbox SWPPP-site map is unavailable')
  const map = normalizeScoutSandboxSwpppSiteMap(data)
  if (!map) throw new Error('Scout sandbox SWPPP-site map did not satisfy the bounded contract')
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

const premiumOpportunitySchema = z.object({
  opportunity_type: z.literal('premium_exterior'),
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
})

const waterTankOpportunitySchema = z.object({
  opportunity_type: z.literal('water_tank'),
  name: z.string().min(1).max(160),
  system_name: z.string().min(1).max(200),
  status: z.literal('rehab_signal'),
  confidence: z.number().min(0).max(1),
  observed_at: z.string().min(1).max(80),
  tank_type: z.literal('ELEVATED'),
  capacity_gallons: z.number().min(1).max(100_000_000),
  morphology_class: z.string().min(1).max(120),
  support_geometry: z.literal('single_pedestal'),
  operator_assessment: z.literal('favorable'),
  project_status: z.literal('REHAB'),
  project_purpose: z.string().min(1).max(300),
  guardrail: z.string().min(1).max(1000),
})

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

const waterTankMapSchema = z.object({
  contract_version: z.literal('water_tank_single_site_map_v1'),
  opportunity_type: z.literal('water_tank'),
  tank_id: z.string().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i),
  candidate_key: z.string().min(1).max(100),
  name: z.string().min(1).max(160),
  system_name: z.string().min(1).max(200),
  site_point: z.object({
    lon: z.number().min(-180).max(180),
    lat: z.number().min(-90).max(90),
    source: z.literal('kentucky_wris_water_tank'),
    source_slug: z.literal('ky-kia-water-tanks'),
    source_name: z.string().min(1).max(240),
    source_authority: z.string().min(1).max(240),
    source_native_id: z.string().min(1).max(240),
    wris_fid: z.string().min(1).max(80),
    pwsid: z.string().min(1).max(80),
    retrieved_at: z.string().min(1).max(80),
  }),
  asset: z.object({
    tank_type: z.literal('ELEVATED'),
    capacity_gallons: z.number().min(1).max(100_000_000),
    construction_date: z.string().min(1).max(40).nullable(),
    last_cleaning_date: z.string().min(1).max(40).nullable(),
    last_inspection_date: z.string().min(1).max(40).nullable(),
    out_of_service: z.literal(false),
  }),
  geometry: z.object({
    morphology_class: z.string().min(1).max(120),
    support_geometry: z.literal('single_pedestal'),
    cross_bracing_status: z.literal('none'),
    support_leg_count: z.number().int().min(0).max(64).nullable(),
    operator_assessment: z.literal('favorable'),
    operator_assessment_basis: z.string().min(1).max(1000),
    evidence_kind: z.literal('engineering_document'),
    confidence: z.number().min(0).max(1),
    source_authority: z.string().min(1).max(300),
    source_url: z.string().min(1).max(1000),
    observed_on: z.string().min(1).max(40),
    media_retained: z.literal(false),
    guardrail: z.string().min(1).max(1000),
  }),
  project_linkage: z.object({
    project_id: z.string().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i),
    pnum: z.string().min(1).max(80),
    status: z.literal('REHAB'),
    purpose: z.string().min(1).max(120).nullable(),
    other_purpose: z.string().min(1).max(300).nullable(),
    match_method: z.string().min(1).max(120),
    match_distance_m: z.number().min(0).max(10000),
    source_modified_at: z.string().min(1).max(80),
    guardrail: z.string().min(1).max(1000),
  }),
})

const premiumResultSchema = z.object({
  surface: z.literal('scout_component_sandbox'),
  opportunity_type: z.literal('premium_exterior'),
  opportunity: premiumOpportunitySchema,
  map: sandboxMapSchema,
})

const waterTankResultSchema = z.object({
  surface: z.literal('scout_component_sandbox'),
  opportunity_type: z.literal('water_tank'),
  opportunity: waterTankOpportunitySchema,
  map: waterTankMapSchema,
})

const swpppSiteMapSchema = z.object({
  contract_version: z.literal('swppp_site_map_v1'),
  opportunity_type: z.literal('swppp_site'),
  candidate_key: z.string().min(1).max(160),
  site_name: z.string().min(1).max(200),
  location_label: z.string().min(1).max(160),
  project_reference: z.string().min(1).max(80),
  site_point: z.object({
    lon: z.number().min(-180).max(180), lat: z.number().min(-90).max(90),
    geometry_type: z.literal('Point'), semantics: z.literal('authoritative_permit_location_point'),
    guardrail: z.string().min(1).max(1000),
  }),
  permit: z.object({
    evidence_status: z.literal('active_documented_state_construction_permit'), status: z.literal('ACTIVE'),
    type: z.literal('CONSTRUCTION_STORMWATER'), category: z.literal('GENERAL_CONSTRUCTION'),
    permit_number: z.string().min(1).max(80), registry_id: z.string().min(1).max(80),
    master_permit_number: z.string().min(1).max(80), issue_date: z.string().min(1).max(40),
    effective_date: z.string().min(1).max(40), expiration_date: z.string().min(1).max(40),
    termination_date: z.null(), documented_total_acres: z.number().min(1).max(10_000_000),
    acreage_semantics: z.string().min(1).max(1000),
  }),
  source: z.object({
    slug: z.literal('ohio-epa-npdes-construction'), name: z.string().min(1).max(240),
    authority: z.string().min(1).max(240), authority_level: z.literal('state'),
    source_native_id: z.string().min(1).max(240), source_url: z.string().min(1).max(1000),
    last_seen_at: z.string().min(1).max(80),
  }),
  buyer: z.object({ classification: z.literal('unresolved'), organization_id: z.null(), guardrail: z.string().min(1).max(1000) }),
  why_investigate: z.string().min(1).max(1000), guardrail: z.string().min(1).max(1000),
})

const swpppSiteOpportunitySchema = z.object({
  opportunity_type: z.literal('swppp_site'), name: z.string().min(1).max(200),
  location_label: z.string().min(1).max(160), evidence_status: z.literal('active_documented_state_construction_permit'),
  observed_at: z.string().min(1).max(80), permit_number: z.string().min(1).max(80),
  permit_status: z.literal('ACTIVE'), permit_type: z.literal('CONSTRUCTION_STORMWATER'),
  permit_effective_date: z.string().min(1).max(40), permit_expiration_date: z.string().min(1).max(40),
  documented_total_acres: z.number().min(1).max(10_000_000), project_reference: z.string().min(1).max(80),
  buyer_resolvability: z.literal('unresolved'), why_investigate: z.string().min(1).max(1000),
  guardrail: z.string().min(1).max(1000),
})

const swpppSiteResultSchema = z.object({
  surface: z.literal('scout_component_sandbox'), opportunity_type: z.literal('swppp_site'),
  opportunity: swpppSiteOpportunitySchema, map: swpppSiteMapSchema,
})

function makeServer() {
  const server = new McpServer({ name: 'Scout UI Foundation', version: '2.2.2' })

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
            csp: { resourceDomains: [MAP_TILE_ORIGIN] },
          },
        },
      }],
    }),
  )

  for (const compatibilityUri of COMPATIBILITY_RESOURCE_URIS) {
    registerAppResource(
      server,
      `scout-ui-foundation-${compatibilityUri.split('/').at(-1)}-compatibility`,
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
              csp: { resourceDomains: [MAP_TILE_ORIGIN] },
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
      description: 'Owner-only read-only developer tool that renders one bounded Scout MCP Apps opportunity card and matching single-site map. Select premium_exterior, water_tank, or swppp_site; omission preserves the PNC Tower compatibility default.',
      inputSchema: z.object({
        opportunity_type: z.enum(['premium_exterior', 'water_tank', 'swppp_site']).optional(),
      }),
      outputSchema: z.discriminatedUnion('opportunity_type', [premiumResultSchema, waterTankResultSchema, swpppSiteResultSchema]),
      annotations: {
        readOnlyHint: true,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false,
      },
      _meta: { ui: { resourceUri: RESOURCE_URI } },
    },
    async ({ opportunity_type }) => {
      const selectedType = opportunity_type ?? 'premium_exterior'

      if (selectedType === 'swppp_site') {
        const map = await loadScoutSandboxSwpppSiteMap()
        const opportunity = buildScoutSandboxSwpppSiteOpportunity(map)
        if (map.site_name !== opportunity.name || map.location_label !== opportunity.location_label) {
          throw new Error('Scout sandbox SWPPP-site opportunity and map identity do not match')
        }
        const structuredContent: ScoutSandboxResult = {
          surface: 'scout_component_sandbox', opportunity_type: 'swppp_site', opportunity, map,
        }
        return {
          content: [{ type: 'text', text: `Scout returned the bounded ${opportunity.name} SWPPP-site evidence card with its authoritative permit-location point map.` }],
          structuredContent,
        }
      }

      if (selectedType === 'water_tank') {
        const map = await loadScoutSandboxWaterTankMap()
        const opportunity = buildScoutSandboxWaterTankOpportunity(map)
        if (map.name !== opportunity.name || map.system_name !== opportunity.system_name) {
          throw new Error('Scout sandbox water-tank opportunity and map identity do not match')
        }
        const structuredContent: ScoutSandboxResult = {
          surface: 'scout_component_sandbox',
          opportunity_type: 'water_tank',
          opportunity,
          map,
        }
        return {
          content: [{ type: 'text', text: `Scout returned the bounded ${opportunity.name} water-tank opportunity card with its single-site map.` }],
          structuredContent,
        }
      }

      const [opportunity, map] = await Promise.all([
        loadScoutSandboxOpportunity(),
        loadScoutSandboxSingleSiteMap(),
      ])
      if (map.name !== opportunity.name || map.address !== opportunity.address) {
        throw new Error('Scout sandbox premium-exterior opportunity and map identity do not match')
      }
      const structuredContent: ScoutSandboxResult = {
        surface: 'scout_component_sandbox',
        opportunity_type: 'premium_exterior',
        opportunity,
        map,
      }
      return {
        content: [{ type: 'text', text: `Scout returned the bounded ${opportunity.name} premium-exterior opportunity card with its single-site map.` }],
        structuredContent,
      }
    },
  )

  return server
}

const mcpHandler = createMcpHandler(() => makeServer())

function tileCenter(z: number, x: number, y: number) {
  const count = Math.pow(2, z)
  const lon = (x + 0.5) / count * 360 - 180
  const mercator = Math.PI * (1 - 2 * (y + 0.5) / count)
  const lat = Math.atan(Math.sinh(mercator)) * 180 / Math.PI
  return { lon, lat }
}

function parseSandboxTile(url: URL) {
  const match = url.pathname.match(/\/map-tile\/(\d{1,2})\/(\d{1,8})\/(\d{1,8})\.png$/)
  if (!match) return null
  const z = Number(match[1]), x = Number(match[2]), y = Number(match[3])
  const count = Math.pow(2, z)
  if (!Number.isInteger(z) || z < 12 || z > 18 || x < 0 || y < 0 || x >= count || y >= count) return null
  const center = tileCenter(z, x, y)
  if (!SANDBOX_MAP_CENTERS.some((site) => Math.abs(center.lon - site.lon) <= 0.12 && Math.abs(center.lat - site.lat) <= 0.12)) return null
  return { z, x, y }
}

async function serveSandboxTile(req: Request, tile: { z: number; x: number; y: number }) {
  try {
    const upstream = await fetch(`${MAP_TILE_UPSTREAM}/${tile.z}/${tile.x}/${tile.y}.png`, {
      headers: { 'user-agent': 'Scout-by-Cadastory-Sandbox/1.0 (+https://github.com/pmicka/Cadastory)' },
    })
    if (!upstream.ok || !String(upstream.headers.get('content-type')).startsWith('image/')) {
      return new Response(null, { status: 502, headers: { 'access-control-allow-origin': '*' } })
    }
    const headers = new Headers({
      'access-control-allow-origin': '*',
      'cache-control': 'public, max-age=86400, stale-while-revalidate=604800, stale-if-error=604800',
      'content-type': upstream.headers.get('content-type') || 'image/png',
      'x-content-type-options': 'nosniff',
    })
    return new Response(req.method === 'HEAD' ? null : upstream.body, { status: 200, headers })
  } catch {
    return new Response(null, { status: 502, headers: { 'access-control-allow-origin': '*' } })
  }
}

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
  if (req.method === 'GET' || req.method === 'HEAD') {
    const tile = parseSandboxTile(new URL(req.url))
    if (tile) return await serveSandboxTile(req, tile)
  }
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
