-- Scout by Cadastory
-- Deferred human visual confirmation backbone for the eventual Help improve Scout surface.
-- Internal machine/visual research may nominate hypotheses here, but precision-sensitive
-- facts are not promoted merely because an internal visual classifier produced them.

create table if not exists scout.human_visual_confirmation_backlog (
  id uuid primary key default gen_random_uuid(),
  review_surface text not null default 'help_improve_scout'
    check (review_surface = 'help_improve_scout'),
  source_domain text not null,
  target_key text not null,
  candidate_key text,
  asset_type text not null,
  attribute_key text not null,
  subject_label text not null,
  question text not null,
  model_hypothesis jsonb not null default '{}'::jsonb,
  evidence_snapshot jsonb not null default '{}'::jsonb,
  current_confidence numeric check (current_confidence is null or (current_confidence >= 0 and current_confidence <= 1)),
  required_confidence numeric not null default 0.95 check (required_confidence >= 0 and required_confidence <= 1),
  priority integer not null default 50 check (priority between 0 and 100),
  blocked_downstream_uses text[] not null default '{}'::text[],
  originating_system text not null default 'scout_internal_visual_research',
  status text not null default 'pending'
    check (status in ('pending','deferred','materialized','answered','dismissed','superseded')),
  materialized_task_id uuid references scout.improvement_tasks(id) on delete set null,
  human_answer jsonb,
  human_confirmed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (source_domain, target_key, attribute_key)
);

alter table scout.human_visual_confirmation_backlog enable row level security;
revoke all on scout.human_visual_confirmation_backlog from anon, authenticated;
grant select, insert, update, delete on scout.human_visual_confirmation_backlog to service_role;

create index if not exists human_visual_confirmation_backlog_pending_idx
  on scout.human_visual_confirmation_backlog(status, priority desc, created_at)
  where status in ('pending','deferred');
create index if not exists human_visual_confirmation_backlog_candidate_idx
  on scout.human_visual_confirmation_backlog(candidate_key)
  where candidate_key is not null;
create index if not exists human_visual_confirmation_backlog_asset_idx
  on scout.human_visual_confirmation_backlog(asset_type, attribute_key, status);

