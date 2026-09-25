export const KDFWR_MAST_SURVEY_INDEX_URL =
  'https://fw.ky.gov/Hunt/Pages/Deer-Hunting-Stats.aspx'

export type KdfwrMastPublicationState =
  | 'not_published'
  | 'published_pending_ingest'
  | 'ingested'

function decodeHtmlAttribute(value: string) {
  return value
    .replaceAll('&amp;', '&')
    .replaceAll('&#38;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
}

export function mastReportCandidateUrls(
  html: string,
  surveyYear: number,
  baseUrl = KDFWR_MAST_SURVEY_INDEX_URL,
): string[] {
  if (!Number.isInteger(surveyYear) || surveyYear < 2007 || surveyYear > 2100) {
    throw new Error('invalid KDFWR mast survey year')
  }

  const candidates = new Set<string>()
  const hrefPattern = /href\s*=\s*(?:"([^"]+)"|'([^']+)')/gi
  for (const match of html.matchAll(hrefPattern)) {
    const raw = decodeHtmlAttribute(String(match[1] || match[2] || '').trim())
    if (!raw) continue

    let url: URL
    try {
      url = new URL(raw, baseUrl)
    } catch {
      continue
    }

    const haystack = decodeURIComponent(url.pathname + url.search).toLowerCase()
    if (!haystack.includes(String(surveyYear))) continue
    if (!haystack.includes('mast')) continue
    if (!haystack.includes('report')) continue
    if (!url.pathname.toLowerCase().endsWith('.pdf')) continue
    if (url.hostname.toLowerCase() !== 'fw.ky.gov') continue

    candidates.add(url.toString())
  }

  return [...candidates].sort()
}

export function selectMastReportUrl(
  html: string,
  surveyYear: number,
  baseUrl = KDFWR_MAST_SURVEY_INDEX_URL,
): string | null {
  const candidates = mastReportCandidateUrls(html, surveyYear, baseUrl)
  if (!candidates.length) return null
  if (candidates.length > 1) {
    throw new Error(
      `multiple KDFWR mast report candidates found for ${surveyYear}: ${candidates.join(', ')}`,
    )
  }
  return candidates[0]
}

export async function sha256Hex(value: string) {
  const bytes = new TextEncoder().encode(value)
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))
  return [...digest].map((byte) => byte.toString(16).padStart(2, '0')).join('')
}
