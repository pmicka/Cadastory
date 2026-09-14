-- Source-control the bounded Warren County Water District portfolio projection that
-- previously existed only in the live database. Keep response-generation time
-- separate from source evidence freshness so the sandbox cannot imply that 2023
-- WRIS asset records were freshly observed in 2026.

create or replace function public.scout_get_component_sandbox_water_portfolio_v1_internal()
returns jsonb
language sql
stable
security definer
set search_path = 'pg_catalog'
as $function$
with org as (
  select o.id, o.canonical_name
  from core.organizations o
  where o.status = 'active'
    and o.organization_type = 'water_utility'
    and o.canonical_name = 'Warren County Water District'
    and o.attributes->>'source' = 'ky-kia-water-tanks'
    and o.attributes->>'asset_resolution' = 'wris_operating_system_v1'
    and o.attributes->'pwsids' = '["KY1140487"]'::jsonb
), roster as (
  select
    o.id as organization_id,
    o.canonical_name,
    r.source_native_id,
    r.location,
    r.within_pilot_radius,
    r.raw_payload#>>'{attributes,WRIS_FID}' as wris_fid,
    r.raw_payload#>>'{attributes,PWSID}' as pwsid,
    r.raw_payload#>>'{attributes,MODIFYDATE}' as modify_epoch_ms
  from org o
  join ingest.sources s on s.slug = 'ky-kia-water-tanks'
  join ingest.raw_records r on r.source_id = s.id
  where r.raw_payload#>>'{attributes,PWSID}' = 'KY1140487'
), bounded as (
  select *
  from roster
  order by source_native_id, wris_fid
  limit 100
)
select jsonb_build_object(
  'contract_version', 'water_utility_portfolio_map_v1',
  'account_name', min(b.canonical_name),
  'organization_id', min(b.organization_id::text),
  'pwsid', 'KY1140487',
  'scope', 'documented_roster',
  'source_slug', 'ky-kia-water-tanks',
  'relationship', 'system_membership',
  'generated_at', statement_timestamp(),
  'source_modified_at', max(to_timestamp(b.modify_epoch_ms::double precision / 1000)),
  'members', jsonb_agg(
    jsonb_build_object(
      'id', b.wris_fid,
      'pwsid', b.pwsid,
      'name', b.source_native_id,
      'point', case
        when b.location is null then jsonb_build_object('type', 'unresolved')
        else extensions.st_asgeojson(b.location::extensions.geometry)::jsonb
      end,
      'service_state', case
        when b.source_native_id ilike '%NOT IN SERVICE%' then 'documented_not_in_service'
        else 'unverified'
      end,
      'within_pilot_radius', b.within_pilot_radius,
      'source_modified_at', to_timestamp(b.modify_epoch_ms::double precision / 1000),
      'signals', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'id', s.candidate_key,
            'kind', 'historical_rehab_record',
            'observed_at', s.observed_at
          ) order by s.observed_at desc, s.candidate_key
        )
        from (
          select v.candidate_key, v.observed_at
          from scout.v_water_tank_opportunity_candidates v
          where v.organization_id = b.organization_id
            and v.subject_key = b.wris_fid
            and v.details->>'latest_project_status' = 'REHAB'
          order by v.observed_at desc, v.candidate_key
          limit 10
        ) s
      ), '[]'::jsonb)
    ) order by b.source_native_id, b.wris_fid
  )
)
from bounded b
having count(*) between 1 and 100;
$function$;

comment on function public.scout_get_component_sandbox_water_portfolio_v1_internal() is
  'Owner sandbox-only Warren County Water District documented tank roster. generated_at is response time; source_modified_at is evidence freshness. Historical rehab evidence is not current need.';

revoke all on function public.scout_get_component_sandbox_water_portfolio_v1_internal() from public;
revoke all on function public.scout_get_component_sandbox_water_portfolio_v1_internal() from anon;
revoke all on function public.scout_get_component_sandbox_water_portfolio_v1_internal() from authenticated;
grant execute on function public.scout_get_component_sandbox_water_portfolio_v1_internal() to service_role;
