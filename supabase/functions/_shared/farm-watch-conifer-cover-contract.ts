export const FARM_WATCH_CONIFER_COVER_PRODUCT = Object.freeze({
  key: 'conifer-cover-context',
  algorithmVersion: 'delgiudice-conifer-availability-source-substitution-v1',
  outputSchemaVersion: 'conifer-cover-context-v1',
  evidenceState: 'proxy',
  measurementAlignment: 'calibrated_proxy',
  studyCitation: 'DelGiudice, Fieberg & Sampson 2013, PLOS ONE 8:e65368',
  landcoverSourceSlug: 'usgs-annual-nlcd-land-cover',
  canopySourceSlug: 'nlcd-tree-canopy-cover-2025',
  evergreenLandcoverValue: 42,
  mixedForestLandcoverValue: 43,
  moderateMinimumPercent: 40,
  denseMinimumPercent: 70,
  pixelSizeM: 30,
  domainKeys: Object.freeze([
    'property',
    'local_500m',
    'landscape_1500m',
    'broad_3000m',
  ] as const),
  studyAvailabilityClasses: Object.freeze([
    'moderately_dense_conifer',
    'dense_conifer',
    'other',
  ] as const),
})

export type FarmWatchConiferDomainKey =
  typeof FARM_WATCH_CONIFER_COVER_PRODUCT.domainKeys[number]

function finite(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value)
}

export function coniferStudyClass(landcoverValue: number, canopyPercent: number) {
  const p = FARM_WATCH_CONIFER_COVER_PRODUCT
  if (!Number.isFinite(landcoverValue) || !Number.isFinite(canopyPercent)) {
    throw new Error('invalid conifer classification inputs')
  }
  if (landcoverValue !== p.evergreenLandcoverValue) return 'other' as const
  if (canopyPercent >= p.denseMinimumPercent) return 'dense_conifer' as const
  if (canopyPercent >= p.moderateMinimumPercent) return 'moderately_dense_conifer' as const
  return 'other' as const
}

export function validateFarmWatchConiferCoverContext(value: any) {
  const p = FARM_WATCH_CONIFER_COVER_PRODUCT
  if (
    value?.schema !== p.outputSchemaVersion ||
    value?.method !== p.algorithmVersion ||
    value?.evidence_state !== p.evidenceState ||
    value?.measurement_alignment !== p.measurementAlignment ||
    value?.deer_inference_performed !== false ||
    value?.coefficient_transfer_performed !== false ||
    value?.scoring_performed !== false ||
    value?.source_reconciliation?.landcover?.slug !== p.landcoverSourceSlug ||
    value?.source_reconciliation?.canopy?.slug !== p.canopySourceSlug ||
    Number(value?.source_reconciliation?.common_source_year) < 1985 ||
    Number(value?.raster_support?.pixel_width_m) !== p.pixelSizeM ||
    Number(value?.raster_support?.pixel_height_m) !== p.pixelSizeM
  ) return false

  const domains = value?.domains
  if (!domains || typeof domains !== 'object') return false

  for (const key of p.domainKeys) {
    const row = domains[key]
    if (
      !row ||
      row.status !== 'available' ||
      !Number.isInteger(Number(row.domain_cell_count)) ||
      Number(row.domain_cell_count) < 1 ||
      !Number.isInteger(Number(row.valid_pair_cell_count)) ||
      Number(row.valid_pair_cell_count) < 1 ||
      Number(row.valid_pair_cell_count) > Number(row.domain_cell_count) ||
      !finite(Number(row.valid_pair_coverage_ratio)) ||
      Number(row.valid_pair_coverage_ratio) < 0 ||
      Number(row.valid_pair_coverage_ratio) > 1
    ) return false

    const availability = row.study_availability
    if (!availability || typeof availability !== 'object') return false
    let classCount = 0
    let percentSum = 0
    for (const classKey of p.studyAvailabilityClasses) {
      const cls = availability[classKey]
      if (
        !cls ||
        !Number.isInteger(Number(cls.cell_count)) ||
        Number(cls.cell_count) < 0 ||
        !finite(Number(cls.percent_of_valid_habitat)) ||
        Number(cls.percent_of_valid_habitat) < 0 ||
        Number(cls.percent_of_valid_habitat) > 100
      ) return false
      classCount += Number(cls.cell_count)
      percentSum += Number(cls.percent_of_valid_habitat)
    }
    if (classCount !== Number(row.valid_pair_cell_count)) return false
    if (Math.abs(percentSum - 100) > 0.02) return false

    const diagnostic = row.diagnostics
    if (
      !diagnostic ||
      !Number.isInteger(Number(diagnostic.open_conifer_cell_count)) ||
      !Number.isInteger(Number(diagnostic.mixed_forest_cell_count)) ||
      Number(diagnostic.open_conifer_cell_count) < 0 ||
      Number(diagnostic.mixed_forest_cell_count) < 0
    ) return false
  }

  return true
}
