begin;

insert into ingest.sources (
  slug, name, authority, source_class, geographic_scope, acquisition_method,
  update_cadence, authority_level, status, homepage_url, license_notes,
  commercial_use_status, notes
)
values (
  'noaa-hrrr-conus-3km',
  'NOAA High-Resolution Rapid Refresh CONUS 3 km',
  'NOAA / NCEP',
  'modeled_environmental',
  'CONUS',
  'NOAA Open Data HRRR GRIB2 index + HTTP byte-range records',
  'hourly',
  'federal_operational_authoritative',
  'active_reference',
  'https://rapidrefresh.noaa.gov/hrrr/',
  'Public U.S. government operational weather-model data; retain NOAA/NCEP attribution and modeled-data caveat.',
  'public_government',
  'Hourly approximately 3 km HRRR model analysis/forecast fields. Farm Watch v1 collector stores f00 analysis forcing only; values are model-grid proxies, not on-property instrument observations.'
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

create table if not exists farm_watch.property_meteorological_forcing_v1 (
  property_id uuid not null references farm_watch.properties(id) on delete cascade,
  valid_at timestamptz not null,
  source_model text not null,
  source_state text not null check (source_state in ('analysis','forecast')),
  reference_time timestamptz not null,
  forecast_lead_hours integer not null check (forecast_lead_hours >= 0 and forecast_lead_hours <= 72),
  forcing jsonb not null check (jsonb_typeof(forcing)='object'),
  target_latitude numeric not null check (target_latitude between -90 and 90),
  target_longitude numeric not null check (target_longitude between -180 and 180),
  grid_latitude numeric not null check (grid_latitude between -90 and 90),
  grid_longitude numeric not null check (grid_longitude between -360 and 360),
  grid_distance_m numeric not null check (grid_distance_m >= 0),
  source_file_url text not null,
  source_index_sha256 text not null check (source_index_sha256 ~ '^[0-9a-f]{64}$'),
  source_records_sha256 text not null check (source_records_sha256 ~ '^[0-9a-f]{64}$'),
  boundary_sha256 text not null check (boundary_sha256 ~ '^[0-9a-f]{64}$'),
  algorithm_version text not null,
  output_schema_version text not null,
  identity_sha256 text not null check (identity_sha256 ~ '^[0-9a-f]{64}$'),
  retrieved_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (property_id, valid_at, source_model, source_state)
);

create index if not exists property_meteorological_forcing_lookup_idx
  on farm_watch.property_meteorological_forcing_v1
    (property_id, source_state, valid_at desc, retrieved_at desc);

alter table farm_watch.property_meteorological_forcing_v1 enable row level security;
revoke all on farm_watch.property_meteorological_forcing_v1 from public, anon, authenticated;
grant select, insert, update, delete on farm_watch.property_meteorological_forcing_v1 to service_role;

create or replace function farm_watch.farm_watch_meteorological_forcing_contract_v1()
returns jsonb
language sql
immutable
security definer
set search_path='pg_catalog'
as $$
  select jsonb_build_object(
    'algorithm_version','noaa-hrrr-nearest-grid-analysis-v1',
    'output_schema_version','farm-watch-meteorological-forcing-v1',
    'evidence_class','modeled_environmental_proxy',
    'source_model','noaa-hrrr-conus-3km',
    'source_authority','NOAA / NCEP',
    'spatial_resolution_km',3,
    'max_grid_distance_m',5000,
    'collector_source_state','analysis',
    'collector_forecast_lead_hours',0,
    'fields',jsonb_build_array(
      'air_temperature_2m_c',
      'dew_point_2m_c',
      'relative_humidity_2m_pct',
      'wind_grid_u_10m_mps',
      'wind_grid_v_10m_mps',
      'wind_east_10m_mps',
      'wind_north_10m_mps',
      'wind_speed_10m_mps',
      'wind_direction_from_deg',
      'downward_shortwave_wm2',
      'downward_longwave_wm2',
      'total_cloud_cover_pct',
      'precipitation_rate_mm_hr'
    ),
    'interpretation_boundary',
      'HRRR forcing is modeled environmental state at the nearest model grid point. It is not an on-property weather-station observation and performs no wildlife or management inference.'
  );
$$;

create or replace function farm_watch.farm_watch_get_meteorological_targets_v1_internal(
  p_slug text default null,
  p_limit integer default 25
)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','farm_watch','extensions'
as $$
declare
  v_limit integer := greatest(1,least(coalesce(p_limit,25),100));
begin
  if p_slug is not null and (
    length(p_slug)>80 or p_slug !~ '^[a-z0-9][a-z0-9-]{0,79}$'
  ) then
    raise exception 'invalid Farm Watch property slug';
  end if;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'property_id',q.id,
        'slug',q.slug,
        'latitude',extensions.st_y(q.pt),
        'longitude',extensions.st_x(q.pt),
        'boundary_sha256',encode(
          extensions.digest(extensions.st_asewkb(q.boundary),'sha256'),
          'hex'
        )
      )
      order by q.slug
    )
    from (
      select
        p.id,
        p.slug,
        p.boundary,
        coalesce(p.center,extensions.st_pointonsurface(p.boundary)) as pt
      from farm_watch.properties p
      where p.status='active'
        and p.boundary is not null
        and (p_slug is null or p.slug=p_slug)
      order by p.slug
      limit v_limit
    ) q
    where q.pt is not null
  ),'[]'::jsonb);
