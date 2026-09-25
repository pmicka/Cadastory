begin;

insert into ingest.sources (
  slug,
  name,
  authority,
  source_class,
  geographic_scope,
  acquisition_method,
  update_cadence,
  authority_level,
  status,
  homepage_url,
  license_notes,
  commercial_use_status,
  notes
)
values (
  'landfire-evt-evc',
  'LANDFIRE Existing Vegetation Type + Existing Vegetation Cover',
  'LANDFIRE / U.S. Geological Survey / USDA Forest Service',
  'vegetation_type_cover_raster',
  'United States and LANDFIRE supported extents',
  'Public LANDFIRE ArcGIS ImageServer plus matching versioned EVT/EVC attribute tables; Farm Watch requests a bounded 30 m raster over the current property landscape domain and persists only aggregated derived summaries, hashes, and provenance.',
  'annual / versioned update',
  'federal_authoritative_modeled',
  'active_reference',
  'https://www.landfire.gov/vegetation/evt',
  'LANDFIRE is a U.S. DOI/USDA interagency product. Preserve LANDFIRE product/version attribution and source metadata. The USGS technical documentation notes that the information product is mostly public domain but may contain separately copyrighted materials where noted.',
  'allowed_with_source_caveats',
  'Farm Watch uses EVT lifeform=Tree plus EVT physiognomy=Hardwood as a mapped deciduous/hardwood composition proxy and matching EVC tree-cover percentage for area-weighted canopy context. LANDFIRE advises against treating individual/small groups of pixels as authoritative local measurements; Farm Watch therefore exposes only aggregated property and landscape summaries for M43.'
)
on conflict (slug) do update set
  name=excluded.name,
  authority=excluded.authority,
  source_class=excluded.source_class,
  geographic_scope=excluded.geographic_scope,
  acquisition_method=excluded.acquisition_method,
  update_cadence=excluded.update_cadence,
  authority_level=excluded.authority_level,
  status=excluded.status,
  homepage_url=excluded.homepage_url,
  license_notes=excluded.license_notes,
  commercial_use_status=excluded.commercial_use_status,
  notes=excluded.notes,
  updated_at=now();

