-- Phase 3: documented site operators may use the projection-suppressed
-- responsible-party contact researcher. Operator identity still does not imply buyer authority.

create or replace function public.internal_seed_documented_operator_contact_research_jobs_v1(p_limit integer default 50)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_jobs integer:=0;
  v_links integer:=0;
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_limit<1 or p_limit>250 then raise exception 'p_limit must be between 1 and 250'; end if;

  create temporary table operator_contact_seed on commit drop as
  with eligible as (
    select
      e.id responsible_party_evidence_id,e.candidate_key,e.organization_id,e.party_name,
      e.source_url,e.source_authority,q.priority,q.address_hint,q.source_kind,
      s.primary_service_slug,s.source_id
    from scout.opportunity_responsible_party_evidence e
    join scout.buyer_resolution_queue q using(candidate_key)
    join scout.opportunity_search_spine s using(candidate_key)
    join core.organizations o on o.id=e.organization_id and o.status='active'
    where e.party_role='operator'
      and e.party_kind='organization'
      and e.evidence_class in ('documented','corroborated')
      and e.confidence>=.95
      and e.organization_id is not null
      and e.attributes->>'resolution_scope'='household_owner_fallback'
      and q.state in ('pending','researching')
      and coalesce(s.global_suppressed,false)=false
  ), clustered as (
    select organization_id,max(party_name) organization_name,max(priority) queue_priority,
      count(*) opportunity_count,
      array_agg(candidate_key order by priority desc,candidate_key) candidate_keys,
      array_agg(responsible_party_evidence_id order by candidate_key) evidence_ids,
      array_agg(distinct source_kind) source_kinds,
      array_agg(distinct primary_service_slug) filter(where primary_service_slug is not null) service_slugs,
      array_agg(distinct address_hint) filter(where address_hint is not null) addresses,
      md5(concat_ws('|',organization_id::text,count(*)::text,max(priority)::text,
        string_agg(candidate_key,',' order by candidate_key))) input_fingerprint
    from eligible
    group by organization_id
    order by max(priority) desc,count(*) desc,organization_id
    limit p_limit
  )
  select * from clustered;

  insert into research.document_evidence_jobs(
    rule_pack,subject_type,subject_id,subject_key,cluster_key,input_fingerprint,
    display_name,organization_name,priority,max_attempts,search_query,source_roots,context,updated_at
  )
  select
    'buyer_organization_contact_v1','responsible_party_contact',
    (substr(md5('responsible-party-operator-org:'||c.organization_id::text),1,8)||'-'||
     substr(md5('responsible-party-operator-org:'||c.organization_id::text),9,4)||'-'||
     substr(md5('responsible-party-operator-org:'||c.organization_id::text),13,4)||'-'||
     substr(md5('responsible-party-operator-org:'||c.organization_id::text),17,4)||'-'||
     substr(md5('responsible-party-operator-org:'||c.organization_id::text),21,12))::uuid,
    'responsible-party-operator-org:'||c.organization_id::text,
    'responsible-party-operator-org:'||c.organization_id::text,
    c.input_fingerprint,c.organization_name,c.organization_name,
    (-4500-(c.queue_priority*50)-least(c.opportunity_count,20)*25)::integer,
    2,
    concat_ws(' ',quote_literal(c.organization_name),'official facilities maintenance procurement vendor general contact'),
    coalesce((
      select jsonb_agg(x.url order by x.ord,x.url)
      from (
        select min(z.ord) ord,z.url
        from (
          select 1 ord,o.website_url url from core.organizations o
          where o.id=c.organization_id and o.website_url ~ '^https?://'
          union all
          select 2,e.source_url from scout.opportunity_responsible_party_evidence e
          where e.candidate_key=any(c.candidate_keys)
            and e.party_role='operator' and e.organization_id=c.organization_id
            and e.source_url ~ '^https?://'
        ) z group by z.url
      ) x
    ),'[]'::jsonb),
    jsonb_build_object(
      'research_domain','responsible_party_contact',
      'responsibility_role','operator',
      'organization_id',c.organization_id,
      'organization_name',c.organization_name,
      'candidate_keys',to_jsonb(c.candidate_keys),
      'source_kinds',to_jsonb(c.source_kinds),
      'service_slugs',to_jsonb(c.service_slugs),
      'addresses',to_jsonb(c.addresses),
      'opportunity_count',c.opportunity_count,
      'identity_projection','suppressed',
      'buyer_authority_not_implied',true,
      'ownership_not_implied',true,
      'property_management_not_implied',true,
      'operator_identity_only',true,
      'outbound_contact_performed',false,
      'guardrails',jsonb_build_array(
        'site_operator_is_not_automatically_the_buyer',
        'contact_route_does_not_imply_purchasing_authority',
        'do_not_project_this_job_into_buyer_identity',
        'do_not_infer_personal_email')
    ),now()
  from operator_contact_seed c
  on conflict(rule_pack,subject_type,subject_id) do update set
    subject_key=excluded.subject_key,cluster_key=excluded.cluster_key,input_fingerprint=excluded.input_fingerprint,
    display_name=excluded.display_name,organization_name=excluded.organization_name,priority=excluded.priority,
    search_query=excluded.search_query,source_roots=excluded.source_roots,context=excluded.context,updated_at=now(),
    state=case
      when research.document_evidence_jobs.input_fingerprint is distinct from excluded.input_fingerprint
        and research.document_evidence_jobs.state in ('exhausted','failed') then 'queued'
      when research.document_evidence_jobs.state='exhausted'
        and research.document_evidence_jobs.requery_after<=now() then 'queued'
      else research.document_evidence_jobs.state end,
    attempt_count=case
      when research.document_evidence_jobs.input_fingerprint is distinct from excluded.input_fingerprint
        or (research.document_evidence_jobs.state='exhausted' and research.document_evidence_jobs.requery_after<=now()) then 0
      else research.document_evidence_jobs.attempt_count end,
    exhaustion_reason=case when research.document_evidence_jobs.input_fingerprint is distinct from excluded.input_fingerprint then null else research.document_evidence_jobs.exhaustion_reason end,
    requery_after=case when research.document_evidence_jobs.input_fingerprint is distinct from excluded.input_fingerprint then null else research.document_evidence_jobs.requery_after end;
  get diagnostics v_jobs=row_count;

  insert into research.responsible_party_contact_job_candidates(
    job_id,candidate_key,responsible_party_evidence_id,responsible_organization_id,responsibility_role,updated_at
  )
  select j.id,e.candidate_key,e.id,e.organization_id,'operator',now()
  from operator_contact_seed c
  join research.document_evidence_jobs j
    on j.rule_pack='buyer_organization_contact_v1'
   and j.subject_type='responsible_party_contact'
   and j.cluster_key='responsible-party-operator-org:'||c.organization_id::text
  join scout.opportunity_responsible_party_evidence e
    on e.candidate_key=any(c.candidate_keys)
   and e.party_role='operator'
   and e.organization_id=c.organization_id
   and e.evidence_class in ('documented','corroborated')
   and e.confidence>=.95
   and e.attributes->>'resolution_scope'='household_owner_fallback'
  on conflict(job_id,candidate_key) do update set
    responsible_party_evidence_id=excluded.responsible_party_evidence_id,
    responsible_organization_id=excluded.responsible_organization_id,
    responsibility_role=excluded.responsibility_role,updated_at=now();
  get diagnostics v_links=row_count;

  return jsonb_build_object(
    'operator_contact_jobs_upserted',v_jobs,
    'responsibility_links_upserted',v_links,
    'buyer_projection_links_created',0
  );
