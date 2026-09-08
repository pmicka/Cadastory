-- Scout OneRestore chemistry pilot v1
-- Mirrors production migration 20260908225137 onerestore_chemistry_pilot_v1.
-- Idempotent and lookup-driven: do not hardcode generated primary keys.

-- Current manufacturer evidence ------------------------------------------------
with d as (
  insert into knowledge.documents(
    title,document_type,publisher,published_at,source_url,authority_tier,
    review_status,attributes,lifecycle_status,canonical_source_key,reviewed_at,updated_at
  ) values (
    'OneRestore Product Data Sheet (2025)','manufacturer_product_data','EaCo Chem','2025-01-01'::timestamptz,
    'https://eacochem.com/wp-content/uploads/2025/04/onerestore_product-data_2025_english.pdf',
    'manufacturer','reviewed',
    jsonb_build_object('captured_on','2026-09-08','product_slug','eaco-chem-onerestore','current_product_specific_document',true),
    'linked','manufacturer:eaco-chem:onerestore:pds:2025',now(),now()
  ) on conflict (canonical_source_key) where canonical_source_key is not null
  do update set title=excluded.title,source_url=excluded.source_url,published_at=excluded.published_at,
                attributes=excluded.attributes,review_status='reviewed',lifecycle_status='linked',reviewed_at=now(),updated_at=now()
  returning id
), doc as (
  select id from d union all
  select id from knowledge.documents where canonical_source_key='manufacturer:eaco-chem:onerestore:pds:2025' limit 1
)
insert into knowledge.claims(document_id,claim_type,statement,structured_value,source_location,applicability,hard_stop,confidence,status,reviewed_at,updated_at)
select doc.id,x.claim_type,x.statement,x.structured_value,x.source_location,
       jsonb_build_object('product_slug','eaco-chem-onerestore'),x.hard_stop,x.confidence,'active',now(),now()
from doc cross join (values
 ('specification'::text,
  'The current OneRestore PDS specifies professional-use restoration chemistry used undiluted, with pre-wetting, low-pressure application, typical 5–10 minute dwell, thorough cold-water rinsing, and a prohibition on allowing the product to dry on the surface.',
  jsonb_build_object('used_undiluted',true,'prewet_required',true,'low_pressure_application',true,'typical_dwell_minutes',jsonb_build_array(5,10),'thorough_rinse_required',true,'do_not_allow_to_dry',true,'temperature_f',jsonb_build_array(40,90)),
  'PDS pp. 1–3',false,0.99::numeric),
 ('compatibility',
  'EaCo Chem lists brick, limestone, concrete, precast, exposed aggregate, granite, unpolished marble, synthetic stone, terrazzo, anodized aluminum, EIFS, uncoated stainless steel, stucco and glass as tested suitable substrates under standard conditions, while requiring pre-testing before full-scale cleaning.',
  jsonb_build_object('pretesting_required',true,'manufacturer_positioned_surfaces',jsonb_build_array('brick','limestone','concrete','precast','exposed aggregate','granite','unpolished marble','synthetic stone','terrazzo','anodized aluminum','EIFS','uncoated stainless steel','stucco','glass')),
  'PDS pp. 1–2',false,0.99::numeric),
 ('incompatibility',
  'The current OneRestore PDS says not to use the product on polished stone, oxide films used for tinting glass, self-cleaning glass, or galvanized metal; it is not recommended for colored horizontal surfaces, and puddling/dwell on horizontal surfaces must be avoided.',
  jsonb_build_object('avoid_surfaces',jsonb_build_array('polished stone','oxide tint films','self-cleaning glass','galvanized metal','colored horizontal surfaces'),'avoid_horizontal_puddling',true),
  'PDS p. 1',true,0.99::numeric),
 ('performance',
  'The current OneRestore PDS identifies mineral oxide stains, environmental pollution stains, rust, vanadium, manganese, concrete leaching, sealant stains, caulk bleed, hard-water stains on glass, sealer overspray on glass and fresh tar stains among manufacturer-positioned stain-removal uses; this is manufacturer positioning, not proof that a specific observed discoloration has that origin.',
  jsonb_build_object('manufacturer_positioned_stains',jsonb_build_array('mineral oxide','environmental pollution','rust','vanadium','manganese','concrete leaching','sealant stains','caulk bleed','hard water on glass','sealer overspray on glass','fresh tar'),'specific_stain_origin_proven',false),
  'PDS pp. 1–2',false,0.98::numeric)
) as x(claim_type,statement,structured_value,source_location,hard_stop,confidence)
where not exists(select 1 from knowledge.claims c where c.document_id=doc.id and c.statement=x.statement);

