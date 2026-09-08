-- Scout cleaning chemistry evidence resolution v2
--
-- Purpose:
--   * preserve current public manufacturer/regulatory evidence without inferring legality;
--   * distinguish federal registration from an applicable federal exemption;
--   * expose a reusable evidence-resolution queue;
--   * require a mapped, compatible provider rig/fluid route before chemistry execution fit;
--   * keep all numeric chemistry score modifiers at zero until field calibration exists.
--
-- This file is intentionally idempotent and preserves all v1 views.

-- -----------------------------------------------------------------------------
-- Current Citra-Shield claim-conflict evidence
-- -----------------------------------------------------------------------------

with d as (
  insert into knowledge.documents(
    title, document_type, publisher, source_url, authority_tier, review_status,
    attributes, lifecycle_status, canonical_source_key, reviewed_at, updated_at
  ) values (
    'Citra-Shield Data Center Roof Cleaning — No Biocides Claim',
    'manufacturer_product_reference','Citra-Shield',
    'https://citrashield.com/applications/data-center-roof-cleaning/',
    'manufacturer','reviewed',
    jsonb_build_object(
      'captured_on','2026-09-08',
      'current_public_manufacturer_source',true,
      'evidence_role','regulatory_claim_conflict',
      'guardrail','Manufacturer marketing claim only; does not establish FIFRA status, formulation identity, registration, exemption, environmental safety, or product-label authorization.'
    ),
    'reference_only','manufacturer:citra-shield:data-center-roof-cleaning:no-biocides:2026-09-08',now(),now()
  )
  on conflict (canonical_source_key) where canonical_source_key is not null
  do update set title=excluded.title, source_url=excluded.source_url, attributes=excluded.attributes,
                review_status='reviewed', reviewed_at=now(), updated_at=now()
  returning id
), doc as (
  select id from d
  union all
  select id from knowledge.documents
  where canonical_source_key='manufacturer:citra-shield:data-center-roof-cleaning:no-biocides:2026-09-08'
  limit 1
)
insert into knowledge.claims(
  document_id, claim_type, statement, structured_value, source_location,
  applicability, hard_stop, confidence, status, reviewed_at, updated_at
)
select doc.id,'other',
       'A current Citra-Shield data-center roof-cleaning page markets the product as "No Biocides" while separately describing removal of organic matter and use for algae/mildew-related maintenance; this manufacturer statement is recorded as a claim, not as a regulatory determination.',
       jsonb_build_object('manufacturer_claim','no_biocides','current_public_claim',true,'regulatory_status_inferred',false),
       'Current public manufacturer page',
       jsonb_build_object('product_family','Citra-Shield','pilot','citra_shield_chemistry_v1'),
       false,0.98,'active',now(),now()
from doc
where not exists (
  select 1 from knowledge.claims c
  where c.document_id=doc.id
    and c.statement like 'A current Citra-Shield data-center roof-cleaning page markets%'
);

