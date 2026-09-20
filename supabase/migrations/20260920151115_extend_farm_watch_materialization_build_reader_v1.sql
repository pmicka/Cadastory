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
    'boundary_sha256',b.boundary_sha256,
    'source_signature',b.source_signature,
    'source_signature_sha256',b.source_signature_sha256,
    'deterministic_inputs',b.deterministic_inputs,
    'input_signature_sha256',b.input_signature_sha256,
    'status',b.status,
    'attempt_count',b.attempt_count,
    'max_attempts',b.max_attempts,
    'lease_owner',b.lease_owner,
    'lease_token',b.lease_token,
    'lease_expires_at',b.lease_expires_at,
    'materialization_id',b.materialization_id,
    'last_error',case when b.status='failed' then b.last_error else null end
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

comment on function farm_watch.farm_watch_get_materialization_build_v1_internal(uuid) is
'Internal materialization build reader for protected workers. Includes deterministic boundary/source identity so completion workers can fail closed against stale artifacts.';
