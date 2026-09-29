begin;

create or replace function farm_watch.farm_watch_external_dependency_signature_key_v1(
  p_dependency_key text
)
returns text
language sql
immutable
set search_path='pg_catalog'
as $$
  select 'external_identity_' ||
    regexp_replace(
      lower(regexp_replace(coalesce(p_dependency_key,''),'^external:','','i')),
      '[^a-z0-9]+','_','g'
    );
$$;

create or replace function farm_watch.farm_watch_recorded_dependency_value_v1(
  p_source_signature text,
  p_source_provenance jsonb,
  p_dependency jsonb,
  p_comparison jsonb
)
returns text
language plpgsql
stable
set search_path='pg_catalog','farm_watch'
as $$
declare
  v_recorded jsonb := p_comparison->'recorded';
  v_source text := v_recorded->>'source';
  v_value text;
  v_path text[];
begin
  if v_source='signature' then
    return farm_watch.farm_watch_source_signature_value_v1(
      p_source_signature,
      v_recorded->>'key'
    );
  elsif v_source='signature_json' then
    v_value := farm_watch.farm_watch_source_signature_value_v1(
      p_source_signature,
      v_recorded->>'key'
    );
    if v_value is null then return null; end if;
    select array_agg(value order by ordinality)
      into v_path
    from jsonb_array_elements_text(v_recorded->'path') with ordinality;
    begin
      return (v_value::jsonb)#>>v_path;
    exception when others then
      return null;
    end;
  elsif v_source='provenance' then
    select array_agg(value order by ordinality)
      into v_path
    from jsonb_array_elements_text(v_recorded->'path') with ordinality;
    return p_source_provenance#>>v_path;
  elsif v_source='external_contract' then
    -- P0.2: new artifacts bind the live provider-observation identity into
    -- the pre-reuse source signature. Pre-P0.2 artifacts intentionally fall
    -- back to the old contract identity, which makes them stale as soon as a
    -- provider-observed override is supplied.
    v_value := farm_watch.farm_watch_source_signature_value_v1(
      p_source_signature,
      farm_watch.farm_watch_external_dependency_signature_key_v1(
        p_dependency->>'key'
      )
    );
    if v_value is not null then return v_value; end if;
    return farm_watch.farm_watch_external_dependency_contract_v1(
      p_dependency->>'key'
    )->>'contract_identity_sha256';
  elsif v_source='literal' then
    return v_recorded->>'value';
  end if;
  return null;
end;
$$;

create or replace function farm_watch.farm_watch_get_materialization_identity_context_v1_internal(
  p_slug text
)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','farm_watch','extensions'
as $$
declare
  v_property farm_watch.properties%rowtype;
begin
  select * into v_property
  from farm_watch.properties
  where slug=p_slug and status='active'
  limit 1;

  if v_property.id is null or v_property.boundary is null then
    return jsonb_build_object('status','unavailable');
  end if;

  return jsonb_build_object(
    'status','available',
    'property_id',v_property.id,
    'property_slug',v_property.slug,
    'stated_acres',v_property.stated_acres,
    'boundary_geojson',extensions.st_asgeojson(v_property.boundary,15)::jsonb
  );
end;
$$;

create or replace function public.farm_watch_get_materialization_identity_context_v1_internal(
  p_slug text
)
returns jsonb
language sql
stable
security definer
set search_path='pg_catalog'
as $$
  select farm_watch.farm_watch_get_materialization_identity_context_v1_internal(p_slug);
$$;

create or replace function farm_watch.farm_watch_get_materialization_external_dependencies_v1_internal(
  p_product_kind text
)
returns jsonb
language sql
immutable
set search_path='pg_catalog','farm_watch'
as $$
  select coalesce(
    jsonb_agg(dep->>'key' order by dep->>'key'),
    '[]'::jsonb
  )
  from jsonb_array_elements(
    coalesce(
      farm_watch.farm_watch_materialization_dependency_contract_v1(p_product_kind)->'dependencies',
      '[]'::jsonb
    )
  ) dep
  where dep->>'kind'='external';
$$;

create or replace function public.farm_watch_get_materialization_external_dependencies_v1_internal(
  p_product_kind text
)
returns jsonb
language sql
immutable
security definer
set search_path='pg_catalog'
as $$
  select farm_watch.farm_watch_get_materialization_external_dependencies_v1_internal(
    p_product_kind
  );
