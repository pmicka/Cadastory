-- Scout by Cadastory
-- Telecom aviation-marking determination lookup queue v1.
-- Research-only. Uses existing ASR registration identifiers to make the current tower
-- universe systematically lookup-ready without inferring that a tower is painted.
-- Marking/paint status remains unknown until the FAA/FCC determination evidence is fetched.

create schema if not exists research;

create or replace view research.v_telecom_marking_determination_lookup_queue_v1 as
select
  a.registration_number,
  a.file_number,
  a.unique_system_identifier,
  a.structure_type,
  a.overall_height_agl_m,
  a.structure_height_m,
  a.structure_state,
  a.structure_city,
  a.structure_county_fips,
  coalesce(a.owner_name,a.raw_attributes->'attributes'->>'Licensee') as owner_or_licensee,
  a.faa_study_number,
  a.faa_issue_date,
  a.date_constructed,
  a.last_action_date,
  a.application_purpose,
  a.status_code,
  a.within_pilot,
  case
    when coalesce(a.faa_study_number,'')<>'' then 'faa_study_already_present'
    when coalesce(a.registration_number,'')<>'' then 'asr_registration_lookup_ready'
    else 'identifier_gap'
  end as determination_lookup_state,
  case
    when coalesce(a.faa_study_number,'')<>'' then 1
    when coalesce(a.registration_number,'')<>'' and a.overall_height_agl_m>=120 then 2
    when coalesce(a.registration_number,'')<>'' and a.overall_height_agl_m>=90 then 3
    when coalesce(a.registration_number,'')<>'' then 4
    else 5
  end as lookup_priority,
  'unknown_requires_determination'::text as aviation_marking_status,
  case
    when coalesce(a.faa_study_number,'')<>'' then
      'FAA study number is already present; fetch/resolve the determination and marking/lighting specification before inferring paint applicability.'
    when coalesce(a.registration_number,'')<>'' then
      'ASR registration number is available, so full registration/FAA determination evidence can be fetched systematically. Height is used only to order research work, not to infer painting.'
    else
      'No determination lookup identifier is currently available.'
  end as research_interpretation
from telecom.asr_structures a
where a.within_pilot is true;

comment on view research.v_telecom_marking_determination_lookup_queue_v1 is
  'Research-only telecom lookup queue. All paint/marking status remains unknown until determination evidence is resolved. Height orders lookup work only; it is never treated as proof of aviation paint.';

create or replace view research.v_telecom_marking_determination_lookup_summary_v1 as
select
  determination_lookup_state,
  lookup_priority,
  structure_type,
  count(*)::bigint as towers,
  count(*) filter (where owner_or_licensee is not null)::bigint as owner_or_licensee_available
from research.v_telecom_marking_determination_lookup_queue_v1
group by determination_lookup_state,lookup_priority,structure_type;

comment on view research.v_telecom_marking_determination_lookup_summary_v1 is
  'Research-only summary of telecom marking-determination lookup readiness.';

update research.painting_signal_target_readiness
set confirmed_hit_readiness='asset_only',
    forecast_readiness='applicability_only',
    forecast_sources=array['telecom.asr_structures','fcc-asr-weekly'],
    confirmed_hit_basis='Scout resolves the tower asset and ASR registration identifier, but current data does not contain a confirmed painting/repainting maintenance scope.',
    forecast_basis=concat(
      'The current pilot tower universe is lookup-ready rather than paint-classified: ',
      (select count(*) from research.v_telecom_marking_determination_lookup_queue_v1 where determination_lookup_state='faa_study_already_present'),
      ' towers already carry an FAA study number and ',
      (select count(*) from research.v_telecom_marking_determination_lookup_queue_v1 where determination_lookup_state='asr_registration_lookup_ready'),
      ' additional towers carry ASR registration identifiers suitable for systematic determination lookup. Marking status remains unknown until that evidence is fetched.'
    ),
    observation_note=concat(
      (select count(*) from research.v_telecom_marking_determination_lookup_queue_v1),
      ' pilot towers are identifier-resolved for determination research; owner/licensee text is available on ',
      (select count(*) from research.v_telecom_marking_determination_lookup_queue_v1 where owner_or_licensee is not null),
      '. No tower is labeled painted solely from height or structure type.'
    ),
    blocker='Need systematic FAA/FCC determination retrieval plus marking/lighting specification and later maintenance-condition/project evidence. Height alone is not paint applicability evidence.',
    next_action='Fetch determinations by existing FAA study number first, then by ASR registration number; normalize marking specification before pursuing maintenance/repainting sources.',
    reviewed_at=now()
where survey_key='telecom_operator:aviation_marked_tower';

revoke all on research.v_telecom_marking_determination_lookup_queue_v1 from anon, authenticated;
revoke all on research.v_telecom_marking_determination_lookup_summary_v1 from anon, authenticated;
