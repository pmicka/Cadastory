import {
  FARM_WATCH_DEER_BIOLOGICAL_STATE_PRODUCT,
  type FarmWatchDeerAgeClass,
  type FarmWatchDeerSex,
} from './farm-watch-diel-biological-state-contract.ts'

export const FARM_WATCH_DEER_RELATIONSHIP_REGISTRY_PRODUCT = Object.freeze({
  key: 'deer-relationship-registry',
  algorithmVersion: 'farm-watch-deer-relationship-registry-v1',
  outputSchemaVersion: 'deer-relationship-registry-v1',
  species: 'Odocoileus virginianus',
  ledgerVersion: '2026-09-25',
  outputKinds: Object.freeze([
    'quantitative_relative_selection',
    'ordinal_directional',
    'mechanism_context',
    'negative_constraint',
    'not_applicable',
    'insufficient_input',
  ] as const),
  directions: Object.freeze([
    'positive','negative','interaction','conditional','mixed','null_constraint','not_applicable',
  ] as const),
  coefficientTransferStates: Object.freeze([
    'authorized','not_supported','not_applicable',
  ] as const),
  evidenceStates: Object.freeze([
    'available','known','proxy','accepted','candidate_only',
    'stale','unavailable','blocked','abstained',
  ] as const),
  scales: Object.freeze([
    'individual_scenario','point','field','property','event_local',
    'local_500m','landscape_1500m','broad_3000m','regional','statewide','multiscale',
  ] as const),
})

export type DeerRelationshipOutputKind =
  typeof FARM_WATCH_DEER_RELATIONSHIP_REGISTRY_PRODUCT.outputKinds[number]
export type DeerRelationshipDirection =
  typeof FARM_WATCH_DEER_RELATIONSHIP_REGISTRY_PRODUCT.directions[number]
export type DeerRelationshipScale =
  typeof FARM_WATCH_DEER_RELATIONSHIP_REGISTRY_PRODUCT.scales[number]
export type DeerRelationshipEvidenceState =
  typeof FARM_WATCH_DEER_RELATIONSHIP_REGISTRY_PRODUCT.evidenceStates[number]

export const FARM_WATCH_DEER_MEASUREMENT_ALIGNMENTS = Object.freeze([
  'measurement_equivalent',
  'derived_equivalent',
  'calibrated_proxy',
  'mechanism_context_only',
  'unsupported',
] as const)

export type DeerMeasurementAlignment =
  typeof FARM_WATCH_DEER_MEASUREMENT_ALIGNMENTS[number]

export type DeerStudyMeasurementRequirement = {
  id: string
  binding_key: string | null
  study_variable: string
  study_protocol: string
  alignment: DeerMeasurementAlignment
  activation_requirement: 'required' | 'context_only' | 'not_applicable'
  permitted_use: string
  limitations: string[]
}

export type DeerRelationshipValueConstraint = {
  id: string
  binding_key: string
  field: string
  operator: 'equals' | 'one_of' | 'known' | 'study_specific'
  values: string[]
  rationale: string
}

export const FARM_WATCH_DEER_INPUT_PRODUCT_CATALOG = Object.freeze({
  'deer-biological-state': {
    status: 'production',
    scales: ['individual_scenario','statewide'],
    evidence_states: ['available'],
  },
  'diel-photoperiod-context': {
    status: 'production',
    scales: ['property'],
    evidence_states: ['available'],
  },
  'thermal-exposure-context': {
    status: 'production',
    scales: ['local_500m','landscape_1500m'],
    evidence_states: ['available'],
  },
  'seasonal-state': {
    status: 'production',
    scales: ['property','regional'],
    evidence_states: ['available','known','proxy','stale','unavailable'],
  },
  'field-phenology-context': {
    status: 'production_partial',
    scales: ['field','property','local_500m','landscape_1500m','broad_3000m'],
    evidence_states: ['available','known','proxy','stale','unavailable'],
  },
  'agriculture-landcover-context': {
    status: 'production_neutral_context',
    scales: ['field','property','local_500m','landscape_1500m','broad_3000m'],
    evidence_states: ['available','known','proxy'],
  },
  'current-crop-identity': {
    status: 'candidate_blocked_rights',
    scales: ['field','property','local_500m','landscape_1500m','broad_3000m'],
    evidence_states: ['candidate_only','accepted','abstained','blocked','unavailable'],
  },
  'mast-capacity': {
    status: 'production',
    scales: ['property','local_500m','landscape_1500m','broad_3000m'],
    evidence_states: ['available','unavailable'],
  },
  'annual-mast-state': {
    status: 'production_exact_year_regional_proxy',
    scales: ['property','regional'],
    evidence_states: ['available','known','proxy','stale','unavailable'],
  },
  'terrain-form-permeability': {
    status: 'production',
    scales: ['local_500m','landscape_1500m'],
    evidence_states: ['available'],
  },
  'lidar-physical-structure': {
    status: 'production_neutral_only',
    scales: ['local_500m'],
    evidence_states: ['available'],
  },
  'study-aligned-vegetation-height-context': {
    status: 'production_validated_neutral_measurement',
    scales: ['local_500m'],
    evidence_states: ['available'],
  },
  'spatial-edge-patch-context': {
    status: 'production',
    scales: ['local_500m'],
    evidence_states: ['available'],
  },
  'horizontal-visibility-context': {
    status: 'production_neutral_only',
    scales: ['local_500m'],
    evidence_states: ['available'],
  },
  'mapped-hydrography-context': {
    status: 'production_neutral_context',
    scales: ['local_500m','landscape_1500m','broad_3000m'],
    evidence_states: ['available','known'],
  },
  'stand-vulnerability-zone-context': {
    status: 'planned_measurement_alignment',
    scales: ['event_local','local_500m'],
    evidence_states: ['available','known','unavailable'],
  },
  'conifer-cover-context': {
    status: 'production_calibrated_proxy',
    scales: ['property','local_500m','landscape_1500m','broad_3000m'],
    evidence_states: ['available','known','proxy','unavailable'],
  },
  'predator-occurrence-context': {
    status: 'planned',
    scales: ['landscape_1500m','broad_3000m','regional'],
    evidence_states: ['available','known','proxy','unavailable'],
  },
  'forest-type-context': {
    status: 'production_source_substituted',
    scales: ['point','property','local_500m','landscape_1500m','broad_3000m'],
    evidence_states: ['available','known','proxy','unavailable'],
  },
  'low-height-concealment-context': {
    status: 'planned_measurement_alignment',
    scales: ['local_500m'],
    evidence_states: ['available','unavailable'],
  },
  'human-activity-context': {
    status: 'planned',
    scales: ['event_local','property','local_500m'],
    evidence_states: ['available','known','proxy','stale','unavailable'],
  },
  'human-footprint-context': {
    status: 'production_neutral_measurement',
    scales: ['local_500m','landscape_1500m','broad_3000m'],
    evidence_states: ['available','known','proxy','stale','unavailable'],
  },
  'road-focal-context': {
    status: 'production_on_demand_neutral_measurement',
    scales: ['event_local','local_500m','landscape_1500m'],
    evidence_states: ['available','unavailable'],
  },
  'multiscale-cover-context': {
    status: 'production_neutral_measurement',
    scales: ['multiscale'],
    evidence_states: ['available'],
  },
  'multiscale-forest-context': {
    status: 'production_on_demand_neutral_measurement',
    scales: ['event_local','local_500m','landscape_1500m','multiscale'],
    evidence_states: ['available','unavailable'],
  },
  'browse-resource-context': {
    status: 'planned',
    scales: ['property','local_500m','landscape_1500m'],
    evidence_states: ['available','known','proxy','stale','unavailable'],
  },
  'managed-food-feature-context': {
    status: 'production_static_configured',
    scales: ['field','property','local_500m'],
    evidence_states: ['available','known','unavailable'],
  },
  'managed-water-source-context': {
    status: 'production_static_configured',
    scales: ['point','property','local_500m'],
    evidence_states: ['available','known','unavailable'],
  },
  'surface-water-state': {
    status: 'production',
    scales: ['property','local_500m','landscape_1500m'],
    evidence_states: ['available','known','proxy','stale','unavailable'],
  },
  'snow-winter-severity-context': {
    status: 'production_source_substituted_neutral_measurement',
    scales: ['property','regional'],
    evidence_states: ['available','known','proxy','stale','unavailable'],
  },
  'extreme-weather-event-context': {
    status: 'production_authoritative_event_gate',
    scales: ['event_local','property','regional'],
    evidence_states: ['available','known','proxy','stale','unavailable'],
  },
} as const)

export const FARM_WATCH_DEER_BLOCKED_UNIVERSAL_ASSUMPTIONS = Object.freeze([
  'moon_phase_generic_movement',
  'barometric_pressure_generic_movement',
  'wind_generic_movement',
  'cold_generic_movement',
  'south_facing_slope_generic_preference',
  'north_facing_slope_generic_preference',
  'ridge_generic_corridor',
  'draw_generic_corridor',
  'saddle_generic_funnel',
  'roads_generic_avoidance',
  'roads_generic_selection',
  'dense_vegetation_generic_bedding_security_cover',
  'field_edge_generic_deer_use',
  'cdl_identity_equals_current_food',
  'nearest_water_or_discharge_equals_deer_use',
  'open_hunting_season_equals_current_pressure',
] as const)

export type DeerRelationshipProductKey =
  keyof typeof FARM_WATCH_DEER_INPUT_PRODUCT_CATALOG

type ProductKey = DeerRelationshipProductKey

export type DeerRelationshipInputRequirement = {
  key: string
  product_keys: ProductKey[]
  match: 'any' | 'all'
  required: boolean
  allowed_evidence_states: DeerRelationshipEvidenceState[]
  allowed_scales: DeerRelationshipScale[]
  freshness_policy: 'current_required' | 'state_explicit' | 'static_context_ok'
}

export type DeerRelationshipBiologicalGate = {
  sex: FarmWatchDeerSex[] | null
  age_class: FarmWatchDeerAgeClass[] | null
  movement_state: string[] | null
  reproductive_state: string[] | null
  seasons: string[] | null
  diel_periods: string[] | null
  regional_reproductive_context: string[] | null
  required_explicit_dimensions: string[]
}

export type DeerRelationshipRecord = {
  relationship_id: string
  ledger_ids: string[]
  source_citations: string[]
  title: string
  module_family: string
  response_variable: string
  required_inputs: DeerRelationshipInputRequirement[]
  biological_state_gates: DeerRelationshipBiologicalGate
  spatial_scale: {
    relationship_scales: DeerRelationshipScale[]
    notes: string
  }
  temporal_scale: string
  relationship_form: string
  direction: DeerRelationshipDirection
  supported_nonlinearity: string | null
  coefficient_transfer: {
    status: 'authorized' | 'not_supported' | 'not_applicable'
    numeric_parameters: number[]
  }
  parameter_source_version: string
  null_or_blocked_conditions: string[]
  blocked_universal_assumptions: string[]
  output_kind: DeerRelationshipOutputKind
  limitations: string[]
  study_measurements: DeerStudyMeasurementRequirement[]
  value_constraints: DeerRelationshipValueConstraint[]
  biological_state_annotation?: {
    state_codes?: string[]
    sex?: FarmWatchDeerSex[]
    require_known_age?: boolean
    regional_reproductive_context?: string[]
  }
}

const ALL_SEX = [...FARM_WATCH_DEER_BIOLOGICAL_STATE_PRODUCT.sexVocabulary]
const ALL_AGE = [...FARM_WATCH_DEER_BIOLOGICAL_STATE_PRODUCT.ageVocabulary]
const PARAMETER_SOURCE = 'FARM_WATCH_DEER_SCIENCE_EVIDENCE_LEDGER.md@2026-09-25'

function req(
  key: string,
  product_keys: ProductKey[],
  allowed_scales: DeerRelationshipScale[],
  allowed_evidence_states: DeerRelationshipEvidenceState[] = ['available'],
  freshness_policy: DeerRelationshipInputRequirement['freshness_policy'] = 'current_required',
  match: DeerRelationshipInputRequirement['match'] = 'any',
): DeerRelationshipInputRequirement {
  return {
    key,
    product_keys,
    match,
    required: true,
    allowed_evidence_states,
    allowed_scales,
    freshness_policy,
  }
}