with ids as (
  select
    (select id from knowledge.documents where canonical_source_key='citra-shield:manufacturer:faq:2026-09-08' limit 1) as faq_doc,
    (select id from knowledge.documents where canonical_source_key='manufacturer:citra-shield:data-center-roof-cleaning:no-biocides:2026-09-08' limit 1) as no_biocide_doc,
    (select id from knowledge.documents where canonical_source_key='citra-shield:manufacturer:sds-link-check:2026-09-08' limit 1) as sds_check_doc,
    (select id from knowledge.documents where canonical_source_key='citra-shield:manufacturer:directions:2026-09-08' limit 1) as directions_doc,
    (select id from knowledge.documents where canonical_source_key='epa:fifra:cleaning-product-claims:2026-07-06' limit 1) as epa_doc
)
update cleaning.product_regulatory_assessments a
set evidence_document_id = case
      when a.assessment_kind='current_sds' then ids.sds_check_doc
      when a.assessment_kind='current_label' then ids.directions_doc
      when a.assessment_kind='pesticidal_claim_basis' then ids.faq_doc
      when a.assessment_kind='pesticide_registration' then ids.epa_doc
      else a.evidence_document_id end,
    assessment = case
      when a.assessment_kind='current_sds' then a.assessment || jsonb_build_object(
        'public_manufacturer_sds_link_status','redirects_without_current_sds',
        'historical_sds_available',true,
        'historical_sds_revision','2021-05-18',
        'historical_sds_currentness','unresolved',
        'resolution_required','obtain current variant-specific SDS directly from manufacturer or authoritative distributor',
        'manufacturer_contact_url','https://citrashield.com/contact-us/'
      )
      when a.assessment_kind='current_label' then a.assessment || jsonb_build_object(
        'public_directions_reference_product_label',true,
        'current_authoritative_label_located',false,
        'resolution_required','obtain current variant-specific product label including precautionary, treatment, storage and disposal statements',
        'manufacturer_contact_url','https://citrashield.com/contact-us/'
      )
      when a.assessment_kind='pesticidal_claim_basis' then a.assessment || jsonb_build_object(
        'explicit_prevent_biological_growth_claim_observed',true,
        'preventive_ratio_water_to_concentrate','9:1',
        'current_no_biocides_claim_observed',true,
        'public_claim_conflict_requires_authoritative_resolution',true,
        'no_biocides_evidence_document_id',ids.no_biocide_doc,
        'supporting_source_urls',jsonb_build_array(
          'https://citrashield.com/faq/',
          'https://citrashield.com/applications/data-center-roof-cleaning/',
          'https://www.epa.gov/pesticide-registration/determining-if-cleaning-product-pesticide-under-fifra'
        ),
        'regulatory_interpretation','EPA treats sale/distribution claims that prevent or mitigate pests as pesticidal unless an applicable exemption applies; Scout therefore requires a current registration or exemption basis. This is not a finding of noncompliance.',
        'resolution_required','obtain current label plus EPA registration number, applicable FIFRA exemption/minimum-risk basis, or authoritative written regulatory basis for the current claims'
      )
      when a.assessment_kind='pesticide_registration' then a.assessment || jsonb_build_object(
        'authoritative_search_system','EPA Pesticide Product and Label System (PPLS) / APPRIL',
        'authoritative_search_url','https://ordspub.epa.gov/ords/pesticides/f?p=PPLS:1:',
        'exact_registration_number_established',false,
        'exemption_basis_established',false,
        'resolution_required','resolve exact EPA registration number or applicable federal exemption basis for the current product/claims before pesticidal-use authorization'
      )
      when a.assessment_kind='state_product_registration' and a.jurisdiction_scope='KY' then a.assessment || jsonb_build_object(
        'authoritative_source','Kentucky Department of Agriculture / NPIRS state product data',
        'authoritative_source_url','https://www.kyagr.com/consumer/product-registration.html',
        'npirs_last_update_observed','2026-07-18',
        'resolution_required','resolve exact current Kentucky registration for the exact product identity if pesticidal-use status applies'
      )
      when a.assessment_kind='state_product_registration' and a.jurisdiction_scope='IN' then a.assessment || jsonb_build_object(
        'authoritative_source','Office of Indiana State Chemist / NPIRS state product data',
        'authoritative_source_url','https://oisc.purdue.edu/pesticide/pesticide_products.html',
        'npirs_last_update_observed','2026-07-17',
        'resolution_required','resolve exact current Indiana registration for the exact product identity if pesticidal-use status applies'
      )
      when a.assessment_kind='state_product_registration' and a.jurisdiction_scope='OH' then a.assessment || jsonb_build_object(
        'authoritative_source','Ohio Department of Agriculture Product Registration / Kelly state product data',
        'authoritative_source_url','https://ohioagonline.agri.ohio.gov/',
        'state_rule_note','Ohio requires registration for pesticide products including minimum-risk products distributed in the state.',
        'resolution_required','resolve exact current Ohio registration for the exact product identity if pesticidal-use status applies'
      )
      else a.assessment end,
    reviewed_at=now(), updated_at=now()