end;
$$;

create or replace function farm_watch.farm_watch_store_meteorological_forcing_v1_internal(
  p_rows jsonb
)
returns integer
language plpgsql
security definer
set search_path='pg_catalog','farm_watch','extensions'
as $$
declare
  v_contract jsonb := farm_watch.farm_watch_meteorological_forcing_contract_v1();
  v_row jsonb;
  v_property_id uuid;
  v_boundary extensions.geometry;
  v_current_boundary_sha text;
  v_slug text;
  v_valid_at timestamptz;
  v_reference_time timestamptz;
  v_source_state text;
  v_lead integer;
  v_forcing jsonb;
  v_source_model text;
  v_source_file_url text;
  v_index_sha text;
  v_records_sha text;
  v_algorithm text;
  v_schema text;
  v_identity text;
  v_count integer := 0;
begin
  if jsonb_typeof(p_rows) <> 'array' then
    raise exception 'meteorological forcing rows must be a JSON array';
  end if;

  for v_row in select value from jsonb_array_elements(p_rows)
  loop
    v_slug := nullif(v_row->>'property_slug','');
    if v_slug is null or length(v_slug)>80 or v_slug !~ '^[a-z0-9][a-z0-9-]{0,79}$' then
      raise exception 'invalid Farm Watch property slug';
    end if;

    select p.id,p.boundary
    into v_property_id,v_boundary
    from farm_watch.properties p
    where p.slug=v_slug and p.status='active'
    limit 1;

    if v_property_id is null or v_boundary is null then
      raise exception 'Farm Watch property is unavailable: %',v_slug;
    end if;

    v_current_boundary_sha := encode(
      extensions.digest(extensions.st_asewkb(v_boundary),'sha256'),
      'hex'
    );
    if nullif(v_row->>'boundary_sha256','') is distinct from v_current_boundary_sha then
      raise exception 'meteorological forcing target boundary identity is stale';
    end if;

    v_valid_at := nullif(v_row->>'valid_at','')::timestamptz;
    v_reference_time := nullif(v_row->>'reference_time','')::timestamptz;
    v_source_state := nullif(v_row->>'source_state','');
    v_lead := nullif(v_row->>'forecast_lead_hours','')::integer;
    v_source_model := nullif(v_row->>'source_model','');
    v_source_file_url := nullif(v_row->>'source_file_url','');
    v_index_sha := nullif(v_row->>'source_index_sha256','');
    v_records_sha := nullif(v_row->>'source_records_sha256','');
    v_forcing := v_row->'forcing';
    v_algorithm := v_contract->>'algorithm_version';
    v_schema := v_contract->>'output_schema_version';

    if v_valid_at is null or v_reference_time is null then
      raise exception 'meteorological forcing timestamps are required';
    end if;
    if v_source_state not in ('analysis','forecast') then
      raise exception 'invalid meteorological forcing source state';
    end if;
    if v_lead is null or v_lead < 0 or v_lead > 72 then
      raise exception 'invalid meteorological forcing lead';
    end if;
    if v_source_state='analysis' and (
      v_lead<>0 or v_valid_at is distinct from v_reference_time
    ) then
      raise exception 'analysis forcing must have zero lead and valid_at=reference_time';
    end if;
    if v_source_state='forecast' and
       v_valid_at is distinct from v_reference_time + make_interval(hours=>v_lead) then
      raise exception 'forecast forcing valid time does not match reference time + lead';
    end if;
    if v_source_model is distinct from (v_contract->>'source_model') then
      raise exception 'unsupported meteorological forcing source model';
    end if;
    if v_source_file_url is null or
       v_source_file_url !~ '^https://noaa-hrrr-bdp-pds\.s3\.amazonaws\.com/hrrr\.[0-9]{8}/conus/hrrr\.t[0-9]{2}z\.wrfsfcf[0-9]{2}\.grib2$' then
      raise exception 'invalid HRRR source file URL';
    end if;
    if v_index_sha !~ '^[0-9a-f]{64}$' or v_records_sha !~ '^[0-9a-f]{64}$' then
      raise exception 'meteorological forcing source hashes are invalid';
    end if;
    if jsonb_typeof(v_forcing)<>'object'
       or v_forcing->>'schema' is distinct from v_schema
       or v_forcing->>'method' is distinct from v_algorithm
       or v_forcing->>'evidence_class' is distinct from (v_contract->>'evidence_class')
       or v_forcing->>'source_state' is distinct from v_source_state
       or nullif(v_forcing->>'valid_at','')::timestamptz is distinct from v_valid_at
       or v_forcing->'source'->>'model_slug' is distinct from v_source_model
       or nullif(v_forcing->'source'->>'reference_time','')::timestamptz is distinct from v_reference_time
       or nullif(v_forcing->'source'->>'forecast_lead_hours','')::integer is distinct from v_lead
       or coalesce((v_forcing->>'scoring_performed')::boolean,true) is not false
       or coalesce((v_forcing->>'behavioral_inference_performed')::boolean,true) is not false then
      raise exception 'meteorological forcing context violates contract';
    end if;

    if jsonb_typeof(v_forcing->'fields')<>'object'
       or not ((v_forcing->'fields') ?& array[
         'air_temperature_2m_c',
         'dew_point_2m_c',
         'relative_humidity_2m_pct',
         'wind_grid_u_10m_mps',
         'wind_grid_v_10m_mps',
         'wind_east_10m_mps',
         'wind_north_10m_mps',
         'wind_speed_10m_mps',
         'wind_direction_from_deg',
         'downward_shortwave_wm2',
         'downward_longwave_wm2',
         'total_cloud_cover_pct',
         'precipitation_rate_mm_hr'
       ]) then
      raise exception 'meteorological forcing fields are incomplete';
    end if;

    if exists (
      select 1
      from jsonb_each(v_forcing->'fields') f
      where f.key = any(array[
        'air_temperature_2m_c',
        'dew_point_2m_c',
        'relative_humidity_2m_pct',
        'wind_grid_u_10m_mps',
        'wind_grid_v_10m_mps',
        'wind_east_10m_mps',
        'wind_north_10m_mps',
        'wind_speed_10m_mps',
        'wind_direction_from_deg',
        'downward_shortwave_wm2',
        'downward_longwave_wm2',
        'total_cloud_cover_pct',
        'precipitation_rate_mm_hr'
      ])
      and jsonb_typeof(f.value)<>'number'
    ) then
      raise exception 'meteorological forcing fields must be numeric';
    end if;

    if (v_forcing->'fields'->>'relative_humidity_2m_pct')::numeric not between 0 and 100
       or (v_forcing->'fields'->>'total_cloud_cover_pct')::numeric not between 0 and 100
       or (v_forcing->'fields'->>'wind_speed_10m_mps')::numeric < 0
       or (v_forcing->'fields'->>'wind_direction_from_deg')::numeric < 0
       or (v_forcing->'fields'->>'wind_direction_from_deg')::numeric >= 360
       or (v_forcing->'fields'->>'downward_shortwave_wm2')::numeric < 0
       or (v_forcing->'fields'->>'downward_longwave_wm2')::numeric < 0
       or (v_forcing->'fields'->>'precipitation_rate_mm_hr')::numeric < 0 then
      raise exception 'meteorological forcing fields violate physical range checks';
    end if;

    if (v_row->>'grid_distance_m')::numeric > (v_contract->>'max_grid_distance_m')::numeric
       or (v_forcing->'grid'->>'distance_m')::numeric is distinct from (v_row->>'grid_distance_m')::numeric
       or (v_forcing->'grid'->>'target_latitude')::numeric is distinct from (v_row->>'target_latitude')::numeric
       or (v_forcing->'grid'->>'target_longitude')::numeric is distinct from (v_row->>'target_longitude')::numeric
       or (v_forcing->'grid'->>'sampled_latitude')::numeric is distinct from (v_row->>'grid_latitude')::numeric
       or (v_forcing->'grid'->>'sampled_longitude')::numeric is distinct from (v_row->>'grid_longitude')::numeric then
      raise exception 'HRRR grid metadata violates forcing contract';
    end if;

    v_identity := encode(
      extensions.digest(
        convert_to(
          concat_ws(
            '|',
            v_property_id::text,
            v_valid_at::text,
            v_source_model,
            v_source_state,
            v_reference_time::text,
            v_lead::text,
            v_current_boundary_sha,
            v_index_sha,
            v_records_sha,
            v_algorithm,
            v_schema,
            coalesce(v_row->>'grid_latitude',''),
            coalesce(v_row->>'grid_longitude','')
          ),
          'UTF8'
        ),
        'sha256'
      ),
      'hex'
    );

    insert into farm_watch.property_meteorological_forcing_v1(
      property_id,
      valid_at,
      source_model,
      source_state,
      reference_time,
      forecast_lead_hours,
      forcing,
      target_latitude,
      target_longitude,
      grid_latitude,
      grid_longitude,
      grid_distance_m,
      source_file_url,
      source_index_sha256,
      source_records_sha256,
      boundary_sha256,
      algorithm_version,
      output_schema_version,
      identity_sha256,
      retrieved_at,
      updated_at
    ) values (
      v_property_id,
      v_valid_at,
      v_source_model,
      v_source_state,
      v_reference_time,
      v_lead,
      v_forcing,
      (v_row->>'target_latitude')::numeric,
      (v_row->>'target_longitude')::numeric,
      (v_row->>'grid_latitude')::numeric,
      (v_row->>'grid_longitude')::numeric,
      (v_row->>'grid_distance_m')::numeric,
      v_source_file_url,
      v_index_sha,
      v_records_sha,
      v_current_boundary_sha,
      v_algorithm,
      v_schema,
      v_identity,
      coalesce(nullif(v_row->>'retrieved_at','')::timestamptz,now()),
      now()
    )
    on conflict(property_id,valid_at,source_model,source_state) do update set
      reference_time=excluded.reference_time,
      forecast_lead_hours=excluded.forecast_lead_hours,
      forcing=excluded.forcing,
      target_latitude=excluded.target_latitude,
      target_longitude=excluded.target_longitude,
      grid_latitude=excluded.grid_latitude,
      grid_longitude=excluded.grid_longitude,
      grid_distance_m=excluded.grid_distance_m,
      source_file_url=excluded.source_file_url,
      source_index_sha256=excluded.source_index_sha256,
      source_records_sha256=excluded.source_records_sha256,
      boundary_sha256=excluded.boundary_sha256,
      algorithm_version=excluded.algorithm_version,
      output_schema_version=excluded.output_schema_version,
      identity_sha256=excluded.identity_sha256,
      retrieved_at=excluded.retrieved_at,
      updated_at=now();

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

