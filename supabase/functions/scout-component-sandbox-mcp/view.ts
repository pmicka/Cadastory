import { App, PostMessageTransport } from '@modelcontextprotocol/ext-apps'

const status = document.querySelector<HTMLElement>('[data-scout-status]')
const detail = document.querySelector<HTMLElement>('[data-scout-detail]')
const count = document.querySelector<HTMLElement>('[data-scout-count]')
const diagnostics = document.querySelector<HTMLUListElement>('[data-scout-diagnostics]')
const list = document.querySelector<HTMLUListElement>('[data-scout-exemplars]')
const rows = new Map<string, HTMLLIElement>()

function checkpoint(id: string, state: 'pending' | 'pass' | 'fail', message: string) {
  if (!diagnostics) return
  let row = rows.get(id)
  if (!row) {
    row = document.createElement('li')
    rows.set(id, row)
    diagnostics.append(row)
  }
  const marker = state === 'pass' ? '✓' : state === 'fail' ? '✕' : '○'
  row.textContent = `${marker} ${message}`
  row.dataset.state = state
}

function cleanName(value: unknown) {
  if (typeof value !== 'string') return null
  const name = value.trim()
  return name.length > 0 && name.length <= 160 ? name : null
}

function renderNames(value: unknown) {
  const names = Array.isArray(value)
    ? value.map(cleanName).filter((name): name is string => name !== null).slice(0, 2)
    : []
  checkpoint('render', names.length ? 'pass' : 'fail', `Names rendered: ${names.length}`)
  if (status) status.textContent = names.length ? 'Scout lifecycle complete' : 'Scout tool result had no valid names'
  if (detail) detail.textContent = 'Diagnostic remains visible below.'
  if (count) count.textContent = names.length
    ? `${names.length} real Scout name${names.length === 1 ? '' : 's'} received`
    : 'No valid names were returned.'
  if (!list) return
  list.replaceChildren(...names.map((value) => {
    const item = document.createElement('li')
    const name = document.createElement('strong')
    name.textContent = value
    item.append(name)
    return item
  }))
}

checkpoint('script', 'pass', 'View script started')
const app = new App({ name: 'scout-ui-foundation', version: '2.0.0' })
checkpoint('app', 'pass', 'SDK App created')

app.ontoolinput = () => checkpoint('input', 'pass', 'Tool input received')
app.ontoolresult = (result) => {
  const content = result?.structuredContent
  const keys = content && typeof content === 'object' ? Object.keys(content).sort().join(', ') : 'none'
  checkpoint('result', 'pass', `Tool result received; keys: ${keys}`)
  renderNames(content?.names)
}
app.onerror = (error) => {
  checkpoint('sdk-error', 'fail', `SDK error: ${error instanceof Error ? error.message : String(error)}`)
  if (status) status.textContent = 'Scout lifecycle error'
}
app.onteardown = async () => {
  checkpoint('teardown', 'pass', 'Teardown requested')
  return {}
}
checkpoint('handlers', 'pass', 'Lifecycle handlers registered')

window.addEventListener('error', (event) => checkpoint('page-error', 'fail', `Page error: ${event.message || 'unknown'}`))
window.addEventListener('unhandledrejection', (event) => checkpoint('rejection', 'fail', `Rejected: ${event.reason instanceof Error ? event.reason.message : String(event.reason)}`))

const transport = new PostMessageTransport()
checkpoint('transport', 'pass', 'PostMessageTransport created')
checkpoint('connect', 'pending', 'SDK initialization handshake pending')
const pendingTimer = window.setTimeout(() => checkpoint('connect', 'pending', 'SDK initialization still pending after 3 seconds'), 3000)

try {
  await app.connect(transport)
  window.clearTimeout(pendingTimer)
  checkpoint('connect', 'pass', 'SDK initialization handshake completed')
  if (status) status.textContent = 'Scout View connected'
  if (detail) detail.textContent = 'Waiting for the tool result notification.'
} catch (error) {
  window.clearTimeout(pendingTimer)
  checkpoint('connect', 'fail', `SDK initialization failed: ${error instanceof Error ? error.message : String(error)}`)
  if (status) status.textContent = 'Scout connection failed'
}
