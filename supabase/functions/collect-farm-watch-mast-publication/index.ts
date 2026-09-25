import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.57.4'
import { withCollectorRun } from '../_shared/collector-runtime.ts'
import {
  KDFWR_MAST_SURVEY_INDEX_URL,
  selectMastReportUrl,
  sha256Hex,
} from '../_shared/farm-watch-kdfwr-mast-publication.ts'

function serviceKey(): string {
  try {
    const keys = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') || '{}')
    if (typeof keys.default === 'string' && keys.default) return keys.default
  } catch { /* legacy fallback */ }
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!key) throw new Error('Farm Watch mast publication service credential is unavailable')
  return key
}

const admin: any = createClient(Deno.env.get('SUPABASE_URL')!, serviceKey(), {
  auth: { persistSession: false, autoRefreshToken: false },
})

function boundedYear(value: unknown, fallback: number) {
  const year = Number(value ?? fallback)
  if (!Number.isInteger(year) || year < 2007 || year > 2100) {
    throw new Error('invalid mast survey year')
  }
  return year
}

Deno.serve(withCollectorRun('collect-farm-watch-mast-publication', async (req) => {
  try {
    const body = await req.json().catch(() => ({}))
    const surveyYear = boundedYear(body?.survey_year, new Date().getUTCFullYear())

    const response = await fetch(KDFWR_MAST_SURVEY_INDEX_URL, {
      headers: {
        accept: 'text/html,application/xhtml+xml',
        'user-agent': 'Scout-by-Cadastory/1.0',
      },
      redirect: 'follow',
      signal: AbortSignal.timeout(15_000),
    })
    if (!response.ok) {
      throw new Error(`KDFWR mast survey index returned ${response.status}`)
    }

    const html = await response.text()
    const indexSha256 = await sha256Hex(html)
    const reportUrl = selectMastReportUrl(html, surveyYear)
    const checkedAt = new Date().toISOString()

    const { data, error } = await admin.rpc(
      'farm_watch_record_mast_survey_publication_watch_v1_internal',
      {
        p_survey_year: surveyYear,
        p_index_url: KDFWR_MAST_SURVEY_INDEX_URL,
        p_index_sha256: indexSha256,
        p_discovered_report_url: reportUrl,
        p_checked_at: checkedAt,
      },
    )
    if (error) throw new Error(error.message)

    const state = data?.status || (reportUrl ? 'published_pending_ingest' : 'not_published')
    return Response.json({
      ok: true,
      targets: 1,
      stored: 1,
      survey_year: surveyYear,
      publication_status: state,
      report_url: reportUrl,
      checked_at: checkedAt,
      valid_at: checkedAt,
      index_sha256: indexSha256,
    })
  } catch (error) {
    console.error(
      'Farm Watch mast publication check failed',
      error instanceof Error ? error.message : error,
    )
    return Response.json(
      { ok: false, error: error instanceof Error ? error.message : String(error) },
      { status: 500 },
    )
  }
}))
