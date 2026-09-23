import {
  type FarmWatchSeasonalEvidenceState,
} from './farm-watch-seasonal-state-contract.ts'

export const FARM_WATCH_SURFACE_WATER_STATE_PRODUCT = Object.freeze({
  key: 'surface-water-state',
  algorithmVersion: 'farm-watch-surface-water-state-resolver-v1',
  outputSchemaVersion: 'surface-water-state-v1',
  evidenceClass: 'deterministic_derived',
  operatorObservationKind: 'surface_water_presence',
  mappedPersistenceVocabulary: Object.freeze([
    'mapped_persistent',
    'mapped_seasonal',
    'mapped_temporary',
    'mapped_unknown_persistence',
  ] as const),
  currentPresenceVocabulary: Object.freeze([
    'observed_present',
    'observed_absent',
    'observed_uncertain',
    'no_current_observation',
  ] as const),
  demDrainageState: 'geometry_only',
  dynamicComponentKeys: Object.freeze([
    'precipitation',
    'drought',
    'stream',
    'rootzone_soil_moisture',
  ] as const),
  exactObservationDateRequired: true,
})

export type FarmWatchMappedWaterPersistence =
  typeof FARM_WATCH_SURFACE_WATER_STATE_PRODUCT.mappedPersistenceVocabulary[number]
export type FarmWatchCurrentWaterPresence =
  typeof FARM_WATCH_SURFACE_WATER_STATE_PRODUCT.currentPresenceVocabulary[number]

export const FARM_WATCH_SURFACE_WATER_STATE_LIMITATIONS = Object.freeze([
  'USGS 3DHP flowlines and waterbodies are mapped hydrography. Unless an authoritative persistence attribute is carried by the source record, they do not establish current water presence or perennial flow.',
  'USFWS NWI water-regime attributes describe mapped wetland hydrologic regime. A Permanently Flooded classification supports mapped persistence context but does not prove water is present on the requested date.',
  'Conditioned D8 terrain flow traces are drainage geometry only. They are not mapped streams, observed water, inferred water permanence, crossings, or deer-use evidence.',
  'QPE precipitation, U.S. Drought Monitor classification, off-property USGS stream-gauge discharge, and Crop-CASMA/SMAP root-zone soil moisture remain scoped environmental context or proxies. No numeric wet/dry threshold is invented by Surface Water State v1.',
  'Only an operator observation explicitly dated to the requested as-of date may become observed_present or observed_absent current-presence evidence. Older observations remain historical evidence and do not silently become current truth.',
  'The product performs no deer water preference, attraction, movement, bedding, habitat-quality, hunting, or management inference.',
])

export function classifyMappedWaterPersistence(args: {
  sourceSlug: string
  featureKind: string
  properties?: Record<string, unknown> | null
}): FarmWatchMappedWaterPersistence {
  const source = String(args.sourceSlug || '').toLowerCase()
  const properties = args.properties || {}
  const regime = String(properties.water_regime_name || '').toLowerCase()

  if (source === 'usfws-nwi') {
    if (regime.includes('permanently flooded')) return 'mapped_persistent'
    if (regime.includes('seasonally flooded')) return 'mapped_seasonal'
    if (regime.includes('temporary flooded') || regime.includes('temporarily flooded')) {
      return 'mapped_temporary'
    }
  }

  return 'mapped_unknown_persistence'
}

function sha(value: unknown) {
  return /^[0-9a-f]{64}$/.test(String(value || ''))
}

function seasonalState(value: unknown): value is FarmWatchSeasonalEvidenceState {
  return ['known','proxy','stale','unavailable'].includes(String(value || ''))
}

export function validateFarmWatchSurfaceWaterStateContext(value: any) {
  const p = FARM_WATCH_SURFACE_WATER_STATE_PRODUCT
  if (
    value?.schema !== p.outputSchemaVersion ||
    value?.method !== p.algorithmVersion ||
    value?.evidence_class !== p.evidenceClass ||
    !/^\d{4}-\d{2}-\d{2}$/.test(String(value?.as_of_date || '')) ||
    !Array.isArray(value?.mapped_features) ||
    !value?.dynamic_wetness_context ||
    !value?.dem_drainage ||
    !value?.source_fingerprint ||
    !sha(value?.source_fingerprint_sha256) ||
    value?.scoring_performed !== false ||
    value?.behavioral_inference_performed !== false ||
    value?.deer_water_preference_inferred !== false
  ) return false

  for (const feature of value.mapped_features) {
    if (!['flowline','waterbody','wetland'].includes(String(feature?.feature_kind || ''))) return false
    if (!p.mappedPersistenceVocabulary.includes(feature?.mapped_persistence_state)) return false
    if (!p.currentPresenceVocabulary.includes(feature?.current_presence?.state)) return false
    if (feature?.current_presence?.state !== 'no_current_observation') {
      if (feature?.current_presence?.evidence_class !== 'operator_field_observation') return false
      if (String(feature?.current_presence?.observed_date || '') !== String(value.as_of_date)) return false
    }
  }

  for (const key of p.dynamicComponentKeys) {
    const component = value.dynamic_wetness_context[key]
    if (!component || !seasonalState(component.state)) return false
  }

  if (value.dynamic_wetness_context.qualitative_wetness_state !== 'not_classified') return false
  if (value.dem_drainage.status === 'available') {
    if (value.dem_drainage.state !== p.demDrainageState) return false
    if (!sha(value.dem_drainage.materialization_identity_sha256)) return false
    if (!sha(value.dem_drainage.artifact_sha256)) return false
    if (value.dem_drainage.water_presence_inferred !== false) return false
  }

  return true
}

export function validateFarmWatchSurfaceWaterStateResponse(value: any) {
  if (!['available','partial','unavailable','missing','stale'].includes(String(value?.status || ''))) {
    return false
  }
  if (value?.status === 'missing' || value?.status === 'stale') return value?.context == null
  if (!validateFarmWatchSurfaceWaterStateContext(value?.context)) return false
  const identity = value?.identity
  return Boolean(
    identity &&
    sha(identity.boundary_sha256) &&
    sha(identity.source_signature_sha256) &&
    sha(identity.identity_sha256) &&
    identity.algorithm_version === FARM_WATCH_SURFACE_WATER_STATE_PRODUCT.algorithmVersion &&
    identity.output_schema_version === FARM_WATCH_SURFACE_WATER_STATE_PRODUCT.outputSchemaVersion
  )
}
