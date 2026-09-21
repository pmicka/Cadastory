begin;

create or replace function public.farm_watch_get_landscape_raster_domains_v1_internal(
  p_slug text
)
returns jsonb
language sql
stable
security definer
set search_path = 'pg_catalog'
as $$
  select farm_watch.farm_watch_get_landscape_raster_domains_v1_internal(p_slug);
$$;

create or replace function public.farm_watch_get_landscape_physical_context_v1_internal(
  p_slug text
)
returns jsonb
language sql
stable
security definer
set search_path = 'pg_catalog'
as $$
  select farm_watch.farm_watch_get_landscape_physical_context_v1_internal(p_slug);
$$;

create or replace function public.farm_watch_upsert_landscape_physical_context_v1_internal(
  p_slug text,
  p_status text,
  p_context jsonb,
  p_retrieved_at timestamptz default now(),
  p_last_error text default null
)
returns jsonb
language sql
security definer
set search_path = 'pg_catalog'
as $$
  select farm_watch.farm_watch_upsert_landscape_physical_context_v1_internal(
    p_slug,
    p_status,
    p_context,
    p_retrieved_at,
    p_last_error
  );
$$;

revoke all on function public.farm_watch_get_landscape_raster_domains_v1_internal(text)
from public, anon, authenticated;
revoke all on function public.farm_watch_get_landscape_physical_context_v1_internal(text)
from public, anon, authenticated;
revoke all on function public.farm_watch_upsert_landscape_physical_context_v1_internal(text,text,jsonb,timestamptz,text)
from public, anon, authenticated;

grant execute on function public.farm_watch_get_landscape_raster_domains_v1_internal(text)
to service_role;
grant execute on function public.farm_watch_get_landscape_physical_context_v1_internal(text)
to service_role;
grant execute on function public.farm_watch_upsert_landscape_physical_context_v1_internal(text,text,jsonb,timestamptz,text)
to service_role;

commit;
