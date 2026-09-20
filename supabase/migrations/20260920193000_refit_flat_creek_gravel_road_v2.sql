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
            [-84.8888186,38.3240313],
            [-84.8886145,38.3241114],
            [-84.8883848,38.3241314],
            [-84.8879000,38.3240513],
            [-84.8871217,38.3240713],
            [-84.8865221,38.3240113],
            [-84.8862669,38.3239312],
            [-84.8858841,38.3239012],
            [-84.8854886,38.3238211],
            [-84.8849272,38.3236409],
            [-84.8845189,38.3236209],
            [-84.8839320,38.3234508],
            [-84.8833834,38.3234007],
            [-84.8830772,38.3232205],
            [-84.8828986,38.3231905]
          ],
          [
            [-84.8877214,38.3244417],
            [-84.8877086,38.3244017],
            [-84.8874790,38.3242815],
            [-84.8872110,38.3241915],
            [-84.8871345,38.3240713]
          ],
          [
            [-84.8828986,38.3231905],
            [-84.8828475,38.3232906],
            [-84.8828986,38.3235709],
            [-84.8828603,38.3237010],
            [-84.8827327,38.3238912],
            [-84.8827327,38.3240113],
            [-84.8828092,38.3241614],
            [-84.8828220,38.3243016],
            [-84.8827454,38.3246819],
            [-84.8827582,38.3251424],
            [-84.8826561,38.3253525],
            [-84.8826434,38.3255027]
          ],
          [
            [-84.8828986,38.3231905],
            [-84.8828603,38.3230504],
            [-84.8828858,38.3226700],
            [-84.8827072,38.3225299],
            [-84.8822989,38.3224498],
            [-84.8821075,38.3222696],
            [-84.8821203,38.3219793],
            [-84.8822606,38.3217391],
            [-84.8823882,38.3216090]
          ]
        ]
      }
      $geojson$
    ),
    4326
  ),
  geometry_basis = 'operator_annotation_leaflet_georeferenced_v2',
  geometry_precision_m = 2.0,
  source_context = o.source_context || jsonb_build_object(
    'geometry_refit', jsonb_build_object(
      'method', 'operator_annotation_pixel_centerline_to_leaflet_web_mercator',
      'reference_map', 'Farm Watch Phase 3 map',
      'leaflet_zoom', 16.75,
      'map_viewport_px', jsonb_build_array(688, 699),
      'fit_padding_px', 26,
      'centerline_simplification_tolerance_px', 2,
      'approx_ground_resolution_m_per_px', 1.11,
      'additional_path_inference', false
    )
  ),
  notes = 'Operator confirmed the gravel road and the early branch serving the neighboring parcel with a house. Geometry was refit from the operator annotation by recovering the exact Leaflet/Web Mercator map transform and tracing the annotation centerline. No additional access paths were inferred.',
  updated_at = now()
from farm_watch.properties p
where o.property_id = p.id
  and p.slug = 'validation-property-01'
  and o.path_key = 'flat-creek-gravel-access-road';

commit;
