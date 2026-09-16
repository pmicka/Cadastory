-- Phase 2: exceptional research-job triage.
-- Preserve evidence provenance while preventing person-name construction research,
-- removing unsafe legacy route artifacts, and assigning explicit dispositions.

create or replace function research.guard_person_named_construction_research_v1()
returns trigger
language plpgsql
set search_path=''
as $$
begin
  if new.rule_pack='buyer_organization_contact_v1'
     and new.subject_type='buyer_cluster'
     and new.subject_key like 'named-party:%'
     and nullif(new.context->>'organization_id','') is null
     and coalesce(new.context->'source_kinds','[]'::jsonb) ? 'construction_window'
     and coalesce(new.context->'known_roles','[]'::jsonb) ? 'owner_gc_or_project_team'
     and scout.classify_responsible_party_name_v1(new.organization_name)='person_or_household'
     and new.state in ('queued','failed','claimed') then
    new.state:='needs_review';
    new.completed_at:=coalesce(new.completed_at,now());
    new.claimed_at:=null;
    new.lease_until:=null;
    new.last_error:=null;
    new.exhaustion_reason:=coalesce(
      new.exhaustion_reason,
      'Named individual is not a buyer organization. Resolve the project company/owner/GC upstream; do not research or contact the individual.'
    );
    new.context:=coalesce(new.context,'{}'::jsonb)||jsonb_build_object(
      'research_guard','named_person_requires_upstream_organization_resolution',
      'outbound_contact_performed',false
    );
  end if;
  return new;
end
$$;

revoke all on function research.guard_person_named_construction_research_v1()
  from public,anon,authenticated;

do $$
begin
  if not exists (
    select 1 from pg_trigger
    where tgname='trg_guard_person_named_construction_research_v1'
      and tgrelid='research.document_evidence_jobs'::regclass
  ) then
    execute 'create trigger trg_guard_person_named_construction_research_v1
      before insert or update on research.document_evidence_jobs
      for each row execute function research.guard_person_named_construction_research_v1()';
  end if;
end
$$;

-- Redact the single legacy credential-like query string retained in evidence provenance.
update research.document_evidence_findings
set source_url=regexp_replace(
      source_url,
      '([?&](api_key|key|token|access_token|auth|authorization)=)[^&]+',
      E'\\1[REDACTED]',
      'gi'
    ),
    extracted_values=coalesce(extracted_values,'{}'::jsonb)||jsonb_build_object(
      'triage_provenance_cleanup','credential_like_query_parameter_redacted'
    )
where source_url ~* '[?&](api_key|key|token|access_token|auth|authorization)=';

-- Remove the legacy placeholder phone value while retaining the underlying identity evidence.
update research.document_evidence_findings f
set extracted_values=(
      case
        when jsonb_typeof(coalesce(f.extracted_values->'contact_routes','[]'::jsonb))='array' then
          jsonb_set(
            coalesce(f.extracted_values,'{}'::jsonb),
            '{contact_routes}',
            coalesce((
              select jsonb_agg(r.value)
              from jsonb_array_elements(coalesce(f.extracted_values->'contact_routes','[]'::jsonb)) r(value)
              where regexp_replace(coalesce(r.value->>'contact_value',''),'\D','','g')<>'5554567890'
            ),'[]'::jsonb),
            true
          )
        else coalesce(f.extracted_values,'{}'::jsonb)
      end
    )||jsonb_build_object('triage_contact_route_cleanup','removed_placeholder_phone_5554567890'),
    auto_applied=false
where f.extracted_values::text like '%5554567890%';

-- Person-name construction evidence from the retired broad web-research pass is not
-- organization identity evidence. Preserve the rows but quarantine their decision value.
update research.document_evidence_findings f
set decision_state='unknown',
    identity_confidence=least(identity_confidence,.45),
    auto_applied=false,
    extracted_values=coalesce(extracted_values,'{}'::jsonb)||jsonb_build_object(
      'triage_disposition','legacy_person_name_not_organization_evidence'
    )
from research.document_evidence_jobs j
where j.id=f.job_id
  and j.rule_pack='buyer_organization_contact_v1'
  and j.subject_key='named-party:daniel gregory';

-- The Smith Farms legacy pass matched unrelated similarly named businesses. Retain the
-- research trail, but remove those pages from decision-grade identity evidence.
update research.document_evidence_findings f
set decision_state='unknown',
    identity_confidence=least(identity_confidence,.45),
    auto_applied=false,
    extracted_values=coalesce(extracted_values,'{}'::jsonb)||jsonb_build_object(
      'triage_disposition','name_collision_not_authoritative_farm_identity'
    )
