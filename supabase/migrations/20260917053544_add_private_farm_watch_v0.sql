create schema if not exists farm_watch;

revoke all on schema farm_watch from public, anon, authenticated;
grant usage on schema farm_watch to postgres, service_role;

create table if not exists farm_watch.authorized_users (
  user_id uuid primary key,
  account_role text not null default 'owner' check (account_role in ('owner','viewer')),
  status text not null default 'active' check (status in ('active','revoked')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revoked_at timestamptz
);

create table if not exists farm_watch.properties (
  id uuid primary key default extensions.gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9][a-z0-9-]{0,79}$'),
  display_name text not null,
  street_address text,
  city text,
  state_code text check (state_code is null or state_code ~ '^[A-Z]{2}$'),
  postal_code text,
  stated_acres numeric check (stated_acres is null or stated_acres > 0),
  center extensions.geometry(Point,4326),
  boundary extensions.geometry(MultiPolygon,4326),
  status text not null default 'active' check (status in ('active','archived')),
  access_scope text not null default 'owner_only' check (access_scope in ('owner_only')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table farm_watch.authorized_users enable row level security;
alter table farm_watch.properties enable row level security;

revoke all on table farm_watch.authorized_users from public, anon, authenticated;
revoke all on table farm_watch.properties from public, anon, authenticated;
grant select, insert, update, delete on table farm_watch.authorized_users to postgres, service_role;
grant select, insert, update, delete on table farm_watch.properties to postgres, service_role;

create or replace function public.farm_watch_authorize_user_v1_internal(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = 'pg_catalog'
as $$
  select exists (
    select 1
    from farm_watch.authorized_users u
    where u.user_id = p_user_id
      and u.status = 'active'
      and u.revoked_at is null
  );
$$;

create or replace function public.farm_watch_get_property_v1_internal(p_slug text)
returns jsonb
language sql
stable
security definer
set search_path = 'pg_catalog'
as $$
  select jsonb_build_object(
    'id', p.id,
    'slug', p.slug,
    'display_name', p.display_name,
    'street_address', p.street_address,
    'city', p.city,
    'state_code', p.state_code,
    'postal_code', p.postal_code,
    'stated_acres', p.stated_acres,
    'center_geojson', case when p.center is null then null else extensions.st_asgeojson(p.center)::jsonb end,
    'boundary_geojson', case when p.boundary is null then null else extensions.st_asgeojson(p.boundary)::jsonb end,
    'metadata', p.metadata,
    'updated_at', p.updated_at
  )
  from farm_watch.properties p
  where p.slug = p_slug
    and p.status = 'active'
  limit 1;
$$;

revoke all on function public.farm_watch_authorize_user_v1_internal(uuid) from public, anon, authenticated;
revoke all on function public.farm_watch_get_property_v1_internal(text) from public, anon, authenticated;
grant execute on function public.farm_watch_authorize_user_v1_internal(uuid) to postgres, service_role;
grant execute on function public.farm_watch_get_property_v1_internal(text) to postgres, service_role;
