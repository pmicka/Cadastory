const path = new URL(
  '../supabase/migrations/20260921233000_add_farm_watch_diel_biological_state_v1.sql',
  import.meta.url,
)
const sql = await Deno.readTextFile(path)

const required = [
  'farm_watch.property_diel_photoperiod_context_v1',
  'farm_watch.deer_regional_breeding_evidence_v1',
  'farm_watch.farm_watch_solar_position_v1',
  'farm_watch.farm_watch_solar_events_v1',
  'farm_watch.farm_watch_resolve_diel_photoperiod_v1_internal',
  'farm_watch.farm_watch_refresh_diel_photoperiod_v1_internal',
  'farm_watch.farm_watch_get_diel_photoperiod_v1_internal',
  'farm_watch.farm_watch_resolve_diel_state_v1_internal',
  'farm_watch.farm_watch_resolve_deer_biological_state_v1_internal',
  'farm-watch-diel-photoperiod-v1',
  'diel-photoperiod-context-v1',
  'farm-watch-deer-biological-state-v1',
  'deer-biological-state-v1',
  "'individual_state_inferred',false",
  "'coefficient_transfer_authorized',false",
  "'scoring_performed',false",
  "'behavioral_inference_performed',false",
  "'kdfwr-deer-peak-breeding-reference'",
  "'uky-white-tailed-deer-biology-kentucky'",
  "jsonb_build_array('FW-D21')",
  "v_evidence_found := found",
  "grant execute on function public.farm_watch_resolve_deer_biological_state_v1_internal",
  "to service_role",
]
for (const needle of required) {
  if (!sql.includes(needle)) {
    throw new Error('diel/biological-state migration missing: ' + needle)
  }
}

for (const forbidden of [
  "array_append(v_ids,'FW-D23')",
  "'kdfwr-deer-fetal-breeding-phenology'",
  "grant execute on function public.farm_watch_resolve_deer_biological_state_v1_internal(text,timestamptz,text,text,text,text) to authenticated",
  "grant execute on function public.farm_watch_resolve_deer_biological_state_v1_internal(text,timestamptz,text,text,text,text) to anon",
  'deer_score',
  'habitat_score',
  'rut_score',
  'movement_score',
  'bedding_score',
  'stand_score',
]) {
  if (sql.includes(forbidden)) {
    throw new Error('diel/biological-state migration contains forbidden contract: ' + forbidden)
  }
}

if (!sql.includes("'FW-D06'") || !sql.includes("'FW-D22'")) {
  throw new Error('diel/biological-state migration must retain age/state relationship gates')
}

console.log('Farm Watch diel/biological-state migration invariants passed')


function count(needle: string) {
  return sql.split(needle).length - 1
}

for (const [needle, expected] of [
  ['begin;', 1],
  ['commit;', 1],
  ['create table if not exists farm_watch.property_diel_photoperiod_context_v1', 1],
  ['create table if not exists farm_watch.deer_regional_breeding_evidence_v1', 1],
  ['create or replace function farm_watch.farm_watch_diel_photoperiod_contract_v1()', 1],
  ['create or replace function farm_watch.farm_watch_resolve_deer_biological_state_v1_internal(', 1],
  ["'kdfwr-deer-peak-breeding-reference'", 2],
  ["'kdfwr-deer-fetal-breeding-phenology'", 0],
  ["array_append(v_ids,'FW-D23')", 0],
]) {
  const actual = count(needle)
  if (actual !== expected) {
    throw new Error(
      'diel/biological-state migration count mismatch for ' +
      needle + ': expected ' + expected + ', got ' + actual,
    )
  }
}
