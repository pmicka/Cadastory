-- Scout by Cadastory
-- KDE surface-work facility resolution probe v1.
-- Research-only. Resolves preservation/painting occurrences in KDE District Facility Plan
-- document text to the nearest preceding facility/project title already extracted from the
-- same source document. No production scoring, MCP exposure, or opportunity creation.

create schema if not exists research;

create or replace view research.v_kde_surface_work_facility_resolution_probe as
with src as (
  select id
  from ingest.sources
  where slug='kde-district-facility-plans'
), docs as (
  select
    split_part(r.source_native_id,'|',1) as doc_key,
    r.source_native_id as doc_source_native_id,
    r.raw_payload->>'district_label' as district_label,
    r.raw_payload->>'document_name' as document_name,
    r.raw_payload->>'kde_approval_date_text' as kde_approval_date_text,
    r.raw_payload->>'next_dfp_due_text' as next_dfp_due_text,
    r.raw_payload->>'extracted_text' as document_text
  from ingest.raw_records r
  join src s on s.id=r.source_id
  where coalesce(r.raw_payload->>'extracted_text','')<>''
), families(signal_family,family_regex) as (
  values
    ('exterior_paint_recoat'::text,
     'exterior[^a-z]{0,40}(paint|painting|repaint|coat|coating)|repaint[^a-z]{0,30}(exterior|eifs|dryvit)|recoat[^a-z]{0,30}(exterior|eifs|dryvit)'::text),
    ('masonry_restoration_tuckpoint_seal',
     'clean(ing)?[^a-z]{0,35}(brick|masonry|stone)|tuck[ -]?point|repoint|masonry restoration|masonry repair[^a-z]{0,35}(seal|clean)|seal(ing)?[^a-z]{0,30}(masonry|brick|stone)'),
    ('eifs_dryvit_preservation','eifs|dryvit|dri-it'),
    ('joint_sealant_caulk','joint sealant|exterior sealant|sealant replacement|caulk|caulking'),
    ('waterproofing','waterproofing|water proofing|waterproof[^a-z]{0,30}(wall|masonry|concrete|exterior|roof structure)'),
    ('concrete_clean_repair_coat','concrete cleaning|clean(ing)?[^a-z]{0,25}concrete|concrete[^a-z]{0,30}(repair|coat|coating|sealant|sealer)'),
    ('roof_recoat_restoration','roof restoration|restore[^a-z]{0,20}roof|roof recover|roof re-cover|recover[^a-z]{0,20}roof|roof resurfacing|roof membrane coating|fluid[- ]applied roof|silicone[^a-z]{0,20}roof|acrylic[^a-z]{0,20}roof|elastomeric[^a-z]{0,20}roof|recoat(ing)?.{0,60}roof|roof.{0,60}recoat(ing)?')
), occurrences as (
  select
    d.*,
    f.signal_family,
    f.family_regex,
    gs.occurrence_number,
    regexp_substr(lower(d.document_text),f.family_regex,1,gs.occurrence_number) as matched_phrase,
    regexp_instr(lower(d.document_text),f.family_regex,1,gs.occurrence_number,0) as signal_position
  from docs d
  cross join families f
  cross join lateral generate_series(
    1,
    regexp_count(lower(d.document_text),f.family_regex)
  ) as gs(occurrence_number)
), projects as (
  select
    split_part(r.source_native_id,'|',1) as doc_key,
    r.source_native_id as project_source_native_id,
    r.raw_payload->>'candidate_kind' as candidate_kind,
    r.raw_payload->>'title' as facility_title,
    r.raw_payload->>'schedule_bucket' as schedule_bucket,
    r.raw_payload->>'estimated_cost' as estimated_cost,
    r.raw_payload->>'gross_sf' as gross_sf,
    r.raw_payload->>'raw_line' as project_raw_line
  from ingest.raw_records r
  join src s on s.id=r.source_id
  where r.raw_payload->>'candidate_kind' in ('project','facility_priority')
    and coalesce(r.raw_payload->>'title','') ~ '[A-Za-z]{3}'
), candidates as (
  select
    o.*,
    p.project_source_native_id,
    p.candidate_kind,
    p.facility_title,
    p.schedule_bucket,
    p.estimated_cost,
    p.gross_sf,
    p.project_raw_line,
    case
      when strpos(
        reverse(left(lower(o.document_text),greatest(o.signal_position-1,0))),
        reverse(lower(p.facility_title))
      ) > 0
      then length(left(lower(o.document_text),greatest(o.signal_position-1,0)))
           - strpos(
               reverse(left(lower(o.document_text),greatest(o.signal_position-1,0))),
               reverse(lower(p.facility_title))
             )
           - length(p.facility_title) + 2
    end as facility_position
  from occurrences o
  join projects p on p.doc_key=o.doc_key
), ranked as (
  select
    c.*,
    c.signal_position-c.facility_position as distance_before_signal,
    row_number() over (
      partition by c.doc_source_native_id,c.signal_family,c.occurrence_number
      order by
        case
          when c.facility_position is not null and c.facility_position<=c.signal_position
            then c.signal_position-c.facility_position
          else 999999
        end,
        length(c.facility_title) desc,
        c.project_source_native_id
    ) as resolution_rank
  from candidates c
), resolved as (
  select
    r.*,
    case
      when r.facility_position is not null
       and r.distance_before_signal between 0 and 1200 then 'strong'
      when r.facility_position is not null
       and r.distance_before_signal between 1201 and 2500 then 'medium'
      else 'unresolved'
    end as facility_resolution_confidence
  from ranked r
  where r.resolution_rank=1
)
select
  doc_key,
  doc_source_native_id,
  district_label,
  document_name,
  kde_approval_date_text,
  next_dfp_due_text,
  signal_family,
  occurrence_number,
  matched_phrase,
  signal_position,
  case when facility_resolution_confidence<>'unresolved' then project_source_native_id end as resolved_project_source_native_id,
  case when facility_resolution_confidence<>'unresolved' then facility_title end as resolved_facility_title,
  case when facility_resolution_confidence<>'unresolved' then candidate_kind end as resolved_candidate_kind,
  case when facility_resolution_confidence<>'unresolved' then schedule_bucket end as schedule_bucket,
  case when facility_resolution_confidence<>'unresolved' then estimated_cost end as estimated_cost,
  case when facility_resolution_confidence<>'unresolved' then gross_sf end as gross_sf,
  distance_before_signal,
  facility_resolution_confidence,
  regexp_replace(
    substring(document_text from greatest(1,signal_position-300) for 1000),
    '[\r\n]+',' ','g'
  ) as evidence_context,
  case
    when lower(substring(document_text from greatest(1,signal_position-300) for 1000))
      ~ '(pressure wash|power wash|wash(ing)?[^a-z]{0,35}(exterior|brick|masonry|concrete|eifs|surface)|clean(ing)?[^a-z]{0,35}(brick|masonry|stone|concrete|eifs|exterior))'
    then true else false
  end as cleaning_explicit_in_context
