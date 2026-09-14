import { normalizePortfolioResult } from './portfolio/result.ts'
import { portfolioCounts } from './portfolio/model.ts'
import { mountPortfolioMap } from './portfolio/mount.ts'
import { normalizeScoutSwpppSiteTransport } from './swppp_site_transport.ts'
import { diagnostic, diagnosticError, diagnosticOverlay } from './map_diagnostics.ts'
import { App, PostMessageTransport } from '@modelcontextprotocol/ext-apps'
import {
  normalizeScoutSandboxOpportunity,
  normalizeScoutSandboxSingleSiteMap,
  normalizeScoutSandboxWaterTankMap,
  type ScoutSandboxOpportunityType,
  type ScoutSandboxWaterTankOpportunity,
} from './contract.ts'
import { mountScoutSingleSiteMap } from './single_site_map_renderer.ts'
import { mountScoutWaterTankMap } from './water_tank_map_mount.ts'
import { normalizeScoutSandboxSwpppSiteOpportunity } from './swppp_site_map_model.ts'
import { mountScoutSwpppSiteMap } from './swppp_site_map_mount.ts'

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
const portfolioControls = document.querySelector<HTMLElement>('[data-scout-portfolio-controls]')
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
  if (!Array.isArray(value) || value.length > 20) return undefined
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

function renderOpportunity(opportunityType: ScoutSandboxOpportunityType, value: unknown) {
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
  if (portfolioControls) { portfolioControls.hidden = true; portfolioControls.replaceChildren() }
}

function renderMap(opportunityType: ScoutSandboxOpportunityType, value: unknown, embeddedTiles?: Record<string, string>) {
  destroyMap()
  if (opportunityType === 'swppp_site') diagnostic({ mapContainer: Boolean(mapContainer), mapOverlay: Boolean(mapState) })
  if (!mapContainer || !mapState) return

  const generation = ++mapGeneration
  let ready = false
  mapState.hidden = false
  mapState.textContent = 'Loading site map…'

  const mapOptions = {
    tileUrlTemplate: SCOUT_RASTER_TILE_TEMPLATE,
    attributionLabel: SCOUT_RASTER_ATTRIBUTION_LABEL,
    attributionUrl: SCOUT_RASTER_ATTRIBUTION_URL,
    onReady: () => {
      if (generation !== mapGeneration) return
      ready = true
      mapState.hidden = true
      if (opportunityType === 'swppp_site') { diagnostic({ viewReady: true }); diagnosticOverlay(mapState) }
      setState('Scout site map ready')
    },
    onError: (error: Error) => {
      if (generation !== mapGeneration) return
      if (!ready) {
        mapState.hidden = false
        mapState.textContent = 'Site map unavailable'
      }
      if (opportunityType === 'swppp_site') { diagnostic({ viewError: true }); diagnosticOverlay(mapState) }
      setState(`Scout map error: ${error.message}`)
    },
  }

  try {
    if (opportunityType === 'swppp_site') {
      const mapData = normalizeScoutSwpppSiteTransport(value, (detail) => diagnostic({ rejectedField: detail.field, rejectedCheck: detail.check, receivedType: detail.actualType, receivedStringShape: detail.stringShape }))
      diagnostic({ mapNormalizer: mapData ? 'passed' : 'rejected', viewReady: false, viewError: false, initialization: 'entered' })
      if (!mapData) {
        mapState.textContent = 'Site map unavailable'
        diagnosticOverlay(mapState)
        setState('Scout SWPPP-site map result failed validation')
        return
      }
      mapContainer.setAttribute('role', 'img')
      mapContainer.setAttribute('aria-label', `Permit location map for ${mapData.site_name}`)
      mapHandle = mountScoutSwpppSiteMap(mapContainer, mapData, { ...mapOptions, embeddedTiles, onDiagnostic: diagnostic })
      diagnostic({ initialization: 'returned' })
    } else if (opportunityType === 'water_tank') {
      const mapData = normalizeScoutSandboxWaterTankMap(value)
      if (!mapData) {
        mapState.textContent = 'Site map unavailable'
        setState('Scout water-tank map result failed validation')
        return
      }
      mapContainer.setAttribute('role', 'img')
      mapContainer.setAttribute('aria-label', `Site map for ${mapData.name}`)
      mapHandle = mountScoutWaterTankMap(mapContainer, mapData, { ...mapOptions, embeddedTiles })
    } else {
      const mapData = normalizeScoutSandboxSingleSiteMap(value)
      if (!mapData) {
        mapState.textContent = 'Site map unavailable'
        setState('Scout single-site map result failed validation')
        return
      }
      mapContainer.setAttribute('role', 'img')
      mapContainer.setAttribute('aria-label', `Site map for ${mapData.name}`)
      mapHandle = mountScoutSingleSiteMap(mapContainer, mapData, { ...mapOptions, embeddedTiles })
    }
    scheduleLayoutRefresh()
  } catch (error) {
    mapState.hidden = false
    mapState.textContent = 'Site map unavailable'
    if (opportunityType === 'swppp_site') { diagnostic({ initialization: 'failed', initializationError: diagnosticError(error) }); diagnosticOverlay(mapState) }
    setState(`Scout map initialization failed: ${error instanceof Error ? error.message : String(error)}`)
  }
}