with d as (
  insert into knowledge.documents(
    title,document_type,publisher,published_at,source_url,authority_tier,
    review_status,attributes,lifecycle_status,canonical_source_key,reviewed_at,updated_at
  ) values (
    'OneRestore Safety Data Sheet — Version 3.1','sds','EaCo Chem','2025-09-24'::timestamptz,
    'https://eacochem.com/wp-content/uploads/2024/08/SDS_ONERESTORE.pdf',
    'manufacturer','reviewed',
    jsonb_build_object('version','3.1','revision_date','2025-09-24','captured_on','2026-09-08','product_slug','eaco-chem-onerestore','current_product_specific_document',true),
    'linked','manufacturer:eaco-chem:onerestore:sds:2025-09-24:v3.1',now(),now()
  ) on conflict (canonical_source_key) where canonical_source_key is not null
  do update set title=excluded.title,source_url=excluded.source_url,published_at=excluded.published_at,
                attributes=excluded.attributes,review_status='reviewed',lifecycle_status='linked',reviewed_at=now(),updated_at=now()
  returning id
), doc as (
  select id from d union all
  select id from knowledge.documents where canonical_source_key='manufacturer:eaco-chem:onerestore:sds:2025-09-24:v3.1' limit 1
)
insert into knowledge.claims(document_id,claim_type,statement,structured_value,source_location,applicability,hard_stop,confidence,status,reviewed_at,updated_at)
select doc.id,x.claim_type,x.statement,x.structured_value,x.source_location,
       jsonb_build_object('product_slug','eaco-chem-onerestore'),x.hard_stop,x.confidence,'active',now(),now()
from doc cross join (values
 ('specification'::text,
  'The current OneRestore SDS version 3.1 discloses hydrochloric acid (CAS 7647-01-0) below 20% and 2-butoxyethanol (CAS 111-76-2) at 1–5%, with the balance withheld as trade secret.',
  jsonb_build_object('hydrochloric_acid',jsonb_build_object('cas','7647-01-0','max_percent',20,'upper_bound_exclusive',true),'2-butoxyethanol',jsonb_build_object('cas','111-76-2','min_percent',1,'max_percent',5),'balance','trade secret'),
  'SDS §3, p. 2',false,1.0::numeric),
 ('safety_absolute',
  'The current OneRestore SDS classifies the mixture as potentially corrosive to metals, harmful if swallowed, irritating to skin and eyes, capable of respiratory irritation, and harmful to aquatic life; it directs users to avoid release to the environment and to keep product out of waterways and storm drains.',
  jsonb_build_object('hazards',jsonb_build_array('H290','H302','H315','H319','H335','H402'),'avoid_release_to_environment',true,'exclude_waterways_and_storm_drains',true),
  'SDS §§2 and 6',true,1.0::numeric),
 ('incompatibility',
  'The current OneRestore SDS identifies strong alkali and oxidizing compounds as incompatible materials.',
  jsonb_build_object('incompatible_material_classes',jsonb_build_array('strong alkali','oxidizing compounds')),
  'SDS §10.5',true,1.0::numeric)
) as x(claim_type,statement,structured_value,source_location,hard_stop,confidence)
where not exists(select 1 from knowledge.claims c where c.document_id=doc.id and c.statement=x.statement);

-- Product and disclosed ingredients -------------------------------------------
update cleaning.products p
set sds_document_id=(select id from knowledge.documents where canonical_source_key='manufacturer:eaco-chem:onerestore:sds:2025-09-24:v3.1' limit 1),
    technical_document_id=(select id from knowledge.documents where canonical_source_key='manufacturer:eaco-chem:onerestore:pds:2025' limit 1),
    attributes=p.attributes || jsonb_build_object(
      'chemistry_pilot','onerestore_chemistry_v1','current_sds_status','confirmed','current_pds_status','confirmed',
      'current_sds_version','3.1','current_sds_revision','2025-09-24',
      'product_specific_chemistry_resolved',true,'reported_chemistry_family','buffered_acid_restoration_cleaner',
      'current_pesticidal_claim_basis','not_applicable_on_reviewed_product_specific_evidence','automatic_score_uplift',0),
    updated_at=now()
where p.slug='eaco-chem-onerestore';

delete from cleaning.product_ingredients pi
using cleaning.products p, cleaning.chemical_agents a
where pi.product_id=p.id and pi.chemical_agent_id=a.id and p.slug='eaco-chem-onerestore' and a.slug='acidic-cleaners';

