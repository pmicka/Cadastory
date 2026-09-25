export const FARM_WATCH_FOREST_TYPE_CONTEXT_PRODUCT = Object.freeze({
  key: 'forest-type-context',
  algorithmVersion: 'landfire-evt-evc-deciduous-proxy-v1',
  outputSchemaVersion: 'forest-type-context-v1',
  evidenceClass: 'deterministic_derived',
  semanticEvidenceClass: 'mapped_forest_type_canopy_proxy',
  sourceAuthority: 'LANDFIRE / USGS / USDA Forest Service',
  sourceProduct: 'LANDFIRE Existing Vegetation Type + Existing Vegetation Cover',
  sourcePixelMeters: 30,
  sourceNativeCrs: 'EPSG:5070',
  sourceNativeWkid: 5070,
  sourceCandidateLookbackYears: 2,
  refreshDays: 30,
  scopeOrder: Object.freeze([
    'property',
    'local_500m',
    'landscape_1500m',
    'broad_3000m',
  ] as const),
})

export const FARM_WATCH_FOREST_TYPE_CONTEXT_LIMITATIONS = Object.freeze([
  'The Darlington et al. source study used Alberta Vegetation Inventory percent crown closure of dominant overstorey species. LANDFIRE EVT/EVC is a documented 30 m Kentucky source substitution, not the original AVI measurement.',
  'Hardwood EVT physiognomy is used as a deciduous/natural-forest composition proxy. It does not establish species-specific overstorey percentages.',
  'No generic fragmentation, old-growth, undisturbed, or biological intactness score is calculated. The source paper used intact natural vegetation descriptively; its natural covariates were species-composition/canopy variables.',
  'LANDFIRE classes are modeled mapped vegetation classes and canopy cover, not a field inventory of every stand.',
  'LANDFIRE cautions against treating individual or small groups of 30 m pixels as authoritative local measurements. Farm Watch therefore uses aggregated property/landscape summaries and does not expose a pixel-level M43 evidence API.',
  'This neutral product does not activate the Darlington cumulative-effects relationship while industrial human-footprint composition and camera-derived wolf occurrence remain unavailable.',
  'No deer selection direction, coefficient, habitat-quality score, movement inference, or management recommendation is produced.',
])

export type FarmWatchForestTypeScopeSummary = {
  modeled_cell_count: number
  tree_cell_count: number
  hardwood_cell_count: number
  hardwood_cell_share_percent: number
  hardwood_share_of_tree_cells_percent: number | null
  hardwood_canopy_equivalent_percent_of_area: number | null
  mean_tree_cover_percent_within_hardwood_cells: number | null
}

function finitePercent(value: unknown, allowNull = false) {
  if (allowNull && value == null) return true
  const n = Number(value)
  return Number.isFinite(n) && n >= 0 && n <= 100
}

export function validateForestTypeContext(value: any) {
  const p = FARM_WATCH_FOREST_TYPE_CONTEXT_PRODUCT
  if (
    value?.schema !== p.outputSchemaVersion ||
    value?.method !== p.algorithmVersion ||
    value?.status !== 'available' ||
    value?.evidence_class !== p.semanticEvidenceClass ||
    value?.source?.authority !== p.sourceAuthority ||
    value?.source?.product !== p.sourceProduct ||
    Number(value?.source?.spatial_resolution_m) !== p.sourcePixelMeters ||
    value?.source?.native_crs !== p.sourceNativeCrs ||
    value?.source_alignment?.source_study !== 'Darlington et al. 2022, Scientific Reports 12:1072' ||
    value?.source_alignment?.source_measurement !==
      'Alberta Vegetation Inventory percent crown closure of dominant overstorey species' ||
    value?.source_alignment?.farm_watch_alignment !== 'calibrated_proxy' ||
    value?.intactness_metric_performed !== false ||
    value?.behavioral_inference_performed !== false ||
    value?.coefficient_transfer_performed !== false ||
    value?.scoring_performed !== false
  ) return false

  const version = Number(value?.source?.landfire_version)
  if (!Number.isInteger(version) || version < 2024 || version > 2100) return false
  if (!/^[0-9a-f]{64}$/.test(String(value?.source?.evt_service_metadata_sha256 || ''))) return false
  if (!/^[0-9a-f]{64}$/.test(String(value?.source?.evc_service_metadata_sha256 || ''))) return false
  if (!/^[0-9a-f]{64}$/.test(String(value?.source?.evt_attribute_table_sha256 || ''))) return false
  if (!/^[0-9a-f]{64}$/.test(String(value?.source?.evc_attribute_table_sha256 || ''))) return false

  const scopes = value?.summary?.scopes
  for (const scope of p.scopeOrder) {
    const row = scopes?.[scope]
    if (
      !row ||
      !Number.isInteger(Number(row.modeled_cell_count)) ||
      Number(row.modeled_cell_count) <= 0 ||
      !Number.isInteger(Number(row.tree_cell_count)) ||
      Number(row.tree_cell_count) < 0 ||
      !Number.isInteger(Number(row.hardwood_cell_count)) ||
      Number(row.hardwood_cell_count) < 0 ||
      Number(row.hardwood_cell_count) > Number(row.tree_cell_count) ||
      !finitePercent(row.hardwood_cell_share_percent) ||
      !finitePercent(row.hardwood_share_of_tree_cells_percent, true) ||
      !finitePercent(row.hardwood_canopy_equivalent_percent_of_area, true) ||
      !finitePercent(row.mean_tree_cover_percent_within_hardwood_cells, true)
    ) return false
  }

  return Boolean(
    value?.source_selection?.probe_basis === 'property_center_internal_source_health_only' &&
    value?.source_selection?.pixel_interpretation_exposed === false &&
    value?.interpretation_boundary
  )
}
