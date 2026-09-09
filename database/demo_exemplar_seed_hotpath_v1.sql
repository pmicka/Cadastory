-- Keep document-evidence seeding bounded per RPC.
--
-- Base document seeding, buyer seeding, and exemplar prioritization are invoked
-- as separate service-role RPCs by the worker entrypoint. This avoids wrapping
-- all three potentially expensive phases in one HTTP transaction while preserving
-- idempotent queue semantics and the same privacy/exposure posture.

create or replace function public.internal_seed_exemplar_document_evidence_jobs()
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','extensions','research','scout','decisioning','core','intelligence','water'
as $function$
declare
  v_surface int := 0;
  v_account int := 0;
  v_boosted int := 0;
  v_reopened int := 0;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service_role required';
  end if;

  update research.document_evidence_jobs j
  set priority = least(j.priority,e.priority),
      updated_at = now(),
      context = j.context || jsonb_build_object(
        'demo_exemplar',true,
        'demo_exemplar_class',e.exemplar_class,
        'demo_exemplar_priority',e.priority,
        'desired_evidence',to_jsonb(e.desired_evidence),
        'worker_routes',to_jsonb(e.worker_routes)
      )
  from research.v_demo_exemplar_enrichment_queue_v1 e
  where (
    (j.rule_pack='water_tank_morphology_v1'
      and e.candidate_key like 'water_tank:%'
      and j.subject_id=split_part(e.candidate_key,':',2)::uuid)
    or
    (j.rule_pack='facade_material_glazing_v1'
      and e.candidate_key is not null
      and j.subject_key=e.candidate_key)
  );
  get diagnostics v_boosted = row_count;

  insert into research.document_evidence_jobs(
    rule_pack,subject_type,subject_id,subject_key,display_name,organization_name,
    priority,state,max_attempts,next_attempt_at,search_query,source_roots,context,
    cluster_key,input_fingerprint
  )
  select
    'surface_work_condition_v1',
    'exemplar_surface',
    coalesce(
      e.subject_id,
      (substr(md5(e.exemplar_key),1,8)||'-'||substr(md5(e.exemplar_key),9,4)||'-'||substr(md5(e.exemplar_key),13,4)||'-'||substr(md5(e.exemplar_key),17,4)||'-'||substr(md5(e.exemplar_key),21,12))::uuid
    ),
    e.exemplar_key,
    e.display_name,
    e.organization_name,
    e.priority,
    'queued',
    3,
    now(),
    concat_ws(' ',
      e.display_name,e.organization_name,e.context->>'address_text',
      e.context->>'county_name',e.context->>'state_code',
      'exterior cleaning facade wash window brick EIFS limestone staining algae mold mildew paint coating rehabilitation restoration surface preparation'
    ),
    e.source_roots,
    e.context || jsonb_build_object(
      'candidate_key',e.candidate_key,
      'demo_exemplar',true,
      'demo_exemplar_class',e.exemplar_class,
      'desired_evidence',to_jsonb(e.desired_evidence),
      'worker_routes',to_jsonb(e.worker_routes),
      'selection_basis',e.selection_basis
    ),
    'demo-exemplar:'||e.exemplar_key,
    encode(digest(concat_ws('|',
      'surface_work_condition_v1',e.exemplar_key,e.display_name,
      coalesce(e.organization_name,''),e.priority::text,
      to_jsonb(e.desired_evidence)::text
    ),'sha256'),'hex')
  from research.v_demo_exemplar_enrichment_queue_v1 e
  on conflict(rule_pack,subject_type,subject_id) do update set
    priority=least(research.document_evidence_jobs.priority,excluded.priority),
    display_name=excluded.display_name,
    organization_name=coalesce(excluded.organization_name,research.document_evidence_jobs.organization_name),
    search_query=excluded.search_query,
    source_roots=case
      when jsonb_array_length(excluded.source_roots)>0 then excluded.source_roots
      else research.document_evidence_jobs.source_roots
    end,
    context=research.document_evidence_jobs.context||excluded.context,
    input_fingerprint=excluded.input_fingerprint,
    updated_at=now(),
    state=case
      when research.document_evidence_jobs.state in ('failed','exhausted')
       and research.document_evidence_jobs.input_fingerprint is distinct from excluded.input_fingerprint
      then 'queued' else research.document_evidence_jobs.state end,
    next_attempt_at=case
      when research.document_evidence_jobs.state in ('failed','exhausted')
       and research.document_evidence_jobs.input_fingerprint is distinct from excluded.input_fingerprint
      then now() else research.document_evidence_jobs.next_attempt_at end;
  get diagnostics v_surface = row_count;

  insert into research.document_evidence_job_candidates(
    job_id,candidate_key,base_candidate_key,source_kind,service_slug,
    source_record_id,relationship_role
  )
  select
    j.id,
    e.candidate_key,
    e.candidate_key,
    'demo_exemplar',
    null,
    case
      when split_part(e.candidate_key,':',2)~*'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      then split_part(e.candidate_key,':',2)::uuid
      else null
    end,
    'exemplar'
  from research.document_evidence_jobs j
  join research.v_demo_exemplar_enrichment_queue_v1 e
    on j.rule_pack='surface_work_condition_v1'
   and j.subject_key=e.exemplar_key
  where e.candidate_key is not null
  on conflict(job_id,candidate_key) do update set
    updated_at=now(),relationship_role='exemplar';

  insert into research.document_evidence_jobs(
    rule_pack,subject_type,subject_id,subject_key,display_name,organization_name,
    priority,state,max_attempts,next_attempt_at,search_query,source_roots,context,
    cluster_key,input_fingerprint
  )
  select
    'account_portfolio_context_v1',
    'exemplar_account',
    coalesce(
      a.organization_id,
      (substr(md5(a.account_key),1,8)||'-'||substr(md5(a.account_key),9,4)||'-'||substr(md5(a.account_key),13,4)||'-'||substr(md5(a.account_key),17,4)||'-'||substr(md5(a.account_key),21,12))::uuid
    ),
    a.account_key,
    a.display_name,
    a.display_name,
    a.priority,
    'queued',
    3,
    now(),
    concat_ws(' ',a.display_name,'portfolio properties projects facilities locations operations procurement vendor registration service area'),
    case when o.website_url is not null then jsonb_build_array(o.website_url) else '[]'::jsonb end,
    a.context || jsonb_build_object(
      'organization_id',a.organization_id,
      'organization_name',a.display_name,
      'demo_exemplar',true,
      'demo_exemplar_class',a.exemplar_class,
      'desired_evidence',to_jsonb(a.desired_evidence),
      'worker_routes',to_jsonb(a.worker_routes)
    ),
    'demo-account:'||a.account_key,
    encode(digest(concat_ws('|',
      'account_portfolio_context_v1',a.account_key,a.display_name,
      a.priority::text,to_jsonb(a.desired_evidence)::text
    ),'sha256'),'hex')
  from research.v_demo_exemplar_account_queue_v1 a
  left join core.organizations o on o.id=a.organization_id
  on conflict(rule_pack,subject_type,subject_id) do update set
    priority=least(research.document_evidence_jobs.priority,excluded.priority),
    display_name=excluded.display_name,
    organization_name=excluded.organization_name,
    search_query=excluded.search_query,
    source_roots=case
      when jsonb_array_length(excluded.source_roots)>0 then excluded.source_roots
      else research.document_evidence_jobs.source_roots
    end,
    context=research.document_evidence_jobs.context||excluded.context,
    input_fingerprint=excluded.input_fingerprint,
    updated_at=now(),
    state=case
      when research.document_evidence_jobs.state in ('failed','exhausted')
       and research.document_evidence_jobs.input_fingerprint is distinct from excluded.input_fingerprint
      then 'queued' else research.document_evidence_jobs.state end,
    next_attempt_at=case
      when research.document_evidence_jobs.state in ('failed','exhausted')
       and research.document_evidence_jobs.input_fingerprint is distinct from excluded.input_fingerprint
      then now() else research.document_evidence_jobs.next_attempt_at end;
  get diagnostics v_account = row_count;

  update research.document_evidence_jobs j
  set priority=least(j.priority,a.priority),
      updated_at=now(),
      context=j.context||jsonb_build_object(
        'demo_exemplar',true,
        'demo_exemplar_class',a.exemplar_class,
        'demo_exemplar_priority',a.priority,
        'desired_evidence',to_jsonb(a.desired_evidence),
        'worker_routes',to_jsonb(a.worker_routes)
      )
  from research.v_demo_exemplar_account_queue_v1 a
  where j.rule_pack='buyer_organization_contact_v1'
    and j.subject_key=a.account_key;

  with eligible as (
    select j.id
    from research.document_evidence_jobs j
    join research.v_demo_exemplar_account_queue_v1 a on a.account_key=j.subject_key
    where j.rule_pack='buyer_organization_contact_v1'
      and j.state='exhausted'
      and coalesce((j.context->>'demo_exemplar_retry_used')::boolean,false)=false
      and a.priority<=-110000
  )
  update research.document_evidence_jobs j
  set state='queued',
      attempt_count=0,
      max_attempts=greatest(max_attempts,3),
      next_attempt_at=now(),
      completed_at=null,
      last_error=null,
      context=j.context||jsonb_build_object(
        'demo_exemplar_retry_used',true,
        'demo_exemplar_retry_reason','one bounded deeper pass for high-leverage showcase account'
      ),
      updated_at=now()
  from eligible e
  where j.id=e.id;
  get diagnostics v_reopened = row_count;

  return jsonb_build_object(
    'surface_jobs_upserted',v_surface,
    'account_jobs_upserted',v_account,
    'existing_domain_jobs_boosted',v_boosted,
    'buyer_jobs_reopened_once',v_reopened,
    'policy','dynamic demo exemplar bench; no portfolio freeze; no score mutation; source media transient only'
  );
end;
$function$;

revoke all on function public.internal_seed_exemplar_document_evidence_jobs() from public, anon, authenticated;
grant execute on function public.internal_seed_exemplar_document_evidence_jobs() to service_role;
