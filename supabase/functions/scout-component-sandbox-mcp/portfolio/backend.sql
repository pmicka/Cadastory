-- Deployment candidate only: not applied in this batch.
-- No public/anon/authenticated execute; existing owner-gated Edge Function only.
BEGIN;
CREATE OR REPLACE FUNCTION public.scout_get_component_sandbox_water_portfolio_v1_internal()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $portfolio$
WITH org AS (SELECT id,canonical_name,attributes FROM core.organizations WHERE status='active' AND organization_type='water_utility' AND canonical_name='Warren County Water District' AND attributes->>'source'='ky-kia-water-tanks' AND attributes->>'asset_resolution'='wris_operating_system_v1' AND attributes->'pwsids'='["KY1140487"]'::jsonb)
SELECT jsonb_build_object('contract_version','water_utility_portfolio_map_v1','account_name',o.canonical_name,'organization_id',o.id,'pwsid','KY1140487','scope','documented_roster','source_slug','ky-kia-water-tanks','relationship','system_membership','observed_on',current_date,'members',jsonb_agg(jsonb_build_object('id',r.raw_payload#>>'{attributes,WRIS_FID}','pwsid',r.raw_payload#>>'{attributes,PWSID}','name',r.source_native_id,'point',CASE WHEN r.location IS NULL THEN jsonb_build_object('type','unresolved') ELSE extensions.ST_AsGeoJSON(r.location::extensions.geometry)::jsonb END,'service_state',CASE WHEN r.source_native_id ILIKE '%NOT IN SERVICE%' THEN 'documented_not_in_service' ELSE 'unverified' END,'within_pilot_radius',r.within_pilot_radius,'source_modified_at',to_timestamp((r.raw_payload#>>'{attributes,MODIFYDATE}')::double precision/1000),'signals',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',v.candidate_key,'kind','historical_rehab_record','observed_at',v.observed_at)) FROM scout.v_water_tank_opportunity_candidates v WHERE v.organization_id=o.id AND v.subject_key=r.raw_payload#>>'{attributes,WRIS_FID}' AND v.details->>'latest_project_status'='REHAB'),'[]'::jsonb)) ORDER BY r.source_native_id)) AS portfolio
FROM org o JOIN ingest.raw_records r ON r.raw_payload#>>'{attributes,PWSID}' IN (SELECT jsonb_array_elements_text(o.attributes->'pwsids')) JOIN ingest.sources s ON s.id=r.source_id AND s.slug='ky-kia-water-tanks' GROUP BY o.id,o.canonical_name;
$portfolio$;
REVOKE ALL ON FUNCTION public.scout_get_component_sandbox_water_portfolio_v1_internal() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.scout_get_component_sandbox_water_portfolio_v1_internal() TO service_role;
COMMIT;
