-- Scout document evidence worker: conservative buyer/contact enrichment v1.
-- Reuses the canonical document evidence queue, leases, findings, buyer model,
-- and buyer-only projection path. Public source bodies are never retained.

alter table research.document_evidence_jobs
  add column if not exists cluster_key text,
  add column if not exists input_fingerprint text,
  add column if not exists exhaustion_reason text,
  add column if not exists requery_after timestamptz,
  add column if not exists outcome_metadata jsonb not null default '{}'::jsonb;

create index if not exists document_evidence_jobs_cluster_idx
  on research.document_evidence_jobs(rule_pack,cluster_key);
create index if not exists document_evidence_jobs_requery_idx
  on research.document_evidence_jobs(requery_after)
  where state='exhausted';

create table if not exists research.document_evidence_job_candidates (
  job_id uuid not null references research.document_evidence_jobs(id) on delete cascade,
  candidate_key text not null,
  base_candidate_key text,
  source_kind text not null,
  service_slug text,
  source_record_id uuid,
  relationship_role text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(job_id,candidate_key)
);

create index if not exists document_evidence_job_candidates_candidate_idx
  on research.document_evidence_job_candidates(candidate_key);

alter table research.document_evidence_job_candidates enable row level security;
revoke all on table research.document_evidence_job_candidates from public,anon,authenticated;

