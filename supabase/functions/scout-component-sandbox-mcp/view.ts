import { diagnostic, diagnosticError, diagnosticOverlay } from './map_diagnostics.ts'
import { App, PostMessageTransport } from '@modelcontextprotocol/ext-apps'
import {
  SCOUT_SANDBOX_MAX_EMBEDDED_RASTER_TILES,
  isScoutSandboxOpportunityType,
  isScoutSandboxSingleSiteType,
  isScoutSandboxSpineSingleAssetType,
  isScoutSandboxPortfolioType,
  type ScoutSandboxOpportunityType as ScoutViewOpportunityType,
} from '../_shared/scout_sandbox_manifest.ts'
import { scoutSandboxPortfolioImplementation } from './portfolio_registry.ts'
import { scoutSandboxPortfolioViewImplementation } from './portfolio_view_registry.ts'
import { scoutSandboxSingleSiteViewImplementation } from './single_site_view_registry.ts'
import {
  normalizeScoutSandboxOpportunity,
  type ScoutSandboxOpportunityType,
  type ScoutSandboxWaterTankOpportunity,
} from './contract.ts'
import { normalizeScoutSandboxTelecomChangeOpportunity } from './telecom_change_map_model.ts'
import { normalizeScoutSandboxSwpppSiteOpportunity } from './swppp_site_map_model.ts'
import { normalizeScoutSandboxSpineSingleAssetOpportunity } from './spine_single_asset_model.ts'

type ScoutMapHandle = {
  destroy: () => void
  resize: () => void
}


const SCOUT_RASTER_TILE_TEMPLATE = 'https://ufpkjaadmmpmeogzhrcq.supabase.co/functions/v1/scout-component-sandbox-mcp/map-tile/{z}/{x}/{y}.png'
const SCOUT_RASTER_ATTRIBUTION_LABEL = '© OpenStreetMap contributors · HOT'
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
let mapHandle: ScoutMapHandle | null = null
let mapGeneration = 0
let activeCarouselIndex = 0
let diagnosticResultCount = 0
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

function normalizeEmbeddedTiles(value: unknown) {
  if (!Array.isArray(value) || value.length > SCOUT_SANDBOX_MAX_EMBEDDED_RASTER_TILES) return undefined
  const tiles: Record<string, string> = {}
  for (const item of value) {
    if (!item || typeof item !== 'object' || Array.isArray(item)) return undefined
    const source = item as Record<string, unknown>
    const url = cleanString(source.url, 1000)
    const dataUrl = cleanString(source.data_url, 200_000)
    if (!url?.includes('/scout-component-sandbox-mcp/map-tile/') || !dataUrl?.startsWith('data:image/png;base64,')) return undefined
    tiles[url] = dataUrl
  }
  return Object.keys(tiles).length ? tiles : undefined
}

const resourceEmbeddedTiles = (() => {
  const element = document.getElementById('scout-embedded-raster-tiles')
  diagnostic({ jsonElement: Boolean(element), jsonParse: 'not_attempted', embeddedValidCount: 0 })
  if (!element) return undefined
  try {
    const parsed = JSON.parse(element.textContent ?? '')
    const normalized = normalizeEmbeddedTiles(parsed)
    diagnostic({ jsonParse: 'passed', embeddedValidation: normalized ? 'passed' : 'empty_or_rejected', embeddedValidCount: normalized ? Object.keys(normalized).length : 0 })
    return normalized
  } catch {
    diagnostic({ jsonParse: 'failed' })
    return undefined
  }
})()

