create or replace function public.farm_watch_get_access_features_v1_internal(
  p_slug text,
  p_buffer_m integer default 1000
)
returns jsonb
language sql
stable
security definer
set search_path = 'pg_catalog'
as $$
  with property as (
    select p.boundary
    from farm_watch.properties p
    where p.slug = p_slug
      and p.status = 'active'
      and p.boundary is not null
    limit 1
  ),
  bounded as (
    select
      s.id,
      s.feature_class,
      s.feature_subclass,
      s.name,
      s.access_tag,
      s.surface_tag,
      s.service_tag,
      s.drivable,
      s.staging_candidate,
      s.routing_barrier,
      s.access_point,
      s.source_confidence,
      extensions.st_distance(s.geometry::extensions.geography, property.boundary::extensions.geography) as distance_m,
      s.geometry
    from decisioning.site_access_features s
    cross join property
    where s.geometry is not null
      and extensions.st_dwithin(
        s.geometry::extensions.geography,
        property.boundary::extensions.geography,
        least(greatest(coalesce(p_buffer_m, 1000), 0), 1500)
      )
    order by extensions.st_distance(s.geometry::extensions.geography, property.boundary::extensions.geography), s.id
    limit 100
  )
  select jsonb_build_object(
    'type', 'FeatureCollection',
    'features', coalesce(
      jsonb_agg(
        jsonb_build_object(
          'type', 'Feature',
          'id', b.id,
          'geometry', extensions.st_asgeojson(b.geometry, 6)::jsonb,
          'properties', jsonb_strip_nulls(jsonb_build_object(
            'feature_class', b.feature_class,
            'feature_subclass', b.feature_subclass,
            'name', nullif(b.name, ''),
            'access_tag', b.access_tag,
            'surface_tag', b.surface_tag,
            'service_tag', b.service_tag,
            'drivable', b.drivable,
            'staging_candidate', b.staging_candidate,
            'routing_barrier', b.routing_barrier,
            'access_point', b.access_point,
            'source_confidence', b.source_confidence,
            'distance_m', round(b.distance_m::numeric, 1)
          ))
        )
        order by b.distance_m, b.id
      ),
      '[]'::jsonb
    )
  )
  from bounded b;
$$;

revoke all on function public.farm_watch_get_access_features_v1_internal(text, integer) from public, anon, authenticated;
grant execute on function public.farm_watch_get_access_features_v1_internal(text, integer) to postgres, service_role;
