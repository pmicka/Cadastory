import 'jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.115.0'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
let SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
try {
  const keys = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') || '{}')
  SERVICE_KEY = keys.default || SERVICE_KEY
} catch { /* legacy fallback */ }
if (!SERVICE_KEY) throw new Error('Farm Watch service credential is unavailable')

const admin = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
})

const ALLOWED_ORIGINS = new Set([
  'https://pmicka.com',
  'https://www.pmicka.com',
  'http://127.0.0.1:8000',
  'http://localhost:8000',
])
const DEFAULT_PROPERTY_SLUG = 'validation-property-01'
const CACHE_TTL_MS = 30 * 24 * 60 * 60 * 1000
const SOURCE_TIMEOUT_MS = 12000

const SOURCES = {
  geology: 'https://kgs.uky.edu/arcgis/rest/services/GeologicMapData/KY24KGeologicFormations_WGS84/MapServer/0',
  lithology: 'https://kgs.uky.edu/arcgis/rest/services/GeologicMapData/KY24KLitho_WGS84/MapServer/0',
  sinkholes: 'https://kgs.uky.edu/arcgis/rest/services/KYWater/KYSinkholes/MapServer/0',
  huc: 'https://kygisserver.ky.gov/arcgis/rest/services/WGS84WM_Services/Ky_8_10_12_Digit_Hydrologic_Units_WGS84WM/MapServer/0',
}

type Json = Record<string, any>
type Anchor = {
  property_id?: string
  stated_acres?: number | null
  lat?: number
  lon?: number
  boundary_geojson?: Json | null
}

function responseHeaders(origin = ''): Record<string, string> {
  const headers: Record<string, string> = {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store, max-age=0',
    pragma: 'no-cache',
    'referrer-policy': 'no-referrer',
    'x-content-type-options': 'nosniff',
  }
  if (ALLOWED_ORIGINS.has(origin)) {
    headers['access-control-allow-origin'] = origin
    headers.vary = 'Origin'
    headers['access-control-allow-headers'] = 'authorization, content-type, apikey'
    headers['access-control-allow-methods'] = 'GET, OPTIONS'
  }
  return headers
}

function json(body: unknown, status = 200, origin = '') {
  return new Response(JSON.stringify(body), { status, headers: responseHeaders(origin) })
}

function bearer(req: Request): string | null {
  const match = /^Bearer\s+(.+)$/i.exec(req.headers.get('authorization') || '')
  return match?.[1]?.trim() || null
}

function boundedSlug(value: string | null): string | null {
  if (!value) return DEFAULT_PROPERTY_SLUG
  const normalized = value.trim().toLowerCase()
  return /^[a-z0-9][a-z0-9-]{0,79}$/.test(normalized) ? normalized : null
}

async function fetchJson(url: string, timeoutMs = SOURCE_TIMEOUT_MS) {
  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), timeoutMs)
  try {
    const response = await fetch(url, {
      signal: controller.signal,
      headers: {
        accept: 'application/json, application/geo+json, */*',
        'user-agent': 'Cadastory-Farm-Watch/0.5 (https://pmicka.com)',
      },
    })
    const text = await response.text()
    if (!response.ok) throw new Error(`source returned ${response.status}`)
    try { return JSON.parse(text) } catch { throw new Error('source returned non-JSON content') }
  } finally {
    clearTimeout(timeout)
  }
}

function geojsonToEsriPolygon(geometry: Json | null | undefined) {
  if (!geometry) return null
  const rings: any[] = []
  if (geometry.type === 'Polygon') rings.push(...(geometry.coordinates || []))
  if (geometry.type === 'MultiPolygon') {
    for (const polygon of geometry.coordinates || []) rings.push(...polygon)
  }
  return rings.length ? { rings, spatialReference: { wkid: 4326 } } : null
}

function value(props: Json, ...keys: string[]) {
  const entries = Object.entries(props || {})
  for (const key of keys) {
    const found = entries.find(([candidate]) => candidate.toLowerCase() === key.toLowerCase())
    if (found) return found[1]
  }
  return null
}

async function arcgisPolygon(base: string, polygon: Json, outFields: string) {
  const url = new URL(`${base.replace(/\/$/, '')}/query`)
  for (const [key, val] of Object.entries({
    f: 'geojson',
    where: '1=1',
    geometry: JSON.stringify(polygon),
    geometryType: 'esriGeometryPolygon',
    inSR: '4326',
    spatialRel: 'esriSpatialRelIntersects',
    outFields,
    returnGeometry: 'true',
    outSR: '4326',
  })) url.searchParams.set(key, val)
  const payload = await fetchJson(url.toString())
  if (payload?.error) throw new Error(payload.error.message || 'ArcGIS polygon query failed')
  if (!Array.isArray(payload?.features)) throw new Error('ArcGIS response did not contain features')
  return payload
}

