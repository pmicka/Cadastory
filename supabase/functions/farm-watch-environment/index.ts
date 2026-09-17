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
const HISTORICAL_CACHE_TTL_MS = 180 * 24 * 60 * 60 * 1000
const DAYMET_TIMEOUT_MS = 12000
const USGS_TIMEOUT_MS = 9000
const CENSUS_TIMEOUT_MS = 7000
const USDM_TIMEOUT_MS = 9000
const MM_PER_INCH = 25.4

type Anchor = {
  property_id?: string
  lat?: number
  lon?: number
  state_code?: string | null
  postal_code?: string | null
  county_fips?: string | null
  nearest_gauge?: {
    gauge_id?: string | null
    name?: string | null
    distance_m?: number | null
  } | null
}

type DaymetRow = {
  date: string
  precipMm: number
  tmaxC: number | null
  tminC: number | null
}

function headers(origin = ''): Record<string, string> {
  const out: Record<string, string> = {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store, max-age=0',
    pragma: 'no-cache',
    'referrer-policy': 'no-referrer',
    'x-content-type-options': 'nosniff',
  }
  if (ALLOWED_ORIGINS.has(origin)) {
    out['access-control-allow-origin'] = origin
    out.vary = 'Origin'
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
  if (!value) return DEFAULT_PROPERTY_SLUG
  const normalized = value.trim().toLowerCase()
  return /^[a-z0-9][a-z0-9-]{0,79}$/.test(normalized) ? normalized : null
}

function parseDate(value: string | null): Date | null {
  if (!value || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return null
  const date = new Date(`${value}T00:00:00Z`)
  if (!Number.isFinite(date.getTime()) || date.toISOString().slice(0, 10) !== value) return null
  return date
}

function isoDate(date: Date) {
  return date.toISOString().slice(0, 10)
}

function addDays(date: Date, days: number) {
  const next = new Date(date.getTime())
  next.setUTCDate(next.getUTCDate() + days)
  return next
}

async function fetchText(url: string, timeoutMs: number, accept: string) {
  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), timeoutMs)
  try {
    const response = await fetch(url, {
      signal: controller.signal,
      headers: {
        accept,
        'user-agent': 'Cadastory-Farm-Watch/0.3 (https://pmicka.com)',
      },
    })
    if (!response.ok) throw new Error(`source returned ${response.status}`)
    return await response.text()
  } finally {
    clearTimeout(timeout)
  }
}

function parseCsvLine(line: string) {
  const values: string[] = []
  let current = ''
  let quoted = false
  for (let i = 0; i < line.length; i += 1) {
    const char = line[i]
    if (char === '"') {
      if (quoted && line[i + 1] === '"') {
        current += '"'
        i += 1
      } else {
        quoted = !quoted
      }
    } else if (char === ',' && !quoted) {
      values.push(current.trim())
      current = ''
    } else {
      current += char
    }
  }
  values.push(current.trim())
  return values
}

function parseDaymet(text: string): DaymetRow[] {
  const lines = text.split(/\r?\n/).map((line) => line.trim()).filter(Boolean)
  const headerIndex = lines.findIndex((line) => /^year,yday,/i.test(line))
  if (headerIndex < 0) throw new Error('Daymet response did not contain daily data')
  const header = parseCsvLine(lines[headerIndex])
  const yearIndex = header.findIndex((value) => value.toLowerCase() === 'year')
  const dayIndex = header.findIndex((value) => value.toLowerCase() === 'yday')
  const precipIndex = header.findIndex((value) => value.toLowerCase().startsWith('prcp'))
  const tmaxIndex = header.findIndex((value) => value.toLowerCase().startsWith('tmax'))
  const tminIndex = header.findIndex((value) => value.toLowerCase().startsWith('tmin'))
  if ([yearIndex, dayIndex, precipIndex].some((index) => index < 0)) throw new Error('Daymet response fields are incomplete')

  const rows: DaymetRow[] = []
  for (const line of lines.slice(headerIndex + 1)) {
    const values = parseCsvLine(line)
    const year = Number(values[yearIndex])
    const yday = Number(values[dayIndex])
    const precipMm = Number(values[precipIndex])
    if (!Number.isInteger(year) || !Number.isInteger(yday) || !Number.isFinite(precipMm)) continue
    const date = new Date(Date.UTC(year, 0, 1))
    date.setUTCDate(yday)
    const tmax = tmaxIndex >= 0 ? Number(values[tmaxIndex]) : NaN
    const tmin = tminIndex >= 0 ? Number(values[tminIndex]) : NaN
    rows.push({
      date: isoDate(date),
      precipMm,
      tmaxC: Number.isFinite(tmax) ? tmax : null,
      tminC: Number.isFinite(tmin) ? tmin : null,
    })
  }
  return rows
}

