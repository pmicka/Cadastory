begin;

-- P0.3: fail closed when a materialization depends on an external scientific
-- source but the reader did not supply a complete authoritative observation.
-- Static contract identities remain registry metadata only; they are never
-- sufficient by themselves to declare a retained artifact current.

create or replace function farm_watch.farm_watch_compare_materialization_dependency_v1(
  p_source_signature text,
  p_source_provenance jsonb,
  p_dependency jsonb,
  p_current jsonb
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = 'pg_catalog','farm_watch'
as $$
declare
  v_reasons jsonb := '[]'::jsonb;
  v_comparison jsonb;
  v_recorded text;
  v_current text;
  v_normalizer text;
  v_reason text;
begin
  if coalesce(p_current->>'status','unavailable') <> 'available' then
    return jsonb_build_array(
      coalesce(
        p_current->>'reason',
        p_dependency->>'unavailable_reason',
        'dependency_unavailable:' || coalesce(p_dependency->>'key','unknown')
      )
    );
  end if;

  for v_comparison in
    select value
    from jsonb_array_elements(coalesce(p_dependency->'comparisons','[]'::jsonb))
  loop
    v_recorded := farm_watch.farm_watch_recorded_dependency_value_v1(
      p_source_signature,
      coalesce(p_source_provenance,'{}'::jsonb),
      p_dependency,
      v_comparison
    );
    v_current := p_current->>(v_comparison->>'current_field');
    v_normalizer := coalesce(v_comparison->>'normalizer','text');
    v_reason := coalesce(
      v_comparison->>'reason',
      'dependency_identity_changed:' || coalesce(p_dependency->>'key','unknown')
    );

    if v_recorded is null or v_current is null then
      v_reasons := v_reasons || jsonb_build_array(
        'recorded_dependency_binding_missing:' ||
        coalesce(p_dependency->>'key','unknown') || ':' ||
        coalesce(v_comparison->>'current_field','unknown')
      );
    elsif v_normalizer='timestamptz' then
      begin
        if v_recorded::timestamptz is distinct from v_current::timestamptz then
          v_reasons := v_reasons || jsonb_build_array(v_reason);
        end if;
      exception when others then
        v_reasons := v_reasons || jsonb_build_array(
          'recorded_dependency_binding_invalid:' ||
          coalesce(p_dependency->>'key','unknown') || ':' ||
          coalesce(v_comparison->>'current_field','unknown')
        );
      end;
    elsif v_recorded is distinct from v_current then
      v_reasons := v_reasons || jsonb_build_array(v_reason);
    end if;
  end loop;

  return v_reasons;
end;
$$;

create or replace function farm_watch.farm_watch_resolve_materialization_dependency_v1_internal(
  p_property_id uuid,
  p_dependency jsonb,
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
  v_key text := p_dependency->>'key';
  v_kind text := p_dependency->>'kind';
  v_slug text;
  v_current jsonb;
  v_context jsonb;
  v_ref jsonb;
  v_external jsonb;
  v_forcing jsonb;
  v_override jsonb := coalesce(
    p_dependency_overrides->(p_dependency->>'key'),
    '{}'::jsonb
  );
begin
  if p_depth > 12 then
    return jsonb_build_object(
      'key',v_key,
      'kind',v_kind,
      'status','unavailable',
      'reason','dependency_depth_exceeded'
    );
  end if;

  select p.slug into v_slug
  from farm_watch.properties p
  where p.id=p_property_id
    and p.status='active'
  limit 1;

  if v_slug is null and v_kind <> 'external' then
    return jsonb_build_object(
      'key',v_key,
      'kind',v_kind,
      'status','unavailable',
      'reason','property_unavailable'
    );
  end if;

  if v_kind='external' then
    v_external := farm_watch.farm_watch_external_dependency_contract_v1(v_key);

    if v_external is null then
      return jsonb_build_object(
        'key',v_key,
        'kind',v_kind,
        'status','unavailable',
        'authoritative',false,
        'resolution_status','unregistered',
        'reason','external_contract_unregistered'
      );
    end if;

    if jsonb_typeof(v_override) <> 'object'
       or v_override='{}'::jsonb
    then
      return jsonb_build_object(
        'key',v_key,
        'kind',v_kind,
        'status','unavailable',
        'authoritative',false,
        'resolution_status','authoritative_observation_required',
        'contract_identity_sha256',v_external->>'contract_identity_sha256',
        'reason','authoritative_external_observation_required:' || v_key
      );
    end if;

    if coalesce(v_override->>'status','unavailable') <> 'available' then
      return jsonb_strip_nulls(jsonb_build_object(
        'key',v_key,
        'kind',v_kind,
        'status','unavailable',
        'authoritative',false,
        'resolution_status',
          coalesce(v_override->>'resolution_status','provider_observation_unavailable'),
        'contract_identity_sha256',v_external->>'contract_identity_sha256',
        'identity_sha256',v_override->>'identity_sha256',
        'observed_at',v_override->>'observed_at',
        'override_applied',true,
        'reason','authoritative_external_observation_unavailable:' || v_key
      ));
    end if;

    if coalesce(v_override->>'authoritative','false') <> 'true'
       or coalesce(v_override->>'resolution_status','') in (
         '',
         'contract_only',
         'provider_observation_failed',
         'authoritative_observation_required'
       )
    then
      return jsonb_strip_nulls(jsonb_build_object(
        'key',v_key,
        'kind',v_kind,
        'status','unavailable',
        'authoritative',false,
        'resolution_status',
          coalesce(v_override->>'resolution_status','not_authoritative'),
        'contract_identity_sha256',v_external->>'contract_identity_sha256',
        'identity_sha256',v_override->>'identity_sha256',
        'observed_at',v_override->>'observed_at',
        'override_applied',true,
        'reason','authoritative_external_observation_required:' || v_key
      ));
    end if;

    if coalesce(v_override->>'identity_sha256','') !~ '^[0-9a-f]{64}$' then
      return jsonb_strip_nulls(jsonb_build_object(
        'key',v_key,
        'kind',v_kind,
        'status','unavailable',
        'authoritative',false,
        'resolution_status',v_override->>'resolution_status',
        'contract_identity_sha256',v_external->>'contract_identity_sha256',
        'observed_at',v_override->>'observed_at',
        'override_applied',true,
        'reason','authoritative_external_identity_invalid:' || v_key
      ));
    end if;

    return jsonb_strip_nulls(jsonb_build_object(
      'key',v_key,
      'kind',v_kind,
      'status','available',
      'identity_sha256',v_override->>'identity_sha256',
      'resolution_status',v_override->>'resolution_status',
      'authoritative',true,
      'contract_identity_sha256',v_external->>'contract_identity_sha256',
      'observed_at',v_override->>'observed_at',
      'override_applied',true
    ));
  elsif v_kind='context' then
    case p_dependency->>'context_kind'
      when 'landscape-domain' then
        v_context := farm_watch.farm_watch_get_landscape_domain_v1_internal(v_slug);
      when 'landscape-physical' then
        v_context := farm_watch.farm_watch_get_landscape_physical_context_v1_internal(v_slug);
      when 'resource-edge' then
        v_context := farm_watch.farm_watch_get_resource_edge_context_v1_internal(v_slug,false);
      else
        v_context := jsonb_build_object('status','unavailable');
    end case;

    v_current := jsonb_strip_nulls(jsonb_build_object(
      'key',v_key,
      'kind',v_kind,
      'status',coalesce(v_context->>'status','unavailable'),
      'identity_sha256',v_context#>>'{identity,identity_sha256}'
    ));
  elsif v_kind='materialization' then
    v_ref := farm_watch.farm_watch_get_current_materialization_ref_with_overrides_v1_internal(
      p_property_id,
      p_dependency->>'product_kind',
      p_as_of_date,
      p_as_of_at,
      p_dependency_overrides,
      p_depth+1
    );

    v_current := jsonb_strip_nulls(jsonb_build_object(
      'key',v_key,
      'kind',v_kind,
      'status',coalesce(v_ref->>'status','unavailable'),
      'identity_sha256',v_ref#>>'{materialization,identity_sha256}',
      'artifact_sha256',v_ref#>>'{materialization,artifact_sha256}',
      'product_kind',p_dependency->>'product_kind',
      'dependency_manifest_identity_sha256',
        v_ref#>>'{dependency_manifest,identity_sha256}',
      'authoritative_external_resolution_complete',
        v_ref#>'{dependency_manifest,authoritative_external_resolution_complete}',
      'reason_codes',v_ref->'reason_codes'
    ));
  elsif v_kind='temporal'
    and p_dependency->>'resolver'='calendar-date-v1'
  then
    v_current := jsonb_build_object(
      'key',v_key,
      'kind',v_kind,
      'status','available',
      'value',p_as_of_date::text
    );
  elsif v_kind='state'
    and p_dependency->>'resolver'='meteorological-forcing-v1'
  then
    v_forcing := farm_watch.farm_watch_get_meteorological_forcing_v1_internal(
      v_slug,
      p_as_of_at,
      coalesce((p_dependency->>'max_age_minutes')::integer,180),
      coalesce(p_dependency->>'source_state','analysis')
    );

    v_current := jsonb_strip_nulls(jsonb_build_object(
      'key',v_key,
      'kind',v_kind,
      'status',coalesce(v_forcing->>'status','unavailable'),
      'identity_sha256',v_forcing#>>'{identity,identity_sha256}',
      'valid_at',v_forcing->>'valid_at',
      'source_index_sha256',v_forcing#>>'{identity,source_index_sha256}',
      'source_records_sha256',v_forcing#>>'{identity,source_records_sha256}'
    ));
  else
    v_current := jsonb_build_object(
      'key',v_key,
      'kind',v_kind,
      'status','unavailable',
      'reason','unsupported_dependency_resolver'
    );
  end if;

  -- Non-external synthetic overrides remain available to internal tests.
  -- External overrides have already been validated above and may never
  -- manufacture availability from a static contract identity.
  if v_kind <> 'external'
     and jsonb_typeof(v_override)='object'
     and v_override <> '{}'::jsonb
  then
    v_current := v_current || v_override || jsonb_build_object(
      'override_applied',true,
      'resolution_status',
        coalesce(v_override->>'resolution_status','synthetic_override')
    );
  end if;

  return v_current;
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
      'dependencies','[]'::jsonb
    );
  end if;

  for v_dependency in
    select value
    from jsonb_array_elements(coalesce(v_contract->'dependencies','[]'::jsonb))
  loop
    v_current := farm_watch.farm_watch_resolve_materialization_dependency_v1_internal(
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
        (v_current->>'authoritative_external_resolution_complete')::boolean,
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
    'dependencies',v_dependencies
  );

  v_identity := encode(
    extensions.digest(convert_to(v_payload::text,'UTF8'),'sha256'),
    'hex'
  );

  return jsonb_build_object(
    'schema','farm-watch-materialization-dependency-manifest-v1',
    'registry_version',
      farm_watch.farm_watch_materialization_dependency_registry_v1()
        ->>'registry_version',
    'status',case when v_all_available then 'available' else 'blocked' end,
    'product_kind',p_product_kind,
    'algorithm_version',v_contract->>'algorithm_version',
    'output_schema_version',v_contract->>'output_schema_version',
    'as_of_date',p_as_of_date,
    'as_of_at',p_as_of_at,
    'authoritative_external_resolution_complete',
      v_authoritative_external_complete,
    'dependencies',v_dependencies,
    'identity_sha256',v_identity
  );
end;
$$;

create or replace function farm_watch.farm_watch_assert_fail_closed_reader_semantics_v1()
returns void
language plpgsql
stable
security definer
set search_path = 'pg_catalog','farm_watch'
as $$
declare
  v_property_id uuid;
  v_product_kind text;
  v_ref jsonb;
  v_manifest jsonb;
  v_partial jsonb;
begin
  select p.id into v_property_id
  from farm_watch.properties p
  where p.status='active'
  order by p.created_at,p.id
  limit 1;

  if v_property_id is null then
    return;
  end if;

  v_manifest := farm_watch.farm_watch_resolve_materialization_dependency_manifest_v1_internal(
    v_property_id,
    'terrain-analysis',
    current_date,
    now(),
    '{}'::jsonb,
    0
  );

  if coalesce(v_manifest->>'status','') <> 'blocked'
     or coalesce(
       (v_manifest->>'authoritative_external_resolution_complete')::boolean,
       true
     )
  then
    raise exception 'no-observation dependency manifest did not fail closed';
  end if;

  v_partial := jsonb_build_object(
    'external:kyfromabove-phase3-dem',
    jsonb_build_object(
      'status','available',
      'authoritative',true,
      'resolution_status','synthetic_authoritative_test',
      'identity_sha256',repeat('a',64)
    )
  );

  v_manifest := farm_watch.farm_watch_resolve_materialization_dependency_manifest_v1_internal(
    v_property_id,
    'leaf-off-woody-structure',
    current_date,
    now(),
    v_partial,
    0
  );

  if coalesce(v_manifest->>'status','') <> 'blocked'
     or coalesce(
       (v_manifest->>'authoritative_external_resolution_complete')::boolean,
       true
     )
  then
    raise exception 'partial-observation dependency manifest did not fail closed';
  end if;

  -- Regression for the audited old-candidate fallback: a reader with no
  -- provider map may return stale/unavailable metadata, but never "available"
  -- when the recursive manifest says authoritative resolution is incomplete.
  for v_product_kind in
    select distinct m.product_kind
    from farm_watch.property_materializations_v1 m
    where m.property_id=v_property_id
      and m.completed_at is not null
    order by m.product_kind
  loop
    v_ref := farm_watch.farm_watch_get_current_materialization_ref_v1_internal(
      v_property_id,
      v_product_kind,
      current_date,
      now(),
      0
    );

    if coalesce(v_ref->>'status','unavailable')='available'
       and coalesce(
         (
           v_ref#>>'{dependency_manifest,authoritative_external_resolution_complete}'
         )::boolean,
         false
       )=false
    then
      raise exception
        'legacy candidate returned available without authoritative observations: %',
        v_product_kind;
    end if;
  end loop;
end;
$$;

revoke all on function farm_watch.farm_watch_assert_fail_closed_reader_semantics_v1()
  from public,anon,authenticated,service_role;

comment on function farm_watch.farm_watch_assert_fail_closed_reader_semantics_v1() is
'P0.3 regression assertion: no-observation and partial-observation materialization reads must fail closed and may not fall back to a legacy contract-only artifact as current.';

select farm_watch.farm_watch_assert_fail_closed_reader_semantics_v1();

commit;
