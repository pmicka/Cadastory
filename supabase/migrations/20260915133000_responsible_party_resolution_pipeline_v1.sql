-- Upstream responsible-party resolution for address-only buyer opportunities.
-- Property owner != property manager != operator != buyer. Parcel ownership is
-- authoritative responsibility evidence only; purchasing authority is never implied.

create table if not exists research.responsible_party_source_profiles (
  profile_key text primary key,
  state_code text not null,
  county_name text not null,
  provider_kind text not null,
  parcel_source_slug text not null,
  owner_lookup_url_template text,
  source_authority text not null,
  source_url text not null,
  active boolean not null default true,
  priority integer not null default 100,
  attributes jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (provider_kind in ('pva_lrsn_html','embedded_parcel_owner'))
);

insert into research.responsible_party_source_profiles(
  profile_key,state_code,county_name,provider_kind,parcel_source_slug,
  owner_lookup_url_template,source_authority,source_url,active,priority,attributes
) values (
  'ky_jefferson_pva_lrsn','KY','Jefferson','pva_lrsn_html','jefferson-county-parcels',
  'https://jeffersonpva.ky.gov/property-search/property-details/?lrsn={lookup_key}',
  'Jefferson County Property Valuation Administrator',
  'https://jeffersonpva.ky.gov/property-search/',true,10,
  jsonb_build_object(
    'identity_scope','property_owner_only','lookup_key','LRSN',
    'free_detail_fields',jsonb_build_array('owner','parcel_id','assessed_value','acres','data_last_updated'),
    'buyer_authority_not_implied',true
  )
)
on conflict(profile_key) do update set
  state_code=excluded.state_code,county_name=excluded.county_name,
  provider_kind=excluded.provider_kind,parcel_source_slug=excluded.parcel_source_slug,
  owner_lookup_url_template=excluded.owner_lookup_url_template,
  source_authority=excluded.source_authority,source_url=excluded.source_url,
  active=excluded.active,priority=excluded.priority,attributes=excluded.attributes,updated_at=now();

create table if not exists research.responsible_party_resolution_jobs (
  id uuid primary key default gen_random_uuid(),
  profile_key text not null references research.responsible_party_source_profiles(profile_key),
  lookup_key text not null,
  parcel_source_record_id uuid,
  parcel_source_native_id text,
  parcel_id text,
  priority integer not null default 0,
  state text not null default 'queued',
  attempt_count integer not null default 0,
  max_attempts integer not null default 3,
  next_attempt_at timestamptz not null default now(),
  claimed_at timestamptz,
  lease_until timestamptz,
  completed_at timestamptz,
  input_fingerprint text,
  last_error text,
  exhaustion_reason text,
  requery_after timestamptz,
  outcome_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(profile_key,lookup_key),
  check (state in ('queued','claimed','completed','failed','needs_review','exhausted')),
  check (attempt_count >= 0 and max_attempts between 1 and 10)
);

create index if not exists responsible_party_resolution_jobs_claim_idx
  on research.responsible_party_resolution_jobs(state,next_attempt_at,priority desc,created_at)
  where state in ('queued','failed');

create table if not exists research.responsible_party_resolution_job_candidates (
  job_id uuid not null references research.responsible_party_resolution_jobs(id) on delete cascade,
  candidate_key text not null,
  source_kind text not null,
  address_hint text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(job_id,candidate_key)
);

create index if not exists responsible_party_resolution_candidate_idx
  on research.responsible_party_resolution_job_candidates(candidate_key);

create table if not exists scout.opportunity_responsible_party_evidence (
  id uuid primary key default gen_random_uuid(),
  candidate_key text not null,
  party_role text not null,
  party_name text not null,
  party_name_normalized text not null,
  party_kind text not null,
  organization_id uuid references core.organizations(id) on delete set null,
  site_address_text text,
  parcel_source_record_id uuid,
  parcel_source_native_id text,
  parcel_id text,
  evidence_class text not null,
  confidence numeric not null,
  source_url text not null,
  source_authority text not null,
  observed_on date,
  collected_at timestamptz not null default now(),
  attributes jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (party_role in ('property_owner','property_manager','operator','permit_contractor','project_owner','other')),
  check (party_kind in ('organization','person_or_household','unknown')),
  check (evidence_class in ('authoritative_record','documented','corroborated','signal_to_investigate')),
  check (confidence between 0 and 1)
);