function summarizeDaymet(rows: DaymetRow[], contextDate: Date) {
  const end = contextDate.getTime()
  const windows = [1, 3, 7, 14, 30, 90]
  const precipitation: Record<string, number | null> = {}
  for (const days of windows) {
    const start = addDays(contextDate, -(days - 1)).getTime()
    const inWindow = rows.filter((row) => {
      const time = Date.parse(`${row.date}T00:00:00Z`)
      return time >= start && time <= end
    })
    precipitation[`${days}d_in`] = inWindow.length
      ? Number((inWindow.reduce((sum, row) => sum + row.precipMm, 0) / MM_PER_INCH).toFixed(3))
      : null
  }

  const today = rows.find((row) => row.date === isoDate(contextDate)) || null
  return {
    source: 'NASA ORNL Daymet v4',
    source_class: 'modeled_environmental',
    spatial_resolution: '1 km grid',
    modeled_not_measured: true,
    precipitation,
    on_date: today ? {
      tmin_c: today.tminC,
      tmax_c: today.tmaxC,
      tmin_f: today.tminC === null ? null : Number((today.tminC * 9 / 5 + 32).toFixed(1)),
      tmax_f: today.tmaxC === null ? null : Number((today.tmaxC * 9 / 5 + 32).toFixed(1)),
      precip_in: Number((today.precipMm / MM_PER_INCH).toFixed(3)),
    } : null,
    first_date: rows[0]?.date || null,
    last_date: rows.at(-1)?.date || null,
  }
}

async function fetchDaymet(anchor: Anchor, contextDate: Date) {
  const lat = Number(anchor.lat)
  const lon = Number(anchor.lon)
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) throw new Error('property environmental anchor is unavailable')
  const start = isoDate(addDays(contextDate, -89))
  const end = isoDate(contextDate)
  const url = new URL('https://daymet.ornl.gov/single-pixel/api/data')
  url.searchParams.set('lat', String(lat))
  url.searchParams.set('lon', String(lon))
  url.searchParams.set('vars', 'prcp,tmin,tmax')
  url.searchParams.set('start', start)
  url.searchParams.set('end', end)
  const text = await fetchText(url.toString(), DAYMET_TIMEOUT_MS, 'text/csv,text/plain')
  const rows = parseDaymet(text)
  if (!rows.length) throw new Error('Daymet returned no historical rows')
  return summarizeDaymet(rows, contextDate)
}

async function fetchUsgs(anchor: Anchor, contextDate: Date) {
  const gauge = anchor.nearest_gauge
  const gaugeId = gauge?.gauge_id
  if (!gaugeId) throw new Error('nearest USGS gauge is unavailable')
  const url = new URL('https://api.waterdata.usgs.gov/ogcapi/v1/collections/daily/items')
  url.searchParams.set('f', 'json')
  url.searchParams.set('monitoring_location_id', gaugeId)
  url.searchParams.set('parameter_code', '00060')
  url.searchParams.set('statistic_id', '00003')
  url.searchParams.set('time', isoDate(contextDate))
  const payload = JSON.parse(await fetchText(url.toString(), USGS_TIMEOUT_MS, 'application/geo+json,application/json'))
  const feature = Array.isArray(payload?.features) ? payload.features[0] : null
  const properties = feature?.properties || {}
  const value = Number(properties.value)
  if (!feature || !Number.isFinite(value)) throw new Error('USGS daily discharge is unavailable for this date')
  return {
    source: 'USGS Water Data API',
    gauge_id: gaugeId,
    gauge_name: gauge?.name || null,
    distance_m: Number.isFinite(Number(gauge?.distance_m)) ? Number(gauge?.distance_m) : null,
    parameter: 'Daily mean discharge',
    discharge_cfs: value,
    approval_status: properties.approval_status || null,
    qualifier: properties.qualifier || null,
    observed_date: properties.time || isoDate(contextDate),
  }
}

