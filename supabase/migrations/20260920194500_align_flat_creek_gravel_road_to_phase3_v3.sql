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
            [-84.8933273, 38.3234601],
            [-84.8931480, 38.3235304],
            [-84.8929463, 38.3235480],
            [-84.8924531, 38.3234777],
            [-84.8918367, 38.3234952],
            [-84.8912539, 38.3234337],
            [-84.8910858, 38.3233721],
            [-84.8907496, 38.3233457],
            [-84.8904134, 38.3232754],
            [-84.8898530, 38.3231083],
            [-84.8895504, 38.3230995],
            [-84.8890573, 38.3229588],
            [-84.8885529, 38.3229060],
            [-84.8882839, 38.3227478],
            [-84.8881270, 38.3227214]
          ],
          [
            [-84.8918479, 38.3234952],
            [-84.8919040, 38.3235920],
            [-84.8923747, 38.3237942]
          ],
          [
            [-84.8881270, 38.3227214],
            [-84.8880934, 38.3227829],
            [-84.8881270, 38.3229324],
            [-84.8881158, 38.3230995],
            [-84.8879813, 38.3233369],
            [-84.8880598, 38.3237062],
            [-84.8879925, 38.3240315],
            [-84.8880149, 38.3243568],
            [-84.8879028, 38.3247085]
          ],
          [
            [-84.8881270, 38.3227214],
            [-84.8880934, 38.3225983],
            [-84.8881271, 38.3223169],
            [-84.8880710, 38.3222114],
            [-84.8879253, 38.3221323],
            [-84.8876115, 38.3220707],
            [-84.8874434, 38.3219388],
            [-84.8874322, 38.3216838],
            [-84.8875443, 38.3214728],
            [-84.8876788, 38.3213321]
          ]
        ]
      }
      $geojson$
    ),
    4326
  ),
  geometry_basis = 'operator_confirmed_phase3_render_registration_v3',
  geometry_precision_m = 5.0,
  source_context = jsonb_set(
    o.source_context,
    '{geometry_refit}',
    jsonb_build_object(
      'method', 'operator_annotation_registered_to_matching_unannotated_phase3_render',
      'reference_imagery', 'KyFromAbove Phase 3 3 in leaf-off mosaic',
      'reference_hillshade', 'KyFromAbove Phase 3 shaded relief',
      'world_calibration', 'selected parcel geometry in the same Leaflet/Web Mercator render',
      'registration', 'same-view image registration',
      'parcel_control_residual_px', 1.5,
      'additional_path_inference', false,
      'neighboring_house_spur', 'operator confirmed'
    ),
    true
  ),
  notes = 'Operator-confirmed gravel road centerline aligned to the same Farm Watch Phase 3 imagery/shaded-relief render used to identify the road. Includes the early branch serving the neighboring parcel with a house plus the north and south branches. No additional access paths were inferred.',
  updated_at = now()
from farm_watch.properties p
where o.property_id = p.id
  and p.slug = 'validation-property-01'
  and o.path_key = 'flat-creek-gravel-access-road';

commit;
