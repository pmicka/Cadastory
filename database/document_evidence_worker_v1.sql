-- General-purpose, service-role-only document evidence queue and checkpoint layer.
create schema if not exists document_research;
revoke all on schema document_research from public, anon, authenticated;
grant usage on schema document_research to service_role;

create table if not exists document_research.jobs (
  id uuid primary key default gen_random_uuid(),
  target_kind text not null,
  target_id uuid not null,
  target_key text not null,
  rule_pack text not null,
  rule_version text not null,
  priority integer not null default 0,
  state text not null default 'queued' check (state in ('queued','claimed','running','evidence_found','resolved','partial','no_evidence','retryable_failure','needs_human_review','exhausted')),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  distinct_source_attempts integer not null default 0 check (distinct_source_attempts >= 0),
  max_attempts integer not null default 3 check (max_attempts between 1 and 10),
  target_context jsonb not null default '{}'::jsonb,
  lease_token uuid,
  lease_owner text,
  lease_expires_at timestamptz,
  last_error text,
  result_summary jsonb not null default '{}'::jsonb,
  next_research_step text,
  next_attempt_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  resolved_at timestamptz,
  unique (target_kind,target_id,rule_pack,rule_version)
);

create table if not exists document_research.source_attempts (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references document_research.jobs(id) on delete cascade,
  source_url text not null,
  final_url text,
  source_authority text,
  retrieval_status text not null,
  retrieved_at timestamptz not null default now(),
  http_status integer,
  content_type text,
  content_sha256 text,
  document_title text,
  page_count integer,
  indexed_page_count integer,
  failure_reason text,
  extraction_metadata jsonb not null default '{}'::jsonb,
  media_retained boolean not null default false check (media_retained = false),
  retention_policy text not null default 'transient_source_only_derived_evidence_retained',
  unique(job_id,source_url)
);

create table if not exists document_research.evidence_results (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references document_research.jobs(id) on delete cascade,
  source_attempt_id uuid references document_research.source_attempts(id),
  domain_fact_kind text not null,
  normalized_fact jsonb not null,
  page_start integer,
  page_end integer,
  evidence_excerpt text,
  confidence numeric not null check (confidence between 0 and 1),
  classification_reason text not null,
  extraction_rule text not null,
  extraction_version text not null,
  canonical_writeback_status text not null default 'not_applicable',
  created_at timestamptz not null default now(),
  media_retained boolean not null default false check (media_retained = false),
  retention_policy text not null default 'transient_source_only_derived_evidence_retained'
);

create index if not exists document_evidence_jobs_claim_idx
  on document_research.jobs(priority desc,next_attempt_at,created_at)
  where state in ('queued','partial','no_evidence','retryable_failure','claimed','running');
create index if not exists document_evidence_source_attempts_job_idx on document_research.source_attempts(job_id);
create index if not exists document_evidence_results_job_idx on document_research.evidence_results(job_id);

alter table document_research.jobs enable row level security;
alter table document_research.source_attempts enable row level security;
alter table document_research.evidence_results enable row level security;
revoke all on all tables in schema document_research from public,anon,authenticated;
grant select,insert,update on all tables in schema document_research to service_role;

create or replace function public.internal_claim_document_evidence_jobs(
  p_worker_id text, p_batch_size integer default 5, p_lease_minutes integer default 30,
  p_rule_pack text default null, p_min_priority integer default null
) returns jsonb language plpgsql security invoker set search_path='' as $$
declare v_result jsonb;
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  if nullif(btrim(p_worker_id),'') is null then raise exception 'worker id required'; end if;
  if p_batch_size not between 1 and 25 or p_lease_minutes not between 5 and 180 then raise exception 'invalid claim bounds'; end if;
  with candidates as (
    select j.id from document_research.jobs j
    where (j.state in ('queued','partial','no_evidence','retryable_failure') or (j.state in ('claimed','running') and j.lease_expires_at < now()))
      and j.next_attempt_at <= now() and j.attempt_count < j.max_attempts
      and (p_rule_pack is null or j.rule_pack=p_rule_pack)
      and (p_min_priority is null or j.priority>=p_min_priority)
    order by j.priority desc,j.next_attempt_at,j.created_at
    for update skip locked limit p_batch_size
  ), claimed as (
    update document_research.jobs j set state='claimed',attempt_count=j.attempt_count+1,
      lease_token=gen_random_uuid(),lease_owner=p_worker_id,
      lease_expires_at=now()+make_interval(mins=>p_lease_minutes),updated_at=now(),last_error=null
    from candidates c where j.id=c.id returning j.*
  ) select coalesce(jsonb_agg(to_jsonb(claimed) order by priority desc,created_at),'[]'::jsonb) into v_result from claimed;
  return v_result;
