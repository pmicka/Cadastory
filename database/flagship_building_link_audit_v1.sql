-- Scout flagship facility -> building link audit v1
--
-- Facility geocodes are not building identity. This view surfaces shared links,
-- documented story/height conflicts and distant links before any physical
-- evidence is promoted into canonical building enrichment. Explicitly
-- reconciled links are distinguished from raw geocode-distance warnings.

create or replace view intelligence.v_flagship_building_link_audit_v1
with (security_invoker=true) as
with flagship as (
  select
    p.*,
    coalesce(p.evidence->>'facility_scope','') as facility_scope
  from intelligence.premium_exterior_targets p
  join ingest.sources src on src.id=p.source_id
  where src.slug='scout-flagship-facility-registry'
), shared as (
  select building_source_record_id,count(*)::int as shared_link_count
  from flagship
  where building_source_record_id is not null
  group by building_source_record_id
)
select
  f.id as flagship_target_id,
  f.source_native_id,
  f.name,
  f.address_text,
  f.facility_scope,
  f.building_source_record_id,
  f.building_source_slug,
  f.building_match_distance_m,
  f.stated_levels,
  f.glazing_status,
  f.confidence as flagship_confidence,
  coalesce(s.shared_link_count,0) as shared_link_count,
  a.resolved_height_m,
  a.resolved_height_status,
  a.resolved_height_source_slug,
  a.resolved_story_count,
  a.resolved_story_status,
  a.resolved_story_source_slug,
  case
    when f.evidence->>'building_link_status'='unresolved_merged_footprint' then 'unresolved_merged_footprint'
    when f.building_source_record_id is null then 'unlinked'
    when f.stated_levels is not null
      and a.resolved_story_count is not null
      and abs(f.stated_levels-a.resolved_story_count) > 4 then 'documented_story_conflict'
    when f.stated_levels is not null
      and f.stated_levels >= 10
      and coalesce(a.resolved_height_m,0) < 30 then 'documented_height_conflict'
    when f.evidence->>'building_link_status'='reconciled_existing_evidence'
      and f.stated_levels is not null
      and a.resolved_story_count is not null
      and abs(f.stated_levels-a.resolved_story_count) <= 2
      and coalesce(s.shared_link_count,0)=1 then 'reconciled_verified'
    when coalesce(s.shared_link_count,0) > 1 then 'shared_facility_link'
    when f.building_match_distance_m > 100 then 'distant_facility_link'
    when f.stated_levels is not null
      and a.resolved_story_count is not null
      and abs(f.stated_levels-a.resolved_story_count) <= 2 then 'documented_story_compatible'
    else 'needs_review'
  end as link_audit_status,
  case
    when f.building_source_record_id is null then false
    when f.stated_levels is not null
      and a.resolved_story_count is not null
      and abs(f.stated_levels-a.resolved_story_count) <= 2
      and coalesce(s.shared_link_count,0)=1 then true
    else false
  end as documented_story_link_compatible,
  f.evidence
from flagship f
left join shared s on s.building_source_record_id=f.building_source_record_id
left join decisioning.v_building_resolved_attributes a
  on a.building_source_record_id=f.building_source_record_id;

revoke all on intelligence.v_flagship_building_link_audit_v1 from public,anon,authenticated;
grant select on intelligence.v_flagship_building_link_audit_v1 to service_role;

comment on view intelligence.v_flagship_building_link_audit_v1 is
  'Audits flagship facility-to-building links before physical evidence promotion. Explicitly reconciled links remain distinguishable from raw geocode-distance warnings; unresolved merged footprints are quarantined.';