insert into cleaning.product_ingredients(product_id,chemical_agent_id,concentration_min_pct,concentration_max_pct,ingredient_role,disclosure_basis,evidence_claim_id,confidence,attributes)
select p.id,a.id,x.min_pct,x.max_pct,x.role,'sds',
       (select c.id from knowledge.claims c join knowledge.documents d on d.id=c.document_id
        where d.canonical_source_key='manufacturer:eaco-chem:onerestore:sds:2025-09-24:v3.1' and c.claim_type='specification' limit 1),
       1.0,x.attributes
from cleaning.products p
join (values
 ('hydrochloric-acid'::text,null::numeric,20::numeric,'acidic active/restoration component'::text,jsonb_build_object('sds_version','3.1','sds_revision','2025-09-24','upper_bound_exclusive',true)),
 ('2-butoxyethanol',1::numeric,5::numeric,'solvent/surfactant-supporting component',jsonb_build_object('sds_version','3.1','sds_revision','2025-09-24'))
) x(agent_slug,min_pct,max_pct,role,attributes) on true
join cleaning.chemical_agents a on a.slug=x.agent_slug
where p.slug='eaco-chem-onerestore'
on conflict (product_id,chemical_agent_id,disclosure_basis) do update
set concentration_min_pct=excluded.concentration_min_pct,concentration_max_pct=excluded.concentration_max_pct,
    ingredient_role=excluded.ingredient_role,evidence_claim_id=excluded.evidence_claim_id,confidence=excluded.confidence,attributes=excluded.attributes;

-- Current safety/environmental profiles ---------------------------------------
update cleaning.product_safety_profiles s
set sds_document_id=p.sds_document_id,signal_word='WARNING',
    hazard_statements=array['H290 May be corrosive to metals','H302 Harmful if swallowed','H315 Causes skin irritation','H319 Causes serious eye irritation','H335 May cause respiratory irritation','H402 Harmful to aquatic life'],
    hazard_flags=array['metal corrosion potential','oral toxicity','skin irritation','eye irritation','respiratory irritation','aquatic hazard'],
    ppe_classes=array['chemical-resistant gloves','close-fitting safety goggles','protective clothing','face shield if needed','respiratory protection when exposure limits are exceeded or irritation occurs'],
    engineering_controls=array['adequate ventilation','minimize splashes','eyewash and safety shower availability','prevent unintended drift','avoid release to waterways or storm drains'],
    first_aid_summary='Current SDS v3.1 governs first aid: rinse eyes thoroughly for at least 15 minutes and seek immediate medical attention; remove contaminated clothing and wash skin; move inhalation exposure to fresh air; do not induce vomiting after ingestion and seek immediate medical attention.',
    handling_storage_notes='Keep tightly closed in a dry, well-ventilated place; minimize splashes; keep away from strong alkali and oxidizing compounds; follow current PDS/SDS and container label.',
    confidence=1.0,
    attributes=s.attributes || jsonb_build_object('profile_version','onerestore_chemistry_v1','current_sds_verified',true,'sds_version','3.1','sds_revision','2025-09-24'),
    updated_at=now()
from cleaning.products p where s.product_id=p.id and p.slug='eaco-chem-onerestore';

update cleaning.product_environmental_profiles e
set aquatic_toxicity=jsonb_build_object('sds_hazard','H402 Harmful to aquatic life','current_sds_verified',true,'avoid_release_to_environment',true),
    biodegradation=jsonb_build_object('manufacturer_pds_claim','biodegradable','guardrail','Marketing/PDS biodegradability language is not discharge authorization.'),
    release_notes='Current SDS v3.1 directs users to avoid release to the environment and not let product enter waterways or storm drains. Site-specific runoff/receptor and disposal controls remain required.',
    confidence=1.0,
    attributes=e.attributes || jsonb_build_object('profile_version','onerestore_chemistry_v1','current_sds_verified',true,'local_discharge_review_required',true,'storm_drain_release_prohibited_by_sds',true,'marketing_claim_not_discharge_authorization',true),
    updated_at=now()
from cleaning.products p where e.product_id=p.id and p.slug='eaco-chem-onerestore';

-- Regulatory/documentation model ----------------------------------------------
alter table cleaning.product_regulatory_assessments drop constraint if exists product_regulatory_assessments_assessment_kind_check;
alter table cleaning.product_regulatory_assessments add constraint product_regulatory_assessments_assessment_kind_check
check (assessment_kind=any(array['current_sds','current_label','current_technical_data','pesticidal_claim_basis','pesticide_registration','federal_exemption_basis','state_product_registration','other']::text[]));

with p as (select id from cleaning.products where slug='eaco-chem-onerestore'),
     sds as (select id from knowledge.documents where canonical_source_key='manufacturer:eaco-chem:onerestore:sds:2025-09-24:v3.1'),
     pds as (select id from knowledge.documents where canonical_source_key='manufacturer:eaco-chem:onerestore:pds:2025')
