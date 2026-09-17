create or replace function public.farm_watch_get_environment_anchor_v1_internal(p_slug text)
returns jsonb
language sql
security definer
set search_path = pg_catalog, public, farm_watch
as $$
  select farm_watch.farm_watch_get_environment_anchor_v1_internal(p_slug);
$$;

create or replace function public.farm_watch_get_environment_context_v1_internal(
  p_slug text,
  p_context_date date
)
returns jsonb
language sql
security definer
set search_path = pg_catalog, public, farm_watch
as $$
  select farm_watch.farm_watch_get_environment_context_v1_internal(p_slug, p_context_date);
$$;

create or replace function public.farm_watch_upsert_environment_context_v1_internal(
  p_slug text,
  p_context_date date,
  p_status text,
  p_context jsonb,
  p_retrieved_at timestamptz default now()
)
returns void
language sql
security definer
set search_path = pg_catalog, public, farm_watch
as $$
  select farm_watch.farm_watch_upsert_environment_context_v1_internal(
    p_slug,
    p_context_date,
    p_status,
    p_context,
    p_retrieved_at
  );
$$;

revoke all on function public.farm_watch_get_environment_anchor_v1_internal(text) from public, anon, authenticated;
revoke all on function public.farm_watch_get_environment_context_v1_internal(text, date) from public, anon, authenticated;
revoke all on function public.farm_watch_upsert_environment_context_v1_internal(text, date, text, jsonb, timestamptz) from public, anon, authenticated;

grant execute on function public.farm_watch_get_environment_anchor_v1_internal(text) to service_role;
grant execute on function public.farm_watch_get_environment_context_v1_internal(text, date) to service_role;
grant execute on function public.farm_watch_upsert_environment_context_v1_internal(text, date, text, jsonb, timestamptz) to service_role;
