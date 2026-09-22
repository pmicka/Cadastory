export const FARM_WATCH_MAST_CAPACITY_GROUPS = Object.freeze({
  white_oak: Object.freeze([
    { spcd: 802, common_name: 'white oak', scientific_name: 'Quercus alba' },
    { spcd: 804, common_name: 'swamp white oak', scientific_name: 'Quercus bicolor' },
    { spcd: 822, common_name: 'overcup oak', scientific_name: 'Quercus lyrata' },
    { spcd: 823, common_name: 'bur oak', scientific_name: 'Quercus macrocarpa' },
    { spcd: 825, common_name: 'swamp chestnut oak', scientific_name: 'Quercus michauxii' },
    { spcd: 826, common_name: 'chinkapin oak', scientific_name: 'Quercus muehlenbergii' },
    { spcd: 832, common_name: 'chestnut oak', scientific_name: 'Quercus prinus' },
    { spcd: 835, common_name: 'post oak', scientific_name: 'Quercus stellata' },
  ]),
  red_oak: Object.freeze([
    { spcd: 806, common_name: 'scarlet oak', scientific_name: 'Quercus coccinea' },
    { spcd: 812, common_name: 'southern red oak', scientific_name: 'Quercus falcata' },
    { spcd: 813, common_name: 'cherrybark oak', scientific_name: 'Quercus pagoda' },
    { spcd: 817, common_name: 'shingle oak', scientific_name: 'Quercus imbricaria' },
    { spcd: 824, common_name: 'blackjack oak', scientific_name: 'Quercus marilandica' },
    { spcd: 827, common_name: 'water oak', scientific_name: 'Quercus nigra' },
    { spcd: 830, common_name: 'pin oak', scientific_name: 'Quercus palustris' },
    { spcd: 831, common_name: 'willow oak', scientific_name: 'Quercus phellos' },
    { spcd: 833, common_name: 'northern red oak', scientific_name: 'Quercus rubra' },
    { spcd: 834, common_name: 'Shumard oak', scientific_name: 'Quercus shumardii' },
    { spcd: 837, common_name: 'black oak', scientific_name: 'Quercus velutina' },
  ]),
  hickory: Object.freeze([
    { spcd: 400, common_name: 'hickory spp.', scientific_name: 'Carya spp.' },
    { spcd: 402, common_name: 'bitternut hickory', scientific_name: 'Carya cordiformis' },
    { spcd: 403, common_name: 'pignut hickory', scientific_name: 'Carya glabra' },
    { spcd: 405, common_name: 'shellbark hickory', scientific_name: 'Carya laciniosa' },
    { spcd: 407, common_name: 'shagbark hickory', scientific_name: 'Carya ovata' },
    { spcd: 409, common_name: 'mockernut hickory', scientific_name: 'Carya alba' },
    { spcd: 412, common_name: 'red hickory', scientific_name: 'Carya ovalis' },
    { spcd: 413, common_name: 'southern shagbark hickory', scientific_name: 'Carya carolinae-septentrionalis' },
  ]),
  beech: Object.freeze([
    { spcd: 531, common_name: 'American beech', scientific_name: 'Fagus grandifolia' },
  ]),
})

export const FARM_WATCH_MAST_CAPACITY_PRODUCT = Object.freeze({
  key: 'mast-capacity',
  productKind: 'mast-capacity',
  algorithmVersion: 'bigmap2018-species-biomass-broad3000-v2',
  outputSchemaVersion: 'mast-capacity-v1',
  evidenceClass: 'deterministic_derived',
  semanticEvidenceClass: 'modeled_species_capacity',
  artifactBucket: 'farm-watch-derived',
  artifactFormat: 'farm-watch-mast-capacity-json-v1',
  artifactMimeType: 'application/json',
  sourceAuthority: 'USDA Forest Service Forest Inventory and Analysis (FIA)',
  sourceProduct: 'FIA BIGMAP 2018 Tree Species Aboveground Biomass',
  sourceDataYear: 2018,
  sourceService:
    'https://imagery.geoplatform.gov/iipp/rest/services/Vegetation/USFS_FIA_BIGMAP_AboveGroundBiomass/ImageServer',
  sourcePixelMeters: 30,
  sourceNativeCrs: 'ESRI:102039',
  sourceNativeWkid: 102039,
  sourceValueUnit: 'tons_per_acre_live_tree_aboveground_biomass',
  domainScope: 'broad_3000m',
  refreshDays: 365,
  groupOrder: Object.freeze(['white_oak','red_oak','hickory','beech'] as const),
})

export const FARM_WATCH_MAST_CAPACITY_LIMITATIONS = Object.freeze([
  'BIGMAP 2018 is a modeled/imputed 30 m FIA species-biomass product, not an observed inventory of individual trees at each pixel.',
  'The product represents modeled live-tree aboveground biomass capacity by mast-producing species group. It does not measure acorn/nut production, mast fall, crop quality, current-year fruiting, or ground availability.',
  'Species-group biomass is retained as a continuous modeled quantity. No low/moderate/high habitat threshold or deer-food score is authorized by Batch 5A.',
  'The broad_3000m domain is the current barrier-aware Farm Watch landscape domain, not a simple circular buffer.',
  'Group membership is source-controlled for the Kentucky/Central Hardwood use case and must be reviewed before applying this exact species set to a different biogeographic region.',
  'The product performs no deer-use, movement, attraction, bedding, habitat-quality, hunting-pressure, or management inference.',
])

