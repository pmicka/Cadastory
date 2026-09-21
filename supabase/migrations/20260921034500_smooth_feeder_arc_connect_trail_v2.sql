begin;

create temporary table _fw_feeder_arc_v2 on commit drop as
with candidate as (
  select
    o.id,
    extensions.st_transform(
      extensions.st_setsrid(
        extensions.st_geomfromgeojson(
          (o.source_context->'presentation_v1'->'geometry_geojson')::text
        ),
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
), feeder as (
  select
    extensions.st_transform(o.geometry,32616) as feeder_utm
  from farm_watch.property_operator_observations_v1 o
  join farm_watch.properties p on p.id=o.property_id
  where p.slug='validation-property-01'
    and o.observation_key='flat-creek-deer-feeder-01'
    and o.active
  limit 1
), trail as (
  select
    extensions.st_transform(o.geometry,32616) as trail_utm
  from farm_watch.property_operator_paths_v1 o
  join farm_watch.properties p on p.id=o.property_id
  where p.slug='validation-property-01'
    and o.path_key='flat-creek-phase3-image-trails'
    and o.active
  limit 1
), north as (
  select
    c.id,
    extensions.st_geometryn(c.presentation_utm,1) as north_utm,
    f.feeder_utm,
    t.trail_utm
  from candidate c
  cross join feeder f
  cross join trail t
), split as (
  select
    id,
    north_utm,
    feeder_utm,
    trail_utm,
    extensions.st_linelocatepoint(north_utm,feeder_utm) as feeder_fraction,
    extensions.st_startpoint(north_utm) as loose_start,
    extensions.st_endpoint(north_utm) as loose_end
  from north
), halves as (
  select
    id,
    feeder_utm,
    trail_utm,
    extensions.st_linesubstring(north_utm,0,feeder_fraction) as half_a,
    extensions.st_linesubstring(north_utm,feeder_fraction,1) as half_b,
    loose_start,
    loose_end,
    extensions.st_closestpoint(trail_utm,loose_start) as attach_a,
    extensions.st_closestpoint(trail_utm,loose_end) as attach_b
  from split
), extended as (
  select
    id,
    feeder_utm,
    attach_a,
    attach_b,
    extensions.st_linemerge(
      extensions.st_collect(
        extensions.st_makeline(attach_a,loose_start),
        half_a
      )
    ) as extended_a,
    extensions.st_linemerge(
      extensions.st_collect(
        half_b,
        extensions.st_makeline(loose_end,attach_b)
      )
    ) as extended_b
  from halves
), smoothed as (
  select
    id,
    feeder_utm,
    attach_a,
    attach_b,
    extensions.st_chaikinsmoothing(
      extensions.st_simplifypreservetopology(extended_a,4.0),
      2,
      true
    ) as smooth_a,
    extensions.st_chaikinsmoothing(
      extensions.st_simplifypreservetopology(extended_b,4.0),
      2,
      true
    ) as smooth_b
  from extended
), rebuilt_north as (
  select
    id,
    feeder_utm,
    attach_a,
    attach_b,
    extensions.st_linemerge(
      extensions.st_collect(smooth_a,smooth_b)
    ) as north_utm
  from smoothed
), components as (
  select
    c.id,
    n as component_index,
    case
      when n=1 then rn.north_utm
      else extensions.st_geometryn(c.presentation_utm,n)
    end as geom_utm,
    rn.feeder_utm,
    rn.attach_a,
    rn.attach_b
  from candidate c
  join rebuilt_north rn using(id)
  cross join lateral generate_series(1,extensions.st_numgeometries(c.presentation_utm)) n
), rebuilt as (
  select
    id,
    min(feeder_utm) as feeder_utm,
    min(attach_a) as attach_a,
    min(attach_b) as attach_b,
    extensions.st_multi(
      extensions.st_collect(
        extensions.st_transform(geom_utm,4326)
        order by component_index
      )
    ) as presentation_geometry
  from components
  group by id
)
select
  id,
  feeder_utm,
  attach_a,
  attach_b,
  presentation_geometry,
  extensions.st_geometryn(extensions.st_transform(presentation_geometry,32616),1) as north_utm
from rebuilt;

update farm_watch.property_operator_observations_v1 o
set source_context = jsonb_set(
      o.source_context,
      '{presentation_v1}',
      coalesce(o.source_context->'presentation_v1','{}'::jsonb) || jsonb_build_object(
        'geometry_geojson',extensions.st_asgeojson(x.presentation_geometry,7)::jsonb,
        'feeder_dwell_cleanup','smooth_two_half_curves_through_feeder_and_attach_both_ends_to_canonical_trail_v2',
        'feeder_observation_key','flat-creek-deer-feeder-01',
        'feeder_arc_simplify_m',4.0,
        'feeder_arc_chaikin_iterations',2,
        'feeder_arc_topology','canonical_trail_to_feeder_to_canonical_trail',
        'trail_attachment_a_geojson',extensions.st_asgeojson(extensions.st_transform(x.attach_a,4326),7)::jsonb,
        'trail_attachment_b_geojson',extensions.st_asgeojson(extensions.st_transform(x.attach_b,4326),7)::jsonb,
        'raw_classified_geometry_preserved',true,
        'operator_feedback_local_date','2026-09-20'
      ),
      true
    ),
    notes = o.notes || ' Feeder-area presentation v2 smooths the cleaned route into two endpoint-preserving curves through the stored feeder point and extends both loose ends to their nearest canonical imagery-derived trail positions. Raw GPX and classified geometry remain unchanged.',
    updated_at=now()
from _fw_feeder_arc_v2 x
where o.id=x.id;

commit;
