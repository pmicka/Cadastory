create or replace function farm_watch.farm_watch_complete_materialization_build_v1_internal(
  p_build_id uuid,
  p_lease_token uuid,
  p_sampled_source_sha256 text,
  p_evidence_class text,
  p_summary jsonb,
  p_source_provenance jsonb,
  p_limitations jsonb,
  p_artifact_bucket text,
  p_artifact_path text,
  p_artifact_format text,
  p_artifact_mime_type text,
  p_artifact_size_bytes bigint,
  p_artifact_sha256 text,
  p_expires_at timestamptz
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, farm_watch, extensions
as $$
declare
  v_build farm_watch.property_materialization_builds_v1%rowtype;
  v_materialization_id uuid;
  v_identity_sha256 text;
begin
  select * into v_build
  from farm_watch.property_materialization_builds_v1
  where id=p_build_id
  for update;

  if v_build.id is null then raise exception 'build not found'; end if;
  if v_build.status <> 'processing' then raise exception 'build is not processing'; end if;
  if v_build.lease_token is distinct from p_lease_token then raise exception 'lease token mismatch'; end if;
  if v_build.lease_expires_at is null or v_build.lease_expires_at <= now() then raise exception 'lease expired'; end if;
  if p_sampled_source_sha256 !~ '^[0-9a-f]{64}$' then raise exception 'invalid sampled source checksum'; end if;
  if p_artifact_sha256 !~ '^[0-9a-f]{64}$' then raise exception 'invalid artifact checksum'; end if;
  if p_artifact_size_bytes <= 0 then raise exception 'invalid artifact size'; end if;
  if p_artifact_bucket <> 'farm-watch-derived' then raise exception 'invalid artifact bucket'; end if;
  if p_artifact_path is null
     or length(p_artifact_path) < 1
     or length(p_artifact_path) > 700
     or p_artifact_path !~ '^[a-zA-Z0-9._/-]+

  v_identity_sha256 := encode(
    extensions.digest(
      convert_to(
        concat_ws(
          '|',
          v_build.property_id::text,
          v_build.input_signature_sha256,
          p_sampled_source_sha256,
          p_artifact_sha256,
          p_artifact_format
        ),
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  insert into farm_watch.property_materializations_v1 (
    property_id, product_kind, algorithm_version, output_schema_version,
    boundary_sha256, source_signature_sha256, input_signature_sha256,
    sampled_source_sha256, identity_sha256, evidence_class, summary,
    source_provenance, limitations, artifact_bucket, artifact_path,
    artifact_format, artifact_mime_type, artifact_size_bytes, artifact_sha256,
    completed_at, expires_at
  )
  values (
    v_build.property_id, v_build.product_kind, v_build.algorithm_version, v_build.output_schema_version,
    v_build.boundary_sha256, v_build.source_signature_sha256, v_build.input_signature_sha256,
    p_sampled_source_sha256, v_identity_sha256, p_evidence_class, coalesce(p_summary,'{}'::jsonb),
    coalesce(p_source_provenance,'{}'::jsonb), coalesce(p_limitations,'[]'::jsonb),
    p_artifact_bucket, p_artifact_path, p_artifact_format, p_artifact_mime_type,
    p_artifact_size_bytes, p_artifact_sha256, now(), p_expires_at
  )
  on conflict (identity_sha256) do update set
    summary=excluded.summary,
    source_provenance=excluded.source_provenance,
    limitations=excluded.limitations,
    artifact_bucket=excluded.artifact_bucket,
    artifact_path=excluded.artifact_path,
    artifact_format=excluded.artifact_format,
    artifact_mime_type=excluded.artifact_mime_type,
    artifact_size_bytes=excluded.artifact_size_bytes,
    artifact_sha256=excluded.artifact_sha256,
    completed_at=excluded.completed_at,
    expires_at=excluded.expires_at
  returning id into v_materialization_id;

  update farm_watch.property_materialization_builds_v1
  set status='available',
      materialization_id=v_materialization_id,
      lease_owner=null,
      lease_token=null,
      lease_expires_at=null,
      next_attempt_at=null,
      last_error=null,
      finished_at=now(),
      updated_at=now()
  where id=v_build.id;

  return jsonb_build_object(
    'status','available',
    'build_id',v_build.id,
    'materialization_id',v_materialization_id,
    'identity_sha256',v_identity_sha256
  );
end;
$$;