async function resolveCounty(anchor: Anchor) {
  if (anchor.county_fips && /^\d{5}$/.test(anchor.county_fips)) {
    return { fips: anchor.county_fips, name: null }
  }
  const lat = Number(anchor.lat)
  const lon = Number(anchor.lon)
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) throw new Error('property coordinates are unavailable')
  const url = new URL('https://geocoding.geo.census.gov/geocoder/geographies/coordinates')
  url.searchParams.set('x', String(lon))
  url.searchParams.set('y', String(lat))
  url.searchParams.set('benchmark', 'Public_AR_Current')
  url.searchParams.set('vintage', 'Current_Current')
  url.searchParams.set('format', 'json')
  const payload = JSON.parse(await fetchText(url.toString(), CENSUS_TIMEOUT_MS, 'application/json'))
  const county = payload?.result?.geographies?.Counties?.[0]
  const fips = String(county?.GEOID || '')
  if (!/^\d{5}$/.test(fips)) throw new Error('county FIPS could not be resolved')
  return { fips, name: county?.NAME || null }
}

function mdy(date: Date) {
  return `${date.getUTCMonth() + 1}/${date.getUTCDate()}/${date.getUTCFullYear()}`
}

async function fetchUsdm(anchor: Anchor, contextDate: Date) {
  const county = await resolveCounty(anchor)
  const start = addDays(contextDate, -7)
  const url = new URL('https://usdmdataservices.unl.edu/api/CountyStatistics/GetDroughtSeverityStatisticsByAreaPercent')
  url.searchParams.set('aoi', county.fips)
  url.searchParams.set('startdate', mdy(start))
  url.searchParams.set('enddate', mdy(contextDate))
  url.searchParams.set('statisticsType', '1')
  const text = await fetchText(url.toString(), USDM_TIMEOUT_MS, 'text/csv,text/plain')
  const lines = text.split(/\r?\n/).map((line) => line.trim()).filter(Boolean)
  if (lines.length < 2) throw new Error('USDM returned no county statistics')
  const header = parseCsvLine(lines[0])
  const records = lines.slice(1).map((line) => {
    const values = parseCsvLine(line)
    return Object.fromEntries(header.map((key, index) => [key, values[index] ?? '']))
  })
  const targetIso = isoDate(contextDate)
  const selected = records.find((record) => record.ValidStart <= targetIso && record.ValidEnd >= targetIso)
    || records.find((record) => String(record.MapDate || '').slice(0, 8) <= targetIso.replaceAll('-', ''))
    || records[0]
  if (!selected) throw new Error('USDM weekly context is unavailable')

  const pct = (key: string) => {
    const value = Number(selected[key])
    return Number.isFinite(value) ? value : null
  }
  return {
    source: 'U.S. Drought Monitor',
    scope: 'county_weekly',
    property_classification: false,
    county_fips: selected.FIPS || county.fips,
    county: selected.County || county.name,
    state: selected.State || anchor.state_code || null,
    map_date: selected.MapDate ? `${String(selected.MapDate).slice(0, 4)}-${String(selected.MapDate).slice(4, 6)}-${String(selected.MapDate).slice(6, 8)}` : null,
    valid_start: selected.ValidStart || null,
    valid_end: selected.ValidEnd || null,
    percent_area: {
      none: pct('None'),
      d0_plus: pct('D0'),
      d1_plus: pct('D1'),
      d2_plus: pct('D2'),
      d3_plus: pct('D3'),
      d4: pct('D4'),
    },
  }
}

