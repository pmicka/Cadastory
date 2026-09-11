export const SCOUT_SANDBOX_MAX_NAMES = 2

export type ScoutSandboxOpportunity = {
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

export type ScoutSandboxResult = {
  surface: 'scout_component_sandbox'
  names: string[]
  opportunity: ScoutSandboxOpportunity
}

function boundedString(value: unknown, maxLength: number) {
  if (typeof value !== 'string') return null
  const text = value.trim()
  return text.length > 0 && text.length <= maxLength ? text : null
}

function boundedNumber(value: unknown, minimum: number, maximum: number) {
  return typeof value === 'number' && Number.isFinite(value) && value >= minimum && value <= maximum
    ? value
    : null
}

function boundedInteger(value: unknown, minimum: number, maximum: number) {
  const number = boundedNumber(value, minimum, maximum)
  return number !== null && Number.isInteger(number) ? number : null
}

function boundedName(value: unknown) {
  return boundedString(value, 160)
}

export function normalizeScoutSandboxNames(value: unknown): string[] {
  if (!Array.isArray(value)) return []
  return value.map(boundedName).filter((name): name is string => name !== null).slice(0, SCOUT_SANDBOX_MAX_NAMES)
}

export function normalizeScoutSandboxOpportunity(value: unknown): ScoutSandboxOpportunity | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null
  const source = value as Record<string, unknown>
  const opportunity: ScoutSandboxOpportunity = {
    name: boundedString(source.name, 160) ?? '',
    address: boundedString(source.address, 240) ?? '',
    opportunity_tier: boundedString(source.opportunity_tier, 64) ?? '',
    opportunity_score: boundedInteger(source.opportunity_score, 0, 100) ?? -1,
    confidence: boundedNumber(source.confidence, 0, 1) ?? -1,
    story_count: boundedInteger(source.story_count, 0, 1000) ?? -1,
    height_m: boundedNumber(source.height_m, 0, 10000) ?? -1,
    footprint_sqft: boundedNumber(source.footprint_sqft, 0, 1_000_000_000) ?? -1,
    glazing_status: boundedString(source.glazing_status, 80) ?? '',
    observed_at: boundedString(source.observed_at, 80) ?? '',
    target_class: boundedString(source.target_class, 80) ?? '',
    target_subclass: boundedString(source.target_subclass, 80) ?? '',
    buyer_resolvability: boundedString(source.buyer_resolvability, 120) ?? '',
    guardrail: boundedString(source.guardrail, 1000) ?? '',
  }

  return opportunity.name &&
      opportunity.address &&
      opportunity.opportunity_tier &&
      opportunity.opportunity_score >= 0 &&
      opportunity.confidence >= 0 &&
      opportunity.story_count >= 0 &&
      opportunity.height_m >= 0 &&
      opportunity.footprint_sqft >= 0 &&
      opportunity.glazing_status &&
      opportunity.observed_at &&
      opportunity.target_class &&
      opportunity.target_subclass &&
      opportunity.buyer_resolvability &&
      opportunity.guardrail
    ? opportunity
    : null
}
