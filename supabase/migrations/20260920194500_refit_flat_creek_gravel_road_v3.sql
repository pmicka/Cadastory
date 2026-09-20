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
            [-84.895667312,38.324110024],
            [-84.895541797,38.324081890],
            [-84.895254905,38.324180359],
            [-84.894878359,38.324180359],
            [-84.894286644,38.324081890],
            [-84.893121145,38.324095957],
            [-84.892368054,38.324025622],
            [-84.892009439,38.323913086],
            [-84.891561170,38.323884952],
            [-84.890951524,38.323758349],
            [-84.890288086,38.323533277],
            [-84.890001194,38.323477008],
            [-84.889570856,38.323477008],
            [-84.888746042,38.323237868],
            [-84.888279842,38.323223800],
            [-84.887939158,38.323153465],
            [-84.887490889,38.322886189],
            [-84.887347443,38.322872121],
            [-84.887293651,38.322956525]
          ],
          [
            [-84.894107337,38.324644566],
            [-84.893766652,38.324419496],
            [-84.893354245,38.324278827],
            [-84.893157007,38.324095957],
            [-84.892870115,38.324053756]
          ],
          [
            [-84.887293651,38.322956525],
            [-84.887239858,38.322984659],
            [-84.887293651,38.323420740],
            [-84.887060551,38.323856818],
            [-84.887078481,38.324095957],
            [-84.887168135,38.324250693],
            [-84.887168135,38.324517964],
            [-84.887078481,38.324925903],
            [-84.887096412,38.325544839],
            [-84.886917105,38.326135637]
          ],
          [
            [-84.887293651,38.322956525],
            [-84.887239858,38.322717382],
            [-84.887275720,38.322140624],
            [-84.887024689,38.321943681],
            [-84.886450905,38.321831142],
            [-84.886181944,38.321577928],
            [-84.886199875,38.321155903],
            [-84.886576420,38.320593200]
          ]
        ]
      }
      $geojson$
    ),
    4326
  ),
  geometry_basis = 'operator_annotation_property_boundary_georeferenced_v3',
  geometry_precision_m = 2.0,
  source_context = o.source_context || jsonb_build_object(
    'geometry_refit_v3', jsonb_build_object(
      'method', 'operator_annotation_pixel_centerline_georeferenced_from_rendered_property_boundary',
      'reference_screenshot', 'Farm Watch Phase 3 annotated mobile map',
      'reference_boundary', 'farm_watch.properties.boundary',
      'projection', 'Leaflet EPSG:3857 / Web Mercator',
      'validation', jsonb_build_array(
        'projected property boundary independently overlays annotated screenshot',
        'same property boundary independently overlays standard fitBounds screenshot at zoom 16.75'
      ),
      'additional_path_inference', false
    )
  ),
  notes = 'Operator confirmed the gravel road and the early branch serving the neighboring parcel with a house. Geometry is the centerline of the operator annotation georeferenced against the same rendered parcel boundary visible in the source Farm Watch map. No candidate access paths were inferred.',
  updated_at = now()
from farm_watch.properties p
where o.property_id = p.id
  and p.slug = 'validation-property-01'
  and o.path_key = 'flat-creek-gravel-access-road';

commit;
