-- Research-only refinement: distinguish facade repair-only context from coating/cleaning scope.
create or replace view research.v_public_facade_surface_work_probe as
with indiana as (
  select 'indiana-dlgf-school-capital-projects'::text as source_slug,
    r.source_native_id,r.raw_payload->>'unit_name' as buyer_name,r.raw_payload->>'project_title' as project_label,
    r.raw_payload->>'plan_year' as timing_text,r.raw_payload->>'estimated_cost' as amount_text,
    lower(concat_ws(' ',r.raw_payload->>'project_title',r.raw_payload->>'description',r.raw_payload->>'raw_block')) as scope_lc,
    left(concat_ws(' ',r.raw_payload->>'project_title',r.raw_payload->>'description',r.raw_payload->>'raw_block'),1200) as evidence_excerpt,
    'project_row'::text as evidence_granularity
  from ingest.raw_records r join ingest.sources s on s.id=r.source_id
  where s.slug='indiana-dlgf-school-capital-projects' and r.source_native_id like 'candidate|%'
    and lower(concat_ws(' ',r.raw_payload->>'project_title',r.raw_payload->>'description',r.raw_payload->>'raw_block')) ~ '(exterior[^a-z]{0,40}(paint|coat|coating|repaint)|dryvit[^a-z]{0,40}(coat|coating|paint|repaint)|eifs[^a-z]{0,40}(coat|coating|paint|repaint))'
), kde_docs as (
  select 'kde-district-facility-plans'::text as source_slug,r.source_native_id,r.raw_payload->>'district_label' as buyer_name,
    coalesce(r.raw_payload->>'document_name',r.source_native_id) as project_label,
    coalesce(r.raw_payload->>'schedule_bucket',r.raw_payload->>'kde_approval_date_text') as timing_text,
    r.raw_payload->>'estimated_cost' as amount_text,lower(coalesce(r.raw_payload->>'extracted_text','')) as scope_lc,
    r.raw_payload->>'extracted_text' as full_text,'document_text'::text as evidence_granularity
  from ingest.raw_records r join ingest.sources s on s.id=r.source_id
  where s.slug='kde-district-facility-plans' and coalesce(r.raw_payload->>'extracted_text','')<>''
    and lower(r.raw_payload->>'extracted_text') ~ '(clean eifs|clean brick|clean masonry|exterior painting|exterior paint|repaint eifs|eifs panel repair|eifs repairs|dryvit)'
), kde as (
  select source_slug,source_native_id,buyer_name,project_label,timing_text,amount_text,scope_lc,evidence_granularity,
    substring(full_text from greatest(least(
      coalesce(nullif(strpos(scope_lc,'clean eifs'),0),2147483647),coalesce(nullif(strpos(scope_lc,'clean brick'),0),2147483647),
      coalesce(nullif(strpos(scope_lc,'clean masonry'),0),2147483647),coalesce(nullif(strpos(scope_lc,'exterior painting'),0),2147483647),
      coalesce(nullif(strpos(scope_lc,'exterior paint'),0),2147483647),coalesce(nullif(strpos(scope_lc,'repaint eifs'),0),2147483647),
      coalesce(nullif(strpos(scope_lc,'eifs panel repair'),0),2147483647),coalesce(nullif(strpos(scope_lc,'eifs repairs'),0),2147483647),
      coalesce(nullif(strpos(scope_lc,'dryvit'),0),2147483647))-260,1) for 1100) as evidence_excerpt
  from kde_docs
), x as (
  select source_slug,source_native_id,buyer_name,project_label,timing_text,amount_text,scope_lc,evidence_excerpt,evidence_granularity from indiana
  union all
  select source_slug,source_native_id,buyer_name,project_label,timing_text,amount_text,scope_lc,evidence_excerpt,evidence_granularity from kde
), flags as (
  select *,
    (scope_lc ~ '(exterior[^a-z]{0,40}(paint|painting|coat|coating|repaint)|repaint eifs|dryvit[^a-z]{0,40}(coat|coating|paint|repaint)|eifs[^a-z]{0,40}(coat|coating|paint|repaint))') as coating_flag,
    (scope_lc ~ '(clean eifs|clean brick|clean masonry|pressure wash|power wash|wash exterior)') as cleaning_flag
  from x
)
select source_slug,source_native_id,buyer_name,project_label,timing_text,amount_text,evidence_granularity,evidence_excerpt,
  coating_flag as coating_or_paint_explicit,cleaning_flag as cleaning_explicit,
  case
    when cleaning_flag and coating_flag then case when evidence_granularity='project_row' then 'explicit_same_project' else 'same_document_requires_facility_resolution' end
    when cleaning_flag then 'cleaning_explicit_downstream_treatment_unresolved'
    when coating_flag then 'coating_or_paint_explicit_prep_unresolved'
    else 'facade_repair_only_no_coating_or_cleaning'
  end as cleaning_relationship_semantics
from flags;
revoke all on research.v_public_facade_surface_work_probe from anon,authenticated;
