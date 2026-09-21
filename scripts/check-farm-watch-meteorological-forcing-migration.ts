const path = new URL(
  '../supabase/migrations/20260921193000_add_farm_watch_meteorological_forcing_v1.sql',
  import.meta.url,
)
const sql = await Deno.readTextFile(path)

const required = [
  'farm_watch.property_meteorological_forcing_v1',
  'farm_watch.farm_watch_meteorological_forcing_contract_v1',
  'farm_watch.farm_watch_get_meteorological_targets_v1_internal',
  'farm_watch.farm_watch_store_meteorological_forcing_v1_internal',
  'farm_watch.farm_watch_get_meteorological_forcing_v1_internal',
  'noaa-hrrr-nearest-grid-analysis-v1',
  'farm-watch-meteorological-forcing-v1',
  'modeled_environmental_proxy',
  'noaa-hrrr-conus-3km',
  "'analysis','forecast'",
  "'scoring_performed')::boolean,true) is not false",
  "'behavioral_inference_performed')::boolean,true) is not false",
  'grant execute on function public.farm_watch_get_meteorological_forcing_v1_internal(text,timestamptz,integer,text) to service_role',
]
for (const needle of required) {
  if (!sql.includes(needle)) throw new Error('meteorological-forcing migration missing: ' + needle)
}

for (const forbidden of [
  'grant execute on function public.farm_watch_get_meteorological_forcing_v1_internal(text,timestamptz,integer,text) to authenticated',
  'grant execute on function public.farm_watch_get_meteorological_forcing_v1_internal(text,timestamptz,integer,text) to anon',
  'grant execute on function public.farm_watch_store_meteorological_forcing_v1_internal(jsonb) to authenticated',
  'grant execute on function public.farm_watch_store_meteorological_forcing_v1_internal(jsonb) to anon',
  'deer_score',
  'habitat_score',
  'bedding_score',
  'stand_score',
]) {
  if (sql.includes(forbidden)) {
    throw new Error('meteorological-forcing migration contains forbidden contract: ' + forbidden)
  }
}

console.log('Farm Watch meteorological-forcing migration invariants passed')
