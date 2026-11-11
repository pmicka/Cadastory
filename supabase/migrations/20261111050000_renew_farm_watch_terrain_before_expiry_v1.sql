-- Renew Farm Watch terrain up to 72 hours before its 30-day artifact expires.
-- Keep the existing read path fail-closed for stale/missing data and leave other materialization products unchanged.
-- A successfully completed prior build starts a new bounded-attempt renewal cycle; failed attempts remain capped.

CREATE OR REPLACE FUNCTION farm_watch.farm_watch_claim_materialization_build_v1_internal(p_slug text, p_product_kind text, p_algorithm_version text, p_output_schema_version text, p_source_signature text, p_worker_id text, p_lease_seconds integer DEFAULT 900)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'farm_watch', 'extensions'
AS $function$
declare
  v_property farm_watch.properties%rowtype;
  v_identity jsonb;
  v_input_signature text;
  v_build farm_watch.property_materialization_builds_v1%rowtype;
  v_materialization farm_watch.property_materializations_v1%rowtype;
  v_lease_token uuid;
  v_lease_seconds integer := greatest(60, least(coalesce(p_lease_seconds,900), 3600));
  v_refresh_cutoff timestamptz;
begin
  -- Only terrain renews ahead of expiry; all other products retain their current claim semantics.
  v_refresh_cutoff := now() + case when p_product_kind = 'terrain-analysis'
    then interval '3 days' else interval '0 seconds' end;

  if p_worker_id is null or length(trim(p_worker_id)) < 3 then
    raise exception 'worker id is required';
  end if;

  select * into v_property
  from farm_watch.properties
  where slug = p_slug and status = 'active'
  limit 1;

  if v_property.id is null or v_property.boundary is null then
    raise exception 'active property boundary unavailable';
  end if;

  v_identity := farm_watch.farm_watch_materialization_identity_v1(
    v_property.id,
    v_property.boundary,
    v_property.stated_acres,
    p_product_kind,
    p_algorithm_version,
    p_output_schema_version,
    p_source_signature
  );
  v_input_signature := v_identity->>'input_signature_sha256';

  select m.* into v_materialization
  from farm_watch.property_materializations_v1 m
  where m.property_id = v_property.id
    and m.product_kind = p_product_kind
    and m.algorithm_version = p_algorithm_version
    and m.output_schema_version = p_output_schema_version
    and m.input_signature_sha256 = v_input_signature
    and (m.expires_at is null or m.expires_at > v_refresh_cutoff)
  order by m.completed_at desc
  limit 1;

  if v_materialization.id is not null then
    return jsonb_build_object(
      'action','reuse',
      'materialization_id',v_materialization.id,
      'input_signature_sha256',v_input_signature,
      'boundary_sha256',v_identity->>'boundary_sha256',
      'artifact_sha256',v_materialization.artifact_sha256
    );
  end if;

  insert into farm_watch.property_materialization_builds_v1 (
    property_id, product_kind, algorithm_version, output_schema_version,
    boundary_sha256, source_signature, source_signature_sha256,
    deterministic_inputs, input_signature_sha256, status
  )
  values (
    v_property.id, p_product_kind, p_algorithm_version, p_output_schema_version,
    v_identity->>'boundary_sha256', p_source_signature, v_identity->>'source_signature_sha256',
    v_identity->'deterministic_inputs', v_input_signature, 'queued'
  )
  on conflict (input_signature_sha256) do nothing;

  select * into v_build
  from farm_watch.property_materialization_builds_v1
  where input_signature_sha256 = v_input_signature
  for update;

  if v_build.status = 'available' and v_build.materialization_id is not null then
    select * into v_materialization
    from farm_watch.property_materializations_v1
    where id = v_build.materialization_id;

    if v_materialization.id is not null
       and (v_materialization.expires_at is null or v_materialization.expires_at > v_refresh_cutoff) then
      return jsonb_build_object(
        'action','reuse',
        'build_id',v_build.id,
        'materialization_id',v_materialization.id,
        'input_signature_sha256',v_input_signature,
        'boundary_sha256',v_identity->>'boundary_sha256',
        'artifact_sha256',v_materialization.artifact_sha256
      );
    end if;
  end if;

  if v_build.status = 'processing'
     and v_build.lease_expires_at is not null
     and v_build.lease_expires_at > now() then
    return jsonb_build_object(
      'action','busy',
      'build_id',v_build.id,
      'lease_expires_at',v_build.lease_expires_at,
      'attempt_count',v_build.attempt_count
    );
  end if;

  if v_build.next_attempt_at is not null and v_build.next_attempt_at > now() then
    return jsonb_build_object(
      'action','retry_later',
      'build_id',v_build.id,
      'next_attempt_at',v_build.next_attempt_at,
      'attempt_count',v_build.attempt_count
    );
  end if;

  if v_build.attempt_count >= v_build.max_attempts
     and not (v_build.status='available' and v_build.materialization_id is not null) then
    return jsonb_build_object(
      'action','exhausted',
      'build_id',v_build.id,
      'attempt_count',v_build.attempt_count,
      'last_error',v_build.last_error
    );
  end if;

  v_lease_token := extensions.gen_random_uuid();

  update farm_watch.property_materialization_builds_v1
  set status='processing',
      attempt_count=case
        when v_build.status='available' and v_build.materialization_id is not null then 1
        else attempt_count+1
      end,
      lease_owner=p_worker_id,
      lease_token=v_lease_token,
      lease_expires_at=now()+make_interval(secs=>v_lease_seconds),
      next_attempt_at=null,
      last_error=null,
      started_at=coalesce(started_at,now()),
      finished_at=null,
      updated_at=now()
  where id=v_build.id
  returning * into v_build;

  return jsonb_build_object(
    'action','build',
    'build_id',v_build.id,
    'lease_token',v_lease_token,
    'lease_expires_at',v_build.lease_expires_at,
    'attempt_count',v_build.attempt_count,
    'property_id',v_property.id,
    'property_slug',v_property.slug,
    'stated_acres',v_property.stated_acres,
    'boundary_geojson',extensions.st_asgeojson(v_property.boundary,15)::jsonb,
    'boundary_sha256',v_identity->>'boundary_sha256',
    'source_signature_sha256',v_identity->>'source_signature_sha256',
    'input_signature_sha256',v_input_signature
  );
end;
$function$

