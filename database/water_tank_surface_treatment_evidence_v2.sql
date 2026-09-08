-- Scout by Cadastory
-- Water tank surface-treatment evidence v2.
-- Research-only. Normalizes existing WRIS project text plus coating/painting facts already
-- present in water.tanks comments. Separates surface scope, prep, documented work, and
-- treatment-specific forecast cues. No production scoring or MCP exposure.

create schema if not exists research;

create or replace view research.v_water_tank_surface_treatment_evidence_v2 as
with project_rows as (
  select
    'wris_project'::text as evidence_source,
    p.id as evidence_record_id,
    p.matched_tank_id as tank_id,
    p.pnum as project_key,
    p.system_name,
    p.project_status,
    p.source_modified_at as observed_at,
    concat_ws(' ',p.purpose,p.other_purpose) as evidence_text,
    lower(concat_ws(' ',p.purpose,p.other_purpose)) as lc
  from water.tank_projects p
  where lower(concat_ws(' ',p.purpose,p.other_purpose))
    ~ '(paint|repaint|re-coat|recoat|coating|blast|sandblast|surface prep|clean)'
), project_typed as (
  select
    evidence_source,evidence_record_id,tank_id,project_key,system_name,project_status,observed_at,evidence_text,
    case
      when lc ~ '(re-coat|recoat|full re-coat|full recoat)' then 'recoat'
      when lc ~ '(repaint|paint tank|painting|paint and repair|repair and paint)' then 'paint_repaint'
      when lc ~ '(repair damage to coating|coating system rehab|coating rehab)' then 'coating_repair_rehab'
      when lc ~ 'coating' then 'coating_general'
      when lc ~ 'clean' then 'cleaning_only_or_other_maintenance'
      else 'other_surface_work'
    end as treatment_family,
    case
      when lc ~ 'interior' and lc ~ 'exterior' then 'both_explicit'
      when lc ~ 'exterior' and lc !~ 'interior' then 'exterior_explicit'
      when lc ~ 'interior' and lc !~ 'exterior' then 'interior_explicit'
      else 'surface_scope_unresolved'
    end as surface_scope,
    case
      when lc ~ '(sandblast|blasting|abrasive)' and lc ~ 'clean' then 'abrasive_plus_cleaning_explicit'
      when lc ~ '(sandblast|blasting|abrasive)' then 'abrasive_prep_explicit'
      when lc ~ 'clean' then 'cleaning_prep_explicit'
      else 'prep_unresolved'
    end as prep_class,
    case
      when lc ~ '(not been repainted|not repainted)[^0-9]{0,30}[0-9]+\+?[^a-z]{0,10}years' then 'explicit_repaint_age_pressure'
      else null
    end as forecast_cue,
    case
      when lc ~ '(paint|repaint|re-coat|recoat|coating)' and lc ~ 'exterior' then 'treatment_scope_exterior_confirmed'
      when lc ~ '(paint|repaint|re-coat|recoat|coating)' then 'treatment_scope_confirmed_surface_unresolved'
      when lc ~ '(blast|sandblast|clean)' then 'prep_or_maintenance_only'
      else 'adjacent_surface_work'
    end as evidence_strength
  from project_rows
), comment_rows as (
  select
    'tank_comment'::text as evidence_source,
    t.id as evidence_record_id,
    t.id as tank_id,
    null::text as project_key,
    t.system_name,
    null::text as project_status,
    t.source_modified_at as observed_at,
    t.comments as evidence_text,
    lower(t.comments) as lc
  from water.tanks t
  where lower(coalesce(t.comments,'')) ~ '(paint|repaint|coat|coating|rust|corros|peel|blister|chalk)'
), comment_typed as (
  select
    evidence_source,evidence_record_id,tank_id,project_key,system_name,project_status,observed_at,evidence_text,
    case
      when lc ~ '(repaint|repainted)' then 'paint_repaint'
      when lc ~ '(painting|paint repair|painted)' then 'paint_repaint'
      when lc ~ '(coating rehab|rehab coating|coating)' then 'coating_repair_rehab'
      else 'condition_or_project_comment'
    end as treatment_family,
    case
      when lc ~ 'interior' and lc ~ 'exterior' then 'both_explicit'
      when lc ~ 'exterior' and lc !~ 'interior' then 'exterior_explicit'
      when lc ~ 'interior' and lc !~ 'exterior' then 'interior_explicit'
      else 'surface_scope_unresolved'
    end as surface_scope,
    'prep_unresolved'::text as prep_class,
    case
      when lc ~ '(scheduled|planned)[^.;]{0,80}(paint|painting|repaint|coat|coating)' or lc ~ '(paint|painting|repaint|coat|coating)[^.;]{0,80}(scheduled|planned)' then 'explicit_scheduled_treatment'
      when lc ~ '(not been repainted|not repainted)[^0-9]{0,30}[0-9]+\+?[^a-z]{0,10}years' then 'explicit_repaint_age_pressure'
      when lc ~ '(repainted|painting may [0-9]{4}|totally repainted|rehab coating)' then 'historical_treatment_date_or_event'
      else null
    end as forecast_cue,
    case
      when lc ~ '(scheduled|planned)' and lc ~ '(paint|repaint|coat|coating)' then 'scheduled_treatment_explicit'
      when lc ~ '(repainted|painted|coating rehab|rehab coating)' then 'historical_treatment_explicit'
      else 'coating_related_comment'
    end as evidence_strength
  from comment_rows
)
select * from project_typed
union all
select * from comment_typed;

