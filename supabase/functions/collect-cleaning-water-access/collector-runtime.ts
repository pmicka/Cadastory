import { createClient } from 'npm:@supabase/supabase-js@2.57.4'

type Outcome = 'succeeded' | 'partial' | 'failed' | 'no_work'
type Counts = { attempted: number | null; succeeded: number | null; failed: number }
type Result = Record<string, any>

function serviceKey(): string {
  try {
    const keys = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') || '{}')
    if (typeof keys.default === 'string' && keys.default) return keys.default
  } catch {}
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!key) throw new Error('Collector service credentials unavailable')
  return key
}

let client: ReturnType<typeof createClient> | undefined
function admin() {
  if (!client) client = createClient(Deno.env.get('SUPABASE_URL')!, serviceKey(), { auth: { persistSession: false, autoRefreshToken: false } })
  return client
}

function integer(v: unknown): number | null {
  return typeof v === 'number' && Number.isFinite(v) && v >= 0 ? Math.floor(v) : null
}

function errorText(v: unknown): string {
  const raw = typeof v === 'string' ? v : JSON.stringify(v)
  return String(raw || 'unspecified failure')
    .replace(/Bearer\s+[A-Za-z0-9_.-]+/gi, 'Bearer [REDACTED]')
    .replace(/sb_secret_[A-Za-z0-9_-]+/g, '[REDACTED]')
    .replace(/bootstrap=[^&\s]+/gi, 'bootstrap=[REDACTED]')
    .slice(0, 600)
}

export function classifyResult(slug: string, body: Result, httpStatus: number): { outcome: Outcome; counts: Counts; errors: string[] } {
  const errors: string[] = []
  for (const key of ['errors', 'failures', 'counties_failed']) {
    const value = body[key]
    if (Array.isArray(value)) errors.push(...value.map(errorText))
    else if (value && typeof value === 'object') errors.push(...Object.values(value).map(errorText))
  }
  if (body.error) errors.push(errorText(body.error))

  const processed = Array.isArray(body.processed) ? body.processed : null
  const failedProcessed = processed?.filter((x: Result) => x.status !== 'succeeded') || []
  for (const x of failedProcessed) errors.push(errorText(x.error || x.status))

  let attempted = integer(body.targets) ?? integer(body.claimed)
  let succeeded: number | null = null
  let failed = errors.length

  if (processed) {
    attempted = integer(body.claimed) ?? processed.length
    succeeded = processed.filter((x: Result) => x.status === 'succeeded').length
    failed = Math.max(failed, attempted - succeeded)
  } else if (integer(body.targets) !== null && integer(body.stored) !== null) {
    succeeded = integer(body.stored)
    failed = Math.max(failed, Math.max(0, attempted! - succeeded!))
  } else {
    succeeded = integer(body.inserted) ?? integer(body.stored) ?? integer(body.recordsInserted)
  }

  let outcome: Outcome
  if (httpStatus < 200 || httpStatus >= 300 || body.outcome === 'failed') outcome = 'failed'
  else if (body.outcome === 'no_work' || attempted === 0) outcome = 'no_work'
  else if (failed > 0 || body.outcome === 'partial') outcome = succeeded === 0 ? 'failed' : 'partial'
  else outcome = 'succeeded'

  return { outcome, counts: { attempted, succeeded, failed }, errors: errors.slice(0, 10) }
}

export function withCollectorRun(slug: string, handler: (req: Request) => Promise<Response>) {
  return async (req: Request): Promise<Response> => {
    if (req.method !== 'POST') return Response.json({ error: 'POST required' }, { status: 405 })
    const key = req.headers.get('x-scout-key') || ''
    if (!key) return Response.json({ error: 'unauthorized' }, { status: 401 })

    let db: ReturnType<typeof createClient>
    try { db = admin() } catch { return Response.json({ error: 'collector unavailable' }, { status: 503 }) }

    const validation = await db.rpc('internal_validate_collector_key', { p_key: key })
    if (validation.error || validation.data !== true) return Response.json({ error: 'unauthorized' }, { status: 401 })

    const input = await req.clone().json().catch(() => ({}))
    const requestSummary: Result = {}
    for (const field of ['mode', 'kind', 'limit', 'offset', 'startIndex', 'maxRecords', 'finalize']) {
      const value = input?.[field]
      if (typeof value === 'boolean' || typeof value === 'number' || typeof value === 'string') requestSummary[field] = typeof value === 'string' ? value.slice(0, 100) : value
    }

    const started = await db.rpc('internal_begin_collector_run', { p_slug: slug, p_request_summary: requestSummary })
    if (started.error || !started.data) return Response.json({ ok: false, outcome: 'failed', error: 'collector run could not be recorded' }, { status: 503 })

    const runId = String(started.data)
    let response: Response
    let body: Result
    try {
      response = await handler(req)
      const data = await response.clone().json()
      if (!data || typeof data !== 'object' || Array.isArray(data)) throw new Error('Collector returned an invalid result object')
      body = data
    } catch (error) {
      body = { ok: false, error: errorText(error instanceof Error ? error.message : error) }
      response = Response.json(body, { status: 500 })
    }

    const result = classifyResult(slug, body, response.status)
    const status = result.outcome === 'failed' ? (response.status >= 400 ? response.status : 502) : result.outcome === 'partial' ? 207 : response.status
    const summary = { outcome: result.outcome, counts: result.counts, errors: result.errors, source_watermark: body.latest_observed_at || body.source_timestamp || null }
    const finished = await db.rpc('internal_finish_collector_run', { p_run_id: runId, p_status: result.outcome, p_http_status: status, p_summary: summary })
    if (finished.error) return Response.json({ ok: false, outcome: 'failed', run_id: runId, error: 'collector result could not be recorded' }, { status: 503 })

    return Response.json({ ...body, ok: result.outcome === 'succeeded' || result.outcome === 'no_work', outcome: result.outcome, run_id: runId, run_counts: result.counts }, { status })
  }
}