create or replace function public.internal_seed_buyer_document_evidence_jobs(
  p_cluster_limit integer default 250
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare v_jobs integer:=0; v_links integer:=0;
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_cluster_limit < 1 or p_cluster_limit > 1000 then raise exception 'p_cluster_limit must be between 1 and 1000'; end if;

  create temporary table buyer_seed_clusters on commit drop as
  with eligible as (
    select q.candidate_key,q.source_kind,q.priority,q.missing_steps,q.buyer_hint,q.address_hint,q.role_code,
      s.derived_from_candidate_key,s.primary_service_slug,s.time_sensitive,s.signal_strength,s.confidence,
      s.commercial_scale_status,s.scale_metric_count,s.buyer_organization_id,s.buyer_name,
      s.buyer_resolution_status,s.buyer_contact_status,s.procurement_status,s.source_id,
      coalesce(s.derived_from_candidate_key,s.candidate_key) base_candidate_key,
      case
        when s.buyer_organization_id is not null then 'organization:'||s.buyer_organization_id::text
        when nullif(public.scout_normalize_business_name(q.buyer_hint),'') is not null
          then 'named-party:'||public.scout_normalize_business_name(q.buyer_hint)
        when nullif(scout.normalize_address_key(q.address_hint),'') is not null
          then 'site:'||scout.normalize_address_key(q.address_hint)
        else 'candidate:'||coalesce(s.derived_from_candidate_key,s.candidate_key)
      end cluster_key
    from scout.buyer_resolution_queue q
    join scout.opportunity_search_spine s using(candidate_key)
    where q.state in ('pending','researching')
      and coalesce(s.global_suppressed,false)=false
      and q.next_attempt_at<=now()
      and (s.time_sensitive or s.commercial_scale_status='documented' or q.priority>=140)
      and (coalesce(s.buyer_resolution_status,'unresolved')<>'organization_resolved'
        or coalesce(s.buyer_contact_status,'unresolved')='unresolved'
        or coalesce(s.procurement_status,'unresolved') not in
          ('procurement_route_available','procurement_history_available'))
  ), ranked as (
    select cluster_key,
      (array_agg(buyer_organization_id) filter(where buyer_organization_id is not null))[1] buyer_organization_id,
      coalesce(max(buyer_name) filter(where buyer_organization_id is not null),max(buyer_hint)) organization_name,
      max(priority) queue_priority,count(*) opportunity_count,
      bool_or(time_sensitive) time_sensitive,
      count(*) filter(where commercial_scale_status='documented') commercial_scale_count,
      max(scale_metric_count) scale_metric_count,
      array_agg(candidate_key order by priority desc,candidate_key) candidate_keys,
      array_agg(distinct base_candidate_key) base_candidate_keys,
      array_agg(distinct source_kind) source_kinds,
      array_agg(distinct primary_service_slug) filter(where primary_service_slug is not null) service_slugs,
      array_agg(distinct address_hint) filter(where address_hint is not null) addresses,
      array_agg(distinct buyer_hint) filter(where buyer_hint is not null) known_parties,
      array_agg(distinct role_code) filter(where role_code is not null) known_roles,
      array_agg(distinct buyer_resolution_status) buyer_states,
      array_agg(distinct buyer_contact_status) contact_states,
      array_agg(distinct procurement_status) procurement_states,
      md5(concat_ws('|',cluster_key,count(*)::text,max(priority)::text,
        string_agg(candidate_key,',' order by candidate_key),
        string_agg(coalesce(buyer_hint,''),',' order by candidate_key))) input_fingerprint,
      (-(max(priority)*300+least(count(*),100)*150+
        count(*) filter(where commercial_scale_status='documented')*100+
        case when bool_or(time_sensitive) then 20000 else 0 end))::integer worker_priority
    from eligible group by cluster_key
    order by bool_or(time_sensitive) desc,
      count(*) filter(where commercial_scale_status='documented') desc,
      count(*) desc,max(priority) desc
    limit p_cluster_limit
  )
  select * from ranked;

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
      'official facilities procurement vendor property owner manager contact'),
    coalesce((select jsonb_agg(distinct u.url) from (
      select o.website_url url from core.organizations o where o.id=c.buyer_organization_id
      union all
      select cp.source_url from core.organization_contact_points cp where cp.organization_id=c.buyer_organization_id
    ) u where u.url ~ '^https?://'),'[]'::jsonb),
    jsonb_build_object(
      'cluster_key',c.cluster_key,'organization_id',c.buyer_organization_id,
      'organization_name',c.organization_name,'candidate_keys',to_jsonb(c.candidate_keys),
      'base_candidate_keys',to_jsonb(c.base_candidate_keys),'source_kinds',to_jsonb(c.source_kinds),
      'service_slugs',to_jsonb(c.service_slugs),'addresses',to_jsonb(c.addresses),
      'known_parties',to_jsonb(c.known_parties),'known_roles',to_jsonb(c.known_roles),
      'buyer_states',to_jsonb(c.buyer_states),'contact_states',to_jsonb(c.contact_states),
      'procurement_states',to_jsonb(c.procurement_states),'opportunity_count',c.opportunity_count,
      'time_sensitive',c.time_sensitive,'commercial_scale_count',c.commercial_scale_count,
      'scale_metric_count',c.scale_metric_count,
      'guardrails',jsonb_build_array(
        'tenant_or_operator_is_not_automatically_the_exterior_maintenance_buyer',
        'property_owner_manager_contractor_and_buyer_roles_must_remain_distinct',
        'proximity_is_not_ownership_or_buyer_evidence','do_not_infer_personal_email')
    ),now()
  from buyer_seed_clusters c
  on conflict(rule_pack,subject_type,subject_id) do update set
    subject_key=excluded.subject_key,cluster_key=excluded.cluster_key,
    display_name=excluded.display_name,organization_name=excluded.organization_name,
    priority=excluded.priority,search_query=excluded.search_query,source_roots=excluded.source_roots,
    context=excluded.context,updated_at=now(),
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
  select j.id,e.candidate_key,coalesce(e.derived_from_candidate_key,e.candidate_key),e.source_kind,e.primary_service_slug,e.source_id,e.buyer_role_code,now()
  from buyer_seed_clusters c
  join research.document_evidence_jobs j on j.rule_pack='buyer_organization_contact_v1' and j.cluster_key=c.cluster_key
  join scout.buyer_resolution_queue q on q.candidate_key=any(c.candidate_keys)
  join scout.opportunity_search_spine e on e.candidate_key=q.candidate_key
  on conflict(job_id,candidate_key) do update set
    base_candidate_key=excluded.base_candidate_key,source_kind=excluded.source_kind,
    service_slug=excluded.service_slug,source_record_id=excluded.source_record_id,
    relationship_role=excluded.relationship_role,updated_at=now();
  get diagnostics v_links=row_count;

  return jsonb_build_object('buyer_clusters_upserted',v_jobs,'candidate_links_upserted',v_links,
    'eligible_buyer_jobs',(select count(*) from research.document_evidence_jobs
      where rule_pack='buyer_organization_contact_v1' and state in ('queued','failed')
        and attempt_count<max_attempts and next_attempt_at<=now()));
