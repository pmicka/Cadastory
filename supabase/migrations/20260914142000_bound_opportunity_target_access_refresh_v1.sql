-- Batch 2: bound the opportunity target/access normalization refresh.
--
-- scout.v_opportunity_candidates and the access-readiness/context views are
-- intentionally rich global surfaces. Re-evaluating them multiple times inside
-- one full refresh pushed the hourly job past its 120s statement timeout.
-- Snapshot each heavyweight input once per transaction, index the temporary
-- relations, and reuse them without changing the durable output contracts.

create or replace function scout.refresh_opportunity_target_access_facts()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_targets integer;
  v_access integer;
  v_now timestamptz := clock_timestamp();
begin
  drop table if exists pg_temp.scout_refresh_candidates;
  drop table if exists pg_temp.scout_refresh_field_owner_links;
  drop table if exists pg_temp.scout_refresh_access_readiness;
  drop table if exists pg_temp.scout_refresh_target_access;

  create temporary table scout_refresh_candidates on commit drop as
  select *
  from scout.v_opportunity_candidates;

  create index scout_refresh_candidates_candidate_key_idx
    on pg_temp.scout_refresh_candidates(candidate_key);
  create index scout_refresh_candidates_source_idx
    on pg_temp.scout_refresh_candidates(source_kind, subject_type, source_id);
  analyze pg_temp.scout_refresh_candidates;

  create temporary table scout_refresh_field_owner_links on commit drop as
  select field_id, candidate_id, confidence, overlap_acres
  from agriculture.v_resolved_field_owner_links;

  create index scout_refresh_field_owner_links_candidate_idx
    on pg_temp.scout_refresh_field_owner_links(candidate_id, confidence desc, overlap_acres desc);
  analyze pg_temp.scout_refresh_field_owner_links;

  create temporary table scout_refresh_access_readiness on commit drop as
  select *
  from decisioning.v_service_access_target_readiness;

  create index scout_refresh_access_readiness_service_idx
    on pg_temp.scout_refresh_access_readiness(service_type_id);
  analyze pg_temp.scout_refresh_access_readiness;

  delete from scout.opportunity_service_access;
  delete from scout.opportunity_target_identities;

  insert into scout.opportunity_target_identities(
    candidate_key,source_kind,source_id,subject_type,subject_key,target_class,canonical_namespace,canonical_asset_id,stable_external_key,target_name,organization_id,
    resolution_status,identity_basis,confidence,operational_target_key,operational_target_type,operational_target_resolution,access_applicability,location_available,observed_at,last_normalized_at
  )
  select c.candidate_key,c.source_kind,c.source_id,c.subject_type,c.subject_key,r.target_class,r.canonical_namespace,
    case r.resolution_mode
      when 'direct_source_uuid' then c.source_id
      when 'building_source_record' then c.source_id
      when 'construction_window_to_project' then cp.project_id
      when 'farm_candidate_with_field' then c.source_id
      else null
    end as canonical_asset_id,
    c.subject_key as stable_external_key,
    c.display_name,c.organization_id,
    case
      when r.resolution_mode in ('direct_source_uuid','building_source_record') and c.source_id is not null then case when r.resolution_mode='farm_candidate_with_field' then 'canonical_account' else 'canonical_asset' end
      when r.resolution_mode='construction_window_to_project' and cp.project_id is not null then 'canonical_asset'
      when r.resolution_mode='farm_candidate_with_field' and c.source_id is not null then 'canonical_account'
      when r.resolution_mode='organization_scope' then 'organization_scope'
      when r.resolution_mode='area_context' then 'area_context'
      when r.resolution_mode='source_context' then 'source_context'
      when c.subject_type='address' then 'site_address'
      when nullif(c.subject_key,'') is not null then 'stable_external_key'
      else 'unresolved'
    end,
    case
      when r.resolution_mode='construction_window_to_project' and cp.project_id is not null then 'construction_service_window.project_id'
      when r.resolution_mode='building_source_record' then 'building_source_record_id'
      when r.resolution_mode='direct_source_uuid' then 'candidate_source_id'
      when r.resolution_mode='farm_candidate_with_field' then case when ff.field_id is not null then 'farm_candidate_plus_resolved_field_link' else 'farm_candidate' end
      when r.resolution_mode='solar_plant_with_representative_generator' then case when sg.generator_id is not null then 'eia_plant_id_plus_representative_generator' else 'eia_plant_id' end
      when r.resolution_mode='organization_scope' then 'candidate_organization_scope'
      when r.resolution_mode='source_context' then 'candidate_subject_context'
      else 'stable_subject_key'
    end,
    r.identity_confidence,
    case
      when r.resolution_mode='building_source_record' and c.source_id is not null then 'building:'||c.source_id::text
      when c.source_kind='telecom_change' then 'telecom:'||c.subject_key
      when c.source_kind='water_tank_maintenance' and c.source_id is not null then 'water_tank:'||c.source_id::text
      when c.source_kind='rail_crossing_context' then 'rail_crossing:'||c.subject_key
      when r.resolution_mode='construction_window_to_project' and cp.project_id is not null then 'construction_project:'||cp.project_id::text
      when r.resolution_mode='farm_candidate_with_field' and ff.field_id is not null then 'field:'||ff.field_id::text
      when r.resolution_mode='solar_plant_with_representative_generator' and sg.generator_id is not null then 'solar_generator:'||c.subject_key||':'||sg.generator_id
      else null
    end,
    case
      when r.resolution_mode='building_source_record' then 'building'
      when c.source_kind='telecom_change' then 'telecom_structure'
      when c.source_kind='water_tank_maintenance' then 'water_tank'
      when c.source_kind='rail_crossing_context' then 'rail_crossing'
      when r.resolution_mode='construction_window_to_project' then 'construction_project'
      when r.resolution_mode='farm_candidate_with_field' and ff.field_id is not null then 'field'
      when r.resolution_mode='solar_plant_with_representative_generator' and sg.generator_id is not null then 'solar_generator'
      else null
    end,
    case
      when r.resolution_mode in ('building_source_record','construction_window_to_project') then 'exact_operational_target'
      when c.source_kind in ('telecom_change','water_tank_maintenance','rail_crossing_context') then 'exact_operational_target'
      when r.resolution_mode='farm_candidate_with_field' and ff.field_id is not null then 'associated_operating_field'
      when r.resolution_mode='solar_plant_with_representative_generator' and sg.generator_id is not null then 'representative_site_record'
      else null
    end,
    r.access_applicability,
    c.location is not null,c.observed_at,v_now
  from pg_temp.scout_refresh_candidates c
  join scout.opportunity_target_rules r on r.source_kind=c.source_kind and r.subject_type=c.subject_type and r.active
  left join lateral (
    select w.project_id from intelligence.construction_service_windows w
    where r.resolution_mode='construction_window_to_project' and w.id=c.source_id limit 1
  ) cp on true
  left join lateral (
    select rol.field_id
    from pg_temp.scout_refresh_field_owner_links rol
    join agriculture.field_boundaries fb on fb.id=rol.field_id and fb.geometry is not null
    where r.resolution_mode='farm_candidate_with_field' and rol.candidate_id=c.source_id
    order by rol.confidence desc nulls last, rol.overlap_acres desc nulls last, rol.field_id
    limit 1
  ) ff on true
  left join lateral (
    select s.generator_id
    from energy.v_solar_lifecycle_candidates s
    where r.resolution_mode='solar_plant_with_representative_generator' and s.plant_id=c.subject_key and s.can_open_inspection_window
    order by case lower(coalesce(s.timing_strength,'')) when 'very_high' then 4 when 'high' then 3 when 'strong' then 3 when 'medium' then 2 else 1 end desc,
             s.updated_at desc nulls last,s.generator_id
    limit 1
  ) sg on true;
  get diagnostics v_targets=row_count;

  create temporary table scout_refresh_target_access on commit drop as
  select a.*
  from decisioning.v_operational_target_access_context a
  join (
    select distinct operational_target_key as target_key
    from scout.opportunity_target_identities
    where operational_target_key is not null
  ) k on k.target_key=a.target_key;

  create index scout_refresh_target_access_target_idx
    on pg_temp.scout_refresh_target_access(target_key);
  analyze pg_temp.scout_refresh_target_access;

  insert into scout.opportunity_service_access(
    candidate_key,service_type_id,operational_target_key,operational_target_type,access_applicability,site_enrichment_status,service_geometry_status,access_decision_state,
    setup_class,mobility_pattern,support_footprint,parking_need,requires_vehicle_access,trailer_or_large_support,field_entrance_required,refill_turnaround_required,
    open_sky_launch_required,surface_area_validation_required,linked_feature_count,road_count,service_road_count,driveway_count,parking_area_count,paved_area_count,barrier_count,gate_count,
    nearest_road_m,nearest_driveway_m,nearest_staging_m,nearest_gate_m,nearest_barrier_m,authorization_status,access_permission_required,live_job_validation_required,access_unknowns,
    last_access_scan_at,access_source_timestamp,last_normalized_at
  )
  select t.candidate_key,st.id,t.operational_target_key,t.operational_target_type,t.access_applicability,
    case
      when t.access_applicability='restricted_location' then 'restricted_location'
      when t.access_applicability='organization_scope' then 'site_not_resolved'
      when t.access_applicability='area_context' then 'context_only'
      when t.access_applicability='not_applicable' then 'not_applicable'
      when t.operational_target_key is null then 'target_not_linked'
      when a.target_key is null then 'operational_target_missing'
      else a.site_access_status
    end,
    rd.readiness_status,
    case
      when t.access_applicability='restricted_location' then 'authorized_location_required'
      when t.access_applicability='organization_scope' then 'site_resolution_required'
      when t.access_applicability='area_context' then 'site_or_area_resolution_required'
      when t.access_applicability='not_applicable' then 'not_applicable'
      when t.operational_target_key is null then 'target_linkage_required'
      when a.target_key is null then 'target_geometry_or_registration_missing'
      when a.site_access_status='mapped' then 'mapped_access_requires_job_validation'
      when a.site_access_status='unscanned' then 'access_enrichment_pending'
      when a.site_access_status='scan_failed' then 'access_enrichment_failed'
      when a.site_access_status='scanned_no_mapped_features' then 'no_mapped_features_not_no_access'
      else 'access_verification_required'
    end,
    p.setup_class,p.mobility_pattern,p.support_footprint,p.parking_need,p.requires_vehicle_access,p.trailer_or_large_support,p.field_entrance_required,p.refill_turnaround_required,
    p.open_sky_launch_required,p.surface_area_validation_required,
    coalesce(a.linked_feature_count,0),coalesce(a.road_count,0),coalesce(a.service_road_count,0),coalesce(a.driveway_count,0),coalesce(a.parking_area_count,0),coalesce(a.paved_area_count,0),
    coalesce(a.barrier_count,0),coalesce(a.gate_count,0),a.nearest_road_m,a.nearest_driveway_m,a.nearest_staging_m,a.nearest_gate_m,a.nearest_barrier_m,
    case when t.access_applicability='not_applicable' then 'not_assessed' else 'unknown' end,
    t.access_applicability <> 'not_applicable',true,
    array_remove(array[
      case when t.access_applicability='restricted_location' then 'Precise site or right-of-way geometry is intentionally unavailable; obtain the authorized location from the responsible operator before job planning.' end,
      case when t.access_applicability='organization_scope' then 'The exact facility or project site is not resolved, so site access cannot yet be assessed.' end,
      case when t.access_applicability='area_context' then 'The opportunity identifies an area/context rather than a dispatchable site; resolve the operating area before access planning.' end,
      case when t.access_applicability='physical_site' and t.operational_target_key is null then 'Scout has not yet linked this opportunity to an access-enrichment target.' end,
      case when a.site_access_status='unscanned' then 'Mapped site-access enrichment has not yet been run for this target.' end,
      case when a.site_access_status='scan_failed' then 'The latest mapped site-access enrichment attempt failed and must be retried before relying on mapped access context.' end,
      case when a.site_access_status='scanned_no_mapped_features' then 'No mapped access features were returned; this does not mean the site has no access.' end,
      case when a.site_access_status='mapped' then 'Mapped roads, gates, parking, paved areas or barriers are geographic evidence only; they do not establish permission, drivable condition, staging suitability or current availability.' end,
      case when rd.readiness_status in ('target_geometry_missing','corridor_segment_geometry_not_linked','field_boundary_geometry_missing') then rd.readiness_note end,
      case when t.access_applicability<>'not_applicable' then 'Customer/site authorization and current field conditions remain job-specific checks.' end
    ],null)::text[],
    a.last_access_scan_at,a.source_timestamp,v_now
  from scout.opportunity_target_identities t
  join pg_temp.scout_refresh_candidates c on c.candidate_key=t.candidate_key
  cross join lateral unnest(c.service_slugs) ss(slug)
  join commerce.service_types st on st.slug=ss.slug
  left join decisioning.service_access_profiles p on p.service_type_id=st.id
  left join pg_temp.scout_refresh_access_readiness rd on rd.service_type_id=st.id
  left join pg_temp.scout_refresh_target_access a on a.target_key=t.operational_target_key;
  get diagnostics v_access=row_count;

  return jsonb_build_object('refreshed_at',v_now,'target_identities',v_targets,'service_access_rows',v_access);
end
$function$;

comment on function scout.refresh_opportunity_target_access_facts() is
  'Rebuilds normalized opportunity target identities and service-access facts from one transaction-scoped snapshot of heavyweight candidate/access inputs.';