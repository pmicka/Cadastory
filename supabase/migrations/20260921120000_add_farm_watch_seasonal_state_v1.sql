begin;

create table if not exists farm_watch.property_seasonal_state_v1 (
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

create index if not exists property_seasonal_state_as_of_idx
  on farm_watch.property_seasonal_state_v1 (as_of_date desc, retrieved_at desc);

alter table farm_watch.property_seasonal_state_v1 enable row level security;
revoke all on farm_watch.property_seasonal_state_v1 from public, anon, authenticated;
grant select, insert, update, delete on farm_watch.property_seasonal_state_v1 to service_role;

create or replace function farm_watch.farm_watch_seasonal_state_contract_v1()
returns jsonb
language sql
immutable
security definer
set search_path = 'pg_catalog'
as $$
  select jsonb_build_object(
    'algorithm_version','farm-watch-seasonal-state-resolver-v1',
    'output_schema_version','farm-watch-seasonal-state-v1',
    'evidence_class','deterministic_derived',
    'state_vocabulary',jsonb_build_array('known','proxy','stale','unavailable'),
    'freshness_days',jsonb_build_object(
      'precipitation',2,
      'drought',9,
      'stream',1,
      'rootzone_soil_moisture',7,
      'state_fieldwork',14,
      'regional_crop_progress',14,
      'state_crop_stage',14
    ),
    'max_distance_m',jsonb_build_object(
      'precipitation_sample',25000,
      'stream_gauge',25000,
      'rootzone_soil_moisture_proxy',30000
    ),
    'source_contract',jsonb_build_array(
      'hydrology.precip_sample_points + hydrology.precip_daily_snapshots',
      'hydrology.drought_areas',
      'hydrology.stream_gauges + hydrology.stream_observations',
      'hydrology.field_soil_moisture_context',
      'agriculture.state_fieldwork_context',
      'agriculture.crop_progress_layers',
      'agriculture.state_crop_stage_observations',
      'farm_watch.property_resource_edge_context_v1'
    )
  );
$$;

create or replace function farm_watch.farm_watch_seasonal_evidence_state_v1(
  p_observed_date date,
  p_as_of_date date,
  p_fresh_days integer,
  p_fresh_state text
)
returns text
language plpgsql
immutable
security definer
set search_path = 'pg_catalog'
as $$
begin
  if p_fresh_state not in ('known','proxy') then
    raise exception 'fresh seasonal evidence state must be known or proxy';
  end if;
  if p_fresh_days < 0 then
    raise exception 'seasonal freshness days must be non-negative';
  end if;
  if p_observed_date is null or p_as_of_date is null or p_observed_date > p_as_of_date then
    return 'unavailable';
  end if;
  if (p_as_of_date - p_observed_date) > p_fresh_days then
    return 'stale';
  end if;
  return p_fresh_state;
end;
$$;

create or replace function farm_watch.farm_watch_resolve_seasonal_state_v1_internal(
  p_slug text,
  p_as_of_date date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = 'pg_catalog', 'farm_watch', 'hydrology', 'agriculture', 'extensions'
as $$
declare
  v_property_id uuid;
  v_state_code text;
  v_center extensions.geometry;
  v_boundary extensions.geometry;
  v_boundary_sha256 text;
  v_contract jsonb;
  v_algorithm text;
  v_schema text;

  v_precip_sample_key text;
  v_precip_distance_m numeric;
  v_precip_date date;
  v_precip_source_observed_at timestamptz;
  v_precip_1d numeric;
  v_precip_7d numeric;
  v_precip_30d numeric;
  v_precip_state text;
  v_precip jsonb;

  v_drought_date date;
  v_drought_class text;
  v_drought_severity integer;
  v_drought_source_native_id text;
  v_drought_row_count integer;
  v_drought_state text;
  v_drought jsonb;

  v_stream_gauge_id text;
  v_stream_gauge_name text;
  v_stream_distance_m numeric;
  v_stream_observed_at timestamptz;
  v_stream_value numeric;
  v_stream_unit text;
  v_stream_approval text;
  v_stream_qualifier text;
  v_stream_state text;
  v_stream jsonb;

  v_soil_field_id uuid;
  v_soil_distance_m numeric;
  v_soil_observed_at timestamptz;
  v_soil_retrieved_at timestamptz;
  v_soil_rootzone_vwc numeric;
  v_soil_depth_cm integer;
  v_soil_model text;
  v_soil_attributes jsonb;
  v_soil_state text;
  v_soil jsonb;

  v_fieldwork_week date;
  v_fieldwork_report date;
  v_fieldwork_days numeric;
  v_topsoil_very_short smallint;
  v_topsoil_short smallint;
  v_topsoil_adequate smallint;
  v_topsoil_surplus smallint;
  v_subsoil_very_short smallint;
  v_subsoil_short smallint;
  v_subsoil_adequate smallint;
  v_subsoil_surplus smallint;
  v_fieldwork_source_url text;
  v_fieldwork_state text;
  v_fieldwork jsonb;

  v_crop_progress_week date;
  v_crop_progress_rows jsonb;
  v_crop_progress_state text;
  v_crop_progress jsonb;

  v_crop_stage_week date;
  v_crop_stage_rows jsonb;
  v_crop_stage_state text;
  v_crop_stage jsonb;

  v_resource_payload jsonb;
  v_resource_identity text;
  v_resource_retrieved_at timestamptz;
  v_resource_context jsonb;
  v_crop_year integer;
  v_crop_state text;
  v_crop_context jsonb;

  v_component_states jsonb;
  v_fresh_component_count integer;
  v_stale_component_count integer;
  v_unavailable_component_count integer;
  v_status text;
  v_source_fingerprint jsonb;
  v_source_fingerprint_sha256 text;
  v_source_signature text;
  v_source_signature_sha256 text;
  v_identity_sha256 text;
  v_context jsonb;
begin
  if p_slug is null
     or length(p_slug) > 80
     or p_slug !~ '^[a-z0-9][a-z0-9-]{0,79}$' then
    raise exception 'invalid Farm Watch property slug';
  end if;
  if p_as_of_date is null then
    raise exception 'seasonal-state as-of date is required';
  end if;

  select
    p.id,
    p.state_code,
    coalesce(p.center, extensions.st_pointonsurface(p.boundary)),
    p.boundary
  into
    v_property_id,
    v_state_code,
    v_center,
    v_boundary
  from farm_watch.properties p
  where p.slug=p_slug and p.status='active'
  limit 1;

  if v_property_id is null or v_center is null or v_boundary is null then
    return jsonb_build_object(
      'status','missing',
      'property',jsonb_build_object('slug',p_slug),
      'as_of_date',p_as_of_date,
      'context',null
    );
  end if;

  v_contract := farm_watch.farm_watch_seasonal_state_contract_v1();
  v_algorithm := v_contract->>'algorithm_version';
  v_schema := v_contract->>'output_schema_version';
  v_boundary_sha256 := encode(
    extensions.digest(extensions.st_asewkb(v_boundary),'sha256'),
    'hex'
  );

  select
    sp.sample_key,
    round(extensions.st_distance(sp.location::geography, v_center::geography)::numeric,1)
  into
    v_precip_sample_key,
    v_precip_distance_m
  from hydrology.precip_sample_points sp
  where sp.active is true
    and sp.location is not null
    and extensions.st_dwithin(
      sp.location::geography,
      v_center::geography,
      (v_contract->'max_distance_m'->>'precipitation_sample')::integer
    )
  order by sp.location <-> v_center
  limit 1;

  if v_precip_sample_key is not null then
    select max(s.snapshot_date)
    into v_precip_date
    from hydrology.precip_daily_snapshots s
    where s.sample_key=v_precip_sample_key
      and s.snapshot_date <= p_as_of_date;

    if v_precip_date is not null then
      select
        max(s.source_observed_at) filter (where s.snapshot_date=v_precip_date),
        max(s.precipitation_24h_inches) filter (where s.snapshot_date=v_precip_date),
        sum(s.precipitation_24h_inches) filter (
          where s.snapshot_date between p_as_of_date - 6 and p_as_of_date
        ),
        sum(s.precipitation_24h_inches) filter (
          where s.snapshot_date between p_as_of_date - 29 and p_as_of_date
        )
      into
        v_precip_source_observed_at,
        v_precip_1d,
        v_precip_7d,
        v_precip_30d
      from hydrology.precip_daily_snapshots s
      where s.sample_key=v_precip_sample_key
        and s.snapshot_date between p_as_of_date - 29 and p_as_of_date;
    end if;
  end if;

  v_precip_state := farm_watch.farm_watch_seasonal_evidence_state_v1(
    v_precip_date,
    p_as_of_date,
    (v_contract->'freshness_days'->>'precipitation')::integer,
    'proxy'
  );
  v_precip := case
    when v_precip_state='unavailable' then jsonb_build_object(
      'state','unavailable',
      'scope','nearest_qpe_sample',
      'reason',case
        when v_precip_sample_key is null then 'no active precipitation sample point is available within the configured distance'
        else 'no precipitation daily snapshot is available on or before the requested date'
      end
    )
    else jsonb_build_object(
      'state',v_precip_state,
      'scope','nearest_qpe_sample',
      'sample_key',v_precip_sample_key,
      'distance_m',v_precip_distance_m,
      'observed_date',v_precip_date,
      'age_days',p_as_of_date-v_precip_date,
      'source_observed_at',v_precip_source_observed_at,
      'precipitation_in',jsonb_build_object(
        '1d',v_precip_1d,
        '7d',v_precip_7d,
        '30d',v_precip_30d
      ),
      'interpretation_boundary','QPE precipitation is remotely sensed/model-derived regional precipitation context at the nearest configured sample point, not a parcel rain gauge.'
    )
  end;

  select max(d.valid_date)
  into v_drought_date
  from hydrology.drought_areas d
  where d.source_present is true
    and d.valid_date <= p_as_of_date;

  if v_drought_date is not null then
    select count(*)
    into v_drought_row_count
    from hydrology.drought_areas d
    where d.source_present is true
      and d.valid_date=v_drought_date;

    select d.drought_class, d.severity, d.source_native_id
    into v_drought_class, v_drought_severity, v_drought_source_native_id
    from hydrology.drought_areas d
    where d.source_present is true
      and d.valid_date=v_drought_date
      and d.geometry is not null
      and extensions.st_intersects(d.geometry, v_center)
    order by d.severity desc nulls last
    limit 1;
  end if;

  v_drought_state := farm_watch.farm_watch_seasonal_evidence_state_v1(
    case when coalesce(v_drought_row_count,0)>0 then v_drought_date else null end,
    p_as_of_date,
    (v_contract->'freshness_days'->>'drought')::integer,
    'known'
  );
  v_drought := case
    when v_drought_state='unavailable' then jsonb_build_object(
      'state','unavailable',
      'scope','us_drought_monitor_point_classification',
      'reason','no usable drought-map vintage is available on or before the requested date'
    )
    else jsonb_build_object(
      'state',v_drought_state,
      'scope','us_drought_monitor_point_classification',
      'map_date',v_drought_date,
      'age_days',p_as_of_date-v_drought_date,
      'mapped_d0_plus',v_drought_class is not null,
      'drought_class',coalesce(v_drought_class,'none_mapped'),
      'severity',v_drought_severity,
      'source_native_id',v_drought_source_native_id,
      'map_polygon_count',v_drought_row_count,
      'interpretation_boundary','A mapped drought class is regional U.S. Drought Monitor context. none_mapped means the property point did not intersect a D0+ polygon in that map vintage; it is not a parcel soil-moisture measurement.'
    )
  end;

  select
    g.gauge_id,
    g.name,
    round(extensions.st_distance(g.location::geography, v_center::geography)::numeric,1)
  into
    v_stream_gauge_id,
    v_stream_gauge_name,
    v_stream_distance_m
  from hydrology.stream_gauges g
  where g.source_present is true
    and g.location is not null
    and extensions.st_dwithin(
      g.location::geography,
      v_center::geography,
      (v_contract->'max_distance_m'->>'stream_gauge')::integer
    )
  order by g.location <-> v_center
  limit 1;

  if v_stream_gauge_id is not null then
    select
      o.observed_at,
      o.value,
      o.unit,
      o.approval_status,
      o.qualifier
    into
      v_stream_observed_at,
      v_stream_value,
      v_stream_unit,
      v_stream_approval,
      v_stream_qualifier
    from hydrology.stream_observations o
    where o.gauge_id=v_stream_gauge_id
      and o.observed_at < ((p_as_of_date + 1)::timestamp at time zone 'UTC')
      and (
        o.parameter_code='00060'
        or lower(coalesce(o.parameter_name,'')) like '%discharge%'
      )
    order by o.observed_at desc
    limit 1;
  end if;

  v_stream_state := farm_watch.farm_watch_seasonal_evidence_state_v1(
    v_stream_observed_at::date,
    p_as_of_date,
    (v_contract->'freshness_days'->>'stream')::integer,
    'proxy'
  );
  v_stream := case
    when v_stream_state='unavailable' then jsonb_build_object(
      'state','unavailable',
      'scope','nearest_usgs_stream_gauge',
      'reason',case
        when v_stream_gauge_id is null then 'no active stream gauge is available within the configured distance'
        else 'no discharge observation is available on or before the requested date'
      end
    )
    else jsonb_build_object(
      'state',v_stream_state,
      'scope','nearest_usgs_stream_gauge',
      'gauge_id',v_stream_gauge_id,
      'gauge_name',v_stream_gauge_name,
      'distance_m',v_stream_distance_m,
      'observed_at',v_stream_observed_at,
      'age_days',p_as_of_date-v_stream_observed_at::date,
      'discharge',v_stream_value,
      'unit',v_stream_unit,
      'approval_status',v_stream_approval,
      'qualifier',v_stream_qualifier,
      'interpretation_boundary','Nearest-gauge discharge is off-property hydrologic context and must not be interpreted as measured flow, water depth, or crossing condition on the property.'
    )
  end;

  select
    s.field_id,
    round(extensions.st_distance(s.location::geography, v_center::geography)::numeric,1),
    s.observed_at,
    s.retrieved_at,
    s.rootzone_vwc,
    s.layer_depth_cm,
    s.model_version,
    s.attributes
  into
    v_soil_field_id,
    v_soil_distance_m,
    v_soil_observed_at,
    v_soil_retrieved_at,
    v_soil_rootzone_vwc,
    v_soil_depth_cm,
    v_soil_model,
    v_soil_attributes
  from hydrology.field_soil_moisture_context s
  where s.location is not null
    and s.observed_at::date <= p_as_of_date
    and extensions.st_dwithin(
      s.location::geography,
      v_center::geography,
      (v_contract->'max_distance_m'->>'rootzone_soil_moisture_proxy')::integer
    )
  order by s.observed_at desc, s.location <-> v_center
  limit 1;

  v_soil_state := farm_watch.farm_watch_seasonal_evidence_state_v1(
    v_soil_observed_at::date,
    p_as_of_date,
    (v_contract->'freshness_days'->>'rootzone_soil_moisture')::integer,
    'proxy'
  );
  v_soil := case
    when v_soil_state='unavailable' then jsonb_build_object(
      'state','unavailable',
      'scope','nearest_crop_casma_rootzone_proxy',
      'reason','no root-zone soil-moisture context is available within the configured distance on or before the requested date'
    )
    else jsonb_build_object(
      'state',v_soil_state,
      'scope','nearest_crop_casma_rootzone_proxy',
      'field_id',v_soil_field_id,
      'distance_m',v_soil_distance_m,
      'observed_at',v_soil_observed_at,
      'retrieved_at',v_soil_retrieved_at,
      'age_days',p_as_of_date-v_soil_observed_at::date,
      'rootzone_vwc',v_soil_rootzone_vwc,
      'layer_depth_cm',v_soil_depth_cm,
      'model_version',v_soil_model,
      'spatial_resolution_km',nullif(v_soil_attributes->>'spatial_resolution_km','')::numeric,
      'publication_lag_days',nullif(v_soil_attributes->>'publication_lag_days','')::integer,
      'interpretation_boundary','Crop-CASMA/SMAP root-zone VWC is model-assimilated regional context at a nearby mapped field, not an in-field sensor, parcel drainage determination, or direct property soil-moisture measurement.'
    )
  end;

  select
    f.week_ending,
    f.report_date,
    f.days_suitable,
    f.topsoil_very_short_pct,
    f.topsoil_short_pct,
    f.topsoil_adequate_pct,
    f.topsoil_surplus_pct,
    f.subsoil_very_short_pct,
    f.subsoil_short_pct,
    f.subsoil_adequate_pct,
    f.subsoil_surplus_pct,
    f.source_url
  into
    v_fieldwork_week,
    v_fieldwork_report,
    v_fieldwork_days,
    v_topsoil_very_short,
    v_topsoil_short,
    v_topsoil_adequate,
    v_topsoil_surplus,
    v_subsoil_very_short,
    v_subsoil_short,
    v_subsoil_adequate,
    v_subsoil_surplus,
    v_fieldwork_source_url
  from agriculture.state_fieldwork_context f
  where f.state_code=v_state_code
    and f.week_ending <= p_as_of_date
  order by f.week_ending desc
  limit 1;

  v_fieldwork_state := farm_watch.farm_watch_seasonal_evidence_state_v1(
    v_fieldwork_week,
    p_as_of_date,
    (v_contract->'freshness_days'->>'state_fieldwork')::integer,
    'proxy'
  );
  v_fieldwork := case
    when v_fieldwork_state='unavailable' then jsonb_build_object(
      'state','unavailable',
      'scope','state_weekly_fieldwork_and_soil_moisture',
      'reason','no state fieldwork context is available on or before the requested date'
    )
    else jsonb_build_object(
      'state',v_fieldwork_state,
      'scope','state_weekly_fieldwork_and_soil_moisture',
      'state_code',v_state_code,
      'week_ending',v_fieldwork_week,
      'report_date',v_fieldwork_report,
      'age_days',p_as_of_date-v_fieldwork_week,
      'days_suitable_for_fieldwork',v_fieldwork_days,
      'topsoil_pct',jsonb_build_object(
        'very_short',v_topsoil_very_short,
        'short',v_topsoil_short,
        'adequate',v_topsoil_adequate,
        'surplus',v_topsoil_surplus
      ),
      'subsoil_pct',jsonb_build_object(
        'very_short',v_subsoil_very_short,
        'short',v_subsoil_short,
        'adequate',v_subsoil_adequate,
        'surplus',v_subsoil_surplus
      ),
      'source_url',v_fieldwork_source_url,
      'interpretation_boundary','State-level fieldwork and soil-moisture percentages are regional agricultural context. They do not establish conditions on the selected property.'
    )
  end;

  select max(c.week_ending)
  into v_crop_progress_week
  from agriculture.crop_progress_layers c
  where c.week_ending <= p_as_of_date
    and c.valid_cell_count > 0;

  if v_crop_progress_week is not null then
    select jsonb_agg(
      jsonb_build_object(
        'crop',c.crop,
        'metric',c.metric,
        'stage',c.stage,
        'pilot_mean',c.pilot_mean,
        'pilot_median',c.pilot_median,
        'pilot_p25',c.pilot_p25,
        'pilot_p75',c.pilot_p75,
        'valid_cell_count',c.valid_cell_count,
        'resolution_m',nullif(c.metadata->>'resolution_m','')::integer,
        'radius_m',nullif(c.metadata->>'radius_m','')::numeric,
        'synthetic',coalesce((c.metadata->>'synthetic')::boolean,false),
        'source_note',c.metadata->>'source_note'
      )
      order by c.crop,c.metric
    )
    into v_crop_progress_rows
    from agriculture.crop_progress_layers c
    where c.week_ending=v_crop_progress_week
      and c.valid_cell_count > 0;
  end if;

  v_crop_progress_state := farm_watch.farm_watch_seasonal_evidence_state_v1(
    v_crop_progress_week,
    p_as_of_date,
    (v_contract->'freshness_days'->>'regional_crop_progress')::integer,
    'proxy'
  );
  v_crop_progress := case
    when v_crop_progress_state='unavailable' then jsonb_build_object(
      'state','unavailable',
      'scope','regional_gridded_crop_progress',
      'reason','no usable regional gridded crop-progress layer is available on or before the requested date'
    )
    else jsonb_build_object(
      'state',v_crop_progress_state,
      'scope','regional_gridded_crop_progress',
      'week_ending',v_crop_progress_week,
      'age_days',p_as_of_date-v_crop_progress_week,
      'rows',coalesce(v_crop_progress_rows,'[]'::jsonb),
      'interpretation_boundary','NASS gridded crop-progress layers are regional synthetic representations of confidential survey data. They do not establish crop stage, harvest state, condition, or availability on a specific mapped field.'
    )
  end;

  select max(c.week_ending)
  into v_crop_stage_week
  from agriculture.state_crop_stage_observations c
  where c.state_code=v_state_code
    and c.week_ending <= p_as_of_date;

  if v_crop_stage_week is not null then
    select jsonb_agg(
      jsonb_build_object(
        'crop_name',c.crop_name,
        'stage_name',c.stage_name,
        'metric_kind',c.metric_kind,
        'current_pct',c.current_pct,
        'prior_week_pct',c.prior_week_pct,
        'prior_year_pct',c.prior_year_pct,
        'five_year_avg_pct',c.five_year_avg_pct,
        'source_url',c.source_url
      )
      order by c.crop_name,c.stage_name
    )
    into v_crop_stage_rows
    from agriculture.state_crop_stage_observations c
    where c.state_code=v_state_code
      and c.week_ending=v_crop_stage_week;
  end if;

  v_crop_stage_state := farm_watch.farm_watch_seasonal_evidence_state_v1(
    v_crop_stage_week,
    p_as_of_date,
    (v_contract->'freshness_days'->>'state_crop_stage')::integer,
    'proxy'
  );
  v_crop_stage := case
    when v_crop_stage_state='unavailable' then jsonb_build_object(
      'state','unavailable',
      'scope','state_crop_stage',
      'reason','no state crop-stage observation is available on or before the requested date'
    )
    else jsonb_build_object(
      'state',v_crop_stage_state,
      'scope','state_crop_stage',
      'state_code',v_state_code,
      'week_ending',v_crop_stage_week,
      'age_days',p_as_of_date-v_crop_stage_week,
      'rows',coalesce(v_crop_stage_rows,'[]'::jsonb),
      'interpretation_boundary','State crop-stage percentages are statewide context only. They do not establish field-level crop stage, treatment need, harvest state, or resource availability.'
    )
  end;

  v_resource_payload := farm_watch.farm_watch_get_resource_edge_context_v1_internal(
    p_slug,
    false
  );

  if v_resource_payload->>'status'='available' then
    v_resource_identity := nullif(
      v_resource_payload->'identity'->>'identity_sha256',
      ''
    );
    v_resource_retrieved_at := nullif(
      v_resource_payload->>'retrieved_at',
      ''
    )::timestamptz;
    v_resource_context := v_resource_payload->'context';

    select max((x.value->>'year')::integer)
    into v_crop_year
    from jsonb_array_elements(
      coalesce(v_resource_context->'latest_crop_composition_3000m','[]'::jsonb)
    ) as x(value);
  end if;

  v_crop_state := case
    when v_resource_payload->>'status'='stale' then 'stale'
    when v_resource_context is null or v_crop_year is null then 'unavailable'
    when v_crop_year > extract(year from p_as_of_date)::integer then 'unavailable'
    when v_crop_year < extract(year from p_as_of_date)::integer then 'stale'
    else 'known'
  end;
  v_crop_context := case
    when v_resource_payload->>'status'='stale' then jsonb_build_object(
      'state','stale',
      'scope','barrier_aware_latest_cdl_mapped_fields',
      'reason','the persisted resource-edge context is stale relative to its current dependency identity',
      'invalidation_reason',v_resource_payload->>'invalidation_reason',
      'stored_identity_sha256',v_resource_payload->>'stored_identity_sha256',
      'expected_identity_sha256',v_resource_payload->>'expected_identity_sha256'
    )
    when v_crop_state='unavailable' then jsonb_build_object(
      'state','unavailable',
      'scope','barrier_aware_latest_cdl_mapped_fields',
      'reason',case
        when v_crop_year is not null and v_crop_year > extract(year from p_as_of_date)::integer
          then 'the persisted latest CDL crop context postdates the requested as-of year'
        else 'no current resource-edge crop composition is available'
      end
    )
    else jsonb_build_object(
      'state',v_crop_state,
      'scope','barrier_aware_latest_cdl_mapped_fields',
      'resource_edge_identity_sha256',v_resource_identity,
      'resource_edge_retrieved_at',v_resource_retrieved_at,
      'latest_crop_year',v_crop_year,
      'crop_year_age',extract(year from p_as_of_date)::integer-v_crop_year,
      'nearest_mapped_field',v_resource_context->'nearest_mapped_field',
      'composition_3000m',v_resource_context->'latest_crop_composition_3000m',
      'interpretation_boundary','CDL and mapped-field classes describe mapped land-cover/crop identity for the stated year. They do not establish current forage availability, standing crop, harvest state, access, or animal use.'
    )
  end;

  v_component_states := jsonb_build_object(
    'precipitation',v_precip_state,
    'drought',v_drought_state,
    'stream',v_stream_state,
    'rootzone_soil_moisture',v_soil_state,
    'state_fieldwork',v_fieldwork_state,
    'regional_crop_progress',v_crop_progress_state,
    'state_crop_stage',v_crop_stage_state,
    'mapped_crop_context',v_crop_state
  );

  select
    count(*) filter (where value in ('known','proxy')),
    count(*) filter (where value='stale'),
    count(*) filter (where value='unavailable')
  into
    v_fresh_component_count,
    v_stale_component_count,
    v_unavailable_component_count
  from jsonb_each_text(v_component_states);

  v_status := case
    when v_fresh_component_count=0 then 'unavailable'
    when v_stale_component_count=0 and v_unavailable_component_count=0 then 'available'
    else 'partial'
  end;

  v_source_fingerprint := jsonb_build_object(
    'as_of_date',p_as_of_date,
    'precipitation',jsonb_build_object(
      'sample_key',v_precip_sample_key,
      'observed_date',v_precip_date,
      'source_observed_at',v_precip_source_observed_at,
      'one_day_in',v_precip_1d,
      'seven_day_in',v_precip_7d,
      'thirty_day_in',v_precip_30d
    ),
    'drought',jsonb_build_object(
      'map_date',v_drought_date,
      'class',v_drought_class,
      'severity',v_drought_severity,
      'source_native_id',v_drought_source_native_id,
      'map_polygon_count',v_drought_row_count
    ),
    'stream',jsonb_build_object(
      'gauge_id',v_stream_gauge_id,
      'observed_at',v_stream_observed_at,
      'value',v_stream_value,
      'unit',v_stream_unit,
      'approval_status',v_stream_approval
    ),
    'rootzone_soil_moisture',jsonb_build_object(
      'field_id',v_soil_field_id,
      'observed_at',v_soil_observed_at,
      'rootzone_vwc',v_soil_rootzone_vwc,
      'model_version',v_soil_model
    ),
    'state_fieldwork',jsonb_build_object(
      'state_code',v_state_code,
      'week_ending',v_fieldwork_week,
      'days_suitable',v_fieldwork_days,
      'topsoil_short',v_topsoil_short,
      'subsoil_short',v_subsoil_short
    ),
    'regional_crop_progress',jsonb_build_object(
      'week_ending',v_crop_progress_week,
      'rows',coalesce(v_crop_progress_rows,'[]'::jsonb)
    ),
    'state_crop_stage',jsonb_build_object(
      'state_code',v_state_code,
      'week_ending',v_crop_stage_week,
      'rows',coalesce(v_crop_stage_rows,'[]'::jsonb)
    ),
    'mapped_crop_context',jsonb_build_object(
      'resource_edge_identity_sha256',v_resource_identity,
      'latest_crop_year',v_crop_year,
      'composition_3000m',coalesce(v_resource_context->'latest_crop_composition_3000m','[]'::jsonb)
    )
  );
  v_source_fingerprint_sha256 := encode(
    extensions.digest(convert_to(v_source_fingerprint::text,'UTF8'),'sha256'),
    'hex'
  );
  v_source_signature := concat_ws(
    '|',
    'product=seasonal-state',
    'sources=central-existing-feeds-v1',
    'as_of=' || p_as_of_date::text,
    'source_fingerprint_sha256=' || v_source_fingerprint_sha256
  );
  v_source_signature_sha256 := encode(
    extensions.digest(convert_to(v_source_signature,'UTF8'),'sha256'),
    'hex'
  );
  v_identity_sha256 := encode(
    extensions.digest(
      convert_to(
        concat_ws(
          '|',
          v_property_id::text,
          p_as_of_date::text,
          v_algorithm,
          v_schema,
          v_boundary_sha256,
          v_source_signature_sha256
        ),
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  v_context := jsonb_build_object(
    'schema',v_schema,
    'method',v_algorithm,
    'as_of_date',p_as_of_date,
    'evidence_class','deterministic_derived',
    'component_state_vocabulary',v_contract->'state_vocabulary',
    'component_states',v_component_states,
    'component_counts',jsonb_build_object(
      'current_or_proxy',v_fresh_component_count,
      'stale',v_stale_component_count,
      'unavailable',v_unavailable_component_count
    ),
    'components',jsonb_build_object(
      'precipitation',v_precip,
      'drought',v_drought,
      'stream',v_stream,
      'rootzone_soil_moisture',v_soil,
      'state_fieldwork',v_fieldwork,
      'regional_crop_progress',v_crop_progress,
      'state_crop_stage',v_crop_stage,
      'mapped_crop_context',v_crop_context
    ),
    'source_fingerprint_sha256',v_source_fingerprint_sha256,
    'scoring_performed',false,
    'behavioral_inference_performed',false,
    'interpretation_boundary','Seasonal state describes dated environmental and agricultural evidence or proxies with explicit freshness and scope. It does not infer deer presence, movement, bedding, forage use, water use, hunting pressure, habitat quality, or management action.'
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

create or replace function farm_watch.farm_watch_refresh_seasonal_state_v1_internal(
  p_slug text,
  p_as_of_date date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path = 'pg_catalog', 'farm_watch'
as $$
declare
  v_resolved jsonb;
  v_property_id uuid;
begin
  v_resolved := farm_watch.farm_watch_resolve_seasonal_state_v1_internal(p_slug,p_as_of_date);
  if v_resolved->>'status'='missing' then
    return v_resolved;
  end if;

  v_property_id := nullif(v_resolved->'property'->>'id','')::uuid;
  if v_property_id is null then
    raise exception 'resolved seasonal-state property identity is unavailable';
  end if;

  insert into farm_watch.property_seasonal_state_v1(
    property_id,
    as_of_date,
    status,
    context,
    boundary_sha256,
    source_signature,
    source_signature_sha256,
    algorithm_version,
    output_schema_version,
    identity_sha256,
    retrieved_at,
    updated_at
  ) values (
    v_property_id,
    p_as_of_date,
    v_resolved->>'status',
    v_resolved->'context',
    v_resolved->'identity'->>'boundary_sha256',
    v_resolved->'identity'->>'source_signature',
    v_resolved->'identity'->>'source_signature_sha256',
    v_resolved->'identity'->>'algorithm_version',
    v_resolved->'identity'->>'output_schema_version',
    v_resolved->'identity'->>'identity_sha256',
    now(),
    now()
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

  return farm_watch.farm_watch_get_seasonal_state_v1_internal(p_slug,p_as_of_date);
end;
$$;

create or replace function farm_watch.farm_watch_get_seasonal_state_v1_internal(
  p_slug text,
  p_as_of_date date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = 'pg_catalog', 'farm_watch', 'extensions'
as $$
declare
  v_property_id uuid;
  v_boundary extensions.geometry;
  v_boundary_sha256 text;
  v_contract jsonb;
  v_row farm_watch.property_seasonal_state_v1%rowtype;
begin
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

  select *
  into v_row
  from farm_watch.property_seasonal_state_v1 s
  where s.property_id=v_property_id
    and s.as_of_date=p_as_of_date
  limit 1;

  if not found then
    return jsonb_build_object(
      'status','missing',
      'property',jsonb_build_object('slug',p_slug,'id',v_property_id),
      'as_of_date',p_as_of_date,
      'context',null
    );
  end if;

  v_boundary_sha256 := encode(
    extensions.digest(extensions.st_asewkb(v_boundary),'sha256'),
    'hex'
  );
  v_contract := farm_watch.farm_watch_seasonal_state_contract_v1();

  if v_row.boundary_sha256 is distinct from v_boundary_sha256 then
    return jsonb_build_object(
      'status','stale',
      'property',jsonb_build_object('slug',p_slug,'id',v_property_id),
      'as_of_date',p_as_of_date,
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
      'as_of_date',p_as_of_date,
      'context',null,
      'invalidation_reason','seasonal_state_contract_changed',
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

revoke all on function farm_watch.farm_watch_seasonal_state_contract_v1() from public, anon, authenticated;
revoke all on function farm_watch.farm_watch_seasonal_evidence_state_v1(date,date,integer,text) from public, anon, authenticated;
revoke all on function farm_watch.farm_watch_resolve_seasonal_state_v1_internal(text,date) from public, anon, authenticated;
revoke all on function farm_watch.farm_watch_refresh_seasonal_state_v1_internal(text,date) from public, anon, authenticated;
revoke all on function farm_watch.farm_watch_get_seasonal_state_v1_internal(text,date) from public, anon, authenticated;

grant execute on function farm_watch.farm_watch_seasonal_state_contract_v1() to postgres, service_role;
grant execute on function farm_watch.farm_watch_seasonal_evidence_state_v1(date,date,integer,text) to postgres, service_role;
grant execute on function farm_watch.farm_watch_resolve_seasonal_state_v1_internal(text,date) to service_role;
grant execute on function farm_watch.farm_watch_refresh_seasonal_state_v1_internal(text,date) to service_role;
grant execute on function farm_watch.farm_watch_get_seasonal_state_v1_internal(text,date) to service_role;

create or replace function public.farm_watch_refresh_seasonal_state_v1_internal(
  p_slug text,
  p_as_of_date date default current_date
)
returns jsonb
language sql
security definer
set search_path = 'pg_catalog'
as $$
  select farm_watch.farm_watch_refresh_seasonal_state_v1_internal(p_slug,p_as_of_date);
$$;

create or replace function public.farm_watch_get_seasonal_state_v1_internal(
  p_slug text,
  p_as_of_date date default current_date
)
returns jsonb
language sql
stable
security definer
set search_path = 'pg_catalog'
as $$
  select farm_watch.farm_watch_get_seasonal_state_v1_internal(p_slug,p_as_of_date);
$$;

revoke all on function public.farm_watch_refresh_seasonal_state_v1_internal(text,date)
from public, anon, authenticated;
revoke all on function public.farm_watch_get_seasonal_state_v1_internal(text,date)
from public, anon, authenticated;
grant execute on function public.farm_watch_refresh_seasonal_state_v1_internal(text,date)
to service_role;
grant execute on function public.farm_watch_get_seasonal_state_v1_internal(text,date)
to service_role;

comment on table farm_watch.property_seasonal_state_v1 is
'Date-keyed Farm Watch seasonal evidence snapshots. Component states are explicit known/proxy/stale/unavailable and must not be interpreted as wildlife-use inference.';

comment on function farm_watch.farm_watch_resolve_seasonal_state_v1_internal(text,date) is
'Builds a neutral dated environmental/agricultural state from existing central sources with explicit scope and freshness. No deer-use or management inference is performed.';

commit;
