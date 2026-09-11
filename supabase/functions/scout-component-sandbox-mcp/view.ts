import { App, PostMessageTransport } from '@modelcontextprotocol/ext-apps'

const TOTAL_STAGES = 8
const status = document.querySelector<HTMLElement>('[data-scout-status]')
const progressLine = document.querySelector<HTMLElement>('[data-scout-progress]')
const list = document.querySelector<HTMLUListElement>('[data-scout-exemplars]')
let currentStage = 0

function progress(stage: number, message: string, state: 'pass' | 'pending' | 'fail' = 'pass') {
  currentStage = Math.max(currentStage, Math.min(stage, TOTAL_STAGES))
  if (!progressLine) return
  const prefix = state === 'fail'
    ? `Scout stopped at ${currentStage}/${TOTAL_STAGES}`
    : `Scout lifecycle ${currentStage}/${TOTAL_STAGES}`
  progressLine.textContent = `${prefix} · ${message.slice(0, 160)}`
  progressLine.dataset.state = state
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
  if (!names.length) {
    progress(8, 'Tool result contained no valid names', 'fail')
    return
  }
  if (list) {
    list.replaceChildren(...names.map((value) => {
      const item = document.createElement('li')
      const name = document.createElement('strong')
      name.textContent = value
      item.append(name)
      return item
    }))
  }
  if (status) status.textContent = 'Scout'
  progress(8, `Ready · ${names.length} names rendered`)
}

progress(1, 'View script started')
const app = new App({ name: 'scout-ui-foundation', version: '2.0.0' })
progress(2, 'SDK App created')

app.ontoolinput = () => progress(6, 'Tool input received')
app.ontoolresult = (result) => {
  const content = result?.structuredContent
  const keys = content && typeof content === 'object' ? Object.keys(content).sort().join(', ') : 'none'
  progress(7, `Tool result received · keys: ${keys}`)
  renderNames(content?.names)
}
app.onerror = (error) => {
  progress(currentStage, `SDK error: ${error instanceof Error ? error.message : String(error)}`, 'fail')
}
app.onteardown = async () => ({})
progress(3, 'Lifecycle handlers registered')

window.addEventListener('error', (event) => progress(currentStage, `Page error: ${event.message || 'unknown'}`, 'fail'))
window.addEventListener('unhandledrejection', (event) => {
  progress(currentStage, `Rejected: ${event.reason instanceof Error ? event.reason.message : String(event.reason)}`, 'fail')
})

const transport = new PostMessageTransport()
progress(4, 'Transport created', 'pending')
const pendingTimer = window.setTimeout(() => progress(4, 'SDK initialization still pending', 'pending'), 3000)

try {
  await app.connect(transport)
  window.clearTimeout(pendingTimer)
  progress(5, 'SDK initialization complete')
} catch (error) {
  window.clearTimeout(pendingTimer)
  progress(4, `SDK initialization failed: ${error instanceof Error ? error.message : String(error)}`, 'fail')
}