function gate(
  value: Partial<DeerRelationshipBiologicalGate> = {},
): DeerRelationshipBiologicalGate {
  return {
    sex: value.sex ?? null,
    age_class: value.age_class ?? null,
    movement_state: value.movement_state ?? null,
    reproductive_state: value.reproductive_state ?? null,
    seasons: value.seasons ?? null,
    diel_periods: value.diel_periods ?? null,
    regional_reproductive_context: value.regional_reproductive_context ?? null,
    required_explicit_dimensions: value.required_explicit_dimensions ?? [],
  }
}

function record(
  value: Omit<DeerRelationshipRecord,'study_measurements'|'value_constraints'> &
    Partial<Pick<DeerRelationshipRecord,'study_measurements'|'value_constraints'>>,
): DeerRelationshipRecord {
  return Object.freeze({
    ...value,
    study_measurements: value.study_measurements || [],
    value_constraints: value.value_constraints || [],
  })
}

function measurement(
  id: string,
  binding_key: string | null,
  study_variable: string,
  study_protocol: string,
  alignment: DeerMeasurementAlignment,
  activation_requirement: DeerStudyMeasurementRequirement['activation_requirement'],
  permitted_use: string,
  limitations: string[] = [],
): DeerStudyMeasurementRequirement {
  return {
    id,
    binding_key,
    study_variable,
    study_protocol,
    alignment,
    activation_requirement,
    permitted_use,
    limitations,
  }
}

function valueConstraint(
  id: string,
  binding_key: string,
  field: string,
  operator: DeerRelationshipValueConstraint['operator'],
  values: string[],
  rationale: string,
): DeerRelationshipValueConstraint {
  return { id, binding_key, field, operator, values, rationale }
}

export function deerRelationshipStudyFidelityStatus(row: DeerRelationshipRecord) {
  const blockers = row.study_measurements.filter((measurement) =>
    measurement.activation_requirement === 'required' &&
    (measurement.alignment === 'mechanism_context_only' || measurement.alignment === 'unsupported')
  )
  const contextOnly = row.study_measurements.filter((measurement) =>
    measurement.activation_requirement === 'context_only' ||
    measurement.alignment === 'mechanism_context_only'
  )
  return {
    status: blockers.length
      ? 'blocked_measurement_alignment'
      : contextOnly.length
        ? 'context_only'
        : 'module_eligible',
    blocker_ids: blockers.map((measurement) => measurement.id),
    context_only_ids: contextOnly.map((measurement) => measurement.id),
  } as const
}

