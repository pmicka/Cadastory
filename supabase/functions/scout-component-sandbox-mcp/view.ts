import { App, PostMessageTransport } from '@modelcontextprotocol/ext-apps'
import { normalizeScoutSandboxSingleSiteMap } from './contract.ts'
import { mountScoutSingleSiteMap, type ScoutSingleSiteMapRendererHandle } from './single_site_map_renderer.ts'

type ScoutOpportunity = {
  name: string
  address: string
  opportunity_tier: string
  opportunity_score: number
  confidence: number
  story_count: number
  height_m: number
  footprint_sqft: number
  glazing_status: string
  observed_at: string
  target_class: string
  target_subclass: string
  buyer_resolvability: string
  guardrail: string
}

const SCOUT_RASTER_TILE_TEMPLATE = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
const SCOUT_RASTER_ATTRIBUTION_LABEL = '© OpenStreetMap contributors'
const SCOUT_RASTER_ATTRIBUTION_URL = 'https://www.openstreetmap.org/copyright'

const title = document.querySelector<HTMLElement>('[data-scout-title]')
const tier = document.querySelector<HTMLElement>('[data-scout-tier]')
const meta = document.querySelector<HTMLElement>('[data-scout-meta]')
const address = document.querySelector<HTMLElement>('[data-scout-address]')
const summary = document.querySelector<HTMLElement>('[data-scout-summary]')
const guardrail = document.querySelector<HTMLElement>('[data-scout-guardrail]')
const state = document.querySelector<HTMLElement>('[data-scout-state]')
const carousel = document.querySelector<HTMLElement>('[data-scout-carousel]')
const carouselCount = document.querySelector<HTMLElement>('[data-scout-carousel-count]')
const carouselDots = Array.from(document.querySelectorAll<HTMLElement>('[data-scout-carousel-dot]'))
const mapContainer = document.querySelector<HTMLElement>('[data-scout-map]')
const mapState = document.querySelector<HTMLElement>('[data-scout-map-state]')
let mapHandle: ScoutSingleSiteMapRendererHandle | null = null
let mapGeneration = 0
let activeCarouselIndex = 0
let layoutFrame: number | null = null
let carouselResizeObserver: ResizeObserver | null = null

function setState(message: string) {
  if (state) state.textContent = message.slice(0, 200)
}

function cleanString(value: unknown, maxLength = 1000) {
  if (typeof value !== 'string') return null
  const text = value.trim()
  return text.length > 0 && text.length <= maxLength ? text : null
}

function cleanNumber(value: unknown, minimum: number, maximum: number) {
  return typeof value === 'number' && Number.isFinite(value) && value >= minimum && value <= maximum
    ? value
    : null
}

function normalizeOpportunity(value: unknown): ScoutOpportunity | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null
  const source = value as Record<string, unknown>
  const candidate: ScoutOpportunity = {
    name: cleanString(source.name, 160) ?? '',
    address: cleanString(source.address, 240) ?? '',
    opportunity_tier: cleanString(source.opportunity_tier, 64) ?? '',
    opportunity_score: cleanNumber(source.opportunity_score, 0, 100) ?? -1,
    confidence: cleanNumber(source.confidence, 0, 1) ?? -1,
    story_count: cleanNumber(source.story_count, 0, 1000) ?? -1,
    height_m: cleanNumber(source.height_m, 0, 10000) ?? -1,
    footprint_sqft: cleanNumber(source.footprint_sqft, 0, 1_000_000_000) ?? -1,
    glazing_status: cleanString(source.glazing_status, 80) ?? '',
    observed_at: cleanString(source.observed_at, 80) ?? '',
    target_class: cleanString(source.target_class, 80) ?? '',
    target_subclass: cleanString(source.target_subclass, 80) ?? '',
    buyer_resolvability: cleanString(source.buyer_resolvability, 120) ?? '',
    guardrail: cleanString(source.guardrail, 1000) ?? '',
  }
  return candidate.name &&
      candidate.address &&
      candidate.opportunity_tier &&
      candidate.opportunity_score >= 0 &&
      candidate.confidence >= 0 &&
      Number.isInteger(candidate.story_count) && candidate.story_count >= 0 &&
      candidate.height_m >= 0 &&
      candidate.footprint_sqft >= 0 &&
      candidate.glazing_status &&
      candidate.observed_at &&
      candidate.target_class &&
      candidate.target_subclass &&
      candidate.buyer_resolvability &&
      candidate.guardrail
    ? candidate
    : null
}

function label(value: string) {
  const known: Record<string, string> = {
    very_high: 'Very high',
    office_highrise: 'Office high-rise',
    corporate_office: 'Corporate office',
    confirmed_glazed: 'Confirmed glazed facade',
    public_operator_or_site_route: 'Public operator / site route',
  }
  return known[value] ?? value.replaceAll('_', ' ').replace(/^./, (character) => character.toUpperCase())
}

