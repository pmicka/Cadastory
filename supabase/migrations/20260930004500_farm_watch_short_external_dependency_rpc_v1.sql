begin;

create or replace function farm_watch.farm_watch_get_materialization_external_deps_v1_internal(
  p_product_kind text
)
returns jsonb
language sql
immutable
set search_path='pg_catalog','farm_watch'
as $$
  select coalesce(
    jsonb_agg(dep->>'key' order by dep->>'key'),
    '[]'::jsonb
  )
  from jsonb_array_elements(
    coalesce(
      farm_watch.farm_watch_materialization_dependency_contract_v1(p_product_kind)->'dependencies',
      '[]'::jsonb
    )
  ) dep
  where dep->>'kind'='external';
$$;

create or replace function public.farm_watch_get_materialization_external_deps_v1_internal(
  p_product_kind text
)
returns jsonb
language sql
immutable
security definer
set search_path='pg_catalog'
as $$
  select farm_watch.farm_watch_get_materialization_external_deps_v1_internal(
    p_product_kind
  );
$$;

revoke all on function farm_watch.farm_watch_get_materialization_external_deps_v1_internal(text)
  from public,anon,authenticated;
grant execute on function farm_watch.farm_watch_get_materialization_external_deps_v1_internal(text)
  to service_role;

revoke all on function public.farm_watch_get_materialization_external_deps_v1_internal(text)
  from public,anon,authenticated;
grant execute on function public.farm_watch_get_materialization_external_deps_v1_internal(text)
  to service_role;

comment on function public.farm_watch_get_materialization_external_deps_v1_internal(text) is
'PostgREST-safe short alias for the Farm Watch canonical external dependency lookup. The prior longer identifier exceeded PostgreSQL identifier length and was truncated in pg_proc.';

notify pgrst, 'reload schema';

commit;
