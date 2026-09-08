-- Scout cleaning chemistry decisioning v1
-- Evidence-first chemistry/product fit, regulatory readiness, provider capability,
-- and field-outcome calibration scaffolding.
--
-- Guardrails:
--   * environmental moisture/growth proxies never prove treatment need;
--   * product possession never creates a lead-score bonus;
--   * current label/SDS and applicable federal/state registration are independent gates;
--   * field outcomes never automatically promote a hypothesis to a model rule;
--   * numeric chemistry score delta remains zero until evidence-backed calibration.

create table if not exists cleaning.product_regulatory_assessments (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references cleaning.products(id) on delete cascade,
  jurisdiction_scope text not null,
  assessment_kind text not null check (assessment_kind in (
    'current_sds','current_label','pesticidal_claim_basis',
    'pesticide_registration','state_product_registration','other'
  )),
  status text not null check (status in (
    'confirmed','not_established','resolution_required','not_applicable','unknown'
  )),
  registration_number text,
  evidence_document_id uuid references knowledge.documents(id) on delete set null,
  assessment jsonb not null default '{}'::jsonb,
  confidence numeric not null default 0.5 check (confidence between 0 and 1),
  reviewed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(product_id,jurisdiction_scope,assessment_kind)
);

create index if not exists product_regulatory_assessments_product_idx
  on cleaning.product_regulatory_assessments(product_id,jurisdiction_scope,status);

create table if not exists cleaning.field_chemistry_outcomes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references core.organizations(id) on delete set null,
  provider_product_id uuid references cleaning.provider_products(id) on delete set null,
  product_id uuid references cleaning.products(id) on delete set null,
  building_source_record_id uuid,
  surface_type_id uuid references cleaning.surface_types(id) on delete set null,
  soil_type_id uuid references cleaning.soil_types(id) on delete set null,
  observed_condition_class text,
  observed_morphology jsonb not null default '{}'::jsonb,
  application_method text,
  mix jsonb not null default '{}'::jsonb,
  result_state text not null default 'planned' check (result_state in (
    'planned','completed_effective','completed_partial','completed_ineffective',
    'adverse_event','aborted'
  )),
  effectiveness jsonb not null default '{}'::jsonb,
  complications jsonb not null default '{}'::jsonb,
  runoff_outcome jsonb not null default '{}'::jsonb,
  adjacent_material_outcome jsonb not null default '{}'::jsonb,
  labor_minutes integer check (labor_minutes is null or labor_minutes >= 0),
  operator_pursue_again boolean,
  evidence_status text not null default 'unreviewed' check (evidence_status in (
    'unreviewed','field_reported','corroborated','reviewed'
  )),
  notes text,
  attributes jsonb not null default '{"automatic_model_rule_promotion":false}'::jsonb,
  observed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists field_chemistry_outcomes_org_product_idx
  on cleaning.field_chemistry_outcomes(organization_id,product_id,observed_at desc);
create index if not exists field_chemistry_outcomes_building_idx
  on cleaning.field_chemistry_outcomes(building_source_record_id,observed_at desc);

-- Current Citra-Shield research sources.  Historical formulation/SDS evidence remains
-- separate from these current public manufacturer references.
insert into knowledge.documents (
  title,document_type,publisher,published_at,source_url,authority_tier,
  review_status,lifecycle_status,canonical_source_key,attributes,reviewed_at
)
values
('Citra-Shield Current Directions for Use','manufacturer_product_data','Citra-Shield',null,
 'https://citrashield.com/terms-conditions/','manufacturer','reviewed','reference_only',
 'citra-shield:manufacturer:directions:2026-09-08',
 '{"captured_on":"2026-09-08","current_public_manufacturer_source":true}'::jsonb,now()),
