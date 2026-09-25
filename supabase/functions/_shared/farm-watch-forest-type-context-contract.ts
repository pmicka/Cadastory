export const FARM_WATCH_FOREST_TYPE_CONTEXT_PRODUCT = Object.freeze({
  key: 'forest-type-context',
  algorithmVersion: 'abernathy-habitat-distance-source-reconciliation-v1',
  outputSchemaVersion: 'forest-type-context-v1',
  studyCitation: 'Abernathy et al. 2019, Proceedings of the Royal Society B 286:20192230',
  studyLandcoverSource: 'Florida Natural Areas Inventory Cooperative Land Cover v3.2',
  studyResolutionM: 10,
  searchRadiusM: 3000,
  nlcdSourceSlug: 'usgs-annual-nlcd-land-cover',
  nlcdSourceResolutionM: 30,
  nwiSourceSlug: 'usfws-nwi',
  studyClasses: Object.freeze([
    'pine_forest',
    'hardwood_swamp',
    'marsh',
    'prairie',
    'shrub',
    'hardwood_hammock',
  ] as const),
  nlcdClassMap: Object.freeze({
    pine_forest: Object.freeze({ value: 42, name: 'Evergreen Forest' }),
    prairie: Object.freeze({ value: 71, name: 'Grassland/Herbaceous' }),
    shrub: Object.freeze({ value: 52, name: 'Shrub/Scrub' }),
    hardwood_hammock: Object.freeze({ value: 41, name: 'Deciduous Forest' }),
  }),
  nwiClassMap: Object.freeze({
    hardwood_swamp: Object.freeze({ codePrefix: 'PFO1', name: 'Palustrine Forested Broad-Leaved Deciduous' }),
    marsh: Object.freeze({ codePrefix: 'PEM', name: 'Palustrine Emergent' }),
  }),
})

export type FarmWatchForestRefugeClass =
  typeof FARM_WATCH_FOREST_TYPE_CONTEXT_PRODUCT.studyClasses[number]

export function validateFarmWatchForestTypeContext(value: any) {
  const p = FARM_WATCH_FOREST_TYPE_CONTEXT_PRODUCT
  if (
    value?.schema !== p.outputSchemaVersion ||
    value?.method !== p.algorithmVersion ||
    value?.evidence_class !== 'deterministic_derived' ||
    value?.evidence_state !== 'proxy' ||
    value?.deer_inference_performed !== false ||
    value?.coefficient_transfer_performed !== false ||
    value?.scoring_performed !== false ||
    Number(value?.source_reconciliation?.search_radius_m) !== p.searchRadiusM ||
    Number(value?.source_reconciliation?.annual_nlcd?.spatial_resolution_m) !== p.nlcdSourceResolutionM ||
    !Array.isArray(value?.habitat_distances)
  ) return false

  const rows = value.habitat_distances
  if (rows.length !== p.studyClasses.length) return false
  const keys = rows.map((row: any) => String(row?.study_class_key || '')).sort()
  if (JSON.stringify(keys) !== JSON.stringify([...p.studyClasses].sort())) return false

  return rows.every((row: any) => {
    const status = String(row?.status || '')
    if (!['available', 'right_censored', 'unavailable'].includes(status)) return false
    if (status === 'available') {
      return Number.isFinite(Number(row?.distance_m)) && Number(row.distance_m) >= 0
    }
    if (status === 'right_censored') {
      return Number(row?.distance_lower_bound_m) === p.searchRadiusM
    }
    return row?.distance_m == null
  })
}
