import { buildScoutSwpppSiteTransport } from './swppp_site_transport.ts'
import 'jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.115.0'
import { createMcpHandler, fromJsonSchema, McpServer } from 'npm:@modelcontextprotocol/server@2.0.0'
import { registerAppResource, registerAppTool, RESOURCE_MIME_TYPE } from 'npm:@modelcontextprotocol/ext-apps@2.0.0/server'
import {
  SCOUT_SANDBOX_MAX_EMBEDDED_RASTER_TILES,
  SCOUT_SANDBOX_OPPORTUNITY_TYPES,
  SCOUT_SANDBOX_OPPORTUNITY_MANIFEST,
  SCOUT_SANDBOX_PORTFOLIO_MANIFEST,
  SCOUT_SANDBOX_RESOURCE_URI,
  isScoutSandboxPortfolioType,
  isScoutSandboxRasterTileAllowed,
  scoutSandboxCompatibilityResourceUris,
  scoutSandboxToolDescription,
  type ScoutSandboxOpportunityType,
  type ScoutSandboxPortfolioType,
} from '../_shared/scout_sandbox_manifest.ts'
import { sandboxOpportunityTypeInputSchema, sandboxResultSchema } from '../_shared/scout_sandbox_contract_schema.ts'
import { assertScoutSandboxPortfolioImplementationCoverage, scoutSandboxPortfolioImplementation } from './portfolio_registry.ts'
import {
  buildScoutSandboxWaterTankOpportunity,
  normalizeScoutSandboxOpportunity,
  normalizeScoutSandboxSingleSiteMap,
  normalizeScoutSandboxWaterTankMap,
  type ScoutSandboxResult,
} from './contract.ts'
import {
  buildScoutSandboxSwpppSiteOpportunity,
  normalizeScoutSandboxSwpppSiteMap,
  type ScoutSandboxSwpppSiteMap,
} from './swppp_site_map_model.ts'
import { SCOUT_VIEW_HTML } from './view.generated.ts'
import { buildScoutSwpppSiteRasterFrame } from './swppp_site_map_renderer.ts'
import { buildScoutSingleSiteRasterFrame } from './single_site_map_renderer.ts'
import { buildScoutWaterTankRasterFrame } from './water_tank_map_renderer.ts'

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

const RESOURCE_URI = SCOUT_SANDBOX_RESOURCE_URI
const COMPATIBILITY_RESOURCE_URIS = scoutSandboxCompatibilityResourceUris()
const TOOL_NAME = 'scout_preview_component_sandbox'
const PRIVACY_CONTRACT = 'privacy-contract-v2'
const EXPOSURE_CONTRACT = 'scout-exposure-v1'
const ENUMERATION_CONTRACT = 'scout-enumeration-v1'
const MAP_TILE_ORIGIN = SUPABASE_URL
const MAP_TILE_UPSTREAM = 'https://a.tile.openstreetmap.fr/hot'

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

async function loadScoutSandboxPortfolioMap(type: ScoutSandboxPortfolioType) {
  const registration = SCOUT_SANDBOX_PORTFOLIO_MANIFEST[type]
  const implementation = scoutSandboxPortfolioImplementation(type)
  const { data, error } = await admin.rpc(registration.rpc)
  if (error) throw new Error(`Scout sandbox ${type} map is unavailable`)
  const map = implementation.normalizeMap(data)
  if (!map) throw new Error(`Scout sandbox ${type} map did not satisfy the bounded contract`)
  return map
}

type EmbeddedRasterTile = { z: number; x: number; y: number; url: string }
type EmbeddedRasterPayload = { url: string; data_url: string }
const MAX_EMBEDDED_RASTER_TILES = SCOUT_SANDBOX_MAX_EMBEDDED_RASTER_TILES
const EMBEDDED_RASTER_FETCH_TIMEOUT_MS = 3500
const TILE_URL_TEMPLATE = `${SUPABASE_URL}/functions/v1/scout-component-sandbox-mcp/map-tile/{z}/{x}/{y}.png`

async function loadEmbeddedRasterTile(tile: EmbeddedRasterTile): Promise<EmbeddedRasterPayload | null> {
  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), EMBEDDED_RASTER_FETCH_TIMEOUT_MS)
  try {
    const response = await fetch(`${MAP_TILE_UPSTREAM}/${tile.z}/${tile.x}/${tile.y}.png`, {
      headers: { 'user-agent': 'Scout-by-Cadastory-Sandbox/1.0 (+https://github.com/pmicka/Cadastory)' },
      signal: controller.signal,
    })
    if (!response.ok || !String(response.headers.get('content-type')).startsWith('image/png')) return null
    const bytes = new Uint8Array(await response.arrayBuffer())
    let binary = ''
    for (const byte of bytes) binary += String.fromCharCode(byte)
    return { url: tile.url, data_url: `data:image/png;base64,${btoa(binary)}` }
  } catch {
    return null
  } finally {
    clearTimeout(timeout)
  }
}