comment on view research.v_water_tank_surface_treatment_evidence_v2 is
  'Research-only normalized water-tank surface-treatment evidence from WRIS project scope and tank comments. Exterior/interior/both/unresolved scope is explicit-text based; unspecified paint/coating must not be promoted as exterior work.';

create or replace view research.v_water_tank_surface_treatment_summary_v2 as
select
  evidence_source,
  treatment_family,
  surface_scope,
  prep_class,
  coalesce(forecast_cue,'none') as forecast_cue,
  evidence_strength,
  count(*)::bigint as evidence_rows,
  count(distinct tank_id) filter (where tank_id is not null)::bigint as resolved_tanks,
  count(distinct project_key) filter (where project_key is not null)::bigint as distinct_projects
from research.v_water_tank_surface_treatment_evidence_v2
group by evidence_source,treatment_family,surface_scope,prep_class,coalesce(forecast_cue,'none'),evidence_strength;

comment on view research.v_water_tank_surface_treatment_summary_v2 is
  'Research-only summary of normalized water-tank treatment evidence. Counts rows, resolved tanks and distinct projects separately because one WRIS project can apply to multiple tanks.';

create or replace view research.v_water_tank_paint_forecast_scaffold_v1 as
with ev as (
  select
    tank_id,
    count(*) filter (where evidence_source='wris_project' and evidence_strength like 'treatment_scope%')::int as documented_treatment_scope_rows,
    count(*) filter (where surface_scope in ('exterior_explicit','both_explicit') and evidence_strength like 'treatment_scope%')::int as explicit_exterior_treatment_rows,
    bool_or(forecast_cue='explicit_repaint_age_pressure') as has_explicit_repaint_age_pressure,
    bool_or(forecast_cue='explicit_scheduled_treatment') as has_explicit_scheduled_treatment,
    bool_or(forecast_cue='historical_treatment_date_or_event') as has_historical_treatment_event,
    max(observed_at) as latest_surface_evidence_observed_at
  from research.v_water_tank_surface_treatment_evidence_v2
  where tank_id is not null
  group by tank_id
)
select
  t.id as tank_id,
  t.tank_name,
  t.system_name,
  t.pwsid,
  t.tank_type,
  t.material,
  t.interior_coating,
  t.capacity_gallons,
  t.construction_date,
  t.last_cleaning_date,
  t.last_inspection_date,
  t.out_of_service,
  coalesce(ev.documented_treatment_scope_rows,0) as documented_treatment_scope_rows,
  coalesce(ev.explicit_exterior_treatment_rows,0) as explicit_exterior_treatment_rows,
  coalesce(ev.has_explicit_repaint_age_pressure,false) as has_explicit_repaint_age_pressure,
  coalesce(ev.has_explicit_scheduled_treatment,false) as has_explicit_scheduled_treatment,
  coalesce(ev.has_historical_treatment_event,false) as has_historical_treatment_event,
  ev.latest_surface_evidence_observed_at,
  case
    when t.out_of_service is true then 'out_of_service'
    when coalesce(ev.has_explicit_scheduled_treatment,false) then 'explicit_scheduled_treatment'
    when coalesce(ev.has_explicit_repaint_age_pressure,false) then 'explicit_repaint_age_pressure'
    when coalesce(ev.explicit_exterior_treatment_rows,0)>0 then 'documented_exterior_treatment_scope'
    when coalesce(ev.documented_treatment_scope_rows,0)>0 then 'documented_treatment_surface_unresolved'
    when coalesce(ev.has_historical_treatment_event,false) then 'historical_treatment_context_only'
    when upper(coalesce(t.material,''))='STEEL' then 'steel_tank_maintenance_context_only'
    else 'no_paint_specific_signal'
  end as paint_signal_state,
  case
    when t.out_of_service is true then 'exclude'
    when coalesce(ev.has_explicit_scheduled_treatment,false) then 'highest'
    when coalesce(ev.has_explicit_repaint_age_pressure,false) then 'highest'
    when coalesce(ev.explicit_exterior_treatment_rows,0)>0 then 'high'
    when coalesce(ev.documented_treatment_scope_rows,0)>0 then 'medium'
    else 'watch'
  end as paint_project_search_priority,
  case
    when coalesce(ev.has_explicit_scheduled_treatment,false) then 'Tank record explicitly states painting/coating work was scheduled. Treat date wording as source evidence; verify current status before outreach.'
    when coalesce(ev.has_explicit_repaint_age_pressure,false) then 'Source explicitly states repaint age pressure (for example, not repainted in 20+ years). This is treatment-specific forecast evidence.'
    when coalesce(ev.explicit_exterior_treatment_rows,0)>0 then 'A WRIS project explicitly includes exterior painting/coating scope. This is documented project evidence, not a generic age proxy.'
    when coalesce(ev.documented_treatment_scope_rows,0)>0 then 'A WRIS project documents painting/coating but surface scope remains unresolved; do not assume exterior.'
    when upper(coalesce(t.material,''))='STEEL' then 'Steel tank with maintenance/inspection chronology but no current treatment-specific evidence. Construction, cleaning and inspection dates are context only and must not be converted into an unsupported repaint interval.'
    else 'No current paint-specific evidence.'
  end as research_interpretation