export const FARM_WATCH_DEER_RELATIONSHIPS: readonly DeerRelationshipRecord[] = Object.freeze([
  record({
    relationship_id: 'FW-R01-summer-thermal-resource-tradeoff',
    ledger_ids: ['FW-D01'],
    source_citations: ['Wiemers et al. 2014, Wildlife Biology 20:47-56, DOI:10.2981/wlb.13029'],
    title: 'Adult-male summer thermal resource tradeoff',
    module_family: 'thermal_resource_tradeoff',
    response_variable: 'within-habitat resource selection',
    required_inputs: [
      req('biological_state',['deer-biological-state'],['individual_scenario']),
      req('diel_state',['diel-photoperiod-context'],['property']),
      req('thermal_exposure',['thermal-exposure-context'],['local_500m','landscape_1500m']),
      req('vegetation_height',['study-aligned-vegetation-height-context'],['local_500m']),
      req('woody_canopy',['spatial-edge-patch-context'],['local_500m']),
      req('resource_state',['field-phenology-context','browse-resource-context'],['field','property','local_500m'],['available','known','proxy']),
    ],
    biological_state_gates: gate({
      sex:['male'], age_class:['adult'], seasons:['summer'],
      required_explicit_dimensions:['sex','age_class','season','diel_period'],
    }),
    spatial_scale:{relationship_scales:['local_500m','landscape_1500m'],notes:'Within-habitat selection; preserve resource and thermal context at the evaluated scale.'},
    temporal_scale:'summer; activity-period interaction',
    relationship_form:'thermal exposure, vegetation structure and forage interact with activity period',
    direction:'interaction',
    supported_nonlinearity:null,
    coefficient_transfer:{status:'not_supported',numeric_parameters:[]},
    parameter_source_version:PARAMETER_SOURCE,
    null_or_blocked_conditions:['concealment cover was not selected in this study'],
    blocked_universal_assumptions:['cold_generic_movement'],
    output_kind:'ordinal_directional',
    limitations:['South Texas adult males; no generic shade or concealment preference and no transferred coefficients.'],
    study_measurements:[
      measurement('FW-M01-operative-temperature','thermal_exposure','operative temperature','Study used blackglobe-based operative temperature representing convective and radiant heat exchange.','mechanism_context_only','required','Physical thermal context only until an operative-temperature-equivalent or calibrated proxy exists.',['Current thermal-exposure-context explicitly does not calculate operative temperature.']),
      measurement('FW-M02-vegetation-height','vegetation_height','vegetation height','Study derived vegetation height from a 1.2 m first-return elevation surface minus a 1.2 m bare-ground elevation surface.','derived_equivalent','required','Production-validated study-aligned first-return-minus-ground vegetation height may satisfy the physical vegetation-height input.',['Farm Watch preserves the study variable and 1.2 m support but uses deterministic cell-mean/local-fill surfaces rather than the original TIN interpolation.','Cells carrying the negative-raw-height-clamped-to-zero support flag are unavailable for scientific height use and must not be interpreted as genuine 0 m vegetation.']),
      measurement('FW-M03-forage-index','resource_state','forage index','Study forage index combined standing crop, crude protein and acid detergent fiber.','unsupported','required','No deer relationship activation.',['Current field phenology or browse context does not reproduce the study forage index.']),
      measurement('FW-M04-woody-canopy','woody_canopy','woody plant canopy cover','Study evaluated woody plant canopy cover explicitly in the midday thermal model.','mechanism_context_only','required','Canopy context only until the remote canopy metric is aligned to the study variable.'),
      measurement('FW-M05-activity-period','diel_state','movement-defined activity period','Study defined morning, midday, evening and night from observed movement patterns; night was one hour after sundown to one hour before sunrise.','mechanism_context_only','required','Solar phase may contextualize time of day but is not measurement-equivalent to the study activity periods.'),
    ],
  }),
  record({
    relationship_id:'FW-R02-thermal-refuge-time-shift',
    ledger_ids:['FW-D02'],
    source_citations:['Wolff et al. 2020, Ecology and Evolution 10:2579-2587, DOI:10.1002/ece3.6087'],
    title:'Thermal refuge can shift feeding in space and time',
    module_family:'thermal_resource_tradeoff',
    response_variable:'feeding timing and feeder use',
    required_inputs:[
      req('diel_state',['diel-photoperiod-context'],['property']),
      req('thermal_exposure',['thermal-exposure-context'],['local_500m','landscape_1500m']),
    ],
    biological_state_gates:gate({seasons:['spring','summer'],required_explicit_dimensions:['season','diel_period']}),
    spatial_scale:{relationship_scales:['local_500m'],notes:'Mechanism support from a controlled feeder experiment.'},
    temporal_scale:'daytime versus cooler crepuscular periods',
    relationship_form:'thermal refuge modifies temporal and spatial feeding opportunity',
    direction:'conditional',
    supported_nonlinearity:null,
    coefficient_transfer:{status:'not_supported',numeric_parameters:[]},
    parameter_source_version:PARAMETER_SOURCE,
    null_or_blocked_conditions:['hourly solar radiation was not a sufficient standalone explanation'],
    blocked_universal_assumptions:['cold_generic_movement'],
    output_kind:'mechanism_context',
    limitations:['Enclosure/feeder experiment; reported consumption differences are not transferable coefficients.'],
    study_measurements:[
      measurement('FW-M06-shade-thermal-treatment','thermal_exposure','shaded versus unshaded feeder thermal environment','Study experimentally contrasted shaded and unshaded feeders and observed use/consumption shifts.','mechanism_context_only','context_only','Supports thermal-refuge mechanism context only; experimental effect sizes are not transferred.'),
      measurement('FW-M07-feeding-time-window','diel_state','daytime versus cooler crepuscular feeding use','Study response was feeder use and consumption across thermal/time treatment conditions.','mechanism_context_only','context_only','Use as qualitative temporal thermal context only.'),
    ],
  }),
  record({
    relationship_id:'FW-R03-winter-snow-conifer-context',
    ledger_ids:['FW-D03'],
    source_citations:['DelGiudice, Fieberg & Sampson 2013, PLOS ONE 8:e65368, DOI:10.1371/journal.pone.0065368'],
    title:'Winter dense-cover use is snow and availability conditional',
    module_family:'thermal_resource_tradeoff',
    response_variable:'winter dense-conifer versus open-vegetation use',
    required_inputs:[
      req('winter_severity',['snow-winter-severity-context'],['property','regional'],['available','known','proxy']),
      req('thermal_exposure',['thermal-exposure-context'],['local_500m','landscape_1500m']),
      req('structure_context',['spatial-edge-patch-context'],['local_500m']),
      req('conifer_cover',['conifer-cover-context'],['broad_3000m'],['available','known','proxy'],'static_context_ok'),
      req('diel_state',['diel-photoperiod-context'],['property']),
    ],
    biological_state_gates:gate({sex:['female'],seasons:['winter'],required_explicit_dimensions:['sex','season','diel_period']}),
    spatial_scale:{relationship_scales:['local_500m','landscape_1500m','broad_3000m'],notes:'Local thermal/structure context is paired with broad site-scale conifer availability; the Flat Creek broad_3000m domain is the closest Farm Watch analogue to the source study-site availability scale.'},
    temporal_scale:'winter; daytime response conditional on snow and temperature',
    relationship_form:'snow depth, cover availability and solar exposure interact',
    direction:'interaction',
    supported_nonlinearity:null,
    coefficient_transfer:{status:'not_supported',numeric_parameters:[]},
    parameter_source_version:PARAMETER_SOURCE,
    null_or_blocked_conditions:[],
    blocked_universal_assumptions:['dense_vegetation_generic_bedding_security_cover','cold_generic_movement'],
    output_kind:'mechanism_context',
    limitations:['Northern severe-winter system; not a generic Kentucky dense-cover rule.'],
    study_measurements:[
      measurement(
        'FW-M08-snow-depth-severity',
        'winter_severity',
        'daily snow depth (cm) and minimum daily temperature (C), with Minnesota WSI retained as source context',
        'DelGiudice et al. modeled winter cover use with daily snow depth and minimum daily temperature directly. The Minnesota winter-severity index separately accumulated one point for snow depth at least 38 cm and one point for minimum temperature at or below -17.7 C during November-May.',
        'derived_equivalent',
        'required',
        'Farm Watch supplies neutral daily physical context using NOAA/NWS/NOHRSC assimilated snow depth plus the minimum of centrally persisted NOAA/NCEP HRRR f00 analyses over the property local day. The source-defined Minnesota WSI arithmetic is retained only as provenance/context; no Minnesota severity category, response coefficient, or Kentucky biological threshold transfers.',
        [
          'NOHRSC snow depth is a modeled/observationally assimilated analysis rather than an on-property ruler measurement.',
          'HRRR daily minimum is derived from hourly modeled analyses and requires at least 75% local-day coverage; incomplete coverage remains partial.',
          'The separate FW-M09 conifer availability input is represented by a production calibrated proxy; M08 alone still does not authorize the winter-cover relationship.',
        ],
      ),
      measurement(
        'FW-M09-dense-conifer-cover',
        'conifer_cover',
        'availability of moderately dense conifer (40% to <70% canopy closure) and dense conifer (>=70%) relative to other habitat',
        'Study stands were delineated from leaf-off color-infrared aerial photography, assigned dominant tree species and conifer canopy-closure classes, and represented in the model as moderately dense conifer, dense conifer, and other; other included open conifer below 40% closure, openings, and hardwoods. Habitat availability was calculated at the study-site scale and updated for harvest/succession.',
        'calibrated_proxy',
        'required',
        'Production conifer-cover-context-v1 uses a matched-year 30 m Annual NLCD Evergreen Forest (42) dominant-type mask crossed with NLCD Tree Canopy Cover using the exact <40 / 40-<70 / >=70 percent closure thresholds. Mixed Forest (43) is conservatively retained in other. Broad_3000m availability is the relationship binding; property/500 m/1.5 km summaries remain neutral diagnostics. Representative 2024 KyFromAbove imagery spot checks at Flat Creek supported the conservative class treatment.',
        [
          'Annual NLCD Evergreen Forest plus modeled TCC is a national source substitution, not the source study air-photo dominant-species interpretation.',
          'The rare moderate class is edge-sensitive in local imagery and remains a calibrated proxy rather than a derived-equivalent measurement.',
          'No open-conifer source cell occurred in the Flat Creek broad domain during initial validation, so that class boundary was not locally image-validated.',
          'No DelGiudice response coefficient, Minnesota availability effect magnitude, dense-cover preference, or Kentucky winter threshold transfers.',
        ],
      ),
      measurement('FW-M10-winter-solar-context','thermal_exposure','daytime solar/thermal exposure under severe winter conditions','Study interpretation requires solar exposure jointly with snow and minimum temperature.','mechanism_context_only','context_only','Current thermal exposure provides physical context but is not the study winter-cover measurement.'),
    ],
  }),
  record({
    relationship_id:'FW-R04-hot-bedsite-structure-context',
    ledger_ids:['FW-D04'],
    source_citations:['Gallina et al. 2010, Journal of Arid Environments 74:373-377, DOI:10.1016/j.jaridenv.2009.09.032'],
    title:'Hot-season bedsite thermal and structural context',
    module_family:'thermal_resource_tradeoff',
    response_variable:'daytime bedsite selection',
    required_inputs:[
      req('thermal_exposure',['thermal-exposure-context'],['local_500m']),
      req('concealment_measurement',['low-height-concealment-context'],['local_500m']),
      req('biological_state',['deer-biological-state'],['individual_scenario']),
    ],
    biological_state_gates:gate({seasons:['summer'],required_explicit_dimensions:['season','sex','reproductive_state']}),
    spatial_scale:{relationship_scales:['point','local_500m'],notes:'Bedsite-specific relationship; current general horizontal-visibility product is not measurement-equivalent.'},
    temporal_scale:'hot-season daytime resting',
    relationship_form:'thermal and concealment structure at occupied bedsites versus random sites',
    direction:'conditional',
    supported_nonlinearity:null,
    coefficient_transfer:{status:'not_supported',numeric_parameters:[]},
    parameter_source_version:PARAMETER_SOURCE,
    null_or_blocked_conditions:['requires research-aligned low-height concealment measurement before deer interpretation'],
    blocked_universal_assumptions:['dense_vegetation_generic_bedding_security_cover'],
    output_kind:'mechanism_context',
    limitations:['Semiarid Mexico; do not substitute 1.5/3/6 m general viewshed for the field concealment protocol.'],
    study_measurements:[
      measurement('FW-M11-gallina-concealment-profile','concealment_measurement','directional low-height concealment profile','Study measured concealment of a 2 m target from 15 m away in four 50 cm vertical strata and cardinal directions.','unsupported','required','No bedsite relationship activation until low-height-concealment-context reproduces or is calibrated to that field protocol.',['Batch 6 horizontal-visibility-context is explicitly not measurement-equivalent.']),
      measurement('FW-M12-gallina-thermal-cover','thermal_exposure','bedsite thermal-cover structure','Study evaluated physical vegetation/thermal cover at occupied bedsites versus random sites.','mechanism_context_only','context_only','Current thermal exposure may provide mechanism context but does not reproduce the study vegetation-cover protocol.'),
    ],
  }),
  record({
    relationship_id:'FW-R05-fawning-female-low-concealment',
    ledger_ids:['FW-D04'],
    source_citations:['Gallina et al. 2010, Journal of Arid Environments 74:373-377, DOI:10.1016/j.jaridenv.2009.09.032'],
    title:'Fawning-female low-height concealment context',
    module_family:'thermal_resource_tradeoff',
    response_variable:'daytime bedsite selection during fawning',
    required_inputs:[
      req('concealment_measurement',['low-height-concealment-context'],['local_500m']),
      req('biological_state',['deer-biological-state'],['individual_scenario']),
    ],
    biological_state_gates:gate({
      sex:['female'], reproductive_state:['parturition','lactation'], seasons:['spring','summer'],
      required_explicit_dimensions:['sex','reproductive_state','season'],
    }),
    spatial_scale:{relationship_scales:['point','local_500m'],notes:'Study signal occurred in 0-50 cm and 50-100 cm concealment strata.'},
    temporal_scale:'fawning period daytime bedsite',
    relationship_form:'greater low-height concealment at occupied bedsites',
    direction:'positive',
    supported_nonlinearity:'separate 0-50 cm and 50-100 cm field strata',
    coefficient_transfer:{status:'not_supported',numeric_parameters:[]},
    parameter_source_version:PARAMETER_SOURCE,
    null_or_blocked_conditions:['abstain when reproductive state or aligned concealment input is unknown'],
    blocked_universal_assumptions:['dense_vegetation_generic_bedding_security_cover'],
    output_kind:'mechanism_context',
    limitations:['Relationship form is state-specific; no universal bedding-cover classification.'],
    study_measurements:[
      measurement('FW-M13-gallina-low-strata','concealment_measurement','0-50 cm and 50-100 cm concealment','Study fawning-female signal was specifically in the two lowest 50 cm concealment strata.','unsupported','required','No fawning concealment relationship activation until those vertical strata are represented.'),
    ],
  }),
  record({
    relationship_id:'FW-R06-moon-phase-negative-constraint',
    ledger_ids:['FW-D05'],
    source_citations:['Webb et al. 2010, International Journal of Ecology 2010:459610, DOI:10.1155/2010/459610'],
    title:'Moon phase is blocked as a generic movement term',
    module_family:'global_negative_constraints',
    response_variable:'daily, nocturnal and diurnal movement',
    required_inputs:[],
    biological_state_gates:gate(),
    spatial_scale:{relationship_scales:['regional'],notes:'Negative constraint applies to generic module design rather than a spatial surface.'},
    temporal_scale:'daily and fine-scale movement across seasons',
    relationship_form:'reported null effect',
    direction:'null_constraint',
    supported_nonlinearity:null,
    coefficient_transfer:{status:'not_applicable',numeric_parameters:[]},
    parameter_source_version:PARAMETER_SOURCE,
    null_or_blocked_conditions:['moon phase had no effect in the study'],
    blocked_universal_assumptions:['moon_phase_generic_movement'],
    output_kind:'negative_constraint',
    limitations:['A future contradictory high-quality evidence review would be required to revise this block.'],
  }),
  record({
    relationship_id:'FW-R07-routine-weather-negative-constraint',
    ledger_ids:['FW-D05'],
    source_citations:['Webb et al. 2010, International Journal of Ecology 2010:459610, DOI:10.1155/2010/459610'],
    title:'Routine short-term weather is blocked as a universal movement multiplier',
    module_family:'global_negative_constraints',
    response_variable:'fine-scale movement',
    required_inputs:[],
    biological_state_gates:gate(),
    spatial_scale:{relationship_scales:['regional'],notes:'Negative constraint on generic weather scoring.'},
    temporal_scale:'hourly to daily',
    relationship_form:'inconsistent within-season weather effects',
    direction:'null_constraint',
    supported_nonlinearity:null,
    coefficient_transfer:{status:'not_applicable',numeric_parameters:[]},
    parameter_source_version:PARAMETER_SOURCE,
    null_or_blocked_conditions:['ordinary short-term weather effects were inconsistent'],
    blocked_universal_assumptions:['barometric_pressure_generic_movement','wind_generic_movement','cold_generic_movement'],
    output_kind:'negative_constraint',
    limitations:['Extreme events and physical thermal mechanisms remain separate relationship families.'],
  }),
  record({
    relationship_id:'FW-R08-reproductive-diel-movement-context',
    ledger_ids:['FW-D05'],
    source_citations:['Webb et al. 2010, International Journal of Ecology 2010:459610, DOI:10.1155/2010/459610'],
    title:'Crepuscular movement context without transferred reproductive magnitude',
    module_family:'reproductive_movement',
    response_variable:'diel movement pattern',
    required_inputs:[
      req('biological_state',['deer-biological-state'],['individual_scenario']),
      req('diel_state',['diel-photoperiod-context'],['property']),
    ],
    biological_state_gates:gate({required_explicit_dimensions:['diel_period']}),
    spatial_scale:{relationship_scales:['property','regional'],notes:'Context relationship; no transferred movement-rate coefficient.'},
    temporal_scale:'diel and reproductive phases',
    relationship_form:'crepuscular movement pattern only; sex/reproductive movement differences require separate state-specific relationships',
    direction:'conditional',
    supported_nonlinearity:null,
    coefficient_transfer:{status:'not_supported',numeric_parameters:[]},
    parameter_source_version:PARAMETER_SOURCE,
    null_or_blocked_conditions:[],
    blocked_universal_assumptions:[],
    output_kind:'mechanism_context',
    limitations:['Population-specific movement magnitudes and the study activity-period windows are not transferred.'],
    biological_state_annotation:{},
    study_measurements:[
      measurement('FW-M14-webb-activity-period','diel_state','study-defined diel activity period','Study classified movement into daily, diurnal, nocturnal and crepuscular periods using its own movement/time windows.','mechanism_context_only','context_only','Farm Watch solar phase may provide time-of-day context but is not measurement-equivalent to the study movement windows.'),
    ],
  }),
  record({
    relationship_id:'FW-R09-male-breeding-age-movement',
    ledger_ids:['FW-D06'],
    source_citations:['Hunsaker et al. 2025, Ecology and Evolution 15:e71589, DOI:10.1002/ece3.71589'],
    title:'Male breeding-season movement is age and timing dependent',
    module_family:'reproductive_movement',
    response_variable:'hourly movement rate and daily range',
    required_inputs:[req('biological_state',['deer-biological-state'],['individual_scenario','statewide'])],
    biological_state_gates:gate({
      sex:['male'], age_class:['yearling','adult'], regional_reproductive_context:['within_documented_breeding_season','within_peak_month_context'],
      required_explicit_dimensions:['sex','age_class','regional_reproductive_context'],
    }),
    spatial_scale:{relationship_scales:['property','regional'],notes:'Relationship form only; Wisconsin timing is not a Kentucky parameter.'},
    temporal_scale:'breeding season',
    relationship_form:'age-by-date breeding-season movement context',
    direction:'interaction',
    supported_nonlinearity:'age-class differences and breeding-season changepoint form',
    coefficient_transfer:{status:'not_supported',numeric_parameters:[]},
    parameter_source_version:PARAMETER_SOURCE,
    null_or_blocked_conditions:['abstain when male age is unknown'],
    blocked_universal_assumptions:['open_hunting_season_equals_current_pressure'],
    output_kind:'ordinal_directional',
    limitations:['Do not transfer Wisconsin dates or movement magnitudes to Kentucky.'],
    biological_state_annotation:{
      sex:['male'],require_known_age:true,
      regional_reproductive_context:['within_documented_breeding_season','within_peak_month_context'],
    },
    study_measurements:[
      measurement('FW-M15-hunsaker-male-age','biological_state','male age class','Study distinguished yearlings, 2-year-old males, and males 3 years and older; 2-year-olds had the highest hourly movement and larger daily ranges, while 3+ males had the greatest daily movement variance.','unsupported','required','No age-dependent movement relationship activation until Farm Watch can distinguish the study age classes.',['Current juvenile/yearling/adult vocabulary collapses 2-year-old and 3+ males into adult.']),
      measurement('FW-M16-hunsaker-breeding-window','biological_state','population breeding-season timing','Study changepoint timing was estimated for southwest Wisconsin and is not a Kentucky date parameter.','mechanism_context_only','context_only','Kentucky regional breeding context may gate season membership only; Wisconsin dates and movement magnitudes are not transferred.'),
    ],
  }),
  record({
    relationship_id:'FW-R10-firearm-opening-negative-constraint',
    ledger_ids:['FW-D06'],
    source_citations:['Hunsaker et al. 2025, Ecology and Evolution 15:e71589, DOI:10.1002/ece3.71589'],
    title:'Firearm opening is not a generic movement trigger',
    module_family:'global_negative_constraints',
    response_variable:'movement rate',
    required_inputs:[],
    biological_state_gates:gate(),
    spatial_scale:{relationship_scales:['regional'],notes:'Negative constraint on season-opening heuristics.'},
    temporal_scale:'firearm opening weekend',
    relationship_form:'reported null effect',
    direction:'null_constraint',
    supported_nonlinearity:null,
    coefficient_transfer:{status:'not_applicable',numeric_parameters:[]},
    parameter_source_version:PARAMETER_SOURCE,
    null_or_blocked_conditions:['firearm opening weekend had no significant movement-rate effect'],
    blocked_universal_assumptions:['open_hunting_season_equals_current_pressure'],
    output_kind:'negative_constraint',
    limitations:['Actual localized hunting pressure remains a separate evidence requirement.'],
  }),
  record({
    relationship_id:'FW-R11-mast-fall-space-use',
    ledger_ids:['FW-D07'],
    source_citations:['McShea & Schwede 1993, Journal of Mammalogy 74:999-1006, DOI:10.2307/1382439'],
    title:'Annual mast fall can restructure space use and foraging',
    module_family:'mast_response',
    response_variable:'home-range adjustment and foraging behavior',
    required_inputs:[
      req('mast_capacity',['mast-capacity'],['property','local_500m','landscape_1500m','broad_3000m'],['available'],'static_context_ok'),
      req('annual_mast_state',['annual-mast-state'],['property','regional'],['available','known']),
      req('biological_state',['deer-biological-state'],['individual_scenario']),
    ],
    biological_state_gates:gate({sex:['female'],seasons:['fall'],required_explicit_dimensions:['sex','season']}),
    spatial_scale:{relationship_scales:['property','local_500m','landscape_1500m'],notes:'Capacity and annual production must remain separate inputs.'},
    temporal_scale:'mast-fall period',
    relationship_form:'space use shifts toward acorn-producing areas when annual mast is available',
    direction:'positive',
    supported_nonlinearity:null,
    coefficient_transfer:{status:'not_supported',numeric_parameters:[]},
    parameter_source_version:PARAMETER_SOURCE,
    null_or_blocked_conditions:['mast capacity alone cannot activate the relationship'],
    blocked_universal_assumptions:[],
    output_kind:'ordinal_directional',
    limitations:['No current-year mast state means insufficient input; modeled tree capacity is not mast production. KDFWR annual survey state is a regional proxy for an unsurveyed property, not property mast abundance.'],
    study_measurements:[
      measurement('FW-M17-annual-mast-fall','annual_mast_state','annual acorn mast fall / production','Study related female deer space use and foraging to contemporaneous acorn mast fall in the study forest.','calibrated_proxy','required','Exact-year KDFWR statewide/regional mast survey state may satisfy the annual-state input only as an authoritative regional proxy. It must not be represented as measured property mast abundance.',['No prior-year carry-forward is allowed.','Property-specific mast abundance remains unknown unless separately observed.']),
      measurement('FW-M18-mast-producing-area','mast_capacity','acorn-producing area availability','Study deer shifted ranges to include acorn-producing areas during mast fall.','mechanism_context_only','context_only','Modeled mast-producing species capacity is potential resource structure, not observed annual acorn production.'),
    ],
  }),
  record({
    relationship_id:'FW-R12-crop-phenology-home-range-response',
    ledger_ids:['FW-D08'],
    source_citations:['Vercauteren & Hygnstrom 1998, Journal of Wildlife Management 62:280-285, DOI:10.2307/3802289'],
    title:'Female space use can respond to corn phenology and harvest',
    module_family:'agriculture_resource_response',
    response_variable:'home-range center and size',
    required_inputs:[
      req('current_crop_identity',['current-crop-identity'],['field'],['accepted']),
      req('field_phenology',['field-phenology-context'],['field'],['available','known']),
      req('cover_context',['spatial-edge-patch-context'],['local_500m']),
      req('biological_state',['deer-biological-state'],['individual_scenario']),
    ],
    biological_state_gates:gate({sex:['female'],required_explicit_dimensions:['sex']}),
    spatial_scale:{relationship_scales:['field','property','local_500m'],notes:'Field-level crop state is required; stale CDL is not current food.'},
    temporal_scale:'crop stage and post-harvest transition',
    relationship_form:'space-use center and range respond to crop stage and harvest',
    direction:'conditional',
    supported_nonlinearity:'pre-harvest versus post-harvest state transition',
    coefficient_transfer:{status:'not_supported',numeric_parameters:[]},
    parameter_source_version:PARAMETER_SOURCE,
    null_or_blocked_conditions:['abstain when current crop identity or harvest state is unavailable'],
    blocked_universal_assumptions:['cdl_identity_equals_current_food'],
    output_kind:'ordinal_directional',
    limitations:['Nebraska/Iowa female study; distances and range-size changes are not Kentucky coefficients.'],
    study_measurements:[
      measurement('FW-M19-current-corn-identity','current_crop_identity','current field identity as corn','Study response was explicitly tied to corn development and harvest.','unsupported','required','No relationship activation while current-season crop identity remains unresolved.'),
      measurement('FW-M20-corn-stage-harvest','field_phenology','corn tasseling/silking and post-harvest state','Study contrasted female home-range response around corn tasseling/silking and after harvest.','unsupported','required','Regional crop progress or raw vegetation-index change cannot substitute for field-level corn stage/harvest state.'),
      measurement('FW-M21-permanent-cover','cover_context','permanent-cover geometry','Study interpreted post-harvest shifts relative to crop fields and permanent cover.','mechanism_context_only','context_only','Current spatial cover context is related geometry but not a study-calibrated permanent-cover measurement.'),
    ],
    value_constraints:[
      valueConstraint('FW-C01-crop-is-corn','current_crop_identity','crop_name','equals',['Corn'],'FW-D08 is a corn-specific relationship; another known crop cannot satisfy it.'),
      valueConstraint('FW-C02-corn-stage','field_phenology','phenology_state','one_of',['tasseling_or_silking','harvested'],'The relationship requires the study-relevant corn stage or post-harvest transition, not merely a known vegetation trajectory.'),
    ],
  }),
  record({
    relationship_id:'FW-R13-winter-food-configuration-activity',
    ledger_ids:['FW-D09'],
    source_citations:['Delisle et al. 2024, Scientific Reports 14:10223, DOI:10.1038/s41598-024-60079-6'],
    title:'Winter activity depends on agricultural and browse configuration',
    module_family:'agriculture_resource_response',
    response_variable:'diel activity distribution',
    required_inputs:[
      req('agriculture_state',['field-phenology-context'],['field','landscape_1500m','broad_3000m'],['available','known','proxy']),
      req('browse_state',['browse-resource-context'],['local_500m','landscape_1500m'],['available','known','proxy']),
      req('diel_state',['diel-photoperiod-context'],['property']),
      req('human_footprint',['human-footprint-context'],['landscape_1500m','broad_3000m'],['available','known','proxy'],'static_context_ok'),
    ],
    biological_state_gates:gate({seasons:['winter'],required_explicit_dimensions:['season','diel_period']}),
    spatial_scale:{relationship_scales:['landscape_1500m','broad_3000m'],notes:'Interaction is landscape configuration dependent.'},
    temporal_scale:'winter diel cycle',
    relationship_form:'agriculture availability interacts with woody browse and development',
    direction:'interaction',
    supported_nonlinearity:null,
    coefficient_transfer:{status:'not_supported',numeric_parameters:[]},
    parameter_source_version:PARAMETER_SOURCE,
    null_or_blocked_conditions:[],
    blocked_universal_assumptions:[],
    output_kind:'mechanism_context',
    limitations:['Do not create independent agriculture or browse weights from this interaction study.'],
    study_measurements:[
      measurement('FW-M22-winter-agriculture-amount','agriculture_state','landscape amount/configuration of agriculture','Study evaluated winter activity as an interaction with landscape agricultural availability.','mechanism_context_only','context_only','Mapped agricultural context may support mechanism interpretation but does not reproduce the study landscape metric by itself.'),
      measurement('FW-M23-woody-twig-density','browse_state','woody twig density / browse availability','Study interaction used woody twig density, not generic canopy or vegetation greenness.','unsupported','required','No relationship activation until a browse/twig resource measurement or calibrated proxy exists.'),
      measurement('FW-M24-building-density','human_footprint','building/development density','Overall activity level in the study also responded to building density.','derived_equivalent','required','Farm Watch reproduces the study variable family as a FEMA USA Structures count/density in an exact 10.36 km² analytical window. The context records live service edit dates, local feature production/imagery vintage coverage, the source inventory threshold (>450 sq ft), and explicit unquantified spatial completeness. This is a source-aligned derived measurement, not the original Indiana landscape sample.',['No Delisle coefficient or Kentucky activity effect is transferred.','FEMA USA Structures is not treated as a census-complete inventory: structures at or below the source threshold may be absent, and the source does not publish a defensible property-window completeness percentage.']),
    ],
  }),
  record({
    relationship_id:'FW-R14-discrete-hunt-localized-risk',
    ledger_ids:['FW-D10'],
    source_citations:['Sullivan et al. 2018, Wildlife Biology 2018:wlb.00455, DOI:10.2981/wlb.00455'],
    title:'Localized hunting events alter use by time of day',
    module_family:'localized_hunting_risk',
    response_variable:'use of food and vulnerability zones near hunted stands',
    required_inputs:[
      req('human_activity',['human-activity-context'],['event_local','property','local_500m'],['available','known']),
      req('vulnerability_zone',['stand-vulnerability-zone-context'],['event_local','local_500m'],['available','known']),
      req('diel_state',['diel-photoperiod-context'],['property']),
    ],
    biological_state_gates:gate({sex:['female'],required_explicit_dimensions:['sex','diel_period']}),
    spatial_scale:{relationship_scales:['event_local','local_500m'],notes:'Risk history must be localized to the hunted location.'},
    temporal_scale:'recent discrete hunt event; midday/night/crepuscular response',
    relationship_form:'recent localized risk interacts with diel period',
    direction:'interaction',
    supported_nonlinearity:null,
    coefficient_transfer:{status:'not_supported',numeric_parameters:[]},
    parameter_source_version:PARAMETER_SOURCE,
    null_or_blocked_conditions:['abstain when localized pressure history is unknown'],
    blocked_universal_assumptions:['open_hunting_season_equals_current_pressure'],
    output_kind:'ordinal_directional',
    limitations:['Distance to a stand without dated use is not hunting pressure.'],
    study_measurements:[
      measurement('FW-M25-discrete-stand-hunt','human_activity','dated hunt event at a specific stand','Study response was conditioned on when a specific stand had actually been hunted and its localized risk history.','unsupported','required','No relationship activation until dated stand-use/hunt events are represented.'),
      measurement('FW-M26-stand-vulnerability-zone','vulnerability_zone','stand-specific visibility/vulnerability zone','Study mapped the area in which deer were visible to the hunter from each stand using pre-season field observation and laser rangefinding, rather than a uniform distance buffer.','unsupported','required','No localized-risk activation until a stand-specific visibility geometry is available or calibrated.',['Generalized viewshed may become an input to this product, but is not automatically study-equivalent.']),
      measurement('FW-M27-hunt-diel-period','diel_state','day-hunting, day-nonhunting and night periods','Study periods were defined around actual hunter occupancy and sunrise/sunset.','mechanism_context_only','context_only','Solar phase alone does not encode whether hunters occupy the stand.'),
    ],
    value_constraints:[
      valueConstraint('FW-C03-event-is-hunt','human_activity','event_type','equals',['hunting'],'Access, vehicle, farm or generic human activity cannot satisfy the discrete hunting-event relationship.'),
    ],
  }),
  record({
    relationship_id:'FW-R15-adult-male-hunter-space-time',
    ledger_ids:['FW-D11'],
    source_citations:['Henderson et al. 2023, Wildlife Research 51:WR22145, DOI:10.1071/WR22145'],
    title:'Adult males can avoid hunter-selected space by day while retaining nocturnal food use',
    module_family:'localized_hunting_risk',
    response_variable:'fine-scale habitat selection',
    required_inputs:[
      req('human_activity',['human-activity-context'],['event_local','local_500m'],['available','known']),
      req('resource_state',['managed-food-feature-context'],['field','property','local_500m'],['available','known']),
      req('diel_state',['diel-photoperiod-context'],['property']),
      req('biological_state',['deer-biological-state'],['individual_scenario']),
    ],
    biological_state_gates:gate({sex:['male'],age_class:['adult'],required_explicit_dimensions:['sex','age_class','diel_period']}),
    spatial_scale:{relationship_scales:['event_local','local_500m'],notes:'Fine-scale risk-food interaction.'},
    temporal_scale:'daily hunter activity during firearm season',
    relationship_form:'risk avoidance is diel dependent and can reverse around food',
    direction:'interaction',
    supported_nonlinearity:null,
    coefficient_transfer:{status:'not_supported',numeric_parameters:[]},
    parameter_source_version:PARAMETER_SOURCE,
    null_or_blocked_conditions:['abstain when hunter activity is unknown'],
    blocked_universal_assumptions:['open_hunting_season_equals_current_pressure'],
    output_kind:'ordinal_directional',
    limitations:['Reported magnitude is not a transferable Kentucky multiplier.'],
    study_measurements:[
      measurement('FW-M28-daily-hunter-activity','human_activity','daily hunter-use intensity / hunter-selected space','Study compared adult-male selection against contemporaneous hunter activity and hunter-selected landscape characteristics.','unsupported','required','No relationship activation until hunter-use intensity is represented rather than inferred from season or stand geometry.'),
      measurement('FW-M29-food-opportunity','resource_state','food-resource opportunity','Study documented time-dependent use of food plots under hunting risk.','derived_equivalent','required','Production managed-food-feature-context reproduces explicit food-plot/managed-forage geometry plus year-specific current/absent management state. Confirmed-none is retained as known absence rather than missing data.',['Does not infer forage chemistry, nutritional quality, deer attraction, or feeder effects.']),
      measurement('FW-M30-risk-diel-period','diel_state','day versus night risk context','Study contrast depended on hunting-risk availability by time of day.','mechanism_context_only','context_only','Solar phase provides timing context but does not by itself establish hunting risk.'),
    ],
  }),
  record({
    relationship_id:'FW-R16-sex-risk-food-tradeoff',
    ledger_ids:['FW-D12'],
    source_citations:['Stewart et al. 2022, Ecology and Evolution 12:e9277, DOI:10.1002/ece3.9277'],
    title:'Sex modifies the hunting-risk and food tradeoff',
    module_family:'localized_hunting_risk',
    response_variable:'sex- and time-specific cover/resource selection',
    required_inputs:[
      req('human_activity',['human-activity-context'],['event_local','local_500m'],['available','known']),
      req('resource_state',['managed-food-feature-context'],['field','property','local_500m'],['available','known']),
      req('biological_state',['deer-biological-state'],['individual_scenario']),
      req('diel_state',['diel-photoperiod-context'],['property']),
    ],
    biological_state_gates:gate({sex:['male','female'],age_class:['adult'],required_explicit_dimensions:['sex','age_class','diel_period']}),
    spatial_scale:{relationship_scales:['local_500m'],notes:'Risk-food interaction requires explicit sex.'},
    temporal_scale:'hunted-season diel periods',
    relationship_form:'sex by food by risk interaction',
    direction:'interaction',
    supported_nonlinearity:null,
    coefficient_transfer:{status:'not_supported',numeric_parameters:[]},
    parameter_source_version:PARAMETER_SOURCE,
    null_or_blocked_conditions:['unknown sex must not silently use either sex-specific relationship'],
    blocked_universal_assumptions:['open_hunting_season_equals_current_pressure'],
    output_kind:'mechanism_context',
    limitations:['No sex-neutral collapse is authorized.'],
    study_measurements:[
      measurement('FW-M31-frequent-hunt-risk','human_activity','frequency/intensity of hunted areas','Study contrasted adult male and female use of areas hunted more frequently.','unsupported','required','No sex-specific risk tradeoff activation until hunting frequency/intensity is measured.'),
      measurement('FW-M32-abundant-food-risk','resource_state','forage-rich risky areas represented by mapped food plots / study-relevant managed cover','Study female/male contrast depended on risky areas containing mapped food plots or study-relevant cover types rather than remotely inferred forage chemistry.','derived_equivalent','required','Production managed-food-feature-context preserves explicit polygon class, cover type when known, and year-specific management state; it may represent known absence but does not claim measured nutrient abundance.',['Supplemental feeders and mineral attractants remain separate point observations and do not satisfy this measurement.']),
    ],
  }),
  record({
    relationship_id:'FW-R17-low-pressure-negative-constraint',
    ledger_ids:['FW-D13'],
    source_citations:['Rosenberger et al. 2024, Animals 14:1212, DOI:10.3390/ani14081212'],
    title:'Low hunting pressure need not produce meaningful displacement',
    module_family:'localized_hunting_risk',
    response_variable:'female utilization distributions and step lengths',
    required_inputs:[req('human_activity',['human-activity-context'],['event_local','property','local_500m'],['available','known'])],
    biological_state_gates:gate({sex:['female'],required_explicit_dimensions:['sex']}),
    spatial_scale:{relationship_scales:['property','local_500m'],notes:'Pressure intensity and localization are required context.'},
    temporal_scale:'before/during/after firearms hunts',
    relationship_form:'low-intensity hunt context can yield little displacement',
    direction:'null_constraint',
    supported_nonlinearity:null,
    coefficient_transfer:{status:'not_applicable',numeric_parameters:[]},
    parameter_source_version:PARAMETER_SOURCE,
    null_or_blocked_conditions:['season-open status alone is insufficient'],
    blocked_universal_assumptions:['open_hunting_season_equals_current_pressure'],
    output_kind:'negative_constraint',
    limitations:['Does not imply hunting never affects movement; it constrains low-pressure generalization.'],
    study_measurements:[
      measurement('FW-M33-low-hunting-pressure','human_activity','low firearms-hunting pressure','Study null result occurred in a demonstrably low-pressure hunting context.','unsupported','required','The negative constraint may fire only when low pressure is actually documented; season-open status is insufficient.'),
    ],
    value_constraints:[
      valueConstraint('FW-C04-pressure-is-low','human_activity','pressure_class','equals',['low'],'FW-D13 constrains inference only under low hunting pressure; unknown or moderate/high pressure cannot inherit the null result.'),
    ],
  }),
  record({
    relationship_id:'FW-R18-terrain-movement-context',
    ledger_ids:['FW-D14'],
    source_citations:['Stephens et al. 2024, Landscape Ecology 39:84, DOI:10.1007/s10980-024-01879-z'],
    title:'Terrain response can reverse with movement state and landscape context',
    module_family:'terrain_movement_context',
    response_variable:'step selection during dispersal',
    required_inputs:[
      req('terrain',['terrain-form-permeability'],['local_500m','landscape_1500m']),
      req('forest_context',['multiscale-forest-context'],['event_local','local_500m','landscape_1500m','multiscale'],['available'],'static_context_ok'),
      req('biological_state',['deer-biological-state'],['individual_scenario']),
      req('road_context',['road-focal-context'],['event_local','local_500m','landscape_1500m'],['available'],'static_context_ok'),
    ],
    biological_state_gates:gate({sex:['male'],age_class:['juvenile'],movement_state:['dispersal'],required_explicit_dimensions:['sex','age_class','movement_state']}),
    spatial_scale:{relationship_scales:['local_500m','landscape_1500m','multiscale'],notes:'Direction differed between landscapes and scales.'},
    temporal_scale:'before/during/after dispersal',
    relationship_form:'terrain and road response changes with landscape context and movement state',
    direction:'conditional',
    supported_nonlinearity:'direction reversal documented across study landscapes',
    coefficient_transfer:{status:'not_supported',numeric_parameters:[]},
    parameter_source_version:PARAMETER_SOURCE,
    null_or_blocked_conditions:['resident or unknown movement state cannot inherit the dispersal relationship'],
    blocked_universal_assumptions:['ridge_generic_corridor','draw_generic_corridor','saddle_generic_funnel','roads_generic_avoidance','roads_generic_selection'],
    output_kind:'mechanism_context',
    limitations:['No universal ridge, valley, road, saddle or corridor sign is authorized.'],
    study_measurements:[
      measurement('FW-M34-dispersal-terrain-form','terrain','terrain/topographic position during dispersal','Study evaluated scale-dependent topographic selection by dispersing juvenile males in two contrasting Missouri landscapes.','mechanism_context_only','context_only','Farm Watch terrain forms can provide neutral context but the study effect direction cannot transfer without matching landscape context.'),
      measurement('FW-M35-forest-landscape-context','forest_context','forest availability/configuration at multiple scales','Study terrain and forest-selection responses changed with landscape forest availability/configuration.','derived_equivalent','required','Farm Watch reproduces the physical forest variable family at 10 m support with forest proportion and built-excluded internal forest-edge density at the source 30/90/270 m focal radii. The land-cover classifier is a documented Sentinel-2 10 m LULC substitution for the study Dynamic World 2015-2019 dominant composite.',['No property-level forest-selection sign is assigned.','The source-classifier/time-composite substitution is retained in provenance and no Stephens coefficient or Missouri landscape identity transfers.']),
      measurement('FW-M36-road-landscape-context','road_context','road response within landscape context','Road response reversed/vanished across study landscapes and movement states.','derived_equivalent','required','Farm Watch now provides an on-demand 10 m distance-to-nearest-road grid evaluator with source-style mean focal extraction at 30/90/270 m around any bounded evaluation point. OSM replaces the study TIGER road geometry, but the physical transformation is preserved.',['No universal road selection or avoidance sign is authorized.','The downstream deer relationship still requires juvenile-male dispersal state plus aligned forest/terrain landscape context.']),
    ],
  }),
  record({
    relationship_id:'FW-R19-juvenile-male-dispersal-ag-riparian',
    ledger_ids:['FW-D15'],
    source_citations:['Gilbertson et al. 2022, Movement Ecology 10:43, DOI:10.1186/s40462-022-00342-5'],
    title:'Juvenile-male dispersal path selection uses agriculture and riparian context',
    module_family:'terrain_movement_context',
    response_variable:'dispersal path selection',
    required_inputs:[
      req('biological_state',['deer-biological-state'],['individual_scenario']),
      req('agriculture_context',['agriculture-landcover-context'],['field','landscape_1500m','broad_3000m'],['available','known','proxy'],'static_context_ok'),
      req('riparian_geometry',['mapped-hydrography-context'],['local_500m','landscape_1500m','broad_3000m'],['available','known'],'static_context_ok'),
    ],
    biological_state_gates:gate({
      sex:['male'],age_class:['juvenile','yearling'],movement_state:['dispersal'],
      required_explicit_dimensions:['sex','age_class','movement_state'],
    }),
    spatial_scale:{relationship_scales:['landscape_1500m','broad_3000m','multiscale'],notes:'Natal-range agriculture and path selection occur at different scales.'},
    temporal_scale:'seasonal dispersal',
    relationship_form:'during dispersal, paths can avoid agriculture and select areas near rivers and streams',
    direction:'interaction',
    supported_nonlinearity:null,
    coefficient_transfer:{status:'not_supported',numeric_parameters:[]},
    parameter_source_version:PARAMETER_SOURCE,
    null_or_blocked_conditions:['resident adults must not consume this relationship'],
    blocked_universal_assumptions:['nearest_water_or_discharge_equals_deer_use'],
    output_kind:'ordinal_directional',
    limitations:['Riparian selection in dispersal is not a generic resident-deer water rule; current water presence is not required to represent distance to mapped rivers/streams.'],
    study_measurements:[
      measurement('FW-M37-dispersal-ag-landcover','agriculture_context','agricultural land use along dispersal paths','Study step-selection analysis used agricultural land use as landscape geometry, not crop phenology or current food state.','derived_equivalent','required','Mapped agricultural land-cover proportion/geometry may represent this covariate when scale is preserved.'),
      measurement('FW-M38-river-stream-proximity','riparian_geometry','proximity to rivers and streams during dispersal','Study found juvenile males selected areas near rivers and streams during dispersal.','derived_equivalent','required','Authoritative mapped hydrography may represent riparian geometry; this must not be relabeled as water visitation or current water availability.'),
    ],
  }),
  record({
    relationship_id:'FW-R20-multiscale-cover-food-context',
    ledger_ids:['FW-D16'],
    source_citations:['Nagy-Reis et al. 2019, Journal of Environmental Management 248:109299, DOI:10.1016/j.jenvman.2019.109299'],
    title:'Cover and food operate at different spatial scales',
    module_family:'terrain_movement_context',
    response_variable:'winter occurrence and abundance',
    required_inputs:[
      req('study_scales',['multiscale-cover-context'],['multiscale'],['available'],'static_context_ok'),
      req('cover_context',['spatial-edge-patch-context'],['local_500m']),
      req('agriculture_state',['field-phenology-context'],['field','landscape_1500m','broad_3000m'],['available','known','proxy']),
    ],
    biological_state_gates:gate({seasons:['winter'],required_explicit_dimensions:['season']}),
    spatial_scale:{relationship_scales:['local_500m','landscape_1500m','broad_3000m','multiscale'],notes:'Broad cover and fine-scale food must remain distinct.'},
    temporal_scale:'winter',
    relationship_form:'different resource families dominate at different scales',
    direction:'conditional',
    supported_nonlinearity:null,
    coefficient_transfer:{status:'not_supported',numeric_parameters:[]},
    parameter_source_version:PARAMETER_SOURCE,
    null_or_blocked_conditions:[],
    blocked_universal_assumptions:[],
    output_kind:'mechanism_context',
    limitations:['Population occurrence/abundance is not within-property movement.'],
    study_measurements:[
      measurement('FW-M39-d16-study-scales','study_scales','cover at 1 km², 9 km² and hunting-unit scales','Study evaluated occurrence/abundance at explicit 1 km², 9 km², and hunting-unit scales.','derived_equivalent','required','Farm Watch reproduces exact-area 1 km² and 9 km² square analytical windows in a projected CRS. The North Dakota hunting-unit scale is explicitly not transferred.',['Property-centered placement is a target analytical frame, not the source study grid origin.']),
      measurement('FW-M40-d16-escape-cover-types','cover_context','forest, wetland and CRP escape-cover composition','Study broad-scale cover signal came from forest, wetland and Conservation Reserve Program lands.','unsupported','required','Generic edge/patch structure does not preserve the study cover classes.'),
      measurement('FW-M41-d16-winter-food','agriculture_state','residual winter cropland / food at fine scale','Study fine-scale food signal emphasized residual winter cropland.','unsupported','required','Current field vegetation context does not establish residual winter crop food availability.'),
    ],
  }),
  record({
    relationship_id:'FW-R21-human-footprint-seasonal-context',
    ledger_ids:['FW-D17'],
    source_citations:['Darlington et al. 2022, Scientific Reports 12:1072, DOI:10.1038/s41598-022-05018-z'],
    title:'Human-footprint response is cumulative and seasonal',
    module_family:'terrain_movement_context',
    response_variable:'seasonal habitat selection',
    required_inputs:[
      req('human_footprint',['human-footprint-context'],['local_500m','landscape_1500m','broad_3000m'],['available','known','proxy'],'static_context_ok'),
      req('resource_context',['forest-type-context'],['field','local_500m','landscape_1500m'],['available','known','proxy']),
      req('predator_occurrence',['predator-occurrence-context'],['landscape_1500m','broad_3000m','regional'],['available','known','proxy']),
      req('biological_state',['deer-biological-state'],['individual_scenario']),
    ],
    biological_state_gates:gate({sex:['female'],required_explicit_dimensions:['sex','season']}),
    spatial_scale:{relationship_scales:['landscape_1500m','broad_3000m'],notes:'Cumulative footprint and resource context are landscape dependent.'},
    temporal_scale:'seasonal',
    relationship_form:'linear and polygonal human features interact with resources and risk',
    direction:'conditional',
    supported_nonlinearity:null,
    coefficient_transfer:{status:'not_supported',numeric_parameters:[]},
    parameter_source_version:PARAMETER_SOURCE,
    null_or_blocked_conditions:[],
    blocked_universal_assumptions:['roads_generic_avoidance','roads_generic_selection'],
    output_kind:'mechanism_context',
    limitations:['Boreal range-expansion context; linear features are not universally positive or negative.'],
    study_measurements:[
      measurement('FW-M42-human-footprint-composition','human_footprint','polygonal and linear industrial human footprint','Study compared polygonal industrial features and linear features such as roads, trails and seismic lines.','unsupported','required','No relationship activation until footprint subtypes are explicitly represented.'),
      measurement('FW-M43-intact-deciduous-forest','resource_context','AVI species-specific overstorey canopy composition','The abstract describes intact deciduous forest, but the operational natural-habitat covariates were percent overstorey canopy dominated by each of eight leading tree species, extracted at used and available points.','mechanism_context_only','required','Generic Trees land cover, total canopy cover, broad deciduous classification, edge density or fragmentation do not reproduce the source measurement.'),
      measurement('FW-M44-wolf-occurrence','predator_occurrence','camera-derived wolf occurrence','Top seasonal models included modeled wolf occurrence as predation-risk context.','unsupported','required','Omitting predator occurrence changes the published cumulative-effects model; no activation until represented.'),
    ],
  }),
  record({
    relationship_id:'FW-R22-extreme-storm-refuge',
    ledger_ids:['FW-D18'],
    source_citations:['Abernathy et al. 2019, Proceedings of the Royal Society B 286:20192230, DOI:10.1098/rspb.2019.2230'],
    title:'Extreme storms can trigger emergency refuge behavior',
    module_family:'extreme_event_context',
    response_variable:'movement, home-range departure and resource selection',
    required_inputs:[
      req('extreme_event',['extreme-weather-event-context'],['event_local','property','regional'],['available','known']),
      req('terrain',['terrain-form-permeability'],['local_500m','landscape_1500m']),
      req('forest_type',['forest-type-context'],['point','property','local_500m','landscape_1500m','broad_3000m'],['available','known','proxy']),
      req('water_context',['surface-water-state'],['local_500m','landscape_1500m'],['available','known','proxy']),
    ],
    biological_state_gates:gate(),
    spatial_scale:{relationship_scales:['property','local_500m','landscape_1500m'],notes:'Event-specific refuge context.'},
    temporal_scale:'active extreme-storm event',
    relationship_form:'higher-elevation/forested refuge response during hurricane conditions',
    direction:'conditional',
    supported_nonlinearity:'extreme-event gate',
    coefficient_transfer:{status:'not_supported',numeric_parameters:[]},
    parameter_source_version:PARAMETER_SOURCE,
    null_or_blocked_conditions:['must not activate for ordinary rainfall or wind'],
    blocked_universal_assumptions:['wind_generic_movement'],
    output_kind:'mechanism_context',
    limitations:['Southwestern Florida hurricane event; ordinary weather is explicitly out of scope.'],
    study_measurements:[
      measurement('FW-M45-extreme-hurricane-event','extreme_event','active hurricane/extreme climatic event','Study response was observed during Hurricane Irma, not routine rain or wind.','derived_equivalent','required','Farm Watch uses a fresh authoritative NWS tropical/extreme-wind alert poll plus property-intersecting alert geometry and active event time. A healthy poll with no qualifying intersection is explicitly not applicable; source failure, stale polling, or unresolved qualifying alert geometry is unavailable rather than inactive. Ordinary storms, rain, heat, and routine wind are explicitly excluded.',['The event gate establishes extreme-event context only; it does not transfer the Hurricane Irma deer response coefficient.','Only NWS status Actual is eligible for activation.']),
      measurement('FW-M46-elevation-refuge','terrain','relative elevation during the event','Study deer increased selection of higher elevation during Hurricane Irma.','derived_equivalent','required','Farm Watch elevation can represent the physical variable, but no Florida coefficient transfers.'),
      measurement(
        'FW-M47-forest-refuge-type',
        'forest_type',
        'Euclidean distance to pine forest, hardwood swamp, marsh, prairie, shrub and hardwood hammock',
        'Abernathy et al. reclassified FNAI Cooperative Land Cover v3.2 at 10 m and calculated continuous Euclidean distance to each of six retained habitat classes, then extracted those distance covariates at used and available locations and scaled/centered variables for modeling.',
        'derived_equivalent',
        'required',
        'Farm Watch reproduces the six distance-to-class variable family using explicit national source substitutions: Annual NLCD Evergreen Forest (42), Grassland/Herbaceous (71), Shrub/Scrub (52), Deciduous Forest (41), plus NWI PFO1* and PEM*. The product carries proxy evidence state because the national classes are not literal FNAI Florida communities; no source coefficient or hurricane response is transferred.',
        [
          'Annual NLCD 42 is a broad evergreen analogue and must not be relabeled as a pine-species map.',
          'Annual NLCD 41 is an upland/deciduous-hardwood analogue and must not be represented as literal Florida hardwood hammock in Kentucky.',
          'Annual NLCD 71 is a prairie analogue; pasture/hay and cultivated crops are intentionally excluded.',
          'NWI PFO1* and PEM* preserve forested broad-leaved-deciduous wetland versus emergent wetland physiognomy.',
        ],
      ),
    ],
    value_constraints:[
      valueConstraint(
        'FW-C06-extreme-event-active',
        'extreme_event',
        'applicability_state',
        'equals',
        ['active_extreme_event'],
        'FW-D18 is an extreme-event-only relationship; a healthy source state with no qualifying property-intersecting event is explicitly not applicable.'
      ),
    ],
  }),
  record({
    relationship_id:'FW-R23-water-rainfall-context',
    ledger_ids:['FW-D19'],
    source_citations:['Webb et al. 2006, Southwestern Naturalist 51:368-375, DOI:10.1894/0038-4909(2006)51[368:WQASUO]2.0.CO;2'],
    title:'Water-source visitation is rainfall and availability conditional',
    module_family:'water_hydrology_context',
    response_variable:'water-source visitation frequency',
    required_inputs:[
      req('water_state',['managed-water-source-context','surface-water-state'],['point','property','local_500m','landscape_1500m'],['available','known']),
      req('recent_precipitation',['seasonal-state'],['property','regional'],['available','known','proxy']),
    ],
    biological_state_gates:gate({seasons:['summer'],required_explicit_dimensions:['season']}),
    spatial_scale:{relationship_scales:['property','local_500m'],notes:'Actual usable water state is required.'},
    temporal_scale:'summer; recent-rainfall context',
    relationship_form:'visitation tracks recent rainfall and actual water availability more than heat alone',
    direction:'conditional',
    supported_nonlinearity:null,
    coefficient_transfer:{status:'not_supported',numeric_parameters:[]},
    parameter_source_version:PARAMETER_SOURCE,
    null_or_blocked_conditions:['nearest gauge or mapped water alone is insufficient'],
    blocked_universal_assumptions:['nearest_water_or_discharge_equals_deer_use'],
    output_kind:'mechanism_context',
    limitations:['Semiarid artificial-water context; no universal central-Kentucky water attraction rule.'],
    study_measurements:[
      measurement('FW-M48-usable-water-source','water_state','available stock-pond/trough water source','Study visitation response was measured at known artificial water sources; mapped hydrography or regional discharge alone is not equivalent.','derived_equivalent','required','Production managed-water-source-context reproduces stable artificial-source identity plus explicit dated/year-scoped usable-water state; exact-date surface-water observations remain an alternate direct-observation path.',['A configured source with unknown usability does not satisfy the measurement.','Mapped hydrography, drainage geometry, precipitation, drought, or off-property discharge cannot promote a source to known usable water.']),
      measurement('FW-M49-recent-rainfall','recent_precipitation','recent rainfall preceding water-source visitation','Study visitation frequency was related to recent rainfall.','calibrated_proxy','required','QPE or other gridded precipitation may serve only as a documented rainfall proxy with freshness and spatial uncertainty retained.'),
    ],
    value_constraints:[
      valueConstraint('FW-C05-water-present','water_state','current_presence_state','one_of',['observed_present','known_managed_source_present'],'The relationship requires an actually available water source; mapped persistence or an off-property gauge is insufficient.'),
    ],
  }),
  record({
    relationship_id:'FW-R24-climate-modular-architecture',
    ledger_ids:['FW-D20'],
    source_citations:['Felton et al. 2024, Global Change Biology 30:e17505, DOI:10.1111/gcb.17505'],
    title:'Climate responses require modular state-conditioned architecture',
    module_family:'architecture_context',
    response_variable:'architecture-level climate response synthesis',
    required_inputs:[],
    biological_state_gates:gate(),
    spatial_scale:{relationship_scales:['regional','multiscale'],notes:'Synthesis anchor rather than a deployable Kentucky coefficient.'},
    temporal_scale:'seasonal to long-term climate context',
    relationship_form:'local climate, population and risk context mediate response direction',
    direction:'conditional',
    supported_nonlinearity:null,
    coefficient_transfer:{status:'not_applicable',numeric_parameters:[]},
    parameter_source_version:PARAMETER_SOURCE,
    null_or_blocked_conditions:[],
    blocked_universal_assumptions:['cold_generic_movement'],
    output_kind:'mechanism_context',
    limitations:['Multi-species review supports architecture and mechanisms, not a white-tailed-deer numeric term.'],
  }),
  record({
    relationship_id:'FW-R25-kentucky-breeding-context',
    ledger_ids:['FW-D21'],
    source_citations:[
      'University of Kentucky Cooperative Extension, White-tailed Deer, Kentucky biology reference',
      'Kentucky Department of Fish and Wildlife Resources, Kentucky modern gun season / peak breeding guidance (2021)',
    ],
    title:'Kentucky statewide qualitative breeding context',
    module_family:'reproductive_movement',
    response_variable:'regional breeding timing context',
    required_inputs:[req('biological_state',['deer-biological-state'],['individual_scenario','statewide'])],
    biological_state_gates:gate({
      regional_reproductive_context:['outside_documented_breeding_season','within_documented_breeding_season','within_peak_month_context'],
      required_explicit_dimensions:['regional_reproductive_context'],
    }),
    spatial_scale:{relationship_scales:['statewide'],notes:'Kentucky statewide qualitative gate only.'},
    temporal_scale:'documented October-January season with qualitative November peak-month context',
    relationship_form:'regional calendar gate without individual-state inference',
    direction:'conditional',
    supported_nonlinearity:'season membership and qualitative peak-month context',
    coefficient_transfer:{status:'not_supported',numeric_parameters:[]},
    parameter_source_version:PARAMETER_SOURCE,
    null_or_blocked_conditions:['individual estrus/conception/movement state remains unknown unless explicitly supplied'],
    blocked_universal_assumptions:[],
    output_kind:'mechanism_context',
    limitations:['No universal peak day, individual estrus flag or movement multiplier.'],
    biological_state_annotation:{state_codes:['KY']},
    study_measurements:[
      measurement('FW-M50-kentucky-regional-breeding','biological_state','Kentucky regional breeding-season context','Relationship is based on Kentucky authoritative population-level timing summaries.','measurement_equivalent','required','May gate regional season context only; it cannot establish individual estrus, mating, conception, or movement intensity.'),
    ],
  }),
  record({
    relationship_id:'FW-R26-female-age-breeding-context',
    ledger_ids:['FW-D22'],
    source_citations:['Green et al. 2017, Theriogenology 94:71-78, DOI:10.1016/j.theriogenology.2017.02.010'],
    title:'Female breeding timing is age dependent',
    module_family:'reproductive_movement',
    response_variable:'conception timing by maternal age',
    required_inputs:[req('biological_state',['deer-biological-state'],['individual_scenario'])],
    biological_state_gates:gate({
      sex:['female'],age_class:['juvenile','yearling','adult'],
      required_explicit_dimensions:['sex','age_class'],
    }),
    spatial_scale:{relationship_scales:['regional'],notes:'Illinois relationship form is retained; dates are not Kentucky parameters.'},
    temporal_scale:'breeding season',
    relationship_form:'female conception timing differs by age class',
    direction:'conditional',
    supported_nonlinearity:'age-class timing differences',
    coefficient_transfer:{status:'not_supported',numeric_parameters:[]},
    parameter_source_version:PARAMETER_SOURCE,
    null_or_blocked_conditions:['unknown age must remain unknown'],
    blocked_universal_assumptions:[],
    output_kind:'mechanism_context',
    limitations:['Illinois mean conception dates are provenance only and must not be assigned to Kentucky.'],
    biological_state_annotation:{sex:['female'],require_known_age:true},
    study_measurements:[
      measurement('FW-M51-maternal-age-category','biological_state','maternal age class','Illinois study estimated conception timing by maternal age, including fawns, yearlings and adults.','mechanism_context_only','required','Current Farm Watch juvenile/yearling/adult vocabulary requires an explicit mapping review before using the study age relationship.'),
      measurement('FW-M52-conception-timing','biological_state','estimated conception timing','Study timing was derived from fetal/reproductive measurements in Illinois.','mechanism_context_only','context_only','Relationship form may be retained, but Illinois conception dates are not Kentucky parameters.'),
    ],
  }),
  record({
    relationship_id:'FW-R27-ohio-breeding-onset-corroboration',
    ledger_ids:['FW-D23'],
    source_citations:['Harder & Moorhead 1980, Biology of Reproduction 22:185-191, DOI:10.1095/biolreprod22.2.185'],
    title:'Ohio breeding-onset evidence is corroboration only for Kentucky',
    module_family:'reproductive_movement',
    response_variable:'physiological breeding-season onset',
    required_inputs:[],
    biological_state_gates:gate({
      sex:['female'],age_class:['adult'],
      required_explicit_dimensions:['sex','age_class'],
    }),
    spatial_scale:{relationship_scales:['regional'],notes:'Nearby-population corroboration only.'},
    temporal_scale:'autumn breeding onset',
    relationship_form:'regional mechanism/context support',
    direction:'not_applicable',
    supported_nonlinearity:null,
    coefficient_transfer:{status:'not_applicable',numeric_parameters:[]},
    parameter_source_version:PARAMETER_SOURCE,
    null_or_blocked_conditions:['does not independently activate a Kentucky relationship module'],
    blocked_universal_assumptions:[],
    output_kind:'not_applicable',
    limitations:['Ohio onset date is not a Kentucky onset or peak date and not equivalent to male movement.'],
  }),
  record({
    relationship_id:'FW-R28-male-reproductive-phase-movement-context',
    ledger_ids:['FW-D05'],
    source_citations:['Webb et al. 2010, International Journal of Ecology 2010:459610, DOI:10.1155/2010/459610'],
    title:'Male movement differs across reproductive phases',
    module_family:'reproductive_movement',
    response_variable:'male daily movement across rut and post-rut phases',
    required_inputs:[req('biological_state',['deer-biological-state'],['individual_scenario'])],
    biological_state_gates:gate({sex:['male'],required_explicit_dimensions:['sex','reproductive_state']}),
    spatial_scale:{relationship_scales:['property','regional'],notes:'Relationship form only; study phase definitions and magnitudes are not transferred.'},
    temporal_scale:'rut versus post-rut reproductive phases',
    relationship_form:'male daily movement differs by reproductive phase',
    direction:'conditional',
    supported_nonlinearity:null,
    coefficient_transfer:{status:'not_supported',numeric_parameters:[]},
    parameter_source_version:PARAMETER_SOURCE,
    null_or_blocked_conditions:['abstain until an explicit male reproductive-phase state aligned to the study is available'],
    blocked_universal_assumptions:[],
    output_kind:'mechanism_context',
    limitations:['Oklahoma population; no rut/post-rut magnitude or date transfer.'],
    study_measurements:[
      measurement('FW-M53-male-reproductive-phase','biological_state','male rut/post-rut phase','Study compared male movement across reproductive-season phases.','unsupported','required','Current Farm Watch individual reproductive-state vocabulary does not represent male rut/post-rut phase with study fidelity.'),
    ],
  }),
  record({
    relationship_id:'FW-R29-female-reproductive-phase-movement-context',
    ledger_ids:['FW-D05'],
    source_citations:['Webb et al. 2010, International Journal of Ecology 2010:459610, DOI:10.1155/2010/459610'],
    title:'Female movement differs across parturition phases',
    module_family:'reproductive_movement',
    response_variable:'female daily movement across pre-parturition, parturition and post-parturition phases',
    required_inputs:[req('biological_state',['deer-biological-state'],['individual_scenario'])],
    biological_state_gates:gate({sex:['female'],required_explicit_dimensions:['sex','reproductive_state']}),
    spatial_scale:{relationship_scales:['property','regional'],notes:'Relationship form only; study phase definitions and magnitudes are not transferred.'},
    temporal_scale:'pre-parturition, parturition and post-parturition',
    relationship_form:'female daily movement differs across reproductive phases',
    direction:'conditional',
    supported_nonlinearity:null,
    coefficient_transfer:{status:'not_supported',numeric_parameters:[]},
    parameter_source_version:PARAMETER_SOURCE,
    null_or_blocked_conditions:['abstain until reproductive phase is explicitly aligned to the study definitions'],
    blocked_universal_assumptions:[],
    output_kind:'mechanism_context',
    limitations:['Oklahoma population; no movement magnitude transfer.'],
    study_measurements:[
      measurement('FW-M54-female-parturition-phase','biological_state','female pre-/during-/post-parturition phase','Study distinguished female movement among pre-parturition, parturition and post-parturition phases.','unsupported','required','Current Farm Watch reproductive vocabulary does not preserve all three study phase definitions.'),
    ],
  }),
  record({
    relationship_id:'FW-R30-spring-juvenile-male-dispersal-probability',
    ledger_ids:['FW-D15'],
    source_citations:['Gilbertson et al. 2022, Movement Ecology 10:43, DOI:10.1186/s40462-022-00342-5'],
    title:'Spring juvenile-male dispersal probability responds to natal-range agriculture',
    module_family:'terrain_movement_context',
    response_variable:'juvenile-male dispersal probability',
    required_inputs:[
      req('biological_state',['deer-biological-state'],['individual_scenario']),
      req('agriculture_context',['agriculture-landcover-context'],['property','local_500m','landscape_1500m','broad_3000m'],['available','known','proxy'],'static_context_ok'),
    ],
    biological_state_gates:gate({
      sex:['male'],age_class:['juvenile','yearling'],seasons:['spring'],
      required_explicit_dimensions:['sex','age_class','season'],
    }),
    spatial_scale:{relationship_scales:['property','local_500m','landscape_1500m','broad_3000m'],notes:'Natal-range agriculture proportion is the relevant landscape covariate.'},
    temporal_scale:'spring dispersal decision period',
    relationship_form:'greater agricultural land use in the natal range was associated with higher juvenile-male dispersal probability in spring only',
    direction:'positive',
    supported_nonlinearity:'season-specific effect; no comparable fall relationship supported',
    coefficient_transfer:{status:'not_supported',numeric_parameters:[]},
    parameter_source_version:PARAMETER_SOURCE,
    null_or_blocked_conditions:['must not apply the spring agriculture relationship to fall dispersal'],
    blocked_universal_assumptions:[],
    output_kind:'ordinal_directional',
    limitations:['Wisconsin juvenile/yearling males; no dispersal probability coefficient transfers.'],
    study_measurements:[
      measurement('FW-M55-natal-range-agriculture','agriculture_context','proportion of natal range classified as agricultural land use','Study spring dispersal probability used agricultural land-use proportion in the pre-dispersal/natal range.','derived_equivalent','required','Mapped agricultural land-cover proportion may represent the covariate when the natal-range scale is explicit.'),
    ],
  }),
  record({
    relationship_id:'FW-R31-juvenile-male-dispersal-distance',
    ledger_ids:['FW-D15'],
    source_citations:['Gilbertson et al. 2022, Movement Ecology 10:43, DOI:10.1186/s40462-022-00342-5'],
    title:'Juvenile-male dispersal distance responds to season and agricultural land in potential paths',
    module_family:'terrain_movement_context',
    response_variable:'juvenile-male dispersal distance',
    required_inputs:[
      req('biological_state',['deer-biological-state'],['individual_scenario']),
      req('agriculture_context',['agriculture-landcover-context'],['landscape_1500m','broad_3000m'],['available','known','proxy'],'static_context_ok'),
    ],
    biological_state_gates:gate({
      sex:['male'],age_class:['juvenile','yearling'],movement_state:['dispersal'],
      required_explicit_dimensions:['sex','age_class','movement_state','season'],
    }),
    spatial_scale:{relationship_scales:['landscape_1500m','broad_3000m','multiscale'],notes:'Potential-path agriculture and season affected dispersal distance.'},
    temporal_scale:'spring versus fall dispersal',
    relationship_form:'spring dispersals were longer than fall dispersals and greater agriculture in potential paths was associated with longer dispersal distances',
    direction:'interaction',
    supported_nonlinearity:'seasonal difference plus agriculture-path effect',
    coefficient_transfer:{status:'not_supported',numeric_parameters:[]},
    parameter_source_version:PARAMETER_SOURCE,
    null_or_blocked_conditions:['requires explicit dispersal state and season; no distance coefficient transfer'],
    blocked_universal_assumptions:[],
    output_kind:'mechanism_context',
    limitations:['Wisconsin juvenile/yearling males; social-environment covariates in the source study are not yet represented.'],
    study_measurements:[
      measurement('FW-M56-potential-path-agriculture','agriculture_context','agricultural land use in potential dispersal paths','Study modeled agricultural land use along simulated potential dispersal paths.','mechanism_context_only','required','Current landscape agriculture geometry does not yet reproduce the study potential-path simulation.'),
      measurement('FW-M57-dispersal-season','biological_state','spring versus fall dispersal season','Study found strong seasonal differences in dispersal distance.','derived_equivalent','required','Season must remain explicit; no spring/fall distance magnitude transfers.'),
    ],
  }),
])

