-- Bounded, developer-only contract for the third Scout sandbox opportunity type.
-- This contract is intentionally permit-native because Scout has no verified
-- construction-project identity link for the selected Ohio EPA record.
create or replace function public.scout_get_component_sandbox_swppp_site_map_v1_internal()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $function$
  with target as (
    select
      e.source_native_id,
      e.facility_name,
      e.registry_id,
      e.permit_status_desc,
      e.permit_type_desc,
      e.master_permit_number,
      e.issue_date,
      e.effective_date,
      e.expiration_date,
      e.termination_date,
      e.storm_water_area_acres,
      e.last_seen_at,
      e.location,
      e.attributes,
      s.slug as source_slug,
      s.name as source_name,
      s.authority as source_authority,
      s.authority_level as source_authority_level,
      s.homepage_url as source_url
    from compliance.construction_stormwater_evidence as e
    join ingest.sources as s
      on s.id = e.source_id
    where e.source_native_id = 'ohio-epa:1GC10896*AG'
      and s.slug = 'ohio-epa-npdes-construction'
      and e.facility_name = 'HAM-Brent Spence Project (PID 116649)'
      and e.registry_id = 'OHGC18548'
      and e.source_present is true
      and e.permit_status_desc = 'ACTIVE'
      and e.permit_type_desc = 'CONSTRUCTION_STORMWATER'
      and e.termination_date is null
      and e.expiration_date >= current_date
      and e.storm_water_area_acres = 135
      and e.location is not null
      and extensions.st_geometrytype(e.location::extensions.geometry) = 'ST_Point'
      and e.last_seen_at >= (pg_catalog.now() - interval '45 days')
    limit 1
  )
  select pg_catalog.jsonb_build_object(
    'contract_version', 'swppp_site_map_v1',
    'opportunity_type', 'swppp_site',
    'candidate_key', 'swppp_site:' || t.source_native_id,
    'site_name', t.facility_name,
    'location_label', pg_catalog.concat(t.attributes ->> 'county', ' County, Ohio'),
    'project_reference', 'PID 116649',
    'site_point', pg_catalog.jsonb_build_object(
      'lon', extensions.st_x(t.location::extensions.geometry),
      'lat', extensions.st_y(t.location::extensions.geometry),
      'geometry_type', 'Point',
      'semantics', 'authoritative_permit_location_point',
      'guardrail', 'The Ohio EPA record supplies a location point only. It is not a project boundary, disturbance polygon, parcel boundary, ownership boundary, or site-access area.'
    ),
    'permit', pg_catalog.jsonb_build_object(
      'evidence_status', 'active_documented_state_construction_permit',
      'status', t.permit_status_desc,
      'type', t.permit_type_desc,
      'category', t.attributes ->> 'permit_category',
      'permit_number', pg_catalog.replace(t.source_native_id, 'ohio-epa:', ''),
      'registry_id', t.registry_id,
      'master_permit_number', t.master_permit_number,
      'issue_date', t.issue_date,
      'effective_date', t.effective_date,
      'expiration_date', t.expiration_date,
      'termination_date', t.termination_date,
      'documented_total_acres', t.storm_water_area_acres,
      'acreage_semantics', t.attributes ->> 'disturbance_semantics'
    ),
    'source', pg_catalog.jsonb_build_object(
      'slug', t.source_slug,
      'name', t.source_name,
      'authority', t.source_authority,
      'authority_level', t.source_authority_level,
      'source_native_id', t.source_native_id,
      'source_url', t.source_url,
      'last_seen_at', t.last_seen_at
    ),
    'buyer', pg_catalog.jsonb_build_object(
      'classification', 'unresolved',
      'organization_id', null,
      'guardrail', 'Scout has not resolved a project owner, developer, contracting agency, buyer, or contact route for this permit record.'
    ),
    'why_investigate', 'Ohio EPA documents an active construction-stormwater permit with 135 total permit acres and a project identifier; verify present project activity, SWPPP documentation needs, contracting path, and responsible organization.',
    'guardrail', 'Construction-stormwater permit evidence identifies a potentially relevant active site or compliance/documentation need, but it is not proof of an active procurement opportunity, buyer intent, current service need, site access, ownership, or contract availability.'
  )
  from target as t;
$function$;

revoke all on function public.scout_get_component_sandbox_swppp_site_map_v1_internal() from public;
revoke all on function public.scout_get_component_sandbox_swppp_site_map_v1_internal() from anon;
revoke all on function public.scout_get_component_sandbox_swppp_site_map_v1_internal() from authenticated;
grant execute on function public.scout_get_component_sandbox_swppp_site_map_v1_internal() to service_role;