end $$;

create or replace function public.internal_checkpoint_document_evidence_job(
  p_job_id uuid,p_lease_token uuid,p_state text,p_source_attempt jsonb default null,
  p_evidence jsonb default '[]'::jsonb,p_result_summary jsonb default '{}'::jsonb,
  p_last_error text default null,p_next_research_step text default null,p_retry_after_seconds integer default 0
) returns jsonb language plpgsql security invoker set search_path='' as $$
declare j document_research.jobs; a_id uuid; distinct_count integer; terminal boolean;
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_state not in ('running','evidence_found','resolved','partial','no_evidence','retryable_failure','needs_human_review','exhausted') then raise exception 'invalid state'; end if;
  select * into j from document_research.jobs where id=p_job_id for update;
  if not found or j.lease_token is distinct from p_lease_token or j.lease_expires_at < now() then raise exception 'invalid or expired lease'; end if;
  if p_source_attempt is not null then
    insert into document_research.source_attempts(job_id,source_url,final_url,source_authority,retrieval_status,http_status,content_type,content_sha256,document_title,page_count,indexed_page_count,failure_reason,extraction_metadata)
    values(p_job_id,p_source_attempt->>'source_url',p_source_attempt->>'final_url',p_source_attempt->>'source_authority',p_source_attempt->>'retrieval_status',nullif(p_source_attempt->>'http_status','')::integer,p_source_attempt->>'content_type',p_source_attempt->>'content_sha256',p_source_attempt->>'document_title',nullif(p_source_attempt->>'page_count','')::integer,nullif(p_source_attempt->>'indexed_page_count','')::integer,p_source_attempt->>'failure_reason',coalesce(p_source_attempt->'extraction_metadata','{}'::jsonb))
    on conflict(job_id,source_url) do update set final_url=excluded.final_url,retrieval_status=excluded.retrieval_status,retrieved_at=now(),http_status=excluded.http_status,content_type=excluded.content_type,content_sha256=excluded.content_sha256,document_title=excluded.document_title,page_count=excluded.page_count,indexed_page_count=excluded.indexed_page_count,failure_reason=excluded.failure_reason,extraction_metadata=excluded.extraction_metadata
    returning id into a_id;
  end if;
  insert into document_research.evidence_results(job_id,source_attempt_id,domain_fact_kind,normalized_fact,page_start,page_end,evidence_excerpt,confidence,classification_reason,extraction_rule,extraction_version,canonical_writeback_status)
  select p_job_id,a_id,x->>'domain_fact_kind',coalesce(x->'normalized_fact','{}'::jsonb),nullif(x->>'page_start','')::integer,nullif(x->>'page_end','')::integer,left(x->>'evidence_excerpt',1200),coalesce((x->>'confidence')::numeric,0),x->>'classification_reason',x->>'extraction_rule',x->>'extraction_version',coalesce(x->>'canonical_writeback_status','not_applicable')
  from jsonb_array_elements(coalesce(p_evidence,'[]'::jsonb)) x;
  select count(distinct source_url) into distinct_count from document_research.source_attempts where job_id=p_job_id;
  terminal := p_state in ('resolved','needs_human_review','exhausted');
  update document_research.jobs set state=p_state,distinct_source_attempts=distinct_count,last_error=left(p_last_error,2000),result_summary=coalesce(p_result_summary,'{}'::jsonb),next_research_step=p_next_research_step,next_attempt_at=case when p_state='retryable_failure' then now()+make_interval(secs=>greatest(p_retry_after_seconds,60)) else next_attempt_at end,lease_token=case when terminal or p_state in ('partial','no_evidence','retryable_failure') then null else lease_token end,lease_owner=case when terminal or p_state in ('partial','no_evidence','retryable_failure') then null else lease_owner end,lease_expires_at=case when terminal or p_state in ('partial','no_evidence','retryable_failure') then null else lease_expires_at end,resolved_at=case when terminal then now() else null end,updated_at=now() where id=p_job_id;
  return jsonb_build_object('job_id',p_job_id,'state',p_state,'distinct_source_attempts',distinct_count);