export const FARM_WATCH_DEER_LEDGER_IDS = Object.freeze(
  Array.from(new Set(FARM_WATCH_DEER_RELATIONSHIPS.flatMap((row) => row.ledger_ids))).sort(),
)

function intersects<T>(a: readonly T[], b: readonly T[]) {
  return a.some((value) => b.includes(value))
}

function gateRequiresExplicit(
  values: readonly string[] | null,
  fullVocabulary: readonly string[],
) {
  return values != null && (
    values.length !== fullVocabulary.length || values.some((value) => !fullVocabulary.includes(value))
  )
}

export function validateDeerRelationshipRecord(row: DeerRelationshipRecord) {
  const p = FARM_WATCH_DEER_RELATIONSHIP_REGISTRY_PRODUCT
  if (!/^FW-R\d{2}-[a-z0-9-]+$/.test(row.relationship_id)) return false
  if (!row.ledger_ids.length || row.ledger_ids.some((id) => !/^FW-D\d{2}$/.test(id))) return false
  if (!row.source_citations.length || row.source_citations.some((value) => !String(value).trim())) return false
  if (!p.outputKinds.includes(row.output_kind)) return false
  if (!p.directions.includes(row.direction)) return false
  if (!p.coefficientTransferStates.includes(row.coefficient_transfer.status)) return false
  if (row.coefficient_transfer.status !== 'authorized' && row.coefficient_transfer.numeric_parameters.length) return false
  if (row.output_kind === 'quantitative_relative_selection' && row.coefficient_transfer.status !== 'authorized') return false

  const gate = row.biological_state_gates
  const required = new Set(gate.required_explicit_dimensions)
  if (gateRequiresExplicit(gate.sex, ALL_SEX) && !required.has('sex')) return false
  if (gateRequiresExplicit(gate.age_class, ALL_AGE) && !required.has('age_class')) return false
  if (gate.movement_state && !required.has('movement_state')) return false
  if (gate.reproductive_state && !required.has('reproductive_state')) return false
  if (gate.seasons && !required.has('season')) return false
  if (gate.diel_periods && !required.has('diel_period')) return false
  if (gate.regional_reproductive_context && !required.has('regional_reproductive_context')) return false

  const inputKeys = new Set(row.required_inputs.map((requirement) => requirement.key))
  for (const requirement of row.required_inputs) {
    if (!requirement.key || !requirement.product_keys.length || !requirement.allowed_scales.length) return false
    if (!requirement.allowed_evidence_states.length) return false
    if (requirement.required && requirement.allowed_evidence_states.some((state) =>
      state === 'stale' || state === 'unavailable' || state === 'blocked' || state === 'abstained'
    )) return false
    for (const productKey of requirement.product_keys) {
      const product = FARM_WATCH_DEER_INPUT_PRODUCT_CATALOG[productKey]
      if (!product) return false
      if (!intersects(requirement.allowed_scales, product.scales as readonly DeerRelationshipScale[])) return false
      if (!intersects(requirement.allowed_evidence_states, product.evidence_states as readonly DeerRelationshipEvidenceState[])) return false
    }
  }

  if (
    row.output_kind !== 'negative_constraint' &&
    row.output_kind !== 'not_applicable' &&
    row.module_family !== 'architecture_context' &&
    !row.study_measurements.length
  ) return false

  const measurementIds = new Set<string>()
  for (const measurement of row.study_measurements) {
    if (!/^FW-M\d{2}-[a-z0-9-]+$/.test(measurement.id)) return false
    if (measurementIds.has(measurement.id)) return false
    measurementIds.add(measurement.id)
    if (!FARM_WATCH_DEER_MEASUREMENT_ALIGNMENTS.includes(measurement.alignment)) return false
    if (!['required','context_only','not_applicable'].includes(measurement.activation_requirement)) return false
    if (measurement.binding_key != null && !inputKeys.has(measurement.binding_key)) return false
    if (measurement.activation_requirement === 'required' && measurement.binding_key == null) return false
    if (!measurement.study_variable.trim() || !measurement.study_protocol.trim() || !measurement.permitted_use.trim()) return false
  }

  const valueConstraintIds = new Set<string>()
  for (const constraint of row.value_constraints) {
    if (!/^FW-C\d{2}-[a-z0-9-]+$/.test(constraint.id)) return false
    if (valueConstraintIds.has(constraint.id)) return false
    valueConstraintIds.add(constraint.id)
    if (!inputKeys.has(constraint.binding_key)) return false
    if (!constraint.field.trim() || !constraint.rationale.trim()) return false
    if (!['equals','one_of','known','study_specific'].includes(constraint.operator)) return false
    if (constraint.operator !== 'known' && !constraint.values.length) return false
  }

  if (row.output_kind === 'negative_constraint' && !row.blocked_universal_assumptions.length) return false
  if (row.blocked_universal_assumptions.some((id) =>
    !FARM_WATCH_DEER_BLOCKED_UNIVERSAL_ASSUMPTIONS.includes(id as any)
  )) return false
  return true
}

