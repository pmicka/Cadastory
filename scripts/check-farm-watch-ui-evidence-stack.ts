const migration = [
  await Deno.readTextFile('supabase/migrations/20260923012000_add_farm_watch_deer_evidence_stack_v1.sql'),
  await Deno.readTextFile('supabase/migrations/20260923223500_expose_study_vegetation_height_in_deer_evidence_stack_v1.sql'),
  await Deno.readTextFile('supabase/migrations/20260925161000_expose_deer_tier1_context_in_evidence_stack_v1.sql'),
  await Deno.readTextFile('supabase/migrations/20260926104500_restore_farm_watch_deer_evidence_stack_study_height_v1.sql'),
  await Deno.readTextFile('supabase/migrations/20260929201015_farm_watch_dependency_aware_materialization_freshness_v1.sql'),
  await Deno.readTextFile('supabase/migrations/20260929201051_farm_watch_dependency_aware_evidence_stack_freshness_v1.sql'),
  await Deno.readTextFile('supabase/migrations/20260930025013_farm_watch_fail_closed_reader_semantics_v1.sql'),
  await Deno.readTextFile('supabase/migrations/20260930030145_farm_watch_property_input_freshness_v1.sql'),
].join('\n')
const edge = await Deno.readTextFile('supabase/functions/farm-watch-private/index.ts')
const evaluator = await Deno.readTextFile(
  'supabase/functions/_shared/farm-watch-deer-science-evaluator.ts',
)

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message)
}

for (const product of [
  'lidar-physical-structure',
  'study-aligned-vegetation-height-context',
  'landscape-structure-context',
  'terrain-form-permeability',
  'spatial-edge-patch-context',
  'solar-exposure-context',
  'thermal-exposure-context',
  'horizontal-visibility-context',
  'mast-capacity',
]) assert(migration.includes("'" + product + "'"), 'missing evidence-stack product ' + product)

for (const required of [
  'deer-evidence-stack-v1',
  "to_regclass('farm_watch.property_surface_water_state_v1')",
  "'not_deployed'",
  "'not_materialized'",
  'Neutral Farm Watch evidence inventory for UI review',
  'dependency-aware-materialization-v1',
  'farm_watch_get_current_materialization_ref_v1_internal',
  'calendar_date_mismatch',
  'meteorological_forcing_identity_sha256',
  'authoritative_external_observation_required:',
  'farm_watch_assert_fail_closed_reader_semantics_v1',
  'farm_watch_assert_property_input_freshness_v1',
  'property_input_state',
  'property_boundary_changed',
  'property_stated_acres_changed',
]) assert(migration.includes(required), 'missing evidence-stack invariant: ' + required)

assert(
  migration.includes('revoke all on function farm_watch.farm_watch_get_deer_evidence_stack_v1_internal(text,date)') &&
  migration.includes('from public,anon,authenticated') &&
  migration.includes('grant execute on function farm_watch.farm_watch_get_deer_evidence_stack_v1_internal(text,date)') &&
  migration.includes('to service_role'),
  'private evidence-stack function grants are incorrect',
)

assert(
  migration.includes('revoke all on function public.farm_watch_get_deer_evidence_stack_v1_internal(text,date)') &&
  migration.includes('grant execute on function public.farm_watch_get_deer_evidence_stack_v1_internal(text,date)') &&
  !/grant execute on function public\.farm_watch_get_deer_evidence_stack_v1_internal[\s\S]{0,120}\b(anon|authenticated)\b/i.test(migration),
  'public wrapper must remain service-role only',
)

for (const rpc of [
  'farm_watch_get_managed_food_feature_context_v1_internal',
  'farm_watch_get_managed_water_source_context_v1_internal',
]) {
  assert(
    migration.includes(`create or replace function public.${rpc}(`) &&
    migration.includes(`revoke all on function public.${rpc}(text,date)`) &&
    migration.includes(`grant execute on function public.${rpc}(text,date)`) &&
    migration.includes('to service_role'),
    'private managed-context PostgREST wrapper is missing: ' + rpc,
  )
}


assert(
  migration.includes('farm_watch_get_deer_evidence_stack_at_v1_internal') &&
  migration.includes("when 'solar-exposure-context'") &&
  migration.includes("when 'thermal-exposure-context'") &&
  migration.includes("when 'horizontal-visibility-context'") &&
  migration.includes("when 'mast-capacity'") &&
  migration.includes("'contract_version_mismatch'") &&
  migration.includes("'meteorological_forcing_time_changed'"),
  'dependency-aware freshness coverage is incomplete',
)

for (const forbidden of [
  'deer_score',
  'habitat_score',
  'bedding_score',
  'movement_score',
  'water_preference_score',
]) assert(!migration.includes(forbidden), 'forbidden UI scoring semantic: ' + forbidden)

assert(
  edge.includes("admin.rpc('farm_watch_get_deer_evidence_stack_at_v1_internal'") &&
  edge.includes('p_as_of_at: asOfAt') &&
  edge.includes("admin.rpc('farm_watch_get_managed_food_feature_context_v1_internal'") &&
  edge.includes("admin.rpc('farm_watch_get_managed_water_source_context_v1_internal'") &&
  edge.includes('deer_evidence_stack: deerEvidenceStack'),
  'private edge response is not wired to the exact-time dependency-aware evidence stack',
)

for (const required of [
  'deer-science-readiness-v1',
  'FARM_WATCH_DEER_MEASUREMENT_RESOLUTION_DECISIONS',
  'deerRelationshipStudyFidelityStatus',
  'managed_food_feature_context',
  'managed_water_source_context',
  'field_calibration_remaining',
  'Science-contract readiness only',
]) assert(edge.includes(required), 'missing technical deer-readiness invariant: ' + required)

assert(
  edge.includes("status: 'unavailable'") &&
  edge.includes("surface_water_state: { status: 'unavailable' }"),
  'private edge evidence-stack fallback is incomplete',
)

for (const required of [
  'deer-science-context-v1',
  'farm-watch-deer-science-evaluator-v1',
  'evaluateDeerRelationship',
  'evaluateDeerScienceContext',
  'buildDeerEvaluatorEvidenceFromFarmWatch',
  'blocked_measurement_alignment',
  'value_constraint_not_satisfied',
  'biological_state_unknown',
  'coefficient_synthesis_performed: false',
  'behavioral_probability_inferred: false',
]) assert(evaluator.includes(required), 'missing deer evaluator invariant: ' + required)

for (const required of [
  'requestedDeerScenario',
  "'deer_sex'",
  "'deer_age_class'",
  "'deer_movement_state'",
  "'deer_reproductive_state'",
  "url.searchParams.get('at')",
  "admin.rpc('farm_watch_resolve_deer_biological_state_v1_internal'",
  "admin.rpc(\n      'farm_watch_resolve_road_focal_context_v1_internal'",
  'evaluateDeerScienceContext',
  'deer_science_context: deerScienceContext',
]) assert(edge.includes(required), 'private edge is missing deer evaluator binding: ' + required)

for (const forbidden of [
  'deer_score',
  'habitat_score',
  'bedding_score',
  'movement_score',
  'water_preference_score',
]) {
  assert(!evaluator.includes(forbidden), 'forbidden deer evaluator scoring semantic: ' + forbidden)
}

console.log('Farm Watch UI evidence-stack invariants passed')
