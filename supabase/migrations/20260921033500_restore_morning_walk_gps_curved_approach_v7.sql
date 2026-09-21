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
), raw as (
  select
    o.id,
    extensions.st_transform(o.geometry,32616) as raw_utm
  from farm_watch.property_operator_observations_v1 o
  join farm_watch.properties p on p.id=o.property_id
  where p.slug='validation-property-01'
    and o.observation_key='morning-walk-2025-08-29-raw-gpx'
    and o.active
  limit 1
), raw_points as (
  select
    r.id,
    (dp.path)[1]::int as idx,
    dp.geom as pt
  from raw r
  cross join lateral extensions.st_dumppoints(r.raw_utm) dp
), components as (
  select
    c.id,
    n as component_index,
    extensions.st_geometryn(c.presentation_utm,n) as geom_utm
  from candidate c
  cross join lateral generate_series(
    1,
    extensions.st_numgeometries(c.presentation_utm)
  ) n
), controls as (
  select
    c.id,
    extensions.st_startpoint(
      (select geom_utm from components x where x.id=c.id and x.component_index=4)
    ) as y_node_utm
  from candidate c
), image_trail as (
  select
    c.id,
    extensions.st_transform(o.geometry,32616) as geom_utm
  from candidate c
  join farm_watch.property_operator_paths_v1 o on true
  join farm_watch.properties p on p.id=o.property_id
  where p.slug='validation-property-01'
    and o.path_key='flat-creek-phase3-image-trails'
    and o.active
  limit 1
), north_guide as (
  select
    ctrl.id,
    extensions.st_makeline(q.pt order by q.ord) as geom_utm
  from controls ctrl
  join image_trail it using(id)
  cross join lateral (
    select
      0 as ord,
      extensions.st_closestpoint(
        it.geom_utm,
        (select rp.pt from raw_points rp where rp.id=ctrl.id and rp.idx=134)
      ) as pt
    union all
    select
      rp.idx-133 as ord,
      rp.pt
    from raw_points rp
    where rp.id=ctrl.id
      and rp.idx between 135 and 165
    union all
    select
      1000 as ord,
      ctrl.y_node_utm as pt
  ) q
  group by ctrl.id
), north_smooth as (
  select
    id,
    extensions.st_chaikinsmoothing(
      extensions.st_simplifypreservetopology(geom_utm,4.0),
      3,
      true
    ) as geom_utm,
    geom_utm as raw_guide_utm
  from north_guide
), south_existing as (
  select
    cc.id,
    extensions.st_linesubstring(
      cc.geom_utm,
      extensions.st_linelocatepoint(cc.geom_utm,ctrl.y_node_utm),
      1
    ) as geom_utm
  from components cc
  join controls ctrl using(id)
  where cc.component_index=2
), rebuilt_trunk as (
  select
    n.id,
    extensions.st_linemerge(
      extensions.st_collect(n.geom_utm,s.geom_utm)
    ) as geom_utm,
    n.raw_guide_utm
  from north_smooth n
  join south_existing s using(id)
), rebuilt_components as (
  select
    cc.id,
    cc.component_index,
    case
      when cc.component_index=2 then rt.geom_utm
      when cc.component_index=4 then
        extensions.st_setpoint(
          cc.geom_utm,
          0,
          ctrl.y_node_utm
        )
      else cc.geom_utm
    end as geom_utm
  from components cc
  join rebuilt_trunk rt using(id)
  join controls ctrl using(id)
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
    rt.id,
    extensions.st_npoints(ns.raw_guide_utm) as north_raw_vertex_count,
    extensions.st_npoints(ns.geom_utm) as north_presentation_vertex_count,
    extensions.st_length(ns.raw_guide_utm) as north_raw_length_m,
    extensions.st_length(ns.geom_utm) as north_presentation_length_m,
    extensions.st_hausdorffdistance(ns.raw_guide_utm,ns.geom_utm) as north_guide_hausdorff_m,
    extensions.st_distance(
      extensions.st_startpoint(ns.raw_guide_utm),
      extensions.st_startpoint(ns.geom_utm)
    ) as trail_join_shift_m,
    extensions.st_distance(
      extensions.st_endpoint(ns.raw_guide_utm),
      extensions.st_endpoint(ns.geom_utm)
    ) as y_node_shift_m,
    extensions.st_distance(
      extensions.st_startpoint(
        (select geom_utm from rebuilt_components bc where bc.id=rt.id and bc.component_index=4)
      ),
      extensions.st_endpoint(ns.geom_utm)
    ) as spur_y_gap_m,
    extensions.st_isclosed(rt.geom_utm) as trunk_closed,
    extensions.st_issimple(rt.geom_utm) as trunk_simple
  from rebuilt_trunk rt
  join north_smooth ns using(id)
)
update farm_watch.property_operator_observations_v1 o
set source_context = jsonb_set(
      o.source_context,
      '{presentation_v1}',
      coalesce(o.source_context->'presentation_v1','{}'::jsonb) || jsonb_build_object(
        'status','available',
        'map_role','candidate_new_trail_centerline',
        'geometry_geojson',extensions.st_asgeojson(p.geometry,7)::jsonb,
        'deduplication_method','operator_confirmed_gps_guided_connected_centerline_v7',
        'north_approach_raw_start_index',134,
        'north_approach_raw_y_index',165,
        'north_approach_connected_to_existing_trail',true,
        'north_approach_simplify_m',4.0,
        'north_approach_chaikin_iterations',3,
        'north_approach_raw_vertex_count',q.north_raw_vertex_count,
        'north_approach_presentation_vertex_count',q.north_presentation_vertex_count,
        'north_approach_raw_length_m',round(q.north_raw_length_m::numeric,1),
        'north_approach_presentation_length_m',round(q.north_presentation_length_m::numeric,1),
        'north_approach_guide_hausdorff_m',round(q.north_guide_hausdorff_m::numeric,1),
        'north_trail_join_shift_m',round(q.trail_join_shift_m::numeric,3),
        'north_y_node_shift_m',round(q.y_node_shift_m::numeric,3),
        'long_spur_junction_gap_m',round(q.spur_y_gap_m::numeric,3),
        'southern_trunk_open_end',not q.trunk_closed,
        'southern_trunk_simple',q.trunk_simple,
        'raw_classified_geometry_preserved',true,
        'operator_feedback_local_date','2026-09-20'
      ),
      true
    ),
    notes = o.notes || ' Presentation v7 restores the original GPS-guided curvature from raw point 134, which lies on the existing image-derived trail, through raw point 165 at the preserved Y-node. The approach is smoothed rather than straightened; the prior southern turnaround cleanup remains unchanged. Raw GPX and classified geometry remain unchanged.',
    updated_at=now()
from presentation p
join qa q using(id)
where o.id=p.id;

commit;