from water.tanks t
left join ev on ev.tank_id=t.id;

comment on view research.v_water_tank_paint_forecast_scaffold_v1 is
  'Research-only tank painting/coating scaffold. Gives highest priority only to explicit scheduled/due statements, high to explicit exterior treatment projects, medium to treatment projects with unresolved surface scope. Tank age/inspection/cleaning chronology is context only; no unsupported repaint interval is assumed.';

update research.painting_signal_target_readiness
set confirmed_hit_sources=array['water.tank_projects','water.tanks','ky-kia-proposed-water-improvements','kentucky-transparency-contracts'],
    forecast_sources=array['water.tank_projects','water.tanks','water.v_tank_maintenance_candidates'],
    confirmed_hit_basis='WRIS project text now has explicit treatment/surface/prep decomposition; tank comments also expose scheduled and historical painting/coating facts. Unspecified tank paint/coating remains surface-scope unresolved rather than being assumed exterior.',
    forecast_basis='Existing tank data can produce treatment-specific forecast cues when the source explicitly states scheduled painting or repaint-age pressure. Construction, cleaning and inspection chronology remains supporting maintenance context only; Scout does not assume a generic repaint interval.',
    blocker='Exterior/interior scope is still unresolved for many project rows, and scheduled/historical comment dates require current-status verification before production use.',
    next_action='Use explicit exterior/both treatment rows and explicit scheduled/due statements first; then resolve ambiguous project scope and add inspection/procurement sources before estimating broader repaint recurrence.',
    reviewed_at=now()
where survey_key in ('water_utility:elevated_water_tank_exterior','water_utility:ground_storage_tank_exterior');

revoke all on research.v_water_tank_surface_treatment_evidence_v2 from anon, authenticated;
revoke all on research.v_water_tank_surface_treatment_summary_v2 from anon, authenticated;
revoke all on research.v_water_tank_paint_forecast_scaffold_v1 from anon, authenticated;