$$;

create or replace function farm_watch.farm_watch_get_all_external_dependencies_v1_internal()
returns jsonb
language sql
immutable
set search_path='pg_catalog','farm_watch'
as $$
  select coalesce(
    jsonb_agg(source->>'key' order by source->>'key'),
    '[]'::jsonb
  )
  from jsonb_array_elements(
    farm_watch.farm_watch_materialization_dependency_registry_v1()->'external_sources'
  ) source;
$$;

create or replace function public.farm_watch_get_all_external_dependencies_v1_internal()
returns jsonb
language sql
immutable
security definer
set search_path='pg_catalog'
as $$
  select farm_watch.farm_watch_get_all_external_dependencies_v1_internal();
$$;

create or replace function farm_watch.farm_watch_apply_materialization_freshness_to_evidence_stack_with_overrides_v1_internal(
  p_base jsonb,
  p_property_id uuid,
  p_as_of_date date,
  p_as_of_at timestamptz,
  p_dependency_overrides jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','farm_watch'
as $$
declare
  v_key text;
  v_product jsonb;
  v_ref jsonb;
  v_materialization jsonb;
  v_products jsonb := '{}'::jsonb;
  v_available integer := 0;
  v_stale integer := 0;
  v_unavailable integer := 0;
  v_status text;
begin
  if p_base is null or p_property_id is null or p_as_of_date is null or p_as_of_at is null then
    return p_base;
  end if;

  for v_key,v_product in
    select key,value
    from jsonb_each(coalesce(p_base->'products','{}'::jsonb))
  loop
    v_ref := farm_watch.farm_watch_get_current_materialization_ref_with_overrides_v1_internal(
      p_property_id,
      v_key,
      p_as_of_date,
      p_as_of_at,
      coalesce(p_dependency_overrides,'{}'::jsonb),
      0
    );
    v_materialization := v_ref->'materialization';
    v_status := coalesce(v_ref->>'status','unavailable');

    v_product := v_product || jsonb_build_object(
      'status',v_status,
      'freshness_contract','authoritative-external-dependency-materialization-v1',
      'freshness_reason_codes',coalesce(v_ref->'reason_codes','[]'::jsonb),
      'dependency_manifest',v_ref->'dependency_manifest'
    );

    if v_materialization is not null and jsonb_typeof(v_materialization)='object' then
      v_product := v_product || jsonb_strip_nulls(jsonb_build_object(
        'algorithm_version',v_materialization->>'algorithm_version',
        'output_schema_version',v_materialization->>'output_schema_version',
        'identity_sha256',v_materialization->>'identity_sha256',
        'evidence_class',v_materialization->>'evidence_class',
        'summary',v_materialization->'summary',
        'source_provenance',v_materialization->'source_provenance',
        'limitations',v_materialization->'limitations',
        'artifact_sha256',v_materialization->>'artifact_sha256',
        'completed_at',v_materialization->>'completed_at',
        'expires_at',v_materialization->>'expires_at'
      ));
    end if;

    v_products := v_products || jsonb_build_object(v_key,v_product);
    if v_status='available' then v_available := v_available + 1;
    elsif v_status='stale' then v_stale := v_stale + 1;
    else v_unavailable := v_unavailable + 1;
    end if;
  end loop;

  return p_base || jsonb_build_object(
    'status',case
      when v_available > 0 then 'available'
      when v_stale > 0 then 'stale'
      else 'unavailable'
    end,
    'as_of_at',p_as_of_at,
    'freshness_contract','authoritative-external-dependency-materialization-v1',
    'counts',jsonb_build_object(
      'available',v_available,
      'stale',v_stale,
      'unavailable',v_unavailable
    ),
    'products',v_products
  );
end;
$$;

create or replace function farm_watch.farm_watch_get_deer_evidence_stack_at_v1_internal(
  p_slug text,
  p_as_of_at timestamptz,
  p_dependency_overrides jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','farm_watch'
as $$
declare
  v_date date;
  v_base jsonb;
  v_property_id uuid;
begin
  if p_as_of_at is null then
    raise exception 'evidence-stack as-of timestamp is required';
  end if;
  v_date := (p_as_of_at at time zone 'America/Kentucky/Louisville')::date;
  v_base := farm_watch.farm_watch_get_deer_evidence_stack_base_v1_internal(
    p_slug,v_date
  );
  v_property_id := nullif(v_base#>>'{property,id}','')::uuid;
  if v_property_id is null then
    return v_base || jsonb_build_object('as_of_at',p_as_of_at);
  end if;

  return farm_watch.farm_watch_apply_materialization_freshness_to_evidence_stack_with_overrides_v1_internal(
    v_base,
    v_property_id,
    v_date,
    p_as_of_at,
    coalesce(p_dependency_overrides,'{}'::jsonb)
  );
end;
$$;

create or replace function public.farm_watch_get_deer_evidence_stack_at_v1_internal(
  p_slug text,
  p_as_of_at timestamptz,
  p_dependency_overrides jsonb
)
returns jsonb
language sql
stable
security definer
set search_path='pg_catalog'
as $$
  select farm_watch.farm_watch_get_deer_evidence_stack_at_v1_internal(
    p_slug,p_as_of_at,p_dependency_overrides
  );
$$;

revoke all on function farm_watch.farm_watch_external_dependency_signature_key_v1(text)
  from public,anon,authenticated;
grant execute on function farm_watch.farm_watch_external_dependency_signature_key_v1(text)
  to service_role;

revoke all on function farm_watch.farm_watch_get_materialization_identity_context_v1_internal(text)
  from public,anon,authenticated;
grant execute on function farm_watch.farm_watch_get_materialization_identity_context_v1_internal(text)
  to service_role;

revoke all on function public.farm_watch_get_materialization_identity_context_v1_internal(text)
  from public,anon,authenticated;
grant execute on function public.farm_watch_get_materialization_identity_context_v1_internal(text)
  to service_role;

revoke all on function farm_watch.farm_watch_get_materialization_external_dependencies_v1_internal(text)
  from public,anon,authenticated;
grant execute on function farm_watch.farm_watch_get_materialization_external_dependencies_v1_internal(text)
  to service_role;

revoke all on function public.farm_watch_get_materialization_external_dependencies_v1_internal(text)
  from public,anon,authenticated;
grant execute on function public.farm_watch_get_materialization_external_dependencies_v1_internal(text)
  to service_role;

revoke all on function farm_watch.farm_watch_get_all_external_dependencies_v1_internal()
  from public,anon,authenticated;
grant execute on function farm_watch.farm_watch_get_all_external_dependencies_v1_internal()
  to service_role;

revoke all on function public.farm_watch_get_all_external_dependencies_v1_internal()
  from public,anon,authenticated;
grant execute on function public.farm_watch_get_all_external_dependencies_v1_internal()
  to service_role;

revoke all on function farm_watch.farm_watch_apply_materialization_freshness_to_evidence_stack_with_overrides_v1_internal(jsonb,uuid,date,timestamptz,jsonb)
  from public,anon,authenticated;
grant execute on function farm_watch.farm_watch_apply_materialization_freshness_to_evidence_stack_with_overrides_v1_internal(jsonb,uuid,date,timestamptz,jsonb)
  to service_role;

revoke all on function farm_watch.farm_watch_get_deer_evidence_stack_at_v1_internal(text,timestamptz,jsonb)
  from public,anon,authenticated;
grant execute on function farm_watch.farm_watch_get_deer_evidence_stack_at_v1_internal(text,timestamptz,jsonb)
  to service_role;

revoke all on function public.farm_watch_get_deer_evidence_stack_at_v1_internal(text,timestamptz,jsonb)
  from public,anon,authenticated;
grant execute on function public.farm_watch_get_deer_evidence_stack_at_v1_internal(text,timestamptz,jsonb)
  to service_role;

comment on function farm_watch.farm_watch_external_dependency_signature_key_v1(text) is
'Maps a canonical external dependency key to the deterministic source-signature token used to bind provider-observed identity before materialization reuse.';
comment on function farm_watch.farm_watch_get_deer_evidence_stack_at_v1_internal(text,timestamptz,jsonb) is
'Exact-time Farm Watch evidence inventory using live authoritative external-source identity overrides resolved by the protected Edge layer.';

commit;
