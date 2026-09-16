import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.57.4'

const SLUG = 'collect-responsible-party-resolution'
const MAX_BODY_BYTES = 32 * 1024
const FETCH_TIMEOUT_MS = 12_000
const MAX_SOURCE_BYTES = 1_200_000
const MAX_CONCURRENCY = 4
const sourceHttpClient = Deno.createHttpClient({ http1: true, http2: false })

function serviceKey(): string {
  try {
    const keys = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') || '{}')
    if (typeof keys.default === 'string' && keys.default) return keys.default
  } catch { /* legacy service role remains supported */ }
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!key) throw new Error('Scout database credentials unavailable')
  return key
}

const db = createClient(Deno.env.get('SUPABASE_URL')!, serviceKey(), {
  auth: { persistSession: false, autoRefreshToken: false },
})

type O = Record<string, any>
type Job = {
  id: string
  profile_key: string
  lookup_key: string
  parcel_source_record_id?: string | null
  parcel_source_native_id?: string | null
  parcel_id?: string | null
  provider_kind: string
  owner_lookup_url_template?: string | null
  source_authority: string
  source_url: string
  profile_attributes?: O
  lookup_latitude?: number | null
  lookup_longitude?: number | null
  lookup_address?: string | null
  candidate_keys?: string[]
}

type ParsedProperty = {
  owner: string | null
  siteAddress: string | null
  parcelId: string | null
  assessedValue: number | null
  acres: number | null
  observedOn: string | null
}

type AddressPointMatch = {
  fullAddress: string
  matchedAddress: string
  parcelId: string
  lrsn: string
  apartment: string | null
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store, max-age=0',
      'x-content-type-options': 'nosniff',
    },
  })
}

function err(value: unknown) {
  return String(value instanceof Error ? value.message : value)
    .replace(/Bearer\s+[A-Za-z0-9_.-]+/gi, 'Bearer [REDACTED]')
    .replace(/sb_secret_[A-Za-z0-9_-]+/g, '[REDACTED]')
    .slice(0, 1000)
}

function asInt(value: unknown, fallback: number, min: number, max: number) {
  const n = Number(value)
  return Number.isFinite(n) ? Math.max(min, Math.min(max, Math.floor(n))) : fallback
}

function decode(value: string) {
  return value
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'")
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&#(\d+);/g, (_, n) => String.fromCharCode(Number(n)))
}

function text(value: string) {
  return decode(value.replace(/<[^>]+>/g, ' ')).replace(/\s+/g, ' ').trim()
}

function escaped(label: string) {
  return label.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}

function dlValue(html: string, label: string) {
  const re = new RegExp(`<dt\\b[^>]*>\\s*${escaped(label)}\\s*<\\/dt>\\s*<dd\\b[^>]*>([\\s\\S]*?)<\\/dd>`, 'i')
  const match = html.match(re)
  return match ? text(match[1]) || null : null
}

function h1Value(html: string) {
  const match = html.match(/<h1\b[^>]*>([\s\S]*?)<\/h1>/i)
  return match ? text(match[1]) || null : null
}

function numberValue(value: string | null) {
  if (!value) return null
  const n = Number(value.replace(/[$,\s]/g, ''))
  return Number.isFinite(n) ? n : null
}

function observedDate(html: string) {
  const match = text(html).match(/Data last updated:\s*(\d{1,2}\/\d{1,2}\/\d{4})/i)
  if (!match) return null
  const [m, d, y] = match[1].split('/').map(Number)
  if (!m || !d || !y) return null
  return `${String(y).padStart(4, '0')}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`
}

function normalizeParcel(value: string | null | undefined) {
  return String(value || '').toUpperCase().replace(/[^A-Z0-9]/g, '')
}

