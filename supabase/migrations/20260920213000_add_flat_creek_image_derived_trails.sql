begin;

with target as (
  select
    o.id,
    o.geometry,
    extensions.st_geometryn(o.geometry, 1) as g1,
    extensions.st_geometryn(o.geometry, 2) as g2,
    extensions.st_geometryn(o.geometry, 3) as g3,
    extensions.st_geometryn(o.geometry, 4) as g4,
    extensions.st_setsrid(
      extensions.st_makepoint(-84.88706510095088, 38.32365289177236),
      4326
    ) as annotated_intersection
  from farm_watch.property_operator_paths_v1 o
  join farm_watch.properties p on p.id = o.property_id
  where p.slug = 'validation-property-01'
    and o.path_key = 'flat-creek-gravel-access-road'
),
located as (
  select *,
    extensions.st_linelocatepoint(
      extensions.st_transform(g3, 3857),
      extensions.st_transform(annotated_intersection, 3857)
    ) as fraction
  from target
),
trimmed as (
  select
    id,
    g1,
    g2,
    extensions.st_linesubstring(g3, fraction, 1.0) as g3_trimmed,
    g4,
    extensions.st_closestpoint(g3, annotated_intersection) as snapped_intersection
  from located
)
update farm_watch.property_operator_paths_v1 o
set
  geometry = extensions.st_multi(
    extensions.st_collect(array[t.g1, t.g2, t.g3_trimmed, t.g4])
  ),
  source_context = jsonb_set(
    o.source_context,
    '{trail_extension}',
    jsonb_build_object(
      'change', 'north branch truncated at imagery-derived trail junction',
      'annotated_intersection_lon', -84.88706510095088,
      'annotated_intersection_lat', 38.32365289177236,
      'topology_snap_m', round(
        extensions.st_distance(
          t.snapped_intersection::extensions.geography,
          extensions.st_setsrid(
            extensions.st_makepoint(-84.88706510095088, 38.32365289177236),
            4326
          )::extensions.geography
        )::numeric,
        1
      )
    ),
    true
  ),
  notes = coalesce(o.notes, '') || ' North branch terminates at the operator-directed junction with the Phase 3 imagery-derived trail network.',
  updated_at = now()
from trimmed t
where o.id = t.id;

with property_row as (
  select id
  from farm_watch.properties
  where slug = 'validation-property-01'
  limit 1
)
insert into farm_watch.property_operator_paths_v1 (
  property_id,
  path_key,
  name,
  feature_class,
  feature_subclass,
  surface_tag,
  existence_status,
  legal_access_status,
  drivable_status,
  geometry_basis,
  geometry_precision_m,
  source_context,
  notes,
  geometry
)
select
  p.id,
  'flat-creek-phase3-image-trails',
  'Flat Creek imagery-derived trail network',
  'trail',
  'imagery_derived_trail',
  null,
  'operator_confirmed',
  'unknown',
  'not_assessed',
  'operator_guided_phase3_imagery_trace_v1',
  7.5,
  jsonb_build_object(
    'evidence_source', 'KyFromAbove Phase 3 3 in leaf-off mosaic',
    'evidence_window', '2022-2024',
    'operator_assertion', 'Marked paths are visible trail corridors to extend the existing gravel-road access network',
    'registration_method', 'same-frame selected-parcel control',
    'screen_px_per_mercator_m', 1.33667097,
    'screen_m_per_px', 0.74812727,
    'parcel_control_median_residual_px', 1.18,
    'parcel_control_mean_residual_px', 1.51,
    'parcel_control_p90_residual_px', 3.36,
    'centerline_method', 'operator annotation skeleton centerline; 17 px junction artifact pruned; simplified at 2 px',
    'segment_count', 8,
    'topology', 'branched network with one retained loop',
    'road_connection', 'trail endpoint snapped to canonical gravel-road centerline',
    'road_connection_snap_m', 11.5,
    'source_screenshot_persisted', false,
    'additional_path_inference', false
  ),
  'Operator identified these paths from Phase 3 imagery. Geometry is derived from the marked image-space trail centerlines registered against the selected parcel in the same frame. The gravel-road branch is truncated at the shared junction. Legal access, surface, and drivability are not inferred.',
  extensions.st_setsrid(
    extensions.st_geomfromgeojson(
      $geojson$
{
  "type": "MultiLineString",
  "coordinates": [
    [[-84.8859024473,38.3242433984],[-84.8857008310,38.3242064919],[-84.8855462586,38.3242012195],[-84.8852035109,38.3241115893]],
    [[-84.8859024473,38.3242433984],[-84.8859763732,38.3243383008],[-84.8861847100,38.3244173861],[-84.8862989592,38.3245281053],[-84.8866753095,38.3247706324],[-84.8868567642,38.3250289757],[-84.8870651010,38.3251555109],[-84.8872465556,38.3253242240]],
    [[-84.8859024473,38.3242433984],[-84.8859494910,38.3242117643],[-84.8862855181,38.3242170366],[-84.8864804138,38.3241748577],[-84.8865543398,38.3241432235],[-84.8866685890,38.3240799551],[-84.8869575723,38.3238532428],[-84.8871638180,38.3237247950]],
    [[-84.8852035109,38.3241115893],[-84.8851228644,38.3240219590],[-84.8850018947,38.3239639628],[-84.8849548509,38.3238848771],[-84.8848069990,38.3235316264],[-84.8847733963,38.3233945436],[-84.8846255444,38.3231256496],[-84.8846121033,38.3230360181]],
    [[-84.8852035109,38.3241115893],[-84.8851564671,38.3241484959],[-84.8843903254,38.3241959472],[-84.8842021502,38.3241906748],[-84.8840005340,38.3241484959],[-84.8839534902,38.3241168617]],
    [[-84.8846121033,38.3230360181],[-84.8844373692,38.3230412905],[-84.8843298405,38.3231520118],[-84.8842827967,38.3232785502],[-84.8842424735,38.3235632609],[-84.8840542983,38.3238532428],[-84.8839803724,38.3240061419],[-84.8839534902,38.3241168617]],
    [[-84.8846121033,38.3230360181],[-84.8846255444,38.3227987576]],
    [[-84.8839534902,38.3241168617],[-84.8838056383,38.3241010446],[-84.8835636988,38.3240061419],[-84.8834292879,38.3239745076],[-84.8833889647,38.3239797800]]
  ]
}
      $geojson$
    ),
    4326
  )
from property_row p
on conflict (property_id, path_key) do update
set
  name = excluded.name,
  feature_class = excluded.feature_class,
  feature_subclass = excluded.feature_subclass,
  surface_tag = excluded.surface_tag,
  existence_status = excluded.existence_status,
  legal_access_status = excluded.legal_access_status,
  drivable_status = excluded.drivable_status,
  geometry_basis = excluded.geometry_basis,
  geometry_precision_m = excluded.geometry_precision_m,
  source_context = excluded.source_context,
  notes = excluded.notes,
  geometry = excluded.geometry,
  active = true,
  updated_at = now();

commit;
