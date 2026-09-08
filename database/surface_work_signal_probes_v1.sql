-- Scout by Cadastory
-- Research-only probes for paint/coating signal semantics.
-- These views are intentionally isolated from production opportunity scoring and MCP exposure.

create schema if not exists research;

create or replace view research.v_bridge_paint_applicability_probe as
with src as (
  select r.source_native_id,
         r.retrieved_at,
         r.raw_payload,
         coalesce(r.raw_payload->>'BRIDGE_ID', r.source_native_id) as bridge_id,
         coalesce(r.raw_payload->>'BRIDGE_DESCRIPTION','') as bridge_description,
         lower(coalesce(r.raw_payload->>'BRIDGE_DESCRIPTION','')) as description_lc,
         r.raw_payload->>'FACILITY_CARRIED' as facility_carried,
         r.raw_payload->>'FEATURE_INTERSECT' as feature_intersect,
         r.raw_payload->>'COUNTY' as county,
         r.raw_payload->>'DISTRICT' as district,
         r.raw_payload->>'OWNER' as owner_code
  from ingest.raw_records r
  join ingest.sources s on s.id = r.source_id
  where s.slug = 'kydot-trak-bridge-condition-current'
)
select
  source_native_id,
  bridge_id,
  bridge_description,
  facility_carried,
  feature_intersect,
  county,
  district,
  owner_code,
  case
    when description_lc ~ '\munpaint(ed)?\M' and description_lc ~ '\msteel\M' then 'explicit_unpainted_steel'
    when description_lc ~ '\mpaint(ed)?\M' and description_lc ~ '\msteel\M' then 'explicit_painted_steel'
    when description_lc ~ '\msteel\M' then 'steel_paint_status_unknown'
    else 'nonsteel_or_unspecified'
  end as paint_applicability,
  case
    when description_lc ~ '\munpaint(ed)?\M' and description_lc ~ '\msteel\M' then false
    when description_lc ~ '\mpaint(ed)?\M' and description_lc ~ '\msteel\M' then true
    else null
  end as existing_paint_system_explicit,
  case
    when description_lc ~ '\munpaint(ed)?\M' and description_lc ~ '\msteel\M' then 'Do not infer repaint applicability from steel material alone.'
    when description_lc ~ '\mpaint(ed)?\M' and description_lc ~ '\msteel\M' then 'Existing painted-steel system is explicit; coating-condition/project evidence may be relevant.'
    when description_lc ~ '\msteel\M' then 'Steel is explicit but coating system is unresolved.'
    else 'No paint-system inference from this description.'
  end as interpretation,
  retrieved_at
from src;

comment on view research.v_bridge_paint_applicability_probe is
  'Research-only KYTC TRAK bridge applicability probe. Explicit painted/unpainted descriptions are applicability context, not evidence of current coating need.';

create or replace view research.v_school_paint_scope_probe as
with src as (
  select
    r.source_native_id,
    r.retrieved_at,
    r.raw_payload->>'unit_name' as unit_name,
    r.raw_payload->>'project_title' as project_title,
    r.raw_payload->>'description' as description,
    r.raw_payload->>'raw_block' as raw_block,
    r.raw_payload->>'estimated_cost' as estimated_cost_raw,
    r.raw_payload->>'plan_year' as plan_year,
    lower(concat_ws(' ',
      r.raw_payload->>'project_title',
      r.raw_payload->>'description',
      r.raw_payload->>'raw_block'
    )) as scope_lc
  from ingest.raw_records r
  join ingest.sources s on s.id = r.source_id
  where s.slug = 'indiana-dlgf-school-capital-projects'
), hits as (
  select * from src
  where scope_lc ~ '(paint|painting|repaint|recoat|coating|surface prep|power wash|pressure wash|sandblast|abrasive blast)'
)
select
  source_native_id,
  unit_name,
  project_title,
  description,
  estimated_cost_raw,
  plan_year,
  case
    when scope_lc ~ '(parking|seal[ -]?coat|striping|restrip|tennis court|court patch|track repair|track recoat|gym floor|floor refin|paving)' then 'ground_or_athletic_surface'
    when scope_lc ~ '(interior|hallway|auditorium|ceiling|carpet|classroom|indoor)' then 'interior_explicit'
    when scope_lc ~ '(exterior|dryvit|eifs|facade|façade|outside|building envelope|roof coating|metal roof|wall panel)' then 'exterior_or_envelope_explicit'
    else 'ambiguous_paint_scope'
  end as scope_class,
  case
    when scope_lc ~ '(parking|seal[ -]?coat|striping|restrip|tennis court|court patch|track repair|track recoat|gym floor|floor refin|paving)' then false
    when scope_lc ~ '(interior|hallway|auditorium|ceiling|carpet|classroom|indoor)' then false
    when scope_lc ~ '(exterior|dryvit|eifs|facade|façade|outside|building envelope|roof coating|metal roof|wall panel)' then true
    else null
  end as exterior_structure_candidate,
  case
    when scope_lc ~ '(power wash|pressure wash|clean(ing)?[^.]{0,40}(paint|coat)|surface prep)' then 'explicit_or_near_explicit_cleaning_prep'
    when scope_lc ~ '(exterior|dryvit|eifs|facade|façade|outside|building envelope|roof coating|metal roof|wall panel)' then 'coating_scope_only_prep_not_observed'
    else 'not_assessed'
  end as cleaning_prep_semantics,
  retrieved_at