function normalizeAddress(value: string | null | undefined) {
  return String(value || '')
    .toLowerCase()
    .replace(/\b(north)\b/g, 'n')
    .replace(/\b(south)\b/g, 's')
    .replace(/\b(east)\b/g, 'e')
    .replace(/\b(west)\b/g, 'w')
    .replace(/\b(street)\b/g, 'st')
    .replace(/\b(avenue)\b/g, 'ave')
    .replace(/\b(boulevard)\b/g, 'blvd')
    .replace(/\b(road)\b/g, 'rd')
    .replace(/\b(drive)\b/g, 'dr')
    .replace(/\b(lane)\b/g, 'ln')
    .replace(/\b(court)\b/g, 'ct')
    .replace(/\b(circle)\b/g, 'cir')
    .replace(/\b(parkway)\b/g, 'pkwy')
    .replace(/\b(highway)\b/g, 'hwy')
    .replace(/\b(place)\b/g, 'pl')
    .replace(/\b(apartment|apt|unit|suite|ste)\b/g, '')
    .replace(/[^a-z0-9]+/g, '')
}

function parseJeffersonPva(html: string): ParsedProperty {
  return {
    owner: dlValue(html, 'Owner'),
    siteAddress: h1Value(html),
    parcelId: dlValue(html, 'Parcel ID'),
    assessedValue: numberValue(dlValue(html, 'Assessed Value')),
    acres: numberValue(dlValue(html, 'Acres')),
    observedOn: observedDate(html),
  }
}

async function fetchText(url: string, accept: string) {
  const parsed = new URL(url)
  if (parsed.protocol !== 'https:') throw new Error('responsible-party lookup requires HTTPS')
  const response = await fetch(parsed.toString(), {
    client: sourceHttpClient,
    redirect: 'follow',
    signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
    headers: {
      accept,
      'user-agent': 'Scout-by-Cadastory/1.0 property-party-evidence',
    },
  })
  if (!response.ok) throw new Error(`property source HTTP ${response.status}`)
  const contentLength = Number(response.headers.get('content-length') || 0)
  if (contentLength > MAX_SOURCE_BYTES) throw new Error('property source response too large')
  return (await response.text()).slice(0, MAX_SOURCE_BYTES)
}