('Citra-Shield Application Instructions','manufacturer_product_data','Citra-Shield',null,
 'https://citrashield.com/application-instructions/','manufacturer','reviewed','reference_only',
 'citra-shield:manufacturer:application-instructions:2026-09-08',
 '{"captured_on":"2026-09-08","current_public_manufacturer_source":true}'::jsonb,now()),
('Citra-Shield FAQ','manufacturer_product_reference','Citra-Shield',null,
 'https://citrashield.com/faq/','manufacturer','reviewed','reference_only',
 'citra-shield:manufacturer:faq:2026-09-08',
 '{"captured_on":"2026-09-08","current_public_manufacturer_source":true}'::jsonb,now()),
('Citra-Shield Public SDS Link Availability Check','manufacturer_product_reference','Citra-Shield',null,
 'https://citrashield.com/pages/safety-data-sheet','manufacturer','reviewed','reference_only',
 'citra-shield:manufacturer:sds-link-check:2026-09-08',
 '{"captured_on":"2026-09-08","result":"public_link_did_not_resolve_to_current_sds","guardrail":"Does not prove no current SDS exists; only that the current public manufacturer path did not provide one."}'::jsonb,now()),
('EPA: Determining If a Cleaning Product Is a Pesticide Under FIFRA','regulatory_guidance',
 'U.S. Environmental Protection Agency','2026-07-06'::timestamptz,
 'https://www.epa.gov/pesticide-registration/determining-if-cleaning-product-pesticide-under-fifra',
 'regulatory','reviewed','reference_only','epa:fifra:cleaning-product-claims:2026-07-06',
 '{"captured_on":"2026-09-08"}'::jsonb,now()),
('Kentucky Pesticide Product Registration','regulatory_guidance','Kentucky Department of Agriculture',null,
 'https://www.kyagr.com/consumer/product-registration.html','regulatory','reviewed','reference_only',
 'state-pesticide:ky:product-registration:2026-09-08','{"captured_on":"2026-09-08"}'::jsonb,now()),
('Indiana Pesticide Products and Devices Registration','regulatory_guidance','Office of Indiana State Chemist',null,
 'https://oisc.purdue.edu/pesticide/pesticide_products.html','regulatory','reviewed','reference_only',
 'state-pesticide:in:product-registration:2026-09-08','{"captured_on":"2026-09-08"}'::jsonb,now()),
('Ohio Administrative Code Rule 901:5-11-12 Pesticide Registration','regulatory_guidance',
 'Ohio Legislative Service Commission','2024-12-05'::timestamptz,
 'https://codes.ohio.gov/ohio-administrative-code/rule-901%3A5-11-12','regulatory','reviewed','reference_only',
 'state-pesticide:oh:rule-901-5-11-12','{"captured_on":"2026-09-08"}'::jsonb,now())
on conflict do nothing;

