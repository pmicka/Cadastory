import {
  FARM_WATCH_DEER_RELATIONSHIPS,
  deerMeasurementEvidenceFidelityClass,
  getDeerRelationship,
  type DeerEvidenceFidelityClass,
} from './farm-watch-deer-relationship-registry.ts'

export type DeerInteractionType =
  | 'statistical_interaction'
  | 'conditional_effect'
  | 'state_dependent'
  | 'mechanistic_joint_context'

export type DeerInteractionRecord = {
  interaction_id: string
  ledger_ids: string[]
  relationship_ids: string[]
  title: string
  biological_mechanism: string
  response_variable: string
  participating_variables: string[]
  interaction_type: DeerInteractionType
  structure: 'requires_all' | 'conditional_on' | 'effect_modified_by' | 'state_specific' | 'source_statistical_interaction'
  state_gate_relationship_ids: string[]
  required_measurements: Array<{
    measurement_id: string
    minimum_fidelity: Exclude<DeerEvidenceFidelityClass, 'mechanism_only' | 'unavailable'>
  }>
  context_only_measurement_ids: string[]
  temporal_scale: string
  spatial_scale: string
  supported_form: string
  supported_direction: string
  supported_nonlinearity: string | null
  coefficient_transfer_disposition: 'not_authorized'
  property_conditioning_eligibility: 'not_configured'
  null_or_blocked_conditions: string[]
  transfer_limitations: string[]
  interpretation_boundary: string
}

const interaction = (row: DeerInteractionRecord): DeerInteractionRecord => Object.freeze({ ...row })

