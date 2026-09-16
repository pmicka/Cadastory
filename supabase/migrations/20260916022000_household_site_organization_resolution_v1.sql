-- Phase 3: household-owner fallback.
-- Household owners remain property evidence only. Non-residential sites may be
-- researched by address for a first-party documented site organization.

create table if not exists research.household_site_organization_job_candidates(
  job_id uuid not null references research.document_evidence_jobs(id) on delete cascade,
  candidate_key text not null,
  owner_evidence_id uuid not null references scout.opportunity_responsible_party_evidence(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(job_id,candidate_key)
);
create index if not exists household_site_organization_job_candidates_candidate_idx
  on research.household_site_organization_job_candidates(candidate_key);
alter table research.household_site_organization_job_candidates enable row level security;
revoke all on research.household_site_organization_job_candidates from public,anon,authenticated;

create table if not exists research.household_owner_fallback_deferrals(
  candidate_key text primary key,
  reason text not null check(reason in ('residential_household_no_business_target','no_documented_site_organization','ambiguous_site_organization')),
  source_kind text not null,
  site_address_text text,
  requery_after timestamptz,
  details jsonb not null default '{}'::jsonb check(jsonb_typeof(details)='object'),
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists household_owner_fallback_deferrals_active_idx
  on research.household_owner_fallback_deferrals(reason,requery_after) where resolved_at is null;
alter table research.household_owner_fallback_deferrals enable row level security;
revoke all on research.household_owner_fallback_deferrals from public,anon,authenticated;

create or replace function public.internal_seed_household_site_organization_jobs_v1(p_limit integer default 50)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_jobs integer:=0; v_links integer:=0; v_deferred integer:=0;
begin
  if coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  if p_limit<1 or p_limit>250 then raise exception 'p_limit must be between 1 and 250'; end if;

  create temporary table hh_site_base on commit drop as
  with owners as (
    select e.*,row_number() over(partition by e.candidate_key order by e.confidence desc,e.updated_at desc,e.id) rn
    from scout.opportunity_responsible_party_evidence e
    where e.party_role='property_owner' and e.party_kind='person_or_household' and e.confidence>=.95
  )
  select e.candidate_key,e.id owner_evidence_id,q.source_kind,q.priority,q.address_hint,
         s.state_code,s.county_name,s.primary_service_slug,
         case when q.source_kind='construction_window' then p.project_type end project_type,
         coalesce(nullif(s.details->>'city',''),nullif(rr.raw_payload->>'CITY','')) city,
         scout.normalize_address_key_v2(q.address_hint) address_key
  from owners e
  join scout.buyer_resolution_queue q using(candidate_key)
  join scout.opportunity_search_spine s using(candidate_key)
  left join intelligence.construction_service_windows w
    on q.source_kind='construction_window' and w.id=split_part(e.candidate_key,':',2)::uuid
  left join intelligence.construction_projects p on p.id=w.project_id
  left join ingest.raw_records rr on rr.id=p.origin_source_record_id
  where e.rn=1 and q.state in ('pending','researching')
    and q.missing_steps @> array['organization_resolution']::text[]
    and nullif(btrim(q.buyer_hint),'') is null and coalesce(s.global_suppressed,false)=false
    and q.source_kind in ('construction_window','exterior_cleaning','roof_lifecycle')
    and scout.normalize_address_key_v2(q.address_hint)<>''
    and not exists(
      select 1 from scout.opportunity_responsible_party_evidence x
      where x.candidate_key=e.candidate_key and x.party_kind='organization'
        and x.party_role in ('property_manager','operator','permit_contractor','project_owner')
        and x.evidence_class in ('authoritative_record','documented','corroborated') and x.confidence>=.95
    );

  insert into research.household_owner_fallback_deferrals(candidate_key,reason,source_kind,site_address_text,requery_after,details,resolved_at,updated_at)
  select candidate_key,'residential_household_no_business_target',source_kind,address_hint,now()+interval '90 days',
         jsonb_build_object('project_type',project_type,'owner_identity_not_researched',true,'global_buyer_queue_not_blocked',true,'outbound_contact_performed',false),null,now()
  from hh_site_base where source_kind='construction_window' and coalesce(project_type,'') ilike 'Residential %'
  on conflict(candidate_key) do update set reason=excluded.reason,source_kind=excluded.source_kind,
    site_address_text=excluded.site_address_text,requery_after=excluded.requery_after,details=excluded.details,resolved_at=null,updated_at=now();
  get diagnostics v_deferred=row_count;

  create temporary table hh_site_seed on commit drop as
  with eligible as (
    select b.* from hh_site_base b
    where not (b.source_kind='construction_window' and coalesce(b.project_type,'') ilike 'Residential %')
      and not exists(
        select 1 from research.household_owner_fallback_deferrals d
        where d.candidate_key=b.candidate_key and d.resolved_at is null
          and d.reason in ('no_documented_site_organization','ambiguous_site_organization')
          and d.requery_after>now()
      )
  )
  select state_code,address_key,'household-site:'||lower(coalesce(state_code,''))||':'||address_key cluster_key,
         max(address_hint) site_address_text,max(city) city,max(county_name) county_name,max(priority) queue_priority,
         array_agg(candidate_key order by priority desc,candidate_key) candidate_keys,
         array_agg(owner_evidence_id order by candidate_key) owner_evidence_ids,
         array_agg(distinct source_kind order by source_kind) source_kinds,
         array_agg(distinct primary_service_slug) filter(where primary_service_slug is not null) service_slugs,
         md5(concat_ws('|',state_code,address_key,count(*)::text,max(priority)::text,string_agg(candidate_key,',' order by candidate_key))) input_fingerprint
  from eligible group by state_code,address_key order by max(priority) desc,count(*) desc,address_key limit p_limit;

  insert into research.document_evidence_jobs(
    rule_pack,subject_type,subject_id,subject_key,cluster_key,input_fingerprint,display_name,organization_name,
    priority,max_attempts,search_query,source_roots,context,updated_at
  )
  select 'household_site_organization_v1','site_address',
    (substr(md5(cluster_key),1,8)||'-'||substr(md5(cluster_key),9,4)||'-'||substr(md5(cluster_key),13,4)||'-'||substr(md5(cluster_key),17,4)||'-'||substr(md5(cluster_key),21,12))::uuid,
    cluster_key,cluster_key,input_fingerprint,site_address_text,null,
    (-7000-(queue_priority*25)-least(cardinality(candidate_keys),20)*20)::integer,2,
    concat('"',site_address_text,'" ',coalesce(city,''),' ',coalesce(state_code,''),' official organization business school church government location'),
    '[]'::jsonb,
    jsonb_build_object('research_domain','household_site_organization','site_address_text',site_address_text,'address_key',address_key,
      'city',city,'state_code',state_code,'county_name',county_name,'candidate_keys',to_jsonb(candidate_keys),
      'source_kinds',to_jsonb(source_kinds),'service_slugs',to_jsonb(service_slugs),'identity_projection','suppressed',
      'responsibility_role','operator','property_owner_is_person_or_household',true,'owner_identity_not_researched',true,
      'buyer_authority_not_implied',true,'ownership_not_implied',true,'property_management_not_implied',true,
      'outbound_contact_performed',false,'guardrails',jsonb_build_array('exact_first_party_site_address_required',
      'person_or_household_owner_must_not_be_searched_or_contacted','site_operator_is_not_automatically_the_buyer',
      'tenant_or_occupant_does_not_imply_exterior_maintenance_authority','do_not_project_operator_identity_into_buyer_resolution','do_not_infer_personal_email')),now()
  from hh_site_seed
  on conflict(rule_pack,subject_type,subject_id) do update set
    input_fingerprint=excluded.input_fingerprint,display_name=excluded.display_name,priority=excluded.priority,
    search_query=excluded.search_query,context=excluded.context,updated_at=now(),
    state=case when research.document_evidence_jobs.input_fingerprint is distinct from excluded.input_fingerprint
                    and research.document_evidence_jobs.state in ('exhausted','failed','needs_review') then 'queued'
               when research.document_evidence_jobs.state='exhausted' and research.document_evidence_jobs.requery_after<=now() then 'queued'
               else research.document_evidence_jobs.state end,
    attempt_count=case when research.document_evidence_jobs.input_fingerprint is distinct from excluded.input_fingerprint
                            or (research.document_evidence_jobs.state='exhausted' and research.document_evidence_jobs.requery_after<=now()) then 0
                       else research.document_evidence_jobs.attempt_count end,
    completed_at=case when research.document_evidence_jobs.input_fingerprint is distinct from excluded.input_fingerprint then null else research.document_evidence_jobs.completed_at end,
    exhaustion_reason=case when research.document_evidence_jobs.input_fingerprint is distinct from excluded.input_fingerprint then null else research.document_evidence_jobs.exhaustion_reason end,
    requery_after=case when research.document_evidence_jobs.input_fingerprint is distinct from excluded.input_fingerprint then null else research.document_evidence_jobs.requery_after end;
  get diagnostics v_jobs=row_count;

  insert into research.household_site_organization_job_candidates(job_id,candidate_key,owner_evidence_id,updated_at)
  select j.id,b.candidate_key,b.owner_evidence_id,now()
  from hh_site_seed c
  join research.document_evidence_jobs j on j.rule_pack='household_site_organization_v1' and j.subject_type='site_address' and j.cluster_key=c.cluster_key
  join hh_site_base b on b.candidate_key=any(c.candidate_keys)
  on conflict(job_id,candidate_key) do update set owner_evidence_id=excluded.owner_evidence_id,updated_at=now();
  get diagnostics v_links=row_count;

  return jsonb_build_object('jobs_upserted',v_jobs,'candidate_links_upserted',v_links,'residential_deferrals_upserted',v_deferred,
    'eligible_address_clusters',(select count(*) from hh_site_seed),'eligible_candidates',(select coalesce(sum(cardinality(candidate_keys)),0) from hh_site_seed));
end $$;
revoke all on function public.internal_seed_household_site_organization_jobs_v1(integer) from public,anon,authenticated;
grant execute on function public.internal_seed_household_site_organization_jobs_v1(integer) to service_role;

create or replace function public.internal_claim_household_site_organization_jobs_v1(p_limit integer default 4,p_search_available boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_result jsonb;
begin
  if coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  if p_limit<1 or p_limit>8 then raise exception 'p_limit must be between 1 and 8'; end if;
  update research.document_evidence_jobs set state='queued',claimed_at=null,lease_until=null,
    last_error=concat_ws(E'\n',nullif(last_error,''),'claim lease expired'),updated_at=now()
    where rule_pack='household_site_organization_v1' and state='claimed' and lease_until<now();
  update research.document_evidence_jobs set state='exhausted',completed_at=coalesce(completed_at,now()),
    exhaustion_reason=coalesce(exhaustion_reason,'retry_budget_exhausted'),requery_after=coalesce(requery_after,now()+interval '90 days'),updated_at=now()
    where rule_pack='household_site_organization_v1' and state in ('queued','failed') and attempt_count>=max_attempts;
  with picked as (
    select id from research.document_evidence_jobs
    where rule_pack='household_site_organization_v1' and state in ('queued','failed') and attempt_count<max_attempts
      and next_attempt_at<=now() and context->>'identity_projection'='suppressed'
      and coalesce((context->>'owner_identity_not_researched')::boolean,false)=true and p_search_available
    order by priority,next_attempt_at,created_at for update skip locked limit p_limit
  ), claimed as (
    update research.document_evidence_jobs j set state='claimed',attempt_count=j.attempt_count+1,claimed_at=now(),
      lease_until=now()+interval '30 minutes',last_error=null,updated_at=now() from picked where j.id=picked.id returning j.*
  )
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'display_name',display_name,'priority',priority,'attempt_count',attempt_count,
    'max_attempts',max_attempts,'search_query',search_query,'context',context) order by priority,created_at),'[]'::jsonb)
  into v_result from claimed;
  return v_result;
