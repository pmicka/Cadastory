begin;

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
  v_context_sha256 := encode(
    extensions.digest(convert_to((p_context - 'retrieved_at')::text,'UTF8'),'sha256'),
    'hex'
  );
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

comment on function farm_watch.farm_watch_record_conifer_cover_context_v1_internal(text,integer,text,text,jsonb,timestamptz) is
'Validates and stores source-substituted DelGiudice conifer availability classes. Deterministic identity excludes the top-level retrieval timestamp while preserving source metadata/raster hashes, domain identity, and scientific context.';

commit;