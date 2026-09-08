-- Scout OneRestore limestone condition closure v1
-- Mirrors production migration 20260908230632 onerestore_limestone_condition_closure_v1.
-- Records bounded research exhaustion only; does not infer clean condition or treatment need.

with targets(source_slug,source_native_id,source_url,source_date,confidence,recency_weight,notes) as (
  values
   ('ky-ornl-building-footprints'::text,'{2922dfd3-bba4-4606-a37c-8b6ff9d4fda0}'::text,
    'https://sproutandsing.kindermusik.com/location/58262'::text,null::date,0.93::numeric,0.60::numeric,
    'Current public evidence supports active use at 412 E Second St, but no current close-range limestone facade imagery sufficient to distinguish OneRestore-relevant stain classes was established.'::text),
   ('ky-ornl-building-footprints','{61f55246-2970-4d29-bbc8-337f99a48b59}',
    'https://studioaarch.com/immanuel-baptist-church/',null::date,0.92::numeric,0.45::numeric,
    'The historic limestone building underwent a major rehabilitation before Immanuel Baptist reopened it in 2017 and remains in active use, but the available public material does not establish current close-range stain morphology in 2026.'),
   ('ky-ornl-building-footprints','{74d36c53-158b-47c0-868c-3e8d66eea255}',
    'https://kcrea.resimplifi.com/listings/8aa04ad5-market-street-potential-for-restaurant-bar-office-retail','2026-02-07'::date,0.88::numeric,0.82::numeric,
    'Current leasing imagery is recent enough to identify the building, but it does not support reliable classification of rust/iron staining, mineral scale, or atmospheric grime. Do not translate the earlier biological-growth negative into a restoration-stain negative.'),
   ('ky-ornl-building-footprints','{a2ce2968-e945-415f-9daf-b31b701c5101}',
    'https://digital.library.louisville.edu/?f%5Bcontributor_sim%5D%5B%5D=Joseph+%26+Joseph&f%5Bstreet_sim%5D%5B%5D=Third+Street+%28Louisville%2C+Ky.%29&f%5Bsubject_sim%5D%5B%5D=Buildings&locale=en&per_page=100&sort=system_modified_dtsi+desc','1930-11-08'::date,0.99::numeric,0.02::numeric,
    'Authoritative public exterior imagery located for Adath Israel Temple is historical rather than current. It cannot establish 2026 rust, mineral-scale, or atmospheric-grime condition.')
), resolved as (
  select t.*,bc.source_record_id as building_source_record_id
  from targets t
  join decisioning.building_candidates bc on bc.source_slug=t.source_slug and bc.source_native_id=t.source_native_id
)
insert into cleaning.surface_condition_observations(
  building_source_record_id,condition_class,evidence_kind,source_url,source_date,
  observation_scope,observed_morphology,confidence,recency_weight,
  treatment_need_inference_allowed,notes,attributes,created_at,updated_at
)
select r.building_source_record_id,'insufficient_visual_resolution','other',r.source_url,r.source_date,
       'exterior_facade',
       jsonb_build_object('target_soil_classes',jsonb_build_array('rust-iron-staining','mineral-scale','atmospheric-grime'),'stain_origin_resolved',false),
       r.confidence,r.recency_weight,false,r.notes,
       jsonb_build_object('pilot','onerestore_chemistry_v1','research_pass','onerestore_limestone_condition_2026-09-08','researched_on','2026-09-08','image_retained',false,'research_exhausted',true,'requery_only_if_new_visual_or_field_evidence',true),
       now(),now()
from resolved r
where not exists(
  select 1 from cleaning.surface_condition_observations o
  where o.building_source_record_id=r.building_source_record_id
    and o.attributes->>'research_pass'='onerestore_limestone_condition_2026-09-08'
);

create or replace view cleaning.v_onerestore_candidate_building_queue_v3 as
with exhausted as (
  select o.building_source_record_id,
    bool_or(o.condition_class='insufficient_visual_resolution'
            and o.attributes->>'research_pass'='onerestore_limestone_condition_2026-09-08'
            and coalesce((o.attributes->>'research_exhausted')::boolean,false)) as public_stain_research_exhausted,
    count(*) filter(where o.attributes->>'research_pass'='onerestore_limestone_condition_2026-09-08') as research_evidence_rows,
    max(o.updated_at) filter(where o.attributes->>'research_pass'='onerestore_limestone_condition_2026-09-08') as research_updated_at
  from cleaning.surface_condition_observations o
  group by o.building_source_record_id
)
select q.*,
  coalesce(e.public_stain_research_exhausted,false) as public_stain_research_exhausted,
  coalesce(e.research_evidence_rows,0) as research_evidence_rows,e.research_updated_at,
  case
    when q.verification_priority='identity_resolution_required' then 'identity_resolution_required'
    when q.any_confirmed_stain then 'product_test_patch_candidate'
    when q.any_likely_stain then 'field_stain_confirmation_required'
    when q.verification_priority='limestone_stain_verification_high' and coalesce(e.public_stain_research_exhausted,false) then 'await_new_visual_or_field_stain_evidence'
    else q.verification_priority end as verification_state_v3,
  case
    when q.verification_priority='identity_resolution_required' then 'resolve_physical_building_or_surface_zone_identity'
    when q.any_confirmed_stain then 'perform_project_specific_test_patch_and_resolve_adjacent_surfaces_runoff_and_route_compatibility'
    when q.any_likely_stain then 'obtain_close_range_or_field_confirmation_of_stain_origin'
    when q.verification_priority='limestone_stain_verification_high' and coalesce(e.public_stain_research_exhausted,false) then 'wait_for_new_close_range_visual_or_field_evidence'
    else 'verify_actual_stain_morphology_and_origin' end as next_action_v3,
  0 as automatic_score_delta_v3,
  'V3 treats exhausted public research as a terminal research state, not proof that a facade is clean. New close-range visual or field evidence can reopen stain classification; environmental or historic-substrate context alone cannot.'::text as condition_guardrail_v3
from cleaning.v_onerestore_candidate_building_queue_v2 q
left join exhausted e using(building_source_record_id);