export function validateDeerRelationshipRegistry() {
  const ids = new Set<string>()
  for (const row of FARM_WATCH_DEER_RELATIONSHIPS) {
    if (!validateDeerRelationshipRecord(row)) return false
    if (ids.has(row.relationship_id)) return false
    ids.add(row.relationship_id)
  }
  return true
}

export function getDeerRelationship(relationshipId: string) {
  return FARM_WATCH_DEER_RELATIONSHIPS.find((row) => row.relationship_id === relationshipId) || null
}

export function relationshipsForLedgerId(ledgerId: string) {
  return FARM_WATCH_DEER_RELATIONSHIPS.filter((row) => row.ledger_ids.includes(ledgerId))
}

export function assertNoBlockedUniversalAssumptions(assumptionIds: readonly string[]) {
  const blocked = assumptionIds.filter((id) =>
    FARM_WATCH_DEER_BLOCKED_UNIVERSAL_ASSUMPTIONS.includes(id as any)
  )
  if (blocked.length) {
    throw new Error('blocked deer universal assumption: ' + blocked.join(','))
  }
}

export type DeerRelationshipInputBinding = {
  key: string
  product_key: ProductKey
  evidence_state: DeerRelationshipEvidenceState
  scale: DeerRelationshipScale
}

export function validateRelationshipModuleDefinition(value: {
  relationship_id: string
  ledger_ids: string[]
  input_bindings: DeerRelationshipInputBinding[]
  coefficient_transfer_status: 'authorized' | 'not_supported' | 'not_applicable'
  numeric_parameters: number[]
  universal_assumption_ids?: string[]
  study_measurement_ids?: string[]
  enforced_value_constraint_ids?: string[]
}) {
  const relationship = getDeerRelationship(value.relationship_id)
  if (!relationship) return false
  if (JSON.stringify([...value.ledger_ids].sort()) !== JSON.stringify([...relationship.ledger_ids].sort())) {
    return false
  }
  if (value.coefficient_transfer_status !== relationship.coefficient_transfer.status) return false
  if (value.coefficient_transfer_status !== 'authorized' && value.numeric_parameters.length) return false
  if ((value.universal_assumption_ids || []).some((id) =>
    FARM_WATCH_DEER_BLOCKED_UNIVERSAL_ASSUMPTIONS.includes(id as any)
  )) return false

  const fidelity = deerRelationshipStudyFidelityStatus(relationship)
  if (fidelity.status === 'blocked_measurement_alignment') return false
  if (
    fidelity.status === 'context_only' &&
    relationship.output_kind !== 'mechanism_context' &&
    relationship.output_kind !== 'negative_constraint'
  ) return false

  const declaredMeasurementIds = new Set(value.study_measurement_ids || [])
  const knownMeasurementIds = new Set(relationship.study_measurements.map((measurement) => measurement.id))
  if ([...declaredMeasurementIds].some((id) => !knownMeasurementIds.has(id))) return false
  for (const measurement of relationship.study_measurements) {
    if (
      measurement.activation_requirement !== 'not_applicable' &&
      !declaredMeasurementIds.has(measurement.id)
    ) return false
  }

  const enforcedConstraintIds = new Set(value.enforced_value_constraint_ids || [])
  const knownConstraintIds = new Set(relationship.value_constraints.map((constraint) => constraint.id))
  if ([...enforcedConstraintIds].some((id) => !knownConstraintIds.has(id))) return false
  if (relationship.value_constraints.some((constraint) => !enforcedConstraintIds.has(constraint.id))) {
    return false
  }

  for (const requirement of relationship.required_inputs.filter((row) => row.required)) {
    const matches = value.input_bindings.filter((binding) =>
      binding.key === requirement.key &&
      requirement.product_keys.includes(binding.product_key) &&
      requirement.allowed_evidence_states.includes(binding.evidence_state) &&
      requirement.allowed_scales.includes(binding.scale)
    )
    if (requirement.match === 'all') {
      if (!requirement.product_keys.every((productKey) =>
        matches.some((binding) => binding.product_key === productKey)
      )) return false
    } else if (!matches.length) return false
  }
  return true
}

export function applicableBiologicalStateLedgerIds(args: {
  stateCode: string
  sex: FarmWatchDeerSex
  ageClass: FarmWatchDeerAgeClass
  regionalBreedingPhase: string
}) {
  const stateCode = String(args.stateCode || '').toUpperCase()
  const ledgerIds = new Set<string>()
  for (const relationship of FARM_WATCH_DEER_RELATIONSHIPS) {
    const annotation = relationship.biological_state_annotation
    if (!annotation) continue
    if (annotation.state_codes && !annotation.state_codes.includes(stateCode)) continue
    if (annotation.sex && !annotation.sex.includes(args.sex)) continue
    if (annotation.require_known_age && args.ageClass === 'unknown') continue
    if (
      annotation.regional_reproductive_context &&
      !annotation.regional_reproductive_context.includes(args.regionalBreedingPhase)
    ) continue
    relationship.ledger_ids.forEach((id) => ledgerIds.add(id))
  }
  return [...ledgerIds].sort()
}
