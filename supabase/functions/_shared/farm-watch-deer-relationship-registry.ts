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
  ledgerVersion: '2026-09-21',
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
  'current-crop-identity': {
    status: 'candidate_blocked_rights',
    scales: ['field','property','local_500m','landscape_1500m','broad_3000m'],
    evidence_states: ['candidate_only','accepted','abstained','blocked','unavailable'],
  },
  'mast-capacity': {
    status: 'implemented_source_transport_blocked',
    scales: ['property','local_500m','landscape_1500m','broad_3000m'],
    evidence_states: ['available','unavailable'],
  },
  'annual-mast-state': {
    status: 'planned',
    scales: ['property','regional'],
    evidence_states: ['available','known','proxy','stale','unavailable'],
  },
  'terrain-form-permeability': {
    status: 'production',
    scales: ['local_500m','landscape_1500m'],
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
    status: 'planned',
    scales: ['local_500m','landscape_1500m','broad_3000m'],
    evidence_states: ['available','known','proxy','stale','unavailable'],
  },
  'browse-resource-context': {
    status: 'planned',
    scales: ['property','local_500m','landscape_1500m'],
    evidence_states: ['available','known','proxy','stale','unavailable'],
  },
  'surface-water-state': {
    status: 'planned',
    scales: ['property','local_500m','landscape_1500m'],
    evidence_states: ['available','known','proxy','stale','unavailable'],
  },
  'snow-winter-severity-context': {
    status: 'planned',
    scales: ['property','regional'],
    evidence_states: ['available','known','proxy','stale','unavailable'],
  },
  'extreme-weather-event-context': {
    status: 'planned',
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

type ProductKey = keyof typeof FARM_WATCH_DEER_INPUT_PRODUCT_CATALOG

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
  biological_state_annotation?: {
    state_codes?: string[]
    sex?: FarmWatchDeerSex[]
    require_known_age?: boolean
    regional_reproductive_context?: string[]
  }
}

const ALL_SEX = [...FARM_WATCH_DEER_BIOLOGICAL_STATE_PRODUCT.sexVocabulary]
const ALL_AGE = [...FARM_WATCH_DEER_BIOLOGICAL_STATE_PRODUCT.ageVocabulary]
const PARAMETER_SOURCE = 'FARM_WATCH_DEER_SCIENCE_EVIDENCE_LEDGER.md@2026-09-21'

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

