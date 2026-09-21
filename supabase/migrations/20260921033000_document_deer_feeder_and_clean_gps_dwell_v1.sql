begin;

create temporary table _fw_feeder_cleanup_v1 on commit drop as
with candidate as (
  select
    o.id,
    o.property_id,
    o.geometry,
    o.related_artifact_sha256,
    extensions.st_setsrid(
      extensions.st_geomfromgeojson(
        (o.source_context->'presentation_v1'->'geometry_geojson')::text
      ),
      4326
    ) as current_presentation
  from farm_watch.property_operator_observations_v1 o
  join farm_watch.properties p on p.id=o.property_id
  where p.slug='validation-property-01'
    and o.observation_key='morning-walk-2025-08-29-candidate-new'
    and o.active
  limit 1
), north as (
  select
    c.*,
    d.geom as north_4326,
    extensions.st_transform(d.geom,32616) as north_utm
  from candidate c
  cross join lateral extensions.st_dump(c.geometry) d
  where (d.path)[1]=1
), points as (
  select
    n.id,
    n.property_id,
    n.related_artifact_sha256,
    n.current_presentation,
    n.north_utm,
    (dp.path)[1]::int as idx,
    dp.geom as point_utm
  from north n
  cross join lateral extensions.st_dumppoints(n.north_utm) dp
), density as (
  select
    a.id,
    a.idx,
    a.point_utm,
    count(*) filter (where extensions.st_distance(a.point_utm,b.point_utm)<=8.0) as within8_count,
    count(*) filter (where extensions.st_distance(a.point_utm,b.point_utm)<=12.0) as within12_count
  from points a
  join points b on b.id=a.id
  group by a.id,a.idx,a.point_utm
), peak as (
  select distinct on (id)
    id,idx,point_utm,within8_count,within12_count
  from density
  order by id,within8_count desc,within12_count desc,idx
), cluster as (
  select
    p.id,
    p.property_id,
    p.related_artifact_sha256,
    p.idx,
    p.point_utm
  from points p
  join peak x using(id)
  where extensions.st_distance(p.point_utm,x.point_utm)<=12.0
), feeder as (
  select
    c.id,
    min(c.property_id::text)::uuid as property_id,
    min(c.related_artifact_sha256) as related_artifact_sha256,
    extensions.st_centroid(extensions.st_collect(c.point_utm)) as feeder_utm,
    count(*)::int as cluster_point_count,
    min(c.idx)::int as cluster_first_idx,
    max(c.idx)::int as cluster_last_idx,
    round(max(extensions.st_distance(c.point_utm,x.point_utm))::numeric,1) as cluster_radius_m,
    max(x.within8_count)::int as peak_within8_count,
    max(x.within12_count)::int as peak_within12_count
  from cluster c
  join peak x using(id)
  group by c.id
), clean_north_points as (
  select
    p.id,
    p.idx::numeric as ord,
    p.point_utm
  from points p
  where p.idx<=13
  union all
  select
    f.id,
    50.0::numeric as ord,
    f.feeder_utm as point_utm
  from feeder f
  union all
  select
    p.id,
    (100+p.idx)::numeric as ord,
    p.point_utm
  from points p
  where p.idx>=97
), clean_north as (
  select
    id,
    extensions.st_transform(
      extensions.st_makeline(point_utm order by ord),
      4326
    ) as geom_4326
  from clean_north_points
  group by id
), rebuilt_components as (
  select
    c.id,
    n as component_index,
    case
      when n=1 then cn.geom_4326
      else extensions.st_geometryn(c.current_presentation,n)
    end as geom_4326
  from candidate c
  join clean_north cn using(id)
  cross join lateral generate_series(1,extensions.st_numgeometries(c.current_presentation)) n
), rebuilt as (
  select
    id,
    extensions.st_multi(
      extensions.st_collect(geom_4326 order by component_index)
    ) as presentation_geometry
  from rebuilt_components
  group by id
)
select
  c.id,
  c.property_id,
  c.related_artifact_sha256,
  f.feeder_utm,
  f.cluster_point_count,
  f.cluster_first_idx,
  f.cluster_last_idx,
  f.cluster_radius_m,
  f.peak_within8_count,
  f.peak_within12_count,
  r.presentation_geometry
