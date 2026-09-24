export type FarmWatchAccountRole = 'owner' | 'admin' | 'viewer'
export type FarmWatchPresentationProfile = 'technical' | 'guided'

export const FARM_WATCH_PRESENTATION_POLICY = Object.freeze({
  viewerSummaryOnlyMaterializations: Object.freeze([
    'landscape-structure-context',
    'terrain-form-permeability',
    'spatial-edge-patch-context',
    'solar-terrain-context',
    'solar-exposure-context',
    'thermal-exposure-context',
    'horizontal-visibility-context',
  ]),
})

export function normalizeFarmWatchAccountRole(value: unknown): FarmWatchAccountRole | null {
  return value === 'owner' || value === 'admin' || value === 'viewer' ? value : null
}

export function farmWatchPresentationProfile(
  accountRole: FarmWatchAccountRole,
): FarmWatchPresentationProfile {
  return accountRole === 'viewer' ? 'guided' : 'technical'
}

export function canReadFarmWatchMaterializationArtifact(
  accountRole: FarmWatchAccountRole,
  productKey: string,
) {
  if (farmWatchPresentationProfile(accountRole) === 'technical') return true
  return !FARM_WATCH_PRESENTATION_POLICY.viewerSummaryOnlyMaterializations.includes(productKey)
}

export function farmWatchPresentationCapabilities(accountRole: FarmWatchAccountRole) {
  const profile = farmWatchPresentationProfile(accountRole)
  const technical = profile === 'technical'
  return Object.freeze({
    presentation_profile: profile,
    guided_interpretation: !technical,
    technical_evidence: technical,
    qa_controls: technical,
    landscape_structure_map: technical,
    field_evidence_table: technical,
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
