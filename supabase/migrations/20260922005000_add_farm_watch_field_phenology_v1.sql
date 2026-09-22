begin;

create table if not exists farm_watch.field_vegetation_observations_v1 (
  field_id uuid not null references agriculture.field_boundaries(id) on delete cascade,
  source_product text not null check (
    source_product in ('HLSL30.v2.0','HLSS30.v2.0','HLSL30_VI.v2.0','HLSS30_VI.v2.0')
  ),
  source_granule_id text not null,
  observed_at timestamptz not null,
  ndvi_mean double precision,
  ndvi_median double precision,
  evi_mean double precision,
  evi_median double precision,
  nir_mean double precision,
  valid_pixel_count integer not null check (valid_pixel_count >= 0),
  total_pixel_count integer not null check (total_pixel_count > 0),
  valid_fraction double precision not null check (valid_fraction between 0 and 1),
  cloud_fraction double precision check (cloud_fraction is null or cloud_fraction between 0 and 1),
  qa_context jsonb not null default '{}'::jsonb,
  source_url text,
  source_sha256 text not null check (source_sha256 ~ '^[0-9a-f]{64}$'),
  retrieved_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (field_id, source_product, source_granule_id)
);

create index if not exists field_vegetation_observations_field_time_idx
  on farm_watch.field_vegetation_observations_v1 (field_id, observed_at desc);

alter table farm_watch.field_vegetation_observations_v1 enable row level security;
revoke all on farm_watch.field_vegetation_observations_v1 from public, anon, authenticated;
grant select, insert, update, delete on farm_watch.field_vegetation_observations_v1 to service_role;

