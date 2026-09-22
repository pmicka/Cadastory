const path = new URL('../supabase/migrations/20260922031000_add_farm_watch_hls_field_materializer_v1.sql', import.meta.url)
const sql = await Deno.readTextFile(path)

if ((sql.match(/\bbegin\s*;/gi) || []).length !== 1) {
  throw new Error('HLS materializer migration must contain exactly one transaction begin')
}
if ((sql.match(/\bcommit\s*;/gi) || []).length !== 1) {
  throw new Error('HLS materializer migration must contain exactly one transaction commit')
}

for (const needle of [
  'farm_watch.property_field_vegetation_collection_runs_v1',
  'farm_watch.farm_watch_start_field_vegetation_collection_v1_internal',
  'farm_watch.farm_watch_finish_field_vegetation_collection_v1_internal',
  'farm_watch.farm_watch_get_latest_field_vegetation_collection_v1_internal',
  'microsoft-planetary-computer-hls-v2',
  "'catalog_incomplete'",
  "'download_error'",
  "'processing_error'",
  'grant execute on function public.farm_watch_start_field_vegetation_collection_v1_internal',
  'grant execute on function public.farm_watch_finish_field_vegetation_collection_v1_internal',
  'grant execute on function public.farm_watch_get_latest_field_vegetation_collection_v1_internal',
  'to service_role',
]) {
  if (!sql.includes(needle)) throw new Error('HLS materializer migration missing: ' + needle)
}

for (const forbidden of [
  ' to anon',
  ' to authenticated',
  'deer_score',
  'habitat_score',
  'attraction_score',
  'harvest_score',
]) {
  if (sql.toLowerCase().includes(forbidden.toLowerCase())) {
    throw new Error('HLS materializer migration contains forbidden contract: ' + forbidden)
  }
}

console.log('Farm Watch HLS field materializer migration invariants passed')