async function fetchHtml(url: string) {
  return fetchText(url, 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.5')
}

async function fetchJson(url: string) {
  const raw = await fetchText(url, 'application/json,text/plain;q=0.9,*/*;q=0.5')
  try { return JSON.parse(raw) as O } catch { throw new Error('property source returned invalid JSON') }
}

async function complete(jobId: string, outcome: string, payload: O = {}) {
  const result = await db.rpc('internal_complete_responsible_party_resolution_job_v1', {
    p_job_id: jobId,
    p_outcome: outcome,
    p_party_name: payload.party_name ?? null,
    p_site_address: payload.site_address ?? null,
    p_parcel_id: payload.parcel_id ?? null,
    p_source_url: payload.source_url ?? null,
    p_source_authority: payload.source_authority ?? null,
    p_observed_on: payload.observed_on ?? null,
    p_attributes: payload.attributes ?? {},
    p_error: payload.error ?? null,
  })
  if (result.error) throw new Error(`completion: ${result.error.message}`)
  return result.data
}

async function processJeffersonPva(job: Job) {
  if (!job.owner_lookup_url_template || !job.lookup_key) {
    return complete(job.id, 'needs_review', { error: 'owner lookup configuration incomplete' })
  }

  const sourceUrl = job.owner_lookup_url_template.replace('{lookup_key}', encodeURIComponent(job.lookup_key))
  const html = await fetchHtml(sourceUrl)
  const parsed = parseJeffersonPva(html)

  if (!parsed.owner) {
    return complete(job.id, 'no_evidence', { error: 'public property detail did not expose an owner' })
  }

  const expectedParcel = normalizeParcel(job.parcel_id)
  const observedParcel = normalizeParcel(parsed.parcelId)
  if (expectedParcel && (!observedParcel || expectedParcel !== observedParcel)) {
    return complete(job.id, 'needs_review', {
      error: `parcel identity mismatch: expected ${expectedParcel}, observed ${observedParcel || 'missing'}`,
    })
  }

  return complete(job.id, 'completed', {
    party_name: parsed.owner,
    site_address: parsed.siteAddress,
    parcel_id: parsed.parcelId || job.parcel_id || null,
    source_url: sourceUrl,
    source_authority: job.source_authority,
    observed_on: parsed.observedOn,
    attributes: {
      provider_kind: job.provider_kind,
      lookup_key: job.lookup_key,
      parcel_match_method: 'unique_spatial_intersection',
      assessed_value: parsed.assessedValue,
      acres: parsed.acres,
      public_detail_last_updated: parsed.observedOn,
      public_detail_fields_only: true,
      source_media_retained: false,
    },
  })
}

async function processJeffersonPvaAddressRecovery(job: Job) {
  const attrs = job.profile_attributes || {}
  const lookupAddress = String(job.lookup_address || '').trim()
  const addressLookupBase = String(attrs.address_lookup_url || '')
  const fullField = String(attrs.address_full_field || 'FULL_ADDRESS')
  const houseField = String(attrs.address_house_number_field || 'HOUSENO')
  const parcelField = String(attrs.address_parcel_id_field || 'PARCELID')
  const lrsnField = String(attrs.address_lrsn_field || 'LRSN')
  const apartmentField = String(attrs.address_apartment_field || 'APT')

  if (!lookupAddress || !addressLookupBase || !job.owner_lookup_url_template) {
    return complete(job.id, 'needs_review', { error: 'address-point recovery configuration incomplete' })
  }
  const houseMatch = lookupAddress.match(/^\s*(\d+)/)
  if (!houseMatch) {
    return complete(job.id, 'needs_review', { error: 'site address does not begin with a numeric house number' })
  }
  const houseNumber = Number(houseMatch[1])
  if (!Number.isSafeInteger(houseNumber) || houseNumber < 1) {
    return complete(job.id, 'needs_review', { error: 'site address house number is invalid' })
  }

  const queryUrl = new URL(addressLookupBase)
  queryUrl.searchParams.set('where', `${houseField}=${houseNumber}`)
  queryUrl.searchParams.set('outFields', `${fullField},${parcelField},${lrsnField},${apartmentField}`)
  queryUrl.searchParams.set('returnGeometry', 'false')
  queryUrl.searchParams.set('resultRecordCount', '200')
  queryUrl.searchParams.set('orderByFields', `${fullField} ASC`)
  queryUrl.searchParams.set('f', 'json')

  const payload = await fetchJson(queryUrl.toString())
  if (payload?.error) {
    throw new Error(`LOJIC address-point query error: ${String(payload.error?.message || 'unknown').slice(0, 250)}`)
  }
  if (payload?.exceededTransferLimit === true) {
    return complete(job.id, 'needs_review', { error: 'bounded LOJIC address-point query exceeded result limit' })
  }

  const wanted = normalizeAddress(lookupAddress)
  const features = Array.isArray(payload?.features) ? payload.features : []
  const exact: AddressPointMatch[] = []
  for (const feature of features) {
    const values = feature?.attributes && typeof feature.attributes === 'object' ? feature.attributes : {}
    const fullAddress = String(values?.[fullField] ?? '').trim()
    const apartment = String(values?.[apartmentField] ?? '').trim() || null
    const parcelId = String(values?.[parcelField] ?? '').trim()
    const lrsn = String(values?.[lrsnField] ?? '').trim()
    if (!fullAddress) continue
    const baseMatch = normalizeAddress(fullAddress) === wanted
    const unitAddress = apartment ? `${fullAddress} ${apartment}` : fullAddress
    const unitMatch = normalizeAddress(unitAddress) === wanted
    if (!baseMatch && !unitMatch) continue
    exact.push({
      fullAddress,
      matchedAddress: unitMatch && !baseMatch ? unitAddress : fullAddress,
      parcelId,
      lrsn,
      apartment,
    })
  }

  if (!exact.length) {
    return complete(job.id, 'no_evidence', { error: 'LOJIC address points returned no exact normalized site-address match' })
  }

  const byParcel = new Map<string, AddressPointMatch>()
  for (const match of exact) {
    const parcel = normalizeParcel(match.parcelId)
    const lrsn = match.lrsn.replace(/\D/g, '')
    if (!parcel || !lrsn) continue
    byParcel.set(`${parcel}|${lrsn}`, match)
  }
  if (!byParcel.size) {
    return complete(job.id, 'needs_review', { error: 'exact LOJIC address match lacked parcel ID or LRSN' })
  }
  if (byParcel.size !== 1) {
    return complete(job.id, 'needs_review', { error: `exact LOJIC address matched ${byParcel.size} distinct parcels` })
  }

  const addressPoint = [...byParcel.values()][0]
  const expectedParcel = normalizeParcel(addressPoint.parcelId)
  const sourceUrl = job.owner_lookup_url_template.replace('{lookup_key}', encodeURIComponent(addressPoint.lrsn))
  const html = await fetchHtml(sourceUrl)
  const parsed = parseJeffersonPva(html)
  if (!parsed.owner) {
    return complete(job.id, 'no_evidence', { error: 'PVA detail for exact LOJIC address parcel did not expose an owner' })
  }
  const observedParcel = normalizeParcel(parsed.parcelId)
  if (!observedParcel || observedParcel !== expectedParcel) {
    return complete(job.id, 'needs_review', {
      error: `LOJIC/PVA parcel identity mismatch: expected ${expectedParcel}, observed ${observedParcel || 'missing'}`,
    })
  }

  return complete(job.id, 'completed', {
    party_name: parsed.owner,
    site_address: addressPoint.matchedAddress,
    parcel_id: addressPoint.parcelId,
    source_url: sourceUrl,
    source_authority: job.source_authority,
    observed_on: parsed.observedOn,
    attributes: {
      provider_kind: job.provider_kind,
      resolution_mode: 'address_point_lrsn_recovery',
      parcel_match_method: 'exact_lojic_address_point_lrsn_then_pva',
      address_match_basis: 'exact_normalized_lojic_address_point',
      lookup_address: lookupAddress,
      address_point_full_address: addressPoint.fullAddress,
      address_point_apartment: addressPoint.apartment,
      address_point_query_url: queryUrl.toString(),
      address_point_lrsn: addressPoint.lrsn,
      address_point_parcel_id: addressPoint.parcelId,
      pva_primary_site_address: parsed.siteAddress,
      assessed_value: parsed.assessedValue,
      acres: parsed.acres,
      public_detail_last_updated: parsed.observedOn,
      public_detail_fields_only: true,
      bulk_mirror: false,
      source_media_retained: false,
      buyer_authority_not_implied: true,
      property_manager_not_implied: true,
      operator_not_implied: true,
    },
  })
}

async function processArcgisPointOwner(job: Job) {
  const latitude = Number(job.lookup_latitude)
  const longitude = Number(job.lookup_longitude)
  const base = String(job.owner_lookup_url_template || '')
  const attrs = job.profile_attributes || {}
  const ownerField = String(attrs.owner_field || '')
  const parcelField = String(attrs.parcel_id_field || '')
  const querySr = Number(attrs.query_sr || 4326)

  if (!base || !Number.isFinite(latitude) || !Number.isFinite(longitude) || !ownerField || !parcelField) {
    return complete(job.id, 'needs_review', { error: 'ArcGIS owner lookup configuration incomplete' })
  }
  if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
    return complete(job.id, 'needs_review', { error: 'ArcGIS owner lookup coordinates invalid' })
  }

  const queryUrl = new URL(base)
  queryUrl.searchParams.set('where', '1=1')
  queryUrl.searchParams.set('geometry', `${longitude},${latitude}`)
  queryUrl.searchParams.set('geometryType', 'esriGeometryPoint')
  queryUrl.searchParams.set('inSR', String(querySr))
  queryUrl.searchParams.set('spatialRel', 'esriSpatialRelIntersects')
  queryUrl.searchParams.set('outFields', `${parcelField},${ownerField}`)
  queryUrl.searchParams.set('returnGeometry', 'false')
  queryUrl.searchParams.set('f', 'json')

  const payload = await fetchJson(queryUrl.toString())
  if (payload?.error) {
    throw new Error(`ArcGIS parcel query error: ${String(payload.error?.message || 'unknown').slice(0, 250)}`)
  }
  const features = Array.isArray(payload?.features) ? payload.features : []
  if (features.length === 0) {
    return complete(job.id, 'no_evidence', { error: 'public parcel point query returned no parcel' })
  }
  if (features.length !== 1) {
    return complete(job.id, 'needs_review', { error: `public parcel point query returned ${features.length} parcels` })
  }

  const values = features[0]?.attributes && typeof features[0].attributes === 'object' ? features[0].attributes : {}
  const owner = String(values?.[ownerField] ?? '').trim()
  const parcelId = String(values?.[parcelField] ?? '').trim()
  if (!owner) {
    return complete(job.id, 'no_evidence', { error: 'public parcel point query returned no owner' })
  }
  if (!parcelId) {
    return complete(job.id, 'needs_review', { error: 'public parcel point query returned no parcel identifier' })
  }

  return complete(job.id, 'completed', {
    party_name: owner,
    site_address: job.lookup_address || null,
    parcel_id: parcelId,
    source_url: job.source_url || base,
    source_authority: job.source_authority,
    observed_on: null,
    attributes: {
      provider_kind: job.provider_kind,
      lookup_key: job.lookup_key,
      parcel_match_method: 'authoritative_arcgis_point_intersection',
      lookup_latitude: latitude,
      lookup_longitude: longitude,
      query_sr: querySr,
      owner_field: ownerField,
      parcel_id_field: parcelField,
      public_detail_fields_only: true,
      bulk_mirror: false,
      source_media_retained: false,
      buyer_authority_not_implied: true,
      property_manager_not_implied: true,
      operator_not_implied: true,
    },
  })
}

