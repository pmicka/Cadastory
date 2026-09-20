begin;

update farm_watch.property_operator_paths_v1 o
set
  geometry = extensions.st_setsrid(
    extensions.st_geomfromgeojson(
      $geojson$
      {
        "type": "MultiLineString",
        "coordinates": [
          [
            [-84.893029966,38.325172682],
            [-84.892719719,38.325270038],
            [-84.892136454,38.325192154],
            [-84.891379450,38.325211625],
            [-84.891168482,38.325172682],
            [-84.890907874,38.325172682],
            [-84.890610037,38.325114269],
            [-84.890547987,38.325075326],
            [-84.890175690,38.325046119],
            [-84.889790984,38.324968234],
            [-84.889244948,38.324792993],
            [-84.888847832,38.324773521],
            [-84.888438305,38.324676164],
            [-84.888276976,38.324608015],
            [-84.887743351,38.324559336],
            [-84.887668892,38.324539865],
            [-84.887445513,38.324384094],
            [-84.887271775,38.324354886]
          ],
          [
            [-84.891404270,38.325211625],
            [-84.891466319,38.325328452],
            [-84.891726927,38.325416072],
            [-84.891950305,38.325532899],
            [-84.891950305,38.325581577]
          ],
          [
            [-84.887271775,38.324354886],
            [-84.887222135,38.324452244],
            [-84.887271775,38.324724843],
            [-84.887234545,38.324851406],
            [-84.887110446,38.325036384],
            [-84.887110446,38.325153211],
            [-84.887197316,38.325347923],
            [-84.887122856,38.325805494],
            [-84.887147676,38.326155972],
            [-84.887011167,38.326603803]
          ],
          [
            [-84.887284185,38.324354886],
            [-84.887234545,38.324218586],
            [-84.887259365,38.323848627],
            [-84.887085627,38.323712326],
            [-84.886688510,38.323634439],
            [-84.886502362,38.323459194],
            [-84.886514771,38.323176854],
            [-84.886651280,38.322943193],
            [-84.886775379,38.322816626]
          ]
        ]
      }
      $geojson$
    ),
    4326
  ),
  geometry_basis = 'operator_annotation_parcel_control_reprojection_v4',
  geometry_precision_m = 5.0,
  source_context = jsonb_set(
    o.source_context,
    '{geometry_refit}',
    jsonb_build_object(
      'method', 'operator_annotation_centerline_pixels_to_web_mercator_via_selected_parcel_control',
      'reference_imagery', 'KyFromAbove Phase 3 3 in leaf-off mosaic',
      'reference_hillshade', 'KyFromAbove Phase 3 shaded relief',
      'world_control', 'farm_watch.properties.boundary selected-parcel geometry',
      'screen_control', 'selected parcel outline from the same Farm Watch render',
      'screen_px_per_mercator_m', 0.72387021,
      'operator_trace_centerline', 'skeletonized and simplified at 2 px tolerance',
      'additional_path_inference', false,
      'neighboring_house_spur', 'operator confirmed'
    ),
    true
  ),
  notes = 'Operator-confirmed gravel road. Geometry is the centerline of the operator annotation transformed into world coordinates using the selected parcel boundary visible in the same Phase 3 Farm Watch render as the geospatial control. Includes the neighboring-house spur plus north and south branches. No other paths were inferred.',
  updated_at = now()
from farm_watch.properties p
where o.property_id = p.id
  and p.slug = 'validation-property-01'
  and o.path_key = 'flat-creek-gravel-access-road';

commit;
