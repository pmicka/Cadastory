begin;

with target as (
  select
    o.id,
    extensions.st_transform(o.geometry, 3857) as g3857
  from farm_watch.property_operator_paths_v1 o
  join farm_watch.properties p on p.id = o.property_id
  where p.slug = 'validation-property-01'
    and o.path_key = 'flat-creek-phase3-image-trails'
),
centered as (
  select
    id,
    g3857,
    (extensions.st_xmin(extensions.box3d(g3857)) + extensions.st_xmax(extensions.box3d(g3857))) / 2.0 as cx,
    (extensions.st_ymin(extensions.box3d(g3857)) + extensions.st_ymax(extensions.box3d(g3857))) / 2.0 as cy
  from target
),
scaled as (
  select
    id,
    extensions.st_transform(
      extensions.st_translate(
        extensions.st_scale(
          extensions.st_translate(g3857, -cx, -cy),
          0.40,
          0.40
        ),
        cx,
        cy
      ),
      4326
    ) as geometry
  from centered
)
update farm_watch.property_operator_paths_v1 o
set
  geometry = s.geometry,
  geometry_basis = 'operator_guided_phase3_scale_locked_40_v3',
  source_context = jsonb_set(
    o.source_context,
    '{scale_lock}',
    jsonb_build_object(
      'canonical_scale', 0.40,
      'scale_percent', 40.0,
      'scale_origin', 'EPSG:3857 geometry bounding-box center',
      'position_adjustment_applied', false,
      'basis', 'operator visual QA scale-only pass',
      'manual_qa_position_used', false
    ),
    true
  ),
  notes = regexp_replace(
    coalesce(o.notes, ''),
    ' Canonical scale locked at 40% during operator scale-only QA\.$',
    ''
  ) || ' Canonical scale locked at 40% during operator scale-only QA; placement remains intentionally uncorrected pending pixel-nudge QA.',
  updated_at = now()
from scaled s
where o.id = s.id;

commit;
