-- Scout livestock pasture candidate resolver v1.
--
-- This view intentionally produces candidate-only spatial context. Proximity and
-- land-cover classification do not establish field ownership or operation.

create or replace view agriculture.v_livestock_pasture_field_candidates_v1 as
with livestock as (
  select distinct
    i.candidate_id,
    i.farm_name,
    i.organization_id,
    i.state_code,
    i.county_name as farm_county_name,
    i.best_address,
    i.location as farm_location,
    i.location_confidence,
    i.enterprise_kinds
  from agriculture.farm_livestock_inventory_v1 i
  where i.candidate_id is not null
    and i.location is not null
    and i.enterprise_kinds && array['beef','dairy','equine','other_livestock']::text[]
), candidates as (
  select l.*,n.*
  from livestock l
  cross join lateral (
    select
      p.field_id,
      p.state_fips as field_state_fips,
      p.county_name as field_county_name,
      p.county_fips as field_county_fips,
      p.gross_acres,
      p.profile_class,
      p.pasture_years,
      p.hay_years,
      p.forage_years,
      p.pasture_persistence_score,
      p.forage_persistence_score,
      p.grazing_relevance,
      p.classification_confidence,
      round(st_distance(f.geometry::geography,l.farm_location))::integer as distance_m,
      st_intersects(f.geometry,l.farm_location::geometry) as farm_point_intersects_field,
      coalesce(po.parcel_overlap_records,0)::integer as parcel_overlap_records
    from agriculture.field_pasture_profiles_v1 p
    join agriculture.field_boundaries f on f.id=p.field_id
    left join lateral (
      select count(*)::integer as parcel_overlap_records
      from agriculture.field_parcel_overlaps x
      where x.field_id=p.field_id
    ) po on true
    where p.grazing_relevance in ('high','moderate')
      and f.source_present
      and f.geometry && st_expand(l.farm_location::geometry,0.035)
      and st_dwithin(f.geometry::geography,l.farm_location,3218.688)
    order by f.geometry <-> l.farm_location::geometry
    limit 40
  ) n
), scored as (
  select c.*,
    (case
       when c.farm_point_intersects_field then 40
       when c.distance_m<=250 then 32
       when c.distance_m<=1000 then 22
       else 10
     end
     + case c.grazing_relevance when 'high' then 30 else 20 end
     + case when c.parcel_overlap_records>0 then 10 else 0 end
     + least(10,round(coalesce(c.location_confidence,0)*10)::integer)
    )::integer as ranking_score_v1
  from candidates c
)
select
  s.candidate_id,
  s.farm_name,
  s.organization_id,
  s.state_code,
  s.farm_county_name,
  s.best_address,
  s.location_confidence,
  s.enterprise_kinds,
  s.field_id,
  s.field_state_fips,
  s.field_county_name,
  s.field_county_fips,
  s.gross_acres,
  s.profile_class,
  s.pasture_years,
  s.hay_years,
  s.forage_years,
  s.pasture_persistence_score,
  s.forage_persistence_score,
  s.grazing_relevance,
  s.classification_confidence,
  s.distance_m,
  s.farm_point_intersects_field,
  s.parcel_overlap_records,
  case
    when s.farm_point_intersects_field then 'farm_location_intersects_candidate_pasture'
    when s.distance_m<=250 then 'candidate_pasture_within_250m'
    when s.distance_m<=1000 then 'candidate_pasture_within_1km'
    else 'candidate_pasture_within_2mi'
  end as spatial_evidence_state,
  'unconfirmed'::text as operator_relationship_status,
  s.ranking_score_v1,
  row_number() over (
    partition by s.candidate_id
    order by s.ranking_score_v1 desc,s.distance_m asc,s.field_id
  )::integer as candidate_rank,
  jsonb_build_object(
    'resolver_version','livestock_pasture_spatial_v1',
    'relationship_inference','candidate_only',
    'distance_m',s.distance_m,
    'farm_point_intersects_field',s.farm_point_intersects_field,
    'parcel_overlap_records',s.parcel_overlap_records,
    'warning','proximity and land-cover do not establish ownership or operation'
  ) as evidence_summary
from scored s;

comment on view agriculture.v_livestock_pasture_field_candidates_v1 is
  'Candidate-only nearby pasture fields for geocoded beef, dairy, equine, and other-livestock farms. Never treat rows as operator/ownership links without separate corroboration.';

create or replace view agriculture.v_livestock_pasture_resolution_summary_v1 as
with candidate_summary as (
  select
    c.candidate_id,
    count(*)::integer as candidate_field_count,
    count(*) filter (where c.farm_point_intersects_field)::integer as intersecting_field_count,
    count(*) filter (where c.distance_m<=250)::integer as within_250m_field_count,
    count(*) filter (where c.grazing_relevance='high')::integer as high_grazing_relevance_count,
    min(c.distance_m)::integer as nearest_candidate_distance_m,
    round(sum(c.gross_acres))::numeric as nearby_candidate_acres_not_attributed,
    max(c.ranking_score_v1)::integer as best_ranking_score_v1
  from agriculture.v_livestock_pasture_field_candidates_v1 c
  group by c.candidate_id
), bridge_summary as (
  select
    b.operator_candidate_id as candidate_id,
    count(*)::integer as existing_bridge_candidate_count,
    max(b.match_confidence) as existing_bridge_max_confidence
  from agriculture.farm_operator_field_bridge_candidates b
  group by b.operator_candidate_id
)
select
  i.candidate_id,
  i.farm_name,
  i.organization_id,
  i.state_code,
  i.county_name,
  i.enterprise_kinds,
  i.location_confidence,
  (i.location is not null) as has_resolved_location,
  coalesce(s.candidate_field_count,0) as candidate_field_count,
  coalesce(s.intersecting_field_count,0) as intersecting_field_count,
  coalesce(s.within_250m_field_count,0) as within_250m_field_count,
  coalesce(s.high_grazing_relevance_count,0) as high_grazing_relevance_count,
  s.nearest_candidate_distance_m,
  s.nearby_candidate_acres_not_attributed,
  s.best_ranking_score_v1,
  coalesce(b.existing_bridge_candidate_count,0) as existing_bridge_candidate_count,
  b.existing_bridge_max_confidence,
  case
    when i.location is null then 'needs_location_resolution'
    when coalesce(b.existing_bridge_candidate_count,0)>0 then 'has_existing_operator_field_candidates'
    when coalesce(s.candidate_field_count,0)>0 then 'has_spatial_pasture_candidates_unconfirmed'
    else 'no_pasture_candidate_within_2mi'
  end as resolution_state
from agriculture.farm_livestock_inventory_v1 i
left join candidate_summary s on s.candidate_id=i.candidate_id
left join bridge_summary b on b.candidate_id=i.candidate_id
where i.enterprise_kinds && array['beef','dairy','equine','other_livestock']::text[];

comment on view agriculture.v_livestock_pasture_resolution_summary_v1 is
  'Resolution-state summary for pasture-first livestock farms. nearby_candidate_acres_not_attributed is contextual acreage only and must not be presented as farm-operated acreage.';
