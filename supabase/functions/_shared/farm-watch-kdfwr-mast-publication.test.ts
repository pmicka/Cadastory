import {
  KDFWR_MAST_SURVEY_INDEX_URL,
  mastReportCandidateUrls,
  selectMastReportUrl,
} from './farm-watch-kdfwr-mast-publication.ts'

function assert(condition: unknown, message = 'assertion failed'): asserts condition {
  if (!condition) throw new Error(message)
}

Deno.test('selects current-year KDFWR mast report from relative PDF link', () => {
  const html = `
    <a href="/Hunt/Documents/2026-mast-report.pdf">2026 Mast Survey Report</a>
    <a href="/Hunt/Documents/2025-mast-report.pdf">2025 Mast Survey Report</a>
  `
  assert(
    selectMastReportUrl(html, 2026) ===
      'https://fw.ky.gov/Hunt/Documents/2026-mast-report.pdf',
  )
})

Deno.test('accepts historical underscore filename pattern', () => {
  const html = '<a href="/Hunt/Documents/mast_report_2024.pdf">2024 Mast Survey Report</a>'
  assert(
    selectMastReportUrl(html, 2024) ===
      'https://fw.ky.gov/Hunt/Documents/mast_report_2024.pdf',
  )
})

Deno.test('ignores non-PDF and off-domain candidates', () => {
  const html = `
    <a href="/Hunt/Pages/2026-mast-report.aspx">2026 Mast Report</a>
    <a href="https://example.com/2026-mast-report.pdf">2026 Mast Report</a>
  `
  assert(mastReportCandidateUrls(html, 2026).length === 0)
})

Deno.test('returns null before current-year report is listed', () => {
  const html = '<a href="/Hunt/Documents/2025-mast-report.pdf">2025 Mast Survey Report</a>'
  assert(selectMastReportUrl(html, 2026) === null)
})

Deno.test('fails closed on multiple same-year report PDFs', () => {
  const html = `
    <a href="/Hunt/Documents/2026-mast-report.pdf">2026 Mast Survey Report</a>
    <a href="/Hunt/Documents/mast_report_2026.pdf">2026 Mast Survey Report</a>
  `
  let failed = false
  try {
    selectMastReportUrl(html, 2026, KDFWR_MAST_SURVEY_INDEX_URL)
  } catch {
    failed = true
  }
  assert(failed)
})
