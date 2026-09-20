create or replace function farm_watch.farm_watch_get_materialization_build_v1_internal(
  p_build_id uuid
) returns jsonb
language sql
stable
security definer
set search_path=pg_catalog,farm_watch
as $$
  select case when b.id is null then null else jsonb_build_object(
    'id',b.id,
    'property_id',b.property_id,
    'product_kind',b.product_kind,
    'algorithm_version',b.algorithm_version,
    'output_schema_version',b.output_schema_version,
    'input_signature_sha256',b.input_signature_sha256,
    'source_signature',b.source_signature,
    'status',b.status,
    'lease_token',b.lease_token,
    'lease_expires_at',b.lease_expires_at
  ) end
  from farm_watch.property_materialization_builds_v1 b
  where b.id=p_build_id
  limit 1;
$$;

revoke all on function farm_watch.farm_watch_get_materialization_build_v1_internal(uuid)
  from public,anon,authenticated;
grant execute on function farm_watch.farm_watch_get_materialization_build_v1_internal(uuid)
  to postgres,service_role;

create or replace function public.farm_watch_get_materialization_build_v1_internal(
  p_build_id uuid
) returns jsonb
language sql
stable
security definer
set search_path=pg_catalog
as $$
  select farm_watch.farm_watch_get_materialization_build_v1_internal(p_build_id);
$$;

revoke all on function public.farm_watch_get_materialization_build_v1_internal(uuid)
  from public,anon,authenticated;
grant execute on function public.farm_watch_get_materialization_build_v1_internal(uuid)
  to postgres,service_role;
