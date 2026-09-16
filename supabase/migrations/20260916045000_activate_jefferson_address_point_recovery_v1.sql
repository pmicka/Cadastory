-- Phase 4 release activation: add the proven Jefferson address-point recovery
-- lane to the existing responsible-party cadence. No new cron is introduced.
--
-- The recovery provider remains property-owner evidence only. Household owners
-- remain evidence-only; property ownership does not imply management, operation,
-- buyer identity, procurement authority, or outbound contact permission.

update research.responsible_party_source_profiles
set attributes=jsonb_set(
      coalesce(attributes,'{}'::jsonb),
      '{automated_dispatch}',
      'true'::jsonb,
      true
    ),
    updated_at=now()
where profile_key='ky_jefferson_pva_address_lrsn'
  and active
  and provider_kind='pva_lrsn_html'
  and attributes->>'resolution_mode'='address_point_lrsn_recovery';

create or replace function research.seed_responsible_party_resolution_jobs_cron_v1(
  p_limit integer default 500
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_local jsonb;
  v_remote jsonb;
  v_recovery jsonb;
begin
  if current_user <> 'postgres' and session_user <> 'postgres' then
    raise exception 'postgres scheduler only';
  end if;

  perform set_config('request.jwt.claim.role','service_role',true);

  v_local:=public.internal_seed_responsible_party_resolution_jobs_v1(p_limit);
  v_remote:=public.internal_seed_remote_responsible_party_resolution_jobs_v1(p_limit);
  v_recovery:=public.internal_seed_responsible_party_address_recovery_jobs_v1(least(p_limit,1000));

  return jsonb_build_object(
    'local',v_local,
    'remote',v_remote,
    'address_recovery',v_recovery
  );
end
$$;

revoke all on function research.seed_responsible_party_resolution_jobs_cron_v1(integer)
  from public,anon,authenticated;

-- Fail closed if the release activation did not land exactly on the intended
-- profile/dispatch contract. The normal local claim lane already filters on
-- automated_dispatch=true, so this is the only dispatch switch required.
do $$
declare
  v_profile_count integer;
  v_dispatch_enabled boolean;
  v_eligible_count integer;
begin
  select count(*),
         bool_and(coalesce((attributes->>'automated_dispatch')::boolean,false)),
         max(jsonb_array_length(coalesce(attributes->'eligible_source_kinds','[]'::jsonb)))
    into v_profile_count,v_dispatch_enabled,v_eligible_count
  from research.responsible_party_source_profiles
  where profile_key='ky_jefferson_pva_address_lrsn'
    and active
    and provider_kind='pva_lrsn_html'
    and attributes->>'resolution_mode'='address_point_lrsn_recovery';

  if v_profile_count<>1 or coalesce(v_dispatch_enabled,false)<>true then
    raise exception 'Jefferson address recovery profile not activated';
  end if;

  if coalesce(v_eligible_count,0)<>0 then
    raise exception 'Jefferson address recovery profile entered ordinary spatial seeding';
  end if;

  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.proname='internal_seed_responsible_party_address_recovery_jobs_v1'
  ) then
    raise exception 'Jefferson address recovery seeder missing';
  end if;
end
$$;