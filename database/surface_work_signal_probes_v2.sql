-- Research-only refinement for school capital-plan paint/coating semantics.
-- Supersedes only research.v_school_paint_scope_probe from v1.

drop view if exists research.v_surface_work_probe_summary;
drop view if exists research.v_school_paint_scope_probe;

create view research.v_school_paint_scope_probe as
with src as (
  select r.source_native_id, r.retrieved_at,
    r.raw_payload->>'unit_name' as unit_name,
    r.raw_payload->>'project_title' as project_title,
    r.raw_payload->>'description' as description,
    r.raw_payload->>'raw_block' as raw_block,
    r.raw_payload->>'estimated_cost' as estimated_cost_raw,
    r.raw_payload->>'plan_year' as plan_year,
    lower(concat_ws(' ',r.raw_payload->>'project_title',r.raw_payload->>'description',r.raw_payload->>'raw_block')) as scope_lc
  from ingest.raw_records r join ingest.sources s on s.id=r.source_id
  where s.slug='indiana-dlgf-school-capital-projects'
), hits as (
  select *,
    (scope_lc ~ '(exterior|dryvit|eifs|facade|façade|outside|building envelope|roof coating|metal roof|wall panel)') as has_exterior_scope,
    (scope_lc ~ '(interior|hallway|auditorium|ceiling|carpet|classroom|indoor)') as has_interior_scope,
    (scope_lc ~ '(parking|seal[ -]?coat|striping|restrip|tennis court|court patch|track repair|track recoat|gym floor|floor refin|paving)') as has_ground_or_athletic_scope,
    (scope_lc ~ '(power wash|pressure wash|clean(ing)?[^.]{0,40}(paint|coat)|surface prep)') as has_cleaning_prep_scope
  from src
  where scope_lc ~ '(paint|painting|repaint|recoat|coating|surface prep|power wash|pressure wash|sandblast|abrasive blast)'
)
select source_native_id,unit_name,project_title,description,estimated_cost_raw,plan_year,
  has_exterior_scope,has_interior_scope,has_ground_or_athletic_scope,
  case
    when has_exterior_scope and (has_interior_scope or has_ground_or_athletic_scope) then 'mixed_scope_contains_exterior'
    when has_exterior_scope then 'exterior_or_envelope_explicit'
    when has_ground_or_athletic_scope then 'ground_or_athletic_surface'
    when has_interior_scope then 'interior_explicit'
    else 'ambiguous_paint_scope'
  end as scope_class,
  case when has_exterior_scope then true when has_interior_scope or has_ground_or_athletic_scope then false else null end as exterior_structure_candidate,
  case when has_cleaning_prep_scope then 'explicit_or_near_explicit_cleaning_prep' when has_exterior_scope then 'coating_scope_only_prep_not_observed' else 'not_assessed' end as cleaning_prep_semantics,
  retrieved_at
from hits;

create view research.v_surface_work_probe_summary as
select 'bridge_paint_applicability'::text as probe,paint_applicability as class,count(*)::bigint as records from research.v_bridge_paint_applicability_probe group by paint_applicability
union all
select 'school_paint_scope',scope_class,count(*)::bigint from research.v_school_paint_scope_probe group by scope_class
union all
select 'water_tank_prep_relationship',prep_relationship,count(*)::bigint from research.v_water_tank_surface_work_probe group by prep_relationship;

revoke all on research.v_school_paint_scope_probe from anon,authenticated;
revoke all on research.v_surface_work_probe_summary from anon,authenticated;
