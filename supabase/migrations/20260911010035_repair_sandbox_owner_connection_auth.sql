create or replace function public.scout_is_owner_connection_internal(
  p_connection_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, commerce, pg_temp
as $function$
  select exists (
    select 1
    from commerce.oauth_agent_connection_bindings b
    join commerce.scout_account_allowlist a
      on a.user_id = b.user_id
    where b.connection_id = p_connection_id
      and a.account_role = 'owner'
      and a.status = 'active'
  );
$function$;

revoke all on function public.scout_is_owner_connection_internal(uuid) from public;
revoke all on function public.scout_is_owner_connection_internal(uuid) from anon;
revoke all on function public.scout_is_owner_connection_internal(uuid) from authenticated;
grant execute on function public.scout_is_owner_connection_internal(uuid) to service_role;