create table if not exists farm_watch.property_forest_type_context_v1 (
  property_id uuid primary key references farm_watch.properties(id) on delete cascade,
  status text not null check (status in ('available','unavailable')),
  landfire_version integer not null check (landfire_version between 2024 and 2100),
  context jsonb not null default '{}'::jsonb,
  boundary_sha256 text not null check (boundary_sha256 ~ '^[0-9a-f]{64}$'),
  landscape_domain_identity_sha256 text not null
    check (landscape_domain_identity_sha256 ~ '^[0-9a-f]{64}$'),
  source_signature text not null,
  source_signature_sha256 text not null check (source_signature_sha256 ~ '^[0-9a-f]{64}$'),
  algorithm_version text not null,
  output_schema_version text not null,
  identity_sha256 text not null check (identity_sha256 ~ '^[0-9a-f]{64}$'),
  retrieved_at timestamptz not null,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table farm_watch.property_forest_type_context_v1 enable row level security;
revoke all on farm_watch.property_forest_type_context_v1 from public,anon,authenticated;
grant select,insert,update,delete on farm_watch.property_forest_type_context_v1 to service_role;

create or replace function farm_watch.farm_watch_get_forest_type_context_request_v1_internal(
  p_slug text
)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','farm_watch','extensions'
as $$
declare
  v_property_id uuid;
  v_center extensions.geometry;
  v_boundary extensions.geometry;
  v_local extensions.geometry;
  v_landscape extensions.geometry;
  v_broad extensions.geometry;
  v_domain_identity text;
  v_center_5070 extensions.geometry;
  v_broad_5070 extensions.geometry;
  v_xmin double precision;
  v_ymin double precision;
  v_xmax double precision;
  v_ymax double precision;
  v_width integer;
  v_height integer;
begin
  if p_slug is null
     or length(p_slug)>80
     or p_slug !~ '^[a-z0-9][a-z0-9-]{0,79}$' then
    raise exception 'invalid Farm Watch property slug';
  end if;

  select
    p.id,
    p.center,
    p.boundary,
    d.local_500m,
    d.landscape_1500m,
    d.broad_3000m,
    d.identity_sha256
  into
    v_property_id,
    v_center,
    v_boundary,
    v_local,
    v_landscape,
    v_broad,
    v_domain_identity
  from farm_watch.properties p
  left join farm_watch.property_landscape_domains_v1 d
    on d.property_id=p.id and d.status='available'
  where p.slug=p_slug and p.status='active'
  limit 1;

  if v_property_id is null then
    return jsonb_build_object(
      'status','missing',
      'property',jsonb_build_object('slug',p_slug)
    );
  end if;

  if v_center is null
     or v_boundary is null
     or v_local is null
     or v_landscape is null
     or v_broad is null
     or v_domain_identity is null then
    return jsonb_build_object(
      'status','unavailable',
      'property',jsonb_build_object('slug',p_slug,'id',v_property_id),
      'reason','current property boundary / barrier-aware landscape domain unavailable'
    );
  end if;

  v_center_5070 := extensions.st_transform(v_center,5070);
  v_broad_5070 := extensions.st_transform(v_broad,5070);

  v_xmin := floor(extensions.st_xmin(extensions.st_envelope(v_broad_5070))/30.0)*30.0;
  v_ymin := floor(extensions.st_ymin(extensions.st_envelope(v_broad_5070))/30.0)*30.0;
  v_xmax := ceil(extensions.st_xmax(extensions.st_envelope(v_broad_5070))/30.0)*30.0;
  v_ymax := ceil(extensions.st_ymax(extensions.st_envelope(v_broad_5070))/30.0)*30.0;
  v_width := round((v_xmax-v_xmin)/30.0)::integer;
  v_height := round((v_ymax-v_ymin)/30.0)::integer;

  if v_width < 1
     or v_height < 1
     or v_width*v_height > 300000 then
    raise exception 'unexpected forest type raster request dimensions % x %',v_width,v_height;
  end if;

  return jsonb_build_object(
    'status','available',
    'property',jsonb_build_object(
      'slug',p_slug,
      'id',v_property_id
    ),
    'landscape_domain_identity_sha256',v_domain_identity,
    'evaluation_point',jsonb_build_object(
      'x_5070',round(extensions.st_x(v_center_5070)::numeric,3),
      'y_5070',round(extensions.st_y(v_center_5070)::numeric,3),
      'basis','property_center_internal_source_health_only'
    ),
    'raster_request',jsonb_build_object(
      'crs','EPSG:5070',
      'bbox_5070',jsonb_build_array(v_xmin,v_ymin,v_xmax,v_ymax),
      'width',v_width,
      'height',v_height,
      'pixel_size_m',30
    ),
    'zones_5070',jsonb_build_object(
      'property',extensions.st_asgeojson(extensions.st_transform(v_boundary,5070),6,0)::jsonb,
      'local_500m',extensions.st_asgeojson(extensions.st_transform(v_local,5070),6,0)::jsonb,
      'landscape_1500m',extensions.st_asgeojson(extensions.st_transform(v_landscape,5070),6,0)::jsonb,
      'broad_3000m',extensions.st_asgeojson(v_broad_5070,6,0)::jsonb
    ),
    'persist_property_center',true,
    'pixel_interpretation_exposed',false
  );
end;
$$;

create or replace function farm_watch.farm_watch_record_forest_type_context_v1_internal(
  p_slug text,
  p_landfire_version integer,
  p_context jsonb,
  p_retrieved_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','farm_watch','extensions'
as $$
declare
  v_property_id uuid;
  v_boundary extensions.geometry;
  v_domain_identity text;
  v_boundary_sha256 text;
  v_context_sha256 text;
  v_source_signature text;
  v_source_signature_sha256 text;
  v_identity_sha256 text;
  v_scope text;
  v_scope_json jsonb;
begin
  if p_slug is null
     or length(p_slug)>80
     or p_slug !~ '^[a-z0-9][a-z0-9-]{0,79}$' then
    raise exception 'invalid Farm Watch property slug';
  end if;
  if p_landfire_version is null
     or p_landfire_version < 2024
     or p_landfire_version > 2100 then
    raise exception 'invalid LANDFIRE version';
  end if;
  if p_context is null or jsonb_typeof(p_context)<>'object' then
    raise exception 'forest type context is required';
  end if;

  if p_context->>'schema' <> 'forest-type-context-v1'
     or p_context->>'method' <> 'landfire-evt-evc-deciduous-proxy-v1'
     or p_context->>'status' <> 'available'
     or p_context->>'evidence_class' <> 'mapped_forest_type_canopy_proxy'
     or (p_context#>>'{source,landfire_version}')::integer <> p_landfire_version
     or (p_context#>>'{source,spatial_resolution_m}')::numeric <> 30
     or p_context#>>'{source,native_crs}' <> 'EPSG:5070'
     or p_context#>>'{source_alignment,farm_watch_alignment}' <> 'calibrated_proxy'
     or p_context->>'intactness_metric_performed' <> 'false'
     or p_context->>'behavioral_inference_performed' <> 'false'
     or p_context->>'coefficient_transfer_performed' <> 'false'
     or p_context->>'scoring_performed' <> 'false'
     or p_context#>>'{source_selection,pixel_interpretation_exposed}' <> 'false'
  then
    raise exception 'forest type context violates the M43 product contract';
  end if;

  foreach v_scope in array array[
    'property','local_500m','landscape_1500m','broad_3000m'
  ]
  loop
    v_scope_json := p_context#>(array['summary','scopes',v_scope]);
    if v_scope_json is null
       or coalesce((v_scope_json->>'modeled_cell_count')::integer,0) <= 0
       or coalesce((v_scope_json->>'tree_cell_count')::integer,-1) < 0
       or coalesce((v_scope_json->>'hardwood_cell_count')::integer,-1) < 0
       or (v_scope_json->>'hardwood_cell_count')::integer >
          (v_scope_json->>'tree_cell_count')::integer then
      raise exception 'forest type context scope % is invalid',v_scope;
    end if;
  end loop;

  select p.id,p.boundary,d.identity_sha256
  into v_property_id,v_boundary,v_domain_identity
  from farm_watch.properties p
  join farm_watch.property_landscape_domains_v1 d
    on d.property_id=p.id and d.status='available'
  where p.slug=p_slug and p.status='active'
  limit 1;

  if v_property_id is null or v_boundary is null or v_domain_identity is null then
    return jsonb_build_object(
      'status','missing',
      'property',jsonb_build_object('slug',p_slug)
    );
  end if;

  v_boundary_sha256 := encode(
    extensions.digest(extensions.st_asewkb(v_boundary),'sha256'),
    'hex'
  );
  v_context_sha256 := encode(
    extensions.digest(convert_to(p_context::text,'UTF8'),'sha256'),
    'hex'
  );

  v_source_signature := concat_ws(
    '|',
    'product=forest-type-context',
    'landfire_version='||p_landfire_version::text,
    'evt_service_metadata_sha256='||coalesce(p_context#>>'{source,evt_service_metadata_sha256}',''),
    'evc_service_metadata_sha256='||coalesce(p_context#>>'{source,evc_service_metadata_sha256}',''),
    'evt_attribute_table_sha256='||coalesce(p_context#>>'{source,evt_attribute_table_sha256}',''),
    'evc_attribute_table_sha256='||coalesce(p_context#>>'{source,evc_attribute_table_sha256}',''),
    'evt_export_sha256='||coalesce(p_context#>>'{source,evt_export_sha256}',''),
    'evc_export_sha256='||coalesce(p_context#>>'{source,evc_export_sha256}',''),
    'landscape_domain_identity_sha256='||v_domain_identity,
    'algorithm=landfire-evt-evc-deciduous-proxy-v1',
    'schema=forest-type-context-v1'
  );
  v_source_signature_sha256 := encode(
    extensions.digest(convert_to(v_source_signature,'UTF8'),'sha256'),
    'hex'
  );
  v_identity_sha256 := encode(
    extensions.digest(
      convert_to(concat_ws(
        '|',
        v_property_id::text,
        v_boundary_sha256,
        v_domain_identity,
        v_source_signature_sha256,
        v_context_sha256
      ),'UTF8'),
      'sha256'
    ),
    'hex'
  );

  insert into farm_watch.property_forest_type_context_v1(
    property_id,
    status,
    landfire_version,
    context,
    boundary_sha256,
    landscape_domain_identity_sha256,
    source_signature,
    source_signature_sha256,
    algorithm_version,
    output_schema_version,
    identity_sha256,
    retrieved_at,
    last_error,
    updated_at
  ) values (
    v_property_id,
    'available',
    p_landfire_version,
    p_context,
    v_boundary_sha256,
    v_domain_identity,
    v_source_signature,
    v_source_signature_sha256,
    'landfire-evt-evc-deciduous-proxy-v1',
    'forest-type-context-v1',
    v_identity_sha256,
    p_retrieved_at,
    null,
    now()
  )
  on conflict(property_id) do update set
    status=excluded.status,
    landfire_version=excluded.landfire_version,
    context=excluded.context,
    boundary_sha256=excluded.boundary_sha256,
    landscape_domain_identity_sha256=excluded.landscape_domain_identity_sha256,
    source_signature=excluded.source_signature,
    source_signature_sha256=excluded.source_signature_sha256,
    algorithm_version=excluded.algorithm_version,
    output_schema_version=excluded.output_schema_version,
    identity_sha256=excluded.identity_sha256,
    retrieved_at=excluded.retrieved_at,
    last_error=null,
    updated_at=now();

  return jsonb_build_object(
    'status','available',
    'property',jsonb_build_object('slug',p_slug,'id',v_property_id),
    'landfire_version',p_landfire_version,
    'identity',jsonb_build_object(
      'boundary_sha256',v_boundary_sha256,
      'landscape_domain_identity_sha256',v_domain_identity,
      'source_signature_sha256',v_source_signature_sha256,
      'identity_sha256',v_identity_sha256,
      'algorithm_version','landfire-evt-evc-deciduous-proxy-v1',
      'output_schema_version','forest-type-context-v1'
    )
  );
end;
$$;

create or replace function farm_watch.farm_watch_get_forest_type_context_v1_internal(
  p_slug text
)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','farm_watch'
as $$
declare
  v_property_id uuid;
  v_current_domain_identity text;
  v_row farm_watch.property_forest_type_context_v1%rowtype;
  v_state text;
begin
  select p.id,d.identity_sha256
  into v_property_id,v_current_domain_identity
  from farm_watch.properties p
  left join farm_watch.property_landscape_domains_v1 d
    on d.property_id=p.id and d.status='available'
  where p.slug=p_slug and p.status='active'
  limit 1;

  if v_property_id is null then
    return jsonb_build_object(
      'status','missing',
      'property',jsonb_build_object('slug',p_slug)
    );
  end if;

  select *
  into v_row
  from farm_watch.property_forest_type_context_v1 f
  where f.property_id=v_property_id
  limit 1;

  if v_row.property_id is null then
    return jsonb_build_object(
      'status','not_materialized',
      'property',jsonb_build_object('slug',p_slug,'id',v_property_id)
    );
  end if;

  v_state := case
    when v_row.status <> 'available' then v_row.status
    when v_current_domain_identity is null then 'stale'
    when v_current_domain_identity <> v_row.landscape_domain_identity_sha256 then 'stale'
    when v_row.retrieved_at <= now() - interval '45 days' then 'stale'
    else 'available'
  end;

  return jsonb_build_object(
    'status',v_state,
    'property',jsonb_build_object('slug',p_slug,'id',v_property_id),
    'landfire_version',v_row.landfire_version,
    'identity_sha256',v_row.identity_sha256,
    'algorithm_version',v_row.algorithm_version,
    'output_schema_version',v_row.output_schema_version,
    'retrieved_at',v_row.retrieved_at,
    'context',v_row.context
  );
end;
$$;

create or replace function farm_watch.farm_watch_refresh_forest_type_context_v1_internal(
  p_slug text default 'validation-property-01'
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','farm_watch','vault','extensions'
as $$
declare
  v_token text;
  v_response extensions.http_response;
  v_payload jsonb;
begin
  if p_slug is null
     or length(p_slug)>80
     or p_slug !~ '^[a-z0-9][a-z0-9-]{0,79}$' then
    raise exception 'invalid Farm Watch property slug';
  end if;

  select s.decrypted_secret
  into v_token
  from vault.decrypted_secrets s
  where s.name='farm_watch_materialization_worker_v1'
  limit 1;

  if v_token is null or length(v_token)<32 then
    raise exception 'Farm Watch materialization worker credential unavailable';
  end if;

  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS','60000');
  begin
    select *
    into v_response
    from extensions.http_post(
      'https://ufpkjaadmmpmeogzhrcq.supabase.co/functions/v1/farm-watch-forest-type-context',
      jsonb_build_object(
        'worker_token',v_token,
        'property',p_slug
      )::text,
      'application/json'
    );
  exception when others then
    perform extensions.http_reset_curlopt();
    raise;
  end;
  perform extensions.http_reset_curlopt();

  if v_response.status < 200 or v_response.status >= 300 then
    raise exception 'Farm Watch forest type refresh returned HTTP %: %',
      v_response.status,
      left(coalesce(v_response.content,''),500);
  end if;

  begin
    v_payload := v_response.content::jsonb;
  exception when others then
    raise exception 'Farm Watch forest type refresh returned non-JSON content';
  end;

  if v_payload->>'status' <> 'available' then
    raise exception 'Farm Watch forest type refresh did not materialize: %',
      left(v_response.content,500);
  end if;

  return jsonb_build_object(
    'property',p_slug,
    'http_status',v_response.status,
    'status',v_payload->>'status',
    'landfire_version',v_payload#>>'{context,source,landfire_version}',
    'identity_sha256',v_payload#>>'{materialized,identity,identity_sha256}'
  );
end;
$$;

create or replace function public.farm_watch_get_forest_type_context_request_v1_internal(
  p_slug text
)
returns jsonb
language sql
stable
security definer
set search_path='pg_catalog'
as $$
  select farm_watch.farm_watch_get_forest_type_context_request_v1_internal(p_slug);
$$;

create or replace function public.farm_watch_record_forest_type_context_v1_internal(
  p_slug text,
  p_landfire_version integer,
  p_context jsonb,
  p_retrieved_at timestamptz default now()
)
returns jsonb
language sql
security definer
set search_path='pg_catalog'
as $$
  select farm_watch.farm_watch_record_forest_type_context_v1_internal(
    p_slug,p_landfire_version,p_context,p_retrieved_at
  );
$$;

revoke all on function farm_watch.farm_watch_get_forest_type_context_request_v1_internal(text)
from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_record_forest_type_context_v1_internal(text,integer,jsonb,timestamptz)
from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_get_forest_type_context_v1_internal(text)
from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_refresh_forest_type_context_v1_internal(text)
from public,anon,authenticated;
revoke all on function public.farm_watch_get_forest_type_context_request_v1_internal(text)
from public,anon,authenticated;
revoke all on function public.farm_watch_record_forest_type_context_v1_internal(text,integer,jsonb,timestamptz)
from public,anon,authenticated;

grant execute on function farm_watch.farm_watch_get_forest_type_context_request_v1_internal(text)
to service_role;
grant execute on function farm_watch.farm_watch_record_forest_type_context_v1_internal(text,integer,jsonb,timestamptz)
to service_role;
grant execute on function farm_watch.farm_watch_get_forest_type_context_v1_internal(text)
to service_role;
grant execute on function farm_watch.farm_watch_refresh_forest_type_context_v1_internal(text)
to service_role;
grant execute on function public.farm_watch_get_forest_type_context_request_v1_internal(text)
to service_role;
grant execute on function public.farm_watch_record_forest_type_context_v1_internal(text,integer,jsonb,timestamptz)
to service_role;

do $$
begin
  if exists(
    select 1 from cron.job
    where jobname='farm-watch-forest-type-context-v1'
  ) then
    perform cron.unschedule('farm-watch-forest-type-context-v1');
  end if;

  perform cron.schedule(
    'farm-watch-forest-type-context-v1',
    '13 15 4 * *',
    $cron$
      select farm_watch.farm_watch_refresh_forest_type_context_v1_internal(
        'validation-property-01'
      );
    $cron$
  );
end;
$$;

comment on table farm_watch.property_forest_type_context_v1 is
'Neutral aggregate LANDFIRE EVT/EVC forest-type and canopy context for FW-M43. Hardwood is a documented deciduous-composition proxy; no pixel-level evidence API or biological intactness score is exposed.';

comment on function farm_watch.farm_watch_get_forest_type_context_request_v1_internal(text) is
'Builds the bounded 30 m EPSG:5070 LANDFIRE request and aggregate analysis zones for M43. The property-center point is used only to select a source version with data coverage.';

comment on function farm_watch.farm_watch_record_forest_type_context_v1_internal(text,integer,jsonb,timestamptz) is
'Persists aggregate property/local/landscape/broad forest-type summaries with source-version and raster provenance for M43.';

commit;