function normalizeWaterTankOpportunity(value: unknown): ScoutSandboxWaterTankOpportunity | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null
  const source = value as Record<string, unknown>
  const name = cleanString(source.name, 160)
  const systemName = cleanString(source.system_name, 200)
  const confidence = cleanNumber(source.confidence, 0, 1)
  const observedAt = cleanString(source.observed_at, 80)
  const capacityGallons = cleanNumber(source.capacity_gallons, 1, 100_000_000)
  const morphologyClass = cleanString(source.morphology_class, 120)
  const projectPurpose = cleanString(source.project_purpose, 300)
  const opportunityGuardrail = cleanString(source.guardrail, 1000)

  if (source.opportunity_type !== 'water_tank' || source.status !== 'rehab_signal') return null
  if (!name || !systemName || confidence === null || !observedAt || capacityGallons === null) return null
  if (source.tank_type !== 'ELEVATED' || !morphologyClass || source.support_geometry !== 'single_pedestal') return null
  if (source.operator_assessment !== 'favorable' || source.project_status !== 'REHAB' || !projectPurpose || !opportunityGuardrail) return null

  return {
    opportunity_type: 'water_tank',
    name,
    system_name: systemName,
    status: 'rehab_signal',
    confidence,
    observed_at: observedAt,
    tank_type: 'ELEVATED',
    capacity_gallons: capacityGallons,
    morphology_class: morphologyClass,
    support_geometry: 'single_pedestal',
    operator_assessment: 'favorable',
    project_status: 'REHAB',
    project_purpose: projectPurpose,
    guardrail: opportunityGuardrail,
  }
}

function label(value: string) {
  const known: Record<string, string> = {
    very_high: 'Very high',
    office_highrise: 'Office high-rise',
    corporate_office: 'Corporate office',
    confirmed_glazed: 'Confirmed glazed facade',
    public_operator_or_site_route: 'Public operator / site route',
    rehab_signal: 'Rehab signal',
    composite_elevated: 'Composite elevated',
    single_pedestal: 'Single pedestal',
    favorable: 'Favorable cleaning geometry',
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
    timeZone: 'UTC',
  }).format(date)
}

function formatNumber(value: number, maximumFractionDigits = 0) {
  return new Intl.NumberFormat('en-US', { maximumFractionDigits }).format(value)
}

function renderUnavailableOpportunity() {
  if (title) title.textContent = 'Opportunity unavailable'
  if (tier) tier.textContent = 'Unavailable'
  if (meta) meta.textContent = 'Scout did not receive a valid bounded opportunity result.'
  if (address) address.textContent = ''
  if (summary) summary.textContent = ''
  if (guardrail) guardrail.textContent = ''
  setState('Scout opportunity result failed validation')
}