from ids
where a.product_id in (
  select id from cleaning.products where slug in (
    'citra-shield-ready-to-use-outdoor-cleaner',
    'citra-shield-concentrate-outdoor-cleaner',
    'citra-shield-exterior-cleaner-treatment'
  )
);

update knowledge.claims c
set structured_value = c.structured_value || jsonb_build_object(
      'explicit_biological_growth_prevention_claim',true,
      'fifra_claim_basis_resolution_required',true,
      'regulatory_authorization_inferred',false
    ),
    updated_at=now()
where c.document_id in (
  select id from knowledge.documents
  where canonical_source_key='citra-shield:manufacturer:faq:2026-09-08'
)
and c.claim_type='performance'
and c.statement like 'Citra-Shield currently claims a 9:1 preventive application%';

update cleaning.products
set attributes = attributes || jsonb_build_object(
      'regulatory_resolution_contact_url','https://citrashield.com/contact-us/',
      'regulatory_resolution_state','blocked_pending_current_label_sds_and_registration_or_exemption_basis',
      'current_public_claim_conflict','prevents_biological_growth_vs_no_biocides',
      'claim_conflict_reviewed_on','2026-09-08'
    ),
    updated_at=now()
where slug in (
  'citra-shield-ready-to-use-outdoor-cleaner',
  'citra-shield-concentrate-outdoor-cleaner',
  'citra-shield-exterior-cleaner-treatment'
);

-- -----------------------------------------------------------------------------
-- Explicit federal exemption path
-- -----------------------------------------------------------------------------

alter table cleaning.product_regulatory_assessments
  drop constraint if exists product_regulatory_assessments_assessment_kind_check;

alter table cleaning.product_regulatory_assessments
  add constraint product_regulatory_assessments_assessment_kind_check
  check (assessment_kind = any (array[
    'current_sds'::text,
    'current_label'::text,
    'pesticidal_claim_basis'::text,
    'pesticide_registration'::text,
    'federal_exemption_basis'::text,
    'state_product_registration'::text,
    'other'::text
  ]));

insert into cleaning.product_regulatory_assessments(
  product_id,jurisdiction_scope,assessment_kind,status,registration_number,
  evidence_document_id,assessment,confidence,reviewed_at,created_at,updated_at
)
select
  p.id,'US_FEDERAL','federal_exemption_basis','not_established',null,
  (select d.id from knowledge.documents d where d.canonical_source_key='epa:fifra:cleaning-product-claims:2026-07-06' limit 1),
  jsonb_build_object(
    'reason','No authoritative federal exemption or minimum-risk basis for the current product identity and current public claims has been established.',
    'authoritative_source','EPA FIFRA cleaning-product claim guidance / PPLS',
    'authoritative_source_url','https://www.epa.gov/pesticide-registration/determining-if-cleaning-product-pesticide-under-fifra',
    'resolution_required','Obtain an authoritative exemption/minimum-risk basis for the exact current product and claims, or resolve an exact EPA registration number.',
    'guardrail','Not established is not a finding that no exemption exists.'
  ),
  0.99,now(),now(),now()
from cleaning.products p
where p.slug in (
  'citra-shield-ready-to-use-outdoor-cleaner',
  'citra-shield-concentrate-outdoor-cleaner',
  'citra-shield-exterior-cleaner-treatment'
)
on conflict (product_id,jurisdiction_scope,assessment_kind) do nothing;

-- -----------------------------------------------------------------------------
-- Regulatory readiness + resolution queue
-- -----------------------------------------------------------------------------