create table if not exists farm_watch.property_field_phenology_context_v1 (
  property_id uuid not null references farm_watch.properties(id) on delete cascade,
  as_of_date date not null,
  status text not null check (status in ('available','partial','unavailable')),
  context jsonb not null default '{}'::jsonb,
  boundary_sha256 text not null check (boundary_sha256 ~ '^[0-9a-f]{64}$'),
  landscape_domain_identity_sha256 text not null check (landscape_domain_identity_sha256 ~ '^[0-9a-f]{64}$'),
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

create index if not exists property_field_phenology_date_idx
  on farm_watch.property_field_phenology_context_v1 (as_of_date desc, retrieved_at desc);

alter table farm_watch.property_field_phenology_context_v1 enable row level security;
revoke all on farm_watch.property_field_phenology_context_v1 from public, anon, authenticated;
grant select, insert, update, delete on farm_watch.property_field_phenology_context_v1 to service_role;

insert into ingest.sources (
  slug,name,authority,source_class,geographic_scope,acquisition_method,update_cadence,
  authority_level,status,homepage_url,license_notes,commercial_use_status,notes
)
values
(
  'nasa-hlsl30-v2',
  'NASA Harmonized Landsat Sentinel-2 Landsat 30 m v2.0',
  'NASA LP DAAC',
  'satellite_surface_reflectance',
  'Global land',
  'HLS Landsat surface-reflectance granules with Fmask quality information',
  'scene driven',
  'federal_primary',
  'active_reference',
  'https://doi.org/10.5067/HLS/HLSL30.002',
  'NASA Earthdata public science product; access conditions follow Earthdata distribution terms.',
  'public_government',
  'Batch 4 source family for field-level current vegetation state. Surface reflectance remains required for NIR-dependent harvest methods.'
),
(
  'nasa-hlss30-v2',
  'NASA Harmonized Landsat Sentinel-2 Sentinel-2 30 m v2.0',
  'NASA LP DAAC',
  'satellite_surface_reflectance',
  'Global land',
  'HLS Sentinel-2 surface-reflectance granules with Fmask quality information',
  'scene driven',
  'federal_primary',
  'active_reference',
  'https://doi.org/10.5067/HLS/HLSS30.002',
  'NASA Earthdata public science product; access conditions follow Earthdata distribution terms.',
  'public_government',
  'Batch 4 source family for field-level current vegetation state. Surface reflectance remains required for NIR-dependent harvest methods.'
),
(
  'nasa-hlsl30-vi-v2',
  'NASA HLS Landsat Vegetation Indices 30 m v2.0',
  'NASA LP DAAC',
  'satellite_vegetation_index',
  'Global land',
  'Vegetation-index product derived from HLS Landsat surface reflectance',
  'scene driven',
  'federal_primary',
  'active_reference',
  'https://doi.org/10.5067/HLS/HLSL30_VI.002',
  'NASA Earthdata public science product; access conditions follow Earthdata distribution terms.',
  'public_government',
  'Candidate source for precomputed field NDVI/EVI observations; catalog availability must be distinguished from valid no-observation state.'
),
(
  'nasa-hlss30-vi-v2',
  'NASA HLS Sentinel-2 Vegetation Indices 30 m v2.0',
  'NASA LP DAAC',
  'satellite_vegetation_index',
  'Global land',
  'Vegetation-index product derived from HLS Sentinel-2 surface reflectance',
  'scene driven',
  'federal_primary',
  'active_reference',
  'https://doi.org/10.5067/HLS/HLSS30_VI.002',
  'NASA Earthdata public science product; access conditions follow Earthdata distribution terms.',
  'public_government',
  'Candidate source for precomputed field NDVI/EVI observations; catalog availability must be distinguished from valid no-observation state.'
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

create or replace function farm_watch.farm_watch_field_phenology_contract_v1()
returns jsonb
language sql
immutable
security definer
set search_path='pg_catalog'
as $$
  select jsonb_build_object(
    'algorithm_version','farm-watch-field-phenology-resolver-v1',
    'output_schema_version','field-phenology-context-v1',
    'field_observation_schema_version','hls-field-vegetation-observation-v1',
    'evidence_class','deterministic_derived',
    'observation_fresh_days',10,
    'trajectory_lookback_days',45,
    'minimum_valid_fraction',0.30,
    'scope_vocabulary',jsonb_build_array(
      'property','local_500m','landscape_1500m','broad_3000m'
    ),
    'phenology_state_vocabulary',jsonb_build_array(
      'green_up','vegetative','mature_senescing',
      'probable_harvest_transition','post_harvest_residual','unknown'
    ),
    'batch4a_behavior',jsonb_build_object(
      'field_phenology_classification_enabled',false,
      'harvest_classification_enabled',false,
      'generic_ndvi_drop_threshold_allowed',false,
      'regional_progress_can_promote_field_state',false
    )
  );
$$;

create or replace function farm_watch.farm_watch_get_field_phenology_targets_v1_internal(
  p_slug text default null,
  p_as_of_date date default current_date,
  p_limit integer default 250
)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','farm_watch','agriculture','extensions'
as $$
declare
  v_limit integer := greatest(1,least(coalesce(p_limit,250),1000));
  v_result jsonb;
begin
  if p_slug is not null and p_slug !~ '^[a-z0-9][a-z0-9-]{0,79}$' then
    raise exception 'invalid Farm Watch property slug';
  end if;
  if p_as_of_date is null then raise exception 'as-of date is required'; end if;

  select coalesce(jsonb_agg(row_json order by property_slug, field_id),'[]'::jsonb)
  into v_result
  from (
    select jsonb_build_object(
      'property_slug',p.slug,
      'property_id',p.id,
      'as_of_date',p_as_of_date,
      'boundary_sha256',d.boundary_sha256,
      'landscape_domain_identity_sha256',d.identity_sha256,
      'field_id',f.id,
      'field_geometry_geojson',extensions.st_asgeojson(f.geometry)::jsonb,
      'field_acres',f.acres,
      'boundary_source_kind',f.boundary_source_kind,
      'source_confidence',f.source_confidence,
      'scopes',to_jsonb(array_remove(array[
        case when extensions.st_intersects(f.geometry,p.boundary) then 'property' end,
        case when extensions.st_intersects(f.geometry,d.local_500m) then 'local_500m' end,
        case when extensions.st_intersects(f.geometry,d.landscape_1500m) then 'landscape_1500m' end,
        'broad_3000m'
      ],null)),
      'crop_identity',jsonb_build_object(
        'crop_year',ch.crop_year,
        'crop_code',ch.crop_code,
        'crop_name',ch.crop_name,
        'observation_kind',ch.observation_kind,
        'confidence',ch.confidence
      )
    ) as row_json,
    p.slug as property_slug,
    f.id as field_id
    from farm_watch.properties p
    join farm_watch.property_landscape_domains_v1 d
      on d.property_id=p.id and d.status='available'
    join agriculture.field_boundaries f
      on extensions.st_intersects(f.geometry,d.broad_3000m)
    left join lateral (
      select h.crop_year,h.crop_code,h.crop_name,h.observation_kind,h.confidence
      from agriculture.field_crop_history h
      where h.field_id=f.id and h.crop_year <= extract(year from p_as_of_date)::integer
      order by h.crop_year desc,h.updated_at desc
      limit 1
    ) ch on true
    where p.status='active'
      and (p_slug is null or p.slug=p_slug)
    order by p.slug,f.id
    limit v_limit
  ) q;

  return v_result;
end;
$$;

create or replace function farm_watch.farm_watch_store_field_vegetation_observations_v1_internal(
  p_rows jsonb
)
returns integer
language plpgsql
security definer
set search_path='pg_catalog','farm_watch'
as $$
declare
  v_row jsonb;
  v_count integer := 0;
  v_field_id uuid;
  v_source_product text;
  v_granule text;
  v_observed_at timestamptz;
  v_valid integer;
  v_total integer;
  v_fraction double precision;
  v_sha text;
begin
  if jsonb_typeof(p_rows) <> 'array' then raise exception 'observation rows must be an array'; end if;

  for v_row in select value from jsonb_array_elements(p_rows)
  loop
    v_field_id := nullif(v_row->>'field_id','')::uuid;
    v_source_product := v_row->>'source_product';
    v_granule := nullif(v_row->>'source_granule_id','');
    v_observed_at := nullif(v_row->>'observed_at','')::timestamptz;
    v_valid := nullif(v_row->>'valid_pixel_count','')::integer;
    v_total := nullif(v_row->>'total_pixel_count','')::integer;
    v_fraction := nullif(v_row->>'valid_fraction','')::double precision;
    v_sha := lower(coalesce(v_row->>'source_sha256',''));

    if v_field_id is null or v_granule is null or v_observed_at is null then
      raise exception 'field observation identity is incomplete';
    end if;
    if v_source_product not in ('HLSL30.v2.0','HLSS30.v2.0','HLSL30_VI.v2.0','HLSS30_VI.v2.0') then
      raise exception 'unsupported HLS source product';
    end if;
    if v_valid is null or v_total is null or v_valid < 0 or v_total <= 0 or v_valid > v_total then
      raise exception 'field observation pixel support is invalid';
    end if;
    if v_fraction is null or v_fraction < 0 or v_fraction > 1
       or abs(v_fraction - (v_valid::double precision / v_total::double precision)) > 0.02 then
      raise exception 'field observation valid fraction is invalid';
    end if;
    if v_sha !~ '^[0-9a-f]{64}$' then raise exception 'field observation source SHA-256 is invalid'; end if;

    insert into farm_watch.field_vegetation_observations_v1(
      field_id,source_product,source_granule_id,observed_at,
      ndvi_mean,ndvi_median,evi_mean,evi_median,nir_mean,
      valid_pixel_count,total_pixel_count,valid_fraction,cloud_fraction,
      qa_context,source_url,source_sha256,retrieved_at,updated_at
    ) values (
      v_field_id,v_source_product,v_granule,v_observed_at,
      nullif(v_row->>'ndvi_mean','')::double precision,
      nullif(v_row->>'ndvi_median','')::double precision,
      nullif(v_row->>'evi_mean','')::double precision,
      nullif(v_row->>'evi_median','')::double precision,
      nullif(v_row->>'nir_mean','')::double precision,
      v_valid,v_total,v_fraction,
      nullif(v_row->>'cloud_fraction','')::double precision,
      coalesce(v_row->'qa_context','{}'::jsonb),
      nullif(v_row->>'source_url',''),
      v_sha,
      coalesce(nullif(v_row->>'retrieved_at','')::timestamptz,now()),
      now()
    )
    on conflict(field_id,source_product,source_granule_id) do update set
      observed_at=excluded.observed_at,
      ndvi_mean=excluded.ndvi_mean,
      ndvi_median=excluded.ndvi_median,
      evi_mean=excluded.evi_mean,
      evi_median=excluded.evi_median,
      nir_mean=excluded.nir_mean,
      valid_pixel_count=excluded.valid_pixel_count,
      total_pixel_count=excluded.total_pixel_count,
      valid_fraction=excluded.valid_fraction,
      cloud_fraction=excluded.cloud_fraction,
      qa_context=excluded.qa_context,
      source_url=excluded.source_url,
      source_sha256=excluded.source_sha256,
      retrieved_at=excluded.retrieved_at,
      updated_at=now();
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

create or replace function farm_watch.farm_watch_resolve_field_phenology_v1_internal(
  p_slug text,
  p_as_of_date date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','farm_watch','agriculture','extensions'
as $$
declare
  v_property_id uuid;
  v_boundary extensions.geometry;
  v_boundary_sha256 text;
  v_state_code text;
  v_domain farm_watch.property_landscape_domains_v1%rowtype;
  v_contract jsonb;
  v_fields jsonb;
  v_total integer := 0;
  v_current integer := 0;
  v_stale integer := 0;
  v_unavailable integer := 0;
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
  if p_as_of_date is null then raise exception 'as-of date is required'; end if;

  select p.id,p.boundary,p.state_code
  into v_property_id,v_boundary,v_state_code
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

  select *
  into v_domain
  from farm_watch.property_landscape_domains_v1 d
  where d.property_id=v_property_id and d.status='available'
  limit 1;

  if not found or v_domain.broad_3000m is null or v_domain.identity_sha256 is null then
    return jsonb_build_object(
      'status','unavailable',
      'property',jsonb_build_object('slug',p_slug,'id',v_property_id),
      'as_of_date',p_as_of_date,
      'context',null,
      'unavailable_reason','landscape_domain_unavailable'
    );
  end if;

  v_contract := farm_watch.farm_watch_field_phenology_contract_v1();
  v_boundary_sha256 := encode(
    extensions.digest(extensions.st_asewkb(v_boundary),'sha256'),'hex'
  );

  with field_rows as (
    select
      f.id as field_id,
      f.acres,
      f.boundary_source_kind,
      f.source_confidence,
      array_remove(array[
        case when extensions.st_intersects(f.geometry,v_boundary) then 'property' end,
        case when extensions.st_intersects(f.geometry,v_domain.local_500m) then 'local_500m' end,
        case when extensions.st_intersects(f.geometry,v_domain.landscape_1500m) then 'landscape_1500m' end,
        'broad_3000m'
      ],null) as scopes,
      ch.crop_year,ch.crop_code,ch.crop_name,ch.observation_kind as crop_observation_kind,ch.confidence as crop_confidence,
      latest.observed_at as latest_observed_at,
      latest.source_product as latest_source_product,
      latest.source_granule_id as latest_granule_id,
      latest.ndvi_mean as latest_ndvi_mean,
      latest.ndvi_median as latest_ndvi_median,
      latest.evi_mean as latest_evi_mean,
      latest.evi_median as latest_evi_median,
      latest.nir_mean as latest_nir_mean,
      latest.valid_fraction as latest_valid_fraction,
      latest.cloud_fraction as latest_cloud_fraction,
      latest.source_sha256 as latest_source_sha256,
      prior.observed_at as prior_observed_at,
      prior.ndvi_mean as prior_ndvi_mean,
      case
        when latest.observed_at is null then 'unavailable'
        when p_as_of_date - latest.observed_at::date <= (v_contract->>'observation_fresh_days')::integer then 'known'
        else 'stale'
      end as evidence_state,
      case
        when latest.observed_at is null or prior.observed_at is null then 'insufficient_observations'
        else 'unknown'
      end as trajectory_state,
      case
        when ch.crop_year is null then 'unavailable'
        when ch.crop_year=extract(year from p_as_of_date)::integer then 'known'
        else 'stale'
      end as crop_identity_state,
      regional.week_ending as regional_week_ending,
      regional.rows as regional_progress_rows
    from agriculture.field_boundaries f
    left join lateral (
      select h.crop_year,h.crop_code,h.crop_name,h.observation_kind,h.confidence
      from agriculture.field_crop_history h
      where h.field_id=f.id and h.crop_year <= extract(year from p_as_of_date)::integer
      order by h.crop_year desc,h.updated_at desc
      limit 1
    ) ch on true
    left join lateral (
      select o.*
      from farm_watch.field_vegetation_observations_v1 o
      where o.field_id=f.id
        and o.observed_at < (p_as_of_date + 1)::timestamp
        and o.valid_fraction >= (v_contract->>'minimum_valid_fraction')::double precision
      order by o.observed_at desc,o.retrieved_at desc
      limit 1
    ) latest on true
    left join lateral (
      select o.*
      from farm_watch.field_vegetation_observations_v1 o
      where o.field_id=f.id
        and latest.observed_at is not null
        and o.observed_at < latest.observed_at
        and o.observed_at >= latest.observed_at - make_interval(days => (v_contract->>'trajectory_lookback_days')::integer)
        and o.valid_fraction >= (v_contract->>'minimum_valid_fraction')::double precision
      order by o.observed_at desc,o.retrieved_at desc
      limit 1
    ) prior on true
    left join lateral (
      with latest_week as (
        select max(l0.week_ending) as week_ending
        from agriculture.crop_progress_layers l0
        where l0.week_ending <= p_as_of_date
          and l0.metric='progress'
          and (
            (lower(coalesce(ch.crop_name,''))='corn' and lower(l0.crop)='corn')
            or (lower(coalesce(ch.crop_name,'')) in ('soybean','soybeans') and lower(l0.crop)='soybean')
          )
      )
      select
        w.week_ending,
        jsonb_agg(
          jsonb_build_object(
            'stage',l.stage,
            'pilot_mean',l.pilot_mean,
            'pilot_min',l.pilot_min,
            'pilot_max',l.pilot_max,
            'metadata',l.metadata
          )
          order by coalesce(l.stage,''),l.raster_name,l.id::text
        ) as rows
      from latest_week w
      join agriculture.crop_progress_layers l
        on l.week_ending=w.week_ending
       and l.metric='progress'
       and (
         (lower(coalesce(ch.crop_name,''))='corn' and lower(l.crop)='corn')
         or (lower(coalesce(ch.crop_name,'')) in ('soybean','soybeans') and lower(l.crop)='soybean')
       )
      where w.week_ending is not null
      group by w.week_ending
    ) regional on true
    where extensions.st_intersects(f.geometry,v_domain.broad_3000m)
  ),
  encoded as (
    select jsonb_build_object(
      'field_id',field_id,
      'scopes',to_jsonb(scopes),
      'field_acres',acres,
      'boundary_source_kind',boundary_source_kind,
      'source_confidence',source_confidence,
      'crop_identity',jsonb_build_object(
        'crop_year',crop_year,
        'crop_code',crop_code,
        'crop_name',crop_name,
        'observation_kind',crop_observation_kind,
        'confidence',crop_confidence,
        'state',crop_identity_state
      ),
      'evidence_state',evidence_state,
      'phenology_state','unknown',
      'trajectory_state',trajectory_state,
      'observations',case when latest_observed_at is null then '[]'::jsonb else jsonb_build_array(
        jsonb_build_object(
          'observed_at',latest_observed_at,
          'source_product',latest_source_product,
          'source_granule_id',latest_granule_id,
          'ndvi_mean',latest_ndvi_mean,
          'ndvi_median',latest_ndvi_median,
          'evi_mean',latest_evi_mean,
          'evi_median',latest_evi_median,
          'nir_mean',latest_nir_mean,
          'valid_fraction',latest_valid_fraction,
          'cloud_fraction',latest_cloud_fraction,
          'source_sha256',latest_source_sha256
        )
      ) end,
      'trajectory',jsonb_build_object(
        'latest_observed_at',latest_observed_at,
        'prior_observed_at',prior_observed_at,
        'latest_ndvi_mean',latest_ndvi_mean,
        'prior_ndvi_mean',prior_ndvi_mean,
        'ndvi_delta',case
          when latest_ndvi_mean is not null and prior_ndvi_mean is not null
          then latest_ndvi_mean-prior_ndvi_mean else null end,
        'classification_boundary','Batch 4A records the observation delta but does not convert it to a phenology or harvest label.'
      ),
      'regional_nass_context',case
        when regional_week_ending is null then null
        else jsonb_build_object(
          'week_ending',regional_week_ending,
          'stage_rows',coalesce(regional_progress_rows,'[]'::jsonb),
          'state','proxy',
          'interpretation_boundary','Regional synthetic crop progress cannot promote a field-level state.'
        )
      end,
      'harvest_method',jsonb_build_object(
        'status','not_evaluated_batch4a',
        'candidate_forms',jsonb_build_array('kentucky-curve-change-phenology','nir-ndvi-nhpi'),
        'coefficient_or_threshold_transfer_authorized',false
      ),
      'applicable_relationship_ids',jsonb_build_array('FW-D08','FW-D09','FW-D15','FW-D16')
    ) as field_json,
    evidence_state
    from field_rows
  )
  select
    coalesce(jsonb_agg(field_json order by field_json->>'field_id'),'[]'::jsonb),
    count(*)::integer,
    count(*) filter (where evidence_state='known')::integer,
    count(*) filter (where evidence_state='stale')::integer,
    count(*) filter (where evidence_state='unavailable')::integer
  into v_fields,v_total,v_current,v_stale,v_unavailable
  from encoded;

  v_status := case
    when v_total=0 or v_current=0 then 'unavailable'
    when v_current=v_total then 'available'
    else 'partial'
  end;

  v_source_fingerprint := jsonb_build_object(
    'as_of_date',p_as_of_date,
    'landscape_domain_identity_sha256',v_domain.identity_sha256,
    'fields',v_fields
  );
  v_source_fingerprint_sha256 := encode(
    extensions.digest(convert_to(v_source_fingerprint::text,'UTF8'),'sha256'),'hex'
  );
  v_source_signature := concat_ws(
    '|',
    'product=field-phenology-context',
    'sources=csb-cdl+hls+nass-progress',
    'as_of='||p_as_of_date::text,
    'landscape_domain_identity_sha256='||v_domain.identity_sha256,
    'source_fingerprint_sha256='||v_source_fingerprint_sha256
  );
  v_source_signature_sha256 := encode(
    extensions.digest(convert_to(v_source_signature,'UTF8'),'sha256'),'hex'
  );
  v_identity_sha256 := encode(
    extensions.digest(convert_to(concat_ws(
      '|',v_property_id::text,p_as_of_date::text,
      v_contract->>'algorithm_version',v_contract->>'output_schema_version',
      v_boundary_sha256,v_domain.identity_sha256,v_source_signature_sha256
    ),'UTF8'),'sha256'),'hex'
  );

  v_context := jsonb_build_object(
    'schema',v_contract->>'output_schema_version',
    'method',v_contract->>'algorithm_version',
    'as_of_date',p_as_of_date,
    'evidence_class',v_contract->>'evidence_class',
    'state_code',v_state_code,
    'scope_counts',jsonb_build_object(
      'property',(select count(*) from jsonb_array_elements(v_fields) x where x->'scopes' ? 'property'),
      'local_500m',(select count(*) from jsonb_array_elements(v_fields) x where x->'scopes' ? 'local_500m'),
      'landscape_1500m',(select count(*) from jsonb_array_elements(v_fields) x where x->'scopes' ? 'landscape_1500m'),
      'broad_3000m',v_total
    ),
    'evidence_counts',jsonb_build_object(
      'known',v_current,'stale',v_stale,'unavailable',v_unavailable
    ),
    'fields',v_fields,
    'source_fingerprint_sha256',v_source_fingerprint_sha256,
    'scoring_performed',false,
    'behavioral_inference_performed',false,
    'interpretation_boundary','Dated field vegetation evidence only. Batch 4A performs no field phenology or harvest classification and no deer-use, movement, attraction, habitat-quality, or management inference.'
  );

  return jsonb_build_object(
    'status',v_status,
    'property',jsonb_build_object('slug',p_slug,'id',v_property_id),
    'as_of_date',p_as_of_date,
    'context',v_context,
    'identity',jsonb_build_object(
      'boundary_sha256',v_boundary_sha256,
      'landscape_domain_identity_sha256',v_domain.identity_sha256,
      'source_signature',v_source_signature,
      'source_signature_sha256',v_source_signature_sha256,
      'algorithm_version',v_contract->>'algorithm_version',
      'output_schema_version',v_contract->>'output_schema_version',
      'identity_sha256',v_identity_sha256
    )
  );
end;
$$;

create or replace function farm_watch.farm_watch_refresh_field_phenology_v1_internal(
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
  v_resolved := farm_watch.farm_watch_resolve_field_phenology_v1_internal(p_slug,p_as_of_date);
  if v_resolved->>'status' in ('missing') or v_resolved->'context' is null then
    return v_resolved;
  end if;

  v_property_id := (v_resolved->'property'->>'id')::uuid;
  insert into farm_watch.property_field_phenology_context_v1(
    property_id,as_of_date,status,context,boundary_sha256,
    landscape_domain_identity_sha256,source_signature,source_signature_sha256,
    algorithm_version,output_schema_version,identity_sha256,retrieved_at,updated_at
  ) values (
    v_property_id,p_as_of_date,v_resolved->>'status',v_resolved->'context',
    v_resolved->'identity'->>'boundary_sha256',
    v_resolved->'identity'->>'landscape_domain_identity_sha256',
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
    landscape_domain_identity_sha256=excluded.landscape_domain_identity_sha256,
    source_signature=excluded.source_signature,
    source_signature_sha256=excluded.source_signature_sha256,
    algorithm_version=excluded.algorithm_version,
    output_schema_version=excluded.output_schema_version,
    identity_sha256=excluded.identity_sha256,
    retrieved_at=excluded.retrieved_at,
    updated_at=now();

  return farm_watch.farm_watch_get_field_phenology_v1_internal(p_slug,p_as_of_date);
end;
$$;

create or replace function farm_watch.farm_watch_get_field_phenology_v1_internal(
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
  v_domain_identity text;
  v_contract jsonb;
  v_row farm_watch.property_field_phenology_context_v1%rowtype;
begin
  select p.id,p.boundary
  into v_property_id,v_boundary
  from farm_watch.properties p
  where p.slug=p_slug and p.status='active'
  limit 1;

  if v_property_id is null or v_boundary is null then
    return jsonb_build_object('status','missing','property',jsonb_build_object('slug',p_slug),'as_of_date',p_as_of_date,'context',null);
  end if;

  select d.identity_sha256
  into v_domain_identity
  from farm_watch.property_landscape_domains_v1 d
  where d.property_id=v_property_id and d.status='available'
  limit 1;

  select *
  into v_row
  from farm_watch.property_field_phenology_context_v1 s
  where s.property_id=v_property_id and s.as_of_date=p_as_of_date
  limit 1;

  if not found then
    return jsonb_build_object('status','missing','property',jsonb_build_object('slug',p_slug,'id',v_property_id),'as_of_date',p_as_of_date,'context',null);
  end if;

  v_boundary_sha256 := encode(extensions.digest(extensions.st_asewkb(v_boundary),'sha256'),'hex');
  v_contract := farm_watch.farm_watch_field_phenology_contract_v1();

  if v_row.boundary_sha256 is distinct from v_boundary_sha256 then
    return jsonb_build_object('status','stale','property',jsonb_build_object('slug',p_slug,'id',v_property_id),'as_of_date',p_as_of_date,'context',null,'invalidation_reason','property_boundary_changed','stored_identity_sha256',v_row.identity_sha256);
  end if;
  if v_domain_identity is null or v_row.landscape_domain_identity_sha256 is distinct from v_domain_identity then
    return jsonb_build_object('status','stale','property',jsonb_build_object('slug',p_slug,'id',v_property_id),'as_of_date',p_as_of_date,'context',null,'invalidation_reason','landscape_domain_changed','stored_identity_sha256',v_row.identity_sha256);
  end if;
  if v_row.algorithm_version is distinct from v_contract->>'algorithm_version'
     or v_row.output_schema_version is distinct from v_contract->>'output_schema_version' then
    return jsonb_build_object('status','stale','property',jsonb_build_object('slug',p_slug,'id',v_property_id),'as_of_date',p_as_of_date,'context',null,'invalidation_reason','field_phenology_contract_changed','stored_identity_sha256',v_row.identity_sha256);
  end if;

  return jsonb_build_object(
    'status',v_row.status,
    'property',jsonb_build_object('slug',p_slug,'id',v_property_id),
    'as_of_date',v_row.as_of_date,
    'context',v_row.context,
    'identity',jsonb_build_object(
      'boundary_sha256',v_row.boundary_sha256,
      'landscape_domain_identity_sha256',v_row.landscape_domain_identity_sha256,
      'source_signature_sha256',v_row.source_signature_sha256,
      'algorithm_version',v_row.algorithm_version,
      'output_schema_version',v_row.output_schema_version,
      'identity_sha256',v_row.identity_sha256
    ),
    'retrieved_at',v_row.retrieved_at
  );
end;
$$;

revoke all on function farm_watch.farm_watch_field_phenology_contract_v1() from public, anon, authenticated;
revoke all on function farm_watch.farm_watch_get_field_phenology_targets_v1_internal(text,date,integer) from public, anon, authenticated;
revoke all on function farm_watch.farm_watch_store_field_vegetation_observations_v1_internal(jsonb) from public, anon, authenticated;
revoke all on function farm_watch.farm_watch_resolve_field_phenology_v1_internal(text,date) from public, anon, authenticated;
revoke all on function farm_watch.farm_watch_refresh_field_phenology_v1_internal(text,date) from public, anon, authenticated;
revoke all on function farm_watch.farm_watch_get_field_phenology_v1_internal(text,date) from public, anon, authenticated;

grant execute on function farm_watch.farm_watch_field_phenology_contract_v1() to postgres, service_role;
grant execute on function farm_watch.farm_watch_get_field_phenology_targets_v1_internal(text,date,integer) to service_role;
grant execute on function farm_watch.farm_watch_store_field_vegetation_observations_v1_internal(jsonb) to service_role;
grant execute on function farm_watch.farm_watch_resolve_field_phenology_v1_internal(text,date) to service_role;
grant execute on function farm_watch.farm_watch_refresh_field_phenology_v1_internal(text,date) to service_role;
grant execute on function farm_watch.farm_watch_get_field_phenology_v1_internal(text,date) to service_role;

create or replace function public.farm_watch_get_field_phenology_targets_v1_internal(
  p_slug text default null,
  p_as_of_date date default current_date,
  p_limit integer default 250
)
returns jsonb
language sql
stable
security definer
set search_path='pg_catalog'
as $$
  select farm_watch.farm_watch_get_field_phenology_targets_v1_internal(p_slug,p_as_of_date,p_limit);
$$;

create or replace function public.farm_watch_store_field_vegetation_observations_v1_internal(p_rows jsonb)
returns integer
language sql
security definer
set search_path='pg_catalog'
as $$
  select farm_watch.farm_watch_store_field_vegetation_observations_v1_internal(p_rows);
$$;

create or replace function public.farm_watch_refresh_field_phenology_v1_internal(
  p_slug text,
  p_as_of_date date default current_date
)
returns jsonb
language sql
security definer
set search_path='pg_catalog'
as $$
  select farm_watch.farm_watch_refresh_field_phenology_v1_internal(p_slug,p_as_of_date);
$$;

create or replace function public.farm_watch_get_field_phenology_v1_internal(
  p_slug text,
  p_as_of_date date default current_date
)
returns jsonb
language sql
stable
security definer
set search_path='pg_catalog'
as $$
  select farm_watch.farm_watch_get_field_phenology_v1_internal(p_slug,p_as_of_date);
$$;

revoke all on function public.farm_watch_get_field_phenology_targets_v1_internal(text,date,integer) from public, anon, authenticated;
revoke all on function public.farm_watch_store_field_vegetation_observations_v1_internal(jsonb) from public, anon, authenticated;
revoke all on function public.farm_watch_refresh_field_phenology_v1_internal(text,date) from public, anon, authenticated;
revoke all on function public.farm_watch_get_field_phenology_v1_internal(text,date) from public, anon, authenticated;

grant execute on function public.farm_watch_get_field_phenology_targets_v1_internal(text,date,integer) to service_role;
grant execute on function public.farm_watch_store_field_vegetation_observations_v1_internal(jsonb) to service_role;
grant execute on function public.farm_watch_refresh_field_phenology_v1_internal(text,date) to service_role;
grant execute on function public.farm_watch_get_field_phenology_v1_internal(text,date) to service_role;

comment on table farm_watch.field_vegetation_observations_v1 is
'Field-level HLS vegetation summaries with explicit pixel support and source provenance. These observations do not themselves assert crop phenology, harvest, forage quality, or wildlife use.';

comment on table farm_watch.property_field_phenology_context_v1 is
'Date-keyed neutral field agricultural-state context bound to the current Farm Watch landscape domain. Batch 4A preserves phenology and harvest as unknown pending an evidence-backed time-series classifier.';

commit;