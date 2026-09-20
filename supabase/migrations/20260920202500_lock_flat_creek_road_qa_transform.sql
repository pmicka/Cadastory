begin;

with target as (
  select
    o.id,
    extensions.st_transform(o.geometry, 3857) as g3857
  from farm_watch.property_operator_paths_v1 o
  join farm_watch.properties p on p.id = o.property_id
  where p.slug = 'validation-property-01'
    and o.path_key = 'flat-creek-gravel-access-road'
),
centered as (
  select
    id,
    g3857,
    (extensions.st_xmin(extensions.box3d(g3857)) + extensions.st_xmax(extensions.box3d(g3857))) / 2.0 as cx,
    (extensions.st_ymin(extensions.box3d(g3857)) + extensions.st_ymax(extensions.box3d(g3857))) / 2.0 as cy
  from target
),
adjusted as (
  select
    id,
    extensions.st_transform(
      extensions.st_translate(
        extensions.st_scale(
          extensions.st_translate(g3857, -cx, -cy),
          1.43,
          1.43
        ),
        cx - 131.49,
        cy - 189.33
      ),
      4326
    ) as geometry
  from centered
)
update farm_watch.property_operator_paths_v1 o
set
  geometry = a.geometry,
  geometry_basis = 'operator_qa_locked_web_mercator_transform_v5',
  geometry_precision_m = 5.0,
  source_context = jsonb_set(
    o.source_context,
    '{geometry_refit}',
    jsonb_build_object(
      'method', 'operator_visual_qa_locked_web_mercator_transform',
      'source_geometry_basis', 'operator_annotation_parcel_control_reprojection_v4',
      'scale', 1.43,
      'east_m', -131.49,
      'north_m', -189.33,
      'qa_zoom', 15,
      'qa_screen_pixel_m', 4.78,
      'reference_imagery', 'KyFromAbove Phase 3 3 in leaf-off mosaic',
      'reference_hillshade', 'KyFromAbove Phase 3 shaded relief',
      'additional_path_inference', false,
      'neighboring_house_spur', 'operator confirmed'
    ),
    true
  ),
  notes = 'Operator-confirmed gravel road. Canonical geometry incorporates the operator-verified QA display transform: 143.00% scale about the road bounding-box center, 131.49 m west, and 189.33 m south in EPSG:3857. Includes the neighboring-house spur plus north and south branches. No other paths were inferred.',
  updated_at = now()
from adjusted a
where o.id = a.id;

commit;
