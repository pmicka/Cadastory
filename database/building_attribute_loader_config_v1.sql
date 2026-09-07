-- Building-attribute collectors should scan only where Scout has a canonical
-- building substrate to receive the evidence. This keeps Overture/OSM refreshes
-- bounded and automatically includes new states when canonical footprints are
-- added. It intentionally does not reuse the broader site-access AOI.

create or replace function public.internal_get_building_attribute_loader_config()
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','extensions','ingest','decisioning'
as $function$
declare
  v_regions jsonb;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service_role required';
  end if;

  with extents as (
    select
      upper(bc.state_code) as state_code,
      count(*)::int as candidate_count,
      st_extent(bc.geometry) as extent
    from decisioning.building_candidates bc
    where bc.geometry is not null
      and nullif(bc.state_code,'') is not null
    group by upper(bc.state_code)
  ), configured as (
    select
      r.region_slug,
      r.state_code,
      r.region_name,
      r.upstream_pbf_url as pbf_url,
      e.candidate_count,
      jsonb_build_array(
        st_xmin(e.extent)-0.002,
        st_ymin(e.extent)-0.002,
        st_xmax(e.extent)+0.002,
        st_ymax(e.extent)+0.002
      ) as bbox
    from extents e
    join decisioning.site_access_snapshot_regions r
      on upper(r.state_code)=e.state_code
    where r.enabled is true
      and r.upstream_pbf_url is not null
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'region_slug',region_slug,
        'state_code',state_code,
        'region_name',region_name,
        'pbf_url',pbf_url,
        'candidate_count',candidate_count,
        'bbox',bbox
      )
      order by region_slug
    ),
    '[]'::jsonb
  ) into v_regions
  from configured;

  return jsonb_build_object(
    'basis','canonical_building_candidate_extents',
    'padding_degrees',0.002,
    'regions',v_regions
  );
end;
$function$;

revoke all on function public.internal_get_building_attribute_loader_config() from public,anon,authenticated;
grant execute on function public.internal_get_building_attribute_loader_config() to service_role;

comment on function public.internal_get_building_attribute_loader_config() is
  'Service-role-only configuration for building-attribute collectors. AOIs are derived from the current canonical building candidate substrate, so states without canonical footprints are not bulk-enriched or retained.';