// This registry encodes only interaction structure identified in the existing ledger.
// It stores no arithmetic formula and never transfers a source coefficient.
export const FARM_WATCH_DEER_INTERACTIONS: readonly DeerInteractionRecord[] = Object.freeze([
  interaction({
    interaction_id: 'FW-I01-thermal-vegetation-forage-activity-period',
    ledger_ids: ['FW-D01'],
    relationship_ids: ['FW-R01-summer-thermal-resource-tradeoff'],
    title: 'Summer thermal, vegetation and forage relationships vary by activity period',
    biological_mechanism: 'Thermal conditions and vegetation structure modify the context in which forage value relates to within-habitat selection across activity periods.',
    response_variable: 'within-habitat resource selection',
    participating_variables: ['operative_temperature', 'vegetation_height', 'woody_canopy', 'forage_index', 'study_activity_period'],
    interaction_type: 'statistical_interaction',
    structure: 'source_statistical_interaction',
    state_gate_relationship_ids: ['FW-R01-summer-thermal-resource-tradeoff'],
    required_measurements: [
      { measurement_id: 'FW-M01-operative-temperature', minimum_fidelity: 'exact' },
      { measurement_id: 'FW-M02-vegetation-height', minimum_fidelity: 'study_aligned_derivative' },
      { measurement_id: 'FW-M03-forage-index', minimum_fidelity: 'exact' },
      { measurement_id: 'FW-M04-woody-canopy', minimum_fidelity: 'exact' },
      { measurement_id: 'FW-M05-activity-period', minimum_fidelity: 'exact' },
    ],
    context_only_measurement_ids: [],
    temporal_scale: 'June-July summer; study-defined morning, midday, evening and night periods',
    spatial_scale: 'within-habitat selection in south Texas study sites',
    supported_form: 'The fitted selection relationship included interactions with activity period; at midday, operative temperature, vegetation height and woody canopy jointly represented the better-supported thermal/structure model.',
    supported_direction: 'Conditional by activity period; taller vegetation was selected in morning and midday and shorter vegetation in evening/night; forage quality mattered across periods.',
    supported_nonlinearity: null,
    coefficient_transfer_disposition: 'not_authorized',
    property_conditioning_eligibility: 'not_configured',
    null_or_blocked_conditions: ['Current thermal exposure is not operative temperature.', 'Current field phenology and browse products do not reproduce the study forage index.', 'Mechanism-only thermal, canopy or activity-period evidence cannot satisfy a required measurement.'],
    transfer_limitations: ['Adult males in south Texas; June-July 2008-2009.', 'No source coefficient or effect size transfers.', 'Concealment was not selected in this study.'],
    interpretation_boundary: 'Registered because the ledger describes an explicit fitted interaction. It remains blocked until every required study measurement is aligned; available physical context cannot partially activate it.',
  }),
  interaction({
    interaction_id: 'FW-I02-winter-snow-conifer-availability',
    ledger_ids: ['FW-D03'],
    relationship_ids: ['FW-R03-winter-snow-conifer-context'],
    title: 'Winter snow response depends on dense-conifer availability',
    biological_mechanism: 'Dense conifer availability modifies the relationship between winter snow conditions and winter cover use; daily minimum temperature and daytime solar context remain distinct source context.',
    response_variable: 'winter use of dense conifer versus open vegetation',
    participating_variables: ['daily_snow_depth', 'daily_minimum_temperature', 'dense_conifer_availability', 'winter_state', 'diel_period'],
    interaction_type: 'conditional_effect',
    structure: 'effect_modified_by',
    state_gate_relationship_ids: ['FW-R03-winter-snow-conifer-context'],
    required_measurements: [
      { measurement_id: 'FW-M08-snow-depth-severity', minimum_fidelity: 'study_aligned_derivative' },
      { measurement_id: 'FW-M09-dense-conifer-cover', minimum_fidelity: 'calibrated_proxy' },
    ],
    context_only_measurement_ids: ['FW-M10-winter-solar-context'],
    temporal_scale: 'winter across 12 Minnesota winters; daily snow depth and minimum temperature',
    spatial_scale: 'local cover use with dense-conifer availability at study-site scale; Farm Watch broad_3000m proxy',
    supported_form: 'Dense-cover use increased with snow depth, most strongly where dense cover was more available; at the lowest minimum temperatures, daytime open-vegetation use increased.',
    supported_direction: 'Conditional; no universal dense-cover preference or cold response.',
    supported_nonlinearity: 'Source Minnesota WSI thresholds are context only and are not transferred as a Farm Watch threshold.',
    coefficient_transfer_disposition: 'not_authorized',
    property_conditioning_eligibility: 'not_configured',
    null_or_blocked_conditions: ['Winter gate must pass.', 'Both daily snow/minimum-temperature evidence and conifer availability are required.', 'The calibrated conifer proxy must retain its broad_3000m scale and source-class limitations.'],
    transfer_limitations: ['Northern Minnesota severe-winter system; 12 winters and female deer.', 'No Minnesota WSI category, response coefficient, Kentucky biological threshold or generic winter-cover score transfers.', 'FW-M10 solar/thermal context does not substitute for the source variables.'],
    interpretation_boundary: 'This is conditional winter context only. It does not establish property use, bedding, thermal refuge quality or a deer-use probability.',
  }),
  interaction({
    interaction_id: 'FW-I03-winter-agriculture-browse-activity',
    ledger_ids: ['FW-D09'],
    relationship_ids: ['FW-R13-winter-food-configuration-activity'],
    title: 'Winter diel activity response depends jointly on agriculture and woody browse',
    biological_mechanism: 'The association between woody twig density and winter night/evening activity changes with the amount of agriculture in the landscape.',
    response_variable: 'winter diel activity distribution',
    participating_variables: ['landscape_agriculture_amount', 'woody_twig_density', 'development_density', 'diel_period', 'winter_state'],
    interaction_type: 'statistical_interaction',
    structure: 'source_statistical_interaction',
    state_gate_relationship_ids: ['FW-R13-winter-food-configuration-activity'],
    required_measurements: [
      { measurement_id: 'FW-M22-winter-agriculture-amount', minimum_fidelity: 'study_aligned_derivative' },
      { measurement_id: 'FW-M23-woody-twig-density', minimum_fidelity: 'calibrated_proxy' },
      { measurement_id: 'FW-M24-building-density', minimum_fidelity: 'study_aligned_derivative' },
    ],
    context_only_measurement_ids: [],
    temporal_scale: 'winter diel cycle',
    spatial_scale: '48 Midwest landscapes, each 10.36 km²; landscape-level predictors',
    supported_form: 'The woody-twig-density association with night/evening activity differed across agriculture amount; building density was a separate activity-level relationship.',
    supported_direction: 'Where agriculture was limited, more twig density corresponded to less night/evening activity; where agriculture was plentiful, more twig density corresponded to a more pronounced night/evening pattern.',
    supported_nonlinearity: null,
    coefficient_transfer_disposition: 'not_authorized',
    property_conditioning_eligibility: 'not_configured',
    null_or_blocked_conditions: ['The unsupported woody-twig-density measurement blocks activation.', 'Do not infer independent agriculture or browse weights.', 'Human-footprint context does not satisfy either food measurement.'],
    transfer_limitations: ['Midwest camera-trap study; no Kentucky activity effect or coefficient transfers.', 'Farm Watch agriculture amount is not yet the study landscape metric.'],
    interpretation_boundary: 'A supported joint structure is recorded, but current Farm Watch evidence cannot activate it while woody twig density and aligned agriculture remain unavailable.',
  }),
  interaction({
    interaction_id: 'FW-I04-corn-identity-stage-harvest',
    ledger_ids: ['FW-D08'],
    relationship_ids: ['FW-R12-crop-phenology-home-range-response'],
    title: 'Female space-use response depends on corn identity and field stage',
    biological_mechanism: 'The published spatial response was conditional on corn development and the post-harvest transition, not generic agricultural geometry.',
    response_variable: 'female home-range center and size',
    participating_variables: ['current_field_crop_identity', 'corn_tasseling_or_silking', 'post_harvest_state', 'permanent_cover_geometry'],
    interaction_type: 'conditional_effect',
    structure: 'conditional_on',
    state_gate_relationship_ids: ['FW-R12-crop-phenology-home-range-response'],
    required_measurements: [
      { measurement_id: 'FW-M19-current-corn-identity', minimum_fidelity: 'exact' },
      { measurement_id: 'FW-M20-corn-stage-harvest', minimum_fidelity: 'exact' },
    ],
    context_only_measurement_ids: ['FW-M21-permanent-cover'],
    temporal_scale: 'field-level crop stage and post-harvest transition',
    spatial_scale: 'field/property home-range response; Nebraska/Iowa study',
    supported_form: 'At tasseling/silking, home-range centers shifted toward corn; after harvest, centers shifted away from crop fields toward permanent cover.',
    supported_direction: 'Stage-specific and conditional; no generic agriculture direction.',
    supported_nonlinearity: 'Pre-harvest versus post-harvest state transition.',
    coefficient_transfer_disposition: 'not_authorized',
    property_conditioning_eligibility: 'not_configured',
    null_or_blocked_conditions: ['Known corn identity with unknown field stage is insufficient input.', 'A known non-corn crop is not applicable.', 'Regional crop progress, stale CDL or generic vegetation change cannot satisfy current field stage.'],
    transfer_limitations: ['Nebraska/Iowa female study; no distance or range-size coefficient transfers.', 'Property-specific deer use is not inferred.'],
    interpretation_boundary: 'Crop identity and stage are conjunctive scientific requirements. Agriculture geometry or crop identity alone cannot activate this interaction.',
  }),
  interaction({
    interaction_id: 'FW-I05-discrete-hunt-event-diel-response',
    ledger_ids: ['FW-D10'],
    relationship_ids: ['FW-R14-discrete-hunt-localized-risk'],
    title: 'Response to a localized hunting event depends on diel period',
    biological_mechanism: 'The change in use around a stand depends on whether a documented stand-specific hunt event occurred and on time of day.',
    response_variable: 'use of food and vulnerability zones near hunted stands',
    participating_variables: ['localized_hunt_event', 'stand_vulnerability_zone', 'hunter_occupancy', 'diel_period', 'elapsed_time_since_event'],
    interaction_type: 'conditional_effect',
    structure: 'effect_modified_by',
    state_gate_relationship_ids: ['FW-R14-discrete-hunt-localized-risk'],
    required_measurements: [
      { measurement_id: 'FW-M25-discrete-stand-hunt', minimum_fidelity: 'exact' },
      { measurement_id: 'FW-M26-stand-vulnerability-zone', minimum_fidelity: 'exact' },
      { measurement_id: 'FW-M27-hunt-diel-period', minimum_fidelity: 'exact' },
    ],
    context_only_measurement_ids: [],
    temporal_scale: 'recent event; midday, night and crepuscular periods',
    spatial_scale: 'stand-local vulnerability zones, not uniform distance buffers',
    supported_form: 'After a stand was hunted, use decreased at midday and increased at night; no detectable crepuscular change was reported.',
    supported_direction: 'Diel-specific conditional response; not a universal hunting-season effect.',
    supported_nonlinearity: null,
    coefficient_transfer_disposition: 'not_authorized',
    property_conditioning_eligibility: 'not_configured',
    null_or_blocked_conditions: ['An open season, nearby stand or distance buffer is not a localized hunting event.', 'Study-specific stand vulnerability geometry and event timing are required.'],
    transfer_limitations: ['Female deer in a single Nebraska study system; no Kentucky response coefficient transfers.'],
    interpretation_boundary: 'No universal hunting-pressure response is inferred; this entry remains unavailable until event and visibility measurements align.',
  }),
  interaction({
    interaction_id: 'FW-I06-hunter-risk-food-diel',
    ledger_ids: ['FW-D11'],
    relationship_ids: ['FW-R15-adult-male-hunter-space-time'],
    title: 'Adult-male risk response depends on hunter activity, food and diel period',
    biological_mechanism: 'Risk-related habitat selection varies with hunter activity over time and with food opportunity.',
    response_variable: 'fine-scale habitat selection',
    participating_variables: ['daily_hunter_activity', 'food_plot_opportunity', 'diel_period', 'adult_male_state'],
    interaction_type: 'statistical_interaction',
    structure: 'source_statistical_interaction',
    state_gate_relationship_ids: ['FW-R15-adult-male-hunter-space-time'],
    required_measurements: [
      { measurement_id: 'FW-M28-daily-hunter-activity', minimum_fidelity: 'exact' },
      { measurement_id: 'FW-M29-food-opportunity', minimum_fidelity: 'study_aligned_derivative' },
      { measurement_id: 'FW-M30-risk-diel-period', minimum_fidelity: 'exact' },
    ],
    context_only_measurement_ids: [],
    temporal_scale: 'daily hunter activity during firearm seasons',
    spatial_scale: 'fine-scale habitat selection in Mississippi study areas',
    supported_form: 'Frequently hunter-selected areas were least selected by deer during daytime; food-plot use could be greater at night when hunting risk was absent.',
    supported_direction: 'Risk response is diel- and food-dependent; the reported five-fold magnitude is not transferred.',
    supported_nonlinearity: null,
    coefficient_transfer_disposition: 'not_authorized',
    property_conditioning_eligibility: 'not_configured',
    null_or_blocked_conditions: ['Unknown hunter activity cannot be inferred from season or stand geometry.', 'Food opportunity is not nutrition, attraction or deer use.'],
    transfer_limitations: ['Adult males in Mississippi; no numeric multiplier or Kentucky coefficient transfers.'],
    interpretation_boundary: 'This interaction describes source structure only; it does not estimate local use or behavioral probability.',
  }),
  interaction({
    interaction_id: 'FW-I07-sex-risk-food-tradeoff',
    ledger_ids: ['FW-D12'],
    relationship_ids: ['FW-R16-sex-risk-food-tradeoff'],
    title: 'Sex modifies the relationship between hunting risk and food opportunity',
    biological_mechanism: 'Adult female and male deer differed in willingness to use risky daytime areas with abundant mapped food.',
    response_variable: 'sex- and time-specific cover/resource selection',
    participating_variables: ['sex', 'adult_age_class', 'measured_hunting_pressure', 'food_resource_state', 'diel_period'],
    interaction_type: 'statistical_interaction',
    structure: 'effect_modified_by',
    state_gate_relationship_ids: ['FW-R16-sex-risk-food-tradeoff'],
    required_measurements: [
      { measurement_id: 'FW-M31-frequent-hunt-risk', minimum_fidelity: 'exact' },
      { measurement_id: 'FW-M32-abundant-food-risk', minimum_fidelity: 'study_aligned_derivative' },
    ],
    context_only_measurement_ids: [],
    temporal_scale: 'adult use over diel periods in hunted landscapes',
    spatial_scale: 'South Carolina hunted landscape; local risk/food context',
    supported_form: 'Both sexes generally avoided frequently hunted/risky areas by day; females were more willing than males to use risky daytime areas containing abundant food.',
    supported_direction: 'Sex-specific conditional tradeoff; no sex-neutral collapse.',
    supported_nonlinearity: null,
    coefficient_transfer_disposition: 'not_authorized',
    property_conditioning_eligibility: 'not_configured',
    null_or_blocked_conditions: ['Sex and adult state must pass the relationship state gate.', 'Measured pressure and study-relevant food context are required.'],
    transfer_limitations: ['South Carolina study; no Kentucky effect size or universal sex preference transfers.', 'Mapped food context is not forage chemistry or observed use.'],
    interpretation_boundary: 'Property covariates do not identify the sex, pressure or behavior of deer using the property.',
  }),
  interaction({
    interaction_id: 'FW-I08-mast-annual-state-fall',
    ledger_ids: ['FW-D07'],
    relationship_ids: ['FW-R11-mast-fall-space-use'],
    title: 'Fall space-use response requires exact-year annual mast state',
    biological_mechanism: 'The fall relationship concerns realized annual acorn production and its spatial availability; static mast-producing capacity is potential resource structure only.',
    response_variable: 'female home-range adjustment and foraging during mast fall',
    participating_variables: ['fall_season', 'exact_year_annual_mast_state', 'mast_capacity_as_context'],
    interaction_type: 'conditional_effect',
    structure: 'conditional_on',
    state_gate_relationship_ids: ['FW-R11-mast-fall-space-use'],
    required_measurements: [
      { measurement_id: 'FW-M17-annual-mast-fall', minimum_fidelity: 'calibrated_proxy' },
    ],
    context_only_measurement_ids: ['FW-M18-mast-producing-area'],
    temporal_scale: 'exact-year mast fall; female fall-season response',
    spatial_scale: 'mature deciduous forest and property/landscape resource availability',
    supported_form: 'Female deer shifted or enlarged ranges toward acorn-producing areas during mast fall; realized annual production is distinct from the spatial capacity to produce mast.',
    supported_direction: 'Conditional on current-year annual mast state; no universal capacity-based positive direction.',
    supported_nonlinearity: null,
    coefficient_transfer_disposition: 'not_authorized',
    property_conditioning_eligibility: 'not_configured',
    null_or_blocked_conditions: ['Static mast capacity cannot substitute for exact-year annual mast state.', 'Prior-year mast reports cannot be carried forward.', 'Regional annual survey state is not property-level mast abundance.'],
    transfer_limitations: ['Ten radiomarked females in mature Virginia forest, 1986-1989.', 'No coefficient, property mast abundance or deer use is inferred.'],
    interpretation_boundary: 'Mast capacity may remain visible as context but cannot activate the annual-state interaction.',
  }),
  interaction({
    interaction_id: 'FW-I09-dispersal-terrain-landscape-state',
    ledger_ids: ['FW-D14'],
    relationship_ids: ['FW-R18-terrain-movement-context'],
    title: 'Terrain and road responses depend on landscape context and dispersal state',
    biological_mechanism: 'The direction of terrain/road selection differed between contrasting landscapes and movement periods for dispersing juvenile males.',
    response_variable: 'multiscale step selection during dispersal',
    participating_variables: ['juvenile_male_state', 'dispersal_state', 'terrain', 'forest_availability_configuration', 'road_context'],
    interaction_type: 'state_dependent',
    structure: 'state_specific',
    state_gate_relationship_ids: ['FW-R18-terrain-movement-context'],
    required_measurements: [
      { measurement_id: 'FW-M34-dispersal-terrain-form', minimum_fidelity: 'calibrated_proxy' },
      { measurement_id: 'FW-M35-forest-landscape-context', minimum_fidelity: 'study_aligned_derivative' },
      { measurement_id: 'FW-M36-road-landscape-context', minimum_fidelity: 'study_aligned_derivative' },
    ],
    context_only_measurement_ids: [],
    temporal_scale: 'before, during and after juvenile-male dispersal',
    spatial_scale: '30 m, 90 m and 270 m multiscale context across two Missouri landscapes',
    supported_form: 'Terrain and road response changes with landscape context and movement state; the source found different terrain/road patterns across study landscapes.',
    supported_direction: 'Landscape- and state-dependent; no universal valley, ridge, road-selection or road-avoidance direction.',
    supported_nonlinearity: 'Directional reversal across source landscapes and scales.',
    coefficient_transfer_disposition: 'not_authorized',
    property_conditioning_eligibility: 'not_configured',
    null_or_blocked_conditions: ['Unknown movement state blocks activation.', 'A known resident/adult or female state is not applicable.', 'Mechanism-only terrain context cannot satisfy the terrain study measurement.'],
    transfer_limitations: ['Juvenile males in two Missouri landscapes.', 'No Missouri landscape identity, relationship sign or coefficient transfers.', 'Current neutral measurements do not establish deer use.'],
    interpretation_boundary: 'State and landscape context condition the published form. Generic ridge, draw, saddle or funnel heuristics remain unregistered.',
  }),
  interaction({
    interaction_id: 'FW-I10-male-age-breeding-date-state',
    ledger_ids: ['FW-D06'],
    relationship_ids: ['FW-R09-male-breeding-age-movement'],
    title: 'Male breeding-season movement is age- and date-dependent',
    biological_mechanism: 'The relationship between date within the breeding season and male movement differs by age class.',
    response_variable: 'hourly movement rate and daily range',
    participating_variables: ['male_sex', 'study_aligned_age_class', 'regional_breeding_phase', 'date'],
    interaction_type: 'state_dependent',
    structure: 'state_specific',
    state_gate_relationship_ids: ['FW-R09-male-breeding-age-movement'],
    required_measurements: [
      { measurement_id: 'FW-M15-hunsaker-male-age', minimum_fidelity: 'exact' },
    ],
    context_only_measurement_ids: [],
    temporal_scale: 'source-defined breeding-season dates and movement windows',
    spatial_scale: 'Wisconsin study population; regional reproductive timing context',
    supported_form: 'The published relationship distinguishes male age classes and breeding-season timing; its timing and movement magnitudes are population-specific.',
    supported_direction: 'Age- and date-dependent; no regional timing proxy establishes individual reproductive state.',
    supported_nonlinearity: 'Source-reported age-class differences and breeding-season changepoint form.',
    coefficient_transfer_disposition: 'not_authorized',
    property_conditioning_eligibility: 'not_configured',
    null_or_blocked_conditions: ['Unknown male age or regional breeding context blocks activation.', 'The evaluator does not infer an individual animal rut state from regional dates.'],
    transfer_limitations: ['Wisconsin timing is not Kentucky timing.', 'Farm Watch age classes do not reproduce the source distinctions between 2-year-old and 3+ males.', 'No movement coefficient transfers.'],
    interpretation_boundary: 'This is regional/state-conditioned movement context, not a rut score, individual reproductive inference or property-use claim.',
  }),
])

