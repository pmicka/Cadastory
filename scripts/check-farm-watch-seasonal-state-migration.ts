const path = new URL(
  '../supabase/migrations/20260921120000_add_farm_watch_seasonal_state_v1.sql',
  import.meta.url,
)
const sql = await Deno.readTextFile(path)

const required = [
  'farm_watch.property_seasonal_state_v1',
  'farm_watch.farm_watch_resolve_seasonal_state_v1_internal',
  'farm_watch.farm_watch_refresh_seasonal_state_v1_internal',
  'farm_watch.farm_watch_get_seasonal_state_v1_internal',
  'farm-watch-seasonal-state-resolver-v1',
  'farm-watch-seasonal-state-v1',
  "'known','proxy','stale','unavailable'",
  "'scoring_performed',false",
  "'behavioral_inference_performed',false",
  'grant execute on function public.farm_watch_get_seasonal_state_v1_internal(text,date)',
  'to service_role',
]
for (const needle of required) {
  if (!sql.includes(needle)) throw new Error('seasonal-state migration missing: ' + needle)
}

for (const forbidden of [
  'grant execute on function public.farm_watch_get_seasonal_state_v1_internal(text,date) to authenticated',
  'grant execute on function public.farm_watch_get_seasonal_state_v1_internal(text,date) to anon',
  'deer_score',
  'habitat_score',
  'bedding_score',
  'stand_score',
]) {
  if (sql.includes(forbidden)) throw new Error('seasonal-state migration contains forbidden contract: ' + forbidden)
}

console.log('Farm Watch seasonal-state migration invariants passed')
