// Retention age is not scientific invalidation for stable, versioned inputs.
// Null removes only calendar expiry. Canonical dependency/property checks still
// decide whether the artifact can be represented as current.
export function farmWatchMaterializationExpiresAt(
  completedAt: Date,
  refreshDays: number | null,
): string | null {
  if (refreshDays === null) return null
  if (!Number.isFinite(refreshDays) || refreshDays <= 0) {
    throw new Error('materialization refresh days must be positive or null')
  }
  return new Date(completedAt.getTime() + refreshDays * 86400000).toISOString()
}