function formatObserved(value: string) {
  const date = new Date(value)
  if (Number.isNaN(date.valueOf())) return value
  return new Intl.DateTimeFormat('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  }).format(date)
}

function formatNumber(value: number, maximumFractionDigits = 0) {
  return new Intl.NumberFormat('en-US', { maximumFractionDigits }).format(value)
}

function renderOpportunity(value: unknown) {
  const opportunity = normalizeOpportunity(value)
  if (!opportunity) {
    if (title) title.textContent = 'Opportunity unavailable'
    if (tier) tier.textContent = 'Unavailable'
    if (meta) meta.textContent = 'Scout did not receive a valid bounded opportunity result.'
    if (address) address.textContent = ''
    if (summary) summary.textContent = ''
    if (guardrail) guardrail.textContent = ''
    setState('Scout opportunity result failed validation')
    return
  }

  if (title) title.textContent = opportunity.name
  if (tier) tier.textContent = label(opportunity.opportunity_tier)
  if (meta) {
    meta.textContent = `Score ${opportunity.opportunity_score}  •  ${Math.round(opportunity.confidence * 100)}% confidence  •  Observed ${formatObserved(opportunity.observed_at)}`
  }
  if (address) address.textContent = opportunity.address
  if (summary) {
    summary.textContent = `${label(opportunity.target_subclass)}  •  ${label(opportunity.target_class)}  •  ${label(opportunity.glazing_status)}  •  ${opportunity.story_count} stories  •  ${formatNumber(opportunity.height_m, 1)} m  •  ${formatNumber(opportunity.footprint_sqft)} sq ft  •  ${label(opportunity.buyer_resolvability)}`
  }
  if (guardrail) guardrail.textContent = `Scout guardrail: ${opportunity.guardrail}`
  setState(`Scout opportunity ready: ${opportunity.name}`)
}

function destroyMap() {
  mapGeneration += 1
  mapHandle?.destroy()
  mapHandle = null
}

function renderMap(value: unknown) {
  const mapData = normalizeScoutSandboxSingleSiteMap(value)
  destroyMap()
  if (!mapContainer || !mapState) return
  if (!mapData) {
    mapState.hidden = false
    mapState.textContent = 'Site map unavailable'
    setState('Scout single-site map result failed validation')
    return
  }

  const generation = ++mapGeneration
  let ready = false
  mapState.hidden = false
  mapState.textContent = 'Loading site map…'
  mapContainer.setAttribute('role', 'img')
  mapContainer.setAttribute('aria-label', `Site map for ${mapData.name}`)

  try {
    mapHandle = mountScoutSingleSiteMap(mapContainer, mapData, {
      tileUrlTemplate: SCOUT_RASTER_TILE_TEMPLATE,
      attributionLabel: SCOUT_RASTER_ATTRIBUTION_LABEL,
      attributionUrl: SCOUT_RASTER_ATTRIBUTION_URL,
      onReady: () => {
        if (generation !== mapGeneration) return
        ready = true
        mapState.hidden = true
        setState(`Scout site map ready: ${mapData.name}`)
      },
      onError: (error) => {
        if (generation !== mapGeneration) return
        if (!ready) {
          mapState.hidden = false
          mapState.textContent = 'Site map unavailable'
        }
        setState(`Scout map error: ${error.message}`)
      },
    })
    scheduleLayoutRefresh()
  } catch (error) {
    mapState.hidden = false
    mapState.textContent = 'Site map unavailable'
    setState(`Scout map initialization failed: ${error instanceof Error ? error.message : String(error)}`)
  }
}

function updateCarouselState() {
  if (!carousel || !carouselCount || carouselDots.length === 0) return
  const slides = Array.from(carousel.querySelectorAll<HTMLElement>('.media-slide'))
  if (slides.length === 0) return
  const viewportCenter = carousel.scrollLeft + carousel.clientWidth / 2
  let active = 0
  let bestDistance = Number.POSITIVE_INFINITY
  for (let index = 0; index < slides.length; index += 1) {
    const slide = slides[index]
    const center = slide.offsetLeft + slide.offsetWidth / 2
    const distance = Math.abs(center - viewportCenter)
    if (distance < bestDistance) {
      bestDistance = distance
      active = index
    }
  }
  activeCarouselIndex = active
  carouselCount.textContent = `${active + 1} / ${slides.length}`
  for (let index = 0; index < carouselDots.length; index += 1) {
    carouselDots[index].dataset.active = String(index === active)
  }
}

function alignCarouselToActiveSlide() {
  if (!carousel || carousel.clientWidth <= 0) return
  const targetScrollLeft = activeCarouselIndex * carousel.clientWidth
  if (Math.abs(carousel.scrollLeft - targetScrollLeft) > 1) {
    carousel.scrollLeft = targetScrollLeft
  }
}

function flushLayoutRefresh() {
  layoutFrame = null
  alignCarouselToActiveSlide()
  mapHandle?.resize()
  updateCarouselState()
}

function scheduleLayoutRefresh() {
  if (layoutFrame !== null) return
  layoutFrame = requestAnimationFrame(flushLayoutRefresh)
}

function handleResize() {
  scheduleLayoutRefresh()
}

carousel?.addEventListener('scroll', updateCarouselState, { passive: true })
window.addEventListener('resize', handleResize, { passive: true })
if (carousel && typeof ResizeObserver !== 'undefined') {
  carouselResizeObserver = new ResizeObserver(() => scheduleLayoutRefresh())
  carouselResizeObserver.observe(carousel)
}
updateCarouselState()

const app = new App({ name: 'scout-ui-foundation', version: '2.3.0' })
app.ontoolinput = () => setState('Scout tool input received')
app.ontoolresult = (result) => {
  renderOpportunity(result?.structuredContent?.opportunity)
  renderMap(result?.structuredContent?.map)
}
app.onhostcontextchanged = () => scheduleLayoutRefresh()
app.onerror = (error) => setState(`Scout SDK error: ${error instanceof Error ? error.message : String(error)}`)
app.onteardown = async () => {
  window.removeEventListener('resize', handleResize)
  carouselResizeObserver?.disconnect()
  carouselResizeObserver = null
  if (layoutFrame !== null) {
    cancelAnimationFrame(layoutFrame)
    layoutFrame = null
  }
  destroyMap()
  return {}
}

const transport = new PostMessageTransport()
try {
  await app.connect(transport)
  setState('Scout SDK connected; waiting for opportunity result')
} catch (error) {
  setState(`Scout SDK initialization failed: ${error instanceof Error ? error.message : String(error)}`)
}