end
$$;

revoke all on function public.internal_seed_documented_operator_contact_research_jobs_v1(integer)
  from public,anon,authenticated;
grant execute on function public.internal_seed_documented_operator_contact_research_jobs_v1(integer) to service_role;

create or replace function public.internal_claim_responsible_party_contact_research_jobs_v1(
  p_limit integer default 2,
  p_search_available boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_result jsonb;
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_limit<1 or p_limit>6 then raise exception 'p_limit must be between 1 and 6'; end if;

  update research.document_evidence_jobs j
  set state='queued',claimed_at=null,lease_until=null,
      last_error=concat_ws(E'\n',nullif(j.last_error,''),'claim lease expired'),updated_at=now()
  where j.rule_pack='buyer_organization_contact_v1'
    and j.subject_type='responsible_party_contact'
    and j.context->>'research_domain'='responsible_party_contact'
    and j.context->>'identity_projection'='suppressed'
    and j.state='claimed' and j.lease_until<now();

  update research.document_evidence_jobs j
  set state='exhausted',completed_at=coalesce(j.completed_at,now()),
      exhaustion_reason=coalesce(j.exhaustion_reason,'retry_budget_exhausted'),
      requery_after=coalesce(j.requery_after,now()+interval '90 days'),updated_at=now()
  where j.rule_pack='buyer_organization_contact_v1'
    and j.subject_type='responsible_party_contact'
    and j.context->>'research_domain'='responsible_party_contact'
    and j.context->>'identity_projection'='suppressed'
    and j.state in ('queued','failed') and j.attempt_count>=j.max_attempts;

  with picked as (
    select j.id
    from research.document_evidence_jobs j
    where j.rule_pack='buyer_organization_contact_v1'
      and j.subject_type='responsible_party_contact'
      and j.context->>'research_domain'='responsible_party_contact'
      and j.context->>'responsibility_role' in ('property_manager','operator')
      and j.context->>'identity_projection'='suppressed'
      and coalesce((j.context->>'buyer_authority_not_implied')::boolean,false)=true
      and nullif(j.context->>'organization_id','') is not null
      and j.state in ('queued','failed')
      and j.attempt_count<j.max_attempts
      and j.next_attempt_at<=now()
      and nullif(btrim(j.organization_name),'') is not null
      and ((jsonb_typeof(coalesce(j.source_roots,'[]'::jsonb))='array' and jsonb_array_length(coalesce(j.source_roots,'[]'::jsonb))>0) or p_search_available)
    order by j.priority asc,j.next_attempt_at asc,j.created_at asc
    for update skip locked
    limit p_limit
  ), claimed as (
    update research.document_evidence_jobs j
    set state='claimed',attempt_count=j.attempt_count+1,claimed_at=now(),lease_until=now()+interval '45 minutes',last_error=null,updated_at=now()
    from picked where j.id=picked.id returning j.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',c.id,'rule_pack',c.rule_pack,'subject_type',c.subject_type,'subject_id',c.subject_id,
    'subject_key',c.subject_key,'cluster_key',c.cluster_key,'display_name',c.display_name,
    'organization_name',c.organization_name,'priority',c.priority,'attempt_count',c.attempt_count,
    'max_attempts',c.max_attempts,'search_query',c.search_query,'source_roots',c.source_roots,'context',c.context
  ) order by c.priority,c.created_at),'[]'::jsonb)
  into v_result from claimed c;
  return v_result;