-- Product regulatory posture for the Citra-Shield pilot.
-- "not_established" is intentionally not "unregistered".
with citra as (
  select id from cleaning.products
  where slug in (
    'citra-shield-ready-to-use-outdoor-cleaner',
    'citra-shield-concentrate-outdoor-cleaner',
    'citra-shield-exterior-cleaner-treatment'
  )
), rows as (
  select c.id product_id,'US_FEDERAL'::text jurisdiction,'current_sds'::text kind,
    'not_established'::text status,null::text reg,
    (select id from knowledge.documents where canonical_source_key='citra-shield:manufacturer:sds-link-check:2026-09-08' limit 1) doc,
    '{"reason":"Current public manufacturer SDS link did not resolve to a usable current SDS; historical 2021 RTU SDS remains historical evidence only."}'::jsonb assessment,
    0.98::numeric confidence from citra c
  union all
  select c.id,'US_FEDERAL','current_label','not_established',null,
    (select id from knowledge.documents where canonical_source_key='citra-shield:manufacturer:directions:2026-09-08' limit 1),
    '{"reason":"Current manufacturer web directions refer users to the product label, but a current authoritative product label was not established in this review."}'::jsonb,0.95 from citra c
  union all
  select c.id,'US_FEDERAL','pesticidal_claim_basis','resolution_required',null,
    (select id from knowledge.documents where canonical_source_key='epa:fifra:cleaning-product-claims:2026-07-06' limit 1),
    '{"reason":"Current manufacturer marketing includes prevention/biological-growth language; EPA makes claim context material to FIFRA pesticide status."}'::jsonb,0.99 from citra c
  union all
  select c.id,'US_FEDERAL','pesticide_registration','not_established',null,
    (select id from knowledge.documents where canonical_source_key='epa:fifra:cleaning-product-claims:2026-07-06' limit 1),
    '{"reason":"No authoritative current EPA product registration number was established in this review. This is not a finding that the product is unregistered."}'::jsonb,0.95 from citra c
  union all
  select c.id,'KY','state_product_registration','not_established',null,
    (select id from knowledge.documents where canonical_source_key='state-pesticide:ky:product-registration:2026-09-08' limit 1),
    '{"reason":"Exact current Kentucky product registration was not established; verify if pesticidal use or claims apply."}'::jsonb,0.95 from citra c
  union all
  select c.id,'IN','state_product_registration','not_established',null,
    (select id from knowledge.documents where canonical_source_key='state-pesticide:in:product-registration:2026-09-08' limit 1),
    '{"reason":"Exact current Indiana product registration was not established; verify if pesticidal use or claims apply."}'::jsonb,0.95 from citra c
  union all
  select c.id,'OH','state_product_registration','not_established',null,
    (select id from knowledge.documents where canonical_source_key='state-pesticide:oh:rule-901-5-11-12' limit 1),
    '{"reason":"Exact current Ohio product registration was not established; Ohio also registers FIFRA 25(b) pesticide products."}'::jsonb,0.98 from citra c
)
insert into cleaning.product_regulatory_assessments(
  product_id,jurisdiction_scope,assessment_kind,status,registration_number,
  evidence_document_id,assessment,confidence,reviewed_at,updated_at
)
select product_id,jurisdiction,kind,status,reg,doc,assessment,confidence,now(),now()
from rows
on conflict(product_id,jurisdiction_scope,assessment_kind) do update
set status=excluded.status,
    registration_number=excluded.registration_number,
    evidence_document_id=excluded.evidence_document_id,
    assessment=excluded.assessment,
    confidence=excluded.confidence,
    reviewed_at=excluded.reviewed_at,
    updated_at=excluded.updated_at;

create or replace view cleaning.v_product_regulatory_readiness_v1 as
select p.id as product_id,p.slug as product_slug,p.product_name,
 max(a.status) filter(where a.jurisdiction_scope='US_FEDERAL' and a.assessment_kind='current_sds') as current_sds_status,
 max(a.status) filter(where a.jurisdiction_scope='US_FEDERAL' and a.assessment_kind='current_label') as current_label_status,
 max(a.status) filter(where a.jurisdiction_scope='US_FEDERAL' and a.assessment_kind='pesticidal_claim_basis') as pesticidal_claim_basis_status,
 max(a.status) filter(where a.jurisdiction_scope='US_FEDERAL' and a.assessment_kind='pesticide_registration') as federal_pesticide_registration_status,
 max(a.status) filter(where a.jurisdiction_scope='KY' and a.assessment_kind='state_product_registration') as ky_product_registration_status,
 max(a.status) filter(where a.jurisdiction_scope='IN' and a.assessment_kind='state_product_registration') as in_product_registration_status,
 max(a.status) filter(where a.jurisdiction_scope='OH' and a.assessment_kind='state_product_registration') as oh_product_registration_status,
 (max(a.status) filter(where a.jurisdiction_scope='US_FEDERAL' and a.assessment_kind='current_sds')='confirmed'
  and max(a.status) filter(where a.jurisdiction_scope='US_FEDERAL' and a.assessment_kind='current_label')='confirmed') as documentation_ready,
 ((max(a.status) filter(where a.jurisdiction_scope='US_FEDERAL' and a.assessment_kind='pesticidal_claim_basis')='not_applicable')
   or max(a.status) filter(where a.jurisdiction_scope='US_FEDERAL' and a.assessment_kind='pesticide_registration')='confirmed') as federal_regulatory_ready,
 max(a.reviewed_at) as regulatory_reviewed_at
