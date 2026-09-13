// Temporary owner-approved diagnostics. Remove after the host reproduction.
export type DiagnosticValue = string | number | boolean
const report: Record<string, DiagnosticValue> = {
  build: 'swppp-transport-v1-20260913',
  resource: (typeof document === 'undefined' ? undefined : document.querySelector<HTMLMetaElement>('meta[name="scout-diagnostic-resource"]')?.content) ?? 'missing',
}
export function diagnostic(fields: Record<string, DiagnosticValue>) {
  Object.assign(report, fields)
  const output = document.querySelector('[data-scout-diagnostic-report]')
  if (output) output.textContent = Object.entries(report).map(([key, value]) => `${key}: ${value}`).join('\n')
}
export function diagnosticError(error: unknown) {
  const name = error instanceof Error || (typeof DOMException !== 'undefined' && error instanceof DOMException) ? error.name : ''
  return ['InvalidCharacterError', 'InvalidStateError', 'NotSupportedError', 'SecurityError', 'TypeError', 'ReferenceError', 'RangeError', 'AbortError'].includes(name) ? name : 'other'
}
export function diagnosticOverlay(element: HTMLElement) {
  const style = getComputedStyle(element)
  diagnostic({ overlayHidden: element.hidden, overlayDisplay: style.display === 'none' ? 'none' : 'visible', overlayVisibility: style.visibility === 'hidden' ? 'hidden' : 'visible' })
}
