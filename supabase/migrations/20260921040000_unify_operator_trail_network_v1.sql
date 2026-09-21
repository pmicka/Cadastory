begin;

create temporary table _fw_unified_trail_v1 on commit drop as
with canonical as (
  select
    o.id,
    o.property_id,
    extensions.st_transform(o.geometry,32616) as geom_utm,
    o.geometry_precision_m,
    o.feature_subclass,
    o.geometry_basis
  from farm_watch.property_operator_paths_v1 o
  join farm_watch.properties p on p.id=o.property_id
  where p.slug='validation-property-01'
    and o.path_key='flat-creek-phase3-image-trails'
    and o.active
  limit 1
), field_obs as (
  select
    o.id,
    o.property_id,
    extensions.st_transform(
      extensions.st_setsrid(
        extensions.st_geomfromgeojson(
          (o.source_context->'presentation_v1'->'geometry_geojson')::text
        ),
        4326
      ),
      32616
    ) as geom_utm,
    o.geometry_precision_m
  from farm_watch.property_operator_observations_v1 o
  join farm_watch.properties p on p.id=o.property_id
  where p.slug='validation-property-01'
    and o.observation_key='morning-walk-2025-08-29-candidate-new'
    and o.active
  limit 1
), field_parts as (
  select (d.path)[1]::int as part_index,d.geom
  from field_obs f
  cross join lateral extensions.st_dump(f.geom_utm) d
), target_field as (
  select geom
  from field_parts
  where part_index=3
), canonical_parts as (
  select
    (d.path)[1]::int as part_index,
    d.geom
  from canonical c
  cross join lateral extensions.st_dump(c.geom_utm) d
), canonical_endpoints as (
  select part_index,'start'::text as end_name,extensions.st_startpoint(geom) as pt from canonical_parts
  union all
  select part_index,'end',extensions.st_endpoint(geom) from canonical_parts
), bridge_target as (
  select
    e.part_index,
    e.end_name,
    e.pt as canonical_endpoint,
    extensions.st_startpoint((select geom from target_field)) as field_endpoint,
    extensions.st_distance(
      e.pt,
      extensions.st_startpoint((select geom from target_field))
    ) as gap_m
  from canonical_endpoints e
  order by gap_m
  limit 1
), bridge as (
  select
    extensions.st_makeline(canonical_endpoint,field_endpoint) as geom_utm,
    gap_m,
    part_index as canonical_part_index,
    end_name as canonical_end_name,
    canonical_endpoint,
    field_endpoint
  from bridge_target
), combined as (
  select
    c.id as canonical_id,
    c.property_id,
    f.id as field_observation_id,
    extensions.st_collect(array[
      c.geom_utm,
      f.geom_utm,
      b.geom_utm
    ]) as geom_utm,
    b.gap_m,
    b.canonical_part_index,
    b.canonical_end_name,
    b.canonical_endpoint,
    b.field_endpoint,
    extensions.st_length(c.geom_utm) as prior_canonical_length_m,
    extensions.st_length(f.geom_utm) as promoted_field_length_m,
    c.geometry_precision_m as prior_precision_m,
    f.geometry_precision_m as field_precision_m,
    c.feature_subclass as prior_feature_subclass,
    c.geometry_basis as prior_geometry_basis
  from canonical c
  cross join field_obs f
  cross join bridge b
), merged as (
  select
    canonical_id,
    property_id,
    field_observation_id,
    extensions.st_multi(
      extensions.st_collectionextract(
        extensions.st_unaryunion(
          extensions.st_snap(geom_utm,geom_utm,0.1)
        ),
        2
      )
    ) as geom_utm,
    gap_m,
    canonical_part_index,
    canonical_end_name,
    canonical_endpoint,
    field_endpoint,
    prior_canonical_length_m,
    promoted_field_length_m,
    prior_precision_m,
    field_precision_m,
    prior_feature_subclass,
    prior_geometry_basis
  from combined
), connected as (
  select
    m.*,
    (
      select cardinality(extensions.st_clusterintersecting(d.geom))
      from extensions.st_dump(m.geom_utm) d
    ) as cluster_count
  from merged m
)
select
  *,
  extensions.st_transform(geom_utm,4326) as geometry_4326,
  extensions.st_length(geom_utm) as unified_length_m,
  extensions.st_numgeometries(geom_utm) as unified_component_count,
  extensions.st_issimple(geom_utm) as unified_simple
from connected;

do $$
declare
  r record;
