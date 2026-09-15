-- Advance responsible-party seeding through the backlog without repeatedly
-- selecting candidates that already have a job or that currently lack a unique
-- local parcel match.
--
-- Deferrals are resolver-specific. They MUST NOT delay the global buyer queue,
-- because another upstream strategy (manager/operator/permit-party evidence)
-- may still be able to resolve the same opportunity.

create table if not exists research.responsible_party_resolution_deferrals (
  candidate_key text not null,
  profile_key text not null references research.responsible_party_source_profiles(profile_key) on delete cascade,
  reason text not null,
  parcel_match_count integer,
  requery_after timestamptz not null,
  details jsonb not null default '{}'::jsonb,
  first_observed_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(candidate_key,profile_key),
  check (reason in ('no_local_parcel_match','ambiguous_local_parcel_match','missing_local_parcel_lookup_key')),
  check (parcel_match_count is null or parcel_match_count>=0)
);
create index if not exists responsible_party_resolution_deferrals_requery_idx
  on research.responsible_party_resolution_deferrals(requery_after);

revoke all on table research.responsible_party_resolution_deferrals from public,anon,authenticated;

create or replace function public.internal_seed_responsible_party_resolution_jobs_v1(p_limit integer default 500)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_jobs integer:=0;
  v_links integer:=0;
  v_eligible integer:=0;
  v_unique integer:=0;
  v_deferred integer:=0;
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_limit < 1 or p_limit > 2000 then raise exception 'p_limit must be between 1 and 2000'; end if;

  drop table if exists pg_temp.responsible_party_roll;
  create temporary table responsible_party_roll on commit drop as
  with eligible as (
    select q.candidate_key,q.source_kind,q.priority,q.address_hint,
           s.state_code,s.county_name,s.location::extensions.geometry location,
           p.profile_key,p.provider_kind,p.parcel_source_slug
    from scout.buyer_resolution_queue q
    join scout.opportunity_search_spine s using(candidate_key)
    join research.responsible_party_source_profiles p
      on p.active
     and p.state_code=s.state_code
     and p.county_name=s.county_name
     and p.provider_kind='pva_lrsn_html'
     and pg_catalog.jsonb_exists(
       coalesce(pg_catalog.jsonb_extract_path(p.attributes,'eligible_source_kinds'),'[]'::jsonb),
       q.source_kind
     )
    where q.state in ('pending','researching')
      and q.next_attempt_at<=now()
      and q.missing_steps @> array['organization_resolution']::text[]
      and nullif(btrim(q.buyer_hint),'') is null
      and s.location is not null
      and coalesce(s.global_suppressed,false)=false
      and not exists (
        select 1
        from research.responsible_party_resolution_deferrals d
        where d.candidate_key=q.candidate_key
          and d.profile_key=p.profile_key
          and d.requery_after>now()
      )
      and not exists (
        select 1
        from research.responsible_party_resolution_job_candidates l
        join research.responsible_party_resolution_jobs j on j.id=l.job_id
        where l.candidate_key=q.candidate_key
          and j.profile_key=p.profile_key
          and not (
            j.state='exhausted'
            and coalesce(j.requery_after,'infinity'::timestamptz)<=now()
          )
      )
    order by q.priority desc,q.candidate_key
    limit p_limit
  ), parcel_roll as (
    select e.*,
      count(distinct r.id) parcel_match_count,
      (array_agg(r.id::text order by r.id::text))[1]::uuid parcel_source_record_id,
      (array_agg(r.source_native_id order by r.source_native_id))[1] parcel_source_native_id,
      (array_agg(nullif(r.raw_payload#>>'{properties,LRSN}','') order by r.source_native_id)
        filter(where nullif(r.raw_payload#>>'{properties,LRSN}','') is not null))[1] lookup_key,
      (array_agg(nullif(r.raw_payload#>>'{properties,PARCELID}','') order by r.source_native_id)
        filter(where nullif(r.raw_payload#>>'{properties,PARCELID}','') is not null))[1] parcel_id
    from eligible e
    join ingest.sources src on src.slug=e.parcel_source_slug
    left join ingest.raw_records r
      on r.source_id=src.id
     and r.geometry is not null
     and r.geometry::extensions.geometry OPERATOR(extensions.&&) e.location
     and extensions.st_intersects(r.geometry::extensions.geometry,e.location)
    group by e.candidate_key,e.source_kind,e.priority,e.address_hint,e.state_code,e.county_name,
             e.location,e.profile_key,e.provider_kind,e.parcel_source_slug
  )
  select *,md5(concat_ws('|',profile_key,lookup_key,parcel_id,parcel_source_record_id::text)) input_fingerprint
  from parcel_roll;

  insert into research.responsible_party_resolution_deferrals(
    candidate_key,profile_key,reason,parcel_match_count,requery_after,details,updated_at
  )
  select candidate_key,profile_key,
    case
      when parcel_match_count=0 then 'no_local_parcel_match'
      when parcel_match_count>1 then 'ambiguous_local_parcel_match'
      else 'missing_local_parcel_lookup_key'
    end,
    parcel_match_count,
    now()+interval '30 days',
    jsonb_build_object(
      'source_kind',source_kind,
      'address_hint',address_hint,
      'parcel_source_slug',parcel_source_slug,
      'resolution_scope','local_parcel_owner'
    ),
    now()
  from responsible_party_roll
  where parcel_match_count<>1 or nullif(lookup_key,'') is null
  on conflict(candidate_key,profile_key) do update set
    reason=excluded.reason,
    parcel_match_count=excluded.parcel_match_count,
    requery_after=excluded.requery_after,
    details=excluded.details,
    updated_at=now();
  get diagnostics v_deferred=row_count;

  delete from research.responsible_party_resolution_deferrals d
  using responsible_party_roll r
  where d.candidate_key=r.candidate_key
    and d.profile_key=r.profile_key
    and r.parcel_match_count=1
    and nullif(r.lookup_key,'') is not null;

  select count(*) into v_eligible
  from scout.buyer_resolution_queue q
  join scout.opportunity_search_spine s using(candidate_key)
  join research.responsible_party_source_profiles p
    on p.active
   and p.state_code=s.state_code
   and p.county_name=s.county_name
   and p.provider_kind='pva_lrsn_html'
   and pg_catalog.jsonb_exists(
     coalesce(pg_catalog.jsonb_extract_path(p.attributes,'eligible_source_kinds'),'[]'::jsonb),
     q.source_kind
   )
  where q.state in ('pending','researching')
    and q.next_attempt_at<=now()
    and q.missing_steps @> array['organization_resolution']::text[]
    and nullif(btrim(q.buyer_hint),'') is null
    and s.location is not null
    and coalesce(s.global_suppressed,false)=false
    and not exists (
      select 1
      from research.responsible_party_resolution_deferrals d
      where d.candidate_key=q.candidate_key
        and d.profile_key=p.profile_key
        and d.requery_after>now()
    )
    and not exists (
      select 1
      from research.responsible_party_resolution_job_candidates l
      join research.responsible_party_resolution_jobs j on j.id=l.job_id
      where l.candidate_key=q.candidate_key
        and j.profile_key=p.profile_key
        and not (
          j.state='exhausted'
          and coalesce(j.requery_after,'infinity'::timestamptz)<=now()
        )
    );

  select count(*) into v_unique
  from responsible_party_roll
  where parcel_match_count=1 and nullif(lookup_key,'') is not null;

  insert into research.responsible_party_resolution_jobs(
    profile_key,lookup_key,parcel_source_record_id,parcel_source_native_id,parcel_id,
    priority,input_fingerprint,updated_at
  )
  select profile_key,lookup_key,
         (array_agg(parcel_source_record_id order by candidate_key))[1],
         (array_agg(parcel_source_native_id order by candidate_key))[1],
         (array_agg(parcel_id order by candidate_key))[1],
         max(priority),md5(string_agg(input_fingerprint,',' order by candidate_key)),now()
  from responsible_party_roll
  where parcel_match_count=1 and nullif(lookup_key,'') is not null
  group by profile_key,lookup_key
  on conflict(profile_key,lookup_key) do update set
    parcel_source_record_id=excluded.parcel_source_record_id,
    parcel_source_native_id=excluded.parcel_source_native_id,
    parcel_id=excluded.parcel_id,
    priority=greatest(research.responsible_party_resolution_jobs.priority,excluded.priority),
    state=case
      when research.responsible_party_resolution_jobs.input_fingerprint is distinct from excluded.input_fingerprint
       and research.responsible_party_resolution_jobs.state in ('failed','exhausted','needs_review') then 'queued'
      when research.responsible_party_resolution_jobs.state='exhausted'
       and research.responsible_party_resolution_jobs.requery_after<=now() then 'queued'
      else research.responsible_party_resolution_jobs.state
    end,
    attempt_count=case
      when research.responsible_party_resolution_jobs.input_fingerprint is distinct from excluded.input_fingerprint then 0
      else research.responsible_party_resolution_jobs.attempt_count
    end,
    input_fingerprint=excluded.input_fingerprint,
    updated_at=now();
  get diagnostics v_jobs=row_count;

  insert into research.responsible_party_resolution_job_candidates(
    job_id,candidate_key,source_kind,address_hint,updated_at
  )
  select j.id,r.candidate_key,r.source_kind,r.address_hint,now()
  from responsible_party_roll r
  join research.responsible_party_resolution_jobs j
    on j.profile_key=r.profile_key and j.lookup_key=r.lookup_key
  where r.parcel_match_count=1 and nullif(r.lookup_key,'') is not null
  on conflict(job_id,candidate_key) do update set
    source_kind=excluded.source_kind,
    address_hint=excluded.address_hint,
    updated_at=now();
  get diagnostics v_links=row_count;

  return jsonb_build_object(
    'eligible_candidates',v_eligible,
    'considered_candidates',(select count(*) from responsible_party_roll),
    'unique_parcel_candidates',v_unique,
    'deferred_candidates',v_deferred,
    'jobs_upserted',v_jobs,
    'candidate_links_upserted',v_links,
    'ready_jobs',(select count(*) from research.responsible_party_resolution_jobs
      where state in ('queued','failed') and attempt_count<max_attempts and next_attempt_at<=now())
  );
end
$$;

revoke all on function public.internal_seed_responsible_party_resolution_jobs_v1(integer) from public,anon,authenticated;
grant execute on function public.internal_seed_responsible_party_resolution_jobs_v1(integer) to service_role;

-- Remote ArcGIS jobs always create a job/link before network lookup, so they do
-- not need parcel-match deferrals. They still need the same seed cursor behavior
-- to avoid repeatedly upserting already-linked candidates as additional remote
-- providers are added.
do $$
declare
  v_def text;
  v_anchor text := '    and coalesce(s.global_suppressed,false)=false';
  v_matches integer;
  v_insert text := E'    and coalesce(s.global_suppressed,false)=false\n    and not exists (\n      select 1\n      from research.responsible_party_resolution_job_candidates l\n      join research.responsible_party_resolution_jobs j on j.id=l.job_id\n      where l.candidate_key=q.candidate_key\n        and j.profile_key=p.profile_key\n        and not (\n          j.state=''exhausted''\n          and coalesce(j.requery_after,''infinity''::timestamptz)<=now()\n        )\n    )';
begin
  select pg_get_functiondef('public.internal_seed_remote_responsible_party_resolution_jobs_v1(integer)'::regprocedure)
  into v_def;
  v_matches := (length(v_def)-length(replace(v_def,v_anchor,''))) / nullif(length(v_anchor),0);
  if v_matches <> 1 then
    raise exception 'expected one remote responsible-party seed cursor anchor, found %',v_matches;
  end if;
  v_def:=replace(v_def,v_anchor,v_insert);
  execute v_def;
end
$$;

do $$
declare v_local text; v_remote text;
begin
  select pg_get_functiondef('public.internal_seed_responsible_party_resolution_jobs_v1(integer)'::regprocedure) into v_local;
  select pg_get_functiondef('public.internal_seed_remote_responsible_party_resolution_jobs_v1(integer)'::regprocedure) into v_remote;

  if v_local not like '%responsible_party_resolution_deferrals%'
     or v_local not like '%p.provider_kind=''pva_lrsn_html''%'
     or v_remote not like '%responsible_party_resolution_job_candidates l%j.profile_key=p.profile_key%' then
    raise exception 'responsible-party seed advancement regression';
  end if;
end
$$;
