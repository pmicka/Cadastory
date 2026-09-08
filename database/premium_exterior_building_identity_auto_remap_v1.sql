-- Premium exterior building identity auto-remap v1
--
-- Repairs only quarantined links where a different nearest building footprint is
-- within 10m and has at least a 10m lead over the second-nearest footprint.
-- The identity guard re-validates the promoted link during the update.

begin;

create temporary table _premium_exterior_unambiguous_remap
on commit drop
as
with q as (
  select *
  from intelligence.v_premium_exterior_building_link_resolution_queue_v1
  where remediation_priority=1
), ranked as (
  select
    q.target_id,
    q.prior_candidate_building_id,
    bc.source_record_id as candidate_id,
    bc.source_slug as candidate_slug,
    extensions.st_distance(q.target_location::extensions.geography,bc.geometry::extensions.geography) as edge_m,
    extensions.st_covers(bc.geometry,q.target_location::extensions.geometry) as point_inside,
    row_number() over (
      partition by q.target_id
      order by bc.geometry <-> q.target_location::extensions.geometry
    ) as rn
  from q
  join decisioning.building_candidates bc
    on q.target_location is not null
   and bc.geometry && extensions.st_expand(q.target_location::extensions.geometry,0.005)
), pivoted as (
  select
    target_id,
    max(prior_candidate_building_id::text)::uuid as prior_candidate_building_id,
    max(candidate_id::text) filter(where rn=1)::uuid as nearest_id,
    max(candidate_slug) filter(where rn=1) as nearest_slug,
    min(edge_m) filter(where rn=1) as nearest_edge_m,
    bool_or(point_inside) filter(where rn=1) as nearest_point_inside,
    min(edge_m) filter(where rn=2) as second_edge_m
  from ranked
  where rn<=2
  group by target_id
)
select
  target_id,
  prior_candidate_building_id,
  nearest_id,
  nearest_slug,
  nearest_edge_m,
  nearest_point_inside,
  second_edge_m,
  second_edge_m-nearest_edge_m as uniqueness_margin_m
from pivoted
where nearest_id is not null
  and nearest_id<>prior_candidate_building_id
  and nearest_edge_m<=10
  and (second_edge_m is null or second_edge_m-nearest_edge_m>=10);

update intelligence.premium_exterior_targets t
set building_source_record_id=r.nearest_id,
    building_source_slug=bc.source_slug,
    footprint_sqft=bc.footprint_sqft,
    mapped_height_m=a.resolved_height_m,
    property_address=bc.property_address,
    property_city=bc.property_city,
    state_code=coalesce(bc.state_code,t.state_code),
    postal_code=bc.postal_code,
    building_match_distance_m=case
      when t.location is not null and bc.location is not null
        then extensions.st_distance(t.location::extensions.geography,bc.location::extensions.geography)
      else null
    end,
    evidence=coalesce(t.evidence,'{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
      'building_identity_remediation','auto_remapped_unique_nearest_footprint',
      'building_identity_remediated_at',now(),
      'building_identity_prior_candidate_id',r.prior_candidate_building_id,
      'building_identity_new_candidate_id',r.nearest_id,
      'building_identity_new_edge_distance_m',round(r.nearest_edge_m::numeric,2),
      'building_identity_second_nearest_margin_m',round(r.uniqueness_margin_m::numeric,2),
      'building_identity_remediation_guardrail','Auto-remap requires a different nearest building footprint within 10m and at least a 10m margin over the second-nearest footprint.'
    )),
    updated_at=now()
from _premium_exterior_unambiguous_remap r
join decisioning.building_candidates bc on bc.source_record_id=r.nearest_id
left join decisioning.v_building_resolved_attributes a on a.building_source_record_id=r.nearest_id
where t.id=r.target_id;

update intelligence.premium_exterior_building_link_candidates q
set status='superseded',
    last_observed_at=now(),
    evidence=coalesce(q.evidence,'{}'::jsonb) || jsonb_build_object(
      'superseded_at',now(),
      'superseded_by_building_id',r.nearest_id,
      'supersession_basis','unique_nearest_footprint_within_10m'
    )
from _premium_exterior_unambiguous_remap r
where q.target_id=r.target_id
  and q.candidate_building_source_record_id=r.prior_candidate_building_id;

insert into intelligence.premium_exterior_building_link_candidates(
  target_id,candidate_building_source_record_id,candidate_building_source_slug,source_slug,
  prior_centroid_distance_m,footprint_edge_distance_m,point_inside_footprint,
  match_basis,status,confidence,evidence,first_observed_at,last_observed_at
)
select
  r.target_id,
  r.nearest_id,
  r.nearest_slug,
  s.slug,
  t.building_match_distance_m,
  r.nearest_edge_m,
  r.nearest_point_inside,
  'unique_nearest_footprint_within_10m',
  'verified',
  case when r.nearest_point_inside then 0.99 else 0.95 end,
  jsonb_strip_nulls(jsonb_build_object(
    'verified_at',now(),
    'verification_basis','unique_nearest_footprint_within_10m',
    'second_nearest_margin_m',round(r.uniqueness_margin_m::numeric,2),
    'prior_candidate_building_id',r.prior_candidate_building_id
  )),
  now(),now()
from _premium_exterior_unambiguous_remap r
join intelligence.premium_exterior_targets t on t.id=r.target_id
join ingest.sources s on s.id=t.source_id
on conflict (target_id,candidate_building_source_record_id) do update set
  candidate_building_source_slug=excluded.candidate_building_source_slug,
  source_slug=excluded.source_slug,
  prior_centroid_distance_m=excluded.prior_centroid_distance_m,
  footprint_edge_distance_m=excluded.footprint_edge_distance_m,
  point_inside_footprint=excluded.point_inside_footprint,
  match_basis=excluded.match_basis,
  status='verified',
  confidence=excluded.confidence,
  evidence=coalesce(intelligence.premium_exterior_building_link_candidates.evidence,'{}'::jsonb) || excluded.evidence,
  last_observed_at=now();

commit;
