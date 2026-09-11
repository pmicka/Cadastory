create or replace function public.scout_get_component_sandbox_names_v1_internal()
returns text[]
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select coalesce(array_agg(name order by sort_order), array[]::text[])
  from (
    select 1 as sort_order, o.canonical_name as name
    from core.organizations as o
    where o.id = 'c425461c-1fcb-4b36-9ea7-c16de7da972e'::uuid
      and o.status = 'active'
      and nullif(btrim(o.canonical_name), '') is not null

    union all

    select 2 as sort_order, p.name
    from intelligence.premium_exterior_targets as p
    where p.id = '0edb82cd-7487-4f72-a036-8faa8a40bd54'::uuid
      and nullif(btrim(p.name), '') is not null
  ) as exemplars;
$$;

revoke all on function public.scout_get_component_sandbox_names_v1_internal() from public;
revoke all on function public.scout_get_component_sandbox_names_v1_internal() from anon;
revoke all on function public.scout_get_component_sandbox_names_v1_internal() from authenticated;
grant execute on function public.scout_get_component_sandbox_names_v1_internal() to service_role;

comment on function public.scout_get_component_sandbox_names_v1_internal()
is 'Returns only the two bounded real Scout exemplar names for the owner-only MCP Apps lifecycle sandbox.';