end;
$function$;

create or replace function scout.refresh_opportunity_buyer_routes_for_candidates_v1(p_candidate_keys text[])
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_routes integer:=0; v_resolved integer:=0;
begin
  if p_candidate_keys is null or cardinality(p_candidate_keys)=0 then
    return jsonb_build_object('routes',0,'queue_resolved',0);
  end if;
  insert into scout.opportunity_buyer_routes(
    candidate_key,source_kind,source_buyer_name,role_code,organization_id,organization_name,
    organization_type,resolution_status,identity_basis,resolution_confidence,
    contact_point_id,contact_scope,contact_channel_type,contact_value,contact_department_name,
    contact_stability_class,contact_inherited,contact_confidence,contact_verify_after,
    procurement_contact_point_id,procurement_scope,procurement_channel_type,procurement_contact_value,
    procurement_contract_count,latest_procurement_type,latest_contract_begin_date,procurement_status,refreshed_at
  )
  select b.candidate_key,b.source_kind,b.buyer_name,b.role_code,b.organization_id,o.canonical_name,
    o.organization_type,'organization_resolved',coalesce(b.identity_basis,'document_evidence_exact_organization'),
    greatest(coalesce(b.confidence,.95),.95),
    bc.contact_point_id,bc.contact_scope,bc.channel_type,bc.contact_value,bc.department_name,
    bc.stability_class,bc.inherited,bc.confidence,bc.verify_after,
    pc.contact_point_id,pc.contact_scope,pc.channel_type,pc.contact_value,
    coalesce(ch.contract_count,0),ch.latest_procurement_type,ch.latest_begin_date,
    case when pc.contact_point_id is not null then 'procurement_route_available'
      when coalesce(ch.contract_count,0)>0 then 'procurement_history_available'
      when bc.contact_point_id is not null then 'durable_contact_available' else 'organization_only' end,now()
  from scout.opportunity_buyer_identities b
  join core.organizations o on o.id=b.organization_id and o.status='active'
  left join lateral (
    select ec.contact_point_id,ec.contact_scope,ec.channel_type,ec.contact_value,ec.department_name,
      ec.stability_class,ec.inherited,ec.confidence,ec.verify_after
    from core.v_organization_effective_contacts ec
    where ec.organization_id=b.organization_id and (ec.verify_after is null or ec.verify_after>=current_date)
    order by case ec.contact_scope when 'facilities' then 1 when 'physical_plant' then 2
      when 'maintenance' then 3 when 'facility_operations' then 4 when 'engineering' then 5
      when 'capital_projects' then 6 when 'planning_design_construction' then 7
      when 'project_construction' then 8 when 'grounds' then 9 when 'procurement' then 10
      when 'supplier_registration' then 11 when 'business_affairs' then 12
      when 'general_switchboard' then 20 else 30 end,
      case ec.stability_class when 'departmental' then 1 when 'institutional' then 2
        when 'role_holder' then 3 when 'project_specific' then 4 else 5 end,
      case ec.channel_type when 'email' then 1 when 'phone' then 2 when 'url' then 3 else 4 end,
      ec.confidence desc nulls last limit 1
  ) bc on true
  left join lateral (
    select ec.contact_point_id,ec.contact_scope,ec.channel_type,ec.contact_value
    from core.v_organization_effective_contacts ec
    where ec.organization_id=b.organization_id and (ec.verify_after is null or ec.verify_after>=current_date)
      and ec.contact_scope in ('procurement','supplier_registration','business_affairs')
    order by case ec.contact_scope when 'procurement' then 1 when 'supplier_registration' then 2 else 3 end,
      case ec.channel_type when 'email' then 1 when 'url' then 2 when 'phone' then 3 else 4 end,
      ec.confidence desc nulls last limit 1
  ) pc on true
  left join lateral (
    select count(*)::integer contract_count,
      (array_agg(c.procurement_type order by c.effective_begin_date desc nulls last,c.updated_at desc))[1] latest_procurement_type,
      max(c.effective_begin_date) latest_begin_date
    from procurement.contracts c where c.buyer_organization_id=b.organization_id
  ) ch on true
  where b.candidate_key=any(p_candidate_keys)
  on conflict(candidate_key) do update set
    source_kind=excluded.source_kind,source_buyer_name=excluded.source_buyer_name,role_code=excluded.role_code,
    organization_id=excluded.organization_id,organization_name=excluded.organization_name,
    organization_type=excluded.organization_type,resolution_status=excluded.resolution_status,
    identity_basis=excluded.identity_basis,resolution_confidence=excluded.resolution_confidence,
    contact_point_id=excluded.contact_point_id,contact_scope=excluded.contact_scope,
    contact_channel_type=excluded.contact_channel_type,contact_value=excluded.contact_value,
    contact_department_name=excluded.contact_department_name,contact_stability_class=excluded.contact_stability_class,
    contact_inherited=excluded.contact_inherited,contact_confidence=excluded.contact_confidence,
    contact_verify_after=excluded.contact_verify_after,procurement_contact_point_id=excluded.procurement_contact_point_id,
    procurement_scope=excluded.procurement_scope,procurement_channel_type=excluded.procurement_channel_type,
    procurement_contact_value=excluded.procurement_contact_value,
    procurement_contract_count=excluded.procurement_contract_count,latest_procurement_type=excluded.latest_procurement_type,
    latest_contract_begin_date=excluded.latest_contract_begin_date,procurement_status=excluded.procurement_status,
    refreshed_at=now();
  get diagnostics v_routes=row_count;
  update scout.buyer_resolution_queue q set state='resolved',last_error=null,updated_at=now()
  where q.candidate_key=any(p_candidate_keys) and exists(
    select 1 from scout.opportunity_buyer_routes r where r.candidate_key=q.candidate_key
      and r.resolution_status='organization_resolved' and r.contact_point_id is not null
      and r.procurement_status in ('procurement_route_available','procurement_history_available'));
  get diagnostics v_resolved=row_count;
  return jsonb_build_object('routes',v_routes,'queue_resolved',v_resolved);
