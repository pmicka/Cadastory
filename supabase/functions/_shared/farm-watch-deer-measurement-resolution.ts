import {
  FARM_WATCH_DEER_RELATIONSHIPS,
  type DeerMeasurementAlignment,
} from './farm-watch-deer-relationship-registry.ts'

export const FARM_WATCH_DEER_MEASUREMENT_RESOLUTION_PRODUCT = Object.freeze({
  key: 'deer-measurement-resolution-decisions',
  version: '2026-09-25',
  dispositions: Object.freeze([
    'reproduce',
    'calibrated_proxy',
    'remain_unavailable',
  ] as const),
  operationalPostures: Object.freeze([
    'active',
    'parked_2026_individual_state',
    'parked_2026_manual_or_noncore',
  ] as const),
})

export type DeerMeasurementResolutionDisposition =
  typeof FARM_WATCH_DEER_MEASUREMENT_RESOLUTION_PRODUCT.dispositions[number]
export type DeerMeasurementOperationalPosture =
  typeof FARM_WATCH_DEER_MEASUREMENT_RESOLUTION_PRODUCT.operationalPostures[number]

export type DeerMeasurementResolutionDecision = {
  measurement_id: string
  disposition: DeerMeasurementResolutionDisposition
  target_product: string | null
  priority: 'P0' | 'P1' | 'P2' | 'defer'
  operational_posture: DeerMeasurementOperationalPosture
  operational_note: string
  contract_change_required: boolean
  rationale: string
  implementation_boundary: string
  validation: string[]
}

const PARKED_2026_INDIVIDUAL_STATE_IDS = new Set([
  'FW-M15-hunsaker-male-age',
  'FW-M51-maternal-age-category',
  'FW-M54-female-parturition-phase',
])

const PARKED_2026_MANUAL_OR_NONCORE_IDS = new Set([
  'FW-M01-operative-temperature',
  'FW-M03-forage-index',
  'FW-M05-activity-period',
  'FW-M19-current-corn-identity',
  'FW-M20-corn-stage-harvest',
  'FW-M23-woody-twig-density',
  'FW-M25-discrete-stand-hunt',
  'FW-M28-daily-hunter-activity',
  'FW-M31-frequent-hunt-risk',
  'FW-M33-low-hunting-pressure',
  'FW-M40-d16-escape-cover-types',
  'FW-M41-d16-winter-food',
  'FW-M42-human-footprint-composition',
  'FW-M44-wolf-occurrence',
  'FW-M53-male-reproductive-phase',
])

function operationalPosture(measurementId: string): {
  operational_posture: DeerMeasurementOperationalPosture
  operational_note: string
} {
  if (PARKED_2026_INDIVIDUAL_STATE_IDS.has(measurementId)) {
    return {
      operational_posture: 'parked_2026_individual_state',
      operational_note:
        'Parked for the 2026 season because reliable individual identification/differentiation is not part of the current Farm Watch operating model. Scientific abstention remains required when the individual state is unknown.',
    }
  }
  if (PARKED_2026_MANUAL_OR_NONCORE_IDS.has(measurementId)) {
    return {
      operational_posture: 'parked_2026_manual_or_noncore',
      operational_note:
        'Parked for the 2026 season because this measurement would require repeated manual user input, a calibration/technology stack outside the intended operating model, or an unavailable study-specific variable. Its scientific disposition is unchanged.',
    }
  }
  return {
    operational_posture: 'active',
    operational_note:
      'Active implementation candidate because it can be pursued autonomously or with bounded one-time/static configuration under the current Farm Watch operating model.',
  }
}

function decision(
  measurement_id: string,
  disposition: DeerMeasurementResolutionDisposition,
  target_product: string | null,
  priority: DeerMeasurementResolutionDecision['priority'],
  contract_change_required: boolean,
  rationale: string,
  implementation_boundary: string,
  validation: string[] = [],
): DeerMeasurementResolutionDecision {
  return Object.freeze({
    measurement_id,
    disposition,
    target_product,
    priority,
    ...operationalPosture(measurement_id),
    contract_change_required,
    rationale,
    implementation_boundary,
    validation,
  })
}

