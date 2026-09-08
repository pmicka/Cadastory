-- Scout by Cadastory
-- Bridge paint/coating project-search scaffold v1.
-- Research-only. Uses existing NBI + KYTC applicability evidence to prioritize
-- which steel bridges deserve paint/coating project-source checks.
-- This is NOT a confirmed repaint forecast and is not exposed to production.

create schema if not exists research;

create or replace view research.v_bridge_paint_project_search_scaffold as
with applicability as (
  select
    regexp_replace(lower(coalesce(bridge_id,'')),'[^a-z0-9]','','g') as normalized_structure_number,
    paint_applicability,
    existing_paint_system_explicit,
    interpretation as applicability_interpretation
  from research.v_bridge_paint_applicability_probe
), base as (
  select
    b.id as bridge_id,
    b.structure_number,
    b.state_fips,
    b.county_fips,
    b.facility_carried,
    b.location_text,
    b.owner_code,
    b.owner_class,
    b.maintenance_code,
    b.maintenance_class,
    b.structure_kind_code,
    b.structure_type_code,
    b.structure_length_m,
    b.deck_area_m2,
    b.year_built,
    b.year_reconstructed,
    b.bridge_condition,
    b.superstructure_condition,
    b.inspection_date_raw,
    b.inspection_frequency_months,
    r.raw_payload->'attributes'->>'WORK_PROPOSED_075A' as work_proposed_code,
    r.raw_payload->'attributes'->>'YEAR_OF_IMP_097' as improvement_year_raw,
    r.raw_payload->'attributes'->>'BRIDGE_IMP_COST_094' as bridge_improvement_cost_raw,
    r.raw_payload->'attributes'->>'TOTAL_IMP_COST_096' as total_improvement_cost_raw,
    r.raw_payload->'attributes'->>'WORK_DONE_BY_075B' as work_done_by_code,
    a.paint_applicability,
    a.existing_paint_system_explicit,
    a.applicability_interpretation
  from transportation.bridges b
  left join ingest.raw_records r on r.id=b.source_record_id
  left join applicability a
    on b.state_fips='21'
   and regexp_replace(lower(coalesce(b.structure_number,'')),'[^a-z0-9]','','g')=a.normalized_structure_number
  where b.structure_kind_code in ('3','4') -- NBI steel / steel continuous
), typed as (
  select *,
    case work_proposed_code
      when '31' then 'replacement_load_or_geometry'
      when '32' then 'replacement_relocation'
      when '33' then 'widening_without_deck_rehab'
      when '34' then 'widening_with_deck_rehab_or_replacement'
      when '35' then 'bridge_rehabilitation_general_deterioration_or_strength'
      when '36' then 'deck_rehabilitation'
      when '37' then 'deck_replacement'
      when '38' then 'other_structural_work'
      else 'none_or_unknown'
    end as work_proposed_family,
    case when superstructure_condition ~ '^[0-9]+$' then superstructure_condition::int end as superstructure_condition_numeric
  from base
)
select
  *,
  case
    when paint_applicability='explicit_unpainted_steel' then 'exclude_explicit_unpainted_steel'
    when work_proposed_code in ('31','32') then 'low_repaint_relevance_replacement'
    when work_proposed_code='35' and superstructure_condition_numeric <= 5 then 'high_project_search_priority'
    when work_proposed_code='35' then 'medium_project_search_priority'
    when work_proposed_code='38' and superstructure_condition_numeric <= 5 then 'medium_project_search_priority'
    when existing_paint_system_explicit is true and superstructure_condition_numeric <= 5 then 'medium_project_search_priority'
    when superstructure_condition_numeric <= 4 then 'medium_project_search_priority'
    else 'watch_only'
  end as paint_project_search_priority,
  case
    when paint_applicability='explicit_unpainted_steel' then
      'KYTC description explicitly indicates unpainted steel; do not infer a repaint need from steel material or condition alone.'
    when work_proposed_code in ('31','32') then
      'NBI proposed work is replacement; replacement may remove rather than preserve the existing coating system, so repaint relevance is reduced.'
    when work_proposed_code='35' and superstructure_condition_numeric <= 5 then
      'Steel bridge with NBI general rehabilitation proposed and fair-or-worse superstructure condition. Strong candidate for a paint/coating project-source lookup, but NBI does not prove painting is in scope.'
    when work_proposed_code='35' then
      'Steel bridge with NBI general rehabilitation proposed. Search bid/pay-item sources for coating scope; do not assume painting from rehabilitation alone.'
    when work_proposed_code='38' and superstructure_condition_numeric <= 5 then
      'Steel bridge with other structural work proposed and fair-or-worse superstructure condition. Useful project-search priority, not paint evidence.'
    when existing_paint_system_explicit is true and superstructure_condition_numeric <= 5 then
      'Existing painted-steel system is explicit and condition is fair-or-worse, but no treatment-specific project evidence is present.'
    when superstructure_condition_numeric <= 4 then
      'Steel bridge has poor-or-worse superstructure condition; useful for targeted project-source checks, not enough to infer repaint timing.'
    else
      'Steel bridge remains paint-applicable or unresolved, but current NBI signals are insufficient for elevated project-search priority.'
  end as research_interpretation
from typed;

comment on view research.v_bridge_paint_project_search_scaffold is
  'Research-only steel-bridge project-search scaffold using NBI material, condition and proposed-work fields plus KYTC paint applicability where available. Never treat priority as confirmed repaint scope.';

create or replace view research.v_bridge_paint_project_search_summary as
select
  paint_project_search_priority,
  coalesce(paint_applicability,'no_kytc_applicability_evidence') as paint_applicability,
  work_proposed_family,
  count(*)::bigint as bridges,
  count(*) filter (where superstructure_condition_numeric <= 5)::bigint as fair_or_worse
from research.v_bridge_paint_project_search_scaffold
group by paint_project_search_priority,coalesce(paint_applicability,'no_kytc_applicability_evidence'),work_proposed_family;

comment on view research.v_bridge_paint_project_search_summary is
  'Research-only summary of steel-bridge paint/coating project-search priority. Not an opportunity feed.';

update research.painting_signal_target_readiness
set forecast_readiness='partial_proxy',
    forecast_sources=array['transportation.bridges','fhwa-ntad-nbi-2025','kydot-trak-bridge-condition-current'],
    forecast_basis='Existing NBI now supports a repeatable steel-bridge project-search scaffold using material, superstructure condition, proposed-work family, owner, improvement timing/cost and KYTC explicit paint applicability where available. This narrows where to seek coating scope but remains non-treatment-specific.',
    blocker='Current NBI can prioritize likely rehabilitation work but cannot prove coating condition or painting scope; coating elements/pay items remain the treatment-specific gap.',
    next_action='Use the scaffold to focus FHWA Element 515 and KY/IN/OH pay-item collection/backtesting on the highest-priority steel bridges rather than scanning the full bridge universe.',
    reviewed_at=now()
where survey_key='transportation_agency:steel_bridge_superstructure';

revoke all on research.v_bridge_paint_project_search_scaffold from anon, authenticated;
revoke all on research.v_bridge_paint_project_search_summary from anon, authenticated;