from hits;

comment on view research.v_school_paint_scope_probe is
  'Research-only Indiana school capital-plan paint/coating probe. Separates exterior/envelope work from interior and pavement/athletic false positives.';

create or replace view research.v_water_tank_surface_work_probe as
with src as (
  select
    p.id as tank_project_id,
    p.source_record_id,
    p.wris_fid,
    p.pnum,
    p.pwsid,
    p.system_name,
    p.project_status,
    p.purpose,
    p.other_purpose,
    p.matched_tank_id,
    p.match_method,
    p.match_distance_m,
    p.source_created_at,
    p.source_modified_at,
    lower(concat_ws(' ',p.purpose,p.other_purpose)) as scope_lc
  from water.tank_projects p
), hits as (
  select * from src
  where scope_lc ~ '(paint|painting|repaint|recoat|re-coat|coating|coat\M|sandblast|sand blast|abrasive blast|blasting|cleaning)'
)
select
  tank_project_id,
  source_record_id,
  wris_fid,
  pnum,
  pwsid,
  system_name,
  project_status,
  purpose,
  other_purpose,
  matched_tank_id,
  match_method,
  match_distance_m,
  case
    when scope_lc ~ '(interior|inside)' and scope_lc ~ '(exterior|outside)' then 'both'
    when scope_lc ~ '(exterior|outside)' then 'exterior'
    when scope_lc ~ '(interior|inside)' then 'interior'
    else 'unknown'
  end as surface_scope,
  case
    when scope_lc ~ '(repaint|re-paint|recoat|re-coat|recoating|re-coating|coating system rehab)' then 'recoat_or_repaint'
    when scope_lc ~ '(paint|painting)' then 'paint'
    when scope_lc ~ '(coating|coat\M)' then 'coating'
    else 'surface_work_unspecified'
  end as coating_work_kind,
  (scope_lc ~ '(cleaning|\mclean\M|power wash|pressure wash|wash(ing)?\M)') as cleaning_explicit,
  (scope_lc ~ '(sandblast|sand blast|abrasive blast|blasting)') as abrasive_prep_explicit,
  case
    when scope_lc ~ '(cleaning|\mclean\M|power wash|pressure wash|wash(ing)?\M)' and scope_lc ~ '(paint|repaint|recoat|re-coat|coating|coat\M)' then 'cleaning_plus_coating_explicit'
    when scope_lc ~ '(sandblast|sand blast|abrasive blast|blasting)' and scope_lc ~ '(paint|repaint|recoat|re-coat|coating|coat\M)' then 'abrasive_prep_plus_coating_explicit'
    when scope_lc ~ '(paint|repaint|recoat|re-coat|coating|coat\M)' then 'coating_explicit_prep_unresolved'
    when scope_lc ~ '(cleaning|\mclean\M|power wash|pressure wash|wash(ing)?\M)' then 'cleaning_only_or_other_maintenance'
    else 'other_surface_work'
  end as prep_relationship,
  case
    when matched_tank_id is not null then 'asset_matched'
    else 'asset_unmatched'
  end as asset_resolution,
  source_created_at,
  source_modified_at
from hits;

comment on view research.v_water_tank_surface_work_probe is
  'Research-only WRIS tank-project probe separating exterior/interior coating scope and explicit cleaning/abrasive preparation. Does not promote opportunities.';

create or replace view research.v_surface_work_probe_summary as
select 'bridge_paint_applicability'::text as probe,
       paint_applicability as class,
       count(*)::bigint as records
from research.v_bridge_paint_applicability_probe
group by paint_applicability
union all
select 'school_paint_scope', scope_class, count(*)::bigint
from research.v_school_paint_scope_probe
group by scope_class
union all
select 'water_tank_prep_relationship', prep_relationship, count(*)::bigint
from research.v_water_tank_surface_work_probe
group by prep_relationship;

comment on view research.v_surface_work_probe_summary is
  'Research-only summary counts for surface-work semantic probes.';

revoke all on research.v_bridge_paint_applicability_probe from anon, authenticated;
revoke all on research.v_school_paint_scope_probe from anon, authenticated;
revoke all on research.v_water_tank_surface_work_probe from anon, authenticated;
revoke all on research.v_surface_work_probe_summary from anon, authenticated;
