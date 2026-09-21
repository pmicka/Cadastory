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
    d.geom as geom_4326,
    extensions.st_transform(d.geom,32616) as geom_utm
  from candidate c
  cross join lateral extensions.st_dump(c.geometry) d
), split_candidates as (
  select
    p.id,
    p.part_index,
    p.geom_4326,
    p.geom_utm,
    dp.geom as point_utm,
    extensions.st_distance(dp.geom,extensions.st_startpoint(p.geom_utm)) as start_distance_m,
    extensions.st_linelocatepoint(p.geom_utm,dp.geom) as fraction,
    row_number() over (
      partition by p.id,p.part_index
      order by extensions.st_distance(dp.geom,extensions.st_startpoint(p.geom_utm)) desc,
               (dp.path)[1]
    ) as rn
  from parts p
  cross join lateral extensions.st_dumppoints(p.geom_utm) dp
), presentation_parts as (
  select
    id,
    part_index,
    case
      when part_index = 1 then geom_4326
      when part_index in (2,3) then extensions.st_transform(
        extensions.st_linesubstring(geom_utm,0,fraction),
        4326
      )
      else geom_4326
    end as geom_4326
  from split_candidates
  where rn=1
), presentation as (
  select
    id,
    extensions.st_multi(
      extensions.st_collect(geom_4326 order by part_index)
    ) as geometry
  from presentation_parts
  group by id
)
update farm_watch.property_operator_observations_v1 o
set source_context = o.source_context || jsonb_build_object(
      'presentation_v1', jsonb_build_object(
        'status','available',
        'map_role','candidate_new_trail_centerline',
        'geometry_geojson',extensions.st_asgeojson(p.geometry,7)::jsonb,
        'deduplication_method','operator_confirmed_out_and_back_first_leg_to_farthest_turnaround_v1',
        'raw_classified_geometry_preserved',true,
        'true_loop_part_indices',jsonb_build_array(1),
        'out_and_back_part_indices',jsonb_build_array(2,3),
        'operator_feedback_local_date','2026-09-20'
      )
    ),
    notes = o.notes || ' Map presentation deduplicates the operator-confirmed out-and-back portions to one representative leg while preserving the genuine northern loop. Raw GPX and full classified geometry remain unchanged.',
    updated_at = now()
from presentation p
where o.id=p.id;

update farm_watch.property_operator_observations_v1 o
set source_context = o.source_context || jsonb_build_object(
      'presentation_v1', jsonb_build_object(
        'status','hidden',
        'reason','redundant_with_existing_canonical_access',
        'map_role','corroborating_only',
        'raw_classified_geometry_preserved',true,
        'operator_feedback_local_date','2026-09-20'
      )
    ),
    notes = o.notes || ' Map presentation hides this overlap geometry because the operator identified it as redundant with the existing canonical access/trail network; the classification remains available analytically.',
    updated_at = now()
from farm_watch.properties p
where o.property_id=p.id
  and p.slug='validation-property-01'
  and o.observation_key='morning-walk-2025-08-29-existing-overlap'
  and o.active;

commit;