begin
  select * into r from _fw_unified_trail_v1 limit 1;
  if r.canonical_id is null then
    raise exception 'canonical trail row not found';
  end if;
  if r.field_observation_id is null then
    raise exception 'field trail observation not found';
  end if;
  if r.gap_m < 14.0 or r.gap_m > 15.0 then
    raise exception 'unexpected canonical-field bridge length: % m', r.gap_m;
  end if;
  if r.cluster_count <> 1 then
    raise exception 'unified trail must be one connected graph; got % clusters', r.cluster_count;
  end if;
  if not r.unified_simple then
    raise exception 'unified trail geometry must be simple';
  end if;
end
$$;

update farm_watch.property_operator_paths_v1 o
set
  name='Flat Creek operator-confirmed trail network',
  feature_class='trail',
  feature_subclass='operator_confirmed_trail_network',
  existence_status='operator_confirmed',
  geometry_basis='operator_merged_phase3_imagery_field_gnss_v1',
  geometry_precision_m=greatest(
    coalesce(o.geometry_precision_m,0),
    coalesce(x.field_precision_m,0)
  ),
  source_context=
    o.source_context
    || jsonb_build_object(
      'topology','unified operator-confirmed connected trail network with retained feeder route and field-confirmed branches',
      'segment_count',x.unified_component_count,
      'evidence_source','mixed operator-confirmed Phase 3 imagery and field GNSS',
      'additional_path_inference',false,
      'unified_network_v1',jsonb_build_object(
        'status','canonical',
        'promotion_local_date','2026-09-20',
        'prior_path_key','flat-creek-phase3-image-trails',
        'prior_feature_subclass',x.prior_feature_subclass,
        'prior_geometry_basis',x.prior_geometry_basis,
        'prior_geometry_precision_m',x.prior_precision_m,
        'prior_canonical_length_m',round(x.prior_canonical_length_m::numeric,1),
        'promoted_field_observation_key','morning-walk-2025-08-29-candidate-new',
        'promoted_field_geometry_precision_m',x.field_precision_m,
        'promoted_field_presentation_length_m',round(x.promoted_field_length_m::numeric,1),
        'feeder_observation_key','flat-creek-deer-feeder-01',
        'bridge_status','operator_confirmed',
        'bridge_length_m',round(x.gap_m::numeric,2),
        'bridge_canonical_part_index',x.canonical_part_index,
        'bridge_canonical_end',x.canonical_end_name,
        'bridge_canonical_endpoint_geojson',
          extensions.st_asgeojson(extensions.st_transform(x.canonical_endpoint,4326),7)::jsonb,
        'bridge_field_endpoint_geojson',
          extensions.st_asgeojson(extensions.st_transform(x.field_endpoint,4326),7)::jsonb,
        'topology_snap_tolerance_m',0.1,
        'topology_snap_scope','combined canonical imagery plus cleaned field-GNSS presentation plus explicit bridge',
        'merge_method','explicit_endpoint_bridge_plus_self_snap_0_1m_plus_st_unaryunion_v1',
        'connected_cluster_count',x.cluster_count,
        'unified_length_m',round(x.unified_length_m::numeric,1),
        'unified_component_count',x.unified_component_count,
        'raw_field_gnss_preserved',true
      )
    ),
  notes=o.notes || ' On 2026-09-20 the cleaned operator-reviewed field-GNSS trail presentation was promoted into this canonical trail network. The visible 14.35 m imagery/GNSS endpoint gap was explicitly operator-confirmed and bridged. A 0.1 m topology snap was applied only to collapse millimeter-scale junction artifacts before noding. Raw GPX and classified field observations remain preserved as provenance.',
  geometry=x.geometry_4326,
  updated_at=now()
from _fw_unified_trail_v1 x
where o.id=x.canonical_id;

update farm_watch.property_operator_observations_v1 o
set
  source_context=jsonb_set(
    o.source_context,
    '{presentation_v1}',
    coalesce(o.source_context->'presentation_v1','{}'::jsonb)
    || jsonb_build_object(
      'status','hidden',
      'reason','promoted_to_canonical_trail_network',
      'canonical_path_key','flat-creek-phase3-image-trails',
      'canonical_feature_subclass','operator_confirmed_trail_network',
      'canonical_geometry_basis','operator_merged_phase3_imagery_field_gnss_v1',
      'promotion_local_date','2026-09-20',
      'raw_classified_geometry_preserved',true
    ),
    true
  ),
  notes=o.notes || ' Cleaned presentation geometry has been promoted into the canonical Flat Creek trail network and is no longer rendered as a separate field-GPS trail layer. Raw GPX and classified geometry remain active field evidence.',
  updated_at=now()
from _fw_unified_trail_v1 x
where o.id=x.field_observation_id;

commit;