export const FARM_WATCH_DEER_MEASUREMENT_RESOLUTION_DECISIONS:
  readonly DeerMeasurementResolutionDecision[] = Object.freeze([
  decision(
    'FW-M01-operative-temperature',
    'calibrated_proxy',
    'operative-temperature-context',
    'P1',
    true,
    'The source study measured 15.24 cm matte-black copper globe temperature at 0.5 m above ground every 30 minutes. Farm Watch already has air temperature, wind, shortwave/longwave radiation and terrain/canopy geometry, so a physically modeled operative-temperature surface is feasible but is not measurement-equivalent until checked against black-globe observations.',
    'Do not relabel thermal-exposure-context as operative temperature. Build a separate physical model and retain its meteorological/radiative assumptions.',
    ['Deploy a small number of black-globe loggers across sun/shade and structure classes', 'Compare bias/RMSE by hour and vegetation class before promotion'],
  ),
  decision(
    'FW-M03-forage-index',
    'remain_unavailable',
    null,
    'defer',
    false,
    'The source forage index combined field-estimated standing crop with laboratory crude protein and acid detergent fiber for selected forage species. NDVI, EVI, greenness, crop identity, or generic browse structure do not measure those variables.',
    'Do not build a remote-sensing forage-index surrogate for this relationship. Revisit only if standardized vegetation sampling and laboratory forage chemistry are intentionally collected.',
  ),
  decision(
    'FW-M04-woody-canopy',
    'calibrated_proxy',
    'woody-canopy-cover-context',
    'P1',
    true,
    'The study used line-intercept percent woody canopy cover along 30 m transects. Farm Watch has modeled tree-canopy cover and high-resolution imagery, which can estimate the same physical concept but not with the same observation protocol.',
    'Keep percent woody canopy distinct from generic TCC until a remote estimate is calibrated to field/imagery line-intercept measurements.',
    ['Collect/derive line-intercept canopy cover at representative plots', 'Compare remote canopy percent against line-intercept percent across open, intermediate and closed classes'],
  ),
  decision(
    'FW-M05-activity-period',
    'calibrated_proxy',
    'deer-activity-period-context',
    'P2',
    true,
    'The study defined morning, midday and evening from observed movement-rate patterns; only the nocturnal window had a direct sunrise/sunset rule. Solar phase alone is therefore not equivalent.',
    'Do not infer local movement-defined activity periods from civil twilight. A local activity-period proxy may be calibrated from sufficiently dense camera or other movement observations while preserving source-study time semantics.',
    ['Estimate local diel detection/activity curves from independent observations', 'Hold out observations when defining period boundaries'],
  ),
  decision(
    'FW-M08-snow-depth-severity',
    'reproduce',
    'snow-winter-severity-context',
    'P2',
    true,
    'The source uses daily snow depth, minimum temperature, and a published winter-severity index definition. These are physical environmental variables available from authoritative observed/modelled snow and temperature products.',
    'Represent raw snow depth and temperature separately. The Minnesota WSI may be reproduced as provenance/context but must not become a Kentucky biological threshold without transfer review.',
    ['Cross-check modelled snow depth with nearby authoritative observations during snow events'],
  ),
  decision(
    'FW-M09-dense-conifer-cover',
    'calibrated_proxy',
    'conifer-cover-context',
    'P2',
    true,
    'The source manually classified dominant conifer stands and canopy-closure classes, with dense cover defined as at least 70% closure. Public forest-type/land-cover data plus TCC can approximate this, but species/forest-type errors at 30 m matter.',
    'Use explicit conifer/evergreen forest type plus canopy closure; generic canopy density is insufficient.',
    ['Spot-check forest type and closure with leaf-on/leaf-off imagery or field observations before use'],
  ),
  decision(
    'FW-M11-gallina-concealment-profile',
    'calibrated_proxy',
    'low-height-concealment-context',
    'P0',
    false,
    'A map-wide virtual cover-board product can be built from terrain, height-specific vegetation structure, horizontal woody organization and seasonal foliage state, but current remote structure cannot be assumed to equal observed percent concealment.',
    'Reproduce the 2 m target, 15 m observation distance, four 50 cm strata and directionality exactly; calibration is against the field protocol, not deer bed occurrence.',
    ['Use segmented 2 m field targets at known non-sensitive locations', 'Hold out some directions/sites as validation', 'Calibrate leaf-on and leaf-off separately'],
  ),
  decision(
    'FW-M13-gallina-low-strata',
    'calibrated_proxy',
    'low-height-concealment-context',
    'P0',
    false,
    'This is the low-strata subset of the Gallina concealment protocol and should be produced by the same calibrated virtual cover-board model.',
    'Preserve 0-50 cm and 50-100 cm outputs separately; do not collapse them into a general obstruction score.',
    ['Validate the two lowest target strata independently'],
  ),
  decision(
    'FW-M15-hunsaker-male-age',
    'reproduce',
    'deer-biological-state',
    'P0',
    true,
    'The source age categories are explicit biological scenario states: yearling, 2-year-old, and 3+ male. Farm Watch can preserve these categories exactly when the scenario/animal age is known or intentionally selected.',
    'Expand age-state vocabulary or add a source-specific male-age dimension. Never infer exact age from calendar, imagery or generic adult status.',
    ['Unit-test that unknown adult age abstains and 2-year/3+ scenarios remain distinct'],
  ),
  decision(
    'FW-M19-current-corn-identity',
    'reproduce',
    'current-crop-identity',
    'P0',
    false,
    'Current field identity as corn is an observable categorical state. Farm Watch can accept an explicit operator observation or another source whose rights and validation permit field-level current crop identity.',
    'Do not promote stale CDL or regional crop progress to current field identity.',
    ['Require explicit current-year provenance and field binding'],
  ),
  decision(
    'FW-M20-corn-stage-harvest',
    'reproduce',
    'field-phenology-context',
    'P0',
    true,
    'Tasseling/silking and harvested are observable field states and can be represented directly when an explicit current observation exists. HLS trajectories alone are not sufficient to assign them.',
    'Provide a direct-observation/accepted-source state path first. Any automated HLS classifier remains a separate calibrated model.',
    ['Require explicit field/date provenance', 'Test that raw NDVI/NIR change cannot promote stage without an authorized classifier'],
  ),
  decision(
    'FW-M23-woody-twig-density',
    'remain_unavailable',
    null,
    'defer',
    false,
    'Woody twig density/browse availability is a fine-scale forage measurement involving accessible browse material and often species composition. LiDAR low structure and leaf-off texture do not measure palatable twig density.',
    'Do not substitute understory structure, greenness, or canopy for browse/twig density. Revisit only if a standardized browse survey is intentionally collected.',
  ),
  decision(
    'FW-M25-discrete-stand-hunt',
    'reproduce',
    'human-activity-context',
    'P0',
    true,
    'The study used daily records of which specific stands were hunted. Farm Watch can reproduce this exactly for known property activity using explicit stand/session event logging.',
    'Unknown neighboring or unlogged activity stays unknown; season-open status is not an event.',
    ['Require stand ID, start/end time and event provenance'],
  ),
  decision(
    'FW-M26-stand-vulnerability-zone',
    'calibrated_proxy',
    'stand-vulnerability-zone-context',
    'P0',
    false,
    'The study sat in each stand and used a laser rangefinder to delineate where deer would be visible within 200 m. A terrain/vegetation viewshed can reproduce the geometry computationally only after field calibration.',
    'Use generalized seasonal viewshed physics as the substrate, but calibrate target height, vegetation screening and foliage state against stand-specific range/visibility observations.',
    ['Rangefinder spot-check bearings from representative stands', 'Validate leaf-on and leaf-off vulnerability polygons separately'],
  ),
  decision(
    'FW-M28-daily-hunter-activity',
    'reproduce',
    'human-activity-context',
    'P0',
    true,
    'Daily hunter-use intensity and hunter-selected space are explicit activity records that Farm Watch can represent on the property when sessions/access are logged.',
    'Do not invent off-property hunter activity from roads, boundaries or hunting season.',
    ['Derive hunter-hours and spatial use only from known events/paths'],
  ),
  decision(
    'FW-M29-food-opportunity',
    'reproduce',
    'managed-food-feature-context',
    'P1',
    true,
    'The cited adult-male hunting study specifically identified food plots as a resource whose selection changed between day and night. Food-plot polygons are observable managed features and do not require a generic nutritional-quality proxy.',
    'Tighten the relationship binding from generic resource state to explicit food-plot/managed-food geometry where the source study did so.',
    ['Require mapped feature provenance and active/current management state where relevant'],
  ),
  decision(
    'FW-M31-frequent-hunt-risk',
    'reproduce',
    'human-activity-context',
    'P0',
    true,
    'Frequency/intensity of hunted areas can be calculated directly from dated hunting events tied to stands/zones.',
    'Use explicit event counts/hunter-hours over a declared window; do not infer frequency from stand presence.',
    ['Test frequency windows against the source relationship period definitions'],
  ),
  decision(
    'FW-M32-abundant-food-risk',
    'reproduce',
    'managed-food-feature-context',
    'P1',
    true,
    'In the source sex-risk study the risky forage-rich areas were represented by food plots/cover types, not by remotely inferred crude protein or biomass chemistry. Those mapped managed features can be reproduced directly.',
    'Bind to explicit food-plot/cover-type geometry instead of generic vegetation greenness.',
    ['Preserve cover type and season state; do not claim measured nutrient abundance'],
  ),
  decision(
    'FW-M33-low-hunting-pressure',
    'reproduce',
    'human-activity-context',
    'P0',
    true,
    'The source low-pressure context was supported by explicit hunter attendance/area information. Farm Watch can reproduce quantitative hunter effort density from known events, but should not invent a universal categorical low/high threshold.',
    'Replace the categorical pressure-class gate with explicit hunter effort density and source-range comparison. Unknown activity remains unknown.',
    ['Store hunter-hours or hunter-events per area/time', 'Do not promote a Kentucky low/high threshold without separate transfer review'],
  ),
  decision(
    'FW-M40-d16-escape-cover-types',
    'remain_unavailable',
    null,
    'defer',
    true,
    'Forest and wetland proportions are reproducible, but the source measurement also depends materially on field-level Conservation Reserve Program land. Current public national CRP reporting does not provide a reliable current parcel-level CRP layer suitable for this use.',
    'Split forest/wetland components into neutral reproducible context if useful, but do not activate the FW-D16 relationship without defensible CRP enrollment geometry or explicit operator/landowner knowledge.',
  ),
  decision(
    'FW-M41-d16-winter-food',
    'calibrated_proxy',
    'residual-winter-cropland-context',
    'P2',
    true,
    'Residual winter cropland/food is more specific than crop identity or greenness. Current crop state, harvest timing and post-harvest residue can support a derived estimate, but remote classification needs validation.',
    'Do not treat a harvested field as guaranteed residual food. Model residue state separately.',
    ['Calibrate against roadside/operator observations of residue availability across crop/harvest classes'],
  ),
  decision(
    'FW-M42-human-footprint-composition',
    'remain_unavailable',
    null,
    'defer',
    false,
    'The source relationship is an oil-sands cumulative-effects model with polygonal industrial features, roads/trails/seismic lines, intact deciduous forest and predator occurrence. Reconstructing generic Kentucky human footprint would not reproduce that industrial landscape treatment.',
    'Retain the source as a negative constraint against universal road avoidance/selection. Do not activate the positive cumulative-effects relationship for Flat Creek by substituting generic development.',
  ),
  decision(
    'FW-M43-intact-deciduous-forest',
    'reproduce',
    'forest-type-context',
    'P2',
    true,
    'Intact deciduous forest composition is a mapped habitat/fragmentation variable that can be derived from land-cover/forest-type data and landscape geometry.',
    'Keep this neutral and source-scale; it does not rescue the FW-D17 relationship if human-footprint composition or predator occurrence remains unavailable.',
    ['Validate deciduous/intact classification against imagery and fragmentation geometry'],
  ),
  decision(
    'FW-M44-wolf-occurrence',
    'remain_unavailable',
    null,
    'defer',
    false,
    'The source used a camera-derived monthly wolf-occurrence model as a specific predator-risk covariate. Substituting coyotes, generic predator habitat, or absence assumptions would be a different biological relationship.',
    'Leave this source relationship unavailable for the current Flat Creek implementation. A different predator relationship requires its own evidence ledger entry.',
  ),
  decision(
    'FW-M47-forest-refuge-type',
    'reproduce',
    'forest-type-context',
    'P2',
    true,
    'Pine, hardwood forest/swamp, marsh and shrub habitat classes are physical land-cover types that can be represented from forest-type, wetland and land-cover data.',
    'Preserve the Florida hurricane transfer limitation; reproducing the covariate does not authorize a generic storm-refuge effect.',
    ['Cross-check forest/wetland classes against imagery and NWI/land-cover sources'],
  ),
  decision(
    'FW-M48-usable-water-source',
    'reproduce',
    'surface-water-state',
    'P1',
    true,
    'Current usable stock-pond/trough presence can be represented directly by explicit managed-source inventory or dated operator observation. This is preferable to inventing availability from mapped hydrography.',
    'Mapped lake/stream geometry or regional gauge data cannot satisfy current usable-source presence.',
    ['Require dated present/absent state and stable feature identity for managed sources'],
  ),
  decision(
    'FW-M51-maternal-age-category',
    'reproduce',
    'deer-biological-state',
    'P1',
    true,
    'Fawn, yearling and adult maternal age are explicit scenario categories. Farm Watch can preserve them when known/selected without transferring Illinois conception dates.',
    'Add an explicit fawn/maternal-age mapping rather than assuming current generic juvenile is automatically equivalent.',
    ['Test unknown age abstention and explicit fawn/yearling/adult scenarios'],
  ),
  decision(
    'FW-M53-male-reproductive-phase',
    'remain_unavailable',
    null,
    'defer',
    false,
    'The source male rut/post-rut phase was a biological population/individual movement context. A calendar-derived Kentucky regional rut label is not an individual male reproductive phase, and Farm Watch has no direct individual physiological state.',
    'Retain regional breeding context separately. Do not infer individual rut/post-rut state from date alone.',
  ),
  decision(
    'FW-M54-female-parturition-phase',
    'reproduce',
    'deer-biological-state',
    'P1',
    true,
    'Pre-parturition, parturition and post-parturition can be represented as explicit scenario states when deliberately supplied; the system does not need to infer them from calendar date.',
    'Expand/align the reproductive-state vocabulary and abstain when the scenario is unknown.',
    ['Test explicit state mapping and unknown-state abstention'],
  ),
  decision(
    'FW-M56-potential-path-agriculture',
    'reproduce',
    'dispersal-potential-path-context',
    'P2',
    true,
    'The source built simulated potential dispersal paths and calculated agriculture along those paths. Farm Watch has mapped agricultural land-use geometry and can reproduce the algorithmic covariate once the source path-generation method is implemented.',
    'Do not substitute simple landscape agriculture percentage for the potential-path covariate.',
    ['Reproduce source path-generation assumptions before comparing agriculture exposure'],
  ),
])