create or replace function farm_watch.farm_watch_get_meteorological_forcing_v1_internal(
  p_slug text,
  p_valid_at timestamptz default now(),
  p_max_age_minutes integer default 180,
  p_source_state text default 'analysis'
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
  v_boundary_sha text;
  v_contract jsonb := farm_watch.farm_watch_meteorological_forcing_contract_v1();
  v_row farm_watch.property_meteorological_forcing_v1%rowtype;
  v_age_minutes numeric;
begin
  if p_slug is null or length(p_slug)>80 or p_slug !~ '^[a-z0-9][a-z0-9-]{0,79}$' then
    raise exception 'invalid Farm Watch property slug';
  end if;
  if p_valid_at is null then
    raise exception 'meteorological forcing valid time is required';
  end if;
  if p_max_age_minutes is null or p_max_age_minutes<0 or p_max_age_minutes>10080 then
    raise exception 'invalid meteorological forcing max age';
  end if;
  if p_source_state not in ('analysis','forecast') then
    raise exception 'invalid meteorological forcing source state';
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
      'requested_valid_at',p_valid_at,
      'context',null
    );
  end if;

  select s.*
  into v_row
  from farm_watch.property_meteorological_forcing_v1 s
  where s.property_id=v_property_id
    and s.source_state=p_source_state
    and s.valid_at<=p_valid_at
  order by s.valid_at desc,s.retrieved_at desc
  limit 1;

  if not found then
    return jsonb_build_object(
      'status','missing',
      'property',jsonb_build_object('slug',p_slug,'id',v_property_id),
      'requested_valid_at',p_valid_at,
      'source_state',p_source_state,
      'context',null
    );
  end if;

  v_boundary_sha := encode(
    extensions.digest(extensions.st_asewkb(v_boundary),'sha256'),
    'hex'
  );

  if v_row.boundary_sha256 is distinct from v_boundary_sha then
    return jsonb_build_object(
      'status','stale',
      'property',jsonb_build_object('slug',p_slug,'id',v_property_id),
      'requested_valid_at',p_valid_at,
      'context',null,
      'invalidation_reason','property_boundary_changed',
      'stored_identity_sha256',v_row.identity_sha256
    );
  end if;

  if v_row.algorithm_version is distinct from (v_contract->>'algorithm_version')
     or v_row.output_schema_version is distinct from (v_contract->>'output_schema_version') then
    return jsonb_build_object(
      'status','stale',
      'property',jsonb_build_object('slug',p_slug,'id',v_property_id),
      'requested_valid_at',p_valid_at,
      'context',null,
      'invalidation_reason','meteorological_forcing_contract_changed',
      'stored_identity_sha256',v_row.identity_sha256
    );
  end if;

  v_age_minutes := extract(epoch from (p_valid_at-v_row.valid_at))/60.0;

  return jsonb_build_object(
    'status',case when v_age_minutes>p_max_age_minutes then 'stale' else 'available' end,
    'property',jsonb_build_object('slug',p_slug,'id',v_property_id),
    'requested_valid_at',p_valid_at,
    'valid_at',v_row.valid_at,
    'age_minutes',round(v_age_minutes,1),
    'context',v_row.forcing,
    'identity',jsonb_build_object(
      'boundary_sha256',v_row.boundary_sha256,
      'source_index_sha256',v_row.source_index_sha256,
      'source_records_sha256',v_row.source_records_sha256,
      'algorithm_version',v_row.algorithm_version,
      'output_schema_version',v_row.output_schema_version,
      'identity_sha256',v_row.identity_sha256
    ),
    'retrieved_at',v_row.retrieved_at
  );
