const migration = await Deno.readTextFile(
  'supabase/migrations/20260930030145_farm_watch_property_input_freshness_v1.sql',
)
const manifestDoc = await Deno.readTextFile(
  'docs/FARM_WATCH_MATERIALIZATION_DEPENDENCY_MANIFEST_V1.md',
)

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message)
}

for (const required of [
  'farm_watch_property_input_state_v1_internal',
  'farm_watch_property_input_mismatches_v1',
  'farm_watch_assert_property_input_freshness_v1',
  "'property_input_state'",
  "'boundary_sha256'",
  "'stated_acres'",
  "'boundary_srid'",
  "'property_boundary_changed'",
  "'property_stated_acres_changed'",
  "'property_boundary_srid_changed'",
  "'recorded_property_input_binding_missing:boundary_sha256'",
  "'recorded_property_input_binding_missing:stated_acres'",
  "'recorded_property_input_binding_missing:boundary_srid'",
  'b.deterministic_inputs',
  "v_manifest->'property_input_state'",
]) {
  assert(migration.includes(required), 'missing property freshness invariant: ' + required)
}

assert(
  migration.includes(
    "v_payload := jsonb_build_object(\n    'product_kind',p_product_kind",
  ) &&
  migration.includes("'property_input_state',v_property_input_state") &&
  migration.includes("'dependencies',v_dependencies"),
  'property state must participate in the canonical manifest identity',
)

assert(
  migration.includes(
    'farm_watch.farm_watch_property_input_mismatches_v1(\n        v_row.boundary_sha256',
  ),
  'every candidate materialization must be checked against current property inputs',
)

assert(
  migration.includes(
    'revoke all on function\n  farm_watch.farm_watch_property_input_state_v1_internal(uuid)',
  ) &&
  migration.includes(
    'revoke all on function\n  farm_watch.farm_watch_property_input_mismatches_v1(text,jsonb,jsonb)',
  ) &&
  migration.includes(
    'revoke all on function\n  farm_watch.farm_watch_assert_property_input_freshness_v1()',
  ) &&
  migration.includes('from public,anon,authenticated,service_role'),
  'property freshness helpers/assertion must remain internal',
)

for (const required of [
  'P0.4 base-property input freshness',
  'boundary hash',
  'stated acreage',
  'boundary SRID',
  'property_boundary_changed',
  'property_stated_acres_changed',
]) {
  assert(manifestDoc.includes(required), 'property freshness documentation is incomplete: ' + required)
}

for (const forbidden of [
  'deer_score',
  'habitat_score',
  'bedding_score',
  'movement_score',
]) {
  assert(!migration.includes(forbidden), 'forbidden scoring semantic: ' + forbidden)
}

console.log('Farm Watch property input freshness invariants passed')