const fidelityRank: Record<DeerEvidenceFidelityClass, number> = {
  exact: 4,
  study_aligned_derivative: 3,
  calibrated_proxy: 2,
  mechanism_only: 1,
  unavailable: 0,
}

export function validateDeerInteractionRecord(row: DeerInteractionRecord) {
  if (!/^FW-I\d{2}-[a-z0-9-]+$/.test(row.interaction_id)) return false
  if (!row.ledger_ids.length || row.ledger_ids.some((id) => !/^FW-D\d{2}$/.test(id))) return false
  if (!row.relationship_ids.length || row.relationship_ids.some((id) => !getDeerRelationship(id))) return false
  if (!row.state_gate_relationship_ids.length || row.state_gate_relationship_ids.some((id) => !row.relationship_ids.includes(id))) return false
  if (!row.participating_variables.length || !row.required_measurements.length) return false
  if (!row.temporal_scale.trim() || !row.spatial_scale.trim() || !row.supported_form.trim()) return false
  if (row.coefficient_transfer_disposition !== 'not_authorized') return false
  if (row.property_conditioning_eligibility !== 'not_configured') return false
  const measurements = new Set<string>()
  for (const item of row.required_measurements) {
    if (measurements.has(item.measurement_id)) return false
    measurements.add(item.measurement_id)
    if (fidelityRank[item.minimum_fidelity] < fidelityRank.calibrated_proxy) return false
    const owners = row.relationship_ids.flatMap((id) => getDeerRelationship(id)?.study_measurements || [])
    const source = owners.find((measurement) => measurement.id === item.measurement_id)
    if (!source) return false
    // A registry requirement may intentionally exceed current source alignment;
    // the evaluator then blocks activation by fidelity rather than invalidating the record.
    if (!row.ledger_ids.some((ledgerId) => row.relationship_ids.some((id) => getDeerRelationship(id)?.ledger_ids.includes(ledgerId)))) return false
  }
  for (const measurementId of row.context_only_measurement_ids) {
    const source = row.relationship_ids.flatMap((id) => getDeerRelationship(id)?.study_measurements || [])
      .find((measurement) => measurement.id === measurementId)
    if (!source || source.activation_requirement !== 'context_only') return false
  }
  for (const id of row.relationship_ids) {
    const relationship = getDeerRelationship(id)
    if (!relationship || !relationship.ledger_ids.some((ledgerId) => row.ledger_ids.includes(ledgerId))) return false
  }
  return true
}

export function validateDeerInteractionRegistry() {
  const ids = new Set<string>()
  for (const row of FARM_WATCH_DEER_INTERACTIONS) {
    if (!validateDeerInteractionRecord(row) || ids.has(row.interaction_id)) return false
    ids.add(row.interaction_id)
  }
  return true
}

export function getDeerInteraction(interactionId: string) {
  return FARM_WATCH_DEER_INTERACTIONS.find((row) => row.interaction_id === interactionId) || null
}

export function deerInteractionRelationshipRows(row: DeerInteractionRecord) {
  return row.relationship_ids.map((id) => FARM_WATCH_DEER_RELATIONSHIPS.find((relationship) => relationship.relationship_id === id) || null)
}
