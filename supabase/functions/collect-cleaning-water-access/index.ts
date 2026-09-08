import { withCollectorRun } from './collector-runtime.ts'
import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.57.4'

function serviceKey(): string {
  try {
    const keys = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') || '{}')
    if (typeof keys.default === 'string' && keys.default) return keys.default
  } catch {}
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!key) throw new Error('collector service credentials unavailable')
  return key
}

const sb = createClient(Deno.env.get('SUPABASE_URL')!, serviceKey(), {
  auth: { persistSession: false, autoRefreshToken: false },
})

type Job = {
  queue_id: string
  building_source_record_id: string
  provider_organization_id?: string | null
  reason: string
  priority: number
  search_radius_m: number
  requested_source_types: string[]
  attempt_count: number
  bbox: { west: number; south: number; east: number; north: number }
}

type Elem = {
  type?: string
  id?: string | number
  lat?: number
  lon?: number
  tags?: Record<string, string>
}

function queryFor(job: Job) {
  const { south, west, north, east } = job.bbox
  const wants = new Set(job.requested_source_types || [])
  const q: string[] = []

  if (wants.has('hydrant')) {
    q.push(`node["emergency"="fire_hydrant"](${south},${west},${north},${east});`)
  }

  if (wants.has('onsite_plumbed') || wants.has('customer_spigot')) {
    q.push(`node["man_made"="water_tap"](${south},${west},${north},${east});`)
    q.push(`node["amenity"="water_point"](${south},${west},${north},${east});`)
    q.push(`node["amenity"="drinking_water"](${south},${west},${north},${east});`)
  }

  // Municipal/commercial fill stations do not have one reliable OSM tag contract.
  // Keep them on a separate evidence/research path rather than guessing.
  return `[out:json][timeout:30];(\n${q.join('\n')}\n);out body tags;`
}

function classify(e: Elem) {
  if (e.type !== 'node' || !Number.isFinite(e.lat) || !Number.isFinite(e.lon)) return null
  const t = e.tags ?? {}
  let source_type: string | null = null
  let confidence = 0.5
  let notes: string | null = null

  if (t.emergency === 'fire_hydrant') {
    source_type = 'hydrant'
    confidence = 0.65
    notes = 'Mapped fire hydrant location only. Mapping does not establish legal use, meter/permit availability, flow, backflow requirements, or operator authorization.'
  } else if (t.man_made === 'water_tap') {
    source_type = 'onsite_plumbed'
    confidence = 0.60
    notes = 'Mapped water tap candidate. Verify property permission, connection type, usable flow, and backflow requirements before planning around it.'
  } else if (t.amenity === 'water_point') {
    source_type = 'onsite_plumbed'
    confidence = 0.50
    notes = 'Mapped water point candidate. Intended use and commercial cleaning flow are unknown until verified.'
  } else if (t.amenity === 'drinking_water') {
    source_type = 'other'
    confidence = 0.30
    notes = 'Mapped drinking-water point is weak evidence for cleaning support and may have inadequate connection/flow. Treat only as a verification lead.'
  }

  if (!source_type) return null

  return {
    source_native_id: `${e.type}/${e.id}`,
    source_type,
    geometry: { type: 'Point', coordinates: [e.lon, e.lat] },
    permission_required: true,
    permission_status: 'unknown',
    backflow_required: null,
    backflow_status: 'unknown',
    confidence,
    notes,
    raw_attributes: t,
  }
}

async function processJob(job: Job) {
  const q = queryFor(job)
  if (!q.includes('node[')) {
    const complete = await sb.rpc('internal_complete_cleaning_water_job', {
      p_queue_id: job.queue_id,
      p_sources: [],
      p_source_timestamp: null,
      p_response_meta: { reason: 'no_supported_mapped_source_types' },
    })
    if (complete.error) throw new Error(complete.error.message)
    return { building_source_record_id: job.building_source_record_id, status: 'succeeded', source_count: 0 }
  }

  const fetched = await sb.rpc('internal_fetch_site_access_overpass', { p_query: q })
  if (fetched.error) throw new Error(`provider rpc failed: ${fetched.error.message}`)
  const r = fetched.data ?? {}

  if (r.ok !== true) {
    const retry = Number(r?.headers?.['retry-after'] ?? 0) || null
    await sb.rpc('internal_fail_cleaning_water_job', {
      p_queue_id: job.queue_id,
      p_error: String(r.error ?? r.body?.error?.message ?? `provider HTTP ${r.http_status ?? 'failure'}`),
      p_retry_after_seconds: retry,
      p_terminal: false,
    })
    return {
      building_source_record_id: job.building_source_record_id,
      status: 'failed',
      error: String(r.error ?? r.body?.error?.message ?? 'provider failure'),
    }
  }

  const elements: Elem[] = Array.isArray(r.body?.elements) ? r.body.elements : []
  const sources = elements.map(classify).filter(Boolean)
  const sourceTs = r.body?.osm3s?.timestamp_osm_base ?? null

  const complete = await sb.rpc('internal_complete_cleaning_water_job', {
    p_queue_id: job.queue_id,
    p_sources: sources,
    p_source_timestamp: sourceTs,
    p_response_meta: {
      provider_slug: r.provider_slug,
      http_status: r.http_status,
      quota: r.headers ?? {},
      queried_source_types: job.requested_source_types,
    },
  })

  if (complete.error) {
    await sb.rpc('internal_fail_cleaning_water_job', {
      p_queue_id: job.queue_id,
      p_error: `completion failed: ${complete.error.message}`,
      p_terminal: false,
    })
    return { building_source_record_id: job.building_source_record_id, status: 'failed', error: complete.error.message }
  }

  return {
    building_source_record_id: job.building_source_record_id,
    status: 'succeeded',
    source_count: Number(complete.data?.source_count ?? sources.length),
  }
}

Deno.serve(withCollectorRun('collect-cleaning-water-access', async (req: Request) => {
  const body = await req.json().catch(() => ({}))
  const state = await sb.rpc('internal_get_site_access_provider_state')

  if (state.error) return Response.json({ ok: false, error: 'water access provider state unavailable' }, { status: 503 })
  if (state.data?.configured !== true) {
    return Response.json({ ok: true, outcome: 'no_work', targets: 0, stored: 0, provider_state: state.data })
  }

  const requested = Number(body?.limit ?? 2)
  const limit = Math.max(1, Math.min(Number.isFinite(requested) ? Math.floor(requested) : 2, 10))
  const claimed = await sb.rpc('internal_claim_cleaning_water_jobs', { p_limit: limit })

  if (claimed.error) return Response.json({ ok: false, error: `water queue claim failed: ${claimed.error.message}` }, { status: 500 })
  const jobs: Job[] = Array.isArray(claimed.data) ? claimed.data : []
  if (jobs.length === 0) return Response.json({ ok: true, outcome: 'no_work', targets: 0, stored: 0, provider: state.data?.provider_slug })

  const processed: any[] = []
  for (const job of jobs) processed.push(await processJob(job))
  const stored = processed.filter(x => x.status === 'succeeded').length
  const failures = processed.filter(x => x.status !== 'succeeded').map(x => ({ building_source_record_id: x.building_source_record_id, error: x.error ?? x.status }))

  return Response.json({ ok: failures.length === 0, targets: jobs.length, stored, processed, failures, provider: state.data?.provider_slug })
}))