create unique index if not exists opportunity_responsible_party_evidence_identity_uq
  on scout.opportunity_responsible_party_evidence(candidate_key,party_role,party_name_normalized,source_url);
create index if not exists opportunity_responsible_party_evidence_candidate_idx
  on scout.opportunity_responsible_party_evidence(candidate_key,party_role,confidence desc);

create or replace function scout.classify_responsible_party_name_v1(p_name text)
returns text language sql immutable set search_path='' as $$
  select case
    when nullif(btrim(p_name),'') is null then 'unknown'
    when lower(p_name) ~ '(^|[^a-z])(llc|pllc|lp|llp|inc|incorporated|corp|corporation|company|co|holdings|properties|property|realty|real estate|partners|partnership|group|services|service|construction|contracting|contractors|engineering|electric|electrical|mechanical|heating|cooling|hvac|solar|energy|power|coop|cooperative|builders|building|roofing|plumbing|bank|trust|church|ministry|temple|association|foundation|authority|district|school|university|college|city|county|government|commonwealth|municipal)([^a-z]|$)'
      then 'organization'
    else 'person_or_household'
  end
$$;

do $$ begin
  if scout.classify_responsible_party_name_v1('WOODBINE CONSTRUCTION CO') <> 'organization'
     or scout.classify_responsible_party_name_v1('LOUISVILLE RIVER PARK DRIVE 63 LLC') <> 'organization'
     or scout.classify_responsible_party_name_v1('HUNTER WILLIAM B & RHONDA K') <> 'person_or_household' then
    raise exception 'responsible-party classifier regression';
  end if;
end $$;

create or replace function public.internal_seed_responsible_party_resolution_jobs_v1(p_limit integer default 500)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_jobs integer:=0; v_links integer:=0; v_eligible integer:=0; v_unique integer:=0;
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_limit < 1 or p_limit > 2000 then raise exception 'p_limit must be between 1 and 2000'; end if;

  create temporary table responsible_party_seed on commit drop as
  with eligible as (
    select q.candidate_key,q.source_kind,q.priority,q.address_hint,
           s.state_code,s.county_name,s.location::geometry location,
           p.profile_key,p.provider_kind,p.parcel_source_slug
    from scout.buyer_resolution_queue q
    join scout.opportunity_search_spine s using(candidate_key)
    join research.responsible_party_source_profiles p
      on p.active and p.state_code=s.state_code and p.county_name=s.county_name
    where q.state in ('pending','researching')
      and q.next_attempt_at<=now()
      and q.missing_steps @> array['organization_resolution']::text[]
      and nullif(btrim(q.buyer_hint),'') is null
      and q.source_kind in ('construction_window','exterior_cleaning')
      and s.location is not null
      and coalesce(s.global_suppressed,false)=false
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
      on r.source_id=src.id and r.geometry is not null
     and r.geometry::geometry && e.location and st_intersects(r.geometry::geometry,e.location)
    group by e.candidate_key,e.source_kind,e.priority,e.address_hint,e.state_code,e.county_name,
             e.location,e.profile_key,e.provider_kind,e.parcel_source_slug
  )
  select *,md5(concat_ws('|',profile_key,lookup_key,parcel_id,parcel_source_record_id::text)) input_fingerprint
  from parcel_roll where parcel_match_count=1 and nullif(lookup_key,'') is not null;

  select count(*) into v_eligible
  from scout.buyer_resolution_queue q
  join scout.opportunity_search_spine s using(candidate_key)
  join research.responsible_party_source_profiles p
    on p.active and p.state_code=s.state_code and p.county_name=s.county_name
  where q.state in ('pending','researching') and q.next_attempt_at<=now()
    and q.missing_steps @> array['organization_resolution']::text[]
    and nullif(btrim(q.buyer_hint),'') is null
    and q.source_kind in ('construction_window','exterior_cleaning')
    and s.location is not null and coalesce(s.global_suppressed,false)=false;
  select count(*) into v_unique from responsible_party_seed;

  insert into research.responsible_party_resolution_jobs(
    profile_key,lookup_key,parcel_source_record_id,parcel_source_native_id,parcel_id,
    priority,input_fingerprint,updated_at
  )
  select profile_key,lookup_key,
         (array_agg(parcel_source_record_id order by candidate_key))[1],
         (array_agg(parcel_source_native_id order by candidate_key))[1],
         (array_agg(parcel_id order by candidate_key))[1],
         max(priority),md5(string_agg(input_fingerprint,',' order by candidate_key)),now()
  from responsible_party_seed group by profile_key,lookup_key
  on conflict(profile_key,lookup_key) do update set
    parcel_source_record_id=excluded.parcel_source_record_id,
    parcel_source_native_id=excluded.parcel_source_native_id,parcel_id=excluded.parcel_id,
    priority=greatest(research.responsible_party_resolution_jobs.priority,excluded.priority),
    state=case
      when research.responsible_party_resolution_jobs.input_fingerprint is distinct from excluded.input_fingerprint
       and research.responsible_party_resolution_jobs.state in ('failed','exhausted','needs_review') then 'queued'
      when research.responsible_party_resolution_jobs.state='exhausted'
       and research.responsible_party_resolution_jobs.requery_after<=now() then 'queued'
      else research.responsible_party_resolution_jobs.state end,
    attempt_count=case when research.responsible_party_resolution_jobs.input_fingerprint is distinct from excluded.input_fingerprint then 0 else research.responsible_party_resolution_jobs.attempt_count end,
    input_fingerprint=excluded.input_fingerprint,updated_at=now();
  get diagnostics v_jobs=row_count;

  insert into research.responsible_party_resolution_job_candidates(job_id,candidate_key,source_kind,address_hint,updated_at)
  select j.id,s.candidate_key,s.source_kind,s.address_hint,now()
  from responsible_party_seed s
  join research.responsible_party_resolution_jobs j on j.profile_key=s.profile_key and j.lookup_key=s.lookup_key
  on conflict(job_id,candidate_key) do update set source_kind=excluded.source_kind,address_hint=excluded.address_hint,updated_at=now();
  get diagnostics v_links=row_count;

  return jsonb_build_object('eligible_candidates',v_eligible,'unique_parcel_candidates',v_unique,
    'jobs_upserted',v_jobs,'candidate_links_upserted',v_links,
    'ready_jobs',(select count(*) from research.responsible_party_resolution_jobs
      where state in ('queued','failed') and attempt_count<max_attempts and next_attempt_at<=now()));
