create or replace function public.internal_seed_livestock_document_evidence_jobs()
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','extensions','research','agriculture','ingest'
as $function$
declare
  v_upserted integer := 0;
  v_total integer := 0;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service_role required';
  end if;

  with grouped as (
    select
      q.candidate_id,
      max(q.farm_name) as farm_name,
      max(q.observed_address) as observed_address,
      array_agg(distinct q.enterprise_kind order by q.enterprise_kind) as known_enterprise_kinds,
      max(q.source_url) as directory_url,
      max(nullif(fee.attributes->>'website_url','')) filter (
        where coalesce(fee.attributes->>'website_url','') ~* '^https?://'
      ) as website_url,
      max(q.source_description) as directory_description,
      max(q.confidence) as confidence
    from agriculture.farm_livestock_count_enrichment_queue_v1 q
    left join agriculture.farm_entity_evidence fee on fee.id=q.source_evidence_id
    where q.state_code='KY'
    group by q.candidate_id
  ), prepared as (
    select
      g.*,
      case
        when g.website_url is not null and g.website_url is distinct from g.directory_url
          then jsonb_build_array(g.directory_url,g.website_url)
        when g.directory_url is not null
          then jsonb_build_array(g.directory_url)
        else '[]'::jsonb
      end as source_roots,
      case
        when g.known_enterprise_kinds && array['beef','dairy','equine']::text[] then 20
        else 50
      end as priority
    from grouped g
  )
  insert into research.document_evidence_jobs(
    rule_pack,subject_type,subject_id,subject_key,display_name,organization_name,
    priority,state,max_attempts,next_attempt_at,search_query,source_roots,context,
    cluster_key,input_fingerprint
  )
  select
    'livestock_inventory_v1',
    'farm_livestock',
    p.candidate_id,
    'farm_livestock:'||p.candidate_id::text,
    p.farm_name,
    p.farm_name,
    p.priority,
    'queued',
    3,
    now(),
    concat_ws(' ',
      p.farm_name,p.observed_address,array_to_string(p.known_enterprise_kinds,' '),
      'farm livestock herd flock animal count head cattle cows calves heifers horses goats sheep pigs hogs poultry chickens turkeys'
    ),
    p.source_roots,
    jsonb_build_object(
      'research_domain','agriculture',
      'candidate_id',p.candidate_id,
      'known_parties',jsonb_build_array(p.farm_name),
      'addresses',case when p.observed_address is not null then jsonb_build_array(p.observed_address) else '[]'::jsonb end,
      'known_enterprise_kinds',to_jsonb(p.known_enterprise_kinds),
      'directory_description',p.directory_description,
      'livestock_evidence_only',true,
      'count_policy','accept explicit source-linked animal counts only; do not infer headcount from acreage, thresholds, or county statistics',
      'source_media_retention','transient_only'
    ),
    'livestock:'||p.candidate_id::text,
    encode(digest(concat_ws('|',
      'livestock_inventory_v1',p.candidate_id::text,p.farm_name,
      coalesce(p.observed_address,''),coalesce(p.directory_url,''),coalesce(p.website_url,''),
      array_to_string(p.known_enterprise_kinds,','),coalesce(p.directory_description,'')
    ),'sha256'),'hex')
  from prepared p
  on conflict(rule_pack,subject_type,subject_id) do update set
    display_name=excluded.display_name,
    organization_name=excluded.organization_name,
    priority=least(research.document_evidence_jobs.priority,excluded.priority),
    search_query=excluded.search_query,
    source_roots=excluded.source_roots,
    context=research.document_evidence_jobs.context||excluded.context,
    cluster_key=excluded.cluster_key,
    state=case
      when research.document_evidence_jobs.state in ('failed','exhausted')
       and research.document_evidence_jobs.input_fingerprint is distinct from excluded.input_fingerprint
      then 'queued' else research.document_evidence_jobs.state end,
    attempt_count=case
      when research.document_evidence_jobs.state in ('failed','exhausted')
       and research.document_evidence_jobs.input_fingerprint is distinct from excluded.input_fingerprint
      then 0 else research.document_evidence_jobs.attempt_count end,
    next_attempt_at=case
      when research.document_evidence_jobs.state in ('failed','exhausted')
       and research.document_evidence_jobs.input_fingerprint is distinct from excluded.input_fingerprint
      then now() else research.document_evidence_jobs.next_attempt_at end,
    completed_at=case
      when research.document_evidence_jobs.state in ('failed','exhausted')
       and research.document_evidence_jobs.input_fingerprint is distinct from excluded.input_fingerprint
      then null else research.document_evidence_jobs.completed_at end,
    last_error=case
      when research.document_evidence_jobs.state in ('failed','exhausted')
       and research.document_evidence_jobs.input_fingerprint is distinct from excluded.input_fingerprint
      then null else research.document_evidence_jobs.last_error end,
    input_fingerprint=excluded.input_fingerprint,
    updated_at=now();
  get diagnostics v_upserted = row_count;

  select count(*) into v_total
  from research.document_evidence_jobs
  where rule_pack='livestock_inventory_v1';

  return jsonb_build_object(
    'jobs_upserted',v_upserted,
    'total_livestock_jobs',v_total,
    'policy','evidence-only; explicit animal type/count evidence; no inferred headcount; source media transient only'
  );
end;
$function$;

revoke all on function public.internal_seed_livestock_document_evidence_jobs() from public;
grant execute on function public.internal_seed_livestock_document_evidence_jobs() to service_role;
