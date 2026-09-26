begin;

create table if not exists farm_watch.property_conifer_cover_context_v1 (
  property_id uuid primary key references farm_watch.properties(id) on delete cascade,
  status text not null check (status in ('available','partial','unavailable','stale')),
  source_year integer not null,
  context jsonb not null,
  boundary_sha256 text not null check (boundary_sha256 ~ '^[0-9a-f]{64}$'),
  landscape_domain_identity_sha256 text not null check (landscape_domain_identity_sha256 ~ '^[0-9a-f]{64}$'),
  landcover_metadata_sha256 text not null check (landcover_metadata_sha256 ~ '^[0-9a-f]{64}$'),
  tcc_metadata_sha256 text not null check (tcc_metadata_sha256 ~ '^[0-9a-f]{64}$'),
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

alter table farm_watch.property_conifer_cover_context_v1 enable row level security;
revoke all on farm_watch.property_conifer_cover_context_v1 from public,anon,authenticated;
grant select,insert,update,delete on farm_watch.property_conifer_cover_context_v1 to service_role;

create or replace function farm_watch.farm_watch_get_conifer_cover_request_v1_internal(
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
  v_boundary extensions.geometry;
  v_local extensions.geometry;
  v_landscape extensions.geometry;
  v_broad extensions.geometry;
  v_domain_identity text;
  v_boundary_utm extensions.geometry;
  v_local_utm extensions.geometry;
  v_landscape_utm extensions.geometry;
  v_broad_utm extensions.geometry;
  v_xmin double precision;
  v_ymin double precision;
  v_xmax double precision;
  v_ymax double precision;
  v_width integer;
  v_height integer;
begin
  if p_slug is null or length(p_slug)>80 or p_slug !~ '^[a-z0-9][a-z0-9-]{0,79}$' then
    raise exception 'invalid Farm Watch property slug';
  end if;

  select p.id,p.boundary,d.local_500m,d.landscape_1500m,d.broad_3000m,d.identity_sha256
  into v_property_id,v_boundary,v_local,v_landscape,v_broad,v_domain_identity
  from farm_watch.properties p
  left join farm_watch.property_landscape_domains_v1 d
    on d.property_id=p.id and d.status='available'
  where p.slug=p_slug and p.status='active'
  limit 1;

  if v_property_id is null or v_boundary is null then
    return jsonb_build_object('status','missing','property',jsonb_build_object('slug',p_slug));
  end if;
  if v_local is null or v_landscape is null or v_broad is null or v_domain_identity is null then
    return jsonb_build_object(
      'status','unavailable',
      'property',jsonb_build_object('slug',p_slug,'id',v_property_id),
      'reason','current Farm Watch landscape domains are unavailable');
  end if;

  v_boundary_utm := extensions.st_transform(v_boundary,32616);
  v_local_utm := extensions.st_transform(v_local,32616);
  v_landscape_utm := extensions.st_transform(v_landscape,32616);
  v_broad_utm := extensions.st_transform(v_broad,32616);

  v_xmin := floor(extensions.st_xmin(extensions.st_envelope(v_broad_utm))/30.0)*30.0;
  v_ymin := floor(extensions.st_ymin(extensions.st_envelope(v_broad_utm))/30.0)*30.0;
  v_xmax := ceil(extensions.st_xmax(extensions.st_envelope(v_broad_utm))/30.0)*30.0;
  v_ymax := ceil(extensions.st_ymax(extensions.st_envelope(v_broad_utm))/30.0)*30.0;
  v_width := round((v_xmax-v_xmin)/30.0)::integer;
  v_height := round((v_ymax-v_ymin)/30.0)::integer;

  if v_width<1 or v_height<1 or v_width>400 or v_height>400 then
    raise exception 'unexpected M09 raster request dimensions % x %',v_width,v_height;
  end if;

  return jsonb_build_object(
    'status','available',
    'property',jsonb_build_object('slug',p_slug,'id',v_property_id),
    'landscape_domain_identity_sha256',v_domain_identity,
    'domains',jsonb_build_object(
      'property',jsonb_build_object(
        'geometry_utm_geojson',extensions.st_asgeojson(v_boundary_utm)::jsonb,
        'exact_area_ha',round((extensions.st_area(v_boundary_utm)/10000.0)::numeric,4)),
      'local_500m',jsonb_build_object(
        'geometry_utm_geojson',extensions.st_asgeojson(v_local_utm)::jsonb,
        'exact_area_ha',round((extensions.st_area(v_local_utm)/10000.0)::numeric,4)),
      'landscape_1500m',jsonb_build_object(
        'geometry_utm_geojson',extensions.st_asgeojson(v_landscape_utm)::jsonb,
        'exact_area_ha',round((extensions.st_area(v_landscape_utm)/10000.0)::numeric,4)),
      'broad_3000m',jsonb_build_object(
        'geometry_utm_geojson',extensions.st_asgeojson(v_broad_utm)::jsonb,
        'exact_area_ha',round((extensions.st_area(v_broad_utm)/10000.0)::numeric,4))
    ),
    'raster_request',jsonb_build_object(
      'crs','EPSG:32616',
      'bbox_utm',jsonb_build_array(v_xmin,v_ymin,v_xmax,v_ymax),
      'width',v_width,
      'height',v_height,
      'pixel_size_m',30
    )
  );
end;
$$;

create or replace function farm_watch.farm_watch_record_conifer_cover_context_v1_internal(
  p_slug text,
  p_source_year integer,
  p_landcover_metadata_sha256 text,
  p_tcc_metadata_sha256 text,
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
  v_boundary_sha256 text;
  v_domain_identity text;
  v_context_sha256 text;
  v_landcover_raster_sha256 text;
  v_tcc_raster_sha256 text;
  v_source_signature text;
  v_source_signature_sha256 text;
  v_identity_sha256 text;
  v_key text;
begin
  if p_slug is null or length(p_slug)>80 or p_slug !~ '^[a-z0-9][a-z0-9-]{0,79}$' then raise exception 'invalid Farm Watch property slug'; end if;
  if p_source_year is null or p_source_year<1985 or p_source_year>2100 then raise exception 'invalid M09 source year'; end if;
  if p_landcover_metadata_sha256 is null or p_landcover_metadata_sha256 !~ '^[0-9a-f]{64}$' then raise exception 'invalid land-cover metadata hash'; end if;
  if p_tcc_metadata_sha256 is null or p_tcc_metadata_sha256 !~ '^[0-9a-f]{64}$' then raise exception 'invalid TCC metadata hash'; end if;
  if p_context is null or jsonb_typeof(p_context)<>'object' then raise exception 'M09 context is required'; end if;

  if p_context->>'schema' <> 'conifer-cover-context-v1'
     or p_context->>'method' <> 'delgiudice-conifer-availability-source-substitution-v1'
     or p_context->>'evidence_state' <> 'proxy'
     or p_context->>'measurement_alignment' <> 'calibrated_proxy'
     or p_context#>>'{source_reconciliation,landcover,slug}' <> 'usgs-annual-nlcd-land-cover'
     or p_context#>>'{source_reconciliation,canopy,slug}' <> 'nlcd-tree-canopy-cover-2025'
     or (p_context#>>'{source_reconciliation,common_source_year}')::integer <> p_source_year
     or (p_context#>>'{source_reconciliation,landcover,source_year}')::integer <> p_source_year
     or (p_context#>>'{source_reconciliation,canopy,source_year}')::integer <> p_source_year
     or (p_context#>>'{raster_support,pixel_width_m}')::numeric <> 30
     or (p_context#>>'{raster_support,pixel_height_m}')::numeric <> 30
     or p_context#>>'{source_reconciliation,landcover,mixed_forest_treatment,treatment}' <> 'other'
     or p_context->>'deer_inference_performed' <> 'false'
     or p_context->>'coefficient_transfer_performed' <> 'false'
     or p_context->>'scoring_performed' <> 'false'
  then raise exception 'M09 conifer-cover context violates product contract'; end if;

  foreach v_key in array array['property','local_500m','landscape_1500m','broad_3000m']
  loop
    if p_context#>>array['domains',v_key,'status'] <> 'available'
       or jsonb_typeof(p_context#>array['domains',v_key,'study_availability']) <> 'object'
       or not ((p_context#>array['domains',v_key,'study_availability']) ?& array[
         'moderately_dense_conifer','dense_conifer','other'
       ])
    then raise exception 'M09 domain contract incomplete: %',v_key; end if;
  end loop;

  v_landcover_raster_sha256 := p_context#>>'{source_reconciliation,landcover,exported_raster_sha256}';
  v_tcc_raster_sha256 := p_context#>>'{source_reconciliation,canopy,exported_raster_sha256}';
  if v_landcover_raster_sha256 is null or v_landcover_raster_sha256 !~ '^[0-9a-f]{64}$'
     or v_tcc_raster_sha256 is null or v_tcc_raster_sha256 !~ '^[0-9a-f]{64}$'
  then raise exception 'M09 raster source hash unavailable'; end if;

  select p.id,p.boundary,d.identity_sha256
  into v_property_id,v_boundary,v_domain_identity
  from farm_watch.properties p
  left join farm_watch.property_landscape_domains_v1 d on d.property_id=p.id and d.status='available'
  where p.slug=p_slug and p.status='active'
  limit 1;

  if v_property_id is null or v_boundary is null then
    return jsonb_build_object('status','missing','property',jsonb_build_object('slug',p_slug));
  end if;
  if v_domain_identity is null then raise exception 'current Farm Watch landscape domain unavailable'; end if;
  if p_context->>'landscape_domain_identity_sha256' is distinct from v_domain_identity then
    raise exception 'M09 landscape-domain identity is stale';
  end if;

  v_boundary_sha256 := encode(extensions.digest(extensions.st_asewkb(v_boundary),'sha256'),'hex');
  v_context_sha256 := encode(extensions.digest(convert_to(p_context::text,'UTF8'),'sha256'),'hex');
  v_source_signature := concat_ws(
    '|',
    'product=conifer-cover-context',
    'common_year='||p_source_year::text,
    'landcover=annual_nlcd_42_evergreen',
    'mixed_forest_43=other',
    'tcc=nlcd_tree_canopy_cover',
    'bins=<40:other_open_conifer|40-<70:moderate|>=70:dense',
    'landcover_metadata_sha256='||p_landcover_metadata_sha256,
    'tcc_metadata_sha256='||p_tcc_metadata_sha256,
    'landcover_raster_sha256='||v_landcover_raster_sha256,
    'tcc_raster_sha256='||v_tcc_raster_sha256,
    'landscape_domain_identity='||v_domain_identity,
    'algorithm=delgiudice-conifer-availability-source-substitution-v1',
    'schema=conifer-cover-context-v1'
  );
  v_source_signature_sha256 := encode(extensions.digest(convert_to(v_source_signature,'UTF8'),'sha256'),'hex');
  v_identity_sha256 := encode(extensions.digest(convert_to(concat_ws(
    '|',v_property_id::text,v_boundary_sha256,v_source_signature_sha256,v_context_sha256
  ),'UTF8'),'sha256'),'hex');

  insert into farm_watch.property_conifer_cover_context_v1(
    property_id,status,source_year,context,boundary_sha256,landscape_domain_identity_sha256,
    landcover_metadata_sha256,tcc_metadata_sha256,source_signature,source_signature_sha256,
    algorithm_version,output_schema_version,identity_sha256,retrieved_at,last_error,updated_at
  ) values (
    v_property_id,'available',p_source_year,p_context,v_boundary_sha256,v_domain_identity,
    p_landcover_metadata_sha256,p_tcc_metadata_sha256,v_source_signature,v_source_signature_sha256,
    'delgiudice-conifer-availability-source-substitution-v1','conifer-cover-context-v1',
    v_identity_sha256,coalesce(p_retrieved_at,now()),null,now()
  )
  on conflict(property_id) do update set
    status=excluded.status,source_year=excluded.source_year,context=excluded.context,
    boundary_sha256=excluded.boundary_sha256,
    landscape_domain_identity_sha256=excluded.landscape_domain_identity_sha256,
    landcover_metadata_sha256=excluded.landcover_metadata_sha256,
    tcc_metadata_sha256=excluded.tcc_metadata_sha256,
    source_signature=excluded.source_signature,
    source_signature_sha256=excluded.source_signature_sha256,
    algorithm_version=excluded.algorithm_version,
    output_schema_version=excluded.output_schema_version,
    identity_sha256=excluded.identity_sha256,
    retrieved_at=excluded.retrieved_at,last_error=null,updated_at=now();

  return jsonb_build_object(
    'status','available',
    'property',jsonb_build_object('slug',p_slug,'id',v_property_id),
    'source_year',p_source_year,
    'identity',jsonb_build_object(
      'boundary_sha256',v_boundary_sha256,
      'landscape_domain_identity_sha256',v_domain_identity,
      'source_signature_sha256',v_source_signature_sha256,
      'identity_sha256',v_identity_sha256,
      'algorithm_version','delgiudice-conifer-availability-source-substitution-v1',
      'output_schema_version','conifer-cover-context-v1'
    )
  );
end;
$$;

create or replace function farm_watch.farm_watch_get_conifer_cover_context_v1_internal(
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
  v_boundary extensions.geometry;
  v_boundary_sha256 text;
  v_domain_identity text;
  v_row farm_watch.property_conifer_cover_context_v1%rowtype;
begin
  select p.id,p.boundary,d.identity_sha256
  into v_property_id,v_boundary,v_domain_identity
  from farm_watch.properties p
  left join farm_watch.property_landscape_domains_v1 d on d.property_id=p.id and d.status='available'
  where p.slug=p_slug and p.status='active'
  limit 1;

  if v_property_id is null or v_boundary is null then
    return jsonb_build_object('status','missing','property',jsonb_build_object('slug',p_slug));
  end if;

  select * into v_row from farm_watch.property_conifer_cover_context_v1 c
  where c.property_id=v_property_id limit 1;
  if v_row.property_id is null then
    return jsonb_build_object('status','not_materialized','property',jsonb_build_object('slug',p_slug,'id',v_property_id));
  end if;

  v_boundary_sha256 := encode(extensions.digest(extensions.st_asewkb(v_boundary),'sha256'),'hex');
  if v_row.boundary_sha256 is distinct from v_boundary_sha256 then
    return jsonb_build_object(
      'status','stale','property',jsonb_build_object('slug',p_slug,'id',v_property_id),
      'invalidation_reason','property_boundary_changed','stored_identity_sha256',v_row.identity_sha256);
  end if;
  if v_domain_identity is null or v_row.landscape_domain_identity_sha256 is distinct from v_domain_identity then
    return jsonb_build_object(
      'status','stale','property',jsonb_build_object('slug',p_slug,'id',v_property_id),
      'invalidation_reason','landscape_domain_changed','stored_identity_sha256',v_row.identity_sha256);
  end if;

  return jsonb_build_object(
    'status',v_row.status,
    'property',jsonb_build_object('slug',p_slug,'id',v_property_id),
    'source_year',v_row.source_year,
    'identity_sha256',v_row.identity_sha256,
    'algorithm_version',v_row.algorithm_version,
    'output_schema_version',v_row.output_schema_version,
    'retrieved_at',v_row.retrieved_at,
    'context',v_row.context
  );
end;
$$;

create or replace function farm_watch.farm_watch_refresh_conifer_cover_context_v1_internal(
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
  if p_slug is null or length(p_slug)>80 or p_slug !~ '^[a-z0-9][a-z0-9-]{0,79}$' then raise exception 'invalid Farm Watch property slug'; end if;
  select s.decrypted_secret into v_token from vault.decrypted_secrets s where s.name='farm_watch_materialization_worker_v1' limit 1;
  if v_token is null or length(v_token)<32 then raise exception 'Farm Watch materialization worker credential unavailable'; end if;

  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS','90000');
  begin
    select * into v_response from extensions.http_post(
      'https://ufpkjaadmmpmeogzhrcq.supabase.co/functions/v1/farm-watch-conifer-cover-context',
      jsonb_build_object('worker_token',v_token,'property',p_slug)::text,'application/json');
  exception when others then
    perform extensions.http_reset_curlopt();
    raise;
  end;
  perform extensions.http_reset_curlopt();

  if v_response.status<200 or v_response.status>=300 then
    raise exception 'Farm Watch M09 refresh returned HTTP %: %',v_response.status,left(coalesce(v_response.content,''),500);
  end if;
  begin v_payload := v_response.content::jsonb; exception when others then raise exception 'Farm Watch M09 refresh returned non-JSON content'; end;
  if v_payload->>'status' <> 'available' then
    raise exception 'Farm Watch M09 refresh did not materialize: %',left(v_response.content,500);
  end if;

  return jsonb_build_object(
    'property',p_slug,
    'http_status',v_response.status,
    'status',v_payload->>'status',
    'source_year',v_payload#>>'{context,source_reconciliation,common_source_year}',
    'identity_sha256',v_payload#>>'{materialized,identity,identity_sha256}'
  );
end;
$$;

create or replace function public.farm_watch_get_conifer_cover_request_v1_internal(p_slug text)
returns jsonb
language sql
stable
security definer
set search_path='pg_catalog'
as $$ select farm_watch.farm_watch_get_conifer_cover_request_v1_internal(p_slug); $$;

create or replace function public.farm_watch_record_conifer_cover_context_v1_internal(
  p_slug text,
  p_source_year integer,
  p_landcover_metadata_sha256 text,
  p_tcc_metadata_sha256 text,
  p_context jsonb,
  p_retrieved_at timestamptz default now()
)
returns jsonb
language sql
security definer
set search_path='pg_catalog'
as $$ select farm_watch.farm_watch_record_conifer_cover_context_v1_internal(
  p_slug,p_source_year,p_landcover_metadata_sha256,p_tcc_metadata_sha256,p_context,p_retrieved_at
); $$;

revoke all on function farm_watch.farm_watch_get_conifer_cover_request_v1_internal(text) from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_record_conifer_cover_context_v1_internal(text,integer,text,text,jsonb,timestamptz) from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_get_conifer_cover_context_v1_internal(text) from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_refresh_conifer_cover_context_v1_internal(text) from public,anon,authenticated;
revoke all on function public.farm_watch_get_conifer_cover_request_v1_internal(text) from public,anon,authenticated;
revoke all on function public.farm_watch_record_conifer_cover_context_v1_internal(text,integer,text,text,jsonb,timestamptz) from public,anon,authenticated;

grant execute on function farm_watch.farm_watch_get_conifer_cover_request_v1_internal(text) to service_role;
grant execute on function farm_watch.farm_watch_record_conifer_cover_context_v1_internal(text,integer,text,text,jsonb,timestamptz) to service_role;
grant execute on function farm_watch.farm_watch_get_conifer_cover_context_v1_internal(text) to service_role;
grant execute on function farm_watch.farm_watch_refresh_conifer_cover_context_v1_internal(text) to service_role;
grant execute on function public.farm_watch_get_conifer_cover_request_v1_internal(text) to service_role;
grant execute on function public.farm_watch_record_conifer_cover_context_v1_internal(text,integer,text,text,jsonb,timestamptz) to service_role;

CREATE OR REPLACE FUNCTION farm_watch.farm_watch_get_deer_evidence_stack_v1_internal(p_slug text, p_as_of_date date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'farm_watch'
AS $function$
declare
  v_property_id uuid; v_products jsonb; v_surface_water jsonb; v_mast_resource jsonb;
  v_human_footprint jsonb; v_multiscale_cover jsonb; v_multiscale_forest jsonb;
  v_forest_type jsonb; v_conifer_cover jsonb; v_snow_winter jsonb; v_extreme_weather jsonb;
  v_available_count integer := 0; v_stale_count integer := 0; v_unavailable_count integer := 0;
begin
  if p_slug is null or length(p_slug)>80 or left(p_slug,1)='-' or p_slug ~ '[^a-z0-9-]' then raise exception 'invalid Farm Watch property slug'; end if;
  if p_as_of_date is null then raise exception 'evidence-stack as-of date is required'; end if;
  select p.id into v_property_id from farm_watch.properties p where p.slug=p_slug and p.status='active' limit 1;

  if v_property_id is null then
    return jsonb_build_object(
      'status','missing','schema','deer-evidence-stack-v1','as_of_date',p_as_of_date,
      'property',jsonb_build_object('slug',p_slug),'products','{}'::jsonb,
      'surface_water_state',jsonb_build_object('status','missing'),
      'mast_resource_context',jsonb_build_object('status','missing'),
      'human_footprint_context',jsonb_build_object('status','missing'),
      'multiscale_cover_context',jsonb_build_object('status','missing'),
      'multiscale_forest_context',jsonb_build_object('status','missing'),
      'forest_type_context',jsonb_build_object('status','missing'),
      'conifer_cover_context',jsonb_build_object('status','missing'),
      'snow_winter_severity_context',jsonb_build_object('status','missing'),
      'extreme_weather_event_context',jsonb_build_object('status','missing'));
  end if;

  with wanted(product_kind,display_name,category,sort_order) as (values
    ('lidar-physical-structure','LiDAR physical vertical structure','physical_structure',10),
    ('landscape-structure-context','Landscape physical structure','physical_structure',20),
    ('terrain-form-permeability','Terrain form / permeability','terrain',30),
    ('spatial-edge-patch-context','Spatial edge / patch context','terrain',40),
    ('solar-exposure-context','Potential solar exposure','thermal_light',50),
    ('thermal-exposure-context','Thermal exposure context','thermal_light',60),
    ('horizontal-visibility-context','Horizontal visibility / obstruction','visibility',70),
    ('mast-capacity','Mast-producing species capacity','resources',80)
  ), latest as (
    select distinct on (m.product_kind)
      m.product_kind,m.algorithm_version,m.output_schema_version,m.identity_sha256,m.evidence_class,
      m.summary,m.source_provenance,m.limitations,m.artifact_sha256,m.completed_at,m.expires_at
    from farm_watch.property_materializations_v1 m
    where m.property_id=v_property_id and m.product_kind in (select product_kind from wanted)
      and m.completed_at is not null
    order by m.product_kind,m.completed_at desc,m.created_at desc
  ), rows as (
    select w.product_kind,w.display_name,w.category,w.sort_order,
      case when l.product_kind is null then 'unavailable'
           when l.expires_at is not null and l.expires_at <= now() then 'stale' else 'available' end as state,
      l.algorithm_version,l.output_schema_version,l.identity_sha256,l.evidence_class,l.summary,
      l.source_provenance,l.limitations,l.artifact_sha256,l.completed_at,l.expires_at
    from wanted w left join latest l using(product_kind)
  )
  select coalesce(jsonb_object_agg(
      r.product_kind,jsonb_strip_nulls(jsonb_build_object(
        'product_kind',r.product_kind,'display_name',r.display_name,'category',r.category,'sort_order',r.sort_order,
        'status',r.state,'algorithm_version',r.algorithm_version,'output_schema_version',r.output_schema_version,
        'identity_sha256',r.identity_sha256,'evidence_class',r.evidence_class,'summary',r.summary,
        'source_provenance',r.source_provenance,'limitations',r.limitations,'artifact_sha256',r.artifact_sha256,
        'completed_at',r.completed_at,'expires_at',r.expires_at)) order by r.sort_order),'{}'::jsonb),
    count(*) filter(where r.state='available'),count(*) filter(where r.state='stale'),count(*) filter(where r.state='unavailable')
  into v_products,v_available_count,v_stale_count,v_unavailable_count from rows r;

  if to_regclass('farm_watch.property_surface_water_state_v1') is not null then
    execute $q$select jsonb_strip_nulls(jsonb_build_object(
      'status',s.status,'as_of_date',s.as_of_date,'identity_sha256',s.identity_sha256,'algorithm_version',s.algorithm_version,
      'output_schema_version',s.output_schema_version,'retrieved_at',s.retrieved_at,'context',s.context))
      from farm_watch.property_surface_water_state_v1 s where s.property_id=$1 and s.as_of_date=$2 limit 1$q$
    into v_surface_water using v_property_id,p_as_of_date;
  end if;
  if v_surface_water is null then v_surface_water := jsonb_build_object(
    'status',case when to_regclass('farm_watch.property_surface_water_state_v1') is null then 'not_deployed' else 'not_materialized' end,
    'as_of_date',p_as_of_date,'interpretation_boundary','Surface Water State v1 is not available for this date. Existing mapped hydrography and Seasonal State evidence remain separate inputs.'); end if;

  if to_regclass('farm_watch.property_mast_resource_context_v1') is not null then
    execute $q$select jsonb_strip_nulls(jsonb_build_object(
      'status',m.status,'survey_year',m.survey_year,'identity_sha256',m.identity_sha256,'algorithm_version',m.algorithm_version,
      'output_schema_version',m.output_schema_version,'retrieved_at',m.retrieved_at,'context',m.context))
      from farm_watch.property_mast_resource_context_v1 m where m.property_id=$1 and m.survey_year=$2 limit 1$q$
    into v_mast_resource using v_property_id,extract(year from p_as_of_date)::integer;
  end if;
  if v_mast_resource is null then v_mast_resource := jsonb_build_object(
    'status',case when to_regclass('farm_watch.property_mast_resource_context_v1') is null then 'not_deployed' else 'not_materialized' end,
    'survey_year',extract(year from p_as_of_date)::integer,'interpretation_boundary','Mast Resource Context v1 is not materialized for this survey year. Mast Capacity remains a separate neutral product and no annual mast state is inferred.'); end if;

  if to_regclass('farm_watch.property_human_footprint_context_v1') is not null then
    select jsonb_strip_nulls(jsonb_build_object(
      'status',h.status,'identity_sha256',h.identity_sha256,'algorithm_version',h.algorithm_version,
      'output_schema_version',h.output_schema_version,'retrieved_at',h.retrieved_at,'context',h.context))
    into v_human_footprint from farm_watch.property_human_footprint_context_v1 h where h.property_id=v_property_id limit 1;
  end if;
  if v_human_footprint is null then v_human_footprint := jsonb_build_object(
    'status',case when to_regclass('farm_watch.property_human_footprint_context_v1') is null then 'not_deployed' else 'not_materialized' end,
    'interpretation_boundary','Human Footprint Context v1 is not available. No building-density or road-response inference is substituted.'); end if;

  if to_regclass('farm_watch.property_study_scale_windows_v1') is not null then
    v_multiscale_cover := farm_watch.farm_watch_get_multiscale_cover_context_v1_internal(p_slug);
  end if;
  if v_multiscale_cover is null then v_multiscale_cover := jsonb_build_object(
    'status',case when to_regclass('farm_watch.property_study_scale_windows_v1') is null then 'not_deployed' else 'not_materialized' end,
    'interpretation_boundary','Study-scale context is not available. Existing 500 m / 1.5 km / 3 km Farm Watch domains do not substitute for the source 1 km2 / 9 km2 windows.'); end if;

  if to_regclass('farm_watch.property_multiscale_forest_context_v1') is not null then
    v_multiscale_forest := farm_watch.farm_watch_get_multiscale_forest_context_v1_internal(p_slug);
  end if;
  if v_multiscale_forest is null then v_multiscale_forest := jsonb_build_object(
    'status',case when to_regclass('farm_watch.property_multiscale_forest_context_v1') is null then 'not_deployed' else 'not_materialized' end,
    'interpretation_boundary','Multiscale Forest Context v1 is not available. Existing generic canopy rings or local edge products do not substitute for the source-aligned 10 m forest proportion/configuration measurement at 30/90/270 m.'); end if;

  if to_regclass('farm_watch.property_forest_type_context_v1') is not null then
    v_forest_type := farm_watch.farm_watch_get_forest_type_context_v1_internal(p_slug);
  end if;
  if v_forest_type is null then v_forest_type := jsonb_build_object(
    'status',case when to_regclass('farm_watch.property_forest_type_context_v1') is null then 'not_deployed' else 'not_materialized' end,
    'interpretation_boundary','M47 Forest Type Context v1 is not available. Generic tree cover, total canopy cover, forest proportion, or wetland presence do not substitute for the six source-aligned distance-to-habitat covariates.'); end if;

  if to_regclass('farm_watch.property_conifer_cover_context_v1') is not null then
    v_conifer_cover := farm_watch.farm_watch_get_conifer_cover_context_v1_internal(p_slug);
  end if;
  if v_conifer_cover is null then v_conifer_cover := jsonb_build_object(
    'status',case when to_regclass('farm_watch.property_conifer_cover_context_v1') is null then 'not_deployed' else 'not_materialized' end,
    'interpretation_boundary','M09 Conifer Cover Context v1 is not available. Generic canopy density, Evergreen Forest alone, or Mixed Forest must not substitute for the source moderate/dense conifer availability classes.'); end if;

  if to_regclass('farm_watch.property_snow_winter_severity_daily_v1') is not null then
    v_snow_winter := farm_watch.farm_watch_get_snow_winter_severity_v1_internal(p_slug,p_as_of_date);
  end if;
  if v_snow_winter is null then v_snow_winter := jsonb_build_object(
    'status',case when to_regclass('farm_watch.property_snow_winter_severity_daily_v1') is null then 'not_deployed' else 'not_materialized' end,
    'as_of_date',p_as_of_date,
    'interpretation_boundary','M08 Snow/Winter Severity Context v1 is not available. Ordinary cold, generic precipitation, or a Minnesota WSI category must not substitute for source-aligned daily snow depth and minimum temperature.'); end if;

  if to_regclass('farm_watch.property_extreme_weather_event_context_v1') is not null then
    select jsonb_strip_nulls(jsonb_build_object(
      'status',e.status,'as_of_at',e.as_of_at,'identity_sha256',e.identity_sha256,'algorithm_version',e.algorithm_version,
      'output_schema_version',e.output_schema_version,'retrieved_at',e.retrieved_at,'context',e.context))
    into v_extreme_weather from farm_watch.property_extreme_weather_event_context_v1 e
    where e.property_id=v_property_id and e.as_of_at::date=p_as_of_date limit 1;
  end if;
  if v_extreme_weather is null then v_extreme_weather := jsonb_build_object(
    'status',case when to_regclass('farm_watch.property_extreme_weather_event_context_v1') is null then 'not_deployed' else 'not_materialized_for_date' end,
    'as_of_date',p_as_of_date,'interpretation_boundary','No date-matched extreme-event context is materialized. Ordinary rain, wind, severe-thunderstorm, or generic weather state must not substitute for the FW-D18 event gate.'); end if;

  return jsonb_build_object(
    'status',case when v_available_count>0 then 'available' when v_stale_count>0 then 'stale' else 'unavailable' end,
    'schema','deer-evidence-stack-v1','as_of_date',p_as_of_date,'property',jsonb_build_object('slug',p_slug,'id',v_property_id),
    'counts',jsonb_build_object('available',v_available_count,'stale',v_stale_count,'unavailable',v_unavailable_count),
    'products',v_products,'surface_water_state',v_surface_water,'mast_resource_context',v_mast_resource,
    'human_footprint_context',v_human_footprint,'multiscale_cover_context',v_multiscale_cover,
    'multiscale_forest_context',v_multiscale_forest,'forest_type_context',v_forest_type,
    'conifer_cover_context',v_conifer_cover,'snow_winter_severity_context',v_snow_winter,'extreme_weather_event_context',v_extreme_weather,
    'interpretation_boundary','Neutral Farm Watch evidence inventory for UI review. Availability here does not mean a deer relationship is applicable, a coefficient is transferable, or a deer-use prediction has been made.');
end;
$function$
;

do $$
begin
  if exists(select 1 from cron.job where jobname='farm-watch-conifer-cover-context-v1') then
    perform cron.unschedule('farm-watch-conifer-cover-context-v1');
  end if;
  perform cron.schedule(
    'farm-watch-conifer-cover-context-v1',
    '31 14 7 * *',
    $cron$select farm_watch.farm_watch_refresh_conifer_cover_context_v1_internal('validation-property-01');$cron$
  );
end;
$$;

comment on table farm_watch.property_conifer_cover_context_v1 is
'Neutral FW-M09 study-style conifer availability context. Annual NLCD Evergreen Forest supplies a conservative conifer-dominant proxy and matched-year NLCD TCC supplies canopy closure; Mixed Forest is other.';
comment on function farm_watch.farm_watch_get_conifer_cover_context_v1_internal(text) is
'Reads M09 moderate/dense conifer and other availability across exact Farm Watch nested landscape domains without deer inference.';
comment on function farm_watch.farm_watch_record_conifer_cover_context_v1_internal(text,integer,text,text,jsonb,timestamptz) is
'Validates and stores source-substituted DelGiudice conifer availability classes with exact 40/70 percent closure thresholds and no transferred biological response.';

commit;