const migration = await Deno.readTextFile(
  'supabase/migrations/20260930025013_farm_watch_fail_closed_reader_semantics_v1.sql',
)
const manifestMigration = await Deno.readTextFile(
  'supabase/migrations/20260930002503_farm_watch_materialization_dependency_manifest_v1.sql',
)

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message)
}

for (const required of [
  'authoritative_external_observation_required:',
  'authoritative_external_observation_unavailable:',
  'authoritative_external_identity_invalid:',
  "coalesce(v_override->>'authoritative','false') <> 'true'",
  "'contract_only'",
  "v_kind <> 'external'",
  'authoritative_external_resolution_complete',
  'farm_watch_assert_fail_closed_reader_semantics_v1',
  'no-observation dependency manifest did not fail closed',
  'partial-observation dependency manifest did not fail closed',
  'legacy candidate returned available without authoritative observations',
]) {
  assert(migration.includes(required), 'missing fail-closed invariant: ' + required)
}

assert(
  migration.includes("p_current->>'reason'") &&
  migration.includes("p_dependency->>'unavailable_reason'"),
  'dependency mismatch reporting must preserve authoritative-observation failure reasons',
)

assert(
  migration.includes(
    "coalesce(v_current->>'status','unavailable') <> 'available'",
  ) &&
  migration.includes(
    "coalesce(v_current->>'authoritative','false') <> 'true'",
  ),
  'manifest must treat unavailable or non-authoritative external state as incomplete',
)

assert(
  !migration.includes(
    "'status','available',\n        'identity_sha256',v_external->>'contract_identity_sha256'",
  ),
  'external static contract identity may not manufacture current availability',
)

assert(
  migration.includes(
    'revoke all on function farm_watch.farm_watch_assert_fail_closed_reader_semantics_v1()',
  ) &&
  migration.includes('from public,anon,authenticated,service_role'),
  'fail-closed regression assertion must remain admin-only',
)

assert(
  manifestMigration.includes(
    "farm_watch_get_current_materialization_ref_with_overrides_v1_internal(\n    p_property_id,\n    p_product_kind,\n    p_as_of_date,\n    p_as_of_at,\n    '{}'::jsonb",
  ),
  'standard current-materialization wrapper no longer exercises the no-observation path',
)

for (const forbidden of [
  'deer_score',
  'habitat_score',
  'bedding_score',
  'movement_score',
]) {
  assert(!migration.includes(forbidden), 'forbidden scoring semantic: ' + forbidden)
}

console.log('Farm Watch fail-closed reader semantics invariants passed')
