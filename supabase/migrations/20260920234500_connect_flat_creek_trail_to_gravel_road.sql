begin;

with property_row as (
  select id
  from farm_watch.properties
  where slug = 'validation-property-01'
  limit 1
),
road as (
  select
    o.id,
    extensions.st_geometryn(o.geometry, 1) as g1,
    extensions.st_geometryn(o.geometry, 2) as g2,
    extensions.st_geometryn(o.geometry, 4) as g4
  from farm_watch.property_operator_paths_v1 o
  join property_row p on p.id = o.property_id
  where o.path_key = 'flat-creek-gravel-access-road'
),
full_branch as (
  select extensions.st_setsrid(
    extensions.st_geomfromgeojson(
      '{"type":"LineString","coordinates":[[-84.886938756,38.326078235],[-84.887120046,38.325509350],[-84.887083788,38.324983128],[-84.887120046,38.324641792],[-84.887192561,38.324456902],[-84.887174433,38.324243565],[-84.887065659,38.324030229],[-84.887065659,38.323859559],[-84.887210690,38.323660444],[-84.887283206,38.323475550],[-84.887301335,38.323205321],[-84.887246948,38.322963536],[-84.887301335,38.322863977]]}'
    ),
    4326
  ) as geom
),
trail as (
  select o.geometry
  from farm_watch.property_operator_paths_v1 o
  join property_row p on p.id = o.property_id
  where o.path_key = 'flat-creek-phase3-image-trails'
),
junction as (
  select
    fb.geom as full_geom,
    extensions.st_closestpoint(fb.geom, t.geometry) as road_point,
    extensions.st_closestpoint(t.geometry, fb.geom) as trail_point
  from full_branch fb
  cross join trail t
),
rebuilt_branch as (
  select
    extensions.st_addpoint(
      extensions.st_linesubstring(
        j.full_geom,
        extensions.st_linelocatepoint(j.full_geom, j.road_point),
        1.0
      ),
      j.trail_point,
      0
    ) as geom,
    round(
      extensions.st_distance(
        j.road_point::extensions.geography,
        j.trail_point::extensions.geography
      )::numeric,
      2
    ) as snap_m,
    j.trail_point
  from junction j
),
updated as (
  select
    r.id,
    extensions.st_multi(
      extensions.st_collect(array[r.g1, r.g2, rb.geom, r.g4])
    ) as geometry,
    rb.snap_m,
    rb.trail_point
  from road r
  cross join rebuilt_branch rb
)
update farm_watch.property_operator_paths_v1 o
set
  geometry = u.geometry,
  source_context = jsonb_set(
    o.source_context,
    '{trail_extension}',
    jsonb_build_object(
      'change', 'north branch restored and terminated at final imagery-derived trail junction',
      'junction_lon', extensions.st_x(u.trail_point),
      'junction_lat', extensions.st_y(u.trail_point),
      'junction_source', 'final canonical imagery-derived trail geometry',
      'road_to_trail_snap_m', u.snap_m,
      'connection_method', 'restore original gravel-road branch then prepend short connector to trail endpoint'
    ),
    true
  ),
  notes = coalesce(o.notes, '') ||
    ' North branch is restored from the source-registered gravel-road geometry and terminates exactly at the final canonical imagery-derived trail junction.',
  updated_at = now()
from updated u
where o.id = u.id;

update farm_watch.property_operator_paths_v1 o
set
  source_context = jsonb_set(
    o.source_context,
    '{placement_lock,road_connection_status}',
    to_jsonb('connected_to_gravel_road'::text),
    true
  ),
  notes = coalesce(o.notes, '') ||
    ' Final canonical trail geometry is topologically connected to the gravel-road north branch.',
  updated_at = now()
where o.property_id = (
    select id
    from farm_watch.properties
    where slug = 'validation-property-01'
    limit 1
  )
  and o.path_key = 'flat-creek-phase3-image-trails';

commit;
