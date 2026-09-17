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

function headers(origin = ''): Record<string, string> {
  const out: Record<string, string> = {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store, max-age=0',
    'pragma': 'no-cache',
    'referrer-policy': 'no-referrer',
    'x-content-type-options': 'nosniff',
  }
  if (ALLOWED_ORIGINS.has(origin)) {
    out['access-control-allow-origin'] = origin
    out['vary'] = 'Origin'
    out['access-control-allow-headers'] = 'authorization, content-type, apikey'
    out['access-control-allow-methods'] = 'GET, OPTIONS'
  }
  return out
}

function json(body: unknown, status = 200, origin = '') {
  return new Response(JSON.stringify(body), { status, headers: headers(origin) })
}

function bearer(req: Request): string | null {
  const value = req.headers.get('authorization') || ''
  const match = /^Bearer\s+(.+)$/i.exec(value)
  return match?.[1]?.trim() || null
}

function boundedSlug(value: string | null): string | null {
  if (!value) return 'flat-creek-test'
  const normalized = value.trim().toLowerCase()
  return /^[a-z0-9][a-z0-9-]{0,79}$/.test(normalized) ? normalized : null
}

type Center = { lat: number; lon: number; basis: string; matched_address?: string }

async function censusCenter(address: string): Promise<Center | null> {
  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), 6000)
  try {
    const url = new URL('https://geocoding.geo.census.gov/geocoder/locations/onelineaddress')
    url.searchParams.set('address', address)
    url.searchParams.set('benchmark', 'Public_AR_Current')
    url.searchParams.set('format', 'json')
    const response = await fetch(url, {
      signal: controller.signal,
      headers: {
        'accept': 'application/json',
        'user-agent': 'Cadastory-Farm-Watch/0.1 (https://pmicka.com)',
      },
    })
    if (!response.ok) return null
    const payload = await response.json()
    const match = payload?.result?.addressMatches?.[0]
    const x = Number(match?.coordinates?.x)
    const y = Number(match?.coordinates?.y)
    if (!Number.isFinite(x) || !Number.isFinite(y)) return null
    return {
      lat: y,
      lon: x,
      basis: 'US Census Geocoder address match',
      ...(typeof match?.matchedAddress === 'string' ? { matched_address: match.matchedAddress } : {}),
    }
  } catch {
    return null
  } finally {
    clearTimeout(timeout)
  }
}

function storedCenter(property: any): Center | null {
  const coords = property?.center_geojson?.coordinates
  if (!Array.isArray(coords) || coords.length < 2) return null
  const lon = Number(coords[0])
  const lat = Number(coords[1])
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) return null
  return { lat, lon, basis: 'stored property center' }
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get('origin') || ''
  if (origin && !ALLOWED_ORIGINS.has(origin)) return json({ error: 'not found' }, 404)
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: headers(origin) })
  if (req.method !== 'GET') return json({ error: 'not found' }, 404, origin)

  const token = bearer(req)
  if (!token) return json({ error: 'not found' }, 404, origin)

  const { data: userData, error: userError } = await admin.auth.getUser(token)
  const user = userData?.user
  if (userError || !user) return json({ error: 'not found' }, 404, origin)

  const { data: allowed, error: accessError } = await admin.rpc('farm_watch_authorize_user_v1_internal', {
    p_user_id: user.id,
  })
  if (accessError || allowed !== true) return json({ error: 'not found' }, 404, origin)

  const requestUrl = new URL(req.url)
  const slug = boundedSlug(requestUrl.searchParams.get('property'))
  if (!slug) return json({ error: 'invalid property selector' }, 400, origin)

  const { data: property, error: propertyError } = await admin.rpc('farm_watch_get_property_v1_internal', {
    p_slug: slug,
  })
  if (propertyError) {
    console.error('farm_watch_get_property_v1_internal failed', propertyError.message)
    return json({ error: 'property unavailable' }, 503, origin)
  }
  if (!property) return json({ error: 'not found' }, 404, origin)

  let center = storedCenter(property)
  if (!center) {
    const address = [property.street_address, property.city, property.state_code, property.postal_code]
      .filter((part) => typeof part === 'string' && part.trim())
      .join(', ')
    if (address) center = await censusCenter(address)
  }

  return json({
    property: {
      id: property.id,
      slug: property.slug,
      display_name: property.display_name,
      address: [property.street_address, property.city, property.state_code, property.postal_code]
        .filter((part) => typeof part === 'string' && part.trim())
        .join(', '),
      stated_acres: property.stated_acres,
      center,
      boundary_geojson: property.boundary_geojson,
      metadata: property.metadata,
      updated_at: property.updated_at,
    },
    access: { scope: 'owner_only' },
  }, 200, origin)
})
