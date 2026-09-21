begin;

create temporary table _fw_road_trail_transition_v1 on commit drop as
with property_row as (
  select id
  from farm_watch.properties
  where slug='validation-property-01'
  limit 1
), road as (
  select
    o.id,
    extensions.st_geometryn(o.geometry,1) as g1,
    extensions.st_geometryn(o.geometry,2) as g2,
    extensions.st_geometryn(o.geometry,3) as g3,
    extensions.st_geometryn(o.geometry,4) as g4
  from farm_watch.property_operator_paths_v1 o
  join property_row p on p.id=o.property_id
  where o.path_key='flat-creek-gravel-access-road'
    and o.active
  limit 1
), trail as (
  select
    o.id,
    o.geometry,
    extensions.st_transform(o.geometry,32616) as geom_utm
  from farm_watch.property_operator_paths_v1 o
  join property_row p on p.id=o.property_id
  where o.path_key='flat-creek-phase3-image-trails'
    and o.active
  limit 1
), road_branch as (
  select
    r.id,
    r.g1,r.g2,r.g3,r.g4,
    extensions.st_transform(r.g3,32616) as g3_utm
  from road r
), trail_endpoints as (
  select
    (d.path)[1]::int as part_index,
    'start'::text as endpoint_side,
    extensions.st_startpoint(d.geom) as endpoint_utm
  from trail t
  cross join lateral extensions.st_dump(t.geom_utm) d
  union all
  select
    (d.path)[1]::int,
    'end',
    extensions.st_endpoint(d.geom)
  from trail t
  cross join lateral extensions.st_dump(t.geom_utm) d
), best_transition as (
  select
    e.part_index,
    e.endpoint_side,
    e.endpoint_utm as trail_endpoint_utm,
    extensions.st_closestpoint(rb.g3_utm,e.endpoint_utm) as road_point_utm,
    extensions.st_distance(
      extensions.st_closestpoint(rb.g3_utm,e.endpoint_utm),
      e.endpoint_utm
    ) as source_gap_m
  from road_branch rb
  cross join trail_endpoints e
  order by source_gap_m
  limit 1
), rebuilt_road as (
  select
    rb.id,
    rb.g1,rb.g2,rb.g4,
    extensions.st_transform(
      extensions.st_addpoint(
        extensions.st_linesubstring(
          rb.g3_utm,
          extensions.st_linelocatepoint(rb.g3_utm,b.road_point_utm),
          1.0
        ),
        b.trail_endpoint_utm,
        0
      ),
      4326
    ) as g3,
    b.part_index as trail_part_index,
    b.endpoint_side as trail_endpoint_side,
    b.source_gap_m,
    b.trail_endpoint_utm
  from road_branch rb
  cross join best_transition b
), final as (
  select
    r.id as road_id,
    t.id as trail_id,
    extensions.st_multi(
      extensions.st_collect(array[r.g1,r.g2,r.g3,r.g4])
    ) as road_geometry,
    r.trail_part_index,
    r.trail_endpoint_side,
    r.source_gap_m,
    r.trail_endpoint_utm
  from rebuilt_road r
  cross join trail t
)
select
  *,
  extensions.st_transform(trail_endpoint_utm,4326) as transition_point
from final;

do $$
declare
  r record;
begin
  select * into r from _fw_road_trail_transition_v1 limit 1;
  if r.road_id is null or r.trail_id is null then
    raise exception 'road/trail rows missing';
  end if;
  if r.source_gap_m < 2.0 or r.source_gap_m > 4.0 then
    raise exception 'unexpected road-to-trail transition gap before connection: % m', r.source_gap_m;
  end if;
end
$$;

update farm_watch.property_operator_paths_v1 o
set
  geometry=x.road_geometry,
  source_context=
    (o.source_context - 'trail_separation_v1')
    || jsonb_build_object(
      'trail_transition_v1',jsonb_build_object(
        'status','shared_endpoint_separate_canonical_objects',
        'trail_path_key','flat-creek-phase3-image-trails',
        'trail_feature_subclass','operator_confirmed_trail_network',
        'source_gap_closed_m',round(x.source_gap_m::numeric,2),
        'transition_point_geojson',extensions.st_asgeojson(x.transition_point,7)::jsonb,
        'trail_part_index',x.trail_part_index,
        'trail_endpoint_side',x.trail_endpoint_side,
        'geometry_relationship','touch_at_single_transition_node',
        'operator_feedback_local_date','2026-09-20'
      ),
      'mobility_profile_v1',jsonb_build_object(
        'network_class','gravel_access_road',
        'primary_use','property_vehicle_access',
        'transition_to','foot_small_utility_trail_network',
        'operator_confirmed',true
      )
    ),
  notes=
    regexp_replace(
      coalesce(o.notes,''),
      ' The gravel access road is intentionally maintained as a separate canonical object from the unified trail network\.[^.]*\.',
      '',
      'g'
    )
    || ' The gravel access road remains a separate canonical road object but terminates exactly at the shared transition node where the operator-confirmed trail network begins.',
  updated_at=now()
from _fw_road_trail_transition_v1 x
where o.id=x.road_id;

update farm_watch.property_operator_paths_v1 o
set
  source_context=
    jsonb_set(
      jsonb_set(
        o.source_context,
        '{placement_lock,road_connection_status}',
        to_jsonb('shared_transition_to_gravel_access_road'::text),
        true
      ),
      '{unified_network_v1}',
      coalesce(o.source_context->'unified_network_v1','{}'::jsonb)
      || jsonb_build_object(
        'gravel_access_road_included',false,
        'gravel_access_road_path_key','flat-creek-gravel-access-road',
        'gravel_access_road_relation','shared_endpoint_separate_canonical_object',
        'nearest_gravel_road_gap_m',0
      ),
      true
    )
    || jsonb_build_object(
      'road_connection','shared endpoint with separate canonical gravel access road; no geometry class absorption',
      'road_relation_v1',jsonb_build_object(
        'status','shared_endpoint_separate_canonical_objects',
        'road_path_key','flat-creek-gravel-access-road',
        'transition_point_geojson',extensions.st_asgeojson(x.transition_point,7)::jsonb,
        'geometry_relationship','touch_at_single_transition_node',
        'operator_feedback_local_date','2026-09-20'
      ),
      'mobility_profile_v1',jsonb_build_object(
        'network_class','foot_small_utility_trail_network',
        'supported_modes',jsonb_build_array('foot','small_utility_vehicle'),
        'transition_from','gravel_access_road',
        'operator_confirmed',true
      )
    ),
  notes=
    regexp_replace(
      coalesce(o.notes,''),
      ' The unified imagery \+ field-GNSS trail network is intentionally separate from the canonical gravel access road\.[^.]*\.',
      '',
      'g'
    )
    || ' The imagery + field-GNSS trail network remains a separate canonical trail object, intended for foot travel and small utility vehicles, and begins exactly at the shared transition node where the gravel access road ends.',
  updated_at=now()
from _fw_road_trail_transition_v1 x
where o.id=x.trail_id;

commit;
