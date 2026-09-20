create table if not exists farm_watch.property_materializations_v1 (
  id uuid primary key default extensions.gen_random_uuid(),
  property_id uuid not null references farm_watch.properties(id) on delete cascade,
  product_kind text not null check (product_kind ~ '^[a-z0-9][a-z0-9-]{0,79}$'),
  algorithm_version text not null check (length(algorithm_version) between 1 and 160),
  output_schema_version text not null check (length(output_schema_version) between 1 and 160),
  boundary_sha256 text not null check (boundary_sha256 ~ '^[0-9a-f]{64}$'),
  source_signature_sha256 text not null check (source_signature_sha256 ~ '^[0-9a-f]{64}$'),
  input_signature_sha256 text not null check (input_signature_sha256 ~ '^[0-9a-f]{64}$'),
  sampled_source_sha256 text check (sampled_source_sha256 is null or sampled_source_sha256 ~ '^[0-9a-f]{64}$'),
  identity_sha256 text not null unique check (identity_sha256 ~ '^[0-9a-f]{64}$'),
  evidence_class text not null check (evidence_class in ('deterministic_derived','experimental_derived','canonical_structured_evidence')),
  summary jsonb not null default '{}'::jsonb,
  source_provenance jsonb not null default '{}'::jsonb,
  limitations jsonb not null default '[]'::jsonb,
  artifact_bucket text not null,
  artifact_path text not null,
  artifact_format text not null,
  artifact_mime_type text not null,
  artifact_size_bytes bigint not null check (artifact_size_bytes > 0),
  artifact_sha256 text not null check (artifact_sha256 ~ '^[0-9a-f]{64}$'),
  completed_at timestamptz not null default now(),
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  unique (artifact_bucket, artifact_path)
);

create index if not exists property_materializations_v1_lookup_idx
  on farm_watch.property_materializations_v1 (
    property_id, product_kind, algorithm_version, output_schema_version, input_signature_sha256, completed_at desc
  );

create table if not exists farm_watch.property_materialization_builds_v1 (
  id uuid primary key default extensions.gen_random_uuid(),
  property_id uuid not null references farm_watch.properties(id) on delete cascade,
  product_kind text not null check (product_kind ~ '^[a-z0-9][a-z0-9-]{0,79}$'),
  algorithm_version text not null check (length(algorithm_version) between 1 and 160),
  output_schema_version text not null check (length(output_schema_version) between 1 and 160),
  boundary_sha256 text not null check (boundary_sha256 ~ '^[0-9a-f]{64}$'),
  source_signature text not null,
  source_signature_sha256 text not null check (source_signature_sha256 ~ '^[0-9a-f]{64}$'),
  deterministic_inputs jsonb not null default '{}'::jsonb,
  input_signature_sha256 text not null unique check (input_signature_sha256 ~ '^[0-9a-f]{64}$'),
  status text not null default 'queued'
    check (status in ('queued','processing','available','failed')),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  max_attempts integer not null default 5 check (max_attempts between 1 and 20),
  next_attempt_at timestamptz,
  lease_owner text,
  lease_token uuid,
  lease_expires_at timestamptz,
  materialization_id uuid references farm_watch.property_materializations_v1(id) on delete set null,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz
);

create index if not exists property_materialization_builds_v1_claim_idx
  on farm_watch.property_materialization_builds_v1 (status, next_attempt_at, lease_expires_at, updated_at);

alter table farm_watch.property_materializations_v1 enable row level security;
alter table farm_watch.property_materialization_builds_v1 enable row level security;

revoke all on farm_watch.property_materializations_v1 from public, anon, authenticated;
revoke all on farm_watch.property_materialization_builds_v1 from public, anon, authenticated;
grant select, insert, update, delete on farm_watch.property_materializations_v1 to postgres, service_role;
grant select, insert, update, delete on farm_watch.property_materialization_builds_v1 to postgres, service_role;

insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
)
values (
  'farm-watch-derived',
  'farm-watch-derived',
  false,
  10485760,
  array['application/json','application/geo+json']::text[]
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types,
  updated_at = now();

create or replace function farm_watch.farm_watch_materialization_identity_v1(
  p_property_id uuid,
  p_boundary extensions.geometry,
  p_stated_acres numeric,
  p_product_kind text,
  p_algorithm_version text,
  p_output_schema_version text,
  p_source_signature text
) returns jsonb
language sql
immutable
security invoker
set search_path = pg_catalog, extensions
as $$
  with values_ as (
    select
      encode(extensions.digest(extensions.st_asewkb(p_boundary), 'sha256'), 'hex') as boundary_sha256,
      encode(
        extensions.digest(convert_to(coalesce(p_source_signature,''), 'UTF8'), 'sha256'),
        'hex'
      ) as source_signature_sha256
  )
  select jsonb_build_object(
    'boundary_sha256', boundary_sha256,
    'source_signature_sha256', source_signature_sha256,
    'deterministic_inputs', jsonb_build_object(
      'stated_acres', p_stated_acres,
      'boundary_srid', extensions.st_srid(p_boundary)
    ),
    'input_signature_sha256',
      encode(
        extensions.digest(
          convert_to(
            concat_ws(
              '|',
              coalesce(p_property_id::text,''),
              coalesce(p_product_kind,''),
              coalesce(p_algorithm_version,''),
              coalesce(p_output_schema_version,''),
              boundary_sha256,
              coalesce(p_stated_acres::text,''),
              source_signature_sha256
            ),
            'UTF8'
          ),
          'sha256'
        ),
        'hex'
      )
  )
  from values_;
$$;

create or replace function farm_watch.farm_watch_claim_materialization_build_v1_internal(
  p_slug text,
  p_product_kind text,
  p_algorithm_version text,
  p_output_schema_version text,
  p_source_signature text,
  p_worker_id text,
  p_lease_seconds integer default 900
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, farm_watch, extensions
as $$
declare
  v_property farm_watch.properties%rowtype;
  v_identity jsonb;
  v_input_signature text;
  v_build farm_watch.property_materialization_builds_v1%rowtype;
  v_materialization farm_watch.property_materializations_v1%rowtype;
  v_lease_token uuid;
  v_lease_seconds integer := greatest(60, least(coalesce(p_lease_seconds,900), 3600));
begin
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
    and (m.expires_at is null or m.expires_at > now())
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
       and (v_materialization.expires_at is null or v_materialization.expires_at > now()) then
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

  if v_build.attempt_count >= v_build.max_attempts then
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
      attempt_count=attempt_count+1,
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
$$;

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
  if p_artifact_path is null or p_artifact_path !~ '^[a-zA-Z0-9._/-]{1,700}$' then raise exception 'invalid artifact path'; end if;

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

create or replace function farm_watch.farm_watch_fail_materialization_build_v1_internal(
  p_build_id uuid,
  p_lease_token uuid,
  p_error text,
  p_retry_delay_seconds integer default 300
) returns void
language plpgsql
security definer
set search_path = pg_catalog, farm_watch
as $$
begin
  update farm_watch.property_materialization_builds_v1
  set status='failed',
      lease_owner=null,
      lease_token=null,
      lease_expires_at=null,
      next_attempt_at=case
        when attempt_count < max_attempts
          then now()+make_interval(secs=>greatest(60,least(coalesce(p_retry_delay_seconds,300),86400)))
        else null
      end,
      last_error=left(coalesce(p_error,'unknown materialization build failure'),4000),
      finished_at=now(),
      updated_at=now()
  where id=p_build_id
    and status='processing'
    and lease_token=p_lease_token;

  if not found then
    raise exception 'active build lease not found';
  end if;
end;
$$;

create or replace function farm_watch.farm_watch_get_materialization_v1_internal(
  p_slug text,
  p_product_kind text,
  p_algorithm_version text,
  p_output_schema_version text,
  p_source_signature text
) returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, farm_watch, extensions
as $$
declare
  v_property farm_watch.properties%rowtype;
  v_identity jsonb;
  v_build farm_watch.property_materialization_builds_v1%rowtype;
  v_materialization farm_watch.property_materializations_v1%rowtype;
  v_status text;
begin
  select * into v_property
  from farm_watch.properties
  where slug=p_slug and status='active'
  limit 1;

  if v_property.id is null or v_property.boundary is null then
    return jsonb_build_object('status','missing');
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

  select * into v_build
  from farm_watch.property_materialization_builds_v1
  where input_signature_sha256=v_identity->>'input_signature_sha256'
  limit 1;

  if v_build.id is null then
    return jsonb_build_object(
      'status','missing',
      'input_signature_sha256',v_identity->>'input_signature_sha256',
      'boundary_sha256',v_identity->>'boundary_sha256'
    );
  end if;

  if v_build.materialization_id is not null then
    select * into v_materialization
    from farm_watch.property_materializations_v1
    where id=v_build.materialization_id;
  end if;

  if v_materialization.id is not null then
    v_status := case
      when v_materialization.expires_at is not null and v_materialization.expires_at <= now() then 'stale'
      else 'available'
    end;
  elsif v_build.status='processing' and v_build.lease_expires_at is not null and v_build.lease_expires_at > now() then
    v_status := 'processing';
  elsif v_build.status='failed' then
    v_status := 'failed';
  else
    v_status := 'missing';
  end if;

  return jsonb_build_object(
    'status',v_status,
    'build',jsonb_build_object(
      'id',v_build.id,
      'status',v_build.status,
      'attempt_count',v_build.attempt_count,
      'max_attempts',v_build.max_attempts,
      'next_attempt_at',v_build.next_attempt_at,
      'lease_expires_at',v_build.lease_expires_at,
      'last_error',case when v_build.status='failed' then v_build.last_error else null end
    ),
    'identity',jsonb_build_object(
      'input_signature_sha256',v_identity->>'input_signature_sha256',
      'boundary_sha256',v_identity->>'boundary_sha256',
      'source_signature_sha256',v_identity->>'source_signature_sha256'
    ),
    'materialization',case when v_materialization.id is null then null else jsonb_build_object(
      'id',v_materialization.id,
      'identity_sha256',v_materialization.identity_sha256,
      'evidence_class',v_materialization.evidence_class,
      'summary',v_materialization.summary,
      'source_provenance',v_materialization.source_provenance,
      'limitations',v_materialization.limitations,
      'artifact_bucket',v_materialization.artifact_bucket,
      'artifact_path',v_materialization.artifact_path,
      'artifact_format',v_materialization.artifact_format,
      'artifact_mime_type',v_materialization.artifact_mime_type,
      'artifact_size_bytes',v_materialization.artifact_size_bytes,
      'artifact_sha256',v_materialization.artifact_sha256,
      'completed_at',v_materialization.completed_at,
      'expires_at',v_materialization.expires_at
    ) end
  );
end;
$$;

revoke all on function farm_watch.farm_watch_materialization_identity_v1(uuid,extensions.geometry,numeric,text,text,text,text)
  from public, anon, authenticated;
revoke all on function farm_watch.farm_watch_claim_materialization_build_v1_internal(text,text,text,text,text,text,integer)
  from public, anon, authenticated;
revoke all on function farm_watch.farm_watch_complete_materialization_build_v1_internal(uuid,uuid,text,text,jsonb,jsonb,jsonb,text,text,text,text,bigint,text,timestamptz)
  from public, anon, authenticated;
revoke all on function farm_watch.farm_watch_fail_materialization_build_v1_internal(uuid,uuid,text,integer)
  from public, anon, authenticated;
revoke all on function farm_watch.farm_watch_get_materialization_v1_internal(text,text,text,text,text)
  from public, anon, authenticated;

grant execute on function farm_watch.farm_watch_materialization_identity_v1(uuid,extensions.geometry,numeric,text,text,text,text)
  to postgres, service_role;
grant execute on function farm_watch.farm_watch_claim_materialization_build_v1_internal(text,text,text,text,text,text,integer)
  to postgres, service_role;
grant execute on function farm_watch.farm_watch_complete_materialization_build_v1_internal(uuid,uuid,text,text,jsonb,jsonb,jsonb,text,text,text,text,bigint,text,timestamptz)
  to postgres, service_role;
grant execute on function farm_watch.farm_watch_fail_materialization_build_v1_internal(uuid,uuid,text,integer)
  to postgres, service_role;
grant execute on function farm_watch.farm_watch_get_materialization_v1_internal(text,text,text,text,text)
  to postgres, service_role;

create or replace function public.farm_watch_claim_materialization_build_v1_internal(
  p_slug text,
  p_product_kind text,
  p_algorithm_version text,
  p_output_schema_version text,
  p_source_signature text,
  p_worker_id text,
  p_lease_seconds integer default 900
) returns jsonb
language sql security definer set search_path=pg_catalog
as $$
  select farm_watch.farm_watch_claim_materialization_build_v1_internal(
    p_slug,p_product_kind,p_algorithm_version,p_output_schema_version,
    p_source_signature,p_worker_id,p_lease_seconds
  );
$$;

create or replace function public.farm_watch_complete_materialization_build_v1_internal(
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
language sql security definer set search_path=pg_catalog
as $$
  select farm_watch.farm_watch_complete_materialization_build_v1_internal(
    p_build_id,p_lease_token,p_sampled_source_sha256,p_evidence_class,p_summary,
    p_source_provenance,p_limitations,p_artifact_bucket,p_artifact_path,
    p_artifact_format,p_artifact_mime_type,p_artifact_size_bytes,p_artifact_sha256,p_expires_at
  );
$$;

create or replace function public.farm_watch_fail_materialization_build_v1_internal(
  p_build_id uuid,
  p_lease_token uuid,
  p_error text,
  p_retry_delay_seconds integer default 300
) returns void
language sql security definer set search_path=pg_catalog
as $$
  select farm_watch.farm_watch_fail_materialization_build_v1_internal(
    p_build_id,p_lease_token,p_error,p_retry_delay_seconds
  );
$$;

create or replace function public.farm_watch_get_materialization_v1_internal(
  p_slug text,
  p_product_kind text,
  p_algorithm_version text,
  p_output_schema_version text,
  p_source_signature text
) returns jsonb
language sql stable security definer set search_path=pg_catalog
as $$
  select farm_watch.farm_watch_get_materialization_v1_internal(
    p_slug,p_product_kind,p_algorithm_version,p_output_schema_version,p_source_signature
  );
$$;

revoke all on function public.farm_watch_claim_materialization_build_v1_internal(text,text,text,text,text,text,integer)
  from public, anon, authenticated;
revoke all on function public.farm_watch_complete_materialization_build_v1_internal(uuid,uuid,text,text,jsonb,jsonb,jsonb,text,text,text,text,bigint,text,timestamptz)
  from public, anon, authenticated;
revoke all on function public.farm_watch_fail_materialization_build_v1_internal(uuid,uuid,text,integer)
  from public, anon, authenticated;
revoke all on function public.farm_watch_get_materialization_v1_internal(text,text,text,text,text)
  from public, anon, authenticated;

grant execute on function public.farm_watch_claim_materialization_build_v1_internal(text,text,text,text,text,text,integer)
  to postgres, service_role;
grant execute on function public.farm_watch_complete_materialization_build_v1_internal(uuid,uuid,text,text,jsonb,jsonb,jsonb,text,text,text,text,bigint,text,timestamptz)
  to postgres, service_role;
grant execute on function public.farm_watch_fail_materialization_build_v1_internal(uuid,uuid,text,integer)
  to postgres, service_role;
grant execute on function public.farm_watch_get_materialization_v1_internal(text,text,text,text,text)
  to postgres, service_role;
