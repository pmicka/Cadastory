begin;

alter table farm_watch.authorized_users
  drop constraint if exists authorized_users_account_role_check;

alter table farm_watch.authorized_users
  add constraint authorized_users_account_role_check
  check (account_role in ('owner', 'admin', 'viewer'));

alter table farm_watch.authorized_emails
  drop constraint if exists authorized_emails_account_role_check;

alter table farm_watch.authorized_emails
  add constraint authorized_emails_account_role_check
  check (account_role in ('owner', 'admin', 'viewer'));

create or replace function public.farm_watch_get_account_role_v1_internal(p_user_id uuid)
returns text
language sql
stable
security definer
set search_path to 'pg_catalog'
as $function$
  with direct_role as (
    select u.account_role
    from farm_watch.authorized_users u
    where u.user_id = p_user_id
      and u.status = 'active'
      and u.revoked_at is null
    order by
      case u.account_role
        when 'owner' then 0
        when 'admin' then 1
        when 'viewer' then 2
        else 99
      end,
      u.updated_at desc
    limit 1
  ),
  email_role as (
    select ae.account_role
    from auth.users au
    join farm_watch.authorized_emails ae
      on ae.email = lower(au.email)
    where au.id = p_user_id
      and au.email is not null
      and au.email_confirmed_at is not null
      and ae.status = 'active'
      and ae.revoked_at is null
      and exists (
        select 1
        from auth.identities ai
        where ai.user_id = au.id
          and ai.provider = 'google'
      )
    order by
      case ae.account_role
        when 'owner' then 0
        when 'admin' then 1
        when 'viewer' then 2
        else 99
      end,
      ae.updated_at desc
    limit 1
  )
  select coalesce(
    (select account_role from direct_role),
    (select account_role from email_role)
  );
$function$;

revoke all on function public.farm_watch_get_account_role_v1_internal(uuid)
  from public, anon, authenticated;
grant execute on function public.farm_watch_get_account_role_v1_internal(uuid)
  to service_role;

commit;