from research.document_evidence_jobs j
where j.id=f.job_id
  and j.subject_key='agriculture:farm-source:b1ea4f90-ec18-4fa6-ae8e-2f5918c40e70'
  and f.source_url !~* '(^|\\.)kyagr\\.com/'
  and f.source_url !~* 'smithberrywinery\\.com';

-- Construction person names require upstream company/project-party resolution, not
-- another person-oriented web search. Leave the global buyer queue pending so other
-- upstream resolvers can continue working these opportunities.
update research.document_evidence_jobs
set state='needs_review',
    completed_at=now(),
    claimed_at=null,
    lease_until=null,
    last_error=null,
    exhaustion_reason='Named individual is not a buyer organization. Resolve the project company/owner/GC upstream; do not research or contact the individual.',
    context=coalesce(context,'{}'::jsonb)||jsonb_build_object(
      'triage_disposition','upstream_project_organization_resolution_required',
      'outbound_contact_performed',false
    ),
    updated_at=now()
where rule_pack='buyer_organization_contact_v1'
  and subject_key='named-party:daniel gregory';

update research.document_evidence_jobs
set context=coalesce(context,'{}'::jsonb)||jsonb_build_object(
      'triage_disposition','ambiguous_person_affiliation_requires_project_link',
      'outbound_contact_performed',false
    ),
    updated_at=now()
where rule_pack='buyer_organization_contact_v1'
  and subject_key='named-party:bill wilkinson';

-- Agricultural directory evidence identifies a farm business/contact surface, but the
-- current operator/customer/purchasing role is not independently corroborated. Park
-- these jobs for operator-resolution evidence rather than repeating generic web search.
update research.document_evidence_jobs
set state='needs_review',
    completed_at=now(),
    claimed_at=null,
    lease_until=null,
    last_error=null,
    exhaustion_reason='Authoritative farm-directory identity/contact is present, but current operator/customer/purchasing authority is not independently corroborated. Await operator-resolution evidence; do not infer personal outreach.',
    context=coalesce(context,'{}'::jsonb)||jsonb_build_object(
      'triage_disposition','farm_identity_documented_operator_role_unresolved',
      'outbound_contact_performed',false
    ),
    updated_at=now()
where rule_pack='buyer_organization_contact_v1'
  and context->>'research_domain'='agriculture'
  and state='failed';

-- Water-tank morphology remains genuinely ambiguous: system-level engineering documents
-- contain morphology terms that cannot safely be assigned to the exact tank.
update research.document_evidence_jobs
set exhaustion_reason='System-level engineering documents contain conflicting morphology terms that cannot be safely attributed to the exact Cub Run tank. Manual/visual confirmation is required.',
    context=coalesce(context,'{}'::jsonb)||jsonb_build_object('triage_disposition','exact_tank_morphology_ambiguous'),
    updated_at=now()
where rule_pack='water_tank_morphology_v1'
  and subject_key='007416C29B5D008677812CC09E000021'
  and state='needs_review';

update research.document_evidence_jobs
set exhaustion_reason='System-level engineering documents contain conflicting standpipe/ground-storage/bracing language that cannot be safely attributed to the exact Montgomery Ln tank. Manual/visual confirmation is required.',
    context=coalesce(context,'{}'::jsonb)||jsonb_build_object('triage_disposition','exact_tank_morphology_ambiguous'),
    updated_at=now()
where rule_pack='water_tank_morphology_v1'
  and subject_key='007416C29B5D0086C7817E8826000664'
  and state='needs_review';

-- Daviess County Public Works: current first-party county bid documents route contracts
-- through Daviess County Fiscal Court Purchasing / Current Bid Documents.
do $$
declare
  v_org_id uuid;
  v_count integer;
  v_job_id uuid;
  v_candidates text[];
