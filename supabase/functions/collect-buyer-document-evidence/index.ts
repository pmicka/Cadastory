import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.57.4'

const SLUG = 'collect-buyer-document-evidence'
const url = Deno.env.get('SUPABASE_URL')!
let serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
try {
  serviceKey = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') || '{}').default || serviceKey
} catch { /* legacy service-role secret remains supported */ }
if (!url || !serviceKey) throw new Error('Scout database credentials unavailable')

const db = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } })
const MAX_BODY_BYTES = 32 * 1024
const SEARCH_ENDPOINT = 'https://api.tavily.com/search'
const MAX_FETCH_BYTES = 1_500_000
const BLOCKED_IDENTITY_DOMAINS = new Set([
  'facebook.com','linkedin.com','instagram.com','x.com','twitter.com','yelp.com','bbb.org',
  'mapquest.com','buildzoom.com','manta.com','chamberofcommerce.com','yellowpages.com'
])
const GENERIC_EMAIL_LOCAL = /^(info|contact|office|sales|estimating|estimate|bids?|bidroom|procurement|purchasing|vendor|vendors|supplier|facilities|maintenance|service|support|admin|hello)$/i
const DISCOVERY_PATH = /(contact|procure|purchas|vendor|supplier|subcontract|bid|estimating|facilit|maintenance|service)/i

type AnyObj = Record<string, any>
type Job = {
  id: string
  cluster_key?: string
  display_name?: string | null
  organization_name: string
  search_query?: string | null
  source_roots?: unknown
  context?: AnyObj
  attempt_count?: number
  max_attempts?: number
}
type Route = {
  contact_scope: string
  channel_type: 'phone' | 'email' | 'url'
  contact_value: string
  stability_class: 'institutional' | 'departmental'
  confidence: number
  label?: string
  department_name?: string
}
type Page = { url: string; title: string; text: string; html: string; routes: Route[]; follow: string[] }

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store, max-age=0',
      'pragma': 'no-cache',
      'x-content-type-options': 'nosniff',
    },
  })
}

function errorText(value: unknown) {
  return String(value instanceof Error ? value.message : value)
    .replace(/Bearer\s+[A-Za-z0-9_.-]+/gi, 'Bearer [REDACTED]')
    .replace(/tvly-[A-Za-z0-9_-]+/g, '[REDACTED]')
    .replace(/sb_secret_[A-Za-z0-9_-]+/g, '[REDACTED]')
    .slice(0, 1200)
}

function asInt(v: unknown, fallback: number, min: number, max: number) {
  const n = Number(v)
  return Number.isFinite(n) ? Math.max(min, Math.min(max, Math.floor(n))) : fallback
}