export function getDeerMeasurementResolutionDecision(measurementId: string) {
  return FARM_WATCH_DEER_MEASUREMENT_RESOLUTION_DECISIONS.find(
    (row) => row.measurement_id === measurementId,
  ) || null
}

export function blockedDeerStudyMeasurements() {
  const rows: Array<{ id: string; alignment: DeerMeasurementAlignment }> = []
  for (const relationship of FARM_WATCH_DEER_RELATIONSHIPS) {
    for (const measurement of relationship.study_measurements) {
      if (
        measurement.activation_requirement === 'required' &&
        (measurement.alignment === 'mechanism_context_only' || measurement.alignment === 'unsupported') &&
        !rows.some((row) => row.id === measurement.id)
      ) {
        rows.push({ id: measurement.id, alignment: measurement.alignment })
      }
    }
  }
  return rows.sort((a, b) => a.id.localeCompare(b.id))
}

export function validateDeerMeasurementResolutionDecisions() {
  const blocked = blockedDeerStudyMeasurements()
  const blockedIds = new Set(blocked.map((row) => row.id))
  const seen = new Set<string>()

  for (const decision of FARM_WATCH_DEER_MEASUREMENT_RESOLUTION_DECISIONS) {
    if (!blockedIds.has(decision.measurement_id)) return false
    if (seen.has(decision.measurement_id)) return false
    seen.add(decision.measurement_id)
    if (!FARM_WATCH_DEER_MEASUREMENT_RESOLUTION_PRODUCT.dispositions.includes(decision.disposition)) return false
    if (!FARM_WATCH_DEER_MEASUREMENT_RESOLUTION_PRODUCT.operationalPostures.includes(decision.operational_posture)) return false
    if (!decision.operational_note.trim()) return false
    if (decision.disposition !== 'remain_unavailable' && !decision.target_product) return false
    if (!decision.rationale.trim() || !decision.implementation_boundary.trim()) return false
  }

  return blocked.every((measurement) => seen.has(measurement.id))
}
