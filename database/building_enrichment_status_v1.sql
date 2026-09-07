-- Scout building enrichment status v1
--
-- Physical/context enrichment posture only. This view intentionally contains
-- no pricing, commercial value, lead scoring, or outreach prioritization.

create or replace view decisioning.v_building_enrichment_status_v1
with (security_invoker=true) as
with evidence as (
  select
    m.building_source_record_id,
    max(o.observed_at) as last_attribute_enriched_at,
    max(o.source_timestamp) as latest_source_timestamp,
    count(distinct o.source_id)::int as attribute_source_count,
    count(*)::int as matched_attribute_observation_count
  from decisioning.building_attribute_matches m
  join decisioning.building_attribute_observations o on o.id=m.observation_id
  group by m.building_source_record_id
)
select
  a.building_source_record_id,
  a.source_slug,
  a.source_native_id,
  a.footprint_sqft,
  a.resolved_height_m,
  a.resolved_height_status,
  a.resolved_height_source_slug,
  a.resolved_story_count,
  a.resolved_story_status,
  a.resolved_story_source_slug,
  a.resolved_facade_material,
  a.resolved_raw_facade_material,
  a.resolved_facade_material_status,
  a.resolved_facade_material_source_slug,
  a.glazing_signal,
  a.glazing_confidence,
  a.matched_building_part_count,
  a.vertical_geometry_signal,
  a.resolved_attribute_confidence,
  coalesce(h.individually_listed_building,false) as individually_listed_building,
  coalesce(h.within_listed_district,false) as within_listed_district,
  coalesce(h.national_historic_landmark_context,false) as national_historic_landmark_context,
  h.historic_match_confidence,
  e.last_attribute_enriched_at,
  e.latest_source_timestamp,
  coalesce(e.attribute_source_count,0) as attribute_source_count,
  coalesce(e.matched_attribute_observation_count,0) as matched_attribute_observation_count,
  (a.resolved_height_m is null) as needs_height,
  (a.resolved_story_count is null) as needs_stories,
  (a.resolved_facade_material is null) as needs_facade_material,
  (a.glazing_signal is null) as glazing_unresolved,
  (
    (case when a.resolved_height_m is not null then 1 else 0 end) +
    (case when a.resolved_story_count is not null then 1 else 0 end) +
    (case when a.resolved_facade_material is not null then 1 else 0 end) +
    (case when a.glazing_signal is not null then 1 else 0 end)
  )::int as resolved_physical_dimension_count,
  case
    when a.resolved_height_m is not null
      and a.resolved_story_count is not null
      and a.resolved_facade_material is not null then 'structurally_rich'
    when a.resolved_height_m is not null
      and (a.resolved_story_count is not null or a.resolved_facade_material is not null) then 'substantially_enriched'
    when a.resolved_height_m is not null
      or a.resolved_story_count is not null
      or a.resolved_facade_material is not null
      or a.glazing_signal is not null then 'partially_enriched'
    else 'unresolved'
  end as physical_enrichment_status,
  case
    when e.last_attribute_enriched_at is null then null
    else e.last_attribute_enriched_at + interval '1 year'
  end as nominal_refresh_due_at,
  case
    when e.last_attribute_enriched_at is null then 'never_enriched'
    when e.last_attribute_enriched_at + interval '1 year' <= now() then 'refresh_due'
    else 'current'
  end as refresh_status
from decisioning.v_building_resolved_attributes a
left join intelligence.v_building_historic_context h
  on h.building_source_record_id=a.building_source_record_id
left join evidence e
  on e.building_source_record_id=a.building_source_record_id;

revoke all on decisioning.v_building_enrichment_status_v1 from public,anon,authenticated;
grant select on decisioning.v_building_enrichment_status_v1 to service_role;

comment on view decisioning.v_building_enrichment_status_v1 is
  'Building-level physical/context enrichment posture only. Summarizes resolved evidence, missing dimensions, historic context, source recency and a nominal annual refresh date. Contains no commercial valuation or lead-ranking logic.';