from resolved;

comment on view research.v_kde_surface_work_facility_resolution_probe is
  'Research-only KDE District Facility Plan surface-work occurrence resolver. Uses nearest preceding extracted facility/project title within the same document. Strong <=1200 chars, medium <=2500 chars, otherwise unresolved. Resolution is evidence localization, not operator compatibility or opportunity scoring.';

create or replace view research.v_kde_surface_work_facility_resolution_summary as
select
  signal_family,
  facility_resolution_confidence,
  count(*)::bigint as evidence_occurrences,
  count(distinct concat_ws('|',doc_source_native_id,coalesce(resolved_facility_title,'UNRESOLVED')))::bigint as distinct_document_facility_units,
  count(*) filter (where cleaning_explicit_in_context)::bigint as cleaning_explicit_occurrences
from research.v_kde_surface_work_facility_resolution_probe
group by signal_family,facility_resolution_confidence;

comment on view research.v_kde_surface_work_facility_resolution_summary is
  'Research-only summary of KDE surface-preservation evidence localization. Counts evidence occurrences and distinct document/facility units; not lead counts.';

update research.painting_signal_target_readiness
set confirmed_hit_basis =
      'Indiana capital-plan project rows provide explicit exterior painting scope. KDE District Facility Plan document evidence is now localized to extracted facility/project titles using a deterministic proximity resolver; only strong/medium resolutions should be treated as facility-linked research evidence.',
    observation_note = concat(
      'Indiana probe retains 9 explicit/mixed exterior-paint project rows. KDE resolver currently yields ',
      (select count(*) from research.v_kde_surface_work_facility_resolution_probe where signal_family='exterior_paint_recoat' and facility_resolution_confidence='strong'),
      ' strong and ',
      (select count(*) from research.v_kde_surface_work_facility_resolution_probe where signal_family='exterior_paint_recoat' and facility_resolution_confidence='medium'),
      ' medium facility-localized exterior-paint evidence occurrences; unresolved occurrences remain document-level only.'
    ),
    blocker = 'KDE proximity resolution is deterministic but still heuristic; preserve evidence context and require facility identity confidence before production promotion. Prep cleaning remains explicit only in a subset of scopes.',
    next_action = 'Backtest strong/medium KDE facility localization, normalize facility identities, and preserve schedule bucket/cost/square-footage where extracted.',
    reviewed_at=now()
where survey_key='school_district:exterior_building_painting';

revoke all on research.v_kde_surface_work_facility_resolution_probe from anon, authenticated;
revoke all on research.v_kde_surface_work_facility_resolution_summary from anon, authenticated;
