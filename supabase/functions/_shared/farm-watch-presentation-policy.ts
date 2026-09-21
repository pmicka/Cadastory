export type FarmWatchAccountRole = 'owner' | 'viewer'

export const FARM_WATCH_PRESENTATION_POLICY = Object.freeze({
  viewerSummaryOnlyMaterializations: Object.freeze([
    'landscape-structure-context',
    'terrain-form-permeability',
    'spatial-edge-patch-context',
    'solar-terrain-context',
    'solar-exposure-context',
  ]),
})

export function normalizeFarmWatchAccountRole(value: unknown): FarmWatchAccountRole | null {
  return value === 'owner' || value === 'viewer' ? value : null
}

export function canReadFarmWatchMaterializationArtifact(
  accountRole: FarmWatchAccountRole,
  productKey: string,
) {
  if (accountRole === 'owner') return true
  return !FARM_WATCH_PRESENTATION_POLICY.viewerSummaryOnlyMaterializations.includes(productKey)
}

export function farmWatchPresentationCapabilities(accountRole: FarmWatchAccountRole) {
  const owner = accountRole === 'owner'
  return Object.freeze({
    qa_controls: owner,
    landscape_structure_map: owner,
  })
}

export function materializationPresentationMode(
  accountRole: FarmWatchAccountRole,
  productKey: string,
) {
  return canReadFarmWatchMaterializationArtifact(accountRole, productKey)
    ? 'full_artifact'
    : 'summary_only'
}