function renderOpportunity(opportunityType: ScoutViewOpportunityType, value: unknown) {
  if (isScoutSandboxPortfolioType(opportunityType)) {
    const implementation = scoutSandboxPortfolioImplementation(opportunityType)
    const opportunity = implementation.normalizeOpportunity(value)
    if (!opportunity) { renderUnavailableOpportunity(); return }
    const presentation = scoutSandboxPortfolioViewImplementation(opportunityType).presentation(opportunity)
    if (title) title.textContent = presentation.title
    if (tier) tier.textContent = presentation.tier
    if (meta) meta.textContent = presentation.meta
    if (address) address.textContent = presentation.address
    if (summary) summary.textContent = presentation.summary
    if (guardrail) guardrail.textContent = presentation.guardrail
    setState(presentation.state)
    return
  }

  if (isScoutSandboxSpineSingleAssetType(opportunityType)) {
    const opportunity = normalizeScoutSandboxSpineSingleAssetOpportunity(opportunityType, value)
    if (!opportunity) { renderUnavailableOpportunity(); return }
    if (title) title.textContent = opportunity.name
    if (tier) tier.textContent = opportunity.status_label
    if (meta) meta.textContent = `${Math.round(opportunity.confidence * 100)}% Scout signal confidence  •  Observed ${formatObserved(opportunity.observed_at)}`
    if (address) address.textContent = opportunity.location_label
    if (summary) summary.textContent = `${opportunity.facts.map((fact) => `${fact.label}: ${fact.value}`).join('  •  ')}  •  ${opportunity.why_investigate}`
    if (guardrail) guardrail.textContent = `Scout guardrail: ${opportunity.guardrail}`
    setState(`Scout opportunity ready: ${opportunity.name}`)
    return
  }

  if (opportunityType === 'swppp_site') {
    const opportunity = normalizeScoutSandboxSwpppSiteOpportunity(value)
    if (!opportunity) {
      renderUnavailableOpportunity()
      return
    }
    if (title) title.textContent = opportunity.name
    if (tier) tier.textContent = 'Active permit evidence'
    if (meta) meta.textContent = `Ohio EPA source updated ${formatObserved(opportunity.observed_at)}  •  Permit expires ${formatObserved(opportunity.permit_expiration_date)}`
    if (address) address.textContent = opportunity.location_label
    if (summary) summary.textContent = `Construction stormwater  •  ${formatNumber(opportunity.documented_total_acres)} documented permit acres  •  Permit ${opportunity.permit_number}  •  ${opportunity.project_reference}  •  Buyer unresolved  •  ${opportunity.why_investigate}`
    if (guardrail) guardrail.textContent = `Scout guardrail: ${opportunity.guardrail}`
    setState(`Scout opportunity ready: ${opportunity.name}`)
    return
  }

  if (opportunityType === 'water_tank') {
    const opportunity = normalizeWaterTankOpportunity(value)
    if (!opportunity) {
      renderUnavailableOpportunity()
      return
    }

    if (title) title.textContent = opportunity.name
    if (tier) tier.textContent = label(opportunity.status)
    if (meta) {
      meta.textContent = `${Math.round(opportunity.confidence * 1000) / 10}% morphology confidence  •  Project source updated ${formatObserved(opportunity.observed_at)}`
    }
    if (address) address.textContent = opportunity.system_name
    if (summary) {
      summary.textContent = `${label(opportunity.tank_type.toLowerCase())} water tank  •  ${formatNumber(opportunity.capacity_gallons)} gal  •  ${label(opportunity.morphology_class)}  •  ${label(opportunity.support_geometry)}  •  ${label(opportunity.operator_assessment)}  •  ${opportunity.project_status} / ${opportunity.project_purpose}`
    }
    if (guardrail) guardrail.textContent = `Scout guardrail: ${opportunity.guardrail}`
    setState(`Scout opportunity ready: ${opportunity.name}`)
    return
  }

  if (opportunityType === 'telecom_change') {
    const opportunity = normalizeScoutSandboxTelecomChangeOpportunity(value)
    if (!opportunity) { renderUnavailableOpportunity(); return }
    if (title) title.textContent = `${opportunity.name} · ASR ${opportunity.registration_number}`
    if (tier) tier.textContent = 'FCC change signal'
    if (meta) meta.textContent = `${Math.round(opportunity.signal_confidence * 100)}% Scout signal confidence  •  Observed ${formatObserved(opportunity.observed_at)}`
    if (address) address.textContent = opportunity.location_label
    if (summary) summary.textContent = `FCC structure type ${opportunity.structure_type_code}  •  ${formatNumber(opportunity.overall_height_agl_m, 1)} m overall AGL  •  FCC record reports constructed ${opportunity.date_constructed}  •  Durable contact route available; procurement route not established  •  ${opportunity.why_investigate}`
    if (guardrail) guardrail.textContent = `Scout guardrail: ${opportunity.guardrail}`
    setState(`Scout opportunity ready: FCC ASR ${opportunity.registration_number}`)
    return
  }

  const opportunity = normalizeScoutSandboxOpportunity(value)
  if (!opportunity) {
    renderUnavailableOpportunity()
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

function renderMap(opportunityType: ScoutViewOpportunityType, value: unknown, embeddedTiles?: Record<string, string>) {
  destroyMap()
  if (opportunityType === 'swppp_site') diagnostic({ mapContainer: Boolean(mapContainer), mapOverlay: Boolean(mapState) })
  if (!mapContainer || !mapState) return

  const generation = ++mapGeneration
  let ready = false
  mapState.hidden = false
  mapState.textContent = isScoutSandboxPortfolioType(opportunityType) ? 'Loading portfolio map…' : 'Loading site map…'

  const mapOptions = {
    tileUrlTemplate: SCOUT_RASTER_TILE_TEMPLATE,
    attributionLabel: SCOUT_RASTER_ATTRIBUTION_LABEL,
    attributionUrl: SCOUT_RASTER_ATTRIBUTION_URL,
    onReady: () => {
      if (generation !== mapGeneration) return
      ready = true
      mapState.hidden = true
      if (opportunityType === 'swppp_site') { diagnostic({ viewReady: true }); diagnosticOverlay(mapState) }
      if (opportunityType === 'dealership_group_portfolio') { diagnostic({ dealershipReady: true, dealershipError: 'none' }); diagnosticOverlay(mapState) }
      setState(isScoutSandboxPortfolioType(opportunityType) ? 'Scout portfolio map ready' : 'Scout site map ready')
    },
    onError: (error: Error) => {
      if (generation !== mapGeneration) return
      if (!ready) {
        mapState.hidden = false
        mapState.textContent = isScoutSandboxPortfolioType(opportunityType) ? 'Portfolio map unavailable' : 'Site map unavailable'
      }
      if (opportunityType === 'swppp_site') { diagnostic({ viewError: true }); diagnosticOverlay(mapState) }
      if (opportunityType === 'dealership_group_portfolio') { diagnostic({ dealershipReady: false, dealershipError: error.message.slice(0, 180) }); diagnosticOverlay(mapState) }
      setState(`Scout map error: ${error.message}`)
    },
  }

  try {
    if (isScoutSandboxPortfolioType(opportunityType)) {
      const implementation = scoutSandboxPortfolioImplementation(opportunityType)
      const mapData = implementation.normalizeMap(value)
      if (!mapData) {
        if (opportunityType === 'dealership_group_portfolio') diagnostic({ dealershipNormalizer: 'failed' })
        mapState.textContent = 'Portfolio map unavailable'
        setState(`Scout ${opportunityType} map result failed validation`)
        return
      }
      if (opportunityType === 'dealership_group_portfolio') {
        const diagnosticFrame = implementation.buildRasterFrame(mapData, mapContainer.clientWidth, mapContainer.clientHeight, mapOptions)
        const matchingEmbeddedTiles = embeddedTiles ? diagnosticFrame.tiles.filter((tile: any) => Boolean(embeddedTiles[tile.url])).length : 0
        diagnostic({ dealershipNormalizer: 'passed', dealershipContainerWidth: mapContainer.clientWidth, dealershipContainerHeight: mapContainer.clientHeight, dealershipFrameWidth: diagnosticFrame.width, dealershipFrameHeight: diagnosticFrame.height, dealershipZoom: diagnosticFrame.zoom, dealershipRequiredTiles: diagnosticFrame.tiles.length, dealershipMatchingEmbeddedTiles: matchingEmbeddedTiles, dealershipMarkers: diagnosticFrame.markers.length, dealershipTileSource: embeddedTiles ? 'embedded_available' : 'embedded_missing', dealershipReady: false, dealershipError: 'not_yet' })
      }
      mapContainer.setAttribute('role', 'img')
      mapContainer.setAttribute('aria-label', implementation.ariaLabel(mapData))
      const mount = scoutSandboxPortfolioViewImplementation(opportunityType).mount as any
      mapHandle = mount(mapContainer, mapData, { ...mapOptions, embeddedTiles })
    } else {
      if (!isScoutSandboxSingleSiteType(opportunityType)) {
        mapState.textContent = 'Site map unavailable'
        setState(`Scout ${opportunityType} has no registered single-site map implementation`)
        return
      }
      const implementation = scoutSandboxSingleSiteViewImplementation(opportunityType)
      const rejectObserver = opportunityType === 'swppp_site'
        ? (detail: any) => diagnostic({ rejectedField: detail.field, rejectedCheck: detail.check, receivedType: detail.actualType, receivedStringShape: detail.stringShape })
        : undefined
      const mapData = implementation.normalizeMap(value, rejectObserver)
      if (opportunityType === 'swppp_site') diagnostic({ mapNormalizer: mapData ? 'passed' : 'rejected', viewReady: false, viewError: false, initialization: 'entered' })
      if (!mapData) {
        mapState.textContent = 'Site map unavailable'
        if (opportunityType === 'swppp_site') diagnosticOverlay(mapState)
        setState(`Scout ${opportunityType} map result failed validation`)
        return
      }
      mapContainer.setAttribute('role', 'img')
      mapContainer.setAttribute('aria-label', implementation.ariaLabel(mapData))
      const mountOptions = opportunityType === 'swppp_site' ? { ...mapOptions, embeddedTiles, onDiagnostic: diagnostic } : { ...mapOptions, embeddedTiles }
      mapHandle = implementation.mount(mapContainer, mapData, mountOptions)
      if (opportunityType === 'swppp_site') diagnostic({ initialization: 'returned' })
    }
    scheduleLayoutRefresh()
  } catch (error) {
    mapState.hidden = false
    mapState.textContent = isScoutSandboxPortfolioType(opportunityType) ? 'Portfolio map unavailable' : 'Site map unavailable'
    if (opportunityType === 'swppp_site') { diagnostic({ initialization: 'failed', initializationError: diagnosticError(error) }); diagnosticOverlay(mapState) }
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

const app = new App({ name: 'scout-ui-foundation', version: '2.21.0' })
app.ontoolinput = () => setState('Scout tool input received')
app.ontoolresult = (result) => {
  const structured = result?.structuredContent
  const metadataTiles = normalizeEmbeddedTiles(result?._meta?.['scout/rasterTiles'])
  const embeddedTiles = metadataTiles ?? resourceEmbeddedTiles
  const opportunityType = structured?.opportunity_type
  const control = document.querySelector<HTMLElement>('[data-scout-diagnostics]')
  if (control) control.hidden = opportunityType !== 'swppp_site' && opportunityType !== 'dealership_group_portfolio'
  if (opportunityType === 'swppp_site') diagnostic({ rejectedField: 'none', rejectedCheck: 'none', receivedType: 'not_checked', receivedStringShape: 'not_checked', resultCount: ++diagnosticResultCount, branch: 'not_entered', initializationError: 'none', mapNormalizer: 'not_entered', requiredTiles: 0, matchingTiles: 0, generation: 0, loadedTiles: 0, decodedTiles: 0, decodeFailed: 0, drawFailed: 0, imageFailed: 0, rendererReady: false, timeout: false, context2d: 'not_attempted', lastError: 'none', payloadSource: metadataTiles ? 'metadata' : resourceEmbeddedTiles ? 'resource' : 'none', identityMatch: structured?.map?.site_name === structured?.opportunity?.name && structured?.map?.location_label === structured?.opportunity?.location_label })
  if (opportunityType === 'dealership_group_portfolio') diagnostic({ dealershipResultCount: ++diagnosticResultCount, dealershipPayloadSource: metadataTiles ? 'metadata' : resourceEmbeddedTiles ? 'resource' : 'none', dealershipIdentityMatch: structured?.map?.account_name === structured?.opportunity?.name, dealershipNormalizer: 'not_entered', dealershipReady: false, dealershipError: 'none' })
  if (!isScoutSandboxOpportunityType(opportunityType)) {
    renderUnavailableOpportunity()
    renderMap('premium_exterior', null)
    return
  }
  renderOpportunity(opportunityType, structured?.opportunity)
  renderMap(opportunityType, structured?.map, embeddedTiles)
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

// Read computed overlay state at the user's diagnostic inspection, without resizing the map.
document.querySelector('[data-scout-diagnostics]')?.addEventListener('toggle', () => {
  if (mapState) diagnosticOverlay(mapState)
})

const transport = new PostMessageTransport()
try {
  await app.connect(transport)
  setState('Scout SDK connected; waiting for opportunity result')
} catch (error) {
  setState(`Scout SDK initialization failed: ${error instanceof Error ? error.message : String(error)}`)
}