async function processJob(job: Job) {
  if (job.provider_kind === 'pva_lrsn_html' && job.profile_attributes?.resolution_mode === 'address_point_lrsn_recovery') {
    return processJeffersonPvaAddressRecovery(job)
  }
  if (job.provider_kind === 'pva_lrsn_html') return processJeffersonPva(job)
  if (job.provider_kind === 'arcgis_point_owner') return processArcgisPointOwner(job)
  return complete(job.id, 'needs_review', { error: `unsupported provider kind ${job.provider_kind}` })
}

async function authorized(req: Request) {
  const key = req.headers.get('x-scout-key') || ''
  if (!key) return false
  const result = await db.rpc('internal_validate_collector_key', { p_key: key })
  return !result.error && result.data === true
}

async function beginRun(limit: number, claimScope: string) {
  const result = await db.rpc('internal_begin_collector_run', {
    p_slug: SLUG,
    p_request_summary: { limit, claim_scope: claimScope },
  })
  if (result.error || !result.data) throw new Error('collector run could not be recorded')
  return String(result.data)
}

async function finishRun(runId: string, status: 'succeeded' | 'partial' | 'failed' | 'no_work', httpStatus: number, summary: O) {
  const result = await db.rpc('internal_finish_collector_run', {
    p_run_id: runId,
    p_status: status,
    p_http_status: httpStatus,
    p_summary: summary,
  })
  if (result.error) throw new Error('collector result could not be recorded')
}