from cleaning.products p
left join cleaning.product_regulatory_assessments a on a.product_id=p.id
group by p.id,p.slug,p.product_name;

create or replace view cleaning.v_surface_condition_product_fit_v1 as
with cond as (
 select building_source_record_id,
   bool_or(condition_class='biological_growth_confirmed') has_confirmed_growth,
   bool_or(condition_class='biological_growth_likely_visual') has_likely_growth,
   max(updated_at) condition_updated_at
 from cleaning.surface_condition_observations
 group by building_source_record_id
), b as (
 select a.building_source_record_id,a.resolved_facade_material,a.resolved_facade_material_status,
   st.id surface_type_id,bc.state_code
 from decisioning.v_building_resolved_attributes a
 left join cleaning.surface_types st on st.slug=a.resolved_facade_material
 left join decisioning.building_candidates bc on bc.source_record_id=a.building_source_record_id
), rules as (
 select cr.id rule_id,cr.product_id,cr.surface_type_id,cr.soil_type_id,cr.service_type_id,
   cr.disposition,cr.conditions,cr.rationale,cr.confidence as rule_confidence,
   so.slug soil_slug,sv.slug service_slug
 from cleaning.cleaning_rules cr
 join cleaning.soil_types so on so.id=cr.soil_type_id
 left join commerce.service_types sv on sv.id=cr.service_type_id
 where cr.product_id is not null and so.slug='biological-growth'
)
select b.building_source_record_id,b.state_code,b.resolved_facade_material,b.resolved_facade_material_status,
 c.has_confirmed_growth,c.has_likely_growth,c.condition_updated_at,
 r.rule_id,r.product_id,p.slug product_slug,p.product_name,r.surface_type_id,st.slug surface_slug,
 r.soil_type_id,r.soil_slug,r.service_type_id,r.service_slug,r.disposition,r.conditions,r.rationale,r.rule_confidence,
 pr.current_sds_status,pr.current_label_status,pr.pesticidal_claim_basis_status,
 pr.federal_pesticide_registration_status,pr.documentation_ready,pr.federal_regulatory_ready,
 case b.state_code
   when 'KY' then pr.ky_product_registration_status
   when 'IN' then pr.in_product_registration_status
   when 'OH' then pr.oh_product_registration_status
   else null
 end as state_product_registration_status,
 case b.state_code
   when 'KY' then pr.ky_product_registration_status='confirmed'
   when 'IN' then pr.in_product_registration_status='confirmed'
   when 'OH' then pr.oh_product_registration_status='confirmed'
   else false
 end as state_regulatory_ready,
 case
  when coalesce(c.has_confirmed_growth,false)=false and coalesce(c.has_likely_growth,false)=false then 'need_not_confirmed'
  when b.surface_type_id is null then 'surface_resolution_required'
  when r.rule_id is null then 'product_surface_rule_unresolved'
  when r.disposition in ('hard_stop','avoid') then 'blocked_by_rule'
  when coalesce(pr.documentation_ready,false)=false then 'product_documentation_unresolved'
  when coalesce(pr.federal_regulatory_ready,false)=false then 'federal_regulatory_resolution_required'
  when b.state_code in ('KY','IN','OH') and
       (case b.state_code when 'KY' then pr.ky_product_registration_status when 'IN' then pr.in_product_registration_status when 'OH' then pr.oh_product_registration_status end) <> 'confirmed'
    then 'state_registration_resolution_required'
  when coalesce(c.has_likely_growth,false) and not coalesce(c.has_confirmed_growth,false) then 'field_confirmation_required'
  when c.has_confirmed_growth and r.disposition in ('preferred','allowed','conditional','test_patch') then 'conditional_execution_candidate'
  else 'insufficient_data'
 end as chemistry_fit_state,
 false as chemistry_scoreable,
 0::integer as automatic_score_delta,
 'Product fit never establishes treatment need. Current label/SDS, applicable registration, runoff/receptors, preservation constraints, delivery-route compatibility and operator-declared inventory remain independent gates.'::text as guardrail
