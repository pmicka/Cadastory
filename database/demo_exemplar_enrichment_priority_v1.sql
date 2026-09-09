-- Dynamic demo-exemplar enrichment priority layer.
--
-- This is a private developer-side prioritization contract. It does not freeze the
-- portfolio, change opportunity scores, or expose new public/MCP surfaces.

create table if not exists research.demo_exemplar_priorities_v1 (
  exemplar_key text primary key,
  candidate_key text,
  subject_type text not null default 'opportunity',
  subject_id uuid,
  display_name text not null,
  organization_id uuid,
  organization_name text,
  exemplar_class text not null,
  priority integer not null,
  desired_evidence text[] not null default '{}'::text[],
  worker_routes text[] not null default '{}'::text[],
  source_roots jsonb not null default '[]'::jsonb check (jsonb_typeof(source_roots) = 'array'),
  context jsonb not null default '{}'::jsonb check (jsonb_typeof(context) = 'object'),
  rationale text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table research.demo_exemplar_priorities_v1 enable row level security;
revoke all on research.demo_exemplar_priorities_v1 from anon, authenticated;
comment on table research.demo_exemplar_priorities_v1 is
  'Private developer-side pins for demo exemplars. Pins boost enrichment but do not freeze the portfolio; dynamic exemplar views continue to admit new candidates.';

-- Manually curated anchor/contrast examples. Dynamic views below keep admitting
-- additional candidates, so this list is intentionally not the full demo bench.
insert into research.demo_exemplar_priorities_v1 (
  exemplar_key,candidate_key,subject_type,display_name,exemplar_class,priority,
  desired_evidence,worker_routes,rationale
) values
('water_tank:7548dc59-63f1-4f3e-ab97-a983f31e46f0','water_tank:7548dc59-63f1-4f3e-ab97-a983f31e46f0','opportunity','FAIRVIEW DR','water_tank_anchor',-130000,array['morphology','surface_work_status','buyer_contact','procurement','site_access','portfolio_context'],array['document_evidence','buyer_document_evidence','site_access','water_portfolio'],'Strong end-to-end maintenance/coating and favorable geometry anchor.'),
('water_tank:db2082b2-81fc-453b-82f9-beb098d2920b','water_tank:db2082b2-81fc-453b-82f9-beb098d2920b','opportunity','GARRETT','water_tank_anchor',-131000,array['morphology','surface_work_status','buyer_contact','procurement','site_access','portfolio_context'],array['document_evidence','buyer_document_evidence','site_access','water_portfolio'],'Explicit exterior coating scope with unresolved morphology; highest information-gain tank.'),
('water_tank:a5ffa1cd-626f-4735-b1a3-5849a443b0ee','water_tank:a5ffa1cd-626f-4735-b1a3-5849a443b0ee','opportunity','SOUTH PRESSURE ZONE TANK','water_tank_operator_fit',-126000,array['morphology','surface_work_status','buyer_contact','procurement','site_access','portfolio_context'],array['document_evidence','buyer_document_evidence','site_access','water_portfolio'],'BGMU favorable operator-fit comparison.'),
('water_tank:e7e84f50-ea1c-4f5b-88af-42a277f64cb1','water_tank:e7e84f50-ea1c-4f5b-88af-42a277f64cb1','opportunity','WKU','water_tank_operator_fit',-125000,array['morphology','surface_work_status','buyer_contact','procurement','site_access','portfolio_context'],array['document_evidence','buyer_document_evidence','site_access','water_portfolio'],'BGMU favorable high-capacity comparison.'),
('water_tank:ae896fca-9238-4833-92e9-34c0da0ff113','water_tank:ae896fca-9238-4833-92e9-34c0da0ff113','opportunity','RESERVOIR HILL #2','water_tank_contrast',-124000,array['morphology','surface_work_status','buyer_contact','procurement','site_access','portfolio_context'],array['document_evidence','buyer_document_evidence','site_access','water_portfolio'],'BGMU challenging cross-braced comparison.'),
('water_tank:fc71769f-28db-46cf-9c1b-89c67578ba2a','water_tank:fc71769f-28db-46cf-9c1b-89c67578ba2a','opportunity','CAVE MILL RD','water_tank_contrast',-121000,array['morphology','surface_work_status','buyer_contact','procurement','site_access'],array['document_evidence','buyer_document_evidence','site_access'],'Additional BGMU challenging geometry exemplar.'),
('water_tank:e7e306d9-01c8-4e2f-b31d-42c3fb09e8cb','water_tank:e7e306d9-01c8-4e2f-b31d-42c3fb09e8cb','opportunity','OFFICE TANK','water_tank_contrast',-122000,array['morphology','surface_work_status','current_project_status','buyer_contact','procurement','site_access'],array['document_evidence','buyer_document_evidence','site_access'],'Scheduled-treatment evidence plus challenging geometry.'),
('water_tank:5c8f28f1-cbeb-4ae6-86da-28bfd80fe753','water_tank:5c8f28f1-cbeb-4ae6-86da-28bfd80fe753','opportunity','MONTGOMERY LN TANK','water_tank_surface_work',-123000,array['morphology','surface_work_status','current_project_status','buyer_contact','procurement','site_access'],array['document_evidence','buyer_document_evidence','site_access'],'Explicit exterior treatment scope with geometry gap.'),
('water_tank:267023f5-8ffa-409d-a02e-1cb2841c9940','water_tank:267023f5-8ffa-409d-a02e-1cb2841c9940','opportunity','EAST OFFICE TANK','water_tank_account',-119000,array['morphology','surface_work_status','buyer_contact','procurement','site_access','portfolio_context'],array['document_evidence','buyer_document_evidence','site_access','water_portfolio'],'Harrodsburg account exemplar with unresolved geometry.'),
('water_tank:d252df99-0c29-4543-a43d-1b8b57f8e7c6','water_tank:d252df99-0c29-4543-a43d-1b8b57f8e7c6','opportunity','SUNBEAM RD.','water_tank_account',-120000,array['morphology','surface_work_status','buyer_contact','procurement','site_access','portfolio_context'],array['document_evidence','buyer_document_evidence','site_access','water_portfolio'],'Completes Leitchfield operability picture.'),
('water_tank:b9b9db13-f4d1-4d77-aa5d-a48d616602a1','water_tank:b9b9db13-f4d1-4d77-aa5d-a48d616602a1','opportunity','SCHOOL ST.','water_tank_contrast',-115000,array['surface_work_status','buyer_contact','procurement','site_access','portfolio_context'],array['document_evidence','buyer_document_evidence','site_access','water_portfolio'],'Leitchfield challenging-geometry contrast.'),
('water_tank:f709febe-b1f7-4727-8c66-badaff2032f0','water_tank:f709febe-b1f7-4727-8c66-badaff2032f0','opportunity','ORCHARD ST.','water_tank_contrast',-115000,array['surface_work_status','buyer_contact','procurement','site_access','portfolio_context'],array['document_evidence','buyer_document_evidence','site_access','water_portfolio'],'Leitchfield challenging-geometry contrast.'),
('water_tank:cbcedace-fda9-49cc-8b68-6a5186166b22','water_tank:cbcedace-fda9-49cc-8b68-6a5186166b22','opportunity','WALMART','water_tank_bench',-113000,array['surface_work_status','buyer_contact','procurement','site_access','portfolio_context'],array['document_evidence','buyer_document_evidence','site_access','water_portfolio'],'Favorable high-capacity Columbia/Adair bench.'),
('water_tank:900e6502-8474-40d7-8770-94715e8789da','water_tank:900e6502-8474-40d7-8770-94715e8789da','opportunity','SPARKESVILLE','water_tank_bench',-112500,array['surface_work_status','buyer_contact','procurement','site_access','portfolio_context'],array['document_evidence','buyer_document_evidence','site_access','water_portfolio'],'Favorable Columbia/Adair bench.'),
('water_tank:d4cacf8b-7642-4eea-912d-4a54e0b9f5f4','water_tank:d4cacf8b-7642-4eea-912d-4a54e0b9f5f4','opportunity','US 421 TANK','water_tank_bench',-112000,array['surface_work_status','buyer_contact','procurement','site_access','portfolio_context'],array['document_evidence','buyer_document_evidence','site_access','water_portfolio'],'Favorable Southern Madison bench.'),
('water_tank:eaa2f8a6-fd4c-4c50-aef5-838dd48a83d1','water_tank:eaa2f8a6-fd4c-4c50-aef5-838dd48a83d1','opportunity','LANES VIEW TANK','water_tank_bench',-111500,array['surface_work_status','buyer_contact','procurement','site_access','portfolio_context'],array['document_evidence','buyer_document_evidence','site_access','water_portfolio'],'Favorable Northeast Woodford bench.'),
('water_tank:ed18a77d-bcbc-4682-ad69-78b5931ce9f0','water_tank:ed18a77d-bcbc-4682-ad69-78b5931ce9f0','opportunity','MIZPAH','water_tank_bench',-111000,array['surface_work_surface_resolution','buyer_contact','procurement','site_access','portfolio_context'],array['document_evidence','buyer_document_evidence','site_access','water_portfolio'],'Favorable geometry with treatment-surface ambiguity.'),
('exterior_cleaning:ebdfc175-46d3-4f3a-bbf6-e7a9c9488013','exterior_cleaning:ebdfc175-46d3-4f3a-bbf6-e7a9c9488013','opportunity','755 DIXIE HIGHWAY','environmental_cleaning_anchor',-129000,array['visible_condition','facade_material','glazing','specialty_service_fit','buyer_contact','procurement','site_access','execution_preflight'],array['document_evidence','facade_attributes','buyer_document_evidence','site_access','cleaning_preflight'],'Strong Baudoinia proxy with resolved commercial context.'),
('exterior_cleaning:6f7d405f-73d7-4e5a-af74-d1e9b1a19f10','exterior_cleaning:6f7d405f-73d7-4e5a-af74-d1e9b1a19f10','opportunity','1720 W BROADWAY','environmental_cleaning_bench',-120000,array['visible_condition','facade_material','glazing','specialty_service_fit','buyer_contact','procurement','site_access'],array['document_evidence','facade_attributes','buyer_document_evidence','site_access'],'Strong Baudoinia proxy and scale.'),
('exterior_cleaning:acd96fa4-0a03-4d09-b5ac-ef1cc7127db3','exterior_cleaning:acd96fa4-0a03-4d09-b5ac-ef1cc7127db3','opportunity','3301 DIXIE HIGHWAY','environmental_cleaning_bench',-120000,array['visible_condition','facade_material','glazing','specialty_service_fit','buyer_contact','procurement','site_access'],array['document_evidence','facade_attributes','buyer_document_evidence','site_access'],'Strong Baudoinia proxy and scale.'),
('exterior_cleaning:8e53a392-b32c-419f-a420-556180128926','exterior_cleaning:8e53a392-b32c-419f-a420-556180128926','opportunity','704 CENTRAL AVENUE','premium_facade_anchor',-128000,array['building_identity','visible_condition','facade_material','glazing','specialty_service_fit','buyer_contact','procurement','site_access','execution_preflight'],array['building_identity','document_evidence','facade_attributes','buyer_document_evidence','site_access','cleaning_preflight'],'Kentucky Derby Museum/Churchill Downs premium-facade anchor; identity must remain exact.'),
('exterior_cleaning:8db60fe5-94e6-49c7-a3e1-91623f6d9f59','exterior_cleaning:8db60fe5-94e6-49c7-a3e1-91623f6d9f59','opportunity','1121 INDUSTRIAL DRIVE','large_exterior_bench',-108000,array['visible_condition','facade_material','buyer_contact','site_access'],array['document_evidence','facade_attributes','buyer_document_evidence','site_access'],'Large industrial exterior bench.'),
('exterior_cleaning:743d279b-5994-4fb1-ac4a-d9e74e846a66','exterior_cleaning:743d279b-5994-4fb1-ac4a-d9e74e846a66','opportunity','2727 KENTRONICS DRIVE','large_exterior_bench',-107500,array['visible_condition','facade_material','buyer_contact','site_access'],array['document_evidence','facade_attributes','buyer_document_evidence','site_access'],'Large industrial exterior bench.'),
('exterior_cleaning:53b9c932-e9a0-49a8-a8c8-0eab10d77705','exterior_cleaning:53b9c932-e9a0-49a8-a8c8-0eab10d77705','opportunity','3795 EAST JOHN ROWAN BOULEVARD','large_exterior_bench',-107000,array['visible_condition','facade_material','glazing','buyer_contact','procurement','site_access'],array['document_evidence','facade_attributes','buyer_document_evidence','site_access'],'Large retail/property-route exemplar.'),
('exterior_cleaning:4b5cf14e-f3ef-4900-bf03-8498b623372e','exterior_cleaning:4b5cf14e-f3ef-4900-bf03-8498b623372e','opportunity','410 NORTH 5TH STREET','institutional_exterior_bench',-107000,array['visible_condition','facade_material','glazing','buyer_contact','procurement','site_access'],array['document_evidence','facade_attributes','buyer_document_evidence','site_access'],'School-system exterior exemplar.'),
('exterior_cleaning:89bc24ca-b6ac-47d5-9788-09d44ea65dfe','exterior_cleaning:89bc24ca-b6ac-47d5-9788-09d44ea65dfe','opportunity','3050 COMMERCE CENTER PLACE','institutional_exterior_bench',-106500,array['visible_condition','facade_material','buyer_contact','procurement','site_access'],array['document_evidence','facade_attributes','buyer_document_evidence','site_access'],'Louisville MSD exterior exemplar.'),
('exterior_cleaning:99e192e4-b29c-4593-8e4a-38b38f7d64dd','exterior_cleaning:99e192e4-b29c-4593-8e4a-38b38f7d64dd','opportunity','607 INDUSTRY ROAD','industrial_exterior_bench',-106000,array['visible_condition','facade_material','buyer_contact','site_access'],array['document_evidence','facade_attributes','buyer_document_evidence','site_access'],'Industrial/logistics exterior exemplar.'),
('exterior_cleaning:7c890eed-6773-48be-b96e-0aecb646719b','exterior_cleaning:7c890eed-6773-48be-b96e-0aecb646719b','opportunity','700 W JEFFERSON STREET','institutional_exterior_bench',-106000,array['visible_condition','facade_material','glazing','buyer_contact','procurement','site_access'],array['document_evidence','facade_attributes','buyer_document_evidence','site_access'],'Large public facility exemplar.'),
('exterior_cleaning:73895285-ad34-4850-9734-a1a8672a67bd','exterior_cleaning:73895285-ad34-4850-9734-a1a8672a67bd','opportunity','1070 BLOOMFIELD ROAD','institutional_exterior_bench',-105500,array['visible_condition','facade_material','glazing','buyer_contact','site_access'],array['document_evidence','facade_attributes','buyer_document_evidence','site_access'],'School-system exterior exemplar.'),
('exterior_cleaning:339b90b1-e4ea-445c-8d07-03ed0b133879','exterior_cleaning:339b90b1-e4ea-445c-8d07-03ed0b133879','opportunity','301 ABRAHAM FLEXNER WAY','campus_portfolio_bench',-105500,array['visible_condition','facade_material','glazing','buyer_contact','procurement','site_access','portfolio_context'],array['document_evidence','facade_attributes','buyer_document_evidence','site_access','portfolio_account'],'UofL campus repeat-account exemplar.'),
('exterior_cleaning:9c70705c-50c4-403e-8689-ae1b8aeb8b93','exterior_cleaning:9c70705c-50c4-403e-8689-ae1b8aeb8b93','opportunity','2035 S 3RD STREET','premium_facade_bench',-105000,array['visible_condition','facade_material','glazing','specialty_service_fit','buyer_contact','site_access'],array['document_evidence','facade_attributes','buyer_document_evidence','site_access'],'Speed Art Museum premium/public-image exemplar.'),
('exterior_cleaning:8845dcd6-edd4-42c8-98d7-53c2c2da8ab1','exterior_cleaning:8845dcd6-edd4-42c8-98d7-53c2c2da8ab1','opportunity','2000 UNITY PLACE','pure_water_anchor',-127000,array['visible_condition','facade_material','glazing','pure_water_fit','buyer_contact','procurement','site_access','water_access'],array['document_evidence','facade_attributes','buyer_document_evidence','site_access','cleaning_water'],'Supported repeated glazing and UofL route; strong pure-water exemplar.'),
('exterior_cleaning:12e3eb30-3df2-45ae-967f-a1fb1ccff0c4','exterior_cleaning:12e3eb30-3df2-45ae-967f-a1fb1ccff0c4','opportunity','310 WEST STEPHEN FOSTER AVENUE','masonry_baudoinia_anchor',-126500,array['visible_condition','facade_material','organic_growth_or_staining','masonry_fit','buyer_contact','procurement','site_access'],array['document_evidence','facade_attributes','buyer_document_evidence','site_access'],'Supported brick plus strong Baudoinia exposure proxy.'),
('exterior_cleaning:35c207af-367f-4cf9-9b12-62ed56123fe4','exterior_cleaning:35c207af-367f-4cf9-9b12-62ed56123fe4','opportunity','213 WEST STEPHEN FOSTER AVENUE','masonry_baudoinia_bench',-124500,array['visible_condition','facade_material','organic_growth_or_staining','masonry_fit','buyer_contact','procurement','site_access'],array['document_evidence','facade_attributes','buyer_document_evidence','site_access'],'Supported brick plus strong Baudoinia exposure proxy.'),
('exterior_cleaning:c39553eb-001b-4450-816f-e398bbef3b69','exterior_cleaning:c39553eb-001b-4450-816f-e398bbef3b69','opportunity','1001 S 4TH STREET','limestone_restoration_anchor',-127500,array['visible_condition','facade_material','staining_or_efflorescence','masonry_fit','chemistry_fit','buyer_contact','procurement','site_access'],array['document_evidence','facade_attributes','chemistry_decisioning','buyer_document_evidence','site_access'],'Supported limestone; strong restoration exemplar if condition verifies.'),
('funded_pain:ba106092-0359-410a-9ede-f5773d0fa99a','funded_pain:ba106092-0359-410a-9ede-f5773d0fa99a','opportunity','Lafayette High School (1939, 1965, 1973, 1975)','documented_cleaning_scope_anchor',-132000,array['cleaning_scope','facade_material','tuckpointing','current_project_status','buyer_contact','procurement','site_access'],array['document_evidence','buyer_document_evidence','site_access'],'Public plan explicitly calls for cleaning brick and tuck pointing.'),
('funded_pain:579ecc17-c722-4109-8ac0-bb423fa6f3c4','funded_pain:579ecc17-c722-4109-8ac0-bb423fa6f3c4','opportunity','North Jackson Elementary 2009, 2011','documented_cleaning_scope_anchor',-132000,array['cleaning_scope','facade_material','eifs_fit','current_project_status','buyer_contact','procurement','site_access'],array['document_evidence','buyer_document_evidence','site_access'],'Public plan explicitly calls for cleaning EIFS.')
on conflict (exemplar_key) do update set
  candidate_key=excluded.candidate_key,
  subject_type=excluded.subject_type,
  display_name=excluded.display_name,
  exemplar_class=excluded.exemplar_class,
  priority=excluded.priority,
  desired_evidence=excluded.desired_evidence,
  worker_routes=excluded.worker_routes,
  rationale=excluded.rationale,
  active=true,
  updated_at=now();

insert into research.demo_exemplar_priorities_v1 (
  exemplar_key,subject_type,subject_id,display_name,organization_name,exemplar_class,
  priority,desired_evidence,worker_routes,context,rationale
)
select
  'premium:'||p.id::text,
  'premium_target',p.id,p.name,p.operator_name,'premium_facade_target',
  case when p.facade_opportunity_score >= 90 then -125000 else -116000 end,
  array['building_identity','visible_condition','facade_material','glazing','pure_water_or_envelope_fit','buyer_contact','procurement','site_access','execution_preflight']::text[],
  array['building_identity','document_evidence','facade_attributes','buyer_document_evidence','site_access','cleaning_preflight']::text[],
  jsonb_build_object(
    'address_text',p.address_text,
    'building_source_record_id',p.building_source_record_id,
    'facade_opportunity_score',p.facade_opportunity_score,
    'opportunity_tier',p.opportunity_tier,
    'premium_confidence',p.confidence
  ),
  'High-value premium facade target; identity guardrails remain authoritative.'
from intelligence.v_premium_exterior_canonical_opportunities p
where p.name in (
  'Kentucky International Convention Center','PNC Tower','400 West Market',
  'Kentucky Derby Museum','Hotel Distil','Moxy Louisville Downtown'
)
on conflict (exemplar_key) do update set
  subject_id=excluded.subject_id,
  display_name=excluded.display_name,
  organization_name=excluded.organization_name,
  priority=excluded.priority,
  desired_evidence=excluded.desired_evidence,
  worker_routes=excluded.worker_routes,
  context=excluded.context,
  active=true,
  updated_at=now();

create or replace view research.v_demo_exemplar_enrichment_queue_v1 as
with manual_rows as (
  select p.exemplar_key,p.candidate_key,p.subject_type,p.subject_id,p.display_name,
         p.organization_id,p.organization_name,p.exemplar_class,p.priority,
         p.desired_evidence,p.worker_routes,p.source_roots,p.context,p.rationale,
         'manual_pin'::text as selection_basis
  from research.demo_exemplar_priorities_v1 p
  where p.active
),
water_bench as (
  select s.candidate_key as exemplar_key,s.candidate_key,'opportunity'::text as subject_type,
         split_part(s.candidate_key,':',2)::uuid as subject_id,s.display_name,
         null::uuid as organization_id,s.buyer_name as organization_name,
         case when g.context->>'operator_cleaning_geometry_assessment' in ('favorable','challenging')
              then 'water_tank_operator_fit' else 'water_tank_high_signal' end as exemplar_class,
         case when g.context->>'operator_cleaning_geometry_assessment'='favorable' then -110000
              when g.context->>'operator_cleaning_geometry_assessment'='challenging' then -106000
              else -102000 end as priority,
         array['morphology','surface_work_status','buyer_contact','procurement','site_access','portfolio_context']::text[] as desired_evidence,
         array['document_evidence','buyer_document_evidence','site_access','water_portfolio']::text[] as worker_routes,
         '[]'::jsonb as source_roots,
         jsonb_build_object('state_code',s.state_code,'county_name',s.county_name,
           'signal_strength',s.signal_strength,'opportunity_confidence',s.confidence,
           'site_access_status',s.site_access_status,
           'geometry_assessment',g.context->>'operator_cleaning_geometry_assessment',
           'morphology_class',g.context->>'morphology_class') as context,
         'Dynamic high-confidence active water-tank bench.'::text as rationale,
         'dynamic_water_bench'::text as selection_basis
  from scout.v_opportunity_spine_cards s
  left join scout.v_opportunity_water_tank_geometry_context g on g.candidate_key=s.candidate_key
  where s.candidate_key like 'water_tank:%'
    and s.time_sensitive
    and s.signal_strength='high'
    and s.confidence>=0.90
    and s.buyer_contact_status<>'unresolved'
),
exterior_bench as (
  select s.candidate_key,s.candidate_key,'opportunity'::text,
         split_part(s.candidate_key,':',2)::uuid,s.display_name,null::uuid,s.buyer_name,
         case when s.confidence>=0.70 then 'environmental_cleaning_signal' else 'large_exterior_opportunity' end,
         case when s.confidence>=0.70 then -108000 else -98000 end,
         array['visible_condition','facade_material','glazing','specialty_service_fit','buyer_contact','procurement','site_access']::text[],
         array['document_evidence','facade_attributes','buyer_document_evidence','site_access']::text[],
         '[]'::jsonb,
         jsonb_build_object('state_code',s.state_code,'county_name',s.county_name,'why_now',s.why_now,
           'opportunity_confidence',s.confidence,'commercial_scale_summary',s.commercial_scale_summary),
         'Dynamic exterior-cleaning bench selected for signal strength or large documented scale.'::text,
         'dynamic_exterior_bench'::text
  from scout.v_opportunity_spine_cards s
  where s.candidate_key like 'exterior_cleaning:%'
    and s.time_sensitive
    and s.commercial_scale_status='documented'
    and s.buyer_contact_status<>'unresolved'
    and s.site_access_status='mapped_context_available'
    and (s.confidence>=0.70 or coalesce(nullif(s.commercial_scale_summary#>>'{measures,0,value}','')::numeric,0)>=150000)
),
specialty_bench as (
  select q.candidate_key,q.candidate_key,'opportunity'::text,q.building_source_record_id,q.display_name,
         null::uuid,s.buyer_name,
         case when q.pure_water_state='supported' then 'pure_water_supported'
              when q.masonry_state='supported' then 'masonry_supported'
              else 'specialty_investigate' end,
         case when q.pure_water_state='supported' then -114000
              when q.masonry_state='supported' then -109000 else -100000 end,
         array['visible_condition','facade_material','glazing','pure_water_fit','masonry_fit','organic_growth_or_staining','buyer_contact','site_access']::text[],
         array['document_evidence','facade_attributes','buyer_document_evidence','site_access','chemistry_decisioning']::text[],
         case when q.website_url is not null then jsonb_build_array(q.website_url) else '[]'::jsonb end,
         jsonb_build_object('state_code',q.state_code,'county_name',q.county_name,
           'pure_water_state',q.pure_water_state,'masonry_state',q.masonry_state,
           'verification_needs',q.verification_needs,'building_source_record_id',q.building_source_record_id),
         'Dynamic specialty-service facade bench.'::text,
         'dynamic_specialty_bench'::text
  from decisioning.v_facade_visual_verification_queue_v4 q
  left join scout.v_opportunity_spine_cards s on s.candidate_key=q.candidate_key
  where q.pure_water_state in ('supported','investigate') or q.masonry_state='supported'
),
premium_bench as (
  select 'premium:'||p.id::text,null::text,'premium_target'::text,p.id,p.name,null::uuid,p.operator_name,
         'premium_facade_target'::text,
         case when p.facade_opportunity_score>=90 then -112000 else -101000 end,
         array['building_identity','visible_condition','facade_material','glazing','pure_water_or_envelope_fit','buyer_contact','procurement','site_access','execution_preflight']::text[],
         array['building_identity','document_evidence','facade_attributes','buyer_document_evidence','site_access','cleaning_preflight']::text[],
         case when p.website_url is not null then jsonb_build_array(p.website_url) else '[]'::jsonb end,
         jsonb_build_object('address_text',p.address_text,'building_source_record_id',p.building_source_record_id,
           'facade_opportunity_score',p.facade_opportunity_score,'opportunity_tier',p.opportunity_tier,
           'premium_confidence',p.confidence),
         'Dynamic high/very-high premium facade bench.'::text,
         'dynamic_premium_bench'::text
  from intelligence.v_premium_exterior_canonical_opportunities p
  where p.rankable and p.facade_opportunity_score>=74 and p.opportunity_tier in ('high','very_high')
),
all_rows as (
  select * from manual_rows
  union all select * from water_bench
  union all select * from exterior_bench
  union all select * from specialty_bench
  union all select * from premium_bench
)
select distinct on (exemplar_key) *
from all_rows
order by exemplar_key,priority asc,selection_basis asc;

create or replace view research.v_demo_exemplar_account_queue_v1 as
with pm as (
  select 'organization:'||q.organization_id::text as account_key,q.organization_id,
         q.management_company_name as display_name,'property_management'::text as exemplar_class,
         case when q.account_class='strategic_account' then -120000
              when q.account_class='portfolio_account' then -111000 else -102000 end as priority,
         array['portfolio_roster','property_crosswalk','building_attributes','current_need','operations_contact','procurement_or_vendor_route']::text[] as desired_evidence,
         array['account_portfolio_document_evidence','property_portfolio_resolver','building_identity','facade_attributes','buyer_document_evidence']::text[] as worker_routes,
         jsonb_build_object('account_class',q.account_class,
           'regional_operating_property_count',q.regional_operating_property_count,
           'known_unit_count',q.known_unit_count,'crosswalk_gap_count',q.crosswalk_gap_count,
           'resolved_building_count',q.resolved_building_count,'contact_route_quality',q.contact_route_quality,
           'procurement_route_available',q.procurement_route_available,'current_need_status',q.current_need_status,
           'missing_steps',q.missing_steps) as context
  from scout.v_property_management_account_research_queue q
  where q.account_class in ('strategic_account','portfolio_account') or coalesce(q.regional_operating_property_count,0)>=5
),
fm as (
  select 'organization:'||q.organization_id::text,q.organization_id,q.account_name,'facilities_management',
         case when q.account_class='strategic_account' then -116000
              when q.account_class='portfolio_account' then -108000 else -100000 end,
         array['portfolio_roster','current_need','operations_contact','procurement_or_vendor_route']::text[],
         array['account_portfolio_document_evidence','buyer_document_evidence','portfolio_account']::text[],
         jsonb_build_object('account_class',q.account_class,'portfolio_archetype',q.portfolio_archetype,
           'reported_client_location_count_minimum',q.reported_client_location_count_minimum,
           'missing_steps',q.missing_steps)
  from scout.v_facilities_management_research_queue q
  where q.account_class in ('strategic_account','portfolio_account','multi_site_account')
),
buyer_clusters as (
  select j.subject_key,
         case when j.subject_key like 'organization:%' then nullif(split_part(j.subject_key,':',2),'')::uuid else null::uuid end,
         j.display_name,
         case when lower(coalesce(j.display_name,'')) like '%construction%'
                   or lower(coalesce(j.display_name,'')) like '%built%' then 'builder_contractor'
              when lower(coalesce(j.display_name,'')) like '%engineering%'
                   or lower(coalesce(j.display_name,'')) like '%inspect%' then 'engineering_inspection'
              else 'multi_opportunity_account' end,
         case when coalesce((j.context->>'opportunity_count')::int,0)>=15 then -118000
              when coalesce((j.context->>'opportunity_count')::int,0)>=8 then -110000 else -101000 end,
         array['portfolio_or_project_roster','operations_contact','procurement_or_vendor_route','current_need']::text[],
         array['buyer_document_evidence','account_portfolio_document_evidence']::text[],
         j.context||jsonb_build_object('buyer_job_id',j.id,'buyer_job_state',j.state,'buyer_job_priority',j.priority)
  from research.document_evidence_jobs j
  where j.rule_pack='buyer_organization_contact_v1'
    and coalesce((j.context->>'opportunity_count')::int,0)>=5
    and j.organization_name is not null
)
select distinct on (account_key) *
from (
  select * from pm
  union all select * from fm
  union all select * from buyer_clusters
) x
order by account_key,priority asc;

revoke all on research.v_demo_exemplar_enrichment_queue_v1 from anon, authenticated;
revoke all on research.v_demo_exemplar_account_queue_v1 from anon, authenticated;