create or replace view cleaning.v_product_regulatory_readiness_v2 as
with a as (
  select
    p.id as product_id,p.slug as product_slug,p.product_name,p.manufacturer_name,
    max(r.status) filter (where r.jurisdiction_scope='US_FEDERAL' and r.assessment_kind='current_sds') as current_sds_status,
    max(r.status) filter (where r.jurisdiction_scope='US_FEDERAL' and r.assessment_kind='current_label') as current_label_status,
    max(r.status) filter (where r.jurisdiction_scope='US_FEDERAL' and r.assessment_kind='pesticidal_claim_basis') as pesticidal_claim_basis_status,
    max(r.status) filter (where r.jurisdiction_scope='US_FEDERAL' and r.assessment_kind='pesticide_registration') as federal_pesticide_registration_status,
    max(r.status) filter (where r.jurisdiction_scope='US_FEDERAL' and r.assessment_kind='federal_exemption_basis') as federal_exemption_basis_status,
    max(r.status) filter (where r.jurisdiction_scope='KY' and r.assessment_kind='state_product_registration') as ky_product_registration_status,
    max(r.status) filter (where r.jurisdiction_scope='IN' and r.assessment_kind='state_product_registration') as in_product_registration_status,
    max(r.status) filter (where r.jurisdiction_scope='OH' and r.assessment_kind='state_product_registration') as oh_product_registration_status,
    bool_or(coalesce((r.assessment->>'public_claim_conflict_requires_authoritative_resolution')::boolean,false)) as public_claim_conflict_requires_authoritative_resolution,
    count(*) filter (where r.status in ('not_established','resolution_required','unknown')) as unresolved_assessment_count,
    max(r.reviewed_at) as regulatory_reviewed_at
  from cleaning.products p
  left join cleaning.product_regulatory_assessments r on r.product_id=p.id
  group by p.id,p.slug,p.product_name,p.manufacturer_name
)
select
  a.*,
  (a.current_sds_status='confirmed' and a.current_label_status='confirmed') as documentation_ready,
  (a.pesticidal_claim_basis_status='not_applicable'
   or a.federal_pesticide_registration_status='confirmed'
   or a.federal_exemption_basis_status='confirmed') as federal_regulatory_ready,
  case
    when a.current_sds_status is distinct from 'confirmed' or a.current_label_status is distinct from 'confirmed' then 'product_documentation_unresolved'
    when a.pesticidal_claim_basis_status in ('resolution_required','not_established','unknown') or a.pesticidal_claim_basis_status is null then 'claim_basis_resolution_required'
    when a.pesticidal_claim_basis_status='not_applicable' then 'non_pesticidal_claim_basis_resolved'
    when a.federal_pesticide_registration_status='confirmed' then 'federal_registration_resolved'
    when a.federal_exemption_basis_status='confirmed' then 'federal_exemption_resolved'
    else 'federal_registration_or_exemption_resolution_required'
  end as federal_resolution_state,
  'Federal readiness can be established by a resolved non-pesticidal claim basis, an exact confirmed EPA registration, or a confirmed applicable federal exemption. These are distinct evidence paths.'::text as guardrail
from a;

