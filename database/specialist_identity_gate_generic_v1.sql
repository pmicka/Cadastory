-- Scout generic specialist physical-building identity gate v1
-- Mirrors production migration 20260908230114 specialist_identity_gate_generic_v1.
-- Reuses cleaning.specialist_identity_resolutions created by the earlier specialist identity layer.

create or replace view cleaning.v_specialist_building_identity_gate_v1 as
with m as (
  select a.building_source_record_id,
    count(*) filter(where hr.resource_type='building' and h.relationship_type=any(array['listed_resource_point_match','listed_resource_polygon_match'])) as building_match_count,
    min(h.distance_m) filter(where hr.resource_type='building' and h.relationship_type=any(array['listed_resource_point_match','listed_resource_polygon_match'])) as min_building_distance_m,
    array_remove(array_agg(distinct hr.resource_name) filter(where hr.resource_type='building' and h.relationship_type=any(array['listed_resource_point_match','listed_resource_polygon_match'])),null::text) as building_names,
    array_remove(array_agg(distinct hr.reference_number) filter(where hr.resource_type='building' and h.relationship_type=any(array['listed_resource_point_match','listed_resource_polygon_match'])),null::text) as building_reference_numbers,
    bool_or(h.relationship_type='within_listed_district') as within_listed_district
  from decisioning.v_building_resolved_attributes a
  left join intelligence.historic_resource_building_matches h on h.building_source_record_id=a.building_source_record_id
  left join intelligence.historic_resources hr on hr.id=h.historic_resource_id
  group by a.building_source_record_id
)
select m.building_source_record_id,
  coalesce(r.canonical_identity_name,case when coalesce(m.building_match_count,0)=1 then m.building_names[1] end) as canonical_identity_name,
  coalesce(r.canonical_reference_numbers,m.building_reference_numbers) as canonical_reference_numbers,
  m.building_match_count,m.min_building_distance_m,m.building_names,m.building_reference_numbers,
  coalesce(m.within_listed_district,false) as within_listed_district,
  r.resolution_scope,r.resolution_confidence,r.evidence as manual_resolution_evidence,
  case
    when r.id is not null and r.identity_ready and not r.surface_zone_resolution_required then 'manually_resolved_ready'
    when r.id is not null and (not r.identity_ready or r.surface_zone_resolution_required) then 'manually_resolved_blocked'
    when coalesce(m.building_match_count,0)=1 and m.min_building_distance_m<=35 then 'single_building_match_strong'
    when coalesce(m.building_match_count,0)=1 and m.min_building_distance_m<=50 then 'single_building_match_review'
    when coalesce(m.building_match_count,0)=1 and m.min_building_distance_m>50 then 'historic_building_match_too_distant'
    when coalesce(m.building_match_count,0)>1 then 'multi_building_ambiguous'
    when coalesce(m.building_match_count,0)=0 and coalesce(m.within_listed_district,false) then 'district_context_only'
    else 'canonical_footprint_only' end as identity_state,
  case
    when r.id is not null then r.identity_ready and not r.surface_zone_resolution_required
    when coalesce(m.building_match_count,0)=1 and m.min_building_distance_m<=35 then true
    when coalesce(m.building_match_count,0)=0 and not coalesce(m.within_listed_district,false) then true
    else false end as specialist_identity_ready,
  case
    when r.id is not null and r.identity_ready and not r.surface_zone_resolution_required then 'condition_or_surface_research'
    when r.id is not null then 'resolve_sub_building_or_surface_zone'
    when coalesce(m.building_match_count,0)=1 and m.min_building_distance_m<=35 then 'condition_or_surface_research'
    when coalesce(m.building_match_count,0)=1 and m.min_building_distance_m<=50 then 'confirm_building_identity'
    when coalesce(m.building_match_count,0)=1 and m.min_building_distance_m>50 then 'resolve_physical_building_identity'
    when coalesce(m.building_match_count,0)>1 then 'disambiguate_historic_building_identity'
    when coalesce(m.building_match_count,0)=0 and coalesce(m.within_listed_district,false) then 'resolve_property_identity_and_contributing_status'
    else 'condition_or_surface_research' end as identity_next_action,
  'Historic district/site overlap and nearby historic-resource points are contextual evidence only. Specialist substrate, stain and chemistry reasoning requires a resolved physical building or surface zone; never transfer material or condition evidence across nearby resources.'::text as guardrail
from m left join cleaning.specialist_identity_resolutions r on r.building_source_record_id=m.building_source_record_id;

create or replace view cleaning.v_onerestore_candidate_scaffold_v2 as
select f.*,i.canonical_identity_name,i.canonical_reference_numbers,i.identity_state,i.specialist_identity_ready,i.identity_next_action,
 case when not coalesce(i.specialist_identity_ready,false) then 'identity_resolution_required' else f.onerestore_fit_state end as onerestore_fit_state_v2,
 (f.product_test_patch_candidate and coalesce(i.specialist_identity_ready,false)) as product_test_patch_candidate_v2,
 case when not coalesce(i.specialist_identity_ready,false) then i.identity_next_action else f.next_action end as next_action_v2,
 0 as automatic_score_delta_v2,
 'V2 adds the reusable physical-building identity gate. A valid substrate/stain rule cannot promote a nearby historic resource, district context, merged footprint or unresolved surface zone into a chemistry candidate.'::text as identity_guardrail
from cleaning.v_onerestore_candidate_scaffold_v1 f
left join cleaning.v_specialist_building_identity_gate_v1 i on i.building_source_record_id=f.building_source_record_id;

create or replace view cleaning.v_onerestore_candidate_building_queue_v2 as
select building_source_record_id,array_agg(distinct candidate_key) candidate_keys,max(canonical_identity_name) canonical_identity_name,
 max(identity_state) identity_state,bool_or(specialist_identity_ready) specialist_identity_ready,
 max(restoration_classification_confidence) restoration_classification_confidence,max(resolved_facade_material) resolved_facade_material,
 max(resolved_raw_facade_material) resolved_raw_facade_material,bool_or(soil_confirmed) any_confirmed_stain,bool_or(soil_likely_visual) any_likely_stain,
 bool_or(product_test_patch_candidate_v2) any_product_test_patch_candidate,array_remove(array_agg(distinct soil_slug),null::text) evaluated_soil_classes,
 case when not bool_or(specialist_identity_ready) then 'identity_resolution_required'
      when bool_or(product_test_patch_candidate_v2) then 'product_test_patch_candidate'
      when bool_or(soil_likely_visual) then 'field_stain_confirmation_required'
      when max(resolved_facade_material)='limestone' then 'limestone_stain_verification_high'
      when max(resolved_facade_material)='brick' then 'brick_stain_verification' else 'surface_resolution_required' end verification_priority,
 false chemistry_scoreable,0 automatic_score_delta,
 'Building-level queue is deduplicated and identity-gated. No stain, product-fit, route-fit or score inference is allowed from historic context or substrate alone.'::text guardrail
from cleaning.v_onerestore_candidate_scaffold_v2 group by building_source_record_id;