export function mastCapacitySourceSignature(args: {
  landscapeDomainIdentitySha256: string
  landscapeDomainAlgorithmVersion: string
}) {
  const identity = String(args.landscapeDomainIdentitySha256 || '').trim().toLowerCase()
  if (!/^[0-9a-f]{64}$/.test(identity)) throw new Error('mast capacity domain identity is invalid')
  const species = FARM_WATCH_MAST_CAPACITY_PRODUCT.groupOrder.flatMap((group) =>
    FARM_WATCH_MAST_CAPACITY_GROUPS[group].map((row) => `${group}:${row.spcd}`)
  )
  return [
    'product=mast-capacity',
    'scope=' + FARM_WATCH_MAST_CAPACITY_PRODUCT.domainScope,
    'landscape_domain_identity_sha256=' + identity,
    'landscape_domain_algorithm=' + String(args.landscapeDomainAlgorithmVersion || ''),
    'source_authority=usfs-fia',
    'source_product=fia-bigmap-2018-species-aboveground-biomass',
    'source_service=' + FARM_WATCH_MAST_CAPACITY_PRODUCT.sourceService,
    'source_year=' + FARM_WATCH_MAST_CAPACITY_PRODUCT.sourceDataYear,
    'source_pixel_m=' + FARM_WATCH_MAST_CAPACITY_PRODUCT.sourcePixelMeters,
    'source_wkid=' + FARM_WATCH_MAST_CAPACITY_PRODUCT.sourceNativeWkid,
    'source_unit=' + FARM_WATCH_MAST_CAPACITY_PRODUCT.sourceValueUnit,
    'species=' + species.join(','),
    'grouping=kentucky-central-hardwood-mast-groups-v1',
  ].join('|')
}

function sha(value: unknown) {
  return /^[0-9a-f]{64}$/.test(String(value || ''))
}

export function validateMastCapacityArtifact(value: any) {
  if (
    value?.schema !== FARM_WATCH_MAST_CAPACITY_PRODUCT.outputSchemaVersion ||
    value?.method !== FARM_WATCH_MAST_CAPACITY_PRODUCT.algorithmVersion ||
    value?.status !== 'available' ||
    value?.evidence_class !== FARM_WATCH_MAST_CAPACITY_PRODUCT.semanticEvidenceClass ||
    value?.annual_mast_inference_performed !== false ||
    value?.behavioral_inference_performed !== false ||
    value?.scoring_performed !== false
  ) return false

  if (
    value?.domain?.scope !== FARM_WATCH_MAST_CAPACITY_PRODUCT.domainScope ||
    !sha(value?.domain?.identity_sha256) ||
    value?.source?.authority !== FARM_WATCH_MAST_CAPACITY_PRODUCT.sourceAuthority ||
    value?.source?.product !== FARM_WATCH_MAST_CAPACITY_PRODUCT.sourceProduct ||
    Number(value?.source?.data_year) !== FARM_WATCH_MAST_CAPACITY_PRODUCT.sourceDataYear ||
    value?.source?.value_unit !== FARM_WATCH_MAST_CAPACITY_PRODUCT.sourceValueUnit
  ) return false

  const grid = value?.grid
  const width = Number(grid?.width)
  const height = Number(grid?.height)
  if (
    !Number.isInteger(width) || width <= 0 ||
    !Number.isInteger(height) || height <= 0 ||
    Number(grid?.cell_meters) !== FARM_WATCH_MAST_CAPACITY_PRODUCT.sourcePixelMeters ||
    grid?.crs !== FARM_WATCH_MAST_CAPACITY_PRODUCT.sourceNativeCrs ||
    grid?.encoding !== 'base64-f32le-v1' ||
    typeof grid?.domain_mask_base64 !== 'string' || !grid.domain_mask_base64
  ) return false

  for (const group of FARM_WATCH_MAST_CAPACITY_PRODUCT.groupOrder) {
    if (typeof grid?.groups?.[group]?.biomass_tons_per_acre_base64 !== 'string') return false
    if (!Array.isArray(value?.source?.groups?.[group])) return false
    const expected = FARM_WATCH_MAST_CAPACITY_GROUPS[group].map((row) => row.spcd).sort((a,b)=>a-b)
    const actual = value.source.groups[group].map((row: any) => Number(row?.spcd)).sort((a: number,b: number)=>a-b)
    if (JSON.stringify(expected) !== JSON.stringify(actual)) return false
    if (!value?.summary?.scopes?.broad_3000m?.groups?.[group]) return false
  }

  return Boolean(
    Array.isArray(grid?.bbox) && grid.bbox.length === 4 &&
    value?.summary?.scopes?.property &&
    value?.summary?.scopes?.local_500m &&
    value?.summary?.scopes?.landscape_1500m &&
    value?.summary?.scopes?.broad_3000m &&
    value?.processing_source_fingerprint &&
    sha(value?.processing_source_fingerprint_sha256)
  )
}

export function mastCapacityArtifactPath(
  propertyId: string,
  inputSignature: string,
  artifactSha256: string,
) {
  return [
    'properties',
    propertyId,
    FARM_WATCH_MAST_CAPACITY_PRODUCT.productKind,
    inputSignature,
    artifactSha256 + '.json',
  ].join('/')
}