end;
$function$;

create or replace function scout.refresh_buyer_projection_for_candidates_v1(p_candidate_keys text[])
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_base integer:=0; v_derived integer:=0;
begin
  if p_candidate_keys is null or cardinality(p_candidate_keys)=0 then
    return jsonb_build_object('base_rows',0,'derived_rows',0);
  end if;
  update scout.opportunity_search_spine s set
    buyer_resolution_status=r.resolution_status,buyer_organization_id=r.organization_id,
    buyer_name=r.organization_name,buyer_organization_type=r.organization_type,
    buyer_role_code=r.role_code,buyer_confidence=r.resolution_confidence,
    buyer_contact_status=case when r.contact_point_id is not null then 'contact_available' else 'unresolved' end,
    procurement_status=r.procurement_status,
    effective_contact_available=(s.source_contact_available or r.contact_point_id is not null),
    buyer_route_summary=jsonb_strip_nulls(jsonb_build_object(
      'resolution_status',r.resolution_status,'organization_id',r.organization_id,
      'organization_name',r.organization_name,'organization_type',r.organization_type,
      'role_code',r.role_code,'confidence',r.resolution_confidence,
      'contact_status',case when r.contact_point_id is not null then 'contact_available' else 'unresolved' end,
      'contact_scope',r.contact_scope,'contact_channel_type',r.contact_channel_type,
      'procurement_status',r.procurement_status)),
    refreshed_at=now()
  from scout.opportunity_buyer_routes r
  where s.candidate_key=r.candidate_key and s.candidate_key=any(p_candidate_keys);
  get diagnostics v_base=row_count;

  update scout.opportunity_search_spine e set
    buyer_resolution_status=b.buyer_resolution_status,buyer_organization_id=b.buyer_organization_id,
    buyer_name=b.buyer_name,buyer_organization_type=b.buyer_organization_type,
    buyer_role_code=b.buyer_role_code,buyer_confidence=b.buyer_confidence,
    buyer_contact_status=b.buyer_contact_status,procurement_status=b.procurement_status,
    effective_contact_available=(e.source_contact_available or b.effective_contact_available),
    buyer_route_summary=b.buyer_route_summary,refreshed_at=now()
  from scout.opportunity_search_spine b
  where e.derived_from_candidate_key=b.candidate_key
    and b.candidate_key=any(p_candidate_keys);
  get diagnostics v_derived=row_count;
  perform scout.refresh_buyer_account_unlock_stats_v1();
  return jsonb_build_object('base_rows',v_base,'derived_rows',v_derived);
