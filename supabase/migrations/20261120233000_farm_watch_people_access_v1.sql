begin;

-- WMW Farm is the only property administered here. Reuse the established
-- email and direct-user grants rather than introducing memberships or invites.
create table farm_watch.access_control_state_v1 (
  singleton boolean primary key default true check (singleton),
  revision integer not null default 1 check (revision > 0),
  updated_at timestamptz not null default now()
);
insert into farm_watch.access_control_state_v1(singleton) values(true);

create table farm_watch.access_audit_v1 (
  id uuid primary key default extensions.gen_random_uuid(),
  actor_user_id uuid not null,
  target_email text not null,
  action text not null check (action in ('grant','change','revoke')),
  previous_role text,
  new_role text,
  previous_status text,
  new_status text not null check (new_status in ('active','revoked')),
  occurred_at timestamptz not null default now()
);

alter table farm_watch.access_control_state_v1 enable row level security;
alter table farm_watch.access_control_state_v1 force row level security;
alter table farm_watch.access_audit_v1 enable row level security;
alter table farm_watch.access_audit_v1 force row level security;
revoke all on farm_watch.access_control_state_v1 from public,anon,authenticated;
revoke all on farm_watch.access_audit_v1 from public,anon,authenticated;
grant select,insert,update,delete on farm_watch.access_control_state_v1 to service_role,postgres;
grant select,insert,update,delete on farm_watch.access_audit_v1 to service_role,postgres;

