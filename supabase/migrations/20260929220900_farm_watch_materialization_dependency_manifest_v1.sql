begin;

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
  v_reasons jsonb;
  v_materialization jsonb;
  v_stale_reasons jsonb := '[]'::jsonb;
  v_candidate_seen boolean := false;
  v_manifest jsonb;
begin
  if p_property_id is null or p_product_kind is null or p_as_of_date is null or p_as_of_at is null then
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
  where p.id=p_property_id and p.status='active'
  limit 1;

  if v_slug is null then
    return jsonb_build_object(
      'status','unavailable',
      'reason_codes',jsonb_build_array('property_unavailable')
    );
  end if;

  v_contract := farm_watch.farm_watch_materialization_dependency_contract_v1(p_product_kind);
  if v_contract is null then
    return jsonb_build_object(
      'status','unavailable',
      'reason_codes',jsonb_build_array('unsupported_product_contract'),
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

  v_manifest := farm_watch.farm_watch_resolve_materialization_dependency_manifest_v1_internal(
    p_property_id,p_product_kind,p_as_of_date,p_as_of_at,p_dependency_overrides,p_depth
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

    select b.source_signature into v_signature
    from farm_watch.property_materialization_builds_v1 b
    where b.materialization_id=v_row.id
    order by coalesce(b.finished_at,b.updated_at,b.created_at) desc
    limit 1;
    v_signature := coalesce(v_signature,v_row.source_provenance->>'source_signature','');

    if v_row.expires_at is not null and v_row.expires_at <= now() then
      v_reasons := v_reasons || jsonb_build_array('expired');
    end if;

    if jsonb_array_length(v_reasons)=0 then
      v_reasons := v_reasons || farm_watch.farm_watch_materialization_dependency_mismatches_v1_internal(
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
    v_stale_reasons := jsonb_build_array('contract_version_mismatch');
  elsif jsonb_array_length(v_stale_reasons)=0 and v_has_latest then
    v_stale_reasons := jsonb_build_array('no_current_materialization');
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
  v_override jsonb;
begin
  if p_depth > 12 then
    return jsonb_build_object(
      'key',v_key,'kind',v_kind,'status','unavailable',
      'reason','dependency_depth_exceeded'
    );
  end if;

  select p.slug into v_slug
  from farm_watch.properties p
  where p.id=p_property_id and p.status='active'
  limit 1;

  if v_slug is null and v_kind <> 'external' then
    return jsonb_build_object(
      'key',v_key,'kind',v_kind,'status','unavailable',
      'reason','property_unavailable'
    );
  end if;

  if v_kind='external' then
    v_external := farm_watch.farm_watch_external_dependency_contract_v1(v_key);
    if v_external is null then
      v_current := jsonb_build_object(
        'key',v_key,'kind',v_kind,'status','unavailable',
        'reason','external_contract_unregistered'
      );
    else
      v_current := jsonb_build_object(
        'key',v_key,
        'kind',v_kind,
        'status','available',
        'identity_sha256',v_external->>'contract_identity_sha256',
        'resolution_status',v_external->>'resolution_status',
        'authoritative',coalesce((v_external->>'authoritative')::boolean,false),
        'contract_identity_sha256',v_external->>'contract_identity_sha256'
      );
    end if;
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
      'product_kind',p_dependency->>'product_kind'
    ));
  elsif v_kind='temporal' and p_dependency->>'resolver'='calendar-date-v1' then
    v_current := jsonb_build_object(
      'key',v_key,
      'kind',v_kind,
      'status','available',
      'value',p_as_of_date::text
    );
  elsif v_kind='state' and p_dependency->>'resolver'='meteorological-forcing-v1' then
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
      'key',v_key,'kind',v_kind,'status','unavailable',
      'reason','unsupported_dependency_resolver'
    );
  end if;

  v_override := coalesce(p_dependency_overrides->v_key,'{}'::jsonb);
  if jsonb_typeof(v_override)='object' and v_override <> '{}'::jsonb then
    v_current := v_current || v_override || jsonb_build_object(
      'override_applied',true,
      'resolution_status',coalesce(v_override->>'resolution_status','synthetic_override')
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
  v_contract_only_external boolean := false;
  v_payload jsonb;
  v_identity text;
begin
  v_contract := farm_watch.farm_watch_materialization_dependency_contract_v1(p_product_kind);
  if v_contract is null then
    return jsonb_build_object(
      'schema','farm-watch-materialization-dependency-manifest-v1',
      'status','unavailable',
      'reason','unsupported_product_contract',
      'product_kind',p_product_kind,
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
    if v_current->>'kind'='external' and v_current->>'resolution_status'='contract_only' then
      v_contract_only_external := true;
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
      farm_watch.farm_watch_materialization_dependency_registry_v1()->>'registry_version',
    'status',case when v_all_available then 'available' else 'blocked' end,
    'product_kind',p_product_kind,
    'algorithm_version',v_contract->>'algorithm_version',
    'output_schema_version',v_contract->>'output_schema_version',
    'as_of_date',p_as_of_date,
    'as_of_at',p_as_of_at,
    'authoritative_external_resolution_complete',not v_contract_only_external,
    'dependencies',v_dependencies,
    'identity_sha256',v_identity
  );
end;
$$;

create or replace function farm_watch.farm_watch_materialization_dependency_mismatches_v1_internal(
  p_property_id uuid,
  p_product_kind text,
  p_source_signature text,
  p_source_provenance jsonb,
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
  v_manifest jsonb;
  v_dependency jsonb;
  v_current jsonb;
  v_reasons jsonb := '[]'::jsonb;
begin
  v_contract := farm_watch.farm_watch_materialization_dependency_contract_v1(p_product_kind);
  if v_contract is null then
    return jsonb_build_array('unsupported_product_contract');
  end if;

  v_manifest := farm_watch.farm_watch_resolve_materialization_dependency_manifest_v1_internal(
    p_property_id,p_product_kind,p_as_of_date,p_as_of_at,p_dependency_overrides,p_depth+1
  );

  for v_dependency in
    select value
    from jsonb_array_elements(coalesce(v_contract->'dependencies','[]'::jsonb))
  loop
    select value into v_current
    from jsonb_array_elements(coalesce(v_manifest->'dependencies','[]'::jsonb))
    where value->>'key'=v_dependency->>'key'
    limit 1;

    if v_current is null then
      v_reasons := v_reasons || jsonb_build_array(
        'dependency_resolution_missing:' || coalesce(v_dependency->>'key','unknown')
      );
    else
      v_reasons := v_reasons || farm_watch.farm_watch_compare_materialization_dependency_v1(
        p_source_signature,
        coalesce(p_source_provenance,'{}'::jsonb),
        v_dependency,
        v_current
      );
    end if;
  end loop;

  return v_reasons;
end;
$$;

create or replace function farm_watch.farm_watch_get_current_materialization_ref_v1_internal(
  p_property_id uuid,
  p_product_kind text,
  p_as_of_date date default current_date,
  p_as_of_at timestamptz default now(),
  p_depth integer default 0
)
returns jsonb
language sql
stable
security definer
set search_path = 'pg_catalog'
as $$
  select farm_watch.farm_watch_get_current_materialization_ref_with_overrides_v1_internal(
    p_property_id,
    p_product_kind,
    p_as_of_date,
    p_as_of_at,
    '{}'::jsonb,
    p_depth
  );
$$;

create or replace function farm_watch.farm_watch_assert_materialization_dependency_registry_v1()
returns void
language plpgsql
stable
security definer
set search_path = 'pg_catalog','farm_watch'
as $$
declare
  v_registry jsonb := farm_watch.farm_watch_materialization_dependency_registry_v1();
  v_count integer;
  v_missing integer;
  v_dep jsonb;
  v_current jsonb;
  v_reasons jsonb;
  v_fake_a text := repeat('a',64);
  v_fake_b text := repeat('b',64);
begin
  if v_registry->>'registry_version' <> 'farm-watch-materialization-dependency-registry-v1' then
    raise exception 'materialization dependency registry version mismatch';
  end if;
  if v_registry->>'manifest_schema' <> 'farm-watch-materialization-dependency-manifest-v1' then
    raise exception 'materialization dependency manifest schema mismatch';
  end if;

  select count(*) into v_count
  from jsonb_array_elements(v_registry->'products');
  if v_count <> 14 then
    raise exception 'materialization dependency registry expected 14 products, found %',v_count;
  end if;

  select count(*) into v_missing
  from (
    select distinct m.product_kind
    from farm_watch.property_materializations_v1 m
  ) m
  where farm_watch.farm_watch_materialization_dependency_contract_v1(m.product_kind) is null;
  if v_missing <> 0 then
    raise exception 'materialized product exists without dependency registry contract';
  end if;

  select count(*) into v_missing
  from jsonb_array_elements(v_registry->'products') p,
       lateral jsonb_array_elements(coalesce(p->'dependencies','[]'::jsonb)) d
  where d->>'kind'='materialization'
    and farm_watch.farm_watch_materialization_dependency_contract_v1(d->>'product_kind') is null;
  if v_missing <> 0 then
    raise exception 'materialization dependency references an unregistered product';
  end if;

  with recursive edges as (
    select
      p->>'product_kind' as src,
      d->>'product_kind' as dst
    from jsonb_array_elements(v_registry->'products') p,
         lateral jsonb_array_elements(coalesce(p->'dependencies','[]'::jsonb)) d
    where d->>'kind'='materialization'
  ), walk(root,node,path,cycle) as (
    select src,dst,array[src,dst],src=dst
    from edges
    union all
    select w.root,e.dst,w.path || e.dst,e.dst=any(w.path)
    from walk w
    join edges e on e.src=w.node
    where not w.cycle
  )
  select count(*) into v_missing
  from walk
  where cycle;
  if v_missing <> 0 then
    raise exception 'materialization dependency registry contains a cycle';
  end if;

  select value into v_dep
  from jsonb_array_elements(
    farm_watch.farm_watch_materialization_dependency_contract_v1('terrain-analysis')->'dependencies'
  )
  where value->>'key'='external:kyfromabove-phase3-dem'
  limit 1;
  v_current := farm_watch.farm_watch_external_dependency_contract_v1(
    'external:kyfromabove-phase3-dem'
  );
  v_current := jsonb_build_object(
    'key',v_dep->>'key',
    'kind','external',
    'status','available',
    'identity_sha256',v_current->>'contract_identity_sha256'
  );
  v_reasons := farm_watch.farm_watch_compare_materialization_dependency_v1(
    '', '{}'::jsonb, v_dep, v_current
  );
  if jsonb_array_length(v_reasons) <> 0 then
    raise exception 'baseline external dependency comparison unexpectedly invalidated';
  end if;
  v_current := v_current || jsonb_build_object('identity_sha256',v_fake_a);
  v_reasons := farm_watch.farm_watch_compare_materialization_dependency_v1(
    '', '{}'::jsonb, v_dep, v_current
  );
  if not (v_reasons ? 'kyfromabove_phase3_dem_identity_changed') then
    raise exception 'synthetic external identity change was not detected';
  end if;

  select value into v_dep
  from jsonb_array_elements(
    farm_watch.farm_watch_materialization_dependency_contract_v1('structure-complementarity')->'dependencies'
  )
  where value->>'key'='materialization:lidar-physical-structure'
  limit 1;
  v_current := jsonb_build_object(
    'key',v_dep->>'key',
    'kind','materialization',
    'status','available',
    'artifact_sha256',v_fake_b
  );
  v_reasons := farm_watch.farm_watch_compare_materialization_dependency_v1(
    'lidar_physical_artifact_sha256=' || v_fake_a,
    '{}'::jsonb,
    v_dep,
    v_current
  );
  if not (v_reasons ? 'lidar_physical_artifact_changed') then
    raise exception 'synthetic materialization identity change was not detected';
  end if;

  select value into v_dep
  from jsonb_array_elements(
    farm_watch.farm_watch_materialization_dependency_contract_v1('solar-exposure-context')->'dependencies'
  )
  where value->>'key'='temporal:calendar-date'
  limit 1;
  v_current := jsonb_build_object(
    'key',v_dep->>'key',
    'kind','temporal',
    'status','available',
    'value','2026-09-22'
  );
  v_reasons := farm_watch.farm_watch_compare_materialization_dependency_v1(
    'solar_date=2026-09-21',
    '{}'::jsonb,
    v_dep,
    v_current
  );
  if not (v_reasons ? 'calendar_date_mismatch') then
    raise exception 'synthetic calendar identity change was not detected';
  end if;

  select value into v_dep
  from jsonb_array_elements(
    farm_watch.farm_watch_materialization_dependency_contract_v1('thermal-exposure-context')->'dependencies'
  )
  where value->>'key'='state:meteorological-forcing-analysis'
  limit 1;
  v_current := jsonb_build_object(
    'key',v_dep->>'key',
    'kind','state',
    'status','available',
    'identity_sha256',v_fake_a,
    'valid_at','2026-09-21T21:00:00Z',
    'source_index_sha256',v_fake_a,
    'source_records_sha256',v_fake_b
  );
  v_reasons := farm_watch.farm_watch_compare_materialization_dependency_v1(
    'meteorological_forcing_identity_sha256=' || v_fake_a ||
      '|meteorological_forcing_valid_at=2026-09-21T21:00:00.000Z' ||
      '|source_index_sha256=' || v_fake_a ||
      '|source_records_sha256=' || v_fake_a,
    '{}'::jsonb,
    v_dep,
    v_current
  );
  if not (v_reasons ? 'meteorological_source_records_changed') then
    raise exception 'synthetic meteorological source identity change was not detected';
  end if;
end;
$$;

revoke all on function farm_watch.farm_watch_resolve_materialization_dependency_v1_internal(uuid,jsonb,date,timestamptz,jsonb,integer)
  from public,anon,authenticated,service_role;
revoke all on function farm_watch.farm_watch_resolve_materialization_dependency_manifest_v1_internal(uuid,text,date,timestamptz,jsonb,integer)
  from public,anon,authenticated,service_role;
revoke all on function farm_watch.farm_watch_materialization_dependency_mismatches_v1_internal(uuid,text,text,jsonb,date,timestamptz,jsonb,integer)
  from public,anon,authenticated,service_role;
revoke all on function farm_watch.farm_watch_get_current_materialization_ref_with_overrides_v1_internal(uuid,text,date,timestamptz,jsonb,integer)
  from public,anon,authenticated,service_role;
revoke all on function farm_watch.farm_watch_assert_materialization_dependency_registry_v1()
  from public,anon,authenticated,service_role;

revoke all on function farm_watch.farm_watch_get_current_materialization_ref_v1_internal(uuid,text,date,timestamptz,integer)
  from public,anon,authenticated;
grant execute on function farm_watch.farm_watch_get_current_materialization_ref_v1_internal(uuid,text,date,timestamptz,integer)
  to service_role;

comment on function farm_watch.farm_watch_resolve_materialization_dependency_manifest_v1_internal(uuid,text,date,timestamptz,jsonb,integer) is
'Builds the canonical current dependency manifest for a Farm Watch materialized product. Internal materialization/context/state/date dependencies are resolved now. External dependencies remain explicitly contract_only until P0.2.';
comment on function farm_watch.farm_watch_get_current_materialization_ref_v1_internal(uuid,text,date,timestamptz,integer) is
'Resolves current Farm Watch materializations from the canonical dependency registry and manifest. Retention expiration is one freshness input, not freshness itself. External provider identities remain contract-only until P0.2.';

select farm_watch.farm_watch_assert_materialization_dependency_registry_v1();

commit;