create or replace function scout.enqueue_human_visual_confirmation(
  p_source_domain text,
  p_target_key text,
  p_asset_type text,
  p_attribute_key text,
  p_subject_label text,
  p_question text,
  p_model_hypothesis jsonb default '{}'::jsonb,
  p_evidence_snapshot jsonb default '{}'::jsonb,
  p_current_confidence numeric default null,
  p_required_confidence numeric default 0.95,
  p_priority integer default 50,
  p_blocked_downstream_uses text[] default '{}'::text[],
  p_candidate_key text default null,
  p_originating_system text default 'scout_internal_visual_research'
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if p_source_domain is null or btrim(p_source_domain) = ''
     or p_target_key is null or btrim(p_target_key) = ''
     or p_asset_type is null or btrim(p_asset_type) = ''
     or p_attribute_key is null or btrim(p_attribute_key) = ''
     or p_subject_label is null or btrim(p_subject_label) = ''
     or p_question is null or btrim(p_question) = '' then
    raise exception 'source_domain, target_key, asset_type, attribute_key, subject_label, and question are required';
  end if;

  if p_current_confidence is not null and (p_current_confidence < 0 or p_current_confidence > 1) then
    raise exception 'current_confidence must be between 0 and 1';
  end if;
  if p_required_confidence < 0 or p_required_confidence > 1 then
    raise exception 'required_confidence must be between 0 and 1';
  end if;
  if p_priority < 0 or p_priority > 100 then
    raise exception 'priority must be between 0 and 100';
  end if;

  insert into scout.human_visual_confirmation_backlog(
    source_domain,target_key,candidate_key,asset_type,attribute_key,subject_label,question,
    model_hypothesis,evidence_snapshot,current_confidence,required_confidence,priority,
    blocked_downstream_uses,originating_system,status,updated_at
  ) values (
    p_source_domain,p_target_key,p_candidate_key,p_asset_type,p_attribute_key,p_subject_label,p_question,
    coalesce(p_model_hypothesis,'{}'::jsonb),coalesce(p_evidence_snapshot,'{}'::jsonb),p_current_confidence,
    p_required_confidence,p_priority,coalesce(p_blocked_downstream_uses,'{}'::text[]),p_originating_system,'pending',now()
  )
  on conflict (source_domain,target_key,attribute_key) do update set
    candidate_key = coalesce(excluded.candidate_key, scout.human_visual_confirmation_backlog.candidate_key),
    subject_label = excluded.subject_label,
    question = excluded.question,
    model_hypothesis = excluded.model_hypothesis,
    evidence_snapshot = excluded.evidence_snapshot,
    current_confidence = excluded.current_confidence,
    required_confidence = excluded.required_confidence,
    priority = greatest(scout.human_visual_confirmation_backlog.priority, excluded.priority),
    blocked_downstream_uses = (
      select array_agg(distinct x order by x)
      from unnest(scout.human_visual_confirmation_backlog.blocked_downstream_uses || excluded.blocked_downstream_uses) x
    ),
    originating_system = excluded.originating_system,
    status = case
      when scout.human_visual_confirmation_backlog.status in ('answered','dismissed') then scout.human_visual_confirmation_backlog.status
      else 'pending'
    end,
    updated_at = now()
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function scout.enqueue_human_visual_confirmation(text,text,text,text,text,text,jsonb,jsonb,numeric,numeric,integer,text[],text,text) from public, anon, authenticated;
grant execute on function scout.enqueue_human_visual_confirmation(text,text,text,text,text,text,jsonb,jsonb,numeric,numeric,integer,text[],text,text) to service_role;

-- Register the eventual review task while keeping the product surface inactive/paused.
insert into scout.improvement_task_types(
  task_type,title,calibration_domain,purpose,answer_options,reason_options,
  min_examples_to_inform,max_per_session,status,active,sort_order,updated_at
) values (
  'human_visual_confirmation',
  'Visual confirmation',
  'human_visual_confirmation',
  'Resolve precision-sensitive visual facts that Scout internal research could not establish to the required confidence. Machine hypotheses nominate the question; independent human review supplies the confirmation.',
  '[{"code":"confirm","label":"Confirm hypothesis","polarity":1},{"code":"correct","label":"Correct it","polarity":0},{"code":"unclear","label":"Cannot tell","polarity":0},{"code":"not_applicable","label":"Not applicable","polarity":0}]'::jsonb,
  '[{"code":"image_unclear","label":"Image is unclear"},{"code":"occluded","label":"Target is occluded"},{"code":"wrong_asset","label":"Wrong asset / identity"},{"code":"mixed_surface","label":"Mixed surface or structure"},{"code":"needs_other_view","label":"Need another view"},{"code":"classification_too_specific","label":"Classification is too specific"}]'::jsonb,
  3,3,'paused',false,90,now()
)
on conflict (task_type) do update set
  title=excluded.title,
  calibration_domain=excluded.calibration_domain,
  purpose=excluded.purpose,
  answer_options=excluded.answer_options,
  reason_options=excluded.reason_options,
  min_examples_to_inform=excluded.min_examples_to_inform,
  max_per_session=excluded.max_per_session,
  status='paused',active=false,sort_order=excluded.sort_order,updated_at=now();

-- Seed existing facade/material/glazing uncertainty into the deferred human-confirmation backlog.
insert into scout.human_visual_confirmation_backlog(
  source_domain,target_key,candidate_key,asset_type,attribute_key,subject_label,question,
  model_hypothesis,evidence_snapshot,current_confidence,required_confidence,priority,
  blocked_downstream_uses,originating_system,status
)
select
  'facade_visual_verification',
  q.building_source_record_id::text,
  q.candidate_key,
  'building',
  case when need='facade_material' then 'intrinsic_facade_material' else 'glazing_extent_or_presence' end,
  coalesce(q.display_name,q.candidate_key,q.building_source_record_id::text),
  case when need='facade_material'
       then 'What is the intrinsic exterior facade material? Ignore staining, biological growth, dirt, weathering, and other surface-condition cues except as needed to see the underlying material.'
       else 'Confirm the commercially meaningful glazing presence/extent on this building from the available view; do not infer from building type alone.' end,
  case when need='facade_material' then jsonb_strip_nulls(jsonb_build_object(
      'facade_material',q.resolved_facade_material,
      'raw_facade_material',q.resolved_raw_facade_material,
      'status',q.resolved_facade_material_status,
      'source_slug',q.resolved_facade_material_source_slug
    ))
    else jsonb_strip_nulls(jsonb_build_object(
      'glazing_signal',q.glazing_signal,
      'glazing_extent',q.glazing_extent,
      'glazing_verification_status',q.glazing_verification_status
    )) end,
  jsonb_strip_nulls(jsonb_build_object(
    'verification_priority',q.verification_priority,
    'verification_score',q.verification_score,
    'verification_needs',q.verification_needs,
    'identity_status',q.identity_status,
    'identity_match_confidence',q.identity_match_confidence,
    'media_retention_policy',q.media_retention_policy,
    'guardrail',q.guardrail
  )),
  case when need='glazing' then coalesce(q.glazing_extent_confidence,q.glazing_confidence)
       else null end,
  0.95,
  case when q.verification_priority='high' then 90 else 45 end,
  case when need='facade_material'
       then array['precision_facade_material','organic_growth_pressure','chemical_surface_compatibility']::text[]
       else array['precision_glazing_extent','pure_water_service_fit']::text[] end,
  'scout_internal_visual_research',
  'pending'
from decisioning.v_facade_visual_verification_queue_v3 q
cross join lateral unnest(q.verification_needs) need
where need in ('facade_material','glazing')
on conflict (source_domain,target_key,attribute_key) do nothing;

-- Seed unresolved / partially resolved water-tank structural morphology.
insert into scout.human_visual_confirmation_backlog(
  source_domain,target_key,candidate_key,asset_type,attribute_key,subject_label,question,
  model_hypothesis,evidence_snapshot,current_confidence,required_confidence,priority,
  blocked_downstream_uses,originating_system,status
)
select
  'water_tank_geometry',
  q.tank_id::text,
  q.candidate_key,
  'water_tank',
  'support_morphology',
  coalesce(q.tank_name,q.system_name,q.wris_fid,q.tank_id::text),
  'Confirm the tank structural morphology relevant to drone-cleaning execution: elevated vs standpipe/ground storage where applicable, support geometry, approximate support-leg count, and whether cross-bracing is present. Choose unknown rather than forcing a specific subtype from an inadequate view.',
  jsonb_strip_nulls(jsonb_build_object(
    'morphology_class',q.morphology_class,
    'support_geometry',q.support_geometry,
    'support_leg_count',q.support_leg_count,
    'cross_bracing_status',q.cross_bracing_status,
    'operator_cleaning_geometry_assessment',q.operator_cleaning_geometry_assessment
  )),
  jsonb_strip_nulls(jsonb_build_object(
    'wris_fid',q.wris_fid,
    'wris_tank_type',q.wris_tank_type,
    'capacity_gallons',q.capacity_gallons,
    'geometry_evidence_kind',q.geometry_evidence_kind,
    'morphology_research_status',q.morphology_research_status,
    'next_research_step',q.next_research_step,
    'research_guardrail',q.research_guardrail,
    'suggested_research_query',q.suggested_research_query
  )),
  q.geometry_confidence,
  0.95,
  case q.research_priority when 0 then 95 when 1 then 80 else 55 end,
  array['water_tank_operator_geometry','water_tank_cleaning_difficulty','precision_tower_morphology']::text[],
  'scout_internal_visual_research',
  'pending'
from scout.v_water_tank_geometry_research_queue q
where q.morphology_research_needed
   or q.morphology_research_status='partially_resolved_bracing_unknown'
on conflict (source_domain,target_key,attribute_key) do nothing;

create or replace view scout.v_help_improve_scout_visual_confirmation_backlog as
select
  id,source_domain,target_key,candidate_key,asset_type,attribute_key,subject_label,question,
  model_hypothesis,evidence_snapshot,current_confidence,required_confidence,priority,
  blocked_downstream_uses,status,created_at,updated_at
from scout.human_visual_confirmation_backlog
where status in ('pending','deferred')
order by priority desc, created_at, id;

revoke all on scout.v_help_improve_scout_visual_confirmation_backlog from anon, authenticated;
grant select on scout.v_help_improve_scout_visual_confirmation_backlog to service_role;

comment on table scout.human_visual_confirmation_backlog is
'Deferred queue for precision-sensitive visual facts that require independent human confirmation before promotion. Feeds the eventual Help improve Scout surface; not itself a model-visible or user-facing capability.';
comment on view scout.v_help_improve_scout_visual_confirmation_backlog is
'Internal pending backlog for the paused Help improve Scout human visual-confirmation workflow.';
