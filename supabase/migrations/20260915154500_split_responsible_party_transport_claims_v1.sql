-- Split responsible-party claims by acquisition transport.
--
-- Jefferson/PVA HTML continues through the authenticated Supabase Edge worker.
-- Public ArcGIS point-owner providers are claimed only by the unattended
-- GitHub-runner enrichment worker because Schneider resets Supabase Edge egress.
-- Evidence/completion semantics remain shared and unchanged.

create or replace function public.internal_claim_local_responsible_party_resolution_jobs_v1(p_limit integer default 8)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_result jsonb;
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_limit < 1 or p_limit > 20 then raise exception 'p_limit must be between 1 and 20'; end if;

  update research.responsible_party_resolution_jobs j
  set state='queued',claimed_at=null,lease_until=null,
      last_error=concat_ws(E'\n',nullif(j.last_error,''),'claim lease expired'),updated_at=now()
  where j.state='claimed' and j.lease_until<now()
    and exists (
      select 1 from research.responsible_party_source_profiles p
      where p.profile_key=j.profile_key and p.active and p.provider_kind='pva_lrsn_html'
    );

  update research.responsible_party_resolution_jobs j
  set state='exhausted',completed_at=coalesce(j.completed_at,now()),
      exhaustion_reason=coalesce(j.exhaustion_reason,'retry_budget_exhausted'),
      requery_after=coalesce(j.requery_after,now()+interval '90 days'),updated_at=now()
  where j.state in ('queued','failed') and j.attempt_count>=j.max_attempts
    and exists (
      select 1 from research.responsible_party_source_profiles p
      where p.profile_key=j.profile_key and p.provider_kind='pva_lrsn_html'
    );

  with picked as (
    select j.id
    from research.responsible_party_resolution_jobs j
    join research.responsible_party_source_profiles p on p.profile_key=j.profile_key
    where p.active and p.provider_kind='pva_lrsn_html'
      and j.state in ('queued','failed')
      and j.attempt_count<j.max_attempts
      and j.next_attempt_at<=now()
    order by j.priority desc,j.next_attempt_at,j.created_at
    for update of j skip locked
    limit p_limit
  ), claimed as (
    update research.responsible_party_resolution_jobs j
    set state='claimed',attempt_count=j.attempt_count+1,claimed_at=now(),
        lease_until=now()+interval '30 minutes',last_error=null,updated_at=now()
    from picked where j.id=picked.id returning j.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',c.id,'profile_key',c.profile_key,'lookup_key',c.lookup_key,
    'parcel_source_record_id',c.parcel_source_record_id,
    'parcel_source_native_id',c.parcel_source_native_id,'parcel_id',c.parcel_id,
    'priority',c.priority,'attempt_count',c.attempt_count,'max_attempts',c.max_attempts,
    'provider_kind',p.provider_kind,'owner_lookup_url_template',p.owner_lookup_url_template,
    'source_authority',p.source_authority,'source_url',p.source_url,
    'profile_attributes',p.attributes,
    'candidate_keys',(select coalesce(jsonb_agg(l.candidate_key order by l.candidate_key),'[]'::jsonb)
      from research.responsible_party_resolution_job_candidates l where l.job_id=c.id)
  ) order by c.priority desc,c.created_at),'[]'::jsonb)
  into v_result
  from claimed c
  join research.responsible_party_source_profiles p on p.profile_key=c.profile_key;

  return v_result;
end
$$;

revoke all on function public.internal_claim_local_responsible_party_resolution_jobs_v1(integer)
  from public,anon,authenticated;
grant execute on function public.internal_claim_local_responsible_party_resolution_jobs_v1(integer)
  to service_role;

