begin;

-- Restore the source-registered gravel-road geometry and truncate only its
-- north branch at the operator-marked trail junction from the same source frame.
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
      [-84.8871013182267,38.324818097105265],
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
  source_context = jsonb_set(
    o.source_context,
    '{trail_extension}',
    jsonb_build_object(
      'change', 'north branch truncated at corrected imagery-derived trail junction',
      'junction_lon', -84.8871013182267,
      'junction_lat', 38.324818097105265,
      'junction_source', 'operator annotation on same Phase 3 frame',
      'annotation_to_road_snap_m', 1.9
    ),
    true
  ),
  notes = regexp_replace(
    coalesce(o.notes, ''),
    ' North branch terminates at the operator-directed junction with the Phase 3 imagery-derived trail network\.$',
    ''
  ) || ' North branch terminates at the corrected operator-marked Phase 3 imagery-derived trail junction.',
  updated_at = now()
from farm_watch.properties p
where o.property_id = p.id
  and p.slug = 'validation-property-01'
  and o.path_key = 'flat-creek-gravel-access-road';

-- Replace the prior trail geometry rather than transforming it again.
-- This geometry is derived directly from the original annotated screenshot.
update farm_watch.property_operator_paths_v1 o
set
  geometry = extensions.st_setsrid(
    extensions.st_geomfromgeojson(
      $geojson$
{
  "type": "MultiLineString",
  "coordinates": [
    [
      [-84.88744954001376,38.327717519361514],
      [-84.88716534507573,38.32746670666089],
      [-84.88677457703592,38.32722518249926],
      [-84.8864666991864,38.32678857908761],
      [-84.88631276026163,38.32666781597752],
      [-84.8860522482351,38.32652847367736],
      [-84.8855904314608,38.32614760335681],
      [-84.88525887069977,38.32602683917876],
      [-84.88512466753458,38.325853433853226]
    ],
    [
      [-84.88512466753458,38.325853433853226],
      [-84.88474968810246,38.32577602062752],
      [-84.88447733462019,38.32576673103488],
      [-84.88396815202287,38.32561809739073],
      [-84.88384184316152,38.32560571123997]
    ],
    [
      [-84.88512466753458,38.325853433853226],
      [-84.885199663421,38.32579459980922],
      [-84.88574437038557,38.32579459980922],
      [-84.88596935804483,38.32575744144106],
      [-84.88621802861562,38.325673835043],
      [-84.88643117481915,38.32556235969561],
      [-84.88695219887221,38.32515361528828],
      [-84.8871013182267,38.324818097105265]
    ],
    [
      [-84.88166794924318,38.32560880777786],
      [-84.88175379979737,38.325673835043],
      [-84.88199062891239,38.32572957265242],
      [-84.8824050798637,38.32575744144106],
      [-84.8828905795495,38.32574815184603],
      [-84.88328134758929,38.32569241425091],
      [-84.88375500581935,38.325673835043],
      [-84.88384184316152,38.32560571123997]
    ],
    [
      [-84.88166794924318,38.32560880777786],
      [-84.88141039758058,38.32559022854853],
      [-84.88100778808504,38.32543230490691],
      [-84.88068806877975,38.32535798778008]
    ],
    [
      [-84.88384184316152,38.32560571123997],
      [-84.88369579854059,38.32544159454243],
      [-84.88350633524857,38.32534869813385],
      [-84.88339976214681,38.3251629049595],
      [-84.88304451847426,38.324215352362515],
      [-84.882866896638,38.3239273682365],
      [-84.88282841190681,38.323713701855276]
    ],
    [
      [-84.88166794924318,38.32560880777786],
      [-84.8817182754301,38.32539514635301],
      [-84.88182484853189,38.32518148429836],
      [-84.88215640929292,38.32467055074429],
      [-84.88225114093892,38.32409458496511],
      [-84.88231034821769,38.32394594789207],
      [-84.88241692131945,38.32379731051423],
      [-84.88253533587695,38.323713701855276],
      [-84.88282841190681,38.323713701855276]
    ],
    [
      [-84.88282841190681,38.323713701855276],
      [-84.88283137227074,38.32330494702325]
    ]
  ]
}
      $geojson$
    ),
    4326
  ),
  geometry_basis = 'operator_guided_phase3_same_frame_road_control_v2',
  geometry_precision_m = 7.5,
  source_context = jsonb_build_object(
    'evidence_source', 'KyFromAbove Phase 3 3 in leaf-off mosaic',
    'evidence_window', '2022-2024',
    'operator_assertion', 'Marked paths are visible trail corridors extending the existing gravel-road access network',
    'registration_method', 'same-frame canonical gravel-road control',
    'screen_px_per_mercator_m', 0.758619,
    'screen_m_per_px', 1.318185,
    'prior_bad_screen_px_per_mercator_m', 1.336671,
    'prior_geometry_discarded', true,
    'centerline_method', 'operator annotation centerline skeletonized and simplified at 2 px',
    'segment_count', 8,
    'topology', 'branched network with one retained loop',
    'road_connection', 'annotation endpoint snapped to canonical gravel-road centerline',
    'road_connection_snap_m', 1.9,
    'source_screenshot_persisted', false,
    'additional_path_inference', false,
    'canonical_uses_manual_qa_transform', false
  ),
  notes = 'Operator identified these paths from Phase 3 imagery. Geometry was rebuilt directly from the original annotated screenshot using the already-correct canonical gravel road visible in that same frame as the geospatial control. The prior trail geometry was discarded rather than transformed. Legal access, surface, and drivability are not inferred.',
  updated_at = now()
from farm_watch.properties p
where o.property_id = p.id
  and p.slug = 'validation-property-01'
  and o.path_key = 'flat-creek-phase3-image-trails';

commit;