insert into cleaning.product_regulatory_assessments(product_id,jurisdiction_scope,assessment_kind,status,registration_number,evidence_document_id,assessment,confidence,reviewed_at,created_at,updated_at)
select p.id,x.scope,x.kind,x.status,null,
       case when x.kind='current_sds' then sds.id when x.kind='current_technical_data' then pds.id else null end,
       jsonb_build_object('reason',x.reason),x.confidence,now(),now(),now()
from p cross join sds cross join pds cross join (values
 ('US_FEDERAL'::text,'current_sds'::text,'confirmed'::text,'Current manufacturer SDS v3.1 revised 2025-09-24 is attached.',1.0::numeric),
 ('US_FEDERAL','current_technical_data','confirmed','Current manufacturer OneRestore Product Data Sheet is attached and supplies product-specific application, substrate, stain, limitation and pretesting guidance.',1.0::numeric),
 ('US_FEDERAL','current_label','not_established','A separate current container-label artifact was not captured. This is non-blocking for Scout documentation readiness because current product-specific PDS and SDS are confirmed; container label directions still govern job handling.',0.95::numeric),
 ('US_FEDERAL','pesticidal_claim_basis','not_applicable','Reviewed current product-specific OneRestore PDS/product positioning is stain/deposit restoration chemistry and does not establish a pest prevention, destruction, repelling or mitigation claim. Reopen if current product-specific claims change.',0.97::numeric),
 ('US_FEDERAL','pesticide_registration','not_applicable','Pesticide-registration gate is not applicable under the current reviewed non-pesticidal product-specific claim basis; this is not a general legal exemption finding.',0.97::numeric),
 ('US_FEDERAL','federal_exemption_basis','not_applicable','No pesticide exemption basis is needed under the current reviewed non-pesticidal product-specific claim basis.',0.97::numeric),
 ('KY','state_product_registration','not_applicable','Scout pesticide-product registration gate is not applicable under the current reviewed non-pesticidal product-specific claim basis. Other chemical, discharge, workplace and local requirements remain independent.',0.96::numeric),
 ('IN','state_product_registration','not_applicable','Scout pesticide-product registration gate is not applicable under the current reviewed non-pesticidal product-specific claim basis. Other chemical, discharge, workplace and local requirements remain independent.',0.96::numeric),
 ('OH','state_product_registration','not_applicable','Scout pesticide-product registration gate is not applicable under the current reviewed non-pesticidal product-specific claim basis. Other chemical, discharge, workplace and local requirements remain independent.',0.96::numeric)
) x(scope,kind,status,reason,confidence)
on conflict (product_id,jurisdiction_scope,assessment_kind) do update
set status=excluded.status,evidence_document_id=coalesce(excluded.evidence_document_id,cleaning.product_regulatory_assessments.evidence_document_id),
    assessment=excluded.assessment,confidence=excluded.confidence,reviewed_at=now(),updated_at=now();