async function arcgisNearby(base: string, lat: number, lon: number, meters: number, outFields: string) {
  const url = new URL(`${base.replace(/\/$/, '')}/query`)
  for (const [key, val] of Object.entries({
    f: 'geojson',
    where: '1=1',
    geometry: `${lon},${lat}`,
    geometryType: 'esriGeometryPoint',
    inSR: '4326',
    spatialRel: 'esriSpatialRelIntersects',
    distance: String(meters),
    units: 'esriSRUnit_Meter',
    outFields,
    returnGeometry: 'true',
    outSR: '4326',
  })) url.searchParams.set(key, val)
  const payload = await fetchJson(url.toString())
  if (payload?.error) throw new Error(payload.error.message || 'ArcGIS nearby query failed')
  if (!Array.isArray(payload?.features)) throw new Error('ArcGIS response did not contain features')
  return payload
}

function normalizeGeology(payload: Json, lithologyPayload: Json | null) {
  const lithologyByCode = new Map<string, string>()
  for (const feature of lithologyPayload?.features || []) {
    const props = feature?.properties || {}
    const code = String(value(props, 'formation_code') || '').trim()
    const lith = String(value(props, 'KLitho_txt_DOMINANT_LITHOLOGY', 'dominant_lithology') || '').trim()
    if (code && lith) lithologyByCode.set(code, lith)
  }
  return {
    type: 'FeatureCollection',
    features: (payload?.features || []).map((feature: Json) => {
      const props = feature?.properties || {}
      const formationCode = String(value(props, 'formation_code') || '').trim()
      return {
        type: 'Feature',
        geometry: feature.geometry,
        properties: {
          map_symbol: value(props, 'map_symbol'),
          formation_code: formationCode || null,
          formation_name: value(props, 'formation_name'),
          dominant_lithology: lithologyByCode.get(formationCode) || null,
          maximum_age: value(props, 'maximum_age'),
          minimum_age: value(props, 'minimum_age'),
          quadrangle_name: value(props, 'quadrangle_name'),
          description: value(props, 'description'),
          source_name: value(props, 'sourceName', 'source_name'),
          source_uri: value(props, 'source_uri'),
        },
      }
    }),
  }
}

function normalizeHuc(payload: Json) {
  return {
    type: 'FeatureCollection',
    features: (payload?.features || []).map((feature: Json) => {
      const props = feature?.properties || {}
      return {
        type: 'Feature',
        geometry: feature.geometry,
        properties: {
          huc12: value(props, 'HUC12', 'huc12'),
          name: value(props, 'Name', 'name'),
          hu_type: value(props, 'HUType', 'hutype'),
          hu_mod: value(props, 'HUMod', 'humod'),
          to_huc: value(props, 'ToHUC', 'tohuc'),
          area_acres: value(props, 'AreaAcres', 'areaacres'),
        },
      }
    }),
  }
}

function normalizeSinkholes(payload: Json) {
  return {
    type: 'FeatureCollection',
    features: (payload?.features || []).map((feature: Json) => {
      const props = feature?.properties || {}
      return {
        type: 'Feature',
        geometry: feature.geometry,
        properties: {
          objectid: value(props, 'ObjectID', 'objectid'),
          county_name: value(props, 'county_name'),
          quadrangle_name: value(props, 'quadrangle_name'),
          mapped_acres: value(props, 'Acres', 'acres'),
        },
      }
    }),
  }
}

