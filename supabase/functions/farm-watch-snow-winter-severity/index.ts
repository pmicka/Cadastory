import 'jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.115.0'
import {
  FARM_WATCH_SNOW_WINTER_SEVERITY_PRODUCT,
  validateFarmWatchSnowWinterSeverityContext,
} from '../_shared/farm-watch-snow-winter-severity-contract.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
let SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
try {
  const keys = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') || '{}')
  SERVICE_KEY = keys.default || SERVICE_KEY
} catch { /* legacy fallback */ }
if (!SERVICE_KEY) throw new Error('Farm Watch service credential is unavailable')

const admin: any = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
})

const SOURCE_URL =
  'https://mapservices.weather.noaa.gov/raster/rest/services/snow/NOHRSC_Snow_Analysis/MapServer/identify'
const SOURCE_TIMEOUT_MS = 20_000

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store, max-age=0',
      pragma: 'no-cache',
      'referrer-policy': 'no-referrer',
      'x-content-type-options': 'nosniff',
    },
  })
}

function boundedSlug(value: unknown) {
  const normalized = String(value || '').trim().toLowerCase()
  return /^[a-z0-9][a-z0-9-]{0,79}$/.test(normalized) ? normalized : null
}

async function sha256Hex(value: string) {
  const digest = new Uint8Array(
    await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value)),
  )
  return [...digest].map((byte) => byte.toString(16).padStart(2, '0')).join('')
}

function parseNoaaArcgisUtc(value: unknown) {
  const match = /^(\d{1,2})\/(\d{1,2})\/(\d{4})\s+(\d{1,2}):(\d{2}):(\d{2})\s+(AM|PM)$/i.exec(
    String(value || '').trim(),
  )
  if (!match) throw new Error('NOHRSC source timestamp is unavailable')
  let hour = Number(match[4])
  const marker = match[7].toUpperCase()
  if (hour === 12) hour = 0
  if (marker === 'PM') hour += 12
  const date = new Date(Date.UTC(
    Number(match[3]), Number(match[1]) - 1, Number(match[2]),
    hour, Number(match[5]), Number(match[6]),
  ))
  if (!Number.isFinite(date.getTime())) throw new Error('NOHRSC source timestamp is invalid')
  return date
}

function localIsoDate(date: Date, timeZone: string) {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(date)
  const byType = Object.fromEntries(parts.map((part) => [part.type, part.value]))
  if (!byType.year || !byType.month || !byType.day) throw new Error('property local date is unavailable')
  return byType.year + '-' + byType.month + '-' + byType.day
}

function identifyUrl(target: any) {
  const lon = Number(target?.longitude)
  const lat = Number(target?.latitude)
  if (!Number.isFinite(lon) || !Number.isFinite(lat)) throw new Error('snow target coordinates unavailable')

  const url = new URL(SOURCE_URL)
  url.searchParams.set('geometry', lon + ',' + lat)
  url.searchParams.set('geometryType', 'esriGeometryPoint')
  url.searchParams.set('sr', '4326')
  url.searchParams.set('layers', 'all:0')
  url.searchParams.set('tolerance', '2')
  url.searchParams.set('mapExtent', [lon - 0.1, lat - 0.1, lon + 0.1, lat + 0.1].join(','))
  url.searchParams.set('imageDisplay', '800,800,96')
  url.searchParams.set('returnGeometry', 'false')
  url.searchParams.set('f', 'json')
  return url.toString()
}

