begin;

with candidate as (
  select o.id,o.geometry
  from farm_watch.property_operator_observations_v1 o
  join farm_watch.properties p on p.id=o.property_id
  where p.slug='validation-property-01'
    and o.observation_key='morning-walk-2025-08-29-candidate-new'
    and o.active
  limit 1
), parts as (
  select
    c.id,
    (d.path)[1]::int as part_index,
    extensions.st_transform(d.geom,32616) as geom_utm
  from candidate c
  cross join lateral extensions.st_dump(c.geometry) d
), farthest_main as (
  select distinct on (p.id,p.part_index)
    p.id,p.part_index,p.geom_utm,
    extensions.st_linelocatepoint(p.geom_utm,dp.geom) as split_fraction
  from parts p
  cross join lateral extensions.st_dumppoints(p.geom_utm) dp
  order by p.id,p.part_index,
           extensions.st_distance(dp.geom,extensions.st_startpoint(p.geom_utm)) desc,
           (dp.path)[1]
), base_parts as (
  select
    id,
    part_index,
    case
      when part_index=1 then geom_utm
      when part_index in (2,3) then extensions.st_linesubstring(geom_utm,0,split_fraction)
      else geom_utm
    end as geom_utm
  from farthest_main
), return_legs as (
  select
    id,
    part_index,
    extensions.st_linesubstring(geom_utm,0,split_fraction) as outbound,
    extensions.st_linesubstring(geom_utm,split_fraction,1) as return_leg
  from farthest_main
  where part_index in (2,3)
), return_segments as (
  select
    r.id,
    r.part_index,
    gs as seg_index,
    r.outbound,
    extensions.st_makeline(
      extensions.st_pointn(r.return_leg,gs),
      extensions.st_pointn(r.return_leg,gs+1)
    ) as seg
  from return_legs r
  cross join lateral generate_series(1,extensions.st_npoints(r.return_leg)-1) gs
), measured as (
  select *,
    extensions.st_distance(
      extensions.st_lineinterpolatepoint(seg,0.5),
      outbound
    ) as midpoint_distance_m
  from return_segments
), flagged as (
  select *,case when midpoint_distance_m>=8.0 then 1 else 0 end as divergent
  from measured
), breaks as (
  select *,
    case when lag(divergent) over(partition by id,part_index order by seg_index)
      is distinct from divergent then 1 else 0 end as is_break
  from flagged
), runs as (
  select *,
    sum(is_break) over(partition by id,part_index order by seg_index) as run_id
  from breaks
), fork_runs as (
  select
    id,
    part_index,
    run_id,
    extensions.st_linemerge(extensions.st_collect(seg order by seg_index)) as branch
  from runs
  where divergent=1
  group by id,part_index,run_id
), fork_turn_candidates as (
  select
    fr.id,
    fr.part_index,
    fr.run_id,
    l.outbound,
    fr.branch,
    (dp.path)[1]::int as point_index,
    dp.geom as point_utm,
    extensions.st_distance(dp.geom,l.outbound) as distance_to_trunk_m,
    extensions.st_linelocatepoint(fr.branch,dp.geom) as fraction
  from fork_runs fr
  join return_legs l using(id,part_index)
  cross join lateral extensions.st_dumppoints(fr.branch) dp
), fork_turns as (
  select distinct on (id,part_index,run_id)
    id,part_index,run_id,outbound,branch,point_utm,distance_to_trunk_m,fraction
  from fork_turn_candidates
  order by id,part_index,run_id,distance_to_trunk_m desc,point_index
), raw_open_spurs as (
  select
    id,
    part_index,
    extensions.st_linemerge(
      extensions.st_collect(
        extensions.st_shortestline(outbound,extensions.st_startpoint(branch)),
        extensions.st_linesubstring(branch,0,fraction)
      )
    ) as geom_utm,
    distance_to_trunk_m as tip_distance_m,
    point_utm as tip_utm
  from fork_turns
), presentation_spurs as (
  select
    id,
    part_index,
    case
      when part_index=2 then
        extensions.st_simplifypreservetopology(geom_utm,8.0)
      when part_index=3 then
        extensions.st_chaikinsmoothing(
          extensions.st_simplifypreservetopology(geom_utm,5.0),
          2,
          true
        )
      else geom_utm
    end as geom_utm,
    tip_distance_m,
    tip_utm,
    extensions.st_npoints(geom_utm) as source_vertex_count
  from raw_open_spurs
), presentation_components as (
  select id,part_index as group_order,geom_utm
  from base_parts
  union all
  select id,10+part_index as group_order,geom_utm
  from presentation_spurs
), presentation as (
  select
    id,
    extensions.st_multi(
      extensions.st_collect(
        extensions.st_transform(geom_utm,4326)
        order by group_order
      )
    ) as geometry
  from presentation_components
  group by id
), spur_summary as (
  select
    id,
    jsonb_agg(
      jsonb_build_object(
        'part_index',part_index,
        'tip_distance_from_trunk_m',round(tip_distance_m::numeric,1),
        'tip_geojson',extensions.st_asgeojson(extensions.st_transform(tip_utm,4326),7)::jsonb,
        'open_end',true,
        'presentation_vertex_count',extensions.st_npoints(geom_utm),
        'source_open_spur_vertex_count',source_vertex_count,
        'presentation_method',case
          when part_index=2 then 'simple_fork_simplify_8m'
          when part_index=3 then 'rounded_terminal_simplify_5m_chaikin_2'
          else 'raw_open_spur'
        end
      )
      order by part_index
    ) as spurs
  from presentation_spurs
  group by id
)
update farm_watch.property_operator_observations_v1 o
set source_context = jsonb_set(
      o.source_context,
      '{presentation_v1}',
      coalesce(o.source_context->'presentation_v1','{}'::jsonb) || jsonb_build_object(
        'status','available',
        'map_role','candidate_new_trail_centerline',
        'geometry_geojson',extensions.st_asgeojson(p.geometry,7)::jsonb,
        'deduplication_method','operator_confirmed_out_and_back_centerline_plus_clean_open_spurs_v4',
        'spur_topology','single_attachment_open_end',
        'spur_cleanup','part 2 simple fork; part 3 rounded terminal',
        'spur_summary',s.spurs,
        'raw_classified_geometry_preserved',true,
        'operator_feedback_local_date','2026-09-20'
      ),
      true
    ),
    notes = regexp_replace(
      o.notes,
      ' Map presentation keeps one representative leg for each out-and-back trunk[^.]*\.',
      '',
      'g'
    ) || ' Map presentation keeps one representative leg for each out-and-back trunk and the genuine northern loop. The first southern spur is simplified to a clean fork; the second is smoothed into a rounded open terminal. Raw GPX and full classified geometry remain unchanged.',
    updated_at=now()
from presentation p
join spur_summary s using(id)
where o.id=p.id;

commit;