async function refresh(slug: string, anchor: Anchor) {
  const polygon = geojsonToEsriPolygon(anchor.boundary_geojson)
  const lat = Number(anchor.lat)
  const lon = Number(anchor.lon)
  if (!polygon || !Number.isFinite(lat) || !Number.isFinite(lon)) {
    throw new Error('selected parcel geometry is unavailable')
  }

  const results = await Promise.allSettled([
    arcgisPolygon(SOURCES.geology, polygon, 'map_symbol,formation_code,formation_name,maximum_age,minimum_age,quadrangle_name,description,sourceName,source_uri'),
    arcgisPolygon(SOURCES.lithology, polygon, 'formation_code,KLitho_txt_DOMINANT_LITHOLOGY'),
    arcgisPolygon(SOURCES.huc, polygon, 'HUC12,Name,HUType,HUMod,ToHUC,AreaAcres'),
    arcgisNearby(SOURCES.sinkholes, lat, lon, 10000, 'county_name,quadrangle_name,Acres,ObjectID'),
  ])

  const names = ['geology', 'lithology', 'watershed', 'sinkholes']
  const sourceStatus: Record<string, string> = {}
  const sourceErrors: Record<string, string> = {}
  const payloads: Array<Json | null> = results.map((result, index) => {
    const name = names[index]
    if (result.status === 'fulfilled') {
      sourceStatus[name] = 'available'
      return result.value as Json
    }
    sourceStatus[name] = 'unavailable'
    sourceErrors[name] = result.reason instanceof Error ? result.reason.message : String(result.reason)
    return null
  })

  const geology = payloads[0] ? normalizeGeology(payloads[0]!, payloads[1]) : { type: 'FeatureCollection', features: [] }
  const huc = payloads[2] ? normalizeHuc(payloads[2]!) : { type: 'FeatureCollection', features: [] }
  const sinkholes = payloads[3] ? normalizeSinkholes(payloads[3]!) : { type: 'FeatureCollection', features: [] }

  const { data: computed, error: computeError } = await admin.rpc('farm_watch_compute_land_context_v1_internal', {
    p_slug: slug,
    p_geology: geology,
    p_huc: huc,
    p_sinkholes: sinkholes,
  })
  if (computeError || !computed) throw new Error(computeError?.message || 'land geometry computation failed')

  const retrievedAt = new Date().toISOString()
  const context = {
    ...computed,
    retrieved_at: retrievedAt,
    source_status: sourceStatus,
    source_errors: sourceErrors,
    provenance: {
      geology: {
        authority: 'Kentucky Geological Survey',
        scale: '1:24,000',
        source: 'digitized KGS/USGS 7.5-minute geologic quadrangle mapping',
        meaning: 'mapped bedrock geology; not a site boring or geotechnical investigation',
      },
      lithology: {
        authority: 'Kentucky Geological Survey',
        meaning: 'KGS-derived dominant lithology attribute from mapped geologic formations; not a field sample',
      },
      sinkholes: {
        authority: 'Kentucky Geological Survey',
        meaning: 'mapped closed topographic depressions digitized from 7.5-minute topographic contours; mapped absence is not proof of physical absence',
      },
      watershed: {
        authority: 'USGS / Kentucky Division of Water',
        meaning: 'Watershed Boundary Dataset hydrologic unit boundaries for water-resource management and localized studies',
      },
      faults_in_primary_view: false,
      karst_potential_used: false,
      financial_context_included: false,
      ownership_context_included: false,
      imagery_pixels_analyzed: false,
    },
  }

  const availableCount = Object.values(sourceStatus).filter((status) => status === 'available').length
  const status = availableCount === names.length ? 'available' : availableCount > 0 ? 'partial' : 'unavailable'
  await admin.rpc('farm_watch_upsert_land_context_v1_internal', {
    p_slug: slug,
    p_status: status,
    p_context: context,
    p_retrieved_at: retrievedAt,
  })
  return { status, context, retrieved_at: retrievedAt, cache: 'miss' }
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get('origin') || ''
  if (origin && !ALLOWED_ORIGINS.has(origin)) return json({ error: 'not found' }, 404)
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: responseHeaders(origin) })
  if (req.method !== 'GET') return json({ error: 'not found' }, 404, origin)

  const token = bearer(req)
  if (!token) return json({ error: 'not found' }, 404, origin)
  const { data: userData, error: userError } = await admin.auth.getUser(token)
  const user = userData?.user
  if (userError || !user) return json({ error: 'not found' }, 404, origin)
  const { data: allowed, error: accessError } = await admin.rpc('farm_watch_authorize_user_v1_internal', { p_user_id: user.id })
  if (accessError || allowed !== true) return json({ error: 'not found' }, 404, origin)

  const url = new URL(req.url)
  const slug = boundedSlug(url.searchParams.get('property'))
  if (!slug) return json({ error: 'invalid request' }, 400, origin)

  const { data: anchor, error: anchorError } = await admin.rpc('farm_watch_get_land_anchor_v1_internal', { p_slug: slug })
  if (anchorError || !anchor?.property_id) return json({ error: 'land context unavailable' }, 503, origin)

  const { data: cached } = await admin.rpc('farm_watch_get_land_context_v1_internal', { p_slug: slug })
  const cachedAt = Date.parse(cached?.retrieved_at || '')
  let result: any

  if (cached?.context && Number.isFinite(cachedAt) && Date.now() - cachedAt < CACHE_TTL_MS) {
    result = {
      status: cached.status || 'unknown',
      context: cached.context,
      retrieved_at: cached.retrieved_at,
      cache: 'hit',
    }
  } else {
    try {
      result = await refresh(slug, anchor as Anchor)
    } catch (error) {
      result = {
        status: cached?.status || 'unavailable',
        context: cached?.context || {},
        retrieved_at: cached?.retrieved_at || null,
        cache: cached?.context ? 'stale' : 'miss',
        error: error instanceof Error ? error.message : String(error),
      }
    }
  }

  return json({
    property: { slug },
    land: result,
    product_boundaries: {
      faults_in_primary_view: false,
      karst_potential_used: false,
      financial_context_included: false,
      ownership_context_included: false,
      imagery_analysis_performed: false,
    },
  }, 200, origin)
})
