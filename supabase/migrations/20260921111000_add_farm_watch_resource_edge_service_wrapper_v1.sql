begin;

create or replace function public.farm_watch_get_resource_edge_context_v1_internal(
  p_slug text,
  p_include_geometry boolean default false
)
returns jsonb
language sql
stable
security definer
set search_path = 'pg_catalog'
as $$
  select farm_watch.farm_watch_get_resource_edge_context_v1_internal(
    p_slug,
    p_include_geometry
  );
$$;

revoke all on function public.farm_watch_get_resource_edge_context_v1_internal(text,boolean)
from public, anon, authenticated;
grant execute on function public.farm_watch_get_resource_edge_context_v1_internal(text,boolean)
to service_role;

commit;