function selectedRasterFrames(selectedType: ScoutSandboxOpportunityType, map: any) {
  const registration = SCOUT_SANDBOX_OPPORTUNITY_MANIFEST[selectedType]
  if (isScoutSandboxPortfolioType(selectedType)) {
    const implementation = scoutSandboxPortfolioImplementation(selectedType)
    return registration.rasterFrames.map((frameSize) =>
      implementation.buildRasterFrame(map, frameSize.width, frameSize.height, { tileUrlTemplate: TILE_URL_TEMPLATE })
    )
  }
  return registration.rasterFrames.map((frameSize) => {
    if (selectedType === 'swppp_site') return buildScoutSwpppSiteRasterFrame(map, frameSize.width, frameSize.height, { tileUrlTemplate: TILE_URL_TEMPLATE })
    if (selectedType === 'water_tank') return buildScoutWaterTankRasterFrame(map, frameSize.width, frameSize.height, { tileUrlTemplate: TILE_URL_TEMPLATE })
    return buildScoutSingleSiteRasterFrame(map, frameSize.width, frameSize.height, { tileUrlTemplate: TILE_URL_TEMPLATE })
  })
}

async function loadEmbeddedRasterTilesForSelection(selectedType: ScoutSandboxOpportunityType, map: any) {
  if (isScoutSandboxPortfolioType(selectedType)) assertScoutSandboxPortfolioImplementationCoverage()
  const uniqueTiles = new Map<string, EmbeddedRasterTile>()
  for (const frame of selectedRasterFrames(selectedType, map)) {
    for (const tile of frame.tiles) uniqueTiles.set(tile.url, tile)
  }
  if (uniqueTiles.size > MAX_EMBEDDED_RASTER_TILES) {
    throw new Error(`Scout sandbox ${selectedType} raster requires ${uniqueTiles.size} tiles, exceeding bounded per-result budget ${MAX_EMBEDDED_RASTER_TILES}`)
  }
  const payloads = await Promise.all(Array.from(uniqueTiles.values(), loadEmbeddedRasterTile))
  return payloads.filter((payload): payload is EmbeddedRasterPayload => payload !== null)
}

function staticScoutViewHtml(resourceUri: string) {
  return SCOUT_VIEW_HTML
    .replace('__SCOUT_EMBEDDED_RASTER_TILES__', '[]')
    .replace('__SCOUT_DIAGNOSTIC_RESOURCE_URI__', resourceUri)
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

const componentInputSchema = fromJsonSchema(sandboxOpportunityTypeInputSchema())
const componentOutputSchema = fromJsonSchema(sandboxResultSchema())

function makeServer() {
  const server = new McpServer({ name: 'Scout UI Foundation', version: '2.3.8' })

  registerAppResource(
    server,
    'scout-ui-foundation',
    RESOURCE_URI,
    { mimeType: RESOURCE_MIME_TYPE },
    async () => ({
      contents: [{
        uri: RESOURCE_URI,
        mimeType: RESOURCE_MIME_TYPE,
        text: staticScoutViewHtml(RESOURCE_URI),
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
          text: staticScoutViewHtml(compatibilityUri),
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
      description: scoutSandboxToolDescription(),
      inputSchema: componentInputSchema,
      outputSchema: componentOutputSchema,
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

      if (isScoutSandboxPortfolioType(selectedType)) {
        const map = await loadScoutSandboxPortfolioMap(selectedType)
        const implementation = scoutSandboxPortfolioImplementation(selectedType)
        const opportunity = implementation.buildOpportunity(map)
        if (!implementation.identityMatches(map, opportunity)) throw new Error(`Scout sandbox ${selectedType} opportunity and map identity do not match`)
        return {
          content: [{ type: 'text', text: implementation.responseText(opportunity) }],
          structuredContent: { surface: 'scout_component_sandbox', opportunity_type: selectedType, opportunity, map },
          _meta: { 'scout/rasterTiles': await loadEmbeddedRasterTilesForSelection(selectedType, map) },
        }
      }

      if (selectedType === 'swppp_site') {
        const map = await loadScoutSandboxSwpppSiteMap()
        const opportunity = buildScoutSandboxSwpppSiteOpportunity(map)
        if (map.site_name !== opportunity.name || map.location_label !== opportunity.location_label) {
          throw new Error('Scout sandbox SWPPP-site opportunity and map identity do not match')
        }
        const structuredContent: ScoutSandboxResult = {
          surface: 'scout_component_sandbox', opportunity_type: 'swppp_site', opportunity, map: buildScoutSwpppSiteTransport(map),
        }
        return {
          content: [{ type: 'text', text: `Scout returned the bounded ${opportunity.name} SWPPP-site evidence card with its authoritative permit-location point map.` }],
          structuredContent,
          _meta: { 'scout/rasterTiles': await loadEmbeddedRasterTilesForSelection('swppp_site', map) },
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
          _meta: { 'scout/rasterTiles': await loadEmbeddedRasterTilesForSelection('water_tank', map) },
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
        _meta: { 'scout/rasterTiles': await loadEmbeddedRasterTilesForSelection('premium_exterior', map) },
      }
    },
  )

  return server
}

const mcpHandler = createMcpHandler(() => makeServer())

function parseSandboxTile(url: URL) {
  const match = url.pathname.match(/\/map-tile\/(\d{1,2})\/(\d{1,8})\/(\d{1,8})\.png$/)
  if (!match) return null
  const z = Number(match[1]), x = Number(match[2]), y = Number(match[3])
  const count = Math.pow(2, z)
  if (!Number.isInteger(z) || z < 7 || z > 18 || x < 0 || y < 0 || x >= count || y >= count) return null
  return isScoutSandboxRasterTileAllowed(z, x, y) ? { z, x, y } : null
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
