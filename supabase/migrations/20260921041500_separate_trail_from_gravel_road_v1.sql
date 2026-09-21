begin;

create temporary table _fw_trail_road_separation_v1 on commit drop as
with property_row as (
  select id
  from farm_watch.properties
  where slug='validation-property-01'
  limit 1
), restored_road as (
  select extensions.st_setsrid(
    extensions.st_geomfromgeojson(
      $geojson$
      {
        "type": "MultiLineString",
        "coordinates": [
          [[-84.895713174,38.324058674],[-84.895423111,38.324172453],[-84.895096790,38.324200898],[-84.894299115,38.324087119],[-84.893356409,38.324087119],[-84.893302022,38.324115563],[-84.892359316,38.324016006],[-84.892178027,38.323973339],[-84.892087382,38.323916449],[-84.891543513,38.323873781],[-84.890999644,38.323760001],[-84.890093196,38.323489773],[-84.889603714,38.323475550],[-84.889168619,38.323375992],[-84.888806039,38.323247989],[-84.887990236,38.323162653],[-84.887808946,38.323091540],[-84.887555141,38.322906645],[-84.887301335,38.322863977]],
          [[-84.894172213,38.324599125],[-84.893972794,38.324528013],[-84.893809633,38.324414234],[-84.893410796,38.324272010],[-84.893320151,38.324115563]],
          [[-84.886938756,38.326078235],[-84.887120046,38.325509350],[-84.887083788,38.324983128],[-84.887120046,38.324641792],[-84.887192561,38.324456902],[-84.887174433,38.324243565],[-84.887065659,38.324030229],[-84.887065659,38.323859559],[-84.887210690,38.323660444],[-84.887283206,38.323475550],[-84.887301335,38.323205321],[-84.887246948,38.322963536],[-84.887301335,38.322863977]],
          [[-84.886576177,38.320616756],[-84.886358629,38.320844326],[-84.886177340,38.321185679],[-84.886159211,38.321441693],[-84.886195468,38.321598146],[-84.886467403,38.321811490],[-84.886975014,38.321911050],[-84.887101917,38.321953719],[-84.887210690,38.322039056],[-84.887301335,38.322209730],[-84.887246948,38.322451518],[-84.887246948,38.322664859],[-84.887301335,38.322863977]]
        ]
      }
      $geojson$
    ),
    4326
  ) as geometry
), trail as (
  select o.geometry
  from farm_watch.property_operator_paths_v1 o
  join property_row p on p.id=o.property_id
  where o.path_key='flat-creek-phase3-image-trails'
    and o.active
  limit 1
)
select
  (select id from property_row) as property_id,
  r.geometry as restored_road_geometry,
  round(
    extensions.st_distance(
      r.geometry::extensions.geography,
      t.geometry::extensions.geography
    )::numeric,
    2
  ) as gap_m,
  extensions.st_closestpoint(r.geometry,t.geometry) as road_point,
  extensions.st_closestpoint(t.geometry,r.geometry) as trail_point
from restored_road r
cross join trail t;

update farm_watch.property_operator_paths_v1 o
set
  geometry=x.restored_road_geometry,
  source_context=
    (o.source_context - 'trail_extension')
    || jsonb_build_object(
      'trail_separation_v1',
      jsonb_build_object(
        'status','separate_canonical_objects',
        'trail_path_key','flat-creek-phase3-image-trails',
        'restored_geometry_source','20260920204500_source_register_flat_creek_road_v6.sql',
        'removed_connection_source','20260920234500_connect_flat_creek_trail_to_gravel_road.sql',
        'nearest_gap_m',x.gap_m,
        'road_nearest_point_geojson',extensions.st_asgeojson(x.road_point,7)::jsonb,
        'trail_nearest_point_geojson',extensions.st_asgeojson(x.trail_point,7)::jsonb,
        'operator_feedback_local_date','2026-09-20'
      )
    ),
  notes=
    regexp_replace(
      regexp_replace(
        coalesce(o.notes,''),
        ' North branch is restored from the source-registered gravel-road geometry and terminates exactly at the final canonical imagery-derived trail junction\.',
        '',
        'g'
      ),
      ' Final canonical trail geometry is topologically connected to the gravel-road north branch\.',
      '',
      'g'
    )
    || ' The gravel access road is intentionally maintained as a separate canonical object from the unified trail network. Its source-registered v6 geometry is restored; the prior 2.88 m road-to-trail snap is removed.',
  updated_at=now()
from _fw_trail_road_separation_v1 x
where o.property_id=x.property_id
  and o.path_key='flat-creek-gravel-access-road'
  and o.active;

update farm_watch.property_operator_paths_v1 o
set
  source_context=
    jsonb_set(
      jsonb_set(
        o.source_context,
        '{placement_lock,road_connection_status}',
        to_jsonb('separate_from_gravel_access_road'::text),
        true
      ),
      '{unified_network_v1}',
      coalesce(o.source_context->'unified_network_v1','{}'::jsonb)
      || jsonb_build_object(
        'gravel_access_road_included',false,
        'gravel_access_road_path_key','flat-creek-gravel-access-road',
        'gravel_access_road_relation','separate_canonical_object',
        'nearest_gravel_road_gap_m',x.gap_m
      ),
      true
    )
    || jsonb_build_object(
      'road_connection','separate canonical gravel access road; no trail geometry absorbed into road or vice versa',
      'road_relation_v1',jsonb_build_object(
        'status','separate_canonical_objects',
        'road_path_key','flat-creek-gravel-access-road',
        'nearest_gap_m',x.gap_m,
        'road_nearest_point_geojson',extensions.st_asgeojson(x.road_point,7)::jsonb,
        'trail_nearest_point_geojson',extensions.st_asgeojson(x.trail_point,7)::jsonb,
        'operator_feedback_local_date','2026-09-20'
      )
    ),
  notes=
    regexp_replace(
      coalesce(o.notes,''),
      ' Final canonical trail geometry is topologically connected to the gravel-road north branch\.',
      '',
      'g'
    )
    || ' The unified imagery + field-GNSS trail network is intentionally separate from the canonical gravel access road. The road-side snap has been removed; the nearest road/trail gap is preserved from the source-registered road geometry.',
  updated_at=now()
from _fw_trail_road_separation_v1 x
where o.property_id=x.property_id
  and o.path_key='flat-creek-phase3-image-trails'
  and o.active;

commit;
