begin;

create table if not exists farm_watch.authorized_emails (
  email text primary key,
  account_role text not null default 'viewer' check (account_role in ('owner','viewer')),
  status text not null default 'active' check (status in ('active','revoked')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revoked_at timestamptz,
  constraint farm_watch_authorized_emails_normalized_check
    check (email = lower(btrim(email)) and position('@' in email) > 1)
);

alter table farm_watch.authorized_emails enable row level security;

revoke all on table farm_watch.authorized_emails from public, anon, authenticated;
grant select, insert, update, delete on table farm_watch.authorized_emails to postgres, service_role;

create or replace function public.farm_watch_authorize_user_v1_internal(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = 'pg_catalog'
as $$
  select
    exists (
      select 1
      from farm_watch.authorized_users u
      where u.user_id = p_user_id
        and u.status = 'active'
        and u.revoked_at is null
    )
    or exists (
      select 1
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
    );
$$;

revoke all on function public.farm_watch_authorize_user_v1_internal(uuid) from public, anon, authenticated;
grant execute on function public.farm_watch_authorize_user_v1_internal(uuid) to postgres, service_role;

commit;
