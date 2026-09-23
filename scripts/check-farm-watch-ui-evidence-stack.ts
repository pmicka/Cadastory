const migration = await Deno.readTextFile('supabase/migrations/20260923012000_add_farm_watch_deer_evidence_stack_v1.sql')
const edge = await Deno.readTextFile('supabase/functions/farm-watch-private/index.ts')

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message)
}

for (const product of [
  'lidar-physical-structure',
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

for (const forbidden of [
  'deer_score',
  'habitat_score',
  'bedding_score',
  'movement_score',
  'water_preference_score',
]) assert(!migration.includes(forbidden), 'forbidden UI scoring semantic: ' + forbidden)

assert(
  edge.includes("admin.rpc('farm_watch_get_deer_evidence_stack_v1_internal'") &&
  edge.includes('deer_evidence_stack: deerEvidenceStack'),
  'private edge response is not wired to the evidence stack',
)

assert(
  edge.includes("status: 'unavailable'") &&
  edge.includes("surface_water_state: { status: 'unavailable' }"),
  'private edge evidence-stack fallback is incomplete',
)

console.log('Farm Watch UI evidence-stack invariants passed')
