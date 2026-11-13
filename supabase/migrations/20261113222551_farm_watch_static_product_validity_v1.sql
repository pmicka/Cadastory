begin;

-- These products describe versioned source snapshots and deterministic geometry.
-- Their canonical reader still requires matching authoritative source identities,
-- property inputs, algorithms, schemas, and recursive dependency manifests.
create or replace function farm_watch.farm_watch_materialization_is_stable_v1(
  p_product_kind text
)
returns boolean
language sql
immutable
security invoker
set search_path = pg_catalog
as $$
  select coalesce(p_product_kind in (
    'terrain-analysis',
    'lidar-source-coverage',
    'lidar-physical-structure',
    'leaf-off-woody-structure',
    'structure-complementarity',
    'landscape-structure-context',
    'study-aligned-vegetation-height-context',
    'terrain-form-permeability',
    'spatial-edge-patch-context',
    'solar-terrain-context',
    'horizontal-visibility-context',
    'mast-capacity'
  ), false);
$$;

revoke all on function farm_watch.farm_watch_materialization_is_stable_v1(text)
  from public, anon, authenticated;
grant execute on function farm_watch.farm_watch_materialization_is_stable_v1(text)
  to service_role;

-- Enforce policy centrally so older workers cannot reintroduce calendar expiry.
-- Do not touch provenance, hashes, completed_at, or any scientific payload.
create or replace function farm_watch.farm_watch_normalize_materialization_expiry_v1()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog
as $$
begin
  if farm_watch.farm_watch_materialization_is_stable_v1(new.product_kind) then
    new.expires_at := null;
  end if;
  return new;
end;
$$;

revoke all on function farm_watch.farm_watch_normalize_materialization_expiry_v1()
  from public, anon, authenticated, service_role;

create trigger farm_watch_materialization_expiry_policy_v1
  before insert or update of product_kind, expires_at
  on farm_watch.property_materializations_v1
  for each row
  execute function farm_watch.farm_watch_normalize_materialization_expiry_v1();

update farm_watch.property_materializations_v1
set expires_at = null
where expires_at is not null
  and farm_watch.farm_watch_materialization_is_stable_v1(product_kind);

comment on function farm_watch.farm_watch_materialization_is_stable_v1(text) is
  'Explicit stable-product allowlist: no calendar expiry; authoritative dependency, property, model, and schema checks remain mandatory. Unknown and temporal products retain expiry.';

commit;