create or replace view cleaning.v_product_regulatory_resolution_queue_v1 as
select
  r.id as assessment_id,p.id as product_id,p.slug as product_slug,p.product_name,p.manufacturer_name,
  r.jurisdiction_scope,r.assessment_kind,r.status,r.registration_number,r.confidence,r.reviewed_at,r.evidence_document_id,
  case
    when r.assessment_kind in ('current_sds','current_label','pesticidal_claim_basis','pesticide_registration','federal_exemption_basis') then 'critical'
    when r.assessment_kind='state_product_registration' then 'high'
    else 'normal'
  end as resolution_priority,
  true as blocks_chemistry_fit,
  case r.assessment_kind
    when 'current_sds' then 'Obtain and review the current variant-specific SDS from the manufacturer or an authoritative distributor.'
    when 'current_label' then 'Obtain and review the current variant-specific product label, including precautionary, treatment, storage and disposal statements.'
    when 'pesticidal_claim_basis' then 'Resolve whether the current sale/distribution claims are pesticidal under FIFRA and document the authoritative basis.'
    when 'pesticide_registration' then 'Resolve the exact current EPA registration number in PPLS/APPRIL for the exact product identity, if registered.'
    when 'federal_exemption_basis' then 'Resolve and document any applicable federal exemption/minimum-risk basis for the exact product and current claims.'
    when 'state_product_registration' then 'After federal product identity/claim posture is resolved, verify the exact current state product-registration record.'
    else coalesce(r.assessment->>'resolution_required','Perform evidence resolution.')
  end as next_action,
  coalesce(r.assessment->>'authoritative_source_url',
    case
      when r.assessment_kind in ('pesticide_registration','federal_exemption_basis') then 'https://ordspub.epa.gov/ords/pesticides/f?p=PPLS:1:'
      when r.jurisdiction_scope='KY' then 'https://www.kyagr.com/consumer/product-registration.html'
      when r.jurisdiction_scope='IN' then 'https://oisc.purdue.edu/pesticide/pesticide_products.html'
      when r.jurisdiction_scope='OH' then 'https://ohioagonline.agri.ohio.gov/'
      else null
    end) as authoritative_source_url,
  coalesce(r.assessment->>'manufacturer_contact_url',p.attributes->>'regulatory_resolution_contact_url') as manufacturer_contact_url,
  case
    when r.assessment_kind='state_product_registration' then 'State registration resolution depends on exact product identity and the resolved federal pesticidal/non-pesticidal or exemption posture.'
    when r.assessment_kind in ('pesticide_registration','federal_exemption_basis') then 'Federal registration and exemption are alternate evidence paths when current claims are pesticidal; neither should be inferred from marketing language.'
    when r.assessment_kind='pesticidal_claim_basis' then 'Resolve current claim context before treating a registration or exemption lookup as dispositive.'
    else null
  end as dependency_note,
  r.assessment,
  'An unresolved queue item is an evidence gap, not a finding of illegality, incompatibility, or non-registration.'::text as guardrail
from cleaning.product_regulatory_assessments r
join cleaning.products p on p.id=r.product_id
where r.status in ('not_established','resolution_required','unknown');

-- -----------------------------------------------------------------------------
-- Candidate-side v2 fit: federal exemption + non-pesticidal state logic
-- -----------------------------------------------------------------------------

create or replace view cleaning.v_surface_condition_product_fit_v2 as
select
  f.*,
  pr.federal_exemption_basis_status,
  pr.public_claim_conflict_requires_authoritative_resolution,
  pr.federal_resolution_state,
  pr.federal_regulatory_ready as federal_regulatory_ready_v2,
  case
    when pr.pesticidal_claim_basis_status='not_applicable' then true
    when f.state_code='KY' then pr.ky_product_registration_status='confirmed'
    when f.state_code='IN' then pr.in_product_registration_status='confirmed'
    when f.state_code='OH' then pr.oh_product_registration_status='confirmed'
    else false
  end as state_regulatory_ready_v2,
  case
    when coalesce(f.has_confirmed_growth,false)=false and coalesce(f.has_likely_growth,false)=false then 'need_not_confirmed'
    when f.surface_type_id is null then 'surface_resolution_required'
    when f.rule_id is null then 'product_surface_rule_unresolved'
    when f.disposition in ('hard_stop','avoid') then 'blocked_by_rule'
    when coalesce(pr.documentation_ready,false)=false then 'product_documentation_unresolved'
    when pr.pesticidal_claim_basis_status in ('resolution_required','not_established','unknown') or pr.pesticidal_claim_basis_status is null then 'federal_claim_basis_resolution_required'
    when coalesce(pr.federal_regulatory_ready,false)=false then 'federal_registration_or_exemption_resolution_required'
    when pr.pesticidal_claim_basis_status is distinct from 'not_applicable'
      and f.state_code in ('KY','IN','OH')
      and case f.state_code when 'KY' then pr.ky_product_registration_status when 'IN' then pr.in_product_registration_status when 'OH' then pr.oh_product_registration_status end is distinct from 'confirmed'
      then 'state_registration_resolution_required'
    when coalesce(f.has_likely_growth,false) and not coalesce(f.has_confirmed_growth,false) then 'field_confirmation_required'
    when coalesce(f.has_confirmed_growth,false) and f.disposition in ('preferred','allowed','conditional','test_patch') then 'conditional_execution_candidate'
    else 'insufficient_data'
  end as chemistry_fit_state_v2,
  false as chemistry_scoreable_v2,
  0 as automatic_score_delta_v2,
  'V2 distinguishes federal registration from federal exemption and does not require state pesticide-product registration when the authoritative claim basis is resolved as non-pesticidal. All other substrate, condition, preservation, runoff and delivery gates remain independent.'::text as guardrail_v2
