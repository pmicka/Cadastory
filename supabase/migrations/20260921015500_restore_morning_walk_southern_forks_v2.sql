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
), farthest as (
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
  from farthest
), return_legs as (
  select
    id,
    part_index,
    extensions.st_linesubstring(geom_utm,0,split_fraction) as outbound,
    extensions.st_linesubstring(geom_utm,split_fraction,1) as return_leg
  from farthest
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
    min(outbound) as outbound,
    extensions.st_linemerge(extensions.st_collect(seg order by seg_index)) as branch
  from runs
  where divergent=1
  group by id,part_index,run_id
), fork_components as (
  select id,part_index,run_id,1 as component_order,
         extensions.st_shortestline(outbound,extensions.st_startpoint(branch)) as geom_utm
  from fork_runs
  union all
  select id,part_index,run_id,2,
         branch
  from fork_runs
  union all
  select id,part_index,run_id,3,
         extensions.st_shortestline(extensions.st_endpoint(branch),outbound) as geom_utm
  from fork_runs
), presentation_components as (
  select id,part_index as group_order,0 as sub_order,geom_utm
  from base_parts
  union all
  select id,10+part_index as group_order,
         row_number() over(partition by id,part_index,run_id order by component_order)::int as sub_order,
         geom_utm
  from fork_components
), presentation as (
  select
    id,
    extensions.st_multi(
      extensions.st_collect(
        extensions.st_transform(geom_utm,4326)
        order by group_order,sub_order
      )
    ) as geometry
  from presentation_components
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
        'deduplication_method','operator_confirmed_out_and_back_centerline_plus_divergent_forks_v2',
        'fork_restore_threshold_m',8.0,
        'restored_fork_part_indices',jsonb_build_array(2,3),
        'raw_classified_geometry_preserved',true,
        'operator_feedback_local_date','2026-09-20'
      ),
      true
    ),
    notes = regexp_replace(
      o.notes,
      ' Map presentation deduplicates the operator-confirmed out-and-back portions[^.]*\.',
      '',
      'g'
    ) || ' Map presentation keeps one representative leg for each out-and-back trunk, preserves the genuine northern loop, and restores the operator-confirmed divergent fork excursions from both southern traces. Raw GPX and full classified geometry remain unchanged.',
    updated_at=now()
from presentation p
where o.id=p.id;

commit;
