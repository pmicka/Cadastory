-- Scout site-access building compatibility bridge sync v1
-- The local snapshot worker writes canonical target links into site_access_feature_targets.
-- Existing building cleaning/staging views consume site_access_feature_buildings.
-- Keep the latter synchronized as a compatibility projection rather than duplicating access logic in each view.

create or replace function decisioning.refresh_site_access_feature_buildings_from_targets()
returns jsonb
language plpgsql
security invoker
set search_path to ''
as $$
declare
  v_upserted integer:=0;
  v_deleted integer:=0;
  v_buildings integer:=0;
  v_snapshot_source_id uuid;
begin
  select id into v_snapshot_source_id
  from ingest.sources
  where slug='openstreetmap-geofabrik-access-snapshot';

  insert into decisioning.site_access_feature_buildings(
    feature_id,building_source_record_id,distance_to_building_m,relation,first_linked_at,last_linked_at
  )
  select l.feature_id,b.source_record_id,l.distance_to_target_m,l.relation,coalesce(l.last_linked_at,now()),coalesce(l.last_linked_at,now())
  from decisioning.site_access_feature_targets l
  join decisioning.building_candidates b on l.target_key='building:'||b.source_record_id::text
  where l.target_type='building'
  on conflict(feature_id,building_source_record_id) do update
  set distance_to_building_m=excluded.distance_to_building_m,
      relation=excluded.relation,
      last_linked_at=excluded.last_linked_at;
  get diagnostics v_upserted=row_count;

  if v_snapshot_source_id is not null then
    delete from decisioning.site_access_feature_buildings lb
    using decisioning.site_access_features f
    where lb.feature_id=f.id
      and f.source_id=v_snapshot_source_id
      and not exists(
        select 1
        from decisioning.site_access_feature_targets l
        where l.feature_id=lb.feature_id
          and l.target_type='building'
          and l.target_key='building:'||lb.building_source_record_id::text
      );
    get diagnostics v_deleted=row_count;
  end if;

  select count(distinct building_source_record_id) into v_buildings
  from decisioning.site_access_feature_buildings;

  return jsonb_build_object(
    'upserted',v_upserted,
    'deleted_stale_snapshot_links',v_deleted,
    'linked_buildings',v_buildings
  );
end;
$$;

-- Ensure materialization consumes the canonical local-snapshot links via the compatibility bridge first.
create or replace function decisioning.refresh_cleaning_access_scenarios(p_limit_per_building integer default 3)
returns jsonb
language plpgsql
security invoker
set search_path to ''
as $$
declare
  v_limit integer:=greatest(1,least(coalesce(p_limit_per_building,3),10));
  v_deleted integer:=0;
  v_upserted integer:=0;
  v_buildings integer:=0;
  v_bridge_sync jsonb;