create or replace view cleaning.v_product_regulatory_readiness_v3 as
select p.id as product_id,p.slug as product_slug,p.product_name,
 max(a.status) filter(where a.jurisdiction_scope='US_FEDERAL' and a.assessment_kind='current_sds') as current_sds_status,
 max(a.status) filter(where a.jurisdiction_scope='US_FEDERAL' and a.assessment_kind='current_label') as current_label_status,
 max(a.status) filter(where a.jurisdiction_scope='US_FEDERAL' and a.assessment_kind='current_technical_data') as current_technical_data_status,
 max(a.status) filter(where a.jurisdiction_scope='US_FEDERAL' and a.assessment_kind='pesticidal_claim_basis') as pesticidal_claim_basis_status,
 max(a.status) filter(where a.jurisdiction_scope='US_FEDERAL' and a.assessment_kind='pesticide_registration') as federal_pesticide_registration_status,
 max(a.status) filter(where a.jurisdiction_scope='US_FEDERAL' and a.assessment_kind='federal_exemption_basis') as federal_exemption_basis_status,
 max(a.status) filter(where a.jurisdiction_scope='KY' and a.assessment_kind='state_product_registration') as ky_product_registration_status,
 max(a.status) filter(where a.jurisdiction_scope='IN' and a.assessment_kind='state_product_registration') as in_product_registration_status,
 max(a.status) filter(where a.jurisdiction_scope='OH' and a.assessment_kind='state_product_registration') as oh_product_registration_status,
 (max(a.status) filter(where a.jurisdiction_scope='US_FEDERAL' and a.assessment_kind='current_sds')='confirmed' and
  (max(a.status) filter(where a.jurisdiction_scope='US_FEDERAL' and a.assessment_kind='current_label')='confirmed' or
   max(a.status) filter(where a.jurisdiction_scope='US_FEDERAL' and a.assessment_kind='current_technical_data')='confirmed')) as documentation_ready,
 (max(a.status) filter(where a.jurisdiction_scope='US_FEDERAL' and a.assessment_kind='pesticidal_claim_basis')='not_applicable' or
  max(a.status) filter(where a.jurisdiction_scope='US_FEDERAL' and a.assessment_kind='pesticide_registration')='confirmed' or
  max(a.status) filter(where a.jurisdiction_scope='US_FEDERAL' and a.assessment_kind='federal_exemption_basis')='confirmed') as federal_regulatory_ready,
 case
  when max(a.status) filter(where a.jurisdiction_scope='US_FEDERAL' and a.assessment_kind='pesticidal_claim_basis')='not_applicable' then 'non_pesticidal_claim_basis_resolved'
  when max(a.status) filter(where a.jurisdiction_scope='US_FEDERAL' and a.assessment_kind='pesticide_registration')='confirmed' then 'pesticide_registration_confirmed'
  when max(a.status) filter(where a.jurisdiction_scope='US_FEDERAL' and a.assessment_kind='federal_exemption_basis')='confirmed' then 'federal_exemption_basis_confirmed'
  when not (max(a.status) filter(where a.jurisdiction_scope='US_FEDERAL' and a.assessment_kind='current_sds')='confirmed' and
            (max(a.status) filter(where a.jurisdiction_scope='US_FEDERAL' and a.assessment_kind='current_label')='confirmed' or
             max(a.status) filter(where a.jurisdiction_scope='US_FEDERAL' and a.assessment_kind='current_technical_data')='confirmed')) then 'product_documentation_unresolved'
  when max(a.status) filter(where a.jurisdiction_scope='US_FEDERAL' and a.assessment_kind='pesticidal_claim_basis')=any(array['resolution_required','not_established','unknown']) then 'claim_basis_resolution_required'
  else 'federal_registration_or_exemption_resolution_required' end as federal_resolution_state,
 coalesce((p.attributes->>'current_public_claim_conflict') is not null,false) as public_claim_conflict_requires_authoritative_resolution,
 count(*) filter(where a.status=any(array['not_established','resolution_required','unknown'])) as unresolved_assessment_count,
 max(a.reviewed_at) as regulatory_reviewed_at
from cleaning.products p left join cleaning.product_regulatory_assessments a on a.product_id=p.id
group by p.id,p.slug,p.product_name;

-- Condition taxonomy -----------------------------------------------------------
alter table cleaning.surface_condition_observations add column if not exists soil_type_id uuid references cleaning.soil_types(id) on delete set null;
alter table cleaning.surface_condition_observations drop constraint if exists surface_condition_observations_condition_class_check;
alter table cleaning.surface_condition_observations add constraint surface_condition_observations_condition_class_check
check(condition_class=any(array['biological_growth_confirmed','biological_growth_likely_visual','soil_confirmed','soil_likely_visual','visible_soiling_origin_unresolved','no_obvious_biological_growth_in_public_view','major_exterior_renovation_or_restoration_documented','identity_ambiguous','insufficient_visual_resolution']::text[]));

-- Product stain rules ----------------------------------------------------------
with p as (select id from cleaning.products where slug='eaco-chem-onerestore'),
     svc as (select id from commerce.service_types where slug='masonry-restoration-cleaning'),
     r as (
       select * from (values
        ('limestone'::text,'rust-iron-staining'::text),('limestone','mineral-scale'),('limestone','atmospheric-grime'),
        ('brick','rust-iron-staining'),('brick','mineral-scale'),('brick','atmospheric-grime'),
        ('architectural-glass','mineral-scale')) v(surface_slug,soil_slug)
     )
insert into cleaning.cleaning_rules(product_id,surface_type_id,soil_type_id,service_type_id,disposition,rinse_required,containment_required,conditions,rationale,confidence,attributes)
select p.id,st.id,so.id,svc.id,'test_patch',true,false,
 jsonb_build_object('requires',jsonb_build_array('current PDS/SDS','inconspicuous pretest','pre-wet per current PDS','low-pressure application','5–10 minute typical dwell','do not allow product to dry','thorough cold-water rinse','protect adjacent materials','runoff/receptor assessment'),'used_undiluted',true),
 'Current OneRestore PDS/SDS supports stain-specific restoration use only after substrate/finish and stain origin are resolved; pretesting and project-specific controls remain mandatory.',0.95,
 jsonb_build_object('rule_version','onerestore_chemistry_v1','actual_stain_evidence_required',true,'automatic_score_uplift',0,'environmental_proxy_not_sufficient',true)
