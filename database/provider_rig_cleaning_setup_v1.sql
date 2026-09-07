-- Scout operator rig cleaning setup v1
-- Adds explicit rig-to-fluid-route and rig-to-product assignments while preserving
-- unresolved product identity and incomplete route evidence as unresolved, never approval.

alter table cleaning.provider_products
  add column if not exists declared_product_kind text,
  add column if not exists declared_manufacturer_name text;

alter table cleaning.provider_products
  drop constraint if exists provider_products_declared_product_kind_check;
alter table cleaning.provider_products
  add constraint provider_products_declared_product_kind_check
  check (declared_product_kind is null or declared_product_kind ~ '^[a-z][a-z0-9_.-]{0,79}$');

alter table cleaning.provider_products
  drop constraint if exists provider_products_declared_manufacturer_name_check;
alter table cleaning.provider_products
  add constraint provider_products_declared_manufacturer_name_check
  check (declared_manufacturer_name is null or length(btrim(declared_manufacturer_name)) between 1 and 200);

alter table commerce.provider_onboarding_state
  add column if not exists cleaning_products_confirmed_at timestamptz;

create table if not exists equipment.provider_rig_fluid_routes (
  id uuid primary key default gen_random_uuid(),
  rig_id uuid not null references equipment.provider_rigs(id) on delete cascade,
  fluid_route_id uuid not null references equipment.fluid_routes(id) on delete cascade,
  service_type_id uuid references commerce.service_types(id) on delete set null,
  route_role text not null default 'primary_delivery',
  status text not null default 'active',
  notes text,
  attributes jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint provider_rig_fluid_routes_role_check check (route_role ~ '^[a-z][a-z0-9_.-]{0,79}$'),
  constraint provider_rig_fluid_routes_status_check check (status in ('active','backup','planned','inactive'))
);

create unique index if not exists provider_rig_fluid_routes_uq
  on equipment.provider_rig_fluid_routes(rig_id,fluid_route_id,coalesce(service_type_id,'00000000-0000-0000-0000-000000000000'::uuid),route_role);
create index if not exists provider_rig_fluid_routes_rig_idx on equipment.provider_rig_fluid_routes(rig_id,status);
create index if not exists provider_rig_fluid_routes_route_idx on equipment.provider_rig_fluid_routes(fluid_route_id);
create index if not exists provider_rig_fluid_routes_service_idx on equipment.provider_rig_fluid_routes(service_type_id);

alter table equipment.provider_rig_fluid_routes enable row level security;
revoke all on equipment.provider_rig_fluid_routes from public,anon,authenticated;
grant select,insert,update,delete on equipment.provider_rig_fluid_routes to service_role;

create table if not exists cleaning.provider_rig_products (
  id uuid primary key default gen_random_uuid(),
  rig_id uuid not null references equipment.provider_rigs(id) on delete cascade,
  provider_product_id uuid not null references cleaning.provider_products(id) on delete cascade,
  service_type_id uuid references commerce.service_types(id) on delete set null,
  fluid_route_id uuid references equipment.fluid_routes(id) on delete set null,
  application_role text not null default 'cleaner',
  service_mode text,
  default_mix jsonb,
  status text not null default 'active',
  notes text,
  attributes jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint provider_rig_products_role_check check (application_role ~ '^[a-z][a-z0-9_.-]{0,79}$'),
  constraint provider_rig_products_service_mode_check check (service_mode is null or service_mode ~ '^[a-z][a-z0-9_.-]{0,119}$'),
  constraint provider_rig_products_status_check check (status in ('active','inactive','seasonal','planned'))
);

