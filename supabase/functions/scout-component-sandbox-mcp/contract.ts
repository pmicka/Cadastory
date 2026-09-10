export const SCOUT_SANDBOX_RESULT_VERSION = 'v2' as const
export const SCOUT_SANDBOX_MAX_EXEMPLARS = 4

export type ScoutSandboxExemplarKind = 'property' | 'group'

export type ScoutSandboxExemplar = {
  name: string
  kind: ScoutSandboxExemplarKind
  archetype: string | null
  resolution_status: string | null
}

export type ScoutSandboxResult = {
  surface: 'scout_component_sandbox'
  version: typeof SCOUT_SANDBOX_RESULT_VERSION
  business_data: true
  interaction_scope: 'ephemeral_only'
  foundation: 'ready'
  exemplars: ScoutSandboxExemplar[]
}

function boundedText(value: unknown, maxLength: number) {
  if (typeof value !== 'string') return null
  const normalized = value.trim()
  return normalized.length > 0 && normalized.length <= maxLength ? normalized : null
}

function record(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null
}

export function normalizeScoutSandboxExemplar(value: unknown): ScoutSandboxExemplar | null {
  const candidate = record(value)
  if (!candidate) return null

  const name = boundedText(candidate.name, 160)
  const kind = candidate.kind === 'property' || candidate.kind === 'group'
    ? candidate.kind
    : null
  if (!name || !kind) return null

  return {
    name,
    kind,
    archetype: boundedText(candidate.archetype, 100),
    resolution_status: boundedText(candidate.resolution_status, 100),
  }
}

export function normalizeScoutSandboxExemplars(value: unknown): ScoutSandboxExemplar[] {
  if (!Array.isArray(value)) return []
  return value
    .map(normalizeScoutSandboxExemplar)
    .filter((item): item is ScoutSandboxExemplar => item !== null)
    .slice(0, SCOUT_SANDBOX_MAX_EXEMPLARS)
}

export function normalizeScoutSandboxRpcExemplars(value: unknown): ScoutSandboxExemplar[] {
  if (!Array.isArray(value)) return []
  return normalizeScoutSandboxExemplars(value.map((item) => {
    const candidate = record(item)
    if (!candidate) return null
    const contact = record(candidate.contact_card)
    return {
      name: candidate.label,
      kind: candidate.kind,
      archetype: candidate.kind === 'group'
        ? candidate.portfolio_archetype
        : contact?.organization_type,
      resolution_status: contact?.resolution_status,
    }
  }))
}
