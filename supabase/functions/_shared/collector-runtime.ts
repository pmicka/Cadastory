import { createClient } from 'npm:@supabase/supabase-js@2.57.4'

type Outcome = 'succeeded' | 'partial' | 'failed' | 'no_work'
type Counts = { attempted: number | null; succeeded: number | null; failed: number }
type Result = Record<string, any>

function serviceKey(): string {
  try {
    const keys = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') || '{}')
    if (typeof keys.default === 'string' && keys.default) return keys.default
  } catch { /* legacy fallback */ }
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!key) throw new Error('Collector service credentials unavailable')
  return key
}

let client: any
function admin(): any {
  if (!client) client = createClient(Deno.env.get('SUPABASE_URL')!, serviceKey(), {
    auth: { persistSession: false, autoRefreshToken: false },
  })
  return client
}

function integer(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0
    ? Math.floor(value)
    : null
}

function errorText(value: unknown): string {
  const raw = typeof value === 'string' ? value : JSON.stringify(value)
  return String(raw || 'unspecified failure')
    .replace(/Bearer\s+[A-Za-z0-9_.-]+/gi, 'Bearer [REDACTED]')
    .replace(/sb_secret_[A-Za-z0-9_-]+/g, '[REDACTED]')
    .replace(/bootstrap=[^&\s]+/gi, 'bootstrap=[REDACTED]')
    .slice(0, 600)
}

export function classifyCollectorResult(body: Result, httpStatus: number): {
  outcome: Outcome
  counts: Counts
  errors: string[]
} {
  const errors: string[] = []
  for (const key of ['errors','failures']) {
    const value = body[key]
    if (Array.isArray(value)) {
      for (const item of value) errors.push(errorText(item?.error ?? item))
    }
  }
  if (body.error) errors.push(errorText(body.error))

  const attempted = integer(body.targets)
  const succeeded = integer(body.stored)
  const failed = Math.max(
    errors.length,
    attempted !== null && succeeded !== null ? Math.max(0, attempted - succeeded) : 0,
  )

  let outcome: Outcome
  if (httpStatus < 200 || httpStatus >= 300 || body.ok === false || body.outcome === 'failed') {
    outcome = 'failed'
  } else if (failed > 0 || body.outcome === 'partial') {
    outcome = succeeded === 0 ? 'failed' : 'partial'
  } else if (attempted === 0 || body.outcome === 'no_work') {
    outcome = 'no_work'
  } else {
    outcome = 'succeeded'
  }
  return { outcome, counts: { attempted, succeeded, failed }, errors: errors.slice(0, 10) }
}

export function withCollectorRun(
  slug: string,
  handler: (req: Request) => Promise<Response>,
) {
  return async (req: Request): Promise<Response> => {
    if (req.method !== 'POST') return Response.json({ error: 'POST required' }, { status: 405 })

    const key = req.headers.get('x-scout-key') || ''
    if (!key) return Response.json({ error: 'unauthorized' }, { status: 401 })

    let db: any
    try {
      db = admin()
    } catch {
      return Response.json({ error: 'collector unavailable' }, { status: 503 })
    }

    const validation = await db.rpc('internal_validate_collector_key', { p_key: key })
    if (validation.error || validation.data !== true) {
      return Response.json({ error: 'unauthorized' }, { status: 401 })
    }

    const input = await req.clone().json().catch(() => ({}))
    const requestSummary: Result = {}
    for (const field of ['property','limit','lookback_hours']) {
      const value = input?.[field]
      if (typeof value === 'number' || typeof value === 'string') {
        requestSummary[field] = typeof value === 'string' ? value.slice(0, 100) : value
      }
    }

    const started = await db.rpc('internal_begin_collector_run', {
      p_slug: slug,
      p_request_summary: requestSummary,
    })
    if (started.error || !started.data) {
      return Response.json(
        { ok: false, outcome: 'failed', error: 'collector run could not be recorded' },
        { status: 503 },
      )
    }

    const runId = String(started.data)
    let response: Response
    let body: Result

    try {
      response = await handler(req)
      const data = await response.clone().json()
      if (!data || typeof data !== 'object' || Array.isArray(data)) {
        throw new Error('Collector returned an invalid result object')
      }
      body = data
    } catch (error) {
      body = { ok: false, error: errorText(error instanceof Error ? error.message : error) }
      response = Response.json(body, { status: 500 })
    }

    const result = classifyCollectorResult(body, response.status)
    const status = result.outcome === 'failed'
      ? (response.status >= 400 ? response.status : 502)
      : result.outcome === 'partial'
      ? 207
      : response.status

    const summary = {
      outcome: result.outcome,
      counts: result.counts,
      errors: result.errors,
      source_watermark: body.valid_at || body.reference_time || null,
    }
    const finished = await db.rpc('internal_finish_collector_run', {
      p_run_id: runId,
      p_status: result.outcome,
      p_http_status: status,
      p_summary: summary,
    })
    if (finished.error) {
      return Response.json(
        { ok: false, outcome: 'failed', run_id: runId, error: 'collector result could not be recorded' },
        { status: 503 },
      )
    }

    return Response.json(
      {
        ...body,
        ok: result.outcome === 'succeeded' || result.outcome === 'no_work',
        outcome: result.outcome,
        run_id: runId,
        run_counts: result.counts,
      },
      { status },
    )
  }
}