async function processBatch(jobs: Job[]) {
  const processed: O[] = []
  for (let i = 0; i < jobs.length; i += MAX_CONCURRENCY) {
    const group = jobs.slice(i, i + MAX_CONCURRENCY)
    const outcomes = await Promise.all(group.map(async job => {
      try {
        const result = await processJob(job)
        return { job_id: job.id, lookup_key: job.lookup_key, provider_kind: job.provider_kind, status: 'succeeded', result }
      } catch (error) {
        const message = err(error)
        try {
          const result = await complete(job.id, 'failed', { error: message })
          return { job_id: job.id, lookup_key: job.lookup_key, provider_kind: job.provider_kind, status: 'succeeded', result, worker_error: message }
        } catch (completionError) {
          return {
            job_id: job.id,
            lookup_key: job.lookup_key,
            provider_kind: job.provider_kind,
            status: 'failed',
            error: `${message}; failure completion also failed: ${err(completionError)}`,
          }
        }
      }
    }))
    processed.push(...outcomes)
  }
  return processed
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return json({ error: 'POST required' }, 405)
  if (!await authorized(req)) return json({ error: 'unauthorized' }, 401)

  const raw = await req.text()
  if (new TextEncoder().encode(raw).byteLength > MAX_BODY_BYTES) return json({ error: 'request_too_large' }, 413)
  let body: O = {}
  try { body = JSON.parse(raw || '{}') } catch { return json({ error: 'invalid_json' }, 400) }
  const claimScope = body.claim_scope === 'address_recovery' ? 'address_recovery' : 'local'
  const limit = asInt(body.limit, claimScope === 'address_recovery' ? 4 : 8, 1, claimScope === 'address_recovery' ? 8 : 12)

  let runId = ''
  try {
    runId = await beginRun(limit, claimScope)
    const claimRpc = claimScope === 'address_recovery'
      ? 'internal_claim_responsible_party_address_recovery_jobs_v1'
      : 'internal_claim_responsible_party_resolution_jobs_v1'
    const claimed = await db.rpc(claimRpc, { p_limit: limit })
    if (claimed.error) throw new Error(`claim: ${claimed.error.message}`)
    const jobs: Job[] = Array.isArray(claimed.data) ? claimed.data : []

    if (!jobs.length) {
      const summary = { outcome: 'no_work', counts: { attempted: 0, succeeded: 0, failed: 0 }, claim_scope: claimScope }
      await finishRun(runId, 'no_work', 200, summary)
      return json({ ok: true, outcome: 'no_work', run_id: runId, claimed: 0, processed: [], claim_scope: claimScope })
    }

    const processed = await processBatch(jobs)
    const failed = processed.filter(x => x.status === 'failed')
    const succeeded = processed.length - failed.length
    const outcome = failed.length === 0 ? 'succeeded' : succeeded > 0 ? 'partial' : 'failed'
    const httpStatus = outcome === 'succeeded' ? 200 : outcome === 'partial' ? 207 : 500
    const summary = {
      outcome,
      counts: { attempted: jobs.length, succeeded, failed: failed.length },
      providers: [...new Set(jobs.map(x => x.provider_kind))],
      claim_scope: claimScope,
      errors: failed.map(x => x.error).slice(0, 10),
    }
    await finishRun(runId, outcome, httpStatus, summary)
    return json({ ok: outcome !== 'failed', outcome, run_id: runId, claimed: jobs.length, processed, claim_scope: claimScope }, httpStatus)
  } catch (error) {
    const message = err(error)
    if (runId) {
      try {
        await finishRun(runId, 'failed', 500, {
          outcome: 'failed',
          counts: { attempted: null, succeeded: null, failed: 1 },
          claim_scope: claimScope,
          errors: [message],
        })
      } catch { /* preserve primary error */ }
    }
    console.error(message)
    return json({ ok: false, outcome: 'failed', run_id: runId || null, error: message, claim_scope: claimScope }, 500)
  }
})