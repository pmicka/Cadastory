-- Keep household-owner fallback classification current as new parcel-owner evidence arrives.
-- This does not schedule web research. It only records resolver-specific deferrals while
-- leaving the global buyer-resolution queue available for better organization evidence.

create or replace function research.refresh_household_owner_fallback_deferrals_v1()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_upserted integer:=0;
  v_resolved integer:=0;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service_role required';
  end if;

  -- Close deferrals when the candidate no longer needs this fallback or another
  -- strong organization responsibility path has appeared.
  update research.household_owner_fallback_deferrals d
  set resolved_at=now(),updated_at=now(),
      details=coalesce(d.details,'{}'::jsonb)||jsonb_build_object('resolved_by','stronger_or_no_longer_required')
  where d.resolved_at is null
    and (
      not exists(
        select 1
        from scout.opportunity_responsible_party_evidence e
        join scout.buyer_resolution_queue q using(candidate_key)
        where e.candidate_key=d.candidate_key
          and e.party_role='property_owner'
          and e.party_kind='person_or_household'
          and e.confidence>=.95
          and q.state in ('pending','researching')
          and q.missing_steps @> array['organization_resolution']::text[]
      )
      or exists(
        select 1
        from scout.opportunity_responsible_party_evidence x
        where x.candidate_key=d.candidate_key
          and x.party_kind='organization'
          and x.party_role in ('property_manager','operator','permit_contractor','project_owner')
          and x.evidence_class in ('authoritative_record','documented','corroborated')
          and x.confidence>=.95
      )
    );
  get diagnostics v_resolved=row_count;

  with owner_ranked as (
    select e.candidate_key,
           row_number() over(partition by e.candidate_key order by e.confidence desc,e.updated_at desc,e.id) rn
    from scout.opportunity_responsible_party_evidence e
    where e.party_role='property_owner'
      and e.party_kind='person_or_household'
      and e.confidence>=.95
  ), eligible as (
    select q.candidate_key,q.source_kind,q.address_hint,
           case when q.source_kind='construction_window' then p.project_type else null end project_type
    from owner_ranked e
    join scout.buyer_resolution_queue q using(candidate_key)
    join scout.opportunity_search_spine s using(candidate_key)
    left join intelligence.construction_service_windows w
      on q.source_kind='construction_window'
     and split_part(q.candidate_key,':',2) ~ '^[0-9a-fA-F-]{36}$'
     and w.id=split_part(q.candidate_key,':',2)::uuid
    left join intelligence.construction_projects p on p.id=w.project_id
    where e.rn=1
      and q.state in ('pending','researching')
      and q.missing_steps @> array['organization_resolution']::text[]
      and nullif(btrim(q.buyer_hint),'') is null
      and coalesce(s.global_suppressed,false)=false
      and q.source_kind in ('construction_window','exterior_cleaning','roof_lifecycle')
      and not exists(
        select 1
        from scout.opportunity_responsible_party_evidence x
        where x.candidate_key=q.candidate_key
          and x.party_kind='organization'
          and x.party_role in ('property_manager','operator','permit_contractor','project_owner')
          and x.evidence_class in ('authoritative_record','documented','corroborated')
          and x.confidence>=.95
      )
  )
  insert into research.household_owner_fallback_deferrals(
    candidate_key,reason,source_kind,site_address_text,requery_after,details,resolved_at,updated_at
  )
  select
    candidate_key,
    case
      when source_kind='construction_window' and project_type ilike 'Residential %'
        then 'residential_household_no_business_target'
      else 'no_documented_site_organization'
    end,
    source_kind,
    address_hint,
    now()+interval '90 days',
    jsonb_strip_nulls(jsonb_build_object(
      'project_type',project_type,
      'resolution_scope','household_owner_fallback',
      'owner_identity_not_researched',true,
      'global_buyer_queue_not_blocked',true,
      'recurring_web_search_enabled',false,
      'strict_first_party_web_experiment_yield','zero_after_full_first_pass',
      'outbound_contact_performed',false
    )),
    null,
    now()
  from eligible
  on conflict(candidate_key) do update set
    reason=excluded.reason,
    source_kind=excluded.source_kind,
    site_address_text=excluded.site_address_text,
    requery_after=case
      when research.household_owner_fallback_deferrals.reason is distinct from excluded.reason
        or research.household_owner_fallback_deferrals.resolved_at is not null
      then excluded.requery_after
      else coalesce(research.household_owner_fallback_deferrals.requery_after,excluded.requery_after)
    end,
    details=research.household_owner_fallback_deferrals.details||excluded.details,
    resolved_at=null,
    updated_at=now();
  get diagnostics v_upserted=row_count;

  return jsonb_build_object(
    'deferrals_upserted',v_upserted,
    'deferrals_resolved',v_resolved,
    'active_household_deferrals',(
      select count(*) from research.household_owner_fallback_deferrals where resolved_at is null
    )
  );
end
$$;

revoke all on function research.refresh_household_owner_fallback_deferrals_v1()
  from public,anon,authenticated;
grant execute on function research.refresh_household_owner_fallback_deferrals_v1() to service_role;

create or replace function scout.restore_responsible_party_buyer_candidates_cron_v1()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_restore jsonb;
  v_household jsonb;
begin
  if current_user <> 'postgres' and session_user <> 'postgres' then
    raise exception 'postgres scheduler only';
  end if;
  perform set_config('request.jwt.claim.role','service_role',true);
  v_restore:=scout.restore_responsible_party_buyer_candidates_v1(null);
  v_household:=research.refresh_household_owner_fallback_deferrals_v1();
  return jsonb_build_object('responsible_party_restore',v_restore,'household_fallback',v_household);
end
$$;

-- This maintenance path must not schedule the low-yield web collector.
do $$
declare v_bad integer;
begin
  select count(*) into v_bad
  from cron.job
  where active and command ilike '%collect-household-site-organization-evidence%';
  if v_bad<>0 then
    raise exception 'household site web collector must remain unscheduled';
  end if;
end
$$;