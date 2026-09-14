import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.57.4'

const url = Deno.env.get('SUPABASE_URL')!
let serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
try {
  serviceKey = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') || '{}').default || serviceKey
} catch { /* legacy service-role secret remains supported */ }
if (!url || !serviceKey) throw new Error('Scout database credentials unavailable')

const db = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } })
const MAX_BODY_BYTES = 128 * 1024
const BUYER_PACK = 'buyer_organization_contact_v1'
const OUTCOMES = new Set(['completed', 'no_evidence', 'research_exhausted', 'needs_review', 'failed'])

function headers() {
  return {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store, max-age=0',
    'pragma': 'no-cache',
    'x-content-type-options': 'nosniff',
  }
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: headers() })
}

async function authorized(req: Request) {
  const key = req.headers.get('x-scout-key') || ''
  if (!key) return false
  const { data, error } = await db.rpc('internal_validate_collector_key', { p_key: key })
  return !error && data === true
}

function asInt(v: unknown, fallback: number, min: number, max: number) {
  const n = Number(v)
  if (!Number.isFinite(n)) return fallback
  return Math.max(min, Math.min(max, Math.floor(n)))
}

Deno.serve(async (req: Request) => {
  try {
    if (req.method !== 'POST') return json({ ok: false, error: 'POST required' }, 405)
    if (!await authorized(req)) return json({ ok: false, error: 'unauthorized' }, 401)

    const declared = Number(req.headers.get('content-length') || 0)
    if (declared > MAX_BODY_BYTES) return json({ ok: false, error: 'request_too_large' }, 413)
    const raw = await req.text()
    if (new TextEncoder().encode(raw).byteLength > MAX_BODY_BYTES) return json({ ok: false, error: 'request_too_large' }, 413)

    let body: Record<string, unknown>
    try {
      const parsed = JSON.parse(raw || '{}')
      if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) throw new Error('object required')
      body = parsed
    } catch {
      return json({ ok: false, error: 'invalid_json' }, 400)
    }

    const action = String(body.action || '')

    if (action === 'health') {
      const { data, error } = await db
        .schema('research')
        .from('document_evidence_jobs')
        .select('state', { count: 'exact', head: false })
        .eq('rule_pack', BUYER_PACK)
        .limit(1)
      if (error) throw error
      return json({ ok: true, worker: 'scout-document-evidence-worker', rule_pack: BUYER_PACK, database_reachable: Array.isArray(data) })
    }

    if (action === 'seed_buyer') {
      const clusterLimit = asInt(body.cluster_limit, 250, 1, 1000)
      const { data, error } = await db.rpc('internal_seed_buyer_document_evidence_jobs', { p_cluster_limit: clusterLimit })
      if (error) throw error
      return json({ ok: true, action, rule_pack: BUYER_PACK, result: data })
    }

    if (action === 'claim_buyer') {
      // Keep one research handoff deliberately small. The DB contract provides
      // leases/retries; this endpoint does not perform research or fabricate findings.
      const limit = asInt(body.limit, 4, 1, 10)
      const { data, error } = await db.rpc('internal_claim_document_evidence_jobs', {
        p_limit: limit,
        p_rule_pack: BUYER_PACK,
      })
      if (error) throw error
      return json({ ok: true, action, rule_pack: BUYER_PACK, jobs: data ?? [] })
    }

    if (action === 'complete_buyer') {
      const jobId = String(body.job_id || '')
      const outcome = String(body.outcome || '')
      const findings = body.findings ?? []
      const errorText = body.error == null ? null : String(body.error).slice(0, 4000)
      if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(jobId)) {
        return json({ ok: false, error: 'invalid_job_id' }, 400)
      }
      if (!OUTCOMES.has(outcome)) return json({ ok: false, error: 'invalid_outcome' }, 400)
      if (!Array.isArray(findings) || findings.length > 20) return json({ ok: false, error: 'invalid_findings' }, 400)

      const { data, error } = await db.rpc('internal_complete_buyer_document_evidence_job', {
        p_job_id: jobId,
        p_outcome: outcome,
        p_findings: findings,
        p_error: errorText,
      })
      if (error) throw error
      return json({ ok: true, action, rule_pack: BUYER_PACK, result: data })
    }

    if (action === 'queue_stats') {
      const { data, error } = await db
        .schema('research')
        .from('document_evidence_jobs')
        .select('state,attempt_count,priority,updated_at')
        .eq('rule_pack', BUYER_PACK)
      if (error) throw error
      const rows = Array.isArray(data) ? data : []
      const states: Record<string, number> = {}
      let ready = 0
      for (const row of rows as any[]) {
        states[row.state] = (states[row.state] || 0) + 1
        if ((row.state === 'queued' || row.state === 'failed') && Number(row.attempt_count || 0) < 2) ready++
      }
      return json({ ok: true, action, rule_pack: BUYER_PACK, total: rows.length, ready, states })
    }

    return json({ ok: false, error: 'unsupported_action' }, 400)
  } catch (error) {
    console.error(error)
    return json({ ok: false, error: error instanceof Error ? error.message : String(error) }, 500)
  }
})