begin
  select count(*),(array_agg(id order by id))[1]
    into v_count,v_org_id
  from core.organizations
  where status='active'
    and public.scout_normalize_business_name(canonical_name)=public.scout_normalize_business_name('Daviess County Public Works');
  if v_count<>1 then
    raise exception 'expected exactly one Daviess County Public Works organization, found %',v_count;
  end if;

  insert into core.organization_contact_points(
    organization_id,department_name,contact_scope,channel_type,contact_value,label,
    stability_class,source_url,source_authority,observed_on,verify_after,confidence,
    is_primary,routing_note,attributes,updated_at
  )
  select v_org_id,'Daviess County Fiscal Court Purchasing','procurement','url',
    'https://www.daviessky.org/transparency/','Current Bid Documents','institutional',
    'https://www.daviessky.org/wp-content/uploads/2026/06/Bid-No.-2526-77-Aluminum-Box-Culvert-Road-PE-Signed.pdf',
    'Daviess County Fiscal Court current bid document',current_date,current_date+365,.99,false,
    'Use Daviess County Fiscal Court Current Bid Documents for county procurements. Purchasing authority is not implied for Public Works staff.',
    jsonb_build_object('phase2_exception_triage',true,'buyer_authority_not_implied',true,'outbound_contact_performed',false),
    now()
  where not exists (
    select 1 from core.organization_contact_points cp
    where cp.organization_id=v_org_id
      and cp.contact_scope='procurement'
      and cp.channel_type='url'
      and cp.contact_value='https://www.daviessky.org/transparency/'
  );

  select id into v_job_id
  from research.document_evidence_jobs
  where rule_pack='buyer_organization_contact_v1'
    and subject_key='organization:e6b3a1b2-34cd-4c12-8d5d-b984ccf53d7e';
  if v_job_id is null then raise exception 'Daviess buyer research job not found'; end if;

  update research.document_evidence_jobs
  set state='completed',completed_at=now(),claimed_at=null,lease_until=null,last_error=null,
      exhaustion_reason=null,
      outcome_metadata=coalesce(outcome_metadata,'{}'::jsonb)||jsonb_build_object(
        'phase2_triage','completed_from_current_first_party_county_procurement_route',
        'buyer_authority_not_implied',true,
        'outbound_contact_performed',false
      ),updated_at=now()
  where id=v_job_id;

  select coalesce(array_agg(candidate_key),'{}'::text[]) into v_candidates
  from research.document_evidence_job_candidates where job_id=v_job_id;
  perform scout.refresh_opportunity_buyer_routes_for_candidates_v1(v_candidates);
  perform scout.refresh_buyer_projection_for_candidates_v1(v_candidates);
end
$$;

-- Louisville & Indiana Railroad: Anacostia Rail Holdings' current first-party LIRC pages
-- establish the railroad identity and publish a stable general contact route.
do $$
declare
  v_org_id uuid;
  v_count integer;
  v_job_id uuid;
  v_candidates text[];