from p cross join svc join r on true join cleaning.surface_types st on st.slug=r.surface_slug join cleaning.soil_types so on so.slug=r.soil_slug
on conflict do nothing;

update cleaning.cleaning_rules cr
set disposition='test_patch',rinse_required=true,confidence=greatest(cr.confidence,0.95),
    attributes=cr.attributes || jsonb_build_object('rule_version','onerestore_chemistry_v1','actual_stain_evidence_required',true,'automatic_score_uplift',0,'environmental_proxy_not_sufficient',true),
    updated_at=now()
from cleaning.products p where cr.product_id=p.id and p.slug='eaco-chem-onerestore';

-- Candidate and provider views -------------------------------------------------
create or replace view cleaning.v_onerestore_candidate_scaffold_v1 as
with product as (select id,slug,product_name from cleaning.products where slug='eaco-chem-onerestore'),
obs as (
 select o.building_source_record_id,o.soil_type_id,
        bool_or(o.condition_class=any(array['soil_confirmed','biological_growth_confirmed'])) as soil_confirmed,
        bool_or(o.condition_class=any(array['soil_likely_visual','biological_growth_likely_visual'])) as soil_likely_visual,
        max(o.confidence) as observation_confidence,max(o.updated_at) as condition_updated_at
 from cleaning.surface_condition_observations o where o.soil_type_id is not null group by o.building_source_record_id,o.soil_type_id
), rules as (
 select cr.id rule_id,cr.product_id,cr.surface_type_id,cr.soil_type_id,cr.disposition,cr.rinse_required,cr.containment_required,cr.conditions,cr.rationale,cr.confidence rule_confidence,st.slug surface_slug,so.slug soil_slug
 from cleaning.cleaning_rules cr join product p on p.id=cr.product_id join cleaning.surface_types st on st.id=cr.surface_type_id join cleaning.soil_types so on so.id=cr.soil_type_id
 where so.slug=any(array['rust-iron-staining','mineral-scale','atmospheric-grime'])
), base as (
 select c.candidate_key,c.building_source_record_id,c.classification_state restoration_classification_state,c.classification_confidence restoration_classification_confidence,c.reason restoration_reason,c.evidence restoration_evidence,
        a.resolved_facade_material,a.resolved_raw_facade_material,a.resolved_facade_material_status,st.id resolved_surface_type_id,bc.state_code
 from cleaning.v_exterior_opportunity_service_classification_build c
 left join decisioning.v_building_resolved_attributes a on a.building_source_record_id=c.building_source_record_id
 left join cleaning.surface_types st on st.slug=a.resolved_facade_material
 left join decisioning.building_candidates bc on bc.source_record_id=c.building_source_record_id
 where c.service_slug='masonry-restoration-cleaning' and c.classification_state=any(array['supported','investigate'])
)
select b.candidate_key,b.building_source_record_id,b.state_code,b.restoration_classification_state,b.restoration_classification_confidence,b.restoration_reason,
 b.resolved_facade_material,b.resolved_raw_facade_material,b.resolved_facade_material_status,
 r.rule_id,r.product_id,p.slug product_slug,p.product_name,r.surface_type_id,r.surface_slug,r.soil_type_id,r.soil_slug,r.disposition,r.rule_confidence,
 coalesce(o.soil_confirmed,false) soil_confirmed,coalesce(o.soil_likely_visual,false) soil_likely_visual,o.observation_confidence,o.condition_updated_at,
 pr.current_sds_status,pr.current_technical_data_status,pr.pesticidal_claim_basis_status,pr.documentation_ready,pr.federal_regulatory_ready,
 case b.state_code when 'KY' then pr.ky_product_registration_status when 'IN' then pr.in_product_registration_status when 'OH' then pr.oh_product_registration_status end state_pesticide_registration_status,
 case when b.resolved_surface_type_id is null then 'surface_resolution_required' when r.rule_id is null then 'product_surface_stain_rule_unresolved'
      when not coalesce(pr.documentation_ready,false) then 'product_documentation_unresolved' when not coalesce(pr.federal_regulatory_ready,false) then 'federal_regulatory_resolution_required'
      when coalesce(o.soil_confirmed,false) then 'stain_evidence_confirmed_test_patch_required' when coalesce(o.soil_likely_visual,false) then 'stain_visual_requires_field_confirmation'
      else 'stain_morphology_verification_required' end onerestore_fit_state,
 (coalesce(o.soil_confirmed,false) and r.rule_id is not null and coalesce(pr.documentation_ready,false) and coalesce(pr.federal_regulatory_ready,false)) product_test_patch_candidate,
 false chemistry_scoreable,0 automatic_score_delta,
 case when b.resolved_surface_type_id is null then 'resolve_exact_substrate_and_finish' when r.rule_id is null then 'resolve_product_surface_stain_rule'
      when not coalesce(pr.documentation_ready,false) then 'resolve_current_product_documentation' when not coalesce(pr.federal_regulatory_ready,false) then 'resolve_product_regulatory_posture'
      when coalesce(o.soil_confirmed,false) then 'perform_project_specific_pretest_and_resolve_adjacent_surfaces_runoff_and_route_compatibility'
      when coalesce(o.soil_likely_visual,false) then 'obtain_close_range_or_field_confirmation_of_stain_origin' else 'verify_actual_stain_morphology_and_origin' end next_action,
 'A masonry-restoration classification establishes substrate/context interest only. OneRestore fit requires actual stain-origin evidence, current product documentation, pretesting, adjacent-material review, runoff/receptor controls and mapped operator delivery compatibility. No automatic score uplift is allowed.'::text guardrail