begin
  v_bridge_sync:=decisioning.refresh_site_access_feature_buildings_from_targets();

  with ranked as (
    select h.*,
           row_number() over (
             partition by h.source_record_id
             order by
               case h.staging_hypothesis_strength when 'strong' then 3 when 'moderate' then 2 when 'weak' then 1 else 0 end desc,
               h.source_confidence desc nulls last,
               h.mapped_access_lower_bound_hose_ft asc nulls last,
               h.representative_ground_run_ft asc nulls last,
               h.access_feature_id
           ) as rn
    from decisioning.v_cleaning_hose_access_hypotheses h
    where h.mapped_access_lower_bound_hose_ft is not null
      and h.representative_ground_run_ft is not null
  ), keepers as (
    select source_record_id,'osm_access:'||access_feature_id::text as scenario_name
    from ranked where rn<=v_limit
  )
  delete from decisioning.cleaning_access_scenarios s
  where s.source_kind='derived'
    and s.provider_organization_id is null
    and s.attributes->>'materializer'='osm_cleaning_access_v1'
    and not exists(
      select 1 from keepers k
      where k.source_record_id=s.building_source_record_id and k.scenario_name=s.scenario_name
    );
  get diagnostics v_deleted=row_count;

  with ranked as (
    select h.*,
           row_number() over (
             partition by h.source_record_id
             order by
               case h.staging_hypothesis_strength when 'strong' then 3 when 'moderate' then 2 when 'weak' then 1 else 0 end desc,
               h.source_confidence desc nulls last,
               h.mapped_access_lower_bound_hose_ft asc nulls last,
               h.representative_ground_run_ft asc nulls last,
               h.access_feature_id
           ) as rn
    from decisioning.v_cleaning_hose_access_hypotheses h
    where h.mapped_access_lower_bound_hose_ft is not null
      and h.representative_ground_run_ft is not null
  )
  insert into decisioning.cleaning_access_scenarios(
    building_source_record_id,provider_organization_id,scenario_name,facade_label,facade_axis,
    staging_point,launch_point,ground_run_ft_override,routing_detour_ft,access_class,access_status,
    obstacle_flags,source_kind,confidence,notes,attributes,updated_at
  )
  select
    r.source_record_id,null,'osm_access:'||r.access_feature_id::text,
    coalesce(nullif(r.staging_feature_name,''),r.feature_class||coalesce('/'||nullif(r.feature_subclass,''),'')),
    'unknown',r.candidate_point,null,r.representative_ground_run_ft,0,'unknown','estimated',
    array_remove(array[
      case when coalesce(r.barrier_count,0)>0 then 'mapped_barriers_present' end,
      case when coalesce(r.gate_count,0)>0 then 'mapped_gates_present' end
    ]::text[],null),
    'derived',
    least(0.95::numeric,coalesce(r.source_confidence,0.5::numeric) *
      case r.staging_hypothesis_strength when 'strong' then 1.0 when 'moderate' then 0.9 when 'weak' then 0.8 else 0.7 end),
    r.estimate_caveat,
    jsonb_build_object(
      'materializer','osm_cleaning_access_v1','hypothesis_rank',r.rn,'access_feature_id',r.access_feature_id,
      'feature_class',r.feature_class,'feature_subclass',r.feature_subclass,'staging_feature_name',r.staging_feature_name,
      'staging_hypothesis_strength',r.staging_hypothesis_strength,'candidate_status',r.candidate_status,
      'source_confidence',r.source_confidence,'minimum_edge_distance_ft',r.minimum_edge_distance_ft,
      'representative_ground_run_ft',r.representative_ground_run_ft,'mapped_access_lower_bound_hose_ft',r.mapped_access_lower_bound_hose_ft,
      'barrier_count',r.barrier_count,'gate_count',r.gate_count,'nearest_barrier_m',r.nearest_barrier_m,'nearest_gate_m',r.nearest_gate_m,
      'estimate_basis',r.estimate_basis,'estimate_caveat',r.estimate_caveat
    ),clock_timestamp()
  from ranked r
  where r.rn<=v_limit
  on conflict (building_source_record_id,scenario_name)
    where source_kind='derived' and provider_organization_id is null
  do update set
    facade_label=excluded.facade_label,
    facade_axis=excluded.facade_axis,
    staging_point=excluded.staging_point,
    ground_run_ft_override=excluded.ground_run_ft_override,
    routing_detour_ft=excluded.routing_detour_ft,
    access_class=excluded.access_class,
    access_status=excluded.access_status,
    obstacle_flags=excluded.obstacle_flags,
    confidence=excluded.confidence,
    notes=excluded.notes,
    attributes=excluded.attributes,
    updated_at=clock_timestamp();
  get diagnostics v_upserted=row_count;

  select count(distinct building_source_record_id) into v_buildings
  from decisioning.cleaning_access_scenarios
  where source_kind='derived' and provider_organization_id is null
    and attributes->>'materializer'='osm_cleaning_access_v1';

  return jsonb_build_object(
    'materializer','osm_cleaning_access_v1',
    'limit_per_building',v_limit,
    'bridge_sync',v_bridge_sync,
    'deleted_stale',v_deleted,
    'upserted',v_upserted,
    'materialized_buildings',v_buildings
  );
end;
$$;