end;
$function$;

create or replace function public.internal_complete_buyer_document_evidence_job(
  p_job_id uuid,p_outcome text,p_findings jsonb default '[]'::jsonb,p_error text default null
)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare
  v_job research.document_evidence_jobs%rowtype; v_item jsonb; v_route jsonb;
  v_org_id uuid; v_match_count integer; v_contact_count integer:=0; v_finding_count integer:=0;
  v_scope text; v_channel text; v_value text; v_stability text; v_conf numeric;
  v_state text; v_next timestamptz; v_exhaustion text; v_candidates text[]; v_refresh jsonb; v_projection jsonb;
begin
  if coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  if p_outcome not in ('completed','no_evidence','research_exhausted','needs_review','failed') then raise exception 'invalid outcome'; end if;
  if jsonb_typeof(coalesce(p_findings,'[]'::jsonb))<>'array' then raise exception 'p_findings must be an array'; end if;
  select * into v_job from research.document_evidence_jobs where id=p_job_id for update;
  if not found or v_job.rule_pack<>'buyer_organization_contact_v1' then raise exception 'buyer evidence job not found'; end if;
  if v_job.state<>'claimed' then raise exception 'job is not currently claimed'; end if;

  v_org_id=nullif(v_job.context->>'organization_id','')::uuid;
  if v_org_id is null and nullif(v_job.organization_name,'') is not null then
    with matches as (
      select o.id from core.organizations o where o.status='active'
        and public.scout_normalize_business_name(o.canonical_name)=public.scout_normalize_business_name(v_job.organization_name)
      union
      select a.organization_id from core.organization_aliases a
        where public.scout_normalize_business_name(a.alias)=public.scout_normalize_business_name(v_job.organization_name)
    ) select count(*),min(id) into v_match_count,v_org_id from matches;
    if v_match_count<>1 then v_org_id:=null; end if;
  end if;

  for v_item in select value from jsonb_array_elements(coalesce(p_findings,'[]'::jsonb)) loop
    if nullif(v_item->>'fingerprint','') is null or nullif(v_item->>'source_url','') is null then raise exception 'finding requires fingerprint and source_url'; end if;
    insert into research.document_evidence_findings(
      job_id,fingerprint,source_url,source_authority,source_kind,document_title,page_number,
      evidence_excerpt,evidence_codes,extracted_values,confidence,identity_confidence,
      decision_state,source_sha256,observed_at,media_retained,media_retention_policy,auto_applied
    ) values(v_job.id,v_item->>'fingerprint',v_item->>'source_url',nullif(v_item->>'source_authority',''),
      coalesce(nullif(v_item->>'source_kind',''),'public_web_page'),nullif(v_item->>'document_title',''),
      nullif(v_item->>'page_number','')::integer,left(v_item->>'evidence_excerpt',4000),
      coalesce(array(select jsonb_array_elements_text(coalesce(v_item->'evidence_codes','[]'::jsonb))),'{}'::text[]),
      coalesce(v_item->'extracted_values','{}'::jsonb),least(1,greatest(0,coalesce((v_item->>'confidence')::numeric,.5))),
      least(1,greatest(0,coalesce((v_item->>'identity_confidence')::numeric,.5))),
      coalesce(nullif(v_item->>'decision_state',''),'signal_to_investigate'),nullif(v_item->>'source_sha256',''),
      coalesce(nullif(v_item->>'observed_at','')::timestamptz,now()),false,
      'transient_only_no_source_media_retention',false)
    on conflict(job_id,fingerprint) do update set source_url=excluded.source_url,
      source_authority=excluded.source_authority,document_title=excluded.document_title,
      evidence_excerpt=excluded.evidence_excerpt,evidence_codes=excluded.evidence_codes,
      extracted_values=excluded.extracted_values,confidence=excluded.confidence,
      identity_confidence=excluded.identity_confidence,decision_state=excluded.decision_state,
      source_sha256=excluded.source_sha256,observed_at=excluded.observed_at;
    v_finding_count:=v_finding_count+1;

    if v_org_id is null or coalesce((v_item->>'auto_apply')::boolean,false)=false
       or coalesce((v_item->>'identity_confidence')::numeric,0)<.95 then continue; end if;
    for v_route in select value from jsonb_array_elements(coalesce(v_item#>'{extracted_values,contact_routes}','[]'::jsonb)) loop
      v_scope:=v_route->>'contact_scope'; v_channel:=v_route->>'channel_type'; v_value:=btrim(v_route->>'contact_value');
      v_stability:=coalesce(nullif(v_route->>'stability_class',''),'departmental');
      v_conf:=least(.89,greatest(.5,coalesce((v_route->>'confidence')::numeric,.7)));
      if v_scope not in ('facilities','physical_plant','maintenance','grounds','facility_operations','engineering','capital_projects','planning_design_construction','procurement','supplier_registration','general_switchboard','business_affairs','project_construction','other')
        or v_channel not in ('phone','email','url','routing_instruction') or nullif(v_value,'') is null then continue; end if;
      -- Generic extraction cannot create VERIFIED DIRECT. Named role-holder routes require a separately reviewed workflow.
      if v_stability='role_holder' then v_stability:='departmental'; end if;
      insert into core.organization_contact_points(
        organization_id,site_name,site_address_text,department_name,contact_scope,channel_type,
        contact_value,label,stability_class,source_url,source_authority,observed_on,verify_after,
        confidence,is_primary,routing_note,attributes,updated_at
      ) values(v_org_id,nullif(v_route->>'site_name',''),nullif(v_route->>'site_address_text',''),
        nullif(v_route->>'department_name',''),v_scope,v_channel,v_value,nullif(v_route->>'label',''),
        v_stability,v_item->>'source_url',coalesce(nullif(v_item->>'source_authority',''),'Public web source'),
        current_date,current_date+case when v_stability='institutional' then 730 else 365 end,
        v_conf,false,'Public route extracted by the bounded buyer evidence worker; purchasing authority is not implied.',
        jsonb_build_object('document_evidence_job_id',v_job.id,'finding_fingerprint',v_item->>'fingerprint',
          'contact_trust_guardrail','public_unverified_unless_separately_supported','media_retained',false),now())
      on conflict do nothing;
      update core.organization_contact_points set source_url=v_item->>'source_url',
        source_authority=coalesce(nullif(v_item->>'source_authority',''),'Public web source'),observed_on=current_date,
        verify_after=current_date+case when v_stability='institutional' then 730 else 365 end,
        confidence=least(.89,greatest(confidence,v_conf)),updated_at=now(),
        attributes=attributes||jsonb_build_object('document_evidence_job_id',v_job.id,'finding_fingerprint',v_item->>'fingerprint')
      where organization_id=v_org_id and coalesce(site_name,'')=coalesce(nullif(v_route->>'site_name',''),'')
        and contact_scope=v_scope and channel_type=v_channel and contact_value=v_value;
      v_contact_count:=v_contact_count+1;
    end loop;
  end loop;

  select coalesce(array_agg(candidate_key),'{}'::text[]) into v_candidates
  from research.document_evidence_job_candidates where job_id=v_job.id;
  if v_org_id is not null and (v_contact_count>0 or p_outcome='completed') then
    update scout.opportunity_buyer_identities b set organization_id=v_org_id,
      buyer_name=o.canonical_name,organization_type=o.organization_type,
      resolution_status='organization_resolved',confidence=greatest(b.confidence,.95),
      identity_basis=coalesce(nullif(b.identity_basis,''),'document_evidence_exact_organization'),
      last_normalized_at=now()
    from core.organizations o
    where o.id=v_org_id and b.candidate_key=any(v_candidates)
      and (b.organization_id=v_org_id
        or nullif(v_job.context->>'organization_id','')::uuid=v_org_id
        or public.scout_normalize_business_name(b.buyer_name)=public.scout_normalize_business_name(v_job.organization_name)
        or exists(select 1 from core.organization_aliases a where a.organization_id=v_org_id
          and public.scout_normalize_business_name(a.alias)=public.scout_normalize_business_name(b.buyer_name)));
    v_refresh:=scout.refresh_opportunity_buyer_routes_for_candidates_v1(v_candidates);
    v_projection:=scout.refresh_buyer_projection_for_candidates_v1(v_candidates);
  end if;

  if p_outcome='completed' and (v_org_id is not null or v_contact_count>0) then v_state:='completed'; v_next:=v_job.next_attempt_at;
  elsif p_outcome in ('research_exhausted','needs_review') then
    v_state:=case when p_outcome='needs_review' then 'needs_review' else 'exhausted' end;
    v_next:=v_job.next_attempt_at; v_exhaustion:=coalesce(nullif(p_error,''),'await_new_evidence');
  elsif p_outcome='no_evidence' and v_job.attempt_count>=v_job.max_attempts then
    v_state:='exhausted';v_next:=v_job.next_attempt_at;v_exhaustion:='bounded_research_completed_without_supported_buyer_or_route';
  elsif p_outcome='no_evidence' then v_state:='queued';v_next:=now()+interval '7 days';
  elsif v_job.attempt_count>=v_job.max_attempts then v_state:='exhausted';v_next:=v_job.next_attempt_at;v_exhaustion:='retry_budget_exhausted';
  else v_state:='failed';v_next:=now()+interval '12 hours'; end if;

  update research.document_evidence_jobs set state=v_state,next_attempt_at=v_next,claimed_at=null,lease_until=null,
    completed_at=case when v_state in ('completed','needs_review','exhausted') then now() else null end,
    last_error=case when p_outcome='failed' then left(p_error,4000) else null end,
    exhaustion_reason=v_exhaustion,
    requery_after=case when v_state='exhausted' then now()+interval '90 days' else null end,
    outcome_metadata=jsonb_build_object('organization_id',v_org_id,'findings',v_finding_count,
      'contact_routes_upserted',v_contact_count,'refresh',v_refresh,'projection',v_projection),updated_at=now()
  where id=v_job.id;
  update scout.buyer_resolution_queue set state=case when v_state='completed' then state else 'blocked' end,
    attempt_count=attempt_count+1,next_attempt_at=coalesce((select requery_after from research.document_evidence_jobs where id=v_job.id),next_attempt_at),
    last_error=v_exhaustion,updated_at=now()
  where candidate_key=any(v_candidates) and v_state in ('exhausted','needs_review');
  return jsonb_build_object('job_id',v_job.id,'state',v_state,'organization_id',v_org_id,
    'finding_count',v_finding_count,'contact_routes_upserted',v_contact_count,
    'candidate_count',cardinality(v_candidates),'refresh',v_refresh,'projection',v_projection);
end;
$function$;

revoke all on function public.internal_seed_buyer_document_evidence_jobs(integer) from public,anon,authenticated;
revoke all on function public.internal_complete_buyer_document_evidence_job(uuid,text,jsonb,text) from public,anon,authenticated;
revoke all on function scout.refresh_buyer_projection_for_candidates_v1(text[]) from public,anon,authenticated;
revoke all on function scout.refresh_opportunity_buyer_routes_for_candidates_v1(text[]) from public,anon,authenticated;
grant execute on function public.internal_seed_buyer_document_evidence_jobs(integer) to service_role;
grant execute on function public.internal_complete_buyer_document_evidence_job(uuid,text,jsonb,text) to service_role;
grant execute on function scout.refresh_buyer_projection_for_candidates_v1(text[]) to service_role;
grant execute on function scout.refresh_opportunity_buyer_routes_for_candidates_v1(text[]) to service_role;

comment on function public.internal_complete_buyer_document_evidence_job(uuid,text,jsonb,text) is
  'Persists buyer evidence through allowlisted canonical tables. Generic extraction is capped below VERIFIED DIRECT and never creates an organization or guesses purchasing authority.';