from cleaning.v_surface_condition_product_fit_v1 f
left join cleaning.v_product_regulatory_readiness_v2 pr on pr.product_id=f.product_id;

-- -----------------------------------------------------------------------------
-- Provider-side v2 fit: require mapped/compatible rig + fluid route
-- -----------------------------------------------------------------------------

create or replace view decisioning.v_provider_chemistry_execution_fit_v2 as
with route as (
  select
    r.organization_id,r.provider_product_id,r.product_id,
    count(*) filter (where r.status is distinct from 'inactive') as active_rig_product_rows,
    bool_or(r.status is distinct from 'inactive' and r.readiness_status='compatible') as has_compatible_route,
    bool_or(r.status is distinct from 'inactive' and r.readiness_status='conditional') as has_conditional_route,
    bool_or(r.status is distinct from 'inactive' and r.readiness_status in ('route_not_assigned','route_mapping_incomplete','compatibility_unresolved')) as has_unresolved_route,
    bool_or(r.status is distinct from 'inactive' and r.readiness_status in ('blocked','not_recommended')) as has_blocked_or_not_recommended_route,
    count(*) filter (where r.status is distinct from 'inactive' and r.readiness_status='compatible') as compatible_route_count,
    count(*) filter (where r.status is distinct from 'inactive' and r.readiness_status='conditional') as conditional_route_count,
    count(*) filter (where r.status is distinct from 'inactive' and r.readiness_status in ('route_not_assigned','route_mapping_incomplete','compatibility_unresolved')) as unresolved_route_count,
    max(r.compatibility_confidence) as max_route_compatibility_confidence,
    bool_or(coalesce(r.manufacturer_verification_required,false)) as manufacturer_verification_required
  from cleaning.v_provider_rig_product_readiness r
  group by r.organization_id,r.provider_product_id,r.product_id
)
select
  b.*,
  pr.federal_exemption_basis_status,
  pr.public_claim_conflict_requires_authoritative_resolution,
  pr.federal_resolution_state,
  coalesce(rt.active_rig_product_rows,0) as active_rig_product_rows,
  coalesce(rt.compatible_route_count,0) as compatible_route_count,
  coalesce(rt.conditional_route_count,0) as conditional_route_count,
  coalesce(rt.unresolved_route_count,0) as unresolved_route_count,
  coalesce(rt.has_compatible_route,false) as has_compatible_route,
  coalesce(rt.has_conditional_route,false) as has_conditional_route,
  coalesce(rt.has_unresolved_route,false) as has_unresolved_route,
  coalesce(rt.has_blocked_or_not_recommended_route,false) as has_blocked_or_not_recommended_route,
  rt.max_route_compatibility_confidence,
  coalesce(rt.manufacturer_verification_required,false) as route_manufacturer_verification_required,
  (coalesce(rt.has_compatible_route,false) or coalesce(rt.has_conditional_route,false)) as route_execution_ready,
  case
    when b.provider_product_status='inactive' then 'inactive'
    when b.product_id is null then 'product_identity_unresolved'
    when b.rule_disposition in ('hard_stop','avoid') then 'capability_blocked'
    when coalesce(pr.documentation_ready,false)=false then 'product_documentation_unresolved'
    when pr.pesticidal_claim_basis_status in ('resolution_required','not_established','unknown') or pr.pesticidal_claim_basis_status is null then 'regulatory_claim_basis_unresolved'
    when coalesce(pr.federal_regulatory_ready,false)=false then 'regulatory_registration_or_exemption_unresolved'
    when coalesce(rt.active_rig_product_rows,0)=0 then 'route_assignment_required'
    when coalesce(rt.has_compatible_route,false) and b.rule_disposition in ('preferred','allowed') then 'capability_supported'
    when (coalesce(rt.has_compatible_route,false) or coalesce(rt.has_conditional_route,false)) and b.rule_disposition in ('conditional','test_patch') then 'capability_conditional'
    when coalesce(rt.has_conditional_route,false) then 'capability_conditional'
    when coalesce(rt.has_unresolved_route,false) then 'route_compatibility_unresolved'
    when coalesce(rt.has_blocked_or_not_recommended_route,false) then 'route_compatibility_blocked'
    else 'capability_insufficient_data'
  end as capability_state_v2,
  0 as calibrated_score_delta_v2,
  false as score_calibrated_v2,
  'V2 requires a provider-declared product to be assigned to at least one mapped rig fluid route with product/route compatibility. Product possession alone cannot establish executable chemistry capability or increase opportunity score.'::text as guardrail_v2