end
$$;

revoke all on function public.internal_claim_responsible_party_contact_research_jobs_v1(integer,boolean)
  from public,anon,authenticated;
grant execute on function public.internal_claim_responsible_party_contact_research_jobs_v1(integer,boolean) to service_role;

create or replace function research.seed_buyer_document_evidence_jobs_cron_v5(
  p_cluster_limit integer default 250,
  p_manager_limit integer default 50,
  p_operator_limit integer default 50
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_base jsonb; v_manager jsonb; v_operator jsonb;
begin
  if current_user<>'postgres' and session_user<>'postgres' then raise exception 'postgres scheduler only'; end if;
  if p_cluster_limit<1 or p_cluster_limit>1000 then raise exception 'p_cluster_limit must be between 1 and 1000'; end if;
  if p_manager_limit<1 or p_manager_limit>250 or p_operator_limit<1 or p_operator_limit>250 then raise exception 'responsible-party limits must be between 1 and 250'; end if;
  perform set_config('request.jwt.claim.role','service_role',true);
  v_base:=research.seed_buyer_document_evidence_jobs_cron_v3(p_cluster_limit);
  v_manager:=public.internal_seed_documented_manager_contact_research_jobs_v1(p_manager_limit);
  v_operator:=public.internal_seed_documented_operator_contact_research_jobs_v1(p_operator_limit);
  return jsonb_build_object('base',v_base,'manager_contact',v_manager,'operator_contact',v_operator);
end
$$;

revoke all on function research.seed_buyer_document_evidence_jobs_cron_v5(integer,integer,integer)
  from public,anon,authenticated;

-- No operator contact job may enter the generic buyer projection table.
do $$
declare v_bad integer;
begin
  select count(*) into v_bad
  from research.document_evidence_jobs j
  join research.document_evidence_job_candidates jc on jc.job_id=j.id
  where j.subject_type='responsible_party_contact'
    and j.context->>'responsibility_role'='operator';
  if v_bad<>0 then raise exception 'operator contact jobs entered buyer projection links'; end if;
end
$$;