export const SCOUT_SANDBOX_MAX_NAMES = 2

export type ScoutSandboxResult = {
  surface: 'scout_component_sandbox'
  names: string[]
}

function boundedName(value: unknown) {
  if (typeof value !== 'string') return null
  const name = value.trim()
  return name.length > 0 && name.length <= 160 ? name : null
}

export function normalizeScoutSandboxNames(value: unknown): string[] {
  if (!Array.isArray(value)) return []
  return value.map(boundedName).filter((name): name is string => name !== null).slice(0, SCOUT_SANDBOX_MAX_NAMES)
}
