begin;

create table if not exists farm_watch.property_surface_water_state_v1 (
  property_id uuid not null references farm_watch.properties(id) on delete cascade,
  as_of_date date not null,
  status text not null check (status in ('available','partial','unavailable')),
  context jsonb not null default '{}'::jsonb,
  boundary_sha256 text not null check (boundary_sha256 ~ '^[0-9a-f]{64}$'),
  source_signature text not null,
  source_signature_sha256 text not null check (source_signature_sha256 ~ '^[0-9a-f]{64}$'),
  algorithm_version text not null,
  output_schema_version text not null,
  identity_sha256 text not null check (identity_sha256 ~ '^[0-9a-f]{64}$'),
  retrieved_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (property_id, as_of_date)
);

create index if not exists property_surface_water_state_as_of_idx
  on farm_watch.property_surface_water_state_v1 (as_of_date desc, retrieved_at desc);

alter table farm_watch.property_surface_water_state_v1 enable row level security;
revoke all on farm_watch.property_surface_water_state_v1 from public, anon, authenticated;
grant select, insert, update, delete on farm_watch.property_surface_water_state_v1 to service_role;

create or replace function farm_watch.farm_watch_surface_water_state_contract_v1()
returns jsonb
language sql
immutable
security definer
set search_path='pg_catalog'
as $$
  select jsonb_build_object(
    'algorithm_version','farm-watch-surface-water-state-resolver-v1',
    'output_schema_version','surface-water-state-v1',
    'evidence_class','deterministic_derived',
    'operator_observation_kind','surface_water_presence',
    'mapped_persistence_vocabulary',jsonb_build_array(
      'mapped_persistent','mapped_seasonal','mapped_temporary','mapped_unknown_persistence'
    ),
    'current_presence_vocabulary',jsonb_build_array(
      'observed_present','observed_absent','observed_uncertain','no_current_observation'
    ),
    'dem_drainage_state','geometry_only',
    'dynamic_component_keys',jsonb_build_array(
      'precipitation','drought','stream','rootzone_soil_moisture'
    ),
    'exact_observation_date_required',true
  );
$$;

create or replace function farm_watch.farm_watch_classify_mapped_water_persistence_v1(
  p_source_slug text,
  p_properties jsonb
)
returns text
language plpgsql
immutable
security definer
set search_path='pg_catalog'
as $$
declare
  v_regime text := lower(coalesce(p_properties->>'water_regime_name',''));
begin
  if lower(coalesce(p_source_slug,''))='usfws-nwi' then
    if v_regime like '%permanently flooded%' then return 'mapped_persistent'; end if;
    if v_regime like '%seasonally flooded%' then return 'mapped_seasonal'; end if;
    if v_regime like '%temporary flooded%' or v_regime like '%temporarily flooded%' then
      return 'mapped_temporary';
    end if;
  end if;
  return 'mapped_unknown_persistence';
end;
$$;