function roots(v: unknown): string[] {
  if (!Array.isArray(v)) return []
  return [...new Set(v.map(String).filter(x => /^https?:\/\//i.test(x)))].slice(0, 8)
}

function normalizeName(v: string) {
  return String(v || '').toLowerCase().replace(/&/g, 'and').replace(/[^a-z0-9]+/g, '')
}

function titleMentionsName(title: string, name: string) {
  const n = normalizeName(name)
  return n.length >= 4 && normalizeName(title).includes(n)
}

function sourceMentionsName(source: string, name: string) {
  const n = normalizeName(name)
  return n.length >= 4 && normalizeName(source.slice(0, 40000)).includes(n)
}

function domainOf(raw: string) {
  try { return new URL(raw).hostname.toLowerCase().replace(/^www\./, '') } catch { return '' }
}

function identityDomainAllowed(raw: string) {
  const d = domainOf(raw)
  if (!d) return false
  return ![...BLOCKED_IDENTITY_DOMAINS].some(x => d === x || d.endsWith(`.${x}`))
}

function domainFitsName(raw: string, name: string) {
  const d = domainOf(raw).replace(/[^a-z0-9]/g, '')
  const ignored = new Set(['the','and','inc','llc','ltd','corp','corporation','company','co','group','services','service'])
  const tokens = name.toLowerCase().replace(/&/g, ' and ').split(/[^a-z0-9]+/)
    .filter(x => x.length >= 4 && !ignored.has(x))
  return tokens.some(t => d.includes(t))
}

function decodeHtml(s: string) {
  return s
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'")
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&#(\d+);/g, (_, n) => String.fromCharCode(Number(n)))
}

function htmlToText(html: string) {
  return decodeHtml(html
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, ' ')
    .replace(/<noscript\b[^>]*>[\s\S]*?<\/noscript>/gi, ' ')
    .replace(/<[^>]+>/g, ' '))
    .replace(/\s+/g, ' ')
    .trim()
}

function extractTitle(html: string) {
  const m = html.match(/<title\b[^>]*>([\s\S]*?)<\/title>/i)
  return m ? htmlToText(m[1]).slice(0, 300) : ''
}

function scopeFor(raw: string) {
  const s = raw.toLowerCase()
  if (/(supplier|vendor|subcontract|registration|register)/.test(s)) return 'supplier_registration'
  if (/(procure|purchas|bid|estimating)/.test(s)) return 'procurement'
  if (/(facilit|maintenance|physical plant)/.test(s)) return 'facilities'
  return 'other'
}

function routeKey(r: Route) { return `${r.contact_scope}|${r.channel_type}|${r.contact_value}` }

function extractRoutes(baseUrl: string, html: string, text: string) {
  const routes = new Map<string, Route>()
  const follow = new Set<string>()
  const baseDomain = domainOf(baseUrl)

  for (const match of html.matchAll(/<a\b[^>]*href\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi)) {
    const href = decodeHtml(match[1]).trim()
    const label = htmlToText(match[2]).slice(0, 200)
    if (!href || /^(javascript:|mailto:|tel:|#)/i.test(href)) continue
    let resolved = ''
    try { resolved = new URL(href, baseUrl).toString() } catch { continue }
    if (domainOf(resolved) !== baseDomain) continue
    const signal = `${resolved} ${label}`
    if (!DISCOVERY_PATH.test(signal)) continue
    follow.add(resolved)
    const route: Route = {
      contact_scope: scopeFor(signal),
      channel_type: 'url',
      contact_value: resolved,
      stability_class: 'institutional',
      confidence: 0.82,
      label: label || 'Public organization route',
    }
    routes.set(routeKey(route), route)
  }

  for (const match of text.matchAll(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi)) {
    const email = match[0].toLowerCase()
    const local = email.split('@')[0]
    if (!GENERIC_EMAIL_LOCAL.test(local)) continue
    const around = text.slice(Math.max(0,(match.index || 0)-100),(match.index || 0)+email.length+100)
    const route: Route = {
      contact_scope: scopeFor(around),
      channel_type: 'email',
      contact_value: email,
      stability_class: scopeFor(around)==='procurement' ? 'departmental' : 'institutional',
      confidence: 0.84,
      label: 'Published generic organization email',
    }
    routes.set(routeKey(route), route)
  }

  for (const match of text.matchAll(/(?:\+?1[ .-]?)?\(?\d{3}\)?[ .-]\d{3}[ .-]\d{4}/g)) {
    const value = match[0].trim()
    const digits = value.replace(/\D/g, '')
    if (![10,11].includes(digits.length)) continue
    const around = text.slice(Math.max(0,(match.index || 0)-80),(match.index || 0)+value.length+80)
    if (/fax/i.test(around) || !/(phone|tel|call|office|contact|main)/i.test(around)) continue
    const route: Route = {
      contact_scope: 'general_switchboard',
      channel_type: 'phone',
      contact_value: value,
      stability_class: 'institutional',
      confidence: 0.82,
      label: 'Published main/public phone',
    }
    routes.set(routeKey(route), route)
  }

  return { routes: [...routes.values()].slice(0, 8), follow: [...follow].slice(0, 4) }
}

async function fetchPage(raw: string): Promise<Page> {
  const u = new URL(raw)
  if (!['http:','https:'].includes(u.protocol)) throw new Error('unsupported source URL')
  const res = await fetch(u.toString(), {
    redirect: 'follow',
    signal: AbortSignal.timeout(10000),
    headers: { 'accept': 'text/html,text/plain;q=0.9,*/*;q=0.5', 'user-agent': 'Scout-by-Cadastory/1.0 buyer-evidence' },
  })
  if (!res.ok) throw new Error(`source HTTP ${res.status}`)
  const contentLength = Number(res.headers.get('content-length') || 0)
  if (contentLength > MAX_FETCH_BYTES) throw new Error('source too large')
  const html = (await res.text()).slice(0, MAX_FETCH_BYTES)
  const text = htmlToText(html)
  const title = extractTitle(html)
  const extracted = extractRoutes(res.url || raw, html, text)
  return { url: res.url || raw, title, text, html, routes: extracted.routes, follow: extracted.follow }
}

async function inspectSite(seed: string, orgName: string, requireIdentity: boolean): Promise<Page | null> {
  let first: Page
  try { first = await fetchPage(seed) } catch { return null }
  const firstSource = `${first.title}\n${first.text}`
  const firstIdentity = sourceMentionsName(firstSource, orgName)
  if ((!requireIdentity || firstIdentity) && first.routes.length > 0) return first

  for (const next of first.follow.slice(0, 3)) {
    try {
      const page = await fetchPage(next)
      const source = `${page.title}\n${page.text}`
      if (requireIdentity && !sourceMentionsName(source, orgName)) continue
      if (page.routes.length > 0) return page
      if (!requireIdentity || sourceMentionsName(source, orgName)) first = page
    } catch { /* bounded best effort */ }
  }
  if (!requireIdentity || sourceMentionsName(`${first.title}\n${first.text}`, orgName)) return first
  return null
}

async function tavilySearch(query: string, apiKey: string) {
  const res = await fetch(SEARCH_ENDPOINT, {
    method: 'POST',
    signal: AbortSignal.timeout(12000),
    headers: { 'content-type': 'application/json', 'authorization': `Bearer ${apiKey}` },
    body: JSON.stringify({
      query,
      topic: 'general',
      search_depth: 'basic',
      max_results: 5,
      include_answer: false,
      include_raw_content: false,
      include_images: false,
    }),
  })
  const text = await res.text()
  if (!res.ok) throw new Error(`search provider HTTP ${res.status}: ${text.slice(0,300)}`)
  const body = JSON.parse(text)
  return Array.isArray(body?.results) ? body.results : []
}

async function findOfficialSite(job: Job, apiKey: string): Promise<Page | null> {
  const name = job.organization_name
  const query = String(job.search_query || `"${name}" official website contact procurement vendor`)
  const results = await tavilySearch(query, apiKey)
  for (const result of results.slice(0, 5)) {
    const candidate = String(result?.url || '')
    if (!/^https?:\/\//i.test(candidate) || !identityDomainAllowed(candidate)) continue
    if (Number(result?.score ?? 0) < 0.45) continue
    let page: Page | null = null
    try { page = await inspectSite(candidate, name, true) } catch { page = null }
    if (!page) continue
    const source = `${page.title}\n${page.text}`
    if (!sourceMentionsName(source, name)) continue
    if (!titleMentionsName(page.title || String(result?.title || ''), name) && !domainFitsName(page.url, name)) continue
    return page
  }
  return null
}

async function sha256(value: string) {
  const bytes = new TextEncoder().encode(value)
  const digest = await crypto.subtle.digest('SHA-256', bytes)
  return [...new Uint8Array(digest)].map(x => x.toString(16).padStart(2,'0')).join('')
}

async function complete(jobId: string, outcome: string, findings: AnyObj[], error: string | null = null) {
  const { data, error: rpcError } = await db.rpc('internal_complete_buyer_document_evidence_job', {
    p_job_id: jobId,
    p_outcome: outcome,
    p_findings: findings,
    p_error: error,
  })
  if (rpcError) throw new Error(`completion: ${rpcError.message}`)
  return data
}

async function processJob(job: Job, apiKey: string | null) {
  const orgName = String(job.organization_name || '').trim()
  if (!orgName) return complete(job.id, 'needs_review', [], 'generic buyer worker requires a named organization')

  const contextOrgId = String(job.context?.organization_id || '') || null
  let page: Page | null = null
  let discovery: 'source_root' | 'search' = 'source_root'

  for (const root of roots(job.source_roots)) {
    page = await inspectSite(root, orgName, contextOrgId == null)
    if (page?.routes.length) break
    if (page && contextOrgId == null) break
  }

  if ((!page || page.routes.length === 0) && apiKey) {
    const searched = await findOfficialSite(job, apiKey)
    if (searched) { page = searched; discovery = 'search' }
  }

  if (!page) {
    return complete(job.id, 'no_evidence', [], apiKey ? 'no supported first-party organization source found' : 'no supported evidence in configured source roots')
  }

  const sourceText = `${page.title}\n${page.text}`.slice(0, 3500)
  const identitySupported = sourceMentionsName(sourceText, orgName)
  if (!identitySupported && !contextOrgId) {
    return complete(job.id, 'needs_review', [], 'candidate source did not establish the named organization')
  }

  let orgId = contextOrgId
  let orgResolution: AnyObj | null = null
  if (!orgId) {
    const firstPhone = page.routes.find(x => x.channel_type === 'phone')?.contact_value || null
    const website = `${new URL(page.url).origin}/`
    const { data, error } = await db.rpc('internal_resolve_or_create_buyer_research_organization_v1', {
      p_job_id: job.id,
      p_canonical_name: orgName,
      p_website_url: website,
      p_phone: firstPhone,
      p_source_url: page.url,
      p_source_authority: 'First-party organization website (automated exact-name verification)',
      p_identity_confidence: 0.96,
      p_evidence_excerpt: sourceText,
    })
    if (error) {
      return complete(job.id, 'needs_review', [], `organization identity requires review: ${error.message}`)
    }
    orgResolution = data || null
    if (data?.status === 'ambiguous_existing_organization') {
      return complete(job.id, 'needs_review', [], 'multiple existing organizations match the researched buyer name')
    }
    orgId = String(data?.organization_id || '') || null
    if (!orgId) return complete(job.id, 'needs_review', [], 'organization identity could not be made durable')
  }

  const identityConfidence = contextOrgId ? (identitySupported ? 0.99 : 0.90) : 0.96
  const routes = identityConfidence >= 0.95 ? page.routes : []
  const fingerprint = await sha256(`${page.url}|${orgName}|${JSON.stringify(routes)}`)
  const findings = [{
    fingerprint,
    source_url: page.url,
    source_authority: contextOrgId ? 'Documented organization source root' : 'First-party organization website (automated exact-name verification)',
    source_kind: 'public_web_page',
    document_title: page.title || null,
    evidence_excerpt: sourceText,
    evidence_codes: routes.length ? ['buyer_identity_documented','public_contact_route'] : ['buyer_identity_documented'],
    extracted_values: {
      organization_name: orgName,
      organization_id: orgId,
      website_url: `${new URL(page.url).origin}/`,
      contact_routes: routes,
      discovery_method: discovery,
      buyer_authority_not_implied: true,
    },
    confidence: routes.length ? 0.91 : 0.88,
    identity_confidence: identityConfidence,
    decision_state: identityConfidence >= 0.95 ? 'documented' : 'signal_to_investigate',
    observed_at: new Date().toISOString(),
    auto_apply: routes.length > 0 && identityConfidence >= 0.95,
  }]

  // Existing organizations with no newly documented route remain research work.
  // A newly resolved organization may complete identity-only; the next seed pass
  // will create an organization-scoped job if contact/procurement remains open.
  const outcome = routes.length > 0 || !contextOrgId ? 'completed' : 'no_evidence'
  const result = await complete(job.id, outcome, findings, routes.length ? null : 'organization documented but no supported public route found')
  return { ...result, organization_resolution: orgResolution, discovery_method: discovery, routes_found: routes.length }
}

async function authorized(req: Request) {
  const key = req.headers.get('x-scout-key') || ''
  if (!key) return false
  const { data, error } = await db.rpc('internal_validate_collector_key', { p_key: key })
  return !error && data === true
}

async function beginRun(limit: number) {
  const { data, error } = await db.rpc('internal_begin_collector_run', {
    p_slug: SLUG,
    p_request_summary: { limit },
  })
  if (error || !data) throw new Error('collector run could not be recorded')
  return String(data)
}

async function finishRun(runId: string, status: 'succeeded'|'failed'|'no_work', httpStatus: number, summary: AnyObj) {
  const { error } = await db.rpc('internal_finish_collector_run', {
    p_run_id: runId,
    p_status: status,
    p_http_status: httpStatus,
    p_summary: summary,
  })
  if (error) throw new Error('collector result could not be recorded')
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return json({ error: 'POST required' }, 405)
  if (!await authorized(req)) return json({ error: 'unauthorized' }, 401)

  const declared = Number(req.headers.get('content-length') || 0)
  if (declared > MAX_BODY_BYTES) return json({ error: 'request_too_large' }, 413)
  const raw = await req.text()
  if (new TextEncoder().encode(raw).byteLength > MAX_BODY_BYTES) return json({ error: 'request_too_large' }, 413)
  let body: AnyObj = {}
  try { body = JSON.parse(raw || '{}') } catch { return json({ error: 'invalid_json' }, 400) }
  const limit = asInt(body.limit, 4, 1, 6)

  let runId = ''
  try {
    runId = await beginRun(limit)
    const provider = await db.rpc('internal_get_buyer_research_provider_v1')
    if (provider.error) throw new Error(`provider config: ${provider.error.message}`)
    const configured = provider.data?.configured === true && typeof provider.data?.api_key === 'string'
    const apiKey = configured ? String(provider.data.api_key) : null

    const claimed = await db.rpc('internal_claim_buyer_web_research_jobs_v1', {
      p_limit: limit,
      p_search_available: configured,
    })
    if (claimed.error) throw new Error(`claim: ${claimed.error.message}`)
    const jobs: Job[] = Array.isArray(claimed.data) ? claimed.data : []

    if (jobs.length === 0) {
      const summary = { outcome: 'no_work', counts: { attempted: 0, succeeded: 0, failed: 0 }, provider: configured ? 'tavily' : 'source_roots_only' }
      await finishRun(runId, 'no_work', 200, summary)
      return json({ ok: true, outcome: 'no_work', run_id: runId, claimed: 0, processed: [], provider: summary.provider })
    }

    const processed: AnyObj[] = []
    for (const job of jobs) {
      try {
        const result = await processJob(job, apiKey)
        processed.push({ job_id: job.id, organization_name: job.organization_name, status: 'succeeded', result })
      } catch (error) {
        const message = errorText(error)
        try {
          const result = await complete(job.id, 'failed', [], message)
          processed.push({ job_id: job.id, organization_name: job.organization_name, status: 'succeeded', result, worker_error: message })
        } catch (completionError) {
          throw new Error(`${message}; failure completion also failed: ${errorText(completionError)}`)
        }
      }
    }

    const summary = {
      outcome: 'succeeded',
      counts: { attempted: jobs.length, succeeded: processed.length, failed: 0 },
      provider: configured ? 'tavily' : 'source_roots_only',
      search_configured: configured,
    }
    await finishRun(runId, 'succeeded', 200, summary)
    return json({ ok: true, outcome: 'succeeded', run_id: runId, claimed: jobs.length, processed, provider: summary.provider, search_configured: configured })
  } catch (error) {
    const message = errorText(error)
    if (runId) {
      try { await finishRun(runId, 'failed', 500, { outcome: 'failed', counts: { attempted: null, succeeded: null, failed: 1 }, errors: [message] }) } catch { /* preserve primary error */ }
    }
    console.error(message)
    return json({ ok: false, outcome: 'failed', run_id: runId || null, error: message }, 500)
  }
})
