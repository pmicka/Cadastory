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
            [-84.895713174,38.324058674],
            [-84.895423111,38.324172453],
            [-84.895096790,38.324200898],
            [-84.894299115,38.324087119],
            [-84.893356409,38.324087119],
            [-84.893302022,38.324115563],
            [-84.892359316,38.324016006],
            [-84.892178027,38.323973339],
            [-84.892087382,38.323916449],
            [-84.891543513,38.323873781],
            [-84.890999644,38.323760001],
            [-84.890093196,38.323489773],
            [-84.889603714,38.323475550],
            [-84.889168619,38.323375992],
            [-84.888806039,38.323247989],
            [-84.887990236,38.323162653],
            [-84.887808946,38.323091540],
            [-84.887555141,38.322906645],
            [-84.887301335,38.322863977]
          ],
          [
            [-84.894172213,38.324599125],
            [-84.893972794,38.324528013],
            [-84.893809633,38.324414234],
            [-84.893410796,38.324272010],
            [-84.893320151,38.324115563]
          ],
          [
            [-84.886938756,38.326078235],
            [-84.887120046,38.325509350],
            [-84.887083788,38.324983128],
            [-84.887120046,38.324641792],
            [-84.887192561,38.324456902],
            [-84.887174433,38.324243565],
            [-84.887065659,38.324030229],
            [-84.887065659,38.323859559],
            [-84.887210690,38.323660444],
            [-84.887283206,38.323475550],
            [-84.887301335,38.323205321],
            [-84.887246948,38.322963536],
            [-84.887301335,38.322863977]
          ],
          [
            [-84.886576177,38.320616756],
            [-84.886358629,38.320844326],
            [-84.886177340,38.321185679],
            [-84.886159211,38.321441693],
            [-84.886195468,38.321598146],
            [-84.886467403,38.321811490],
            [-84.886975014,38.321911050],
            [-84.887101917,38.321953719],
            [-84.887210690,38.322039056],
            [-84.887301335,38.322209730],
            [-84.887246948,38.322451518],
            [-84.887246948,38.322664859],
            [-84.887301335,38.322863977]
          ]
        ]
      }
      $geojson$
    ),
    4326
  ),
  geometry_basis = 'operator_annotation_same_frame_parcel_control_v6',
  geometry_precision_m = 5.0,
  source_context = jsonb_set(
    o.source_context,
    '{geometry_refit}',
    jsonb_build_object(
      'method', 'same_frame_operator_annotation_to_world_via_selected_parcel_control',
      'reference_imagery', 'KyFromAbove Phase 3 3 in leaf-off mosaic',
      'reference_hillshade', 'KyFromAbove Phase 3 shaded relief',
      'world_control', 'farm_watch.properties.boundary selected-parcel geometry',
      'screen_control', 'selected parcel outline visible in the same annotated Farm Watch frame',
      'screen_px_per_mercator_m', 0.495513863,
      'prior_v4_screen_px_per_mercator_m', 0.72387021,
      'prior_scale_error_percent', 46.08,
      'visible_parcel_control_median_residual_px', 0.0,
      'visible_parcel_control_mean_residual_px', 0.99,
      'visible_parcel_control_p90_residual_px', 2.83,
      'operator_trace_method', 'red annotation centerline skeletonized and simplified at 1.5 px tolerance',
      'canonical_uses_manual_qa_transform', false,
      'additional_path_inference', false,
      'neighboring_house_spur', 'operator confirmed'
    ),
    true
  ),
  notes = 'Operator-confirmed gravel road. Canonical geometry is derived directly from the original annotated Farm Watch frame by registering the selected parcel outline visible in that same frame to the stored parcel geometry, then transforming the annotation centerline into EPSG:4326. The prior QA scale/translation is not applied. Includes the neighboring-house spur plus north and south branches. No other paths were inferred.',
  updated_at = now()
from farm_watch.properties p
where o.property_id = p.id
  and p.slug = 'validation-property-01'
  and o.path_key = 'flat-creek-gravel-access-road';

commit;