create unique index if not exists provider_rig_products_uq
  on cleaning.provider_rig_products(
    rig_id,provider_product_id,
    coalesce(service_type_id,'00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(fluid_route_id,'00000000-0000-0000-0000-000000000000'::uuid),
    application_role,coalesce(service_mode,'')
  );
create index if not exists provider_rig_products_rig_idx on cleaning.provider_rig_products(rig_id,status);
create index if not exists provider_rig_products_product_idx on cleaning.provider_rig_products(provider_product_id);
create index if not exists provider_rig_products_route_idx on cleaning.provider_rig_products(fluid_route_id);
create index if not exists provider_rig_products_service_idx on cleaning.provider_rig_products(service_type_id);

alter table cleaning.provider_rig_products enable row level security;
revoke all on cleaning.provider_rig_products from public,anon,authenticated;
grant select,insert,update,delete on cleaning.provider_rig_products to service_role;

create or replace function equipment.validate_provider_rig_fluid_route_scope()
returns trigger
language plpgsql
set search_path to ''
as $$
declare
  v_rig_org uuid;
  v_route_org uuid;
begin
  select organization_id into v_rig_org from equipment.provider_rigs where id=new.rig_id;
  select organization_id into v_route_org from equipment.fluid_routes where id=new.fluid_route_id;
  if v_rig_org is null then raise exception 'provider rig not found'; end if;
  if v_route_org is null then raise exception 'template/unscoped fluid routes cannot be assigned directly to an operator rig'; end if;
  if v_route_org is distinct from v_rig_org then raise exception 'fluid route and rig must belong to the same provider'; end if;
  if new.service_type_id is not null and not exists(
    select 1 from equipment.provider_rig_services rs
    where rs.rig_id=new.rig_id and rs.service_type_id=new.service_type_id and rs.status='active'
  ) then raise exception 'fluid route service must be an active service on the rig'; end if;
  new.updated_at:=now();
  return new;
end;
$$;

create or replace function cleaning.validate_provider_rig_product_scope()
returns trigger
language plpgsql
set search_path to ''
as $$
declare
  v_rig_org uuid;
  v_product_org uuid;
  v_route_org uuid;
begin
  select organization_id into v_rig_org from equipment.provider_rigs where id=new.rig_id;
  select organization_id into v_product_org from cleaning.provider_products where id=new.provider_product_id;
  if v_rig_org is null or v_product_org is null then raise exception 'provider rig/product not found'; end if;
  if v_product_org is distinct from v_rig_org then raise exception 'provider product and rig must belong to the same provider'; end if;
  if new.service_type_id is not null and not exists(
    select 1 from equipment.provider_rig_services rs
    where rs.rig_id=new.rig_id and rs.service_type_id=new.service_type_id and rs.status='active'
  ) then raise exception 'product service must be an active service on the rig'; end if;
  if new.fluid_route_id is not null then
    select organization_id into v_route_org from equipment.fluid_routes where id=new.fluid_route_id;
    if v_route_org is distinct from v_rig_org then raise exception 'product fluid route must belong to the same provider'; end if;
    if not exists(
      select 1 from equipment.provider_rig_fluid_routes rf
      where rf.rig_id=new.rig_id and rf.fluid_route_id=new.fluid_route_id and rf.status in ('active','backup','planned')
    ) then raise exception 'product fluid route must be assigned to the rig first'; end if;
  end if;
  new.updated_at:=now();
  return new;
end;
$$;

drop trigger if exists validate_provider_rig_fluid_route_scope on equipment.provider_rig_fluid_routes;
create trigger validate_provider_rig_fluid_route_scope before insert or update on equipment.provider_rig_fluid_routes
for each row execute function equipment.validate_provider_rig_fluid_route_scope();

drop trigger if exists validate_provider_rig_product_scope on cleaning.provider_rig_products;
create trigger validate_provider_rig_product_scope before insert or update on cleaning.provider_rig_products
for each row execute function cleaning.validate_provider_rig_product_scope();

create or replace function cleaning.normalize_provider_product_defaults()
returns trigger
language plpgsql
set search_path to ''
as $$
begin
  new.default_mix:=coalesce(new.default_mix,'{}'::jsonb);
  new.attributes:=coalesce(new.attributes,'{}'::jsonb);
  new.updated_at:=now();
  return new;
end;
$$;

drop trigger if exists normalize_provider_product_defaults on cleaning.provider_products;
create trigger normalize_provider_product_defaults before insert or update on cleaning.provider_products
for each row execute function cleaning.normalize_provider_product_defaults();

create or replace view equipment.v_provider_rig_fluid_route_readiness
with (security_invoker=true) as
select
  rf.id as rig_fluid_route_id,r.organization_id,rf.rig_id,r.name as rig_name,
  rf.fluid_route_id,fr.name as fluid_route_name,fr.slug as fluid_route_slug,fr.route_kind,
  rf.service_type_id,st.slug as service_slug,st.name as service_name,rf.route_role,rf.status,
  coalesce(ms.component_count,0) as component_count,coalesce(ms.complete_component_count,0) as complete_component_count,
  coalesce(ms.unknown_component_count,0) as unknown_component_count,coalesce(ms.unidentified_component_count,0) as unidentified_component_count,
  coalesce(ms.unverified_seam_count,0) as unverified_seam_count,coalesce(ms.wetted_inventory_complete,false) as wetted_inventory_complete,
  ms.minimum_mapping_confidence,ms.next_mapping_action,
  case
    when rf.status='inactive' then 'inactive'
    when coalesce(ms.component_count,0)=0 then 'route_shell'
    when coalesce(ms.wetted_inventory_complete,false) and coalesce(ms.unverified_seam_count,0)=0 then 'route_mapped'
    when coalesce(ms.unknown_component_count,0)>0 or coalesce(ms.unidentified_component_count,0)>0 then 'route_mapping_incomplete'
    else 'route_mapping_partial'
  end as readiness_status,
  rf.attributes,rf.created_at,rf.updated_at
from equipment.provider_rig_fluid_routes rf
join equipment.provider_rigs r on r.id=rf.rig_id
join equipment.fluid_routes fr on fr.id=rf.fluid_route_id
left join commerce.service_types st on st.id=rf.service_type_id
left join equipment.fluid_route_mapping_status ms on ms.fluid_route_id=rf.fluid_route_id;

revoke all on equipment.v_provider_rig_fluid_route_readiness from public,anon,authenticated;
grant select on equipment.v_provider_rig_fluid_route_readiness to service_role;

create or replace view cleaning.v_provider_rig_product_readiness
with (security_invoker=true) as
select
  rp.id as rig_product_id,r.organization_id,rp.rig_id,r.name as rig_name,
  rp.provider_product_id,pp.product_id,coalesce(p.product_name,pp.entered_name) as product_name,
  coalesce(p.manufacturer_name,pp.declared_manufacturer_name) as manufacturer_name,
  coalesce(p.product_kind,pp.declared_product_kind) as product_kind,
  rp.service_type_id,st.slug as service_slug,st.name as service_name,
  rp.fluid_route_id,fr.name as fluid_route_name,fr.slug as fluid_route_slug,
  rp.application_role,rp.service_mode,coalesce(rp.default_mix,pp.default_mix) as effective_default_mix,rp.status,
  frm.readiness_status as route_readiness_status,ps.overall_compatibility as route_product_compatibility,
  ps.confidence as compatibility_confidence,ps.manufacturer_verification_required,ps.unresolved_component_count,
  case
    when rp.status='inactive' then 'inactive'
    when pp.product_id is null then 'product_identity_unresolved'
    when rp.fluid_route_id is null then 'route_not_assigned'
    when frm.readiness_status is distinct from 'route_mapped' then 'route_mapping_incomplete'
    when ps.fluid_route_id is null or ps.overall_compatibility='insufficient_data' then 'compatibility_unresolved'
    when ps.overall_compatibility='incompatible' then 'blocked'
    when ps.overall_compatibility='doubtful' then 'not_recommended'
    when ps.overall_compatibility='conditional' then 'conditional'
    when ps.overall_compatibility='compatible' then 'compatible'
    else 'compatibility_unresolved'
  end as readiness_status,
  rp.attributes,rp.created_at,rp.updated_at
from cleaning.provider_rig_products rp
join equipment.provider_rigs r on r.id=rp.rig_id
join cleaning.provider_products pp on pp.id=rp.provider_product_id
left join cleaning.products p on p.id=pp.product_id
left join commerce.service_types st on st.id=rp.service_type_id
left join equipment.fluid_routes fr on fr.id=rp.fluid_route_id
left join equipment.v_provider_rig_fluid_route_readiness frm
  on frm.rig_id=rp.rig_id and frm.fluid_route_id=rp.fluid_route_id
  and (rp.service_type_id is null or frm.service_type_id is null or frm.service_type_id=rp.service_type_id)
left join cleaning.fluid_route_product_summary ps on ps.fluid_route_id=rp.fluid_route_id and ps.product_id=pp.product_id;

revoke all on cleaning.v_provider_rig_product_readiness from public,anon,authenticated;
grant select on cleaning.v_provider_rig_product_readiness to service_role;

comment on table equipment.provider_rig_fluid_routes is 'Explicit operator rig-to-fluid-route assignments. Global/template routes cannot be assigned directly; an operator-scoped route is required.';
comment on table cleaning.provider_rig_products is 'Explicit operator rig-to-product assignments with optional service, fluid-route, application-role and mix context. This is declaration/context, not chemistry approval.';
comment on column commerce.provider_onboarding_state.cleaning_products_confirmed_at is 'Operator explicitly confirmed their current cleaning-product/process-fluid setup; zero products is valid and distinct from unanswered.';