from base b left join rules r on r.surface_type_id=b.resolved_surface_type_id cross join product p
left join obs o on o.building_source_record_id=b.building_source_record_id and o.soil_type_id=r.soil_type_id
left join cleaning.v_product_regulatory_readiness_v3 pr on pr.product_id=p.id;

create or replace view cleaning.v_onerestore_candidate_building_queue_v1 as
select building_source_record_id,array_agg(distinct candidate_key) candidate_keys,max(restoration_classification_confidence) restoration_classification_confidence,
 max(resolved_facade_material) resolved_facade_material,max(resolved_raw_facade_material) resolved_raw_facade_material,bool_or(soil_confirmed) any_confirmed_stain,bool_or(soil_likely_visual) any_likely_stain,
 bool_or(product_test_patch_candidate) any_product_test_patch_candidate,array_remove(array_agg(distinct soil_slug),null::text) evaluated_soil_classes,
 case when bool_or(product_test_patch_candidate) then 'product_test_patch_candidate' when bool_or(soil_likely_visual) then 'field_stain_confirmation_required'
      when max(resolved_facade_material)='limestone' then 'limestone_stain_verification_high' when max(resolved_facade_material)='brick' then 'brick_stain_verification' else 'surface_resolution_required' end verification_priority,
 false chemistry_scoreable,0 automatic_score_delta,
 'Building-level queue is deduplicated. Product fit remains stain-specific and no score uplift occurs from substrate or product ownership alone.'::text guardrail
from cleaning.v_onerestore_candidate_scaffold_v1 group by building_source_record_id;