begin
  select count(*),(array_agg(id order by id))[1]
    into v_count,v_org_id
  from core.organizations
  where status='active'
    and public.scout_normalize_business_name(canonical_name)=public.scout_normalize_business_name('Louisville & Indiana Railroad Company');

  if v_count=0 then
    insert into core.organizations(
      canonical_name,normalized_name,organization_type,status,website_url,phone,attributes,updated_at
    ) values (
      'Louisville & Indiana Railroad Company',
      public.scout_normalize_business_name('Louisville & Indiana Railroad Company'),
      'railroad','active','https://www.anacostia.com/our-companies/lirc/','(812) 406-4581',
      jsonb_build_object(
        'identity_source','Anacostia Rail Holdings official LIRC profile',
        'identity_source_url','https://www.anacostia.com/our-companies/lirc/',
        'identity_confidence',.99,
        'buyer_authority_not_implied',true,
        'outbound_contact_performed',false
      ),now()
    ) returning id into v_org_id;
  elsif v_count>1 then
    raise exception 'multiple Louisville & Indiana Railroad Company organizations found';
  end if;

  insert into core.organization_contact_points(
    organization_id,contact_scope,channel_type,contact_value,label,stability_class,
    source_url,source_authority,observed_on,verify_after,confidence,is_primary,routing_note,attributes,updated_at
  )
  select v_org_id,'general_switchboard','phone','(812) 406-4581','General Inquiries','institutional',
    'https://www.anacostia.com/contact-us/','Anacostia Rail Holdings official contact page',
    current_date,current_date+730,.99,false,
    'Published Louisville & Indiana Railroad general-inquiries number. Purchasing authority is not implied.',
    jsonb_build_object('phase2_exception_triage',true,'buyer_authority_not_implied',true,'outbound_contact_performed',false),now()
  where not exists (
    select 1 from core.organization_contact_points cp
    where cp.organization_id=v_org_id and cp.contact_scope='general_switchboard'
      and cp.channel_type='phone' and regexp_replace(cp.contact_value,'\D','','g')='8124064581'
  );

  insert into core.organization_contact_points(
    organization_id,department_name,contact_scope,channel_type,contact_value,label,stability_class,
    source_url,source_authority,observed_on,verify_after,confidence,is_primary,routing_note,attributes,updated_at
  )
  select v_org_id,'Permitting / Right-of-Entry','facility_operations','url','https://omegarail.com/permitting',
    'Permitting / Right-of-Entry Requests','institutional','https://www.anacostia.com/contact-us/',
    'Anacostia Rail Holdings official contact page',current_date,current_date+730,.96,false,
    'Official LIRC page routes permitting/right-of-entry requests through Omega Rail. This is an access route, not a procurement or purchasing-authority claim.',
    jsonb_build_object('phase2_exception_triage',true,'buyer_authority_not_implied',true,'route_role','right_of_entry','outbound_contact_performed',false),now()
  where not exists (
    select 1 from core.organization_contact_points cp
    where cp.organization_id=v_org_id and cp.contact_scope='facility_operations'
      and cp.channel_type='url' and cp.contact_value='https://omegarail.com/permitting'
  );

  select id into v_job_id
  from research.document_evidence_jobs
  where rule_pack='buyer_organization_contact_v1'
    and subject_key='named-party:louisville and indiana railroad';
  if v_job_id is null then raise exception 'LIRC buyer research job not found'; end if;

  update research.document_evidence_jobs
  set organization_name='Louisville & Indiana Railroad Company',
      source_roots=(select coalesce(jsonb_agg(x order by x),'[]'::jsonb)
                    from (select distinct value x from jsonb_array_elements_text(
                      coalesce(source_roots,'[]'::jsonb)||jsonb_build_array(
                        'https://www.anacostia.com/our-companies/lirc/',
                        'https://www.anacostia.com/contact-us/'
                      ))) d),
      context=jsonb_set(jsonb_set(coalesce(context,'{}'::jsonb),'{organization_id}',to_jsonb(v_org_id::text),true),
                        '{organization_name}',to_jsonb('Louisville & Indiana Railroad Company'::text),true)
              ||jsonb_build_object('triage_disposition','first_party_identity_and_contact_route_documented','outbound_contact_performed',false),
      state='completed',completed_at=now(),claimed_at=null,lease_until=null,last_error=null,exhaustion_reason=null,
      outcome_metadata=coalesce(outcome_metadata,'{}'::jsonb)||jsonb_build_object(
        'phase2_triage','completed_from_current_first_party_lirc_route',
        'organization_id',v_org_id,
        'buyer_authority_not_implied',true,
        'outbound_contact_performed',false
      ),updated_at=now()
  where id=v_job_id;

  update scout.opportunity_buyer_identities b
  set organization_id=v_org_id,
      buyer_name='Louisville & Indiana Railroad Company',
      resolution_status='organization_resolved',
      confidence=greatest(b.confidence,.99),
      identity_basis='first_party_parent_company_lirc_profile',
      last_normalized_at=now()
  where b.candidate_key in (
    select candidate_key from research.document_evidence_job_candidates where job_id=v_job_id
  ) and (b.organization_id is null or b.organization_id=v_org_id);

  select coalesce(array_agg(candidate_key),'{}'::text[]) into v_candidates
  from research.document_evidence_job_candidates where job_id=v_job_id;
  perform scout.refresh_opportunity_buyer_routes_for_candidates_v1(v_candidates);
  perform scout.refresh_buyer_projection_for_candidates_v1(v_candidates);
end
$$;

-- Fail closed if the targeted exceptional set or unsafe legacy artifacts remain unexplained.
do $$
declare
  v_failed integer;
  v_placeholder integer;
  v_secretish integer;
begin
  select count(*) into v_failed
  from research.document_evidence_jobs
  where state='failed'
    and (
      subject_key in (
        'named-party:daniel gregory',
        'named-party:louisville and indiana railroad',
        'organization:e6b3a1b2-34cd-4c12-8d5d-b984ccf53d7e'
      )
      or context->>'research_domain'='agriculture'
    );
  if v_failed<>0 then raise exception 'phase2 targeted failed jobs remain: %',v_failed; end if;

  select count(*) into v_placeholder
  from research.document_evidence_findings
  where extracted_values::text like '%5554567890%';
  if v_placeholder<>0 then raise exception 'placeholder phone remains in evidence findings: %',v_placeholder; end if;

  select count(*) into v_secretish
  from research.document_evidence_findings
  where source_url ~* '[?&](api_key|key|token|access_token|auth|authorization)=';
  if v_secretish<>0 then raise exception 'credential-like query parameter remains in evidence provenance: %',v_secretish; end if;
end
$$;