from b
left join cond c using(building_source_record_id)
left join rules r on r.surface_type_id=b.surface_type_id
left join cleaning.products p on p.id=r.product_id
left join cleaning.surface_types st on st.id=r.surface_type_id
left join cleaning.v_product_regulatory_readiness_v1 pr on pr.product_id=r.product_id;

create or replace view decisioning.v_provider_chemistry_execution_fit_v1 as
select pp.organization_id,pp.id provider_product_id,pp.product_id,p.slug product_slug,p.product_name,
 pp.status provider_product_status,cr.id rule_id,cr.surface_type_id,st.slug surface_slug,
 cr.soil_type_id,so.slug soil_slug,cr.service_type_id,sv.slug service_slug,cr.disposition rule_disposition,
 pr.current_sds_status,pr.current_label_status,pr.pesticidal_claim_basis_status,
 pr.federal_pesticide_registration_status,pr.documentation_ready,pr.federal_regulatory_ready,
 case
  when pp.status='inactive' then 'inactive'
  when pp.product_id is null then 'product_identity_unresolved'
  when cr.disposition in ('hard_stop','avoid') then 'capability_blocked'
  when coalesce(pr.documentation_ready,false)=false then 'product_documentation_unresolved'
  when coalesce(pr.federal_regulatory_ready,false)=false then 'regulatory_unresolved'
  when cr.disposition in ('conditional','test_patch') then 'capability_conditional'
  when cr.disposition in ('preferred','allowed') then 'capability_supported'
  else 'capability_insufficient_data'
 end as capability_state,
 0::integer as calibrated_score_delta,
 false as score_calibrated,
 'A declared product can alter execution fit only after evidence, substrate, product-documentation, regulatory and route-compatibility gates pass. Numeric uplift remains zero until field outcomes support calibration.'::text as guardrail
from cleaning.provider_products pp
left join cleaning.products p on p.id=pp.product_id
left join cleaning.cleaning_rules cr on cr.product_id=pp.product_id
left join cleaning.surface_types st on st.id=cr.surface_type_id
left join cleaning.soil_types so on so.id=cr.soil_type_id
left join commerce.service_types sv on sv.id=cr.service_type_id
left join cleaning.v_product_regulatory_readiness_v1 pr on pr.product_id=pp.product_id;

create or replace view decisioning.v_provider_chemistry_opportunity_fit_v1 as
select f.building_source_record_id,f.state_code,f.product_id,f.product_slug,
 f.surface_type_id,f.surface_slug,f.soil_type_id,f.soil_slug,f.chemistry_fit_state,
 pc.organization_id,pc.provider_product_id,pc.capability_state,
 case
  when f.chemistry_fit_state='conditional_execution_candidate'
       and pc.capability_state in ('capability_supported','capability_conditional')
    then 'operator_fit_candidate'
  when f.chemistry_fit_state in (
    'need_not_confirmed','surface_resolution_required','product_surface_rule_unresolved',
    'product_documentation_unresolved','federal_regulatory_resolution_required',
    'state_registration_resolution_required','field_confirmation_required'
  ) then 'operator_fit_blocked_by_candidate_gate'
  when pc.capability_state in (
    'inactive','product_identity_unresolved','capability_blocked','product_documentation_unresolved',
    'regulatory_unresolved','capability_insufficient_data'
  ) then 'operator_fit_blocked_by_provider_gate'
  else 'operator_fit_unresolved'
 end as operator_fit_state,
 0::integer as calibrated_score_delta,
 false as score_calibrated,
 'No operator-specific chemistry uplift is applied until field outcomes calibrate a numeric modifier; product possession alone never increases opportunity score.'::text as guardrail