function record(value: DeerRelationshipRecord): DeerRelationshipRecord {
  return Object.freeze(value)
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
      req('diel_state',['diel-photoperiod-context'],['property']),
    ],
    biological_state_gates:gate({sex:['female'],seasons:['winter'],required_explicit_dimensions:['sex','season','diel_period']}),
    spatial_scale:{relationship_scales:['local_500m','landscape_1500m'],notes:'Dense-cover availability modifies the response.'},
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
    title:'Movement varies by diel and reproductive context',
    module_family:'reproductive_movement',
    response_variable:'daily and fine-scale movement',
    required_inputs:[
      req('biological_state',['deer-biological-state'],['individual_scenario']),
      req('diel_state',['diel-photoperiod-context'],['property']),
    ],
    biological_state_gates:gate({required_explicit_dimensions:['diel_period']}),
    spatial_scale:{relationship_scales:['property','regional'],notes:'Context relationship; no transferred movement-rate coefficient.'},
    temporal_scale:'diel and reproductive phases',
    relationship_form:'crepuscular pattern plus sex/reproductive-state differences',
    direction:'conditional',
    supported_nonlinearity:null,
    coefficient_transfer:{status:'not_supported',numeric_parameters:[]},
    parameter_source_version:PARAMETER_SOURCE,
    null_or_blocked_conditions:[],
    blocked_universal_assumptions:[],
    output_kind:'ordinal_directional',
    limitations:['Population-specific movement magnitudes are not transferred.'],
    biological_state_annotation:{},
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
      sex:['male'], regional_reproductive_context:['within_documented_breeding_season','within_peak_month_context'],
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
    biological_state_gates:gate({seasons:['fall'],required_explicit_dimensions:['season']}),
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
    limitations:['No current-year mast state means insufficient input; modeled tree capacity is not mast production.'],
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
      req('resource_state',['field-phenology-context','browse-resource-context'],['field','local_500m'],['available','known','proxy']),
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
      req('resource_state',['field-phenology-context','browse-resource-context'],['field','local_500m'],['available','known','proxy']),
      req('biological_state',['deer-biological-state'],['individual_scenario']),
      req('diel_state',['diel-photoperiod-context'],['property']),
    ],
    biological_state_gates:gate({sex:['male','female'],required_explicit_dimensions:['sex','diel_period']}),
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
      req('forest_context',['spatial-edge-patch-context'],['local_500m']),
      req('biological_state',['deer-biological-state'],['individual_scenario']),
      req('human_footprint',['human-footprint-context'],['local_500m','landscape_1500m'],['available','known','proxy'],'static_context_ok'),
    ],
    biological_state_gates:gate({movement_state:['dispersal'],required_explicit_dimensions:['movement_state']}),
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
  }),
  record({
    relationship_id:'FW-R19-juvenile-male-dispersal-ag-riparian',
    ledger_ids:['FW-D15'],
    source_citations:['Gilbertson et al. 2022, Movement Ecology 10:43, DOI:10.1186/s40462-022-00342-5'],
    title:'Juvenile-male dispersal depends on agriculture and riparian context',
    module_family:'terrain_movement_context',
    response_variable:'dispersal probability, distance and path selection',
    required_inputs:[
      req('biological_state',['deer-biological-state'],['individual_scenario']),
      req('agriculture_context',['field-phenology-context'],['field','landscape_1500m','broad_3000m'],['available','known','proxy']),
      req('water_context',['surface-water-state'],['local_500m','landscape_1500m'],['available','known','proxy']),
    ],
    biological_state_gates:gate({
      sex:['male'],age_class:['juvenile','yearling'],movement_state:['dispersal'],
      required_explicit_dimensions:['sex','age_class','movement_state'],
    }),
    spatial_scale:{relationship_scales:['landscape_1500m','broad_3000m','multiscale'],notes:'Natal-range agriculture and path selection occur at different scales.'},
    temporal_scale:'seasonal dispersal',
    relationship_form:'agriculture influences dispersal probability/distance while actual paths can avoid agriculture and select riparian features',
    direction:'interaction',
    supported_nonlinearity:null,
    coefficient_transfer:{status:'not_supported',numeric_parameters:[]},
    parameter_source_version:PARAMETER_SOURCE,
    null_or_blocked_conditions:['resident adults must not consume this relationship'],
    blocked_universal_assumptions:['nearest_water_or_discharge_equals_deer_use'],
    output_kind:'ordinal_directional',
    limitations:['Riparian selection in dispersal is not a generic resident-deer water rule.'],
  }),
  record({
    relationship_id:'FW-R20-multiscale-cover-food-context',
    ledger_ids:['FW-D16'],
    source_citations:['Nagy-Reis et al. 2019, Journal of Environmental Management 248:109299, DOI:10.1016/j.jenvman.2019.109299'],
    title:'Cover and food operate at different spatial scales',
    module_family:'terrain_movement_context',
    response_variable:'winter occurrence and abundance',
    required_inputs:[
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
      req('resource_context',['field-phenology-context','browse-resource-context'],['field','local_500m','landscape_1500m'],['available','known','proxy']),
      req('biological_state',['deer-biological-state'],['individual_scenario']),
    ],
    biological_state_gates:gate({required_explicit_dimensions:['season']}),
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
  }),
  record({
    relationship_id:'FW-R23-water-rainfall-context',
    ledger_ids:['FW-D19'],
    source_citations:['Webb et al. 2006, Southwestern Naturalist 51:368-375, DOI:10.1894/0038-4909(2006)51[368:WQASUO]2.0.CO;2'],
    title:'Water-source visitation is rainfall and availability conditional',
    module_family:'water_hydrology_context',
    response_variable:'water-source visitation frequency',
    required_inputs:[
      req('water_state',['surface-water-state'],['property','local_500m','landscape_1500m'],['available','known','proxy']),
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