end $$;

create or replace function public.internal_seed_document_evidence_jobs() returns jsonb language plpgsql security invoker set search_path='' as $$
declare w integer; f integer;
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  insert into document_research.jobs(target_kind,target_id,target_key,rule_pack,rule_version,priority,state,target_context,next_research_step)
  select 'water_tank',q.tank_id,q.candidate_key,'water_tank_morphology_v1','1.0.0',100+q.research_priority,'queued',
    jsonb_build_object('name',q.tank_name,'system_name',q.system_name,'wris_tank_type',q.wris_tank_type,'capacity_gallons',q.capacity_gallons,'pwsid',q.pwsid,'lat',q.lat,'lon',q.lon,'identity_status','confirmed_asset','source_candidates',coalesce((select jsonb_agg(jsonb_build_object('url',e.source_url,'authority',e.source_authority) order by (lower(e.source_url) like '%.pdf') desc,e.confidence desc) from water.tank_geometry_evidence e where e.tank_id=q.tank_id and e.active and e.source_url like 'http%'),'[]'::jsonb)),'resolve elevated support morphology from asset-specific documents'
  from scout.v_water_tank_geometry_research_queue q where q.active_opportunity and q.morphology_research_needed
  on conflict(target_kind,target_id,rule_pack,rule_version) do nothing;
  get diagnostics w=row_count;
  insert into document_research.jobs(target_kind,target_id,target_key,rule_pack,rule_version,priority,state,target_context,next_research_step)
  select 'building',q.building_source_record_id,q.candidate_key,'facade_material_v1','1.0.0',200+q.verification_score,'queued',
    jsonb_build_object('display_name',q.display_name,'state_code',q.state_code,'county_name',q.county_name,'verification_needs',q.verification_needs,'identity_status',q.identity_status,'identity_confidence',q.identity_match_confidence,'source_candidates',jsonb_strip_nulls(jsonb_build_array(case when q.website_url is not null then jsonb_build_object('url',q.website_url,'authority','building website') end,case when q.building_lifecycle_source_url is not null then jsonb_build_object('url',q.building_lifecycle_source_url,'authority','lifecycle source') end))),'identity-resolved authoritative project/specification document required before canonical writeback'
  from decisioning.v_facade_visual_verification_queue_v4 q where q.effective_verification_priority='high'
  on conflict(target_kind,target_id,rule_pack,rule_version) do nothing;
  get diagnostics f=row_count;
  return jsonb_build_object('water_seeded',w,'facade_seeded',f);
end $$;

revoke all on function public.internal_claim_document_evidence_jobs(text,integer,integer,text,integer) from public,anon,authenticated;
revoke all on function public.internal_checkpoint_document_evidence_job(uuid,uuid,text,jsonb,jsonb,jsonb,text,text,integer) from public,anon,authenticated;
revoke all on function public.internal_seed_document_evidence_jobs() from public,anon,authenticated;
grant execute on function public.internal_claim_document_evidence_jobs(text,integer,integer,text,integer) to service_role;
grant execute on function public.internal_checkpoint_document_evidence_job(uuid,uuid,text,jsonb,jsonb,jsonb,text,text,integer) to service_role;
grant execute on function public.internal_seed_document_evidence_jobs() to service_role;