end;
$$;

revoke all on function farm_watch.farm_watch_meteorological_forcing_contract_v1() from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_get_meteorological_targets_v1_internal(text,integer) from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_store_meteorological_forcing_v1_internal(jsonb) from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_get_meteorological_forcing_v1_internal(text,timestamptz,integer,text) from public,anon,authenticated;

grant execute on function farm_watch.farm_watch_meteorological_forcing_contract_v1() to postgres,service_role;
grant execute on function farm_watch.farm_watch_get_meteorological_targets_v1_internal(text,integer) to service_role;
grant execute on function farm_watch.farm_watch_store_meteorological_forcing_v1_internal(jsonb) to service_role;
grant execute on function farm_watch.farm_watch_get_meteorological_forcing_v1_internal(text,timestamptz,integer,text) to service_role;

create or replace function public.farm_watch_get_meteorological_targets_v1_internal(
  p_slug text default null,
  p_limit integer default 25
)
returns jsonb
language sql
stable
security definer
set search_path='pg_catalog'
as $$
  select farm_watch.farm_watch_get_meteorological_targets_v1_internal(p_slug,p_limit);
$$;

create or replace function public.farm_watch_store_meteorological_forcing_v1_internal(
  p_rows jsonb
)
returns integer
language sql
security definer
set search_path='pg_catalog'
as $$
  select farm_watch.farm_watch_store_meteorological_forcing_v1_internal(p_rows);