// Prepared portfolio scope; not exposed by the current public tool schema.
function renderPortfolio(value: unknown, embeddedTiles?: Record<string,string>) {
  destroyMap()
  const result = normalizePortfolioResult(value)
  diagnostic({mapNormalizer:result?'passed':'rejected',identityMatch:Boolean(result),branch:'not_entered',requiredTiles:0,matchingTiles:0,decodedTiles:0,context2d:'not_attempted',rendererReady:false,viewReady:false,viewError:false,lastError:'none'})
  if (!result || !mapContainer || !mapState || !portfolioControls) {
    renderUnavailableOpportunity()
    if (mapState) { mapState.hidden = false; mapState.textContent = 'Portfolio map unavailable' }
    return
  }
  const map = result.map, counts = portfolioCounts(map)
  if (title) title.textContent = map.account_name
  if (tier) tier.textContent = 'Documented tank roster'
  if (meta) meta.textContent = `${counts.total} members • ${counts.mapped} mapped • ${counts.unresolved} locations unresolved • ${counts.omitted} omitted`
  if (address) address.textContent = `Water system ${map.pwsid}`
  const sourceDates = [...new Set(map.members.map(member => member.source_modified_at.slice(0,10)))].sort()
  if (summary) summary.textContent = `${counts.documentedNotInService} documented not in service • ${counts.membersWithHistoricalSignals} members with historical rehabilitation evidence • Roster source updated ${sourceDates[0]}${sourceDates.length>1?' to '+sourceDates.at(-1):''}`
  if (guardrail) guardrail.textContent = 'Scout guardrail: System membership does not establish ownership, contracting authority, or site access. Historical rehabilitation evidence is not proof of current service need, buyer intent, or available work. Other members have unverified operating state.'
  mapContainer.setAttribute('role','img')
  mapContainer.setAttribute('aria-label',`Documented tank locations for ${map.account_name}`)
  mapState.hidden = false; mapState.textContent = 'Loading portfolio map…'
  portfolioControls.hidden = false
  const generation = ++mapGeneration
  try {
    mapHandle = mountPortfolioMap(mapContainer,portfolioControls,map,Object.entries(embeddedTiles ?? {}).map(([url,data_url])=>({url,data_url})), {
      onDiagnostic:diagnostic,
      onReady:()=>{if(generation!==mapGeneration)return;mapState.hidden=true;diagnostic({viewReady:true,viewError:false});diagnosticOverlay(mapState);setState('Scout portfolio map ready')},
      onError:()=>{if(generation!==mapGeneration)return;mapState.hidden=false;mapState.textContent='Portfolio map unavailable';diagnostic({viewReady:false,viewError:true});diagnosticOverlay(mapState);setState('Scout portfolio map unavailable')},
    })
    scheduleLayoutRefresh()
  } catch {
    mapState.hidden=false;mapState.textContent='Portfolio map unavailable'
    diagnostic({viewError:true,lastError:'portfolio_initialization_rejected'});diagnosticOverlay(mapState)
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

const app = new App({ name: 'scout-ui-foundation', version: '2.6.0' })
app.ontoolinput = () => setState('Scout tool input received')
app.ontoolresult = (result) => {
  const structured = result?.structuredContent
  const metadataTiles = normalizeEmbeddedTiles(result?._meta?.['scout/rasterTiles'])
  const embeddedTiles = metadataTiles ?? resourceEmbeddedTiles
  const opportunityType = structured?.opportunity_type
  const control = document.querySelector<HTMLElement>('[data-scout-diagnostics]')
  const isPortfolio = structured?.view_scope === 'portfolio'
  if (control) control.hidden = opportunityType !== 'swppp_site' && !isPortfolio
  if (isPortfolio) { renderPortfolio(structured, embeddedTiles); return }
  if (opportunityType === 'swppp_site') diagnostic({ rejectedField: 'none', rejectedCheck: 'none', receivedType: 'not_checked', receivedStringShape: 'not_checked', resultCount: ++diagnosticResultCount, branch: 'not_entered', initializationError: 'none', mapNormalizer: 'not_entered', requiredTiles: 0, matchingTiles: 0, generation: 0, loadedTiles: 0, decodedTiles: 0, decodeFailed: 0, drawFailed: 0, imageFailed: 0, rendererReady: false, timeout: false, context2d: 'not_attempted', lastError: 'none', payloadSource: metadataTiles ? 'metadata' : resourceEmbeddedTiles ? 'resource' : 'none', identityMatch: structured?.map?.site_name === structured?.opportunity?.name && structured?.map?.location_label === structured?.opportunity?.location_label })
  if (opportunityType !== 'premium_exterior' && opportunityType !== 'water_tank' && opportunityType !== 'swppp_site') {
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
