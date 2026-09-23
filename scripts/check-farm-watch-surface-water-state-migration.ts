const migrationPath = 'supabase/migrations/20260923001000_add_farm_watch_surface_water_state_v1.sql'
const sql = await Deno.readTextFile(migrationPath)

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message)
}

for (const required of [
  'create table if not exists farm_watch.property_surface_water_state_v1',
  'create or replace function farm_watch.farm_watch_surface_water_state_contract_v1()',
  'create or replace function farm_watch.farm_watch_classify_mapped_water_persistence_v1',
  'create or replace function farm_watch.farm_watch_resolve_surface_water_state_v1_internal',
  'create or replace function farm_watch.farm_watch_refresh_surface_water_state_v1_internal',
  'create or replace function farm_watch.farm_watch_get_surface_water_state_v1_internal',
  'create or replace function public.farm_watch_refresh_surface_water_state_v1_internal',
  'create or replace function public.farm_watch_get_surface_water_state_v1_internal',
  "'surface_water_presence'",
  "'geometry_only'",
  "'qualitative_wetness_state','not_classified'",
  "'deer_water_preference_inferred',false",
  "'behavioral_inference_performed',false",
  "'scoring_performed',false",
]) assert(sql.includes(required), 'missing Batch 7 invariant: ' + required)

assert(
  sql.includes("check (status in ('available','partial','unavailable'))"),
  'surface-water snapshot status constraint is missing',
)
assert(
  sql.includes("check (boundary_sha256 ~ '^[0-9a-f]{64}$')") &&
  sql.includes("check (source_signature_sha256 ~ '^[0-9a-f]{64}$')") &&
  sql.includes("check (identity_sha256 ~ '^[0-9a-f]{64}$')"),
  'surface-water identity hash constraints are incomplete',
)
assert(
  sql.includes('alter table farm_watch.property_surface_water_state_v1 enable row level security'),
  'surface-water table RLS is not enabled',
)
assert(
  sql.includes('revoke all on farm_watch.property_surface_water_state_v1 from public, anon, authenticated'),
  'surface-water table end-user revocation is missing',
)
assert(
  !/grant\s+(select|insert|update|delete|all)[\s\S]{0,160}property_surface_water_state_v1[\s\S]{0,120}\b(anon|authenticated)\b/i.test(sql),
  'surface-water table must not grant end-user DML/read access',
)
for (const signature of [
  'farm_watch.farm_watch_resolve_surface_water_state_v1_internal(text,date)',
  'farm_watch.farm_watch_refresh_surface_water_state_v1_internal(text,date)',
  'farm_watch.farm_watch_get_surface_water_state_v1_internal(text,date)',
  'public.farm_watch_refresh_surface_water_state_v1_internal(text,date)',
  'public.farm_watch_get_surface_water_state_v1_internal(text,date)',
]) {
  assert(
    sql.includes('revoke all on function ' + signature) &&
    sql.includes('from public,anon,authenticated'),
    'end-user execute revocation missing for ' + signature,
  )
}
assert(
  sql.includes("and o.observation_kind=(v_contract->>'operator_observation_kind')"),
  'operator observations are not bounded to the surface-water observation kind',
)
assert(
  sql.includes('o.observed_at::date=p_as_of_date') &&
  sql.includes('p_as_of_date between o.observed_date_start and coalesce(o.observed_date_end,o.observed_date_start)'),
  'surface-water observations are not date-bounded',
)
assert(
  sql.includes("m.product_kind='terrain-analysis'") &&
  sql.includes("m.algorithm_version='phase3-dem-61x61-conditioned-flow-v2'") &&
  sql.includes("'water_presence_inferred',false"),
  'conditioned D8 dependency must remain current and geometry-only',
)
assert(
  sql.includes("farm_watch.farm_watch_resolve_seasonal_state_v1_internal(p_slug,p_as_of_date)"),
  'Batch 7 must reuse the central Seasonal State resolver',
)
assert(
  sql.includes("farm_watch.farm_watch_context_identity_v1(v_property_id,'hydrology')"),
  'Batch 7 must bind the identity-aware hydrology context',
)
assert(
  sql.includes("'mapped_persistent'") &&
  sql.includes("'mapped_seasonal'") &&
  sql.includes("'mapped_temporary'") &&
  sql.includes("'mapped_unknown_persistence'"),
  'mapped persistence vocabulary is incomplete',
)
assert(
  !sql.includes("'perennial'") && !sql.includes("'intermittent'"),
  'Batch 7 must not invent 3DHP perennial/intermittent persistence without source attributes',
)
assert(
  sql.includes("'farm-watch-surface-water-state-pilot-v1'") &&
  sql.includes("'10 14 * * *'"),
  'validation-property refresh schedule is missing',
)

console.log('Farm Watch Surface Water State v1 migration invariants passed')