-- A single owner-only RPC is safer than granting broad CRUD to browser clients.
-- Its current-role check runs on every operation, not just at UI bootstrap.
create function public.farm_watch_manage_access_v1(
  p_action text default 'list',
  p_email text default null,
  p_role text default null,
  p_expected_revision integer default null
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  actor_email text;
  normalized_email text;
  current_revision integer;
  previous_role text;
  previous_status text;
  target_exists boolean;
  audit_action text;
  members jsonb;
  events jsonb;
begin
  if actor is null
    or coalesce((auth.jwt()->>'is_anonymous')::boolean,false)
    or not exists(select 1 from auth.users where id=actor)
    or not public.farm_watch_authorize_user_v1_internal(actor)
    or public.farm_watch_get_account_role_v1_internal(actor) is distinct from 'owner'
    or not exists(select 1 from farm_watch.properties p
      where p.slug='validation-property-01' and p.status='active')
  then
    raise exception 'not found' using errcode='42501';
  end if;

  if p_action = 'list' then
    if p_email is not null or p_role is not null or p_expected_revision is not null
    then raise exception 'invalid list request' using errcode='22023'; end if;
    select revision into current_revision
    from farm_watch.access_control_state_v1 where singleton=true;

    -- Email grants are the primary manageable records. An active direct grant
    -- can override an email role, so expose that effective role explicitly.
    with email_records as (
      select e.email, e.account_role,e.status,e.created_at,e.updated_at,
        au.id as linked_user_id,au.last_sign_in_at,
        coalesce(g.google_confirmed,false) as google_confirmed,
        d.account_role as direct_role,
        (d.account_role='owner' or e.account_role='owner'
          or au.id=actor) as protected,
        ('email:'||e.email) as record_key, 'email'::text as source
      from farm_watch.authorized_emails e
      left join lateral (
        select u.id,u.last_sign_in_at,u.email,u.email_confirmed_at
        from auth.users u where lower(u.email)=e.email order by u.created_at limit 1
      ) au on true
      left join lateral (
        select true as google_confirmed from auth.identities ai
        where ai.user_id=au.id and ai.provider='google'
          and au.email_confirmed_at is not null limit 1
      ) g on true
      left join lateral (
        select u.account_role from farm_watch.authorized_users u
        where u.user_id=au.id and u.status='active'
          and u.revoked_at is null limit 1
      ) d on true
    ), direct_only as (
      select au.email as email,u.account_role,u.status,
        u.created_at,u.updated_at,u.user_id as linked_user_id,
        au.last_sign_in_at,
        (au.email_confirmed_at is not null and exists(
          select 1 from auth.identities ai where ai.user_id=u.user_id and ai.provider='google'
        )) as google_confirmed,
        u.account_role as direct_role,
        true as protected,
        'direct:'||u.user_id::text as record_key,'direct'::text as source
      from farm_watch.authorized_users u
      left join auth.users au on au.id=u.user_id
      where not exists (select 1 from farm_watch.authorized_emails e
        where e.email=lower(au.email))
    ), combined as (
      select * from email_records union all select * from direct_only
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'record_key',c.record_key,'source',c.source,'email',c.email,
      'role',c.account_role,'status',c.status,
      'effective_role',case
        when c.direct_role is not null then c.direct_role
        when c.status='active' and c.google_confirmed then c.account_role
        else null end,
      'google_linked',c.google_confirmed,
      'has_signed_in',c.google_confirmed and c.last_sign_in_at is not null,
      'managed',c.source='email' and not coalesce(c.protected,false),
      'created_at',c.created_at,'updated_at',c.updated_at
    ) order by case when c.account_role='owner' then 0 else 1 end,
      c.email nulls last,c.record_key),'[]'::jsonb)
    into members from combined c;

    select coalesce(jsonb_agg(jsonb_build_object(
      'action',e.action,'email',e.target_email,
      'previous_role',e.previous_role,'new_role',e.new_role,
      'occurred_at',e.occurred_at,'by_current_owner',e.actor_user_id=actor
    ) order by e.occurred_at desc,e.id),'[]'::jsonb)
    into events
    from (select * from farm_watch.access_audit_v1
      order by occurred_at desc,id limit 20) e;

    return jsonb_build_object('revision',current_revision,'members',members,
      'activity',events,'can_manage',true,'source','farm-access-v1');
  end if;

  if p_action is null or p_action not in ('set','revoke')
    or p_email is null or p_expected_revision is null
    or (p_action='set' and (p_role is null or p_role not in ('admin','viewer')))
    or (p_action='revoke' and p_role is not null)
  then raise exception 'invalid access change' using errcode='22023'; end if;

  normalized_email := lower(btrim(p_email));
  if length(normalized_email)>254 or length(normalized_email)<5
    or normalized_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[a-z]{2,}$'
    or normalized_email like '%..%' then
    raise exception 'invalid email' using errcode='22023';
  end if;

  -- Serialize all owner changes and prevent stale clients from overwriting
  -- each other. The entire grant synchronization and audit is transactional.
  select revision into current_revision from farm_watch.access_control_state_v1
    where singleton=true for update;
  if current_revision is distinct from p_expected_revision then
    raise exception 'access changed; refresh' using errcode='PT409';
  end if;

  select lower(email) into actor_email from auth.users where id=actor;
  if normalized_email=actor_email
    or exists (select 1 from farm_watch.authorized_emails e
      where e.email=normalized_email and e.account_role='owner')
    or exists (select 1 from farm_watch.authorized_users u
      join auth.users au on au.id=u.user_id
      where lower(au.email)=normalized_email and u.account_role='owner')
  then
    raise exception 'owner access cannot be modified here' using errcode='42501';
  end if;

  -- Direct nonowner rows, when present, must change together with the email
  -- grant or they would silently override role changes and revocations.
  perform 1 from farm_watch.authorized_users u
    join auth.users au on au.id=u.user_id
    where lower(au.email)=normalized_email for update of u;
  select e.account_role,e.status into previous_role,previous_status
  from farm_watch.authorized_emails e where e.email=normalized_email for update;
  target_exists := found;
  if not target_exists then
    select u.account_role,u.status into previous_role,previous_status
    from farm_watch.authorized_users u join auth.users au on au.id=u.user_id
    where lower(au.email)=normalized_email order by u.created_at limit 1;
    target_exists:=found;
  end if;

  if p_action='set' then
    if previous_status='active' and previous_role=p_role
      and exists(select 1 from farm_watch.authorized_emails e
        where e.email=normalized_email and e.status='active' and e.account_role=p_role)
      and not exists(select 1 from farm_watch.authorized_users u
        join auth.users au on au.id=u.user_id
        where lower(au.email)=normalized_email and u.account_role is distinct from p_role)
    then raise exception 'access already current' using errcode='PT409'; end if;

    insert into farm_watch.authorized_emails(email,account_role,status,revoked_at)
      values(normalized_email,p_role,'active',null)
    on conflict (email) do update
      set account_role=excluded.account_role,status='active',revoked_at=null,
        updated_at=now();
    update farm_watch.authorized_users u
      set account_role=p_role,status='active',revoked_at=null,updated_at=now()
      from auth.users au where au.id=u.user_id and lower(au.email)=normalized_email
        and u.account_role<>'owner';
    audit_action:=case when not target_exists or previous_status='revoked'
      then 'grant' else 'change' end;
  else
    if not target_exists or (previous_status='revoked' and
      not exists(select 1 from farm_watch.authorized_users u
        join auth.users au on au.id=u.user_id where lower(au.email)=normalized_email
          and u.status='active' and u.revoked_at is null)) then
      raise exception 'access already unavailable' using errcode='PT409';
    end if;
    update farm_watch.authorized_emails e set status='revoked',
      revoked_at=now(),updated_at=now()
      where e.email=normalized_email;
    update farm_watch.authorized_users u set status='revoked',
      revoked_at=now(),updated_at=now()
      from auth.users au where au.id=u.user_id and lower(au.email)=normalized_email
        and u.account_role<>'owner';
    audit_action:='revoke';
  end if;

  insert into farm_watch.access_audit_v1(
    actor_user_id,target_email,action,previous_role,new_role,previous_status,new_status
  ) values(
    actor,normalized_email,audit_action,previous_role,
    case when p_action='revoke' then null else p_role end,previous_status,
    case when p_action='revoke' then 'revoked' else 'active' end
  );
  update farm_watch.access_control_state_v1
    set revision=revision+1,updated_at=now() where singleton=true;
  return jsonb_build_object('updated',true,'revision',current_revision+1,
    'action',audit_action);
end $$;

revoke all on function public.farm_watch_manage_access_v1(text,text,text,integer)
  from public,anon,authenticated,service_role;
grant execute on function public.farm_watch_manage_access_v1(text,text,text,integer)
  to authenticated;

comment on function public.farm_watch_manage_access_v1(text,text,text,integer) is
  'Single WMW Farm owner-only directory and role/revocation API; direct and email nonowner grants synchronized, owner protected, audit append-only.';

commit;