end $$;

revoke all on function public.internal_seed_responsible_party_resolution_jobs_v1(integer) from public,anon,authenticated;
grant execute on function public.internal_seed_responsible_party_resolution_jobs_v1(integer) to service_role;

create or replace function public.internal_claim_responsible_party_resolution_jobs_v1(p_limit integer default 8)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_result jsonb;
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_limit < 1 or p_limit > 20 then raise exception 'p_limit must be between 1 and 20'; end if;

  update research.responsible_party_resolution_jobs
  set state='queued',claimed_at=null,lease_until=null,last_error=concat_ws(E'\n',nullif(last_error,''),'claim lease expired'),updated_at=now()
  where state='claimed' and lease_until<now();
  update research.responsible_party_resolution_jobs
  set state='exhausted',completed_at=coalesce(completed_at,now()),
      exhaustion_reason=coalesce(exhaustion_reason,'retry_budget_exhausted'),
      requery_after=coalesce(requery_after,now()+interval '90 days'),updated_at=now()
  where state in ('queued','failed') and attempt_count>=max_attempts;

  with picked as (
    select id from research.responsible_party_resolution_jobs
    where state in ('queued','failed') and attempt_count<max_attempts and next_attempt_at<=now()
    order by priority desc,next_attempt_at,created_at for update skip locked limit p_limit
  ), claimed as (
    update research.responsible_party_resolution_jobs j
    set state='claimed',attempt_count=j.attempt_count+1,claimed_at=now(),lease_until=now()+interval '30 minutes',last_error=null,updated_at=now()
    from picked where j.id=picked.id returning j.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',c.id,'profile_key',c.profile_key,'lookup_key',c.lookup_key,
    'parcel_source_record_id',c.parcel_source_record_id,'parcel_source_native_id',c.parcel_source_native_id,
    'parcel_id',c.parcel_id,'priority',c.priority,'attempt_count',c.attempt_count,'max_attempts',c.max_attempts,
    'provider_kind',p.provider_kind,'owner_lookup_url_template',p.owner_lookup_url_template,
    'source_authority',p.source_authority,'source_url',p.source_url,
    'candidate_keys',(select coalesce(jsonb_agg(l.candidate_key order by l.candidate_key),'[]'::jsonb)
      from research.responsible_party_resolution_job_candidates l where l.job_id=c.id)
  ) order by c.priority desc,c.created_at),'[]'::jsonb)
  into v_result from claimed c join research.responsible_party_source_profiles p on p.profile_key=c.profile_key;
  return v_result;
