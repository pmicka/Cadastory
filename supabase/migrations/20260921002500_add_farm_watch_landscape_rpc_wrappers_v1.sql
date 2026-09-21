begin;

create or replace function public.farm_watch_get_landscape_domain_v1_internal(
  p_slug text
) returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select farm_watch.farm_watch_get_landscape_domain_v1_internal(p_slug);
$$;

revoke all on function public.farm_watch_get_landscape_domain_v1_internal(text)
  from public, anon, authenticated;
grant execute on function public.farm_watch_get_landscape_domain_v1_internal(text)
  to service_role;

create or replace function public.farm_watch_get_operator_observations_v1_internal(
  p_slug text,
  p_observation_kind text default null
) returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select farm_watch.farm_watch_get_operator_observations_v1_internal(
    p_slug,
    p_observation_kind
  );
$$;

revoke all on function public.farm_watch_get_operator_observations_v1_internal(text,text)
  from public, anon, authenticated;
grant execute on function public.farm_watch_get_operator_observations_v1_internal(text,text)
  to service_role;

commit;