async function fetchFreshContext(slug: string, anchor: Anchor, contextDate: Date) {
  const [daymet, usgs, usdm] = await Promise.allSettled([
    fetchDaymet(anchor, contextDate),
    fetchUsgs(anchor, contextDate),
    fetchUsdm(anchor, contextDate),
  ])

  const context: Record<string, unknown> = {
    context_date: isoDate(contextDate),
    daymet: daymet.status === 'fulfilled'
      ? daymet.value
      : { status: 'unavailable', error: daymet.reason instanceof Error ? daymet.reason.message : 'Daymet unavailable' },
    stream: usgs.status === 'fulfilled'
      ? usgs.value
      : { status: 'unavailable', error: usgs.reason instanceof Error ? usgs.reason.message : 'USGS daily values unavailable' },
    drought: usdm.status === 'fulfilled'
      ? usdm.value
      : { status: 'unavailable', error: usdm.reason instanceof Error ? usdm.reason.message : 'USDM unavailable' },
    soil_moisture: {
      status: 'unavailable',
      reason: 'No historical root-zone soil-moisture source is currently resolved at a defensible property scale for this acquisition date.',
    },
    provenance: {
      imagery_pixels_analyzed: false,
      imagery_inference_performed: false,
    },
  }

  const successes = [daymet, usgs, usdm].filter((result) => result.status === 'fulfilled').length
  const status = successes >= 2 ? 'available' : successes >= 1 ? 'partial' : 'unavailable'
  const retrievedAt = new Date().toISOString()
  const { error } = await admin.rpc('farm_watch_upsert_environment_context_v1_internal', {
    p_slug: slug,
    p_context_date: isoDate(contextDate),
    p_status: status,
    p_context: context,
    p_retrieved_at: retrievedAt,
  })
  if (error) console.error('Farm Watch environment cache write failed', error.message)
  return { status, context, retrieved_at: retrievedAt, cache: 'miss' }
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
  const contextDate = parseDate(requestUrl.searchParams.get('date'))
  if (!slug || !contextDate) return json({ error: 'invalid request' }, 400, origin)
  if (contextDate < new Date('1980-01-01T00:00:00Z') || contextDate > addDays(new Date(), 1)) {
    return json({ error: 'context date is outside supported range' }, 400, origin)
  }

  const { data: cached, error: cacheError } = await admin.rpc('farm_watch_get_environment_context_v1_internal', {
    p_slug: slug,
    p_context_date: isoDate(contextDate),
  })
  if (cacheError) console.error('Farm Watch environment cache read failed', cacheError.message)
  const cachedAt = Date.parse(cached?.retrieved_at || '')
  if (cached?.context && Number.isFinite(cachedAt) && Date.now() - cachedAt < HISTORICAL_CACHE_TTL_MS) {
    return json({
      context_date: isoDate(contextDate),
      status: cached.status || 'partial',
      context: cached.context,
      retrieved_at: cached.retrieved_at,
      cache: 'hit',
    }, 200, origin)
  }

  const { data: anchor, error: anchorError } = await admin.rpc('farm_watch_get_environment_anchor_v1_internal', {
    p_slug: slug,
  })
  if (anchorError) {
    console.error('farm_watch_get_environment_anchor_v1_internal failed', anchorError.message)
    return json({ error: 'environment context unavailable' }, 503, origin)
  }
  if (!anchor || !Number.isFinite(Number(anchor.lat)) || !Number.isFinite(Number(anchor.lon))) {
    return json({ error: 'property environmental anchor unavailable' }, 503, origin)
  }

  try {
    return json(await fetchFreshContext(slug, anchor as Anchor, contextDate), 200, origin)
  } catch (error) {
    console.error('Farm Watch environment refresh failed', error instanceof Error ? error.message : error)
    return json({ error: 'environment context unavailable' }, 503, origin)
  }
})