create or replace view decisioning.v_provider_chemistry_execution_fit_v3 as
with route as (
 select r.organization_id,r.provider_product_id,r.product_id,
  count(*) filter(where r.status is distinct from 'inactive') active_rig_product_rows,
  bool_or(r.status is distinct from 'inactive' and r.readiness_status='compatible') has_compatible_route,
  bool_or(r.status is distinct from 'inactive' and r.readiness_status='conditional') has_conditional_route,
  bool_or(r.status is distinct from 'inactive' and r.readiness_status=any(array['route_not_assigned','route_mapping_incomplete','compatibility_unresolved'])) has_unresolved_route,
  bool_or(r.status is distinct from 'inactive' and r.readiness_status=any(array['blocked','not_recommended'])) has_blocked_or_not_recommended_route,
  count(*) filter(where r.status is distinct from 'inactive' and r.readiness_status='compatible') compatible_route_count,
  count(*) filter(where r.status is distinct from 'inactive' and r.readiness_status='conditional') conditional_route_count,
  count(*) filter(where r.status is distinct from 'inactive' and r.readiness_status=any(array['route_not_assigned','route_mapping_incomplete','compatibility_unresolved'])) unresolved_route_count,
  max(r.compatibility_confidence) max_route_compatibility_confidence,bool_or(coalesce(r.manufacturer_verification_required,false)) manufacturer_verification_required
 from cleaning.v_provider_rig_product_readiness r group by r.organization_id,r.provider_product_id,r.product_id
)
select b.organization_id,b.provider_product_id,b.product_id,b.product_slug,b.product_name,b.provider_product_status,b.rule_id,b.surface_type_id,b.surface_slug,b.soil_type_id,b.soil_slug,b.service_type_id,b.service_slug,b.rule_disposition,
 pr.current_sds_status,pr.current_label_status,pr.current_technical_data_status,pr.pesticidal_claim_basis_status,pr.federal_pesticide_registration_status,pr.federal_exemption_basis_status,pr.documentation_ready,pr.federal_regulatory_ready,pr.federal_resolution_state,
 coalesce(rt.active_rig_product_rows,0) active_rig_product_rows,coalesce(rt.compatible_route_count,0) compatible_route_count,coalesce(rt.conditional_route_count,0) conditional_route_count,coalesce(rt.unresolved_route_count,0) unresolved_route_count,
 coalesce(rt.has_compatible_route,false) has_compatible_route,coalesce(rt.has_conditional_route,false) has_conditional_route,coalesce(rt.has_unresolved_route,false) has_unresolved_route,coalesce(rt.has_blocked_or_not_recommended_route,false) has_blocked_or_not_recommended_route,
 rt.max_route_compatibility_confidence,coalesce(rt.manufacturer_verification_required,false) route_manufacturer_verification_required,(coalesce(rt.has_compatible_route,false) or coalesce(rt.has_conditional_route,false)) route_execution_ready,
 case when b.provider_product_status='inactive' then 'inactive' when b.product_id is null then 'product_identity_unresolved' when b.rule_disposition=any(array['hard_stop','avoid']) then 'capability_blocked'
      when not coalesce(pr.documentation_ready,false) then 'product_documentation_unresolved' when pr.pesticidal_claim_basis_status=any(array['resolution_required','not_established','unknown']) or pr.pesticidal_claim_basis_status is null then 'regulatory_claim_basis_unresolved'
      when not coalesce(pr.federal_regulatory_ready,false) then 'regulatory_registration_or_exemption_unresolved' when coalesce(rt.active_rig_product_rows,0)=0 then 'route_assignment_required'
      when coalesce(rt.has_compatible_route,false) and b.rule_disposition=any(array['preferred','allowed']) then 'capability_supported'
      when (coalesce(rt.has_compatible_route,false) or coalesce(rt.has_conditional_route,false)) and b.rule_disposition=any(array['conditional','test_patch']) then 'capability_conditional'
      when coalesce(rt.has_conditional_route,false) then 'capability_conditional' when coalesce(rt.has_unresolved_route,false) then 'route_compatibility_unresolved'
      when coalesce(rt.has_blocked_or_not_recommended_route,false) then 'route_compatibility_blocked' else 'capability_insufficient_data' end capability_state_v3,
 0 calibrated_score_delta,false score_calibrated,
 'V3 accepts current product-specific technical data for non-pesticidal professional chemicals while still requiring current SDS, resolved claim/regulatory posture, declared inventory and a mapped compatible rig fluid route. Product possession alone never increases opportunity score.'::text guardrail
from decisioning.v_provider_chemistry_execution_fit_v1 b left join cleaning.v_product_regulatory_readiness_v3 pr on pr.product_id=b.product_id
left join route rt on rt.organization_id=b.organization_id and rt.provider_product_id=b.provider_product_id and rt.product_id=b.product_id;

create or replace view decisioning.v_onerestore_provider_opportunity_fit_v1 as
select f.building_source_record_id,f.candidate_key,f.state_code,f.product_id,f.product_slug,f.surface_type_id,f.surface_slug,f.soil_type_id,f.soil_slug,f.onerestore_fit_state,f.product_test_patch_candidate,
 pc.organization_id,pc.provider_product_id,pc.capability_state_v3,pc.active_rig_product_rows,pc.compatible_route_count,pc.conditional_route_count,pc.unresolved_route_count,pc.route_execution_ready,
 case when f.onerestore_fit_state='stain_evidence_confirmed_test_patch_required' and pc.capability_state_v3='capability_conditional' then 'operator_test_patch_candidate'
      when f.onerestore_fit_state=any(array['surface_resolution_required','product_surface_stain_rule_unresolved','product_documentation_unresolved','federal_regulatory_resolution_required','stain_visual_requires_field_confirmation','stain_morphology_verification_required']) then 'operator_fit_blocked_by_candidate_gate'
      when pc.capability_state_v3=any(array['inactive','product_identity_unresolved','capability_blocked','product_documentation_unresolved','regulatory_claim_basis_unresolved','regulatory_registration_or_exemption_unresolved','route_assignment_required','route_compatibility_unresolved','route_compatibility_blocked','capability_insufficient_data']) then 'operator_fit_blocked_by_provider_gate'
      else 'operator_fit_unresolved' end operator_fit_state,
 0 calibrated_score_delta,false score_calibrated,
 'OneRestore operator fit requires confirmed stain origin, product-specific test patch, adjacent-material/runoff controls and a mapped compatible rig route. Numeric uplift remains zero until field outcomes justify calibration.'::text guardrail
from cleaning.v_onerestore_candidate_scaffold_v1 f
join decisioning.v_provider_chemistry_execution_fit_v3 pc on pc.product_id=f.product_id and pc.surface_type_id=f.surface_type_id and pc.soil_type_id=f.soil_type_id;