end $$;

revoke all on function public.internal_claim_responsible_party_resolution_jobs_v1(integer) from public,anon,authenticated;
grant execute on function public.internal_claim_responsible_party_resolution_jobs_v1(integer) to service_role;

create or replace function public.internal_complete_responsible_party_resolution_job_v1(
  p_job_id uuid,p_outcome text,p_party_name text default null,p_site_address text default null,
  p_parcel_id text default null,p_source_url text default null,p_source_authority text default null,
  p_observed_on date default null,p_attributes jsonb default '{}'::jsonb,p_error text default null
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_job research.responsible_party_resolution_jobs%rowtype; v_candidates text[];
  v_kind text; v_name text; v_norm text; v_evidence integer:=0; v_state text;
  v_next timestamptz; v_reason text; v_refresh jsonb;
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_outcome not in ('completed','no_evidence','needs_review','research_exhausted','failed') then raise exception 'invalid outcome'; end if;
  if jsonb_typeof(coalesce(p_attributes,'{}'::jsonb))<>'object' then raise exception 'p_attributes must be an object'; end if;
  select * into v_job from research.responsible_party_resolution_jobs where id=p_job_id for update;
  if not found or v_job.state<>'claimed' then raise exception 'claimed responsible-party job required'; end if;
  select coalesce(array_agg(candidate_key order by candidate_key),'{}'::text[]) into v_candidates
  from research.responsible_party_resolution_job_candidates where job_id=v_job.id;

  v_name=nullif(btrim(p_party_name),'');
  if p_outcome='completed' and (v_name is null or p_source_url !~ '^https?://') then
    raise exception 'completed outcome requires party name and public source URL';
  end if;

  if v_name is not null then
    v_norm=public.scout_normalize_business_name(v_name); v_kind=scout.classify_responsible_party_name_v1(v_name);
    insert into scout.opportunity_responsible_party_evidence(
      candidate_key,party_role,party_name,party_name_normalized,party_kind,site_address_text,
      parcel_source_record_id,parcel_source_native_id,parcel_id,evidence_class,confidence,
      source_url,source_authority,observed_on,attributes,updated_at
    )
    select c,'property_owner',v_name,v_norm,v_kind,p_site_address,
      v_job.parcel_source_record_id,v_job.parcel_source_native_id,coalesce(nullif(p_parcel_id,''),v_job.parcel_id),
      'authoritative_record',.98,p_source_url,coalesce(nullif(p_source_authority,''),'Public property assessment record'),
      p_observed_on,coalesce(p_attributes,'{}'::jsonb)||jsonb_build_object(
        'responsible_party_job_id',v_job.id,'relationship_scope','property_owner_only',
        'buyer_authority_not_implied',true,'property_manager_not_implied',true,'operator_not_implied',true),now()
    from unnest(v_candidates) c
    on conflict(candidate_key,party_role,party_name_normalized,source_url) do update set
      party_name=excluded.party_name,party_kind=excluded.party_kind,site_address_text=excluded.site_address_text,
      parcel_source_record_id=excluded.parcel_source_record_id,parcel_source_native_id=excluded.parcel_source_native_id,
      parcel_id=excluded.parcel_id,confidence=excluded.confidence,source_authority=excluded.source_authority,
      observed_on=excluded.observed_on,attributes=excluded.attributes,updated_at=now();
    get diagnostics v_evidence=row_count;

    update scout.opportunity_buyer_identities b set
      buyer_name=v_name,role_code='property_owner_candidate',identity_kind='responsible_owner',
      resolution_status='named_responsibility',confidence=greatest(b.confidence,.96),
      identity_basis='authoritative_parcel_owner',observed_at=coalesce(p_observed_on::timestamptz,now()),last_normalized_at=now()
    where b.candidate_key=any(v_candidates) and b.organization_id is null
      and (b.buyer_name is null or b.resolution_status in ('role_only','unresolved'));

    update scout.buyer_resolution_queue q set
      buyer_hint=v_name,role_code='property_owner_candidate',state='pending',next_attempt_at=now(),last_error=null,updated_at=now()
    where q.candidate_key=any(v_candidates) and q.missing_steps @> array['organization_resolution']::text[];
    v_refresh:=scout.refresh_opportunity_buyer_routes_for_candidates_v1(v_candidates);
  end if;

  if p_outcome='completed' then v_state:='completed';v_next:=v_job.next_attempt_at;v_reason:=null;
  elsif p_outcome='needs_review' then v_state:='needs_review';v_next:=v_job.next_attempt_at;v_reason:=coalesce(nullif(p_error,''),'manual_review_required');
  elsif p_outcome='research_exhausted' then v_state:='exhausted';v_next:=v_job.next_attempt_at;v_reason:=coalesce(nullif(p_error,''),'await_new_authoritative_evidence');
  elsif p_outcome='no_evidence' and v_job.attempt_count>=v_job.max_attempts then v_state:='exhausted';v_next:=v_job.next_attempt_at;v_reason:='bounded_lookup_completed_without_supported_owner';
  elsif p_outcome='no_evidence' then v_state:='queued';v_next:=now()+interval '7 days';v_reason:=null;
  elsif v_job.attempt_count>=v_job.max_attempts then v_state:='exhausted';v_next:=v_job.next_attempt_at;v_reason:='retry_budget_exhausted';
  else v_state:='failed';v_next:=now()+interval '12 hours';v_reason:=null; end if;

  update research.responsible_party_resolution_jobs set
    state=v_state,next_attempt_at=v_next,claimed_at=null,lease_until=null,
    completed_at=case when v_state in ('completed','needs_review','exhausted') then now() else null end,
    last_error=case when p_outcome='failed' then left(p_error,4000) else null end,
    exhaustion_reason=v_reason,requery_after=case when v_state='exhausted' then now()+interval '90 days' else null end,
    outcome_metadata=jsonb_build_object('party_name',v_name,'party_kind',v_kind,'evidence_rows',v_evidence,
      'candidate_count',cardinality(v_candidates),'buyer_route_refresh',v_refresh),updated_at=now()
  where id=v_job.id;

  return jsonb_build_object('job_id',v_job.id,'state',v_state,'party_name',v_name,'party_kind',v_kind,
    'evidence_rows',v_evidence,'candidate_count',cardinality(v_candidates),'refresh',v_refresh);
end $$;

revoke all on function public.internal_complete_responsible_party_resolution_job_v1(uuid,text,text,text,text,text,text,date,jsonb,text) from public,anon,authenticated;
grant execute on function public.internal_complete_responsible_party_resolution_job_v1(uuid,text,text,text,text,text,text,date,jsonb,text) to service_role;

create or replace function scout.restore_responsible_party_buyer_candidates_v1(p_candidate_keys text[] default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_restored integer:=0;
begin
  with ranked as (
    select e.*,row_number() over(partition by e.candidate_key order by e.confidence desc,e.observed_on desc nulls last,e.updated_at desc) rn
    from scout.opportunity_responsible_party_evidence e
    where e.party_role='property_owner' and e.evidence_class='authoritative_record' and e.confidence>=.95
      and (p_candidate_keys is null or e.candidate_key=any(p_candidate_keys))
  )
  update scout.opportunity_buyer_identities b set
    buyer_name=r.party_name,role_code='property_owner_candidate',identity_kind='responsible_owner',
    resolution_status='named_responsibility',confidence=greatest(b.confidence,.96),
    identity_basis='authoritative_parcel_owner',observed_at=coalesce(r.observed_on::timestamptz,b.observed_at),last_normalized_at=now()
  from ranked r where r.rn=1 and b.candidate_key=r.candidate_key and b.organization_id is null
    and (b.buyer_name is null or b.resolution_status in ('role_only','unresolved') or b.identity_basis in ('decision_profile_role_only','unresolved'));
  get diagnostics v_restored=row_count;
  return jsonb_build_object('restored',v_restored);
end $$;

revoke all on function scout.restore_responsible_party_buyer_candidates_v1(text[]) from public,anon,authenticated;
grant execute on function scout.restore_responsible_party_buyer_candidates_v1(text[]) to service_role;

create or replace function public.internal_materialize_responsible_party_org_v1(p_job_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_job research.document_evidence_jobs%rowtype; v_name text; v_norm text; v_kind text;
  v_org_id uuid; v_match_count integer:=0; v_evidence_count integer:=0;
  v_source_url text; v_source_authority text; v_created boolean:=false;
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into v_job from research.document_evidence_jobs where id=p_job_id for update;
  if not found or v_job.rule_pack<>'buyer_organization_contact_v1' or v_job.state<>'claimed' then raise exception 'claimed buyer evidence job required'; end if;
  if nullif(v_job.context->>'organization_id','') is not null then return jsonb_build_object('status','already_resolved','organization_id',v_job.context->>'organization_id'); end if;
  v_name=nullif(btrim(v_job.organization_name),''); if v_name is null then return jsonb_build_object('status','not_named'); end if;
  v_kind=scout.classify_responsible_party_name_v1(v_name); if v_kind<>'organization' then return jsonb_build_object('status','not_business_like'); end if;
  v_norm=public.scout_normalize_business_name(v_name);

  select count(*),(array_agg(e.source_url order by e.updated_at desc))[1],(array_agg(e.source_authority order by e.updated_at desc))[1]
  into v_evidence_count,v_source_url,v_source_authority
  from research.document_evidence_job_candidates jc
  join scout.opportunity_responsible_party_evidence e on e.candidate_key=jc.candidate_key
  where jc.job_id=v_job.id and e.party_role='property_owner' and e.evidence_class='authoritative_record'
    and e.confidence>=.95 and e.party_name_normalized=v_norm;
  if v_evidence_count=0 then return jsonb_build_object('status','no_authoritative_responsible_party_evidence'); end if;

  perform pg_advisory_xact_lock(hashtextextended('responsible-party-org:'||v_norm,0));
  with matches as (
    select o.id from core.organizations o where o.status='active' and public.scout_normalize_business_name(o.canonical_name)=v_norm
    union
    select a.organization_id from core.organization_aliases a join core.organizations o on o.id=a.organization_id and o.status='active'
    where public.scout_normalize_business_name(a.alias)=v_norm
  ) select count(*),(array_agg(id order by id))[1] into v_match_count,v_org_id from matches;
  if v_match_count>1 then return jsonb_build_object('status','ambiguous_existing_organization','match_count',v_match_count); end if;

  if v_match_count=0 then
    insert into core.organizations(canonical_name,normalized_name,organization_type,status,attributes,updated_at)
    values(v_name,v_norm,null,'active',jsonb_strip_nulls(jsonb_build_object(
      'identity_source','authoritative_property_owner','identity_source_url',v_source_url,
      'identity_source_authority',v_source_authority,'document_evidence_job_id',v_job.id,
      'identity_scope','property_owner_only','buyer_authority_not_implied',true,'property_manager_not_implied',true)),now())
    returning id into v_org_id; v_created:=true;
  end if;

  update research.document_evidence_jobs set context=jsonb_set(
    jsonb_set(coalesce(context,'{}'::jsonb),'{organization_id}',to_jsonb(v_org_id::text),true),
    '{organization_identity_basis}',to_jsonb('authoritative_property_owner'::text),true),updated_at=now()
  where id=v_job.id;
  update scout.opportunity_responsible_party_evidence e set organization_id=v_org_id,updated_at=now()
  where e.party_role='property_owner' and e.party_name_normalized=v_norm
    and exists(select 1 from research.document_evidence_job_candidates jc where jc.job_id=v_job.id and jc.candidate_key=e.candidate_key);

  return jsonb_build_object('status',case when v_created then 'created_from_authoritative_property_owner' else 'resolved_existing' end,
    'organization_id',v_org_id,'canonical_name',v_name,'created',v_created,'buyer_authority_not_implied',true);
end $$;

revoke all on function public.internal_materialize_responsible_party_org_v1(uuid) from public,anon,authenticated;
grant execute on function public.internal_materialize_responsible_party_org_v1(uuid) to service_role;

-- Wrap the existing source-party materializer without changing the worker call contract.
alter function public.internal_materialize_authoritative_named_buyer_org_v1(uuid)
  rename to internal_materialize_authoritative_named_buyer_org_source_v1;

create or replace function public.internal_materialize_authoritative_named_buyer_org_v1(p_job_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_source jsonb; v_responsible jsonb; v_status text;
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  v_source:=public.internal_materialize_authoritative_named_buyer_org_source_v1(p_job_id);
  v_status:=coalesce(v_source->>'status','');
  if nullif(v_source->>'organization_id','') is not null
     or v_status in ('already_resolved','ambiguous_existing_organization','not_business_like') then return v_source; end if;
  v_responsible:=public.internal_materialize_responsible_party_org_v1(p_job_id);
  if nullif(v_responsible->>'organization_id','') is not null
     or coalesce(v_responsible->>'status','') in ('ambiguous_existing_organization','not_business_like') then return v_responsible; end if;
  return v_source;
end $$;

revoke all on function public.internal_materialize_authoritative_named_buyer_org_v1(uuid) from public,anon,authenticated;
grant execute on function public.internal_materialize_authoritative_named_buyer_org_v1(uuid) to service_role;

-- Defense in depth: personal parcel owners may be researched, but can never be
-- materialized as core organizations by the generic buyer-document worker.
create or replace function research.guard_responsible_party_person_org_materialization_v1()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_job_id uuid; v_norm text; v_person_count integer:=0;
begin
  if coalesce(new.attributes->>'identity_source','')<>'bounded_document_evidence_worker'
     or nullif(new.attributes->>'document_evidence_job_id','') is null then return new; end if;
  v_job_id:=(new.attributes->>'document_evidence_job_id')::uuid;
  v_norm:=public.scout_normalize_business_name(new.canonical_name);
  select count(*) into v_person_count
  from research.document_evidence_job_candidates jc
  join scout.opportunity_responsible_party_evidence e on e.candidate_key=jc.candidate_key
  where jc.job_id=v_job_id and e.party_role='property_owner' and e.party_kind='person_or_household'
    and e.party_name_normalized=v_norm and e.evidence_class='authoritative_record' and e.confidence>=.95;
  if v_person_count>0 then raise exception 'authoritative property owner is a person/household; organization materialization prohibited'; end if;
  return new;
end $$;

revoke all on function research.guard_responsible_party_person_org_materialization_v1() from public,anon,authenticated,service_role;
drop trigger if exists trg_guard_responsible_party_person_org_materialization_v1 on core.organizations;
create trigger trg_guard_responsible_party_person_org_materialization_v1
before insert on core.organizations for each row execute function research.guard_responsible_party_person_org_materialization_v1();

-- Fill canonical source-registry provenance when normalized opportunity details
-- carry source_slug but not source_url.
create or replace function research.enrich_authoritative_named_org_provenance_v1()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_url text; v_authority text;
begin
  if coalesce(new.attributes->>'identity_source','')<>'authoritative_named_responsibility'
     or nullif(new.attributes->>'identity_source_url','') is not null
     or nullif(new.attributes->>'document_evidence_job_id','') is null then return new; end if;
  select src.homepage_url,src.authority into v_url,v_authority
  from research.document_evidence_job_candidates jc
  join scout.opportunity_search_spine s on s.candidate_key=jc.candidate_key
  join ingest.sources src on src.slug=s.details->>'source_slug'
  where jc.job_id=(new.attributes->>'document_evidence_job_id')::uuid and src.homepage_url is not null
  order by jc.candidate_key limit 1;
  if v_url is not null then new.attributes:=new.attributes||jsonb_build_object(
    'identity_source_url',v_url,'identity_source_authority',coalesce(v_authority,new.attributes->>'identity_source_authority')); end if;
  return new;
end $$;

revoke all on function research.enrich_authoritative_named_org_provenance_v1() from public,anon,authenticated,service_role;
drop trigger if exists trg_enrich_authoritative_named_org_provenance_v1 on core.organizations;
create trigger trg_enrich_authoritative_named_org_provenance_v1
before insert or update of attributes on core.organizations
for each row execute function research.enrich_authoritative_named_org_provenance_v1();

with resolved as (
  select distinct on (o.id) o.id,src.homepage_url,src.authority
  from core.organizations o
  join research.document_evidence_job_candidates jc on jc.job_id=(o.attributes->>'document_evidence_job_id')::uuid
  join scout.opportunity_search_spine s on s.candidate_key=jc.candidate_key
  join ingest.sources src on src.slug=s.details->>'source_slug'
  where o.attributes->>'identity_source'='authoritative_named_responsibility'
    and nullif(o.attributes->>'identity_source_url','') is null
    and nullif(o.attributes->>'document_evidence_job_id','') is not null and src.homepage_url is not null
  order by o.id,jc.candidate_key
)
update core.organizations o set attributes=o.attributes||jsonb_build_object(
  'identity_source_url',r.homepage_url,'identity_source_authority',r.authority),updated_at=now()
from resolved r where o.id=r.id;

create or replace function research.seed_responsible_party_resolution_jobs_cron_v1(p_limit integer default 500)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_result jsonb;
begin
  if current_user <> 'postgres' and session_user <> 'postgres' then raise exception 'postgres scheduler only'; end if;
  perform set_config('request.jwt.claim.role','service_role',true);
  v_result:=public.internal_seed_responsible_party_resolution_jobs_v1(p_limit); return v_result;
end $$;
revoke all on function research.seed_responsible_party_resolution_jobs_cron_v1(integer) from public,anon,authenticated,service_role;
grant execute on function research.seed_responsible_party_resolution_jobs_cron_v1(integer) to postgres;

create or replace function scout.restore_responsible_party_buyer_candidates_cron_v1()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_result jsonb;
begin
  if current_user <> 'postgres' and session_user <> 'postgres' then raise exception 'postgres scheduler only'; end if;
  perform set_config('request.jwt.claim.role','service_role',true);
  v_result:=scout.restore_responsible_party_buyer_candidates_v1(null); return v_result;
end $$;
revoke all on function scout.restore_responsible_party_buyer_candidates_cron_v1() from public,anon,authenticated,service_role;
grant execute on function scout.restore_responsible_party_buyer_candidates_cron_v1() to postgres;

create or replace view scout.v_buyer_pipeline_health_v1 as
select now() observed_at,
  (select count(*) from scout.buyer_resolution_queue where state='pending') buyer_queue_pending,
  (select count(*) from scout.buyer_resolution_queue where state='resolved') buyer_queue_resolved,
  (select count(*) from scout.buyer_resolution_queue where state='blocked') buyer_queue_blocked,
  (select min(updated_at) from scout.buyer_resolution_queue where state='pending') oldest_pending_updated_at,
  (select count(*) from research.document_evidence_jobs where rule_pack='buyer_organization_contact_v1' and state='queued') buyer_research_queued,
  (select count(*) from research.document_evidence_jobs where rule_pack='buyer_organization_contact_v1' and state='claimed') buyer_research_claimed,
  (select count(*) from research.document_evidence_jobs where rule_pack='buyer_organization_contact_v1' and state='completed') buyer_research_completed,
  (select count(*) from research.responsible_party_resolution_jobs where state='queued') responsible_party_queued,
  (select count(*) from research.responsible_party_resolution_jobs where state='claimed') responsible_party_claimed,
  (select count(*) from research.responsible_party_resolution_jobs where state='completed') responsible_party_completed,
  (select count(*) from research.responsible_party_resolution_jobs where state in ('needs_review','exhausted')) responsible_party_deferred,
  (select count(*) from scout.opportunity_responsible_party_evidence where evidence_class='authoritative_record') authoritative_responsible_party_facts,
  (select count(*) from ingest.collector_runs where slug='collect-buyer-document-evidence' and started_at>=now()-interval '24 hours') buyer_worker_runs_24h,
  (select count(*) from ingest.collector_runs where slug='collect-buyer-document-evidence' and status='succeeded' and started_at>=now()-interval '24 hours') buyer_worker_success_24h,
  (select count(*) from ingest.collector_runs where slug='collect-responsible-party-resolution' and started_at>=now()-interval '24 hours') responsible_party_worker_runs_24h,
  (select count(*) from ingest.collector_runs where slug='collect-responsible-party-resolution' and status='succeeded' and started_at>=now()-interval '24 hours') responsible_party_worker_success_24h;

insert into ingest.collector_routes(slug,enabled,allow_dispatch,updated_at)
values('collect-responsible-party-resolution',true,true,now())
on conflict(slug) do update set enabled=true,allow_dispatch=true,updated_at=now();

select cron.unschedule('scout-responsible-party-restore-hourly')
where exists(select 1 from cron.job where jobname='scout-responsible-party-restore-hourly');
select cron.schedule('scout-responsible-party-restore-hourly','18 * * * *',
  $$select scout.restore_responsible_party_buyer_candidates_cron_v1();$$);
select cron.unschedule('scout-responsible-party-seed-hourly')
where exists(select 1 from cron.job where jobname='scout-responsible-party-seed-hourly');
select cron.schedule('scout-responsible-party-seed-hourly','21 * * * *',
  $$select research.seed_responsible_party_resolution_jobs_cron_v1(750);$$);
select cron.unschedule('scout-responsible-party-worker')
where exists(select 1 from cron.job where jobname='scout-responsible-party-worker');
select cron.schedule('scout-responsible-party-worker','22,52 * * * *',
  $$select ingest.invoke_edge_collector('collect-responsible-party-resolution','{"limit":8}'::jsonb);$$);
