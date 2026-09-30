begin;

-- P0.4: bind the current base-property deterministic inputs into canonical
-- materialization freshness. The claim path has always included the property
-- boundary and stated acreage in its input identity; the reader must enforce
-- the same inputs before calling a retained artifact current.

create or replace function farm_watch.farm_watch_property_input_state_v1_internal(
  p_property_id uuid
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = 'pg_catalog','farm_watch','extensions'
as $$
declare
  v_property farm_watch.properties%rowtype;
  v_boundary_sha256 text;
  v_payload jsonb;
  v_identity_sha256 text;
begin
  select * into v_property
  from farm_watch.properties
  where id=p_property_id
    and status='active'
  limit 1;

  if v_property.id is null then
    return jsonb_build_object(
      'status','unavailable',
      'reason','property_unavailable'
    );
  end if;

  if v_property.boundary is null then
    return jsonb_build_object(
      'status','unavailable',
      'property_id',v_property.id,
      'reason','property_boundary_unavailable'
    );
  end if;

  v_boundary_sha256 := encode(
    extensions.digest(
      extensions.st_asewkb(v_property.boundary),
      'sha256'
    ),
    'hex'
  );

  v_payload := jsonb_build_object(
    'property_id',v_property.id,
    'boundary_sha256',v_boundary_sha256,
    'stated_acres',v_property.stated_acres,
    'boundary_srid',extensions.st_srid(v_property.boundary)
  );

  v_identity_sha256 := encode(
    extensions.digest(
      convert_to(v_payload::text,'UTF8'),
      'sha256'
    ),
    'hex'
  );

  return v_payload || jsonb_build_object(
    'status','available',
    'identity_sha256',v_identity_sha256
  );
end;
$$;

create or replace function farm_watch.farm_watch_property_input_mismatches_v1(
  p_recorded_boundary_sha256 text,
  p_recorded_deterministic_inputs jsonb,
  p_current_property_state jsonb
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = 'pg_catalog'
as $$
declare
  v_reasons jsonb := '[]'::jsonb;
begin
  if coalesce(p_current_property_state->>'status','unavailable') <> 'available' then
    return jsonb_build_array(
      coalesce(
        p_current_property_state->>'reason',
        'property_input_state_unavailable'
      )
    );
  end if;

  if p_recorded_boundary_sha256 is null
     or p_recorded_boundary_sha256=''
  then
    v_reasons := v_reasons || jsonb_build_array(
      'recorded_property_input_binding_missing:boundary_sha256'
    );
  elsif p_recorded_boundary_sha256 is distinct from
        p_current_property_state->>'boundary_sha256'
  then
    v_reasons := v_reasons || jsonb_build_array(
      'property_boundary_changed'
    );
  end if;

  if p_recorded_deterministic_inputs is null
     or jsonb_typeof(p_recorded_deterministic_inputs) <> 'object'
     or not (p_recorded_deterministic_inputs ? 'stated_acres')
  then
    v_reasons := v_reasons || jsonb_build_array(
      'recorded_property_input_binding_missing:stated_acres'
    );
  elsif p_recorded_deterministic_inputs->'stated_acres'
        is distinct from p_current_property_state->'stated_acres'
  then
    v_reasons := v_reasons || jsonb_build_array(
      'property_stated_acres_changed'
    );
  end if;

  if p_recorded_deterministic_inputs is null
     or jsonb_typeof(p_recorded_deterministic_inputs) <> 'object'
     or not (p_recorded_deterministic_inputs ? 'boundary_srid')
  then
    v_reasons := v_reasons || jsonb_build_array(
      'recorded_property_input_binding_missing:boundary_srid'
    );
  elsif p_recorded_deterministic_inputs->'boundary_srid'
        is distinct from p_current_property_state->'boundary_srid'
  then
    v_reasons := v_reasons || jsonb_build_array(
      'property_boundary_srid_changed'
    );
  end if;

  return v_reasons;
end;
$$;

create or replace function farm_watch.farm_watch_resolve_materialization_dependency_manifest_v1_internal(
  p_property_id uuid,
  p_product_kind text,
  p_as_of_date date,
  p_as_of_at timestamptz,
  p_dependency_overrides jsonb default '{}'::jsonb,
  p_depth integer default 0
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = 'pg_catalog','farm_watch'
as $$
declare
  v_contract jsonb;
  v_dependency jsonb;
  v_current jsonb;
  v_dependencies jsonb := '[]'::jsonb;
  v_property_input_state jsonb;
  v_all_available boolean := true;
  v_authoritative_external_complete boolean := true;
  v_payload jsonb;
  v_identity text;
begin
  v_contract := farm_watch.farm_watch_materialization_dependency_contract_v1(
    p_product_kind
  );

  if v_contract is null then
    return jsonb_build_object(
      'schema','farm-watch-materialization-dependency-manifest-v1',
      'status','unavailable',
      'reason','unsupported_product_contract',
      'product_kind',p_product_kind,
      'authoritative_external_resolution_complete',false,
      'property_input_state',jsonb_build_object(
        'status','unavailable',
        'reason','unsupported_product_contract'
      ),
      'dependencies','[]'::jsonb
    );
  end if;

  v_property_input_state :=
    farm_watch.farm_watch_property_input_state_v1_internal(
      p_property_id
    );

  if coalesce(
    v_property_input_state->>'status',
    'unavailable'
  ) <> 'available'
  then
    v_all_available := false;
  end if;

  for v_dependency in
    select value
    from jsonb_array_elements(
      coalesce(v_contract->'dependencies','[]'::jsonb)
    )
  loop
    v_current :=
      farm_watch.farm_watch_resolve_materialization_dependency_v1_internal(
        p_property_id,
        v_dependency,
        p_as_of_date,
        p_as_of_at,
        p_dependency_overrides,
        p_depth+1
      );

    v_dependencies := v_dependencies || jsonb_build_array(v_current);

    if coalesce(v_current->>'status','unavailable') <> 'available' then
      v_all_available := false;
    end if;

    if v_current->>'kind'='external' then
      if coalesce(v_current->>'status','unavailable') <> 'available'
         or coalesce(v_current->>'authoritative','false') <> 'true'
         or coalesce(v_current->>'resolution_status','') in (
           '',
           'contract_only',
           'provider_observation_failed',
           'authoritative_observation_required'
         )
      then
        v_authoritative_external_complete := false;
      end if;
    elsif v_current->>'kind'='materialization'
      and coalesce(
        (
          v_current
            ->>'authoritative_external_resolution_complete'
        )::boolean,
        false
      )=false
    then
      v_authoritative_external_complete := false;
    end if;
  end loop;

  v_payload := jsonb_build_object(
    'product_kind',p_product_kind,
    'algorithm_version',v_contract->>'algorithm_version',
    'output_schema_version',v_contract->>'output_schema_version',
    'property_input_state',v_property_input_state,
    'dependencies',v_dependencies
  );

  v_identity := encode(
    extensions.digest(
      convert_to(v_payload::text,'UTF8'),
      'sha256'
    ),
    'hex'
  );

  return jsonb_build_object(
    'schema','farm-watch-materialization-dependency-manifest-v1',
    'registry_version',
      farm_watch.farm_watch_materialization_dependency_registry_v1()
        ->>'registry_version',
    'status',
      case when v_all_available then 'available' else 'blocked' end,
    'product_kind',p_product_kind,
    'algorithm_version',v_contract->>'algorithm_version',
    'output_schema_version',v_contract->>'output_schema_version',
    'as_of_date',p_as_of_date,
    'as_of_at',p_as_of_at,
    'property_input_state',v_property_input_state,
    'authoritative_external_resolution_complete',
      v_authoritative_external_complete,
    'dependencies',v_dependencies,
    'identity_sha256',v_identity
  );
end;
$$;

create or replace function farm_watch.farm_watch_get_current_materialization_ref_with_overrides_v1_internal(
  p_property_id uuid,
  p_product_kind text,
  p_as_of_date date default current_date,
  p_as_of_at timestamptz default now(),
  p_dependency_overrides jsonb default '{}'::jsonb,
  p_depth integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = 'pg_catalog','farm_watch'
as $$
declare
  v_slug text;
  v_contract jsonb;
  v_expected_algorithm text;
  v_expected_schema text;
  v_row farm_watch.property_materializations_v1%rowtype;
  v_latest farm_watch.property_materializations_v1%rowtype;
  v_has_latest boolean := false;
  v_signature text;
  v_recorded_inputs jsonb;
  v_reasons jsonb;
  v_materialization jsonb;
  v_stale_reasons jsonb := '[]'::jsonb;
  v_candidate_seen boolean := false;
  v_manifest jsonb;
begin
  if p_property_id is null
     or p_product_kind is null
     or p_as_of_date is null
     or p_as_of_at is null
  then
    return jsonb_build_object(
      'status','unavailable',
      'reason_codes',jsonb_build_array('invalid_freshness_request')
    );
  end if;

  if p_depth > 12 then
    return jsonb_build_object(
      'status','unavailable',
      'reason_codes',jsonb_build_array('dependency_depth_exceeded')
    );
  end if;

  select p.slug into v_slug
  from farm_watch.properties p
  where p.id=p_property_id
    and p.status='active'
  limit 1;

  if v_slug is null then
    return jsonb_build_object(
      'status','unavailable',
      'reason_codes',jsonb_build_array('property_unavailable')
    );
  end if;

  v_contract :=
    farm_watch.farm_watch_materialization_dependency_contract_v1(
      p_product_kind
    );

  if v_contract is null then
    return jsonb_build_object(
      'status','unavailable',
      'reason_codes',
        jsonb_build_array('unsupported_product_contract'),
      'product_kind',p_product_kind
    );
  end if;

  v_expected_algorithm := v_contract->>'algorithm_version';
  v_expected_schema := v_contract->>'output_schema_version';

  select m.* into v_latest
  from farm_watch.property_materializations_v1 m
  where m.property_id=p_property_id
    and m.product_kind=p_product_kind
    and m.completed_at is not null
  order by m.completed_at desc,m.created_at desc
  limit 1;

  v_has_latest := found;

  v_manifest :=
    farm_watch.farm_watch_resolve_materialization_dependency_manifest_v1_internal(
      p_property_id,
      p_product_kind,
      p_as_of_date,
      p_as_of_at,
      p_dependency_overrides,
      p_depth
    );

  for v_row in
    select m.*
    from farm_watch.property_materializations_v1 m
    where m.property_id=p_property_id
      and m.product_kind=p_product_kind
      and m.algorithm_version=v_expected_algorithm
      and m.output_schema_version=v_expected_schema
      and m.completed_at is not null
    order by m.completed_at desc,m.created_at desc
  loop
    v_candidate_seen := true;
    v_reasons := '[]'::jsonb;
    v_signature := null;
    v_recorded_inputs := null;

    select
      b.source_signature,
      b.deterministic_inputs
    into
      v_signature,
      v_recorded_inputs
    from farm_watch.property_materialization_builds_v1 b
    where b.materialization_id=v_row.id
    order by coalesce(
      b.finished_at,
      b.updated_at,
      b.created_at
    ) desc
    limit 1;

    v_signature := coalesce(
      v_signature,
      v_row.source_provenance->>'source_signature',
      ''
    );

    v_reasons := v_reasons ||
      farm_watch.farm_watch_property_input_mismatches_v1(
        v_row.boundary_sha256,
        v_recorded_inputs,
        v_manifest->'property_input_state'
      );

    if v_row.expires_at is not null
       and v_row.expires_at <= now()
    then
      v_reasons := v_reasons || jsonb_build_array('expired');
    end if;

    if jsonb_array_length(v_reasons)=0 then
      v_reasons := v_reasons ||
        farm_watch.farm_watch_materialization_dependency_mismatches_v1_internal(
          p_property_id,
          p_product_kind,
          v_signature,
          v_row.source_provenance,
          p_as_of_date,
          p_as_of_at,
          p_dependency_overrides,
          p_depth
        );
    end if;

    if jsonb_array_length(v_reasons)=0 then
      v_materialization := jsonb_strip_nulls(jsonb_build_object(
        'id',v_row.id,
        'product_kind',v_row.product_kind,
        'algorithm_version',v_row.algorithm_version,
        'output_schema_version',v_row.output_schema_version,
        'identity_sha256',v_row.identity_sha256,
        'evidence_class',v_row.evidence_class,
        'summary',v_row.summary,
        'source_provenance',v_row.source_provenance,
        'limitations',v_row.limitations,
        'artifact_bucket',v_row.artifact_bucket,
        'artifact_path',v_row.artifact_path,
        'artifact_format',v_row.artifact_format,
        'artifact_mime_type',v_row.artifact_mime_type,
        'artifact_size_bytes',v_row.artifact_size_bytes,
        'artifact_sha256',v_row.artifact_sha256,
        'completed_at',v_row.completed_at,
        'expires_at',v_row.expires_at
      ));

      return jsonb_build_object(
        'status','available',
        'freshness_contract','dependency-aware-materialization-v1',
        'dependency_manifest_schema',v_manifest->>'schema',
        'dependency_manifest',v_manifest,
        'reason_codes','[]'::jsonb,
        'as_of_date',p_as_of_date,
        'as_of_at',p_as_of_at,
        'materialization',v_materialization
      );
    end if;

    if jsonb_array_length(v_stale_reasons)=0 then
      v_stale_reasons := v_reasons;
    end if;
  end loop;

  if not v_candidate_seen and v_has_latest then
    v_stale_reasons := jsonb_build_array(
      'contract_version_mismatch'
    );
  elsif jsonb_array_length(v_stale_reasons)=0
        and v_has_latest
  then
    v_stale_reasons := jsonb_build_array(
      'no_current_materialization'
    );
  end if;

  if v_has_latest then
    v_materialization := jsonb_strip_nulls(jsonb_build_object(
      'id',v_latest.id,
      'product_kind',v_latest.product_kind,
      'algorithm_version',v_latest.algorithm_version,
      'output_schema_version',v_latest.output_schema_version,
      'identity_sha256',v_latest.identity_sha256,
      'evidence_class',v_latest.evidence_class,
      'summary',v_latest.summary,
      'source_provenance',v_latest.source_provenance,
      'limitations',v_latest.limitations,
      'artifact_bucket',v_latest.artifact_bucket,
      'artifact_path',v_latest.artifact_path,
      'artifact_format',v_latest.artifact_format,
      'artifact_mime_type',v_latest.artifact_mime_type,
      'artifact_size_bytes',v_latest.artifact_size_bytes,
      'artifact_sha256',v_latest.artifact_sha256,
      'completed_at',v_latest.completed_at,
      'expires_at',v_latest.expires_at
    ));

    return jsonb_build_object(
      'status','stale',
      'freshness_contract','dependency-aware-materialization-v1',
      'dependency_manifest_schema',v_manifest->>'schema',
      'dependency_manifest',v_manifest,
      'reason_codes',v_stale_reasons,
      'as_of_date',p_as_of_date,
      'as_of_at',p_as_of_at,
      'materialization',v_materialization
    );
  end if;

  return jsonb_build_object(
    'status','unavailable',
    'freshness_contract','dependency-aware-materialization-v1',
    'dependency_manifest_schema',v_manifest->>'schema',
    'dependency_manifest',v_manifest,
    'reason_codes',jsonb_build_array('not_materialized'),
    'as_of_date',p_as_of_date,
    'as_of_at',p_as_of_at,
    'materialization',null
  );
end;
$$;

create or replace function farm_watch.farm_watch_assert_property_input_freshness_v1()
returns void
language plpgsql
stable
security definer
set search_path = 'pg_catalog','farm_watch'
as $$
declare
  v_same jsonb;
  v_boundary_changed jsonb;
  v_acres_changed jsonb;
  v_srid_changed jsonb;
  v_missing jsonb;
  v_current jsonb := jsonb_build_object(
    'status','available',
    'property_id','00000000-0000-0000-0000-000000000001',
    'boundary_sha256',repeat('a',64),
    'stated_acres',42.92,
    'boundary_srid',4326,
    'identity_sha256',repeat('b',64)
  );
  v_recorded jsonb := jsonb_build_object(
    'stated_acres',42.92,
    'boundary_srid',4326
  );
begin
  v_same := farm_watch.farm_watch_property_input_mismatches_v1(
    repeat('a',64),
    v_recorded,
    v_current
  );

  if jsonb_array_length(v_same) <> 0 then
    raise exception
      'matching property inputs were marked stale: %',
      v_same;
  end if;

  v_boundary_changed :=
    farm_watch.farm_watch_property_input_mismatches_v1(
      repeat('c',64),
      v_recorded,
      v_current
    );

  if not (v_boundary_changed ? 'property_boundary_changed') then
    raise exception
      'boundary mutation did not invalidate property input binding';
  end if;

  v_acres_changed :=
    farm_watch.farm_watch_property_input_mismatches_v1(
      repeat('a',64),
      jsonb_build_object(
        'stated_acres',42.93,
        'boundary_srid',4326
      ),
      v_current
    );

  if not (v_acres_changed ? 'property_stated_acres_changed') then
    raise exception
      'stated acreage mutation did not invalidate property input binding';
  end if;

  v_srid_changed :=
    farm_watch.farm_watch_property_input_mismatches_v1(
      repeat('a',64),
      jsonb_build_object(
        'stated_acres',42.92,
        'boundary_srid',3857
      ),
      v_current
    );

  if not (v_srid_changed ? 'property_boundary_srid_changed') then
    raise exception
      'boundary srid mutation did not invalidate property input binding';
  end if;

  v_missing :=
    farm_watch.farm_watch_property_input_mismatches_v1(
      null,
      '{}'::jsonb,
      v_current
    );

  if not (
    v_missing
      ? 'recorded_property_input_binding_missing:boundary_sha256'
    and v_missing
      ? 'recorded_property_input_binding_missing:stated_acres'
    and v_missing
      ? 'recorded_property_input_binding_missing:boundary_srid'
  ) then
    raise exception
      'missing property input binding did not fail closed: %',
      v_missing;
  end if;
end;
$$;

revoke all on function
  farm_watch.farm_watch_property_input_state_v1_internal(uuid)
from public,anon,authenticated,service_role;

revoke all on function
  farm_watch.farm_watch_property_input_mismatches_v1(text,jsonb,jsonb)
from public,anon,authenticated,service_role;

revoke all on function
  farm_watch.farm_watch_assert_property_input_freshness_v1()
from public,anon,authenticated,service_role;

comment on function
  farm_watch.farm_watch_property_input_state_v1_internal(uuid) is
'Canonical current Farm Watch base-property materialization input state: boundary hash, stated acreage, and boundary SRID.';

comment on function
  farm_watch.farm_watch_property_input_mismatches_v1(text,jsonb,jsonb) is
'Compares a retained materialization build property binding with the current canonical property input state.';

comment on function
  farm_watch.farm_watch_assert_property_input_freshness_v1() is
'P0.4 regression assertion: boundary, stated-acreage, SRID, and missing property input bindings must fail closed.';

select farm_watch.farm_watch_assert_property_input_freshness_v1();

commit;
