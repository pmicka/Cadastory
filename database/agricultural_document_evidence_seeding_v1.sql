-- Scout agriculture-specific Document Evidence Worker seeding v1.
--
-- Guarantees current agricultural buyer/contact work is materialized into the existing
-- buyer_organization_contact_v1 worker rather than competing for the generic buyer
-- seeder's global top-N. Phone-bearing operator↔field bridge candidates are carried as
-- search hints only and never become identity aliases or auto-promoted operator truth.

create or replace function public.internal_seed_agricultural_buyer_document_evidence_jobs(
  p_cluster_limit integer default 250
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_jobs integer:=0;
  v_links integer:=0;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service_role required';
  end if;
  if p_cluster_limit<1 or p_cluster_limit>1000 then
    raise exception 'p_cluster_limit must be between 1 and 1000';
  end if;

  create temporary table agricultural_buyer_seed_clusters on commit drop as
  with eligible as (
    select q.candidate_key,q.source_kind,q.priority,q.missing_steps,q.buyer_hint,q.address_hint,q.role_code,
           s.source_id,s.primary_service_slug,s.time_sensitive,s.signal_strength,s.confidence,
           s.buyer_organization_id,s.buyer_name,s.buyer_resolution_status,s.buyer_contact_status,
           f.display_name farm_display_name,f.organization_id farm_organization_id,
           f.mailing_address,f.mailing_city_state_zip,
           case
             when s.buyer_organization_id is not null then 'agriculture:organization:'||s.buyer_organization_id::text
             else 'agriculture:farm-source:'||s.source_id::text
           end cluster_key
    from scout.buyer_resolution_queue q
    join scout.opportunity_search_spine s using(candidate_key)
    join agriculture.farm_entity_candidates f on f.id=s.source_id
    where q.source_kind='farm_seasonal'
      and q.state in ('pending','researching','failed')
      and q.next_attempt_at<=now()
      and s.primary_service_slug like 'agricultural-%'
      and coalesce(s.global_suppressed,false)=false
      and coalesce(s.buyer_contact_status,'unresolved')='unresolved'
  ), ranked as (
    select e.cluster_key,
           (array_agg(e.buyer_organization_id) filter(where e.buyer_organization_id is not null))[1] buyer_organization_id,
           coalesce(max(e.buyer_name) filter(where e.buyer_organization_id is not null),max(e.farm_display_name),max(e.buyer_hint)) organization_name,
           max(e.priority) queue_priority,
           count(*) opportunity_count,
           bool_or(e.time_sensitive) time_sensitive,
           array_agg(e.candidate_key order by e.priority desc,e.candidate_key) candidate_keys,
           array_agg(distinct e.source_id) farm_candidate_ids,
           array_agg(distinct e.source_kind) source_kinds,
           array_agg(distinct e.primary_service_slug) filter(where e.primary_service_slug is not null) service_slugs,
           array_agg(distinct coalesce(nullif(e.address_hint,''),nullif(concat_ws(', ',nullif(e.mailing_address,''),nullif(e.mailing_city_state_zip,'')),'')))
             filter(where coalesce(nullif(e.address_hint,''),nullif(concat_ws(', ',nullif(e.mailing_address,''),nullif(e.mailing_city_state_zip,'')),'')) is not null) addresses,
           array_agg(distinct coalesce(e.buyer_name,e.farm_display_name,e.buyer_hint))
             filter(where coalesce(e.buyer_name,e.farm_display_name,e.buyer_hint) is not null) verified_prospect_names,
           array_agg(distinct e.role_code) filter(where e.role_code is not null) known_roles,
           md5(concat_ws('|',e.cluster_key,count(*)::text,max(e.priority)::text,
               string_agg(e.candidate_key,',' order by e.candidate_key),
               string_agg(coalesce(e.buyer_hint,''),',' order by e.candidate_key))) input_fingerprint,
           (-(max(e.priority)*300 + least(count(*),100)*150 +
              case when bool_or(e.time_sensitive) then 20000 else 0 end +
              case when exists(
                select 1
                from unnest(array_agg(distinct e.source_id)) sid
                join agriculture.field_entity_candidates sf on sf.candidate_id=sid and sf.relationship_status<>'rejected'
                join agriculture.farm_operator_field_bridge_candidates b on b.field_id=sf.field_id
                  and b.bridge_state in ('candidate','corroborated')
              ) then 10000 else 0 end))::integer worker_priority
    from eligible e
    group by e.cluster_key
    order by bool_or(e.time_sensitive) desc,max(e.priority) desc,count(*) desc
    limit p_cluster_limit
  )
  select r.*,
         coalesce((
           select jsonb_agg(x.item order by x.operator_name)
           from (
             select distinct on (b.operator_candidate_id)
               op.display_name operator_name,
               jsonb_build_object(
                 'operator_candidate_id',b.operator_candidate_id,
                 'operator_name',op.display_name,
                 'match_basis',b.match_basis,
                 'match_confidence',b.match_confidence,
                 'bridge_state',b.bridge_state,
                 'shared_field_count',(
                   select count(distinct b2.field_id)
                   from agriculture.farm_operator_field_bridge_candidates b2
                   join agriculture.field_entity_candidates sf2 on sf2.field_id=b2.field_id
                   where b2.operator_candidate_id=b.operator_candidate_id
                     and sf2.candidate_id=any(r.farm_candidate_ids)
                     and sf2.relationship_status<>'rejected'
                     and b2.bridge_state in ('candidate','corroborated')
                 ),
                 'source_evidence_ids',to_jsonb(b.source_evidence_ids),
                 'search_hint_only',true,
                 'not_identity_alias',true,
                 'guardrail','Shared mailing address is corroborating candidate evidence only; current field operation and purchasing authority remain unresolved.'
               ) item
             from agriculture.field_entity_candidates sf
             join agriculture.farm_operator_field_bridge_candidates b on b.field_id=sf.field_id
               and b.bridge_state in ('candidate','corroborated')
             join agriculture.farm_entity_candidates op on op.id=b.operator_candidate_id
             where sf.candidate_id=any(r.farm_candidate_ids) and sf.relationship_status<>'rejected'
             order by b.operator_candidate_id,b.match_confidence desc,b.last_observed_at desc
           ) x
         ),'[]'::jsonb) operator_bridge_candidates,
         coalesce((
           select jsonb_agg(distinct u.url)
           from (
             select o.website_url url
             from core.organizations o
             where o.id=r.buyer_organization_id and o.website_url ~ '^https?://'
             union
             select fe.observed_website
             from agriculture.farm_entity_evidence fe
             where fe.candidate_id=any(r.farm_candidate_ids)
               and fe.observed_website ~ '^https?://'
           ) u
         ),'[]'::jsonb) source_roots
  from ranked r;

  insert into research.document_evidence_jobs(
    rule_pack,subject_type,subject_id,subject_key,cluster_key,input_fingerprint,
    display_name,organization_name,priority,max_attempts,search_query,source_roots,context,updated_at
  )
  select 'buyer_organization_contact_v1','buyer_cluster',
         (substr(md5(c.cluster_key),1,8)||'-'||substr(md5(c.cluster_key),9,4)||'-'||
          substr(md5(c.cluster_key),13,4)||'-'||substr(md5(c.cluster_key),17,4)||'-'||
          substr(md5(c.cluster_key),21,12))::uuid,
         c.cluster_key,c.cluster_key,c.input_fingerprint,
         coalesce(c.organization_name,(c.addresses)[1],c.cluster_key),c.organization_name,
         c.worker_priority,2,
         concat_ws(' ',quote_literal(c.organization_name),(c.addresses)[1],
           'farm agricultural operation contact phone website owner operator'),
         c.source_roots,
         jsonb_build_object(
           'research_domain','agriculture',
           'cluster_key',c.cluster_key,
           'organization_id',c.buyer_organization_id,
           'organization_name',c.organization_name,
           'candidate_keys',to_jsonb(c.candidate_keys),
           'farm_candidate_ids',to_jsonb(c.farm_candidate_ids),
           'source_kinds',to_jsonb(c.source_kinds),
           'service_slugs',to_jsonb(c.service_slugs),
           'addresses',to_jsonb(c.addresses),
           'known_parties',to_jsonb(c.verified_prospect_names),
           'known_roles',to_jsonb(c.known_roles),
           'opportunity_count',c.opportunity_count,
           'time_sensitive',c.time_sensitive,
           'agriculture_operator_bridge_candidates',c.operator_bridge_candidates,
           'guardrails',jsonb_build_array(
             'landholder_is_not_automatically_the_current_operator_or_customer',
             'shared_mailing_address_is_candidate_corroboration_not_operator_proof',
             'operator_bridge_names_are_search_hints_not_identity_aliases',
             'proximity_is_not_ownership_or_operator_evidence',
             'do_not_infer_personal_email',
             'do_not_auto_promote_operator_identity_or_purchasing_authority_without_independent_corroboration')
         ),now()
  from agricultural_buyer_seed_clusters c
  on conflict(rule_pack,subject_type,subject_id) do update set
    subject_key=excluded.subject_key,
    cluster_key=excluded.cluster_key,
    display_name=excluded.display_name,
    organization_name=excluded.organization_name,
    priority=excluded.priority,
    search_query=excluded.search_query,
    source_roots=excluded.source_roots,
    context=excluded.context,
    updated_at=now(),
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
    input_fingerprint=excluded.input_fingerprint,
    exhaustion_reason=case when research.document_evidence_jobs.input_fingerprint is distinct from excluded.input_fingerprint then null else research.document_evidence_jobs.exhaustion_reason end,
    requery_after=case when research.document_evidence_jobs.input_fingerprint is distinct from excluded.input_fingerprint then null else research.document_evidence_jobs.requery_after end;
  get diagnostics v_jobs=row_count;

  insert into research.document_evidence_job_candidates(
    job_id,candidate_key,base_candidate_key,source_kind,service_slug,source_record_id,relationship_role,updated_at
  )
  select j.id,e.candidate_key,e.candidate_key,e.source_kind,e.primary_service_slug,e.source_id,e.buyer_role_code,now()
  from agricultural_buyer_seed_clusters c
  join research.document_evidence_jobs j
    on j.rule_pack='buyer_organization_contact_v1'
   and j.subject_type='buyer_cluster'
   and j.cluster_key=c.cluster_key
  join scout.opportunity_search_spine e on e.candidate_key=any(c.candidate_keys)
  on conflict(job_id,candidate_key) do update set
    base_candidate_key=excluded.base_candidate_key,
    source_kind=excluded.source_kind,
    service_slug=excluded.service_slug,
    source_record_id=excluded.source_record_id,
    relationship_role=excluded.relationship_role,
    updated_at=now();
  get diagnostics v_links=row_count;

  return jsonb_build_object(
    'agricultural_clusters_upserted',v_jobs,
    'candidate_links_upserted',v_links,
    'eligible_agricultural_buyer_jobs',(
      select count(*)
      from research.document_evidence_jobs
      where rule_pack='buyer_organization_contact_v1'
        and context->>'research_domain'='agriculture'
        and state in ('queued','failed')
        and attempt_count<max_attempts
        and next_attempt_at<=now()
    )
  );
end;
$function$;

revoke all on function public.internal_seed_agricultural_buyer_document_evidence_jobs(integer) from public,anon,authenticated;
grant execute on function public.internal_seed_agricultural_buyer_document_evidence_jobs(integer) to service_role;

comment on function public.internal_seed_agricultural_buyer_document_evidence_jobs(integer) is
  'Materializes agricultural farm buyer/contact clusters into the existing Document Evidence Worker without treating landholder or shared-address operator candidates as confirmed current operators.';
