-- Research-only correction: allow descriptive words between recoat/recoating and roof.

create or replace view research.v_surface_preservation_semantic_probe as
with scope_rows as (
  select 'indiana-dlgf-school-capital-projects'::text source_slug,r.source_native_id,r.raw_payload->>'unit_name' buyer_name,r.raw_payload->>'project_title' project_label,r.raw_payload->>'plan_year' timing_text,r.raw_payload->>'estimated_cost' amount_text,'project_row'::text evidence_granularity,concat_ws(' ',r.raw_payload->>'project_title',r.raw_payload->>'description',r.raw_payload->>'raw_block') scope_text
  from ingest.raw_records r join ingest.sources s on s.id=r.source_id
  where s.slug='indiana-dlgf-school-capital-projects' and r.source_native_id like 'candidate|%'
  union all
  select 'kde-district-facility-plans',r.source_native_id,r.raw_payload->>'district_label',coalesce(r.raw_payload->>'document_name',r.source_native_id),coalesce(r.raw_payload->>'schedule_bucket',r.raw_payload->>'kde_approval_date_text'),r.raw_payload->>'estimated_cost','document_text',r.raw_payload->>'extracted_text'
  from ingest.raw_records r join ingest.sources s on s.id=r.source_id
  where s.slug='kde-district-facility-plans' and coalesce(r.raw_payload->>'extracted_text','')<>''
  union all
  select 'ky-cpab-2024-2030-projects',r.source_native_id,r.raw_payload->>'agency_name',coalesce(r.raw_payload->>'project_title',r.raw_payload->>'document_name',r.source_native_id),coalesce(r.raw_payload->>'biennium',r.raw_payload->>'plan_year'),r.raw_payload->>'estimated_budget',case when coalesce(r.raw_payload->>'project_title','')<>'' then 'project_or_document_text' else 'document_text' end,coalesce(r.raw_payload->>'extracted_text',r.raw_payload->>'raw_line',r.raw_payload::text)
  from ingest.raw_records r join ingest.sources s on s.id=r.source_id
  where s.slug='ky-cpab-2024-2030-projects'
), normalized as (
 select *,lower(coalesce(scope_text,'')) scope_lc from scope_rows
), matched as (
 select n.*,f.signal_family,f.family_regex
 from normalized n
 cross join lateral (values
  ('masonry_restoration_tuckpoint_seal'::text,'(clean(ing)?[^a-z]{0,35}(brick|masonry|stone)|tuck[ -]?point|repoint|masonry restoration|masonry repair[^a-z]{0,35}(seal|clean)|seal(ing)?[^a-z]{0,30}(masonry|brick|stone))'::text),
  ('joint_sealant_caulk','(joint sealant|exterior sealant|sealant replacement|caulk|caulking)'),
  ('waterproofing','(waterproofing|water proofing|waterproof[^a-z]{0,30}(wall|masonry|concrete|exterior|roof structure))'),
  ('eifs_dryvit_preservation','(eifs|dryvit|dri-it)'),
  ('concrete_clean_repair_coat','(concrete cleaning|clean(ing)?[^a-z]{0,25}concrete|concrete[^a-z]{0,30}(repair|coat|coating|sealant|sealer))'),
  ('roof_recoat_restoration','(roof restoration|restore[^a-z]{0,20}roof|roof recover|roof re-cover|recover[^a-z]{0,20}roof|roof resurfacing|roof membrane coating|fluid[- ]applied roof|silicone[^a-z]{0,20}roof|acrylic[^a-z]{0,20}roof|elastomeric[^a-z]{0,20}roof|recoat(ing)?.{0,60}roof|roof.{0,60}recoat(ing)?)'),
  ('exterior_paint_recoat','(exterior[^a-z]{0,40}(paint|painting|repaint|coat|coating)|repaint[^a-z]{0,30}(exterior|eifs|dryvit)|recoat[^a-z]{0,30}(exterior|eifs|dryvit))')
 ) f(signal_family,family_regex)
 where n.scope_lc ~ f.family_regex
), flags as (
 select *,
  (scope_lc ~ '(pressure wash|power wash|wash(ing)?[^a-z]{0,35}(exterior|brick|masonry|concrete|eifs|surface)|clean(ing)?[^a-z]{0,35}(brick|masonry|stone|concrete|eifs|exterior))') cleaning_explicit,
  case signal_family
   when 'masonry_restoration_tuckpoint_seal' then (scope_lc ~ '(tuck[ -]?point|repoint|masonry restoration|seal(ing)?[^a-z]{0,30}(masonry|brick|stone))')
   when 'joint_sealant_caulk' then true
   when 'waterproofing' then true
   when 'eifs_dryvit_preservation' then (scope_lc ~ '(paint|repaint|coat|coating|repair|resurface)')
   when 'concrete_clean_repair_coat' then (scope_lc ~ '(repair|coat|coating|sealant|sealer)')
   when 'roof_recoat_restoration' then true
   when 'exterior_paint_recoat' then true
   else false end downstream_treatment_explicit
 from matched
)
select source_slug,source_native_id,buyer_name,project_label,timing_text,amount_text,evidence_granularity,signal_family,cleaning_explicit,downstream_treatment_explicit,
 case when cleaning_explicit and downstream_treatment_explicit then case when evidence_granularity='project_row' then 'explicit_cleaning_plus_treatment_same_project_row' else 'cleaning_plus_treatment_same_document_requires_scope_resolution' end
      when cleaning_explicit then 'explicit_cleaning_downstream_treatment_unresolved'
      when downstream_treatment_explicit then 'downstream_treatment_explicit_prep_unresolved'
      else 'adjacent_envelope_work_only' end cleaning_relationship_semantics,
 left(scope_text,1800) evidence_excerpt
from flags;

create or replace view research.v_surface_preservation_semantic_summary as
select source_slug,signal_family,cleaning_relationship_semantics,count(*)::bigint records
from research.v_surface_preservation_semantic_probe
group by source_slug,signal_family,cleaning_relationship_semantics;

revoke all on research.v_surface_preservation_semantic_probe from anon,authenticated;
revoke all on research.v_surface_preservation_semantic_summary from anon,authenticated;
