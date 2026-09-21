begin;

with candidate as (
  select
    o.id,
    extensions.st_transform(
      extensions.st_setsrid(
        extensions.st_geomfromgeojson((o.source_context->'presentation_v1'->'geometry_geojson')::text),
        4326
      ),
      32616
    ) as presentation_utm
  from farm_watch.property_operator_observations_v1 o
  join farm_watch.properties p on p.id=o.property_id
  where p.slug='validation-property-01'
    and o.observation_key='morning-walk-2025-08-29-candidate-new'
    and o.active
  limit 1
), components as (
  select
    c.id,
    n as component_index,
    extensions.st_geometryn(c.presentation_utm,n) as geom_utm
  from candidate c
  cross join lateral generate_series(1,extensions.st_numgeometries(c.presentation_utm)) n
), cleaned_trunk as (
  select
    id,
    extensions.st_simplifypreservetopology(geom_utm,6.0) as geom_utm
  from components
  where component_index=2
), long_spur_source as (
  select id,geom_utm
  from components
  where component_index=4
), long_spur_structural as (
  select
    s.id,
    extensions.st_setpoint(
      extensions.st_simplifypreservetopology(s.geom_utm,10.0),
      0,
      extensions.st_closestpoint(t.geom_utm,extensions.st_startpoint(s.geom_utm))
    ) as geom_utm
  from long_spur_source s
  join cleaned_trunk t using(id)
), long_spur_clean as (
  select
    id,
    extensions.st_chaikinsmoothing(geom_utm,3,true) as geom_utm
  from long_spur_structural
), rebuilt_components as (
  select
    c.id,
    c.component_index,
    case
      when c.component_index=2 then t.geom_utm
      when c.component_index=4 then s.geom_utm
      else c.geom_utm
    end as geom_utm
  from components c
  left join cleaned_trunk t
    on t.id=c.id and c.component_index=2
  left join long_spur_clean s
    on s.id=c.id and c.component_index=4
), presentation as (
  select
    id,
    extensions.st_multi(
      extensions.st_collect(
        extensions.st_transform(geom_utm,4326)
        order by component_index
      )
    ) as geometry
  from rebuilt_components
  group by id
), qa as (
  select
    c.id,
    extensions.st_distance(
      extensions.st_startpoint(s.geom_utm),
      t.geom_utm
    ) as junction_gap_m,
    extensions.st_npoints(t.geom_utm) as trunk_vertex_count,
    extensions.st_npoints(s.geom_utm) as long_spur_vertex_count,
    extensions.st_isclosed(s.geom_utm) as long_spur_closed,
    extensions.st_issimple(s.geom_utm) as long_spur_simple
  from candidate c
  join cleaned_trunk t using(id)
  join long_spur_clean s using(id)
)
update farm_watch.property_operator_observations_v1 o
set source_context = jsonb_set(
      o.source_context,
      '{presentation_v1}',
      coalesce(o.source_context->'presentation_v1','{}'::jsonb) || jsonb_build_object(
        'status','available',
        'map_role','candidate_new_trail_centerline',
        'geometry_geojson',extensions.st_asgeojson(p.geometry,7)::jsonb,
        'deduplication_method','operator_confirmed_out_and_back_centerline_plus_explicit_long_spur_cleanup_v5',
        'long_spur_junction','single_exact_y_node',
        'long_spur_terminal','single_smooth_open_arc',
        'long_spur_structural_simplify_m',10.0,
        'long_spur_chaikin_iterations',3,
        'parent_trunk_simplify_m',6.0,
        'junction_gap_m',round(q.junction_gap_m::numeric,3),
        'parent_trunk_presentation_vertex_count',q.trunk_vertex_count,
        'long_spur_presentation_vertex_count',q.long_spur_vertex_count,
        'long_spur_open_end',not q.long_spur_closed,
        'long_spur_simple',q.long_spur_simple,
        'raw_classified_geometry_preserved',true,
        'operator_feedback_local_date','2026-09-20'
      ),
      true
    ),
    notes = o.notes || ' Presentation v5 explicitly cleans the long southern spur end-to-end: its parent trunk is simplified through the GPS knot to a single exact Y-junction, and the spur is represented as one smooth open arc to the preserved observed tip. Raw GPX and classified geometry remain unchanged.',
    updated_at=now()
from presentation p
join qa q using(id)
where o.id=p.id;

commit;
