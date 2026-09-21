begin;

with candidate as (
  select
    o.id,
    o.geometry as raw_classified_4326,
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
), raw_part2 as (
  select
    c.id,
    extensions.st_transform(d.geom,32616) as geom_utm
  from candidate c
  cross join lateral extensions.st_dump(c.raw_classified_4326) d
  where (d.path)[1]=2
), raw_points as (
  select
    r.id,
    (dp.path)[1]::int as idx,
    dp.geom as pt
  from raw_part2 r
  cross join lateral extensions.st_dumppoints(r.geom_utm) dp
), current_components as (
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
    extensions.st_closestpoint(
      t.geom_utm,
      extensions.st_startpoint(s.geom_utm)
    ) as junction_utm,
    (
      select rp.pt
      from raw_points rp
      where rp.id=c.id and rp.idx=79
    ) as turnaround_utm
  from candidate c
  join current_components t
    on t.id=c.id and t.component_index=2
  join current_components s
    on s.id=c.id and s.component_index=4
), north_prefix as (
  select
    cc.id,
    extensions.st_makeline(
      extensions.st_startpoint(cc.geom_utm),
      ctrl.junction_utm
    ) as geom_utm
  from current_components cc
  join controls ctrl using(id)
  where cc.component_index=2
), raw_south as (
  select
    n.id,
    extensions.st_makeline(q.pt order by q.ord) as geom_utm
  from north_prefix n
  cross join lateral (
    select 0 as ord,extensions.st_endpoint(n.geom_utm) as pt
    union all
    select rp.idx-30 as ord,rp.pt
    from raw_points rp
    where rp.id=n.id
      and rp.idx between 31 and 79
  ) q
  group by n.id
), smooth_south as (
  select
    id,
    extensions.st_chaikinsmoothing(
      extensions.st_simplifypreservetopology(geom_utm,5.0),
      3,
      true
    ) as geom_utm,
    geom_utm as raw_guide_utm
  from raw_south
), rebuilt_trunk as (
  select
    n.id,
    extensions.st_linemerge(
      extensions.st_collect(n.geom_utm,s.geom_utm)
    ) as geom_utm,
    s.raw_guide_utm
  from north_prefix n
  join smooth_south s using(id)
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
          extensions.st_endpoint(np.geom_utm)
        )
      else cc.geom_utm
    end as geom_utm
  from current_components cc
  join rebuilt_trunk rt using(id)
  join controls ctrl using(id)
  join north_prefix np using(id)
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
    extensions.st_npoints(rt.geom_utm) as trunk_vertex_count,
    extensions.st_npoints(ss.geom_utm) as smoothed_terminal_vertex_count,
    extensions.st_length(ss.raw_guide_utm) as raw_terminal_length_m,
    extensions.st_length(ss.geom_utm) as smoothed_terminal_length_m,
    extensions.st_hausdorffdistance(ss.raw_guide_utm,ss.geom_utm) as guide_hausdorff_m,
    extensions.st_distance(
      extensions.st_endpoint(rt.geom_utm),
      ctrl.turnaround_utm
    ) as terminal_shift_m,
    extensions.st_distance(
      extensions.st_startpoint(
        (select geom_utm from rebuilt_components bc where bc.id=rt.id and bc.component_index=4)
      ),
      extensions.st_endpoint(np.geom_utm)
    ) as spur_junction_gap_m,
    extensions.st_isclosed(rt.geom_utm) as trunk_closed,
    extensions.st_issimple(rt.geom_utm) as trunk_simple
  from rebuilt_trunk rt
  join smooth_south ss using(id)
  join controls ctrl using(id)
  join north_prefix np using(id)
)
update farm_watch.property_operator_observations_v1 o
set source_context = jsonb_set(
      o.source_context,
      '{presentation_v1}',
      coalesce(o.source_context->'presentation_v1','{}'::jsonb) || jsonb_build_object(
        'status','available',
        'map_role','candidate_new_trail_centerline',
        'geometry_geojson',extensions.st_asgeojson(p.geometry,7)::jsonb,
        'deduplication_method','operator_confirmed_out_and_back_centerline_plus_true_turnaround_smoothing_v6',
        'southern_turnaround_raw_point_index',79,
        'southern_turnaround_return_backtrack_removed',true,
        'southern_turnaround_simplify_m',5.0,
        'southern_turnaround_chaikin_iterations',3,
        'southern_turnaround_smoothed_vertex_count',q.smoothed_terminal_vertex_count,
        'southern_turnaround_raw_guide_length_m',round(q.raw_terminal_length_m::numeric,1),
        'southern_turnaround_smoothed_length_m',round(q.smoothed_terminal_length_m::numeric,1),
        'southern_turnaround_guide_hausdorff_m',round(q.guide_hausdorff_m::numeric,1),
        'southern_turnaround_terminal_shift_m',round(q.terminal_shift_m::numeric,3),
        'long_spur_junction_gap_m',round(q.spur_junction_gap_m::numeric,3),
        'southern_trunk_presentation_vertex_count',q.trunk_vertex_count,
        'southern_trunk_open_end',not q.trunk_closed,
        'southern_trunk_simple',q.trunk_simple,
        'raw_classified_geometry_preserved',true,
        'operator_feedback_local_date','2026-09-20'
      ),
      true
    ),
    notes = o.notes || ' Presentation v6 removes the final southern return-leg backtrack and rebuilds the outbound approach to the true raw turnaround (point 79) as an endpoint-preserving smoothed centerline guided by the original GPS. The side spur remains snapped to the preserved Y-junction. Raw GPX and classified geometry remain unchanged.',
    updated_at=now()
from presentation p
join qa q using(id)
where o.id=p.id;

commit;