end $$;
revoke all on function public.internal_claim_household_site_organization_jobs_v1(integer,boolean) from public,anon,authenticated;
grant execute on function public.internal_claim_household_site_organization_jobs_v1(integer,boolean) to service_role;

create or replace function public.internal_complete_household_site_organization_job_v1(
  p_job_id uuid,p_outcome text,p_organization_name text default null,p_website_url text default null,
  p_source_url text default null,p_source_authority text default null,p_identity_confidence numeric default null,
  p_evidence_excerpt text default null,p_attributes jsonb default '{}'::jsonb,p_error text default null
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_job research.document_evidence_jobs%rowtype; v_org_id uuid; v_matches integer:=0; v_norm text;
  v_candidates text[]; v_evidence integer:=0; v_state text; v_reason text; v_requery timestamptz;
begin
  if coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  if p_outcome not in ('completed','no_evidence','needs_review','failed') then raise exception 'invalid outcome'; end if;
  if jsonb_typeof(coalesce(p_attributes,'{}'::jsonb))<>'object' then raise exception 'p_attributes must be object'; end if;
  select * into v_job from research.document_evidence_jobs where id=p_job_id for update;
  if not found or v_job.rule_pack<>'household_site_organization_v1' or v_job.state<>'claimed' then raise exception 'claimed household site organization job required'; end if;
  select coalesce(array_agg(candidate_key order by candidate_key),'{}'::text[]) into v_candidates
    from research.household_site_organization_job_candidates where job_id=v_job.id;

  if p_outcome='completed' then
    if nullif(btrim(p_organization_name),'') is null or coalesce(p_identity_confidence,0)<.95 then raise exception 'high-confidence organization identity required'; end if;
    if p_website_url !~ '^https?://' or p_source_url !~ '^https?://' then raise exception 'website/source URLs required'; end if;
    if coalesce(p_attributes->>'address_match_basis','')<>'exact_first_party_structured_address' then raise exception 'exact first-party structured address match required'; end if;
    v_norm:=public.scout_normalize_business_name(p_organization_name);
    if nullif(v_norm,'') is null then raise exception 'invalid organization name'; end if;
    perform pg_advisory_xact_lock(hashtextextended('household-site-org:'||v_norm,0));
    with m as (
      select o.id from core.organizations o where o.status='active' and public.scout_normalize_business_name(o.canonical_name)=v_norm
      union select a.organization_id from core.organization_aliases a join core.organizations o on o.id=a.organization_id and o.status='active'
        where public.scout_normalize_business_name(a.alias)=v_norm
    ) select count(*),(array_agg(id order by id))[1] into v_matches,v_org_id from m;
    if v_matches>1 then p_outcome:='needs_review'; p_error:='multiple existing organizations match exact-address site identity';
    else
      if v_matches=0 then
        insert into core.organizations(canonical_name,normalized_name,status,website_url,attributes,updated_at)
        values(btrim(p_organization_name),v_norm,'active',p_website_url,
          jsonb_build_object('identity_source','household_site_exact_address_first_party','identity_source_url',p_source_url,
            'identity_confidence',least(1,greatest(.95,p_identity_confidence)),'identity_scope','site_operator_candidate',
            'buyer_authority_not_implied',true,'property_owner_not_implied',true,'property_manager_not_implied',true,'outbound_contact_performed',false),now())
        returning id into v_org_id;
      else
        update core.organizations set website_url=coalesce(website_url,p_website_url),updated_at=now() where id=v_org_id;
      end if;
      insert into scout.opportunity_responsible_party_evidence(candidate_key,party_role,party_name,party_name_normalized,party_kind,organization_id,
        site_address_text,evidence_class,confidence,source_url,source_authority,observed_on,attributes,updated_at)
      select l.candidate_key,'operator',btrim(p_organization_name),v_norm,'organization',v_org_id,v_job.context->>'site_address_text','documented',
        least(.99,greatest(.95,p_identity_confidence)),p_source_url,coalesce(nullif(p_source_authority,''),'First-party organization site'),current_date,
        coalesce(p_attributes,'{}'::jsonb)||jsonb_build_object('resolution_scope','household_owner_fallback','match_basis','exact_first_party_structured_address',
          'owner_identity_not_researched',true,'buyer_authority_not_implied',true,'ownership_not_implied',true,'property_manager_not_implied',true,
          'operator_identity_only',true,'outbound_contact_performed',false,'document_evidence_job_id',v_job.id),now()
      from research.household_site_organization_job_candidates l where l.job_id=v_job.id
      on conflict(candidate_key,party_role,party_name_normalized,source_url) do update set organization_id=excluded.organization_id,
        confidence=greatest(scout.opportunity_responsible_party_evidence.confidence,excluded.confidence),attributes=excluded.attributes,updated_at=now();
      get diagnostics v_evidence=row_count;
      update research.household_owner_fallback_deferrals set resolved_at=now(),updated_at=now() where candidate_key=any(v_candidates) and resolved_at is null;
    end if;
  end if;

  if p_outcome='completed' then v_state:='completed';v_reason:=null;v_requery:=null;
  elsif p_outcome='needs_review' then v_state:='needs_review';v_reason:=coalesce(nullif(p_error,''),'ambiguous_site_organization');v_requery:=now()+interval '90 days';
  elsif p_outcome='no_evidence' and v_job.attempt_count>=v_job.max_attempts then v_state:='exhausted';v_reason:='no_documented_site_organization';v_requery:=now()+interval '90 days';
  elsif p_outcome='no_evidence' then v_state:='queued';v_reason:=null;v_requery:=null;
  elsif v_job.attempt_count>=v_job.max_attempts then v_state:='exhausted';v_reason:='retry_budget_exhausted';v_requery:=now()+interval '90 days';
  else v_state:='failed';v_reason:=null;v_requery:=null; end if;

  if v_state in ('needs_review','exhausted') then
    insert into research.household_owner_fallback_deferrals(candidate_key,reason,source_kind,site_address_text,requery_after,details,resolved_at,updated_at)
    select l.candidate_key,case when v_state='needs_review' then 'ambiguous_site_organization' else 'no_documented_site_organization' end,
      q.source_kind,q.address_hint,v_requery,jsonb_build_object('document_evidence_job_id',v_job.id,'reason_detail',v_reason,
      'owner_identity_not_researched',true,'global_buyer_queue_not_blocked',true,'outbound_contact_performed',false),null,now()
    from research.household_site_organization_job_candidates l join scout.buyer_resolution_queue q using(candidate_key) where l.job_id=v_job.id
    on conflict(candidate_key) do update set reason=excluded.reason,requery_after=excluded.requery_after,details=excluded.details,resolved_at=null,updated_at=now();
  end if;

  update research.document_evidence_jobs set state=v_state,next_attempt_at=case when v_state='queued' then now()+interval '14 days' else next_attempt_at end,
    claimed_at=null,lease_until=null,completed_at=case when v_state in ('completed','needs_review','exhausted') then now() else null end,
    last_error=case when p_outcome='failed' then left(p_error,4000) else null end,exhaustion_reason=v_reason,requery_after=v_requery,
    organization_name=case when v_org_id is not null then btrim(p_organization_name) else organization_name end,
    context=case when v_org_id is not null then jsonb_set(jsonb_set(context,'{organization_id}',to_jsonb(v_org_id::text),true),'{organization_name}',to_jsonb(btrim(p_organization_name)),true) else context end,
    outcome_metadata=coalesce(outcome_metadata,'{}'::jsonb)||jsonb_strip_nulls(jsonb_build_object('organization_id',v_org_id,'operator_evidence_upserted',v_evidence,
      'identity_projection','suppressed','buyer_authority_not_implied',true,'outbound_contact_performed',false,'evidence_excerpt',left(p_evidence_excerpt,1000))),updated_at=now()
  where id=v_job.id;
  return jsonb_build_object('job_id',v_job.id,'state',v_state,'organization_id',v_org_id,'candidate_count',cardinality(v_candidates),
    'operator_evidence_upserted',v_evidence,'identity_projection','suppressed','buyer_authority_not_implied',true,'outbound_contact_performed',false);
end $$;
revoke all on function public.internal_complete_household_site_organization_job_v1(uuid,text,text,text,text,text,numeric,text,jsonb,text) from public,anon,authenticated;
grant execute on function public.internal_complete_household_site_organization_job_v1(uuid,text,text,text,text,text,numeric,text,jsonb,text) to service_role;

insert into ingest.collector_routes(slug,enabled,allow_dispatch,updated_at)
values('collect-household-site-organization-evidence',true,true,now())
on conflict(slug) do update set enabled=true,allow_dispatch=true,updated_at=now();

do $$ declare v_bad integer; begin
  select count(*) into v_bad from research.document_evidence_jobs j join research.document_evidence_job_candidates jc on jc.job_id=j.id
  where j.rule_pack='household_site_organization_v1';
  if v_bad<>0 then raise exception 'household site organization jobs entered buyer projection links'; end if;
end $$;