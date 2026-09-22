const path = new URL('../supabase/migrations/20260922005000_add_farm_watch_field_phenology_v1.sql', import.meta.url)
const sql = await Deno.readTextFile(path)

if ((sql.match(/\bbegin\s*;/gi) || []).length !== 1) throw new Error('migration must contain exactly one transaction begin')
if ((sql.match(/\bcommit\s*;/gi) || []).length !== 1) throw new Error('migration must contain exactly one transaction commit')

for (const needle of [
  'farm_watch.field_vegetation_observations_v1',
  'farm_watch.property_field_phenology_context_v1',
  'farm_watch.farm_watch_get_field_phenology_targets_v1_internal',
  'farm_watch.farm_watch_store_field_vegetation_observations_v1_internal',
  'farm_watch.farm_watch_resolve_field_phenology_v1_internal',
  'field-phenology-context-v1',
  'hls-field-vegetation-observation-v1',
  "'phenology_state','unknown'",
  "'scoring_performed',false",
  "'behavioral_inference_performed',false",
  'grant execute on function public.farm_watch_get_field_phenology_v1_internal(text,date)',
  'to service_role',
]) {
  if (!sql.includes(needle)) throw new Error('field-phenology migration missing: ' + needle)
}

for (const forbidden of [
  'to authenticated',
  'to anon',
  "'phenology_state','probable_harvest_transition'",
  'deer_score',
  'habitat_score',
  'attraction_score',
]) {
  if (sql.includes(forbidden)) throw new Error('field-phenology migration contains forbidden contract: ' + forbidden)
}

console.log('Farm Watch field-phenology migration invariants passed')