from cleaning.v_surface_condition_product_fit_v1 f
join decisioning.v_provider_chemistry_execution_fit_v1 pc
  on pc.product_id=f.product_id
 and pc.surface_type_id=f.surface_type_id
 and pc.soil_type_id=f.soil_type_id;

create or replace view cleaning.v_citra_shield_specialist_condition_queue_v3 as
select q.*,
 case
  when q.condition_gate_state_v2='current_condition_verification_required'
       and q.has_insufficient_visual_resolution
    then 'await_new_visual_or_field_evidence'
  else q.condition_gate_state_v2
 end as condition_gate_state_v3,
 case
  when q.condition_gate_state_v2='current_condition_verification_required'
       and q.has_insufficient_visual_resolution
    then 'await_current_close_range_visual_or_field_observation; do_not_repeat_public_web_pass_without_new_source'
  else q.condition_next_action_v2
 end as condition_next_action_v3,
 false as chemistry_scoreable_after_condition_pass_v3,
 0::integer as automatic_score_delta_after_condition_pass_v3,
 'A completed public-web pass with insufficient visual resolution is a research-exhaustion state, not evidence of cleanliness or biological growth. Reopen only for materially newer/closer imagery or field observation.'::text as condition_closure_guardrail
from cleaning.v_citra_shield_specialist_condition_queue_v2 q;

create or replace view cleaning.v_field_chemistry_calibration_readiness_v1 as
select f.organization_id,f.product_id,p.slug product_slug,f.surface_type_id,st.slug surface_slug,
 f.soil_type_id,so.slug soil_slug,
 count(*) as field_outcome_rows,
 count(*) filter(where f.result_state<>'planned') as completed_or_aborted_rows,
 count(*) filter(where f.result_state='completed_effective') as effective_rows,
 count(*) filter(where f.result_state='completed_partial') as partial_rows,
 count(*) filter(where f.result_state='completed_ineffective') as ineffective_rows,
 count(*) filter(where f.result_state='adverse_event') as adverse_event_rows,
 count(*) filter(where f.operator_pursue_again is true) as pursue_again_yes_rows,
 count(*) filter(where f.operator_pursue_again is false) as pursue_again_no_rows,
 max(f.observed_at) as latest_observed_at,
 case
  when count(*) filter(where f.result_state<>'planned')=0 then 'no_completed_field_outcomes'
  else 'field_evidence_accumulating_manual_review_required'
 end as calibration_state,
 false as automatic_model_rule_promotion,
 0::integer as calibrated_score_delta,
 'Field outcomes inform later calibration but never automatically promote a local hypothesis into a model rule or assign a score delta.'::text as guardrail
from cleaning.field_chemistry_outcomes f
left join cleaning.products p on p.id=f.product_id
left join cleaning.surface_types st on st.id=f.surface_type_id
left join cleaning.soil_types so on so.id=f.soil_type_id
group by f.organization_id,f.product_id,p.slug,f.surface_type_id,st.slug,f.soil_type_id,so.slug;

-- Release checks (should return without exception / zero chemistry uplift until calibrated):
-- select agent_contract.assert_tool_registry_integrity_v1();
-- select agent_contract.assert_architecture_doctrine_v1();
-- select product_slug,current_sds_status,current_label_status,pesticidal_claim_basis_status,
--        federal_pesticide_registration_status,documentation_ready,federal_regulatory_ready
-- from cleaning.v_product_regulatory_readiness_v1 where product_slug like 'citra-shield%';