create or replace function public.internal_claim_remote_responsible_party_resolution_jobs_v1(p_limit integer default 8)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_result jsonb;
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_limit < 1 or p_limit > 20 then raise exception 'p_limit must be between 1 and 20'; end if;

  update research.responsible_party_resolution_jobs j
  set state='queued',claimed_at=null,lease_until=null,
      last_error=concat_ws(E'\n',nullif(j.last_error,''),'claim lease expired'),updated_at=now()
  where j.state='claimed' and j.lease_until<now()
    and exists (
      select 1 from research.responsible_party_source_profiles p
      where p.profile_key=j.profile_key and p.active and p.provider_kind='arcgis_point_owner'
    );

  update research.responsible_party_resolution_jobs j
  set state='exhausted',completed_at=coalesce(j.completed_at,now()),
      exhaustion_reason=coalesce(j.exhaustion_reason,'retry_budget_exhausted'),
      requery_after=coalesce(j.requery_after,now()+interval '90 days'),updated_at=now()
  where j.state in ('queued','failed') and j.attempt_count>=j.max_attempts
    and exists (
      select 1 from research.responsible_party_source_profiles p
      where p.profile_key=j.profile_key and p.provider_kind='arcgis_point_owner'
    );

  with picked as (
    select j.id
    from research.responsible_party_resolution_jobs j
    join research.responsible_party_source_profiles p on p.profile_key=j.profile_key
    where p.active and p.provider_kind='arcgis_point_owner'
      and j.state in ('queued','failed')
      and j.attempt_count<j.max_attempts
      and j.next_attempt_at<=now()
    order by j.priority desc,j.next_attempt_at,j.created_at
    for update of j skip locked
    limit p_limit
  ), claimed as (
    update research.responsible_party_resolution_jobs j
    set state='claimed',attempt_count=j.attempt_count+1,claimed_at=now(),
        lease_until=now()+interval '30 minutes',last_error=null,updated_at=now()
    from picked where j.id=picked.id returning j.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',c.id,'profile_key',c.profile_key,'lookup_key',c.lookup_key,
    'priority',c.priority,'attempt_count',c.attempt_count,'max_attempts',c.max_attempts,
    'provider_kind',p.provider_kind,'owner_lookup_url_template',p.owner_lookup_url_template,
    'source_authority',p.source_authority,'source_url',p.source_url,
    'profile_attributes',p.attributes,
    'lookup_latitude',(select extensions.st_y(s.location::extensions.geometry)
      from research.responsible_party_resolution_job_candidates l
      join scout.opportunity_search_spine s on s.candidate_key=l.candidate_key
      where l.job_id=c.id and s.location is not null order by l.candidate_key limit 1),
    'lookup_longitude',(select extensions.st_x(s.location::extensions.geometry)
      from research.responsible_party_resolution_job_candidates l
      join scout.opportunity_search_spine s on s.candidate_key=l.candidate_key
      where l.job_id=c.id and s.location is not null order by l.candidate_key limit 1),
    'lookup_address',(select l.address_hint
      from research.responsible_party_resolution_job_candidates l
      where l.job_id=c.id order by l.candidate_key limit 1),
    'candidate_keys',(select coalesce(jsonb_agg(l.candidate_key order by l.candidate_key),'[]'::jsonb)
      from research.responsible_party_resolution_job_candidates l where l.job_id=c.id)
  ) order by c.priority desc,c.created_at),'[]'::jsonb)
  into v_result
  from claimed c
  join research.responsible_party_source_profiles p on p.profile_key=c.profile_key;

  return v_result;
end
$$;

revoke all on function public.internal_claim_remote_responsible_party_resolution_jobs_v1(integer)
  from public,anon,authenticated;
grant execute on function public.internal_claim_remote_responsible_party_resolution_jobs_v1(integer)
  to service_role;

-- Release guards: each lane must explicitly bind to one provider kind and active profiles.
do $$
declare v_local text; v_remote text;
begin
  select pg_get_functiondef('public.internal_claim_local_responsible_party_resolution_jobs_v1(integer)'::regprocedure)
    into v_local;
  select pg_get_functiondef('public.internal_claim_remote_responsible_party_resolution_jobs_v1(integer)'::regprocedure)
    into v_remote;

  if v_local not like '%p.active and p.provider_kind=''pva_lrsn_html''%'
     or v_local like '%p.provider_kind=''arcgis_point_owner''%' then
    raise exception 'local responsible-party claim lane regression';
  end if;
  if v_remote not like '%p.active and p.provider_kind=''arcgis_point_owner''%'
     or v_remote like '%p.provider_kind=''pva_lrsn_html''%' then
    raise exception 'remote responsible-party claim lane regression';
  end if;
end
$$;
