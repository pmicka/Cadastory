create or replace function public.scout_get_component_sandbox_water_tank_map_v1_internal()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $function$
  with target as (
    select
      t.id,
      t.wris_fid,
      t.pwsid,
      t.tank_name,
      t.system_name,
      t.tank_type,
      t.capacity_gallons,
      t.construction_date,
      t.last_cleaning_date,
      t.last_inspection_date,
      t.out_of_service,
      t.location,
      rr.source_native_id,
      rr.source_url as registry_source_url,
      rr.retrieved_at,
      s.slug as source_slug,
      s.name as source_name,
      s.authority as source_authority,
      ge.morphology_class,
      ge.support_geometry,
      ge.cross_bracing_status,
      ge.support_leg_count,
      ge.evidence_kind as geometry_evidence_kind,
      ge.confidence as geometry_confidence,
      ge.source_url as geometry_source_url,
      ge.source_authority as geometry_source_authority,
      ge.observed_on as geometry_observed_on,
      ge.media_retained,
      gp.operator_cleaning_geometry_assessment,
      gp.operator_assessment_basis,
      p.id as project_id,
      p.pnum,
      p.project_status,
      p.purpose as project_purpose,
      p.other_purpose as project_other_purpose,
      p.match_method as project_match_method,
      p.match_distance_m as project_match_distance_m,
      p.source_modified_at as project_source_modified_at
    from water.tanks as t
    join ingest.raw_records as rr
      on rr.id = t.source_record_id
    join ingest.sources as s
      on s.id = rr.source_id
    join water.v_tank_geometry_profile as gp
      on gp.tank_id = t.id
    join lateral (
      select e.*
      from water.tank_geometry_evidence as e
      where e.tank_id = t.id
        and e.active is true
        and e.confidence >= 0.9
      order by
        case e.evidence_kind when 'engineering_document' then 0 when 'visual_review' then 1 else 2 end,
        e.confidence desc,
        e.observed_on desc nulls last,
        e.id
      limit 1
    ) as ge on true
    join lateral (
      select tp.*
      from water.tank_projects as tp
      where tp.matched_tank_id = t.id
        and tp.source_present is true
        and tp.project_status = 'REHAB'
      order by tp.source_modified_at desc nulls last, tp.id
      limit 1
    ) as p on true
    where t.wris_fid = '00AB7B0C8D56F05717FDFCF0B4000001'
      and t.pwsid = 'KY1140038'
      and t.tank_name = 'SOUTH PRESSURE ZONE TANK'
      and t.source_present is true
      and coalesce(t.out_of_service, false) is false
      and t.location is not null
      and gp.operator_cleaning_geometry_assessment = 'favorable'
      and gp.support_geometry = 'single_pedestal'
      and gp.cross_bracing_status = 'none'
      and gp.geometry_confidence >= 0.9
      and p.source_modified_at >= (pg_catalog.now() - interval '2 years')
    limit 1
  )
  select pg_catalog.jsonb_build_object(
    'contract_version', 'water_tank_single_site_map_v1',
    'opportunity_type', 'water_tank',
    'tank_id', t.id,
    'candidate_key', 'water_tank:' || t.id::text,
    'name', t.tank_name,
    'system_name', t.system_name,
    'site_point', pg_catalog.jsonb_build_object(
      'lon', extensions.st_x(t.location::extensions.geometry),
      'lat', extensions.st_y(t.location::extensions.geometry),
      'source', 'kentucky_wris_water_tank',
      'source_slug', t.source_slug,
      'source_name', t.source_name,
      'source_authority', t.source_authority,
      'source_native_id', t.source_native_id,
      'wris_fid', t.wris_fid,
      'pwsid', t.pwsid,
      'retrieved_at', t.retrieved_at
    ),
    'asset', pg_catalog.jsonb_build_object(
      'tank_type', t.tank_type,
      'capacity_gallons', t.capacity_gallons,
      'construction_date', t.construction_date,
      'last_cleaning_date', t.last_cleaning_date,
      'last_inspection_date', t.last_inspection_date,
      'out_of_service', t.out_of_service
    ),
    'geometry', pg_catalog.jsonb_build_object(
      'morphology_class', t.morphology_class,
      'support_geometry', t.support_geometry,
      'cross_bracing_status', t.cross_bracing_status,
      'support_leg_count', t.support_leg_count,
      'operator_assessment', t.operator_cleaning_geometry_assessment,
      'operator_assessment_basis', t.operator_assessment_basis,
      'evidence_kind', t.geometry_evidence_kind,
      'confidence', t.geometry_confidence,
      'source_authority', t.geometry_source_authority,
      'source_url', t.geometry_source_url,
      'observed_on', t.geometry_observed_on,
      'media_retained', t.media_retained,
      'guardrail', 'Morphology is evidence-backed, while cleaning favorability reflects trusted operator field expertise; verify site-specific access and current physical conditions before planning work.'
    ),
    'project_linkage', pg_catalog.jsonb_build_object(
      'project_id', t.project_id,
      'pnum', t.pnum,
      'status', t.project_status,
      'purpose', t.project_purpose,
      'other_purpose', t.project_other_purpose,
      'match_method', t.project_match_method,
      'match_distance_m', t.project_match_distance_m,
      'source_modified_at', t.project_source_modified_at,
      'guardrail', 'The linked REHAB / tank-improvements record is a current maintenance signal, not proof of an active cleaning procurement opportunity; verify current project scope, status, contracting path and buyer need before outreach.'
    )
  )
  from target as t;
$function$;

revoke all on function public.scout_get_component_sandbox_water_tank_map_v1_internal() from public;
revoke all on function public.scout_get_component_sandbox_water_tank_map_v1_internal() from anon;
revoke all on function public.scout_get_component_sandbox_water_tank_map_v1_internal() from authenticated;
grant execute on function public.scout_get_component_sandbox_water_tank_map_v1_internal() to service_role;
