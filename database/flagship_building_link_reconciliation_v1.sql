-- Reconcile curated flagship-facility records to canonical Scout buildings using
-- existing physical evidence. This intentionally separates facility geocodes from
-- building identity and preserves conflicting source observations rather than
-- overwriting them.
--
-- Rules:
--   * 400 West Market: link to the nearby canonical footprint corroborated by
--     first-party 35 stories plus OSM/Overture 167 m / 35-story evidence.
--   * PNC Tower Louisville: link to the nearby canonical footprint corroborated
--     by first-party 38 stories plus OSM/Overture 156 m / 40-story evidence.
--   * 300 West Vine / Kincaid Towers: clear the single-building link because the
--     current canonical geometry overlaps multiple distinct source buildings.
--   * Curated first-party story/glazing evidence is stored as its own building
--     observation. Source-evidence confidence is kept separate from the curated
--     identity-match confidence.

begin;

with src as (
  select id from ingest.sources where slug='scout-flagship-facility-registry' limit 1
), targets as (
  select t.*
  from intelligence.premium_exterior_targets t, src
  where t.source_id=src.id
    and t.source_native_id in ('400-west-market','pnc-tower-louisville')
), chosen as (
  select distinct on (t.source_native_id)
         t.id as target_id,
         bc.source_record_id as building_id,
         bc.source_slug,
         bc.footprint_sqft,
         r.resolved_height_m,
         st_distance(t.location::geography,bc.location::geography) as distance_m
  from targets t
  join decisioning.building_attribute_observations o
    on (t.source_native_id='400-west-market' and o.story_count=35 and o.height_m=167)
    or (t.source_native_id='pnc-tower-louisville' and o.story_count=40 and o.height_m=156)
  join ingest.sources os on os.id=o.source_id and os.slug='openstreetmap-geofabrik-building-attributes'
  join decisioning.building_attribute_matches m on m.observation_id=o.id
  join decisioning.building_candidates bc on bc.source_record_id=m.building_source_record_id
  join decisioning.v_building_resolved_attributes r on r.building_source_record_id=bc.source_record_id
  where t.location is not null and bc.location is not null
    and st_dwithin(t.location::geography,bc.location::geography,250)
  order by t.source_native_id, st_distance(t.location::geography,bc.location::geography)
)
update intelligence.premium_exterior_targets t
set building_source_record_id=c.building_id,
    building_source_slug=c.source_slug,
    footprint_sqft=c.footprint_sqft,
    mapped_height_m=c.resolved_height_m,
    building_match_distance_m=c.distance_m,
    evidence=coalesce(t.evidence,'{}'::jsonb) || jsonb_build_object(
      'building_link_status','reconciled_existing_evidence',
      'building_link_reconciled_at',now(),
      'building_link_basis','first_party_story_count corroborated by matched OSM/Overture building evidence',
      'building_link_guardrail','Facility geocode is not itself building identity; link selected by corroborating physical evidence.'
    ),
    updated_at=now()
from chosen c
where t.id=c.target_id;

with src as (
  select id from ingest.sources where slug='scout-flagship-facility-registry' limit 1
)
update intelligence.premium_exterior_targets t
set building_source_record_id=null,
    building_source_slug=null,
    footprint_sqft=null,
    mapped_height_m=null,
    building_match_distance_m=null,
    evidence=coalesce(t.evidence,'{}'::jsonb) || jsonb_build_object(
      'building_link_status','unresolved_merged_footprint',
      'building_link_reconciled_at',now(),
      'building_link_basis','existing canonical footprint overlaps multiple distinct building observations',
      'building_link_guardrail','Do not treat facility geocode or merged footprint as a verified single-building identity.'
    ),
    updated_at=now()
from src
where t.source_id=src.id and t.source_native_id='300-west-vine-kincaid-towers';

with src as (
  select id from ingest.sources where slug='scout-flagship-facility-registry' limit 1
), eligible as (
  select t.*,bc.geometry as building_geometry
  from intelligence.premium_exterior_targets t
  join src on t.source_id=src.id
  join decisioning.building_candidates bc on bc.source_record_id=t.building_source_record_id
  where t.source_native_id in ('400-west-market','pnc-tower-louisville')
)
insert into decisioning.building_attribute_observations(
  source_id,source_native_id,source_feature_kind,observed_at,source_timestamp,geometry,
  height_m,height_status,story_count,story_status,facade_material,raw_facade_material,
  facade_material_status,glazing_signal,has_parts,confidence,attributes,updated_at
)
select t.source_id,t.source_native_id,'building',now(),coalesce(t.last_observed_at,t.updated_at,now()),
       coalesce(t.location::geometry,st_pointonsurface(t.building_geometry)),
       null,'unknown',t.stated_levels,
       case when t.stated_levels is not null then 'documented' else 'unknown' end,
       null,null,'unknown',
       case when t.glazing_status='confirmed_glazed' and coalesce(t.evidence->>'glazing_evidence','')<>'' then 'confirmed_glazed' else null end,
       null,coalesce(t.confidence,0.9),
       jsonb_strip_nulls(jsonb_build_object(
         'evidence_origin','flagship_facility_registry',
         'authority_tier',t.evidence->>'authority_tier',
         'authoritative_source_url',t.evidence->>'authoritative_source_url',
         'documented_stories',t.stated_levels,
         'glazing_evidence',t.evidence->>'glazing_evidence',
         'glazing_source_url',t.evidence->>'glazing_source_url',
         'building_link_status',t.evidence->>'building_link_status'
       )),now()
from eligible t
where t.stated_levels is not null
   or (t.glazing_status='confirmed_glazed' and coalesce(t.evidence->>'glazing_evidence','')<>'')
on conflict(source_id,source_native_id,source_feature_kind) do update set
  observed_at=excluded.observed_at,
  source_timestamp=excluded.source_timestamp,
  geometry=excluded.geometry,
  story_count=excluded.story_count,
  story_status=excluded.story_status,
  glazing_signal=excluded.glazing_signal,
  confidence=excluded.confidence,
  attributes=excluded.attributes,
  updated_at=now();

with src as (
  select id from ingest.sources where slug='scout-flagship-facility-registry' limit 1
), desired as (
  select o.id as observation_id,t.building_source_record_id,
         st_distance(t.location::geography,bc.location::geography) as distance_m
  from decisioning.building_attribute_observations o
  join src on o.source_id=src.id
  join intelligence.premium_exterior_targets t on t.source_id=src.id and t.source_native_id=o.source_native_id
  join decisioning.building_candidates bc on bc.source_record_id=t.building_source_record_id
  where o.source_feature_kind='building'
    and o.source_native_id in ('400-west-market','pnc-tower-louisville')
    and t.building_source_record_id is not null
), del as (
  delete from decisioning.building_attribute_matches m
  using desired d
  where m.observation_id=d.observation_id
    and m.building_source_record_id<>d.building_source_record_id
  returning m.observation_id
)
insert into decisioning.building_attribute_matches(
  building_source_record_id,observation_id,match_basis,overlap_ratio,centroid_distance_m,confidence,matched_at
)
select building_source_record_id,observation_id,'curated_facility_reconciliation',null,distance_m,0.99,now()
from desired
on conflict(building_source_record_id,observation_id) do update set
  match_basis=excluded.match_basis,
  overlap_ratio=excluded.overlap_ratio,
  centroid_distance_m=excluded.centroid_distance_m,
  confidence=excluded.confidence,
  matched_at=now();

commit;