from decisioning.v_provider_chemistry_execution_fit_v1 b
left join cleaning.v_product_regulatory_readiness_v2 pr on pr.product_id=b.product_id
left join route rt on rt.organization_id=b.organization_id and rt.provider_product_id=b.provider_product_id and rt.product_id=b.product_id;

create or replace view decisioning.v_provider_chemistry_opportunity_fit_v2 as
select
  f.building_source_record_id,f.state_code,f.product_id,f.product_slug,
  f.surface_type_id,f.surface_slug,f.soil_type_id,f.soil_slug,
  f.chemistry_fit_state_v2,f.federal_exemption_basis_status,f.federal_resolution_state,f.state_regulatory_ready_v2,
  pc.organization_id,pc.provider_product_id,pc.capability_state_v2,
  pc.active_rig_product_rows,pc.compatible_route_count,pc.conditional_route_count,pc.unresolved_route_count,pc.route_execution_ready,
  case
    when f.chemistry_fit_state_v2='conditional_execution_candidate' and pc.capability_state_v2 in ('capability_supported','capability_conditional') then 'operator_fit_candidate'
    when f.chemistry_fit_state_v2 in ('need_not_confirmed','surface_resolution_required','product_surface_rule_unresolved','product_documentation_unresolved','federal_claim_basis_resolution_required','federal_registration_or_exemption_resolution_required','state_registration_resolution_required','field_confirmation_required') then 'operator_fit_blocked_by_candidate_gate'
    when pc.capability_state_v2 in ('inactive','product_identity_unresolved','capability_blocked','product_documentation_unresolved','regulatory_claim_basis_unresolved','regulatory_registration_or_exemption_unresolved','route_assignment_required','route_compatibility_unresolved','route_compatibility_blocked','capability_insufficient_data') then 'operator_fit_blocked_by_provider_gate'
    else 'operator_fit_unresolved'
  end as operator_fit_state_v2,
  0 as calibrated_score_delta,
  false as score_calibrated,
  'A chemistry opportunity becomes operator-fit only after candidate evidence, exact product regulatory posture, declared inventory and a mapped compatible rig fluid route all pass. Numeric uplift remains zero until field outcomes justify calibration.'::text as guardrail
from cleaning.v_surface_condition_product_fit_v2 f
join decisioning.v_provider_chemistry_execution_fit_v2 pc
  on pc.product_id=f.product_id
 and pc.surface_type_id=f.surface_type_id
 and pc.soil_type_id=f.soil_type_id;