$$;

create or replace function public.farm_watch_get_meteorological_forcing_v1_internal(
  p_slug text,
  p_valid_at timestamptz default now(),
  p_max_age_minutes integer default 180,
  p_source_state text default 'analysis'
)
returns jsonb
language sql
stable
security definer
set search_path='pg_catalog'
as $$
  select farm_watch.farm_watch_get_meteorological_forcing_v1_internal(
    p_slug,p_valid_at,p_max_age_minutes,p_source_state
  );
$$;

revoke all on function public.farm_watch_get_meteorological_targets_v1_internal(text,integer) from public,anon,authenticated;
revoke all on function public.farm_watch_store_meteorological_forcing_v1_internal(jsonb) from public,anon,authenticated;
revoke all on function public.farm_watch_get_meteorological_forcing_v1_internal(text,timestamptz,integer,text) from public,anon,authenticated;

grant execute on function public.farm_watch_get_meteorological_targets_v1_internal(text,integer) to service_role;
grant execute on function public.farm_watch_store_meteorological_forcing_v1_internal(jsonb) to service_role;
grant execute on function public.farm_watch_get_meteorological_forcing_v1_internal(text,timestamptz,integer,text) to service_role;

comment on table farm_watch.property_meteorological_forcing_v1 is
'Property-targeted HRRR meteorological forcing snapshots with explicit model/grid provenance. Values are modeled environmental proxies and perform no wildlife inference.';

comment on function farm_watch.farm_watch_store_meteorological_forcing_v1_internal(jsonb) is
'Validates and stores neutral HRRR meteorological forcing with exact source/model/grid provenance and no biological interpretation.';

commit;
