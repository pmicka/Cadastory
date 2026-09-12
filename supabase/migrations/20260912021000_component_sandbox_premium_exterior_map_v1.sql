create or replace function public.scout_get_component_sandbox_premium_exterior_map_v1_internal()
returns jsonb
language sql
stable
security definer
set search_path = 'pg_catalog'
as $function$
  with target as (
    select
      p.id,
      p.name,
      coalesce(nullif(pg_catalog.btrim(p.address_text), ''), nullif(pg_catalog.btrim(p.property_address), '')) as address,
      p.location as target_location,
      p.building_source_record_id,
      p.building_source_slug,
      p.building_match_distance_m,
      p.footprint_sqft,
      p.evidence,
      bc.geometry as footprint_geometry,
      rr.source_native_id as footprint_source_native_id,
      rr.raw_payload as footprint_raw_payload,
      s.name as footprint_source_name
    from intelligence.v_premium_exterior_opportunities as p
    join decisioning.building_candidates as bc
      on bc.source_record_id = p.building_source_record_id
    join ingest.raw_records as rr
      on rr.id = bc.source_record_id
    join ingest.sources as s
      on s.id = rr.source_id
    where p.id = '0edb82cd-7487-4f72-a036-8faa8a40bd54'::uuid
      and p.rankable is true
      and p.source_present is true
      and p.location is not null
      and bc.geometry is not null
      and p.evidence->>'building_link_status' = 'reconciled_existing_evidence'
    limit 1
  )
  select pg_catalog.jsonb_build_object(
    'contract_version', 'single_site_map_v1',
    'opportunity_type', 'premium_exterior',
    'opportunity_id', t.id,
    'name', t.name,
    'address', t.address,
    'site_point', pg_catalog.jsonb_build_object(
      'lon', extensions.st_x(t.target_location::extensions.geometry),
      'lat', extensions.st_y(t.target_location::extensions.geometry),
      'source', 'premium_exterior_target_geocode',
      'method', nullif(t.evidence->>'geocode_method', '')
    ),
    'footprint', pg_catalog.jsonb_build_object(
      'geometry', extensions.st_asgeojson(t.footprint_geometry, 6)::jsonb,
      'bounds', pg_catalog.jsonb_build_object(
        'west', extensions.st_xmin(extensions.box2d(t.footprint_geometry)),
        'south', extensions.st_ymin(extensions.box2d(t.footprint_geometry)),
        'east', extensions.st_xmax(extensions.box2d(t.footprint_geometry)),
        'north', extensions.st_ymax(extensions.box2d(t.footprint_geometry))
      ),
      'footprint_sqft', t.footprint_sqft,
      'source', pg_catalog.jsonb_build_object(
        'slug', t.building_source_slug,
        'name', t.footprint_source_name,
        'native_id', t.footprint_source_native_id,
        'image_date', case
          when nullif(t.footprint_raw_payload #>> '{properties,IMAGE_DATE}', '') ~ '^[0-9]+([.][0-9]+)?$'
          then pg_catalog.to_char(
            pg_catalog.to_timestamp(((t.footprint_raw_payload #>> '{properties,IMAGE_DATE}')::double precision) / 1000.0) at time zone 'UTC',
            'YYYY-MM-DD'
          )
          else null
        end,
        'validation_method', nullif(t.footprint_raw_payload #>> '{properties,VAL_METHOD}', '')
      )
    ),
    'linkage', pg_catalog.jsonb_build_object(
      'status', t.evidence->>'building_link_status',
      'basis', t.evidence->>'building_link_basis',
      'guardrail', t.evidence->>'building_link_guardrail',
      'target_to_footprint_m', extensions.st_distance(t.target_location, t.footprint_geometry::extensions.geography),
      'stored_match_distance_m', t.building_match_distance_m
    )
  )
  from target as t;
$function$;

revoke all on function public.scout_get_component_sandbox_premium_exterior_map_v1_internal() from public;
revoke execute on function public.scout_get_component_sandbox_premium_exterior_map_v1_internal() from anon, authenticated;
grant execute on function public.scout_get_component_sandbox_premium_exterior_map_v1_internal() to service_role;

comment on function public.scout_get_component_sandbox_premium_exterior_map_v1_internal() is
  'Internal service-role-only single-site map contract for the bounded PNC Tower premium-exterior sandbox exemplar. No portfolio, clustering, territory, contact, or renderer behavior.';

revoke execute on function public.scout_get_component_sandbox_map_targets_internal(integer, integer) from service_role, anon, authenticated, public;
revoke execute on function public.scout_get_component_sandbox_map_targets_v2_internal(integer, integer) from service_role, anon, authenticated, public;
revoke execute on function public.scout_get_component_sandbox_map_targets_v3_internal(integer, integer) from service_role, anon, authenticated, public;

comment on function public.scout_get_component_sandbox_map_targets_internal(integer, integer) is
  'LEGACY REFERENCE ONLY. Do not invoke from current Scout MCP Apps surfaces. Generalized map-target contract retained only for prior-iteration archaeology.';
comment on function public.scout_get_component_sandbox_map_targets_v2_internal(integer, integer) is
  'LEGACY REFERENCE ONLY. Do not invoke from current Scout MCP Apps surfaces. Generalized portfolio/territory map contract retained only for prior-iteration archaeology.';
comment on function public.scout_get_component_sandbox_map_targets_v3_internal(integer, integer) is
  'LEGACY REFERENCE ONLY. Do not invoke from current Scout MCP Apps surfaces. Generalized map/contact contract retained only for prior-iteration archaeology.';