create or replace function farm_watch.farm_watch_resolve_surface_water_state_v1_internal(
  p_slug text,
  p_as_of_date date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','farm_watch','extensions'
as $$
declare
  v_property_id uuid;
  v_boundary extensions.geometry;
  v_boundary_sha256 text;
  v_contract jsonb;
  v_algorithm text;
  v_schema text;

  v_expected_hydrology jsonb;
  v_hydrology_state farm_watch.hydrology_refresh_state_v1%rowtype;
  v_hydrology jsonb;
  v_hydrology_status text;
  v_mapped_features jsonb := '[]'::jsonb;

  v_seasonal jsonb;
  v_dynamic jsonb;
  v_seasonal_status text;

  v_terrain_identity text;
  v_terrain_artifact text;
  v_terrain_algorithm text;
  v_terrain_schema text;
  v_terrain_summary jsonb;
  v_terrain_completed_at timestamptz;
  v_dem_drainage jsonb;

  v_current_observations jsonb := '[]'::jsonb;
  v_observation_by_feature jsonb := '{}'::jsonb;

  v_status text;
  v_source_fingerprint jsonb;
  v_source_fingerprint_sha256 text;
  v_source_signature text;
  v_source_signature_sha256 text;
  v_identity_sha256 text;
  v_context jsonb;
begin
  if p_slug is null or p_slug !~ '^[a-z0-9][a-z0-9-]{0,79}$' then
    raise exception 'invalid Farm Watch property slug';
  end if;
  if p_as_of_date is null then
    raise exception 'surface-water as-of date is required';
  end if;

  select p.id,p.boundary
  into v_property_id,v_boundary
  from farm_watch.properties p
  where p.slug=p_slug and p.status='active'
  limit 1;

  if v_property_id is null or v_boundary is null then
    return jsonb_build_object(
      'status','missing',
      'property',jsonb_build_object('slug',p_slug),
      'as_of_date',p_as_of_date,
      'context',null
    );
  end if;

  v_contract := farm_watch.farm_watch_surface_water_state_contract_v1();
  v_algorithm := v_contract->>'algorithm_version';
  v_schema := v_contract->>'output_schema_version';
  v_boundary_sha256 := encode(extensions.digest(extensions.st_asewkb(v_boundary),'sha256'),'hex');

  v_expected_hydrology := farm_watch.farm_watch_context_identity_v1(v_property_id,'hydrology');

  select s.*
  into v_hydrology_state
  from farm_watch.hydrology_refresh_state_v1 s
  where s.property_id=v_property_id
    and s.identity_sha256=v_expected_hydrology->>'identity_sha256'
  limit 1;

  v_hydrology := public.farm_watch_get_hydrology_v1_internal(p_slug);
  v_hydrology_status := coalesce(v_hydrology->>'status','unavailable');

  select coalesce(jsonb_agg(
    jsonb_strip_nulls(jsonb_build_object(
      'feature_key',f->>'id',
      'source_slug',f->'properties'->>'source_slug',
      'feature_kind',f->'properties'->>'feature_kind',
      'source_feature_id',f->'properties'->>'source_feature_id',
      'geometry',f->'geometry',
      'distance_m',nullif(f->'properties'->>'distance_m','')::numeric,
      'intersects_property',coalesce((f->'properties'->>'intersects_property')::boolean,false),
      'mapped_persistence_state',farm_watch.farm_watch_classify_mapped_water_persistence_v1(
        f->'properties'->>'source_slug',f->'properties'
      ),
      'persistence_confidence',case
        when farm_watch.farm_watch_classify_mapped_water_persistence_v1(
          f->'properties'->>'source_slug',f->'properties'
        )='mapped_unknown_persistence' then 'unknown'
        else 'source_attributed'
      end,
      'current_presence',coalesce(
        v_observation_by_feature->(f->>'id'),
        jsonb_build_object('state','no_current_observation')
      ),
      'properties',f->'properties'
    ))
    order by coalesce((f->'properties'->>'distance_m')::numeric,0),f->>'id'
  ),'[]'::jsonb)
  into v_mapped_features
  from jsonb_array_elements(coalesce(v_hydrology->'feature_collection'->'features','[]'::jsonb)) f;

  select coalesce(jsonb_agg(
    jsonb_strip_nulls(jsonb_build_object(
      'observation_key',o.observation_key,
      'observation_state',o.observation_state,
      'current_presence_state',case o.observation_state
        when 'observed_present' then 'observed_present'
        when 'observed_absent' then 'observed_absent'
        else 'observed_uncertain'
      end,
      'persistence_status',o.persistence_status,
      'observed_at',o.observed_at,
      'observed_date_start',o.observed_date_start,
      'observed_date_end',o.observed_date_end,
      'geometry_basis',o.geometry_basis,
      'geometry_precision_m',o.geometry_precision_m,
      'related_feature_key',o.related_feature_key,
      'source_context',o.source_context,
      'notes',o.notes,
      'geometry_geojson',extensions.st_asgeojson(o.geometry)::jsonb,
      'evidence_class','operator_field_observation'
    ))
    order by o.observation_key
  ),'[]'::jsonb)
  into v_current_observations
  from farm_watch.property_operator_observations_v1 o
  where o.property_id=v_property_id
    and o.active
    and o.observation_kind=(v_contract->>'operator_observation_kind')
    and (
      o.observed_at::date=p_as_of_date
      or (
        o.observed_date_start is not null
        and p_as_of_date between o.observed_date_start and coalesce(o.observed_date_end,o.observed_date_start)
      )
    );

  select coalesce(jsonb_object_agg(
    o.related_feature_key,
    jsonb_strip_nulls(jsonb_build_object(
      'state',case o.observation_state
        when 'observed_present' then 'observed_present'
        when 'observed_absent' then 'observed_absent'
        else 'observed_uncertain'
      end,
      'evidence_class','operator_field_observation',
      'observation_key',o.observation_key,
      'observed_date',p_as_of_date,
      'observed_at',o.observed_at,
      'persistence_status',o.persistence_status,
      'geometry_precision_m',o.geometry_precision_m
    ))
  ),'{}'::jsonb)
  into v_observation_by_feature
  from farm_watch.property_operator_observations_v1 o
  where o.property_id=v_property_id
    and o.active
    and o.observation_kind=(v_contract->>'operator_observation_kind')
    and o.related_feature_key is not null
    and (
      o.observed_at::date=p_as_of_date
      or (
        o.observed_date_start is not null
        and p_as_of_date between o.observed_date_start and coalesce(o.observed_date_end,o.observed_date_start)
      )
    );

  -- Rebuild mapped features after exact-date observation indexing.
  select coalesce(jsonb_agg(
    jsonb_strip_nulls(jsonb_build_object(
      'feature_key',f->>'id',
      'source_slug',f->'properties'->>'source_slug',
      'feature_kind',f->'properties'->>'feature_kind',
      'source_feature_id',f->'properties'->>'source_feature_id',
      'geometry',f->'geometry',
      'distance_m',nullif(f->'properties'->>'distance_m','')::numeric,
      'intersects_property',coalesce((f->'properties'->>'intersects_property')::boolean,false),
      'mapped_persistence_state',farm_watch.farm_watch_classify_mapped_water_persistence_v1(
        f->'properties'->>'source_slug',f->'properties'
      ),
      'persistence_confidence',case
        when farm_watch.farm_watch_classify_mapped_water_persistence_v1(
          f->'properties'->>'source_slug',f->'properties'
        )='mapped_unknown_persistence' then 'unknown'
        else 'source_attributed'
      end,
      'current_presence',coalesce(
        v_observation_by_feature->(f->>'id'),
        jsonb_build_object('state','no_current_observation')
      ),
      'properties',f->'properties'
    ))
    order by coalesce((f->'properties'->>'distance_m')::numeric,0),f->>'id'
  ),'[]'::jsonb)
  into v_mapped_features
  from jsonb_array_elements(coalesce(v_hydrology->'feature_collection'->'features','[]'::jsonb)) f;

  v_seasonal := farm_watch.farm_watch_resolve_seasonal_state_v1_internal(p_slug,p_as_of_date);
  v_seasonal_status := coalesce(v_seasonal->>'status','unavailable');
  v_dynamic := jsonb_build_object(
    'qualitative_wetness_state','not_classified',
    'precipitation',coalesce(v_seasonal->'context'->'components'->'precipitation',
      jsonb_build_object('state','unavailable')),
    'drought',coalesce(v_seasonal->'context'->'components'->'drought',
      jsonb_build_object('state','unavailable')),
    'stream',coalesce(v_seasonal->'context'->'components'->'stream',
      jsonb_build_object('state','unavailable')),
    'rootzone_soil_moisture',coalesce(v_seasonal->'context'->'components'->'rootzone_soil_moisture',
      jsonb_build_object('state','unavailable')),
    'interpretation_boundary',
      'Dynamic hydrology components retain their Seasonal State scope/freshness. Surface Water State v1 does not invent wet/dry thresholds or promote off-property proxies to property water presence.'
  );

  select m.identity_sha256,m.artifact_sha256,m.algorithm_version,m.output_schema_version,
         m.summary,m.completed_at
  into v_terrain_identity,v_terrain_artifact,v_terrain_algorithm,v_terrain_schema,
       v_terrain_summary,v_terrain_completed_at
  from farm_watch.property_materializations_v1 m
  where m.property_id=v_property_id
    and m.product_kind='terrain-analysis'
    and m.algorithm_version='phase3-dem-61x61-conditioned-flow-v2'
    and m.completed_at is not null
    and (m.expires_at is null or m.expires_at>now())
  order by m.completed_at desc
  limit 1;

  v_dem_drainage := case
    when v_terrain_identity is null then jsonb_build_object(
      'status','unavailable',
      'state','geometry_only',
      'water_presence_inferred',false,
      'reason','current conditioned D8 terrain materialization is unavailable'
    )
    else jsonb_build_object(
      'status','available',
      'state','geometry_only',
      'product_kind','terrain-analysis',
      'algorithm_version',v_terrain_algorithm,
      'output_schema_version',v_terrain_schema,
      'materialization_identity_sha256',v_terrain_identity,
      'artifact_sha256',v_terrain_artifact,
      'flow_trace_count',nullif(v_terrain_summary->>'flow_trace_count','')::integer,
      'flow_channel_cell_count',nullif(v_terrain_summary->>'flow_channel_cell_count','')::integer,
      'flow_min_contributing_area_acres',nullif(v_terrain_summary->>'flow_min_contributing_area_acres','')::numeric,
      'completed_at',v_terrain_completed_at,
      'water_presence_inferred',false,
      'interpretation_boundary',
        'Conditioned metric D8 flow traces are deterministic drainage geometry only. They do not establish a mapped stream, current water, persistence, crossing condition, or wildlife use.'
    )
  end;

  v_status := case
    when v_hydrology_status in ('available','partial')
      and v_seasonal_status in ('available','partial')
      and v_terrain_identity is not null then 'available'
    when v_hydrology_status in ('available','partial')
      or v_seasonal_status in ('available','partial')
      or v_terrain_identity is not null then 'partial'
    else 'unavailable'
  end;

  v_source_fingerprint := jsonb_build_object(
    'as_of_date',p_as_of_date,
    'hydrology',jsonb_build_object(
      'identity_sha256',v_hydrology_state.identity_sha256,
      'source_signature_sha256',v_hydrology_state.source_signature_sha256,
      'retrieved_at',v_hydrology_state.retrieved_at,
      'source_status',v_hydrology_state.source_status,
      'mapped_feature_count',jsonb_array_length(v_mapped_features)
    ),
    'seasonal_state',jsonb_build_object(
      'identity_sha256',v_seasonal->'identity'->>'identity_sha256',
      'source_signature_sha256',v_seasonal->'identity'->>'source_signature_sha256'
    ),
    'terrain_analysis',jsonb_build_object(
      'identity_sha256',v_terrain_identity,
      'artifact_sha256',v_terrain_artifact
    ),
    'current_operator_observations',v_current_observations
  );
  v_source_fingerprint_sha256 := encode(
    extensions.digest(convert_to(v_source_fingerprint::text,'UTF8'),'sha256'),'hex'
  );
  v_source_signature := concat_ws(
    '|',
    'product=surface-water-state',
    'as_of='||p_as_of_date::text,
    'hydrology_identity='||coalesce(v_hydrology_state.identity_sha256,'unavailable'),
    'seasonal_identity='||coalesce(v_seasonal->'identity'->>'identity_sha256','unavailable'),
    'terrain_identity='||coalesce(v_terrain_identity,'unavailable'),
    'source_fingerprint_sha256='||v_source_fingerprint_sha256
  );
  v_source_signature_sha256 := encode(
    extensions.digest(convert_to(v_source_signature,'UTF8'),'sha256'),'hex'
  );
  v_identity_sha256 := encode(
    extensions.digest(
      convert_to(concat_ws(
        '|',v_property_id::text,p_as_of_date::text,v_algorithm,v_schema,
        v_boundary_sha256,v_source_signature_sha256
      ),'UTF8'),
      'sha256'
    ),
    'hex'
  );

  v_context := jsonb_build_object(
    'schema',v_schema,
    'method',v_algorithm,
    'as_of_date',p_as_of_date,
    'evidence_class','deterministic_derived',
    'hydrology_source_status',v_hydrology_status,
    'mapped_features',v_mapped_features,
    'current_operator_observations',v_current_observations,
    'dynamic_wetness_context',v_dynamic,
    'dem_drainage',v_dem_drainage,
    'summary',jsonb_build_object(
      'mapped_feature_count',jsonb_array_length(v_mapped_features),
      'current_operator_observation_count',jsonb_array_length(v_current_observations),
      'property_intersection_count',(
        select count(*)
        from jsonb_array_elements(v_mapped_features) f
        where coalesce((f->>'intersects_property')::boolean,false)
      ),
      'mapped_persistent_count',(
        select count(*)
        from jsonb_array_elements(v_mapped_features) f
        where f->>'mapped_persistence_state'='mapped_persistent'
      ),
      'mapped_seasonal_count',(
        select count(*)
        from jsonb_array_elements(v_mapped_features) f
        where f->>'mapped_persistence_state'='mapped_seasonal'
      ),
      'mapped_temporary_count',(
        select count(*)
        from jsonb_array_elements(v_mapped_features) f
        where f->>'mapped_persistence_state'='mapped_temporary'
      ),
      'mapped_unknown_persistence_count',(
        select count(*)
        from jsonb_array_elements(v_mapped_features) f
        where f->>'mapped_persistence_state'='mapped_unknown_persistence'
      )
    ),
    'source_fingerprint',v_source_fingerprint,
    'source_fingerprint_sha256',v_source_fingerprint_sha256,
    'scoring_performed',false,
    'behavioral_inference_performed',false,
    'deer_water_preference_inferred',false,
    'interpretation_boundary',
      'Surface Water State v1 separates authoritative mapped hydrography, mapped persistence attributes, deterministic drainage geometry, dated environmental proxies, and direct operator observations. It does not infer water use, deer preference, attraction, movement, habitat quality, or management action.'
  );

  return jsonb_build_object(
    'status',v_status,
    'property',jsonb_build_object('slug',p_slug,'id',v_property_id),
    'as_of_date',p_as_of_date,
    'context',v_context,
    'identity',jsonb_build_object(
      'boundary_sha256',v_boundary_sha256,
      'source_signature',v_source_signature,
      'source_signature_sha256',v_source_signature_sha256,
      'algorithm_version',v_algorithm,
      'output_schema_version',v_schema,
      'identity_sha256',v_identity_sha256
    )
  );
end;
$$;

create or replace function farm_watch.farm_watch_refresh_surface_water_state_v1_internal(
  p_slug text,
  p_as_of_date date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','farm_watch'
as $$
declare
  v_resolved jsonb;
  v_property_id uuid;
begin
  v_resolved := farm_watch.farm_watch_resolve_surface_water_state_v1_internal(p_slug,p_as_of_date);
  if v_resolved->>'status'='missing' then return v_resolved; end if;
  v_property_id := nullif(v_resolved->'property'->>'id','')::uuid;
  if v_property_id is null then raise exception 'resolved surface-water property identity is unavailable'; end if;

  insert into farm_watch.property_surface_water_state_v1(
    property_id,as_of_date,status,context,boundary_sha256,source_signature,
    source_signature_sha256,algorithm_version,output_schema_version,identity_sha256,
    retrieved_at,updated_at
  ) values (
    v_property_id,p_as_of_date,v_resolved->>'status',v_resolved->'context',
    v_resolved->'identity'->>'boundary_sha256',
    v_resolved->'identity'->>'source_signature',
    v_resolved->'identity'->>'source_signature_sha256',
    v_resolved->'identity'->>'algorithm_version',
    v_resolved->'identity'->>'output_schema_version',
    v_resolved->'identity'->>'identity_sha256',
    now(),now()
  )
  on conflict(property_id,as_of_date) do update set
    status=excluded.status,
    context=excluded.context,
    boundary_sha256=excluded.boundary_sha256,
    source_signature=excluded.source_signature,
    source_signature_sha256=excluded.source_signature_sha256,
    algorithm_version=excluded.algorithm_version,
    output_schema_version=excluded.output_schema_version,
    identity_sha256=excluded.identity_sha256,
    retrieved_at=excluded.retrieved_at,
    updated_at=now();

  return farm_watch.farm_watch_get_surface_water_state_v1_internal(p_slug,p_as_of_date);
end;
$$;

create or replace function farm_watch.farm_watch_get_surface_water_state_v1_internal(
  p_slug text,
  p_as_of_date date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','farm_watch','extensions'
as $$
declare
  v_property_id uuid;
  v_boundary extensions.geometry;
  v_boundary_sha256 text;
  v_contract jsonb;
  v_row farm_watch.property_surface_water_state_v1%rowtype;
begin
  select p.id,p.boundary into v_property_id,v_boundary
  from farm_watch.properties p
  where p.slug=p_slug and p.status='active'
  limit 1;

  if v_property_id is null or v_boundary is null then
    return jsonb_build_object('status','missing','property',jsonb_build_object('slug',p_slug),
      'as_of_date',p_as_of_date,'context',null);
  end if;

  select * into v_row
  from farm_watch.property_surface_water_state_v1 s
  where s.property_id=v_property_id and s.as_of_date=p_as_of_date
  limit 1;

  if not found then
    return jsonb_build_object('status','missing','property',jsonb_build_object('slug',p_slug,'id',v_property_id),
      'as_of_date',p_as_of_date,'context',null);
  end if;

  v_boundary_sha256 := encode(extensions.digest(extensions.st_asewkb(v_boundary),'sha256'),'hex');
  v_contract := farm_watch.farm_watch_surface_water_state_contract_v1();

  if v_row.boundary_sha256 is distinct from v_boundary_sha256 then
    return jsonb_build_object(
      'status','stale','property',jsonb_build_object('slug',p_slug,'id',v_property_id),
      'as_of_date',p_as_of_date,'context',null,
      'invalidation_reason','property_boundary_changed',
      'stored_identity_sha256',v_row.identity_sha256
    );
  end if;

  if v_row.algorithm_version is distinct from (v_contract->>'algorithm_version')
     or v_row.output_schema_version is distinct from (v_contract->>'output_schema_version') then
    return jsonb_build_object(
      'status','stale','property',jsonb_build_object('slug',p_slug,'id',v_property_id),
      'as_of_date',p_as_of_date,'context',null,
      'invalidation_reason','surface_water_state_contract_changed',
      'stored_identity_sha256',v_row.identity_sha256
    );
  end if;

  return jsonb_build_object(
    'status',v_row.status,
    'property',jsonb_build_object('slug',p_slug,'id',v_property_id),
    'as_of_date',v_row.as_of_date,
    'context',v_row.context,
    'identity',jsonb_build_object(
      'boundary_sha256',v_row.boundary_sha256,
      'source_signature_sha256',v_row.source_signature_sha256,
      'algorithm_version',v_row.algorithm_version,
      'output_schema_version',v_row.output_schema_version,
      'identity_sha256',v_row.identity_sha256
    ),
    'retrieved_at',v_row.retrieved_at
  );
end;
$$;

revoke all on function farm_watch.farm_watch_surface_water_state_contract_v1() from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_classify_mapped_water_persistence_v1(text,jsonb) from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_resolve_surface_water_state_v1_internal(text,date) from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_refresh_surface_water_state_v1_internal(text,date) from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_get_surface_water_state_v1_internal(text,date) from public,anon,authenticated;

grant execute on function farm_watch.farm_watch_surface_water_state_contract_v1() to postgres,service_role;
grant execute on function farm_watch.farm_watch_classify_mapped_water_persistence_v1(text,jsonb) to postgres,service_role;
grant execute on function farm_watch.farm_watch_resolve_surface_water_state_v1_internal(text,date) to service_role;
grant execute on function farm_watch.farm_watch_refresh_surface_water_state_v1_internal(text,date) to service_role;
grant execute on function farm_watch.farm_watch_get_surface_water_state_v1_internal(text,date) to service_role;

create or replace function public.farm_watch_refresh_surface_water_state_v1_internal(
  p_slug text,
  p_as_of_date date default current_date
)
returns jsonb
language sql
security definer
set search_path='pg_catalog'
as $$
  select farm_watch.farm_watch_refresh_surface_water_state_v1_internal(p_slug,p_as_of_date);
$$;

create or replace function public.farm_watch_get_surface_water_state_v1_internal(
  p_slug text,
  p_as_of_date date default current_date
)
returns jsonb
language sql
stable
security definer
set search_path='pg_catalog'
as $$
  select farm_watch.farm_watch_get_surface_water_state_v1_internal(p_slug,p_as_of_date);
$$;

revoke all on function public.farm_watch_refresh_surface_water_state_v1_internal(text,date)
  from public,anon,authenticated;
revoke all on function public.farm_watch_get_surface_water_state_v1_internal(text,date)
  from public,anon,authenticated;
grant execute on function public.farm_watch_refresh_surface_water_state_v1_internal(text,date) to service_role;
grant execute on function public.farm_watch_get_surface_water_state_v1_internal(text,date) to service_role;

comment on table farm_watch.property_surface_water_state_v1 is
'Date-keyed neutral surface-water state. Separates mapped hydrography/persistence, deterministic drainage geometry, dynamic environmental proxies, and exact-date operator observations; no wildlife-use inference.';

do $$
begin
  if exists(select 1 from cron.job where jobname='farm-watch-surface-water-state-pilot-v1') then
    perform cron.unschedule('farm-watch-surface-water-state-pilot-v1');
  end if;
  perform cron.schedule(
    'farm-watch-surface-water-state-pilot-v1',
    '10 14 * * *',
    $cron$
      select farm_watch.farm_watch_refresh_surface_water_state_v1_internal(
        'validation-property-01',
        current_date
      );
    $cron$
  );
end;
$$;

commit;
