import { App, PostMessageTransport } from '@modelcontextprotocol/ext-apps'

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

const title = document.querySelector<HTMLElement>('[data-scout-title]')
const tier = document.querySelector<HTMLElement>('[data-scout-tier]')
const address = document.querySelector<HTMLElement>('[data-scout-address]')
const summary = document.querySelector<HTMLElement>('[data-scout-summary]')
const score = document.querySelector<HTMLElement>('[data-scout-score]')
const confidence = document.querySelector<HTMLElement>('[data-scout-confidence]')
const stories = document.querySelector<HTMLElement>('[data-scout-stories]')
const height = document.querySelector<HTMLElement>('[data-scout-height]')
const footprint = document.querySelector<HTMLElement>('[data-scout-footprint]')
const facade = document.querySelector<HTMLElement>('[data-scout-facade]')
const observed = document.querySelector<HTMLElement>('[data-scout-observed]')
const route = document.querySelector<HTMLElement>('[data-scout-route]')
const guardrail = document.querySelector<HTMLElement>('[data-scout-guardrail]')
const state = document.querySelector<HTMLElement>('[data-scout-state]')

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

function renderOpportunity(value: unknown) {
  const opportunity = normalizeOpportunity(value)
  if (!opportunity) {
    if (title) title.textContent = 'Opportunity unavailable'
    if (tier) tier.textContent = 'Unavailable'
    if (address) address.textContent = 'Scout did not receive a valid bounded opportunity result.'
    setState('Scout opportunity result failed validation')
    return
  }

  if (title) title.textContent = opportunity.name
  if (tier) tier.textContent = label(opportunity.opportunity_tier)
  if (address) address.textContent = opportunity.address
  if (summary) summary.textContent = `${label(opportunity.target_subclass)} · ${label(opportunity.target_class)} · ${label(opportunity.glazing_status)}`
  if (score) score.textContent = String(opportunity.opportunity_score)
  if (confidence) confidence.textContent = `${Math.round(opportunity.confidence * 100)}%`
  if (stories) stories.textContent = String(opportunity.story_count)
  if (height) height.textContent = `${new Intl.NumberFormat('en-US', { maximumFractionDigits: 1 }).format(opportunity.height_m)} m`
  if (footprint) footprint.textContent = `${new Intl.NumberFormat('en-US', { maximumFractionDigits: 0 }).format(opportunity.footprint_sqft)} sq ft`
  if (facade) facade.textContent = label(opportunity.glazing_status)
  if (observed) observed.textContent = formatObserved(opportunity.observed_at)
  if (route) route.textContent = label(opportunity.buyer_resolvability)
  if (guardrail) guardrail.textContent = opportunity.guardrail
  setState(`Scout opportunity ready: ${opportunity.name}`)
}

const app = new App({ name: 'scout-ui-foundation', version: '2.0.0' })
app.ontoolinput = () => setState('Scout tool input received')
app.ontoolresult = (result) => renderOpportunity(result?.structuredContent?.opportunity)
app.onerror = (error) => setState(`Scout SDK error: ${error instanceof Error ? error.message : String(error)}`)
app.onteardown = async () => ({})

const transport = new PostMessageTransport()
try {
  await app.connect(transport)
  setState('Scout SDK connected; waiting for opportunity result')
} catch (error) {
  setState(`Scout SDK initialization failed: ${error instanceof Error ? error.message : String(error)}`)
}