from candidate c
join feeder f using(id,property_id,related_artifact_sha256)
join rebuilt r using(id);

insert into farm_watch.property_operator_observations_v1 (
  property_id,
  observation_key,
  observation_kind,
  observation_state,
  persistence_status,
  timing_status,
  geometry_basis,
  geometry_precision_m,
  related_product_kind,
  related_artifact_sha256,
  related_feature_key,
  source_context,
  notes,
  geometry
)
select
  x.property_id,
  'flat-creek-deer-feeder-01',
  'deer_feeder_location',
  'observed_present',
  'unknown',
  'unknown',
  'operator_identified_field_gnss_dwell_centroid_v1',
  15.0,
  'field_gnss_track',
  x.related_artifact_sha256,
  'morning-walk-2025-08-29-feeder-dwell-cluster',
  jsonb_build_object(
    'operator_identified',true,
    'operator_feedback_local_date','2026-09-20',
    'source_observation_key','morning-walk-2025-08-29-candidate-new',
    'source_track_key','morning-walk-2025-08-29-raw-gpx',
    'dwell_cluster_method','densest_candidate_component_point_then_12m_cluster_centroid_v1',
    'cluster_point_count',x.cluster_point_count,
    'cluster_first_source_vertex',x.cluster_first_idx,
    'cluster_last_source_vertex',x.cluster_last_idx,
    'cluster_radius_m',x.cluster_radius_m,
    'peak_within_8m_count',x.peak_within8_count,
    'peak_within_12m_count',x.peak_within12_count,
    'raw_gpx_preserved',true,
    'temporal_deployment_inferred',false
  ),
  'Operator identified the dense GPS dwell cluster as the deer feeder location. Point is retained for later Farm Watch analysis. Feeder installation/deployment timing is not inferred from the GPS track.',
  extensions.st_transform(x.feeder_utm,4326)
from _fw_feeder_cleanup_v1 x
on conflict (property_id,observation_key) do update
set observation_kind=excluded.observation_kind,
    observation_state=excluded.observation_state,
    persistence_status=excluded.persistence_status,
    timing_status=excluded.timing_status,
    geometry_basis=excluded.geometry_basis,
    geometry_precision_m=excluded.geometry_precision_m,
    related_product_kind=excluded.related_product_kind,
    related_artifact_sha256=excluded.related_artifact_sha256,
    related_feature_key=excluded.related_feature_key,
    source_context=excluded.source_context,
    notes=excluded.notes,
    geometry=excluded.geometry,
    active=true,
    updated_at=now();

update farm_watch.property_operator_observations_v1 o
set source_context = jsonb_set(
      o.source_context,
      '{presentation_v1}',
      coalesce(o.source_context->'presentation_v1','{}'::jsonb) || jsonb_build_object(
        'geometry_geojson',extensions.st_asgeojson(x.presentation_geometry,7)::jsonb,
        'feeder_dwell_cleanup','replace_dense_dwell_cluster_with_single_pass_through_feeder_point_v1',
        'feeder_observation_key','flat-creek-deer-feeder-01',
        'feeder_cluster_source_vertex_range',jsonb_build_array(x.cluster_first_idx,x.cluster_last_idx),
        'raw_classified_geometry_preserved',true,
        'operator_feedback_local_date','2026-09-20'
      ),
      true
    ),
    notes = o.notes || ' The northern route presentation removes the GPS dwell/jitter at the operator-identified deer feeder, replacing it with one clean pass through the separately stored feeder point. Raw GPX and classified geometry remain unchanged.',
    updated_at=now()
from _fw_feeder_cleanup_v1 x
where o.id=x.id;

commit;