async function fetchNohrsc(target: any) {
  const response = await fetch(identifyUrl(target), {
    headers: {
      accept: 'application/json',
      'user-agent': 'Scout-by-Cadastory/1.0 (Farm Watch snow winter severity)',
    },
    signal: AbortSignal.timeout(SOURCE_TIMEOUT_MS),
  })
  const text = await response.text()
  if (!response.ok) throw new Error('NOHRSC snow service returned HTTP ' + response.status)
  let payload: any
  try {
    payload = JSON.parse(text)
  } catch {
    throw new Error('NOHRSC snow service returned non-JSON content')
  }
  if (payload?.error) throw new Error(payload.error?.message || 'NOHRSC snow service returned an error')
  const results = Array.isArray(payload?.results) ? payload.results : []
  const image = results.find((row: any) => row?.layerName === 'Image' || row?.layerId === 3)
  const footprint = results.find((row: any) => row?.layerName === 'Footprint' || row?.layerId === 2)
  const pixel = Number(image?.attributes?.['Service Pixel Value'])
  if (!Number.isFinite(pixel) || pixel < 0 || pixel > 2000) {
    throw new Error('NOHRSC snow depth pixel is unavailable')
  }
  const sourceValidAt = parseNoaaArcgisUtc(
    image?.attributes?.idp_validtime || footprint?.attributes?.idp_validtime,
  )
  const sourceIngestedRaw = image?.attributes?.idp_ingestdate || footprint?.attributes?.idp_ingestdate
  const sourceIngestedAt = sourceIngestedRaw ? parseNoaaArcgisUtc(sourceIngestedRaw) : null
  const sourceObject = String(image?.attributes?.name || footprint?.attributes?.name || '').trim() || null
  return {
    rawText: text,
    snowDepthCm: pixel,
    sourceValidAt,
    sourceIngestedAt,
    sourceObject,
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return json({ error: 'not found' }, 404)
  try {
    const body = await req.json().catch(() => ({}))
    const slug = boundedSlug(body?.property || 'validation-property-01')
    if (!slug) return json({ error: 'invalid request' }, 400)

    const workerToken = typeof body?.worker_token === 'string' ? body.worker_token : null
    const { data: workerAllowed, error: workerError } = await admin.rpc(
      'farm_watch_validate_materialization_worker_v1_internal',
      { p_token: workerToken },
    )
    if (workerError || workerAllowed !== true) return json({ error: 'not found' }, 404)

    const { data: target, error: targetError } = await admin.rpc(
      'farm_watch_get_snow_winter_severity_target_v1_internal',
      { p_slug: slug },
    )
    if (targetError) throw new Error(targetError.message)
    if (target?.status !== 'available') {
      return json({
        ok: true,
        status: target?.status || 'unavailable',
        property: target?.property || { slug },
        reason: target?.reason || null,
      })
    }

    const source = await fetchNohrsc(target)
    const sourcePayloadSha256 = await sha256Hex(source.rawText)
    const sampleDate = localIsoDate(source.sourceValidAt, String(target.time_zone || ''))

    const { data: context, error: recordError } = await admin.rpc(
      'farm_watch_record_snow_winter_severity_sample_v1_internal',
      {
        p_slug: slug,
        p_sample_date: sampleDate,
        p_snow_depth_cm: source.snowDepthCm,
        p_snow_source_valid_at: source.sourceValidAt.toISOString(),
        p_snow_source_ingested_at: source.sourceIngestedAt?.toISOString() || null,
        p_snow_source_object: source.sourceObject,
        p_snow_source_payload_sha256: sourcePayloadSha256,
        p_retrieved_at: new Date().toISOString(),
      },
    )
    if (recordError) throw new Error(recordError.message)
    if (!validateFarmWatchSnowWinterSeverityContext(context)) {
      throw new Error('snow/winter severity context failed contract validation')
    }

    return json({
      ok: true,
      status: context.status,
      property: target.property,
      sample: {
        date: sampleDate,
        snow_depth_cm: source.snowDepthCm,
        source_valid_at: source.sourceValidAt.toISOString(),
        source_ingested_at: source.sourceIngestedAt?.toISOString() || null,
        source_object: source.sourceObject,
        source_slug: FARM_WATCH_SNOW_WINTER_SEVERITY_PRODUCT.snowSourceSlug,
      },
      context,
    })
  } catch (error) {
    console.error('Farm Watch snow/winter severity failed', error instanceof Error ? error.message : error)
    return json({
      ok: false,
      status: 'unavailable',
      error: error instanceof Error ? error.message : String(error),
    }, 500)
  }
})
