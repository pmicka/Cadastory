import { App, PostMessageTransport } from '@modelcontextprotocol/ext-apps'

const status = document.querySelector<HTMLElement>('[data-scout-status]')
const detail = document.querySelector<HTMLElement>('[data-scout-detail]')
const count = document.querySelector<HTMLElement>('[data-scout-count]')
const list = document.querySelector<HTMLUListElement>('[data-scout-exemplars]')

function cleanName(value: unknown) {
  if (typeof value !== 'string') return null
  const name = value.trim()
  return name.length > 0 && name.length <= 160 ? name : null
}

function renderNames(value: unknown) {
  const names = Array.isArray(value)
    ? value.map(cleanName).filter((name): name is string => name !== null).slice(0, 2)
    : []

  if (status) status.textContent = 'Scout View ready'
  if (detail) detail.textContent = 'Real Scout names reached this View through structured tool content.'
  if (count) count.textContent = names.length === 0
    ? 'No valid names were returned.'
    : `${names.length} real Scout name${names.length === 1 ? '' : 's'} received`

  if (!list) return
  const items = names.map((value) => {
    const item = document.createElement('li')
    const name = document.createElement('strong')
    name.textContent = value
    item.append(name)
    return item
  })
  list.replaceChildren(...items)
}

const app = new App({ name: 'scout-ui-foundation', version: '2.0.0' })

app.ontoolinput = () => {
  if (status) status.textContent = 'Scout View connected'
  if (detail) detail.textContent = 'Tool input received through the MCP Apps host bridge.'
}
app.ontoolresult = (result) => renderNames(result?.structuredContent?.names)
app.onerror = (error) => {
  console.error('Scout MCP Apps View error', error)
  if (status) status.textContent = 'Scout View rendered'
  if (detail) detail.textContent = 'The UI is visible, but the host bridge reported an error.'
}
app.onteardown = async () => ({})

await app.connect(new PostMessageTransport())

if (status) status.textContent = 'Scout View connected'
if (detail) detail.textContent = 'MCP Apps host bridge initialized; waiting for the tool result.'
