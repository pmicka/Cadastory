begin;

insert into ingest.sources (
  slug,name,authority,source_class,geographic_scope,acquisition_method,update_cadence,
  authority_level,status,homepage_url,license_notes,commercial_use_status,notes
)
values (
  'noaa-nohrsc-national-snow-analysis',
  'NOAA National Snow Analysis — Snow Depth',
  'NOAA / National Weather Service / National Operational Hydrologic Remote Sensing Center',
  'assimilated_snow_analysis',
  'Conterminous United States',
  'Public NOAA/NWS ArcGIS MapServer identify request against the operational NOHRSC National Snow Analysis snow-depth mosaic. Farm Watch stores only the point snow-depth value and source timestamps/provenance.',
  'subdaily operational analysis; Farm Watch samples daily',
  'authoritative_modeled_observational_analysis',
  'active_reference',
  'https://www.nohrsc.noaa.gov/nsa/',
  'U.S. Government/public NOAA data. Preserve NOAA/NWS/NOHRSC attribution and modeled/observational-analysis semantics.',
  'allowed',
  'Farm Watch M08 uses the operational snow-depth analysis as a national source substitution for the study-site measured daily snow depth. The NOAA analysis assimilates ground, airborne and satellite observations into a physically based snow model. The point value remains a modeled/assimilated environmental estimate, not an on-property ruler observation.'
)
on conflict (slug) do update set
  name=excluded.name,authority=excluded.authority,source_class=excluded.source_class,
  geographic_scope=excluded.geographic_scope,acquisition_method=excluded.acquisition_method,
  update_cadence=excluded.update_cadence,authority_level=excluded.authority_level,
  status=excluded.status,homepage_url=excluded.homepage_url,license_notes=excluded.license_notes,
  commercial_use_status=excluded.commercial_use_status,notes=excluded.notes,updated_at=now();

update farm_watch.properties
set metadata=jsonb_set(coalesce(metadata,'{}'::jsonb),'{time_zone}',to_jsonb('America/New_York'::text),true),
    updated_at=now()
where slug='validation-property-01'
  and coalesce(metadata->>'time_zone','')='';

create table if not exists farm_watch.property_snow_winter_severity_daily_v1 (
  property_id uuid not null references farm_watch.properties(id) on delete cascade,
  observation_date date not null,
  time_zone text not null,
  status text not null check (status in ('available','partial','unavailable')),
  snow_status text not null check (snow_status in ('available','unavailable')),
  snow_depth_cm numeric,
  snow_source_valid_at timestamptz,
  snow_source_ingested_at timestamptz,
  snow_source_object text,
  snow_source_payload_sha256 text,
  temperature_status text not null check (temperature_status in ('pending','available','partial','unavailable')),
  minimum_daily_temperature_c numeric,
  temperature_hour_count integer,
  temperature_expected_hours integer,
  temperature_coverage_ratio numeric,
  boundary_sha256 text not null check (boundary_sha256 ~ '^[0-9a-f]{64}$'),
  algorithm_version text not null,
  output_schema_version text not null,
  identity_sha256 text not null check (identity_sha256 ~ '^[0-9a-f]{64}$'),
  retrieved_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(property_id,observation_date),
  check (snow_depth_cm is null or snow_depth_cm>=0),
  check (snow_source_payload_sha256 is null or snow_source_payload_sha256 ~ '^[0-9a-f]{64}$'),
  check (temperature_hour_count is null or temperature_hour_count>=0),
  check (temperature_expected_hours is null or temperature_expected_hours between 23 and 25),
  check (temperature_coverage_ratio is null or temperature_coverage_ratio between 0 and 1)
);

alter table farm_watch.property_snow_winter_severity_daily_v1 enable row level security;
revoke all on farm_watch.property_snow_winter_severity_daily_v1 from public,anon,authenticated;
grant select,insert,update,delete on farm_watch.property_snow_winter_severity_daily_v1 to service_role;

create or replace function farm_watch.farm_watch_get_snow_winter_severity_target_v1_internal(p_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','farm_watch','extensions'
as $$
declare
  v_property_id uuid;
  v_boundary extensions.geometry;
  v_point extensions.geometry;
  v_time_zone text;
begin
  if p_slug is null or length(p_slug)>80 or p_slug !~ '^[a-z0-9][a-z0-9-]{0,79}$' then
    raise exception 'invalid Farm Watch property slug';
  end if;

  select p.id,p.boundary,coalesce(p.center,extensions.st_pointonsurface(p.boundary)),nullif(p.metadata->>'time_zone','')
  into v_property_id,v_boundary,v_point,v_time_zone
  from farm_watch.properties p
  where p.slug=p_slug and p.status='active'
  limit 1;

  if v_property_id is null or v_boundary is null or v_point is null then
    return jsonb_build_object('status','missing','property',jsonb_build_object('slug',p_slug));
  end if;
  if v_time_zone is null or not exists(select 1 from pg_timezone_names where name=v_time_zone) then
    return jsonb_build_object(
      'status','unavailable','property',jsonb_build_object('slug',p_slug,'id',v_property_id),
      'reason','property_time_zone_unavailable');
  end if;

  return jsonb_build_object(
    'status','available',
    'property',jsonb_build_object('slug',p_slug,'id',v_property_id),
    'latitude',extensions.st_y(v_point),
    'longitude',extensions.st_x(v_point),
    'time_zone',v_time_zone,
    'boundary_sha256',encode(extensions.digest(extensions.st_asewkb(v_boundary),'sha256'),'hex')
  );
end;
$$;

create or replace function farm_watch.farm_watch_get_snow_winter_severity_v1_internal(
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
  v_boundary_sha text;
  v_time_zone text;
  v_latest farm_watch.property_snow_winter_severity_daily_v1%rowtype;
  v_complete farm_watch.property_snow_winter_severity_daily_v1%rowtype;
  v_month integer;
  v_season_start date;
  v_season_end date;
  v_through date;
  v_expected_days integer := 0;
  v_complete_days integer := 0;
  v_snow_days integer := 0;
  v_temperature_days integer := 0;
  v_points integer := 0;
begin
  if p_slug is null or length(p_slug)>80 or p_slug !~ '^[a-z0-9][a-z0-9-]{0,79}$' then
    raise exception 'invalid Farm Watch property slug';
  end if;
  if p_as_of_date is null then raise exception 'snow/winter as-of date is required'; end if;

  select p.id,p.boundary,nullif(p.metadata->>'time_zone','')
  into v_property_id,v_boundary,v_time_zone
  from farm_watch.properties p
  where p.slug=p_slug and p.status='active'
  limit 1;

  if v_property_id is null or v_boundary is null then
    return jsonb_build_object('status','missing','property',jsonb_build_object('slug',p_slug),'as_of_date',p_as_of_date);
  end if;

  v_boundary_sha := encode(extensions.digest(extensions.st_asewkb(v_boundary),'sha256'),'hex');

  select d.* into v_latest
  from farm_watch.property_snow_winter_severity_daily_v1 d
  where d.property_id=v_property_id and d.observation_date<=p_as_of_date
  order by d.observation_date desc
  limit 1;

  select d.* into v_complete
  from farm_watch.property_snow_winter_severity_daily_v1 d
  where d.property_id=v_property_id
    and d.observation_date<=p_as_of_date
    and d.snow_status='available'
    and d.temperature_status='available'
  order by d.observation_date desc
  limit 1;

  v_month := extract(month from p_as_of_date)::integer;
  if v_month>=11 then
    v_season_start := make_date(extract(year from p_as_of_date)::integer,11,1);
    v_season_end := make_date(extract(year from p_as_of_date)::integer+1,5,31);
  elsif v_month<=5 then
    v_season_start := make_date(extract(year from p_as_of_date)::integer-1,11,1);
    v_season_end := make_date(extract(year from p_as_of_date)::integer,5,31);
  else
    v_season_start := null;
    v_season_end := null;
  end if;

  if v_season_start is not null then
    v_through := least(p_as_of_date-1,v_season_end);
    if v_through>=v_season_start then
      v_expected_days := v_through-v_season_start+1;
      select
        count(*) filter(where d.snow_status='available' and d.temperature_status='available'),
        count(*) filter(where d.snow_status='available' and d.temperature_status='available' and d.snow_depth_cm>=38),
        count(*) filter(where d.snow_status='available' and d.temperature_status='available' and d.minimum_daily_temperature_c<=-17.7),
        coalesce(sum(
          case when d.snow_status='available' and d.temperature_status='available'
            then (case when d.snow_depth_cm>=38 then 1 else 0 end)
               + (case when d.minimum_daily_temperature_c<=-17.7 then 1 else 0 end)
            else 0 end
        ),0)
      into v_complete_days,v_snow_days,v_temperature_days,v_points
      from farm_watch.property_snow_winter_severity_daily_v1 d
      where d.property_id=v_property_id
        and d.observation_date between v_season_start and v_through;
    end if;
  end if;

  return jsonb_build_object(
    'status',case
      when v_latest.property_id is null then 'not_materialized'
      when v_latest.boundary_sha256 is distinct from v_boundary_sha then 'stale'
      else v_latest.status end,
    'schema','snow-winter-severity-context-v1',
    'method','delgiudice-daily-snow-temperature-context-v1',
    'evidence_state','proxy',
    'property',jsonb_build_object('slug',p_slug,'id',v_property_id),
    'as_of_date',p_as_of_date,
    'latest_snow_sample',case when v_latest.property_id is null then null else jsonb_build_object(
      'date',v_latest.observation_date,
      'status',v_latest.snow_status,
      'snow_depth_cm',v_latest.snow_depth_cm,
      'source_valid_at',v_latest.snow_source_valid_at,
      'source_ingested_at',v_latest.snow_source_ingested_at,
      'source_object',v_latest.snow_source_object,
      'retrieved_at',v_latest.retrieved_at
    ) end,
    'latest_complete_daily_context',case when v_complete.property_id is null then null else jsonb_build_object(
      'date',v_complete.observation_date,
      'snow_depth_cm',v_complete.snow_depth_cm,
      'minimum_daily_temperature_c',v_complete.minimum_daily_temperature_c,
      'temperature_hour_count',v_complete.temperature_hour_count,
      'temperature_expected_hours',v_complete.temperature_expected_hours,
      'temperature_coverage_ratio',v_complete.temperature_coverage_ratio,
      'snow_threshold_38cm_met',v_complete.snow_depth_cm>=38,
      'temperature_threshold_minus17_7c_met',v_complete.minimum_daily_temperature_c<=-17.7,
      'minnesota_wsi_daily_points',
        (case when v_complete.snow_depth_cm>=38 then 1 else 0 end)
        +(case when v_complete.minimum_daily_temperature_c<=-17.7 then 1 else 0 end)
    ) end,
    'minnesota_wsi_context',case when v_season_start is null then jsonb_build_object(
      'status','not_applicable',
      'reason','outside_november_through_may_source_wsi_window',
      'thresholds',jsonb_build_object('snow_depth_cm',38,'minimum_temperature_c',-17.7),
      'transfer_boundary','The Minnesota WSI is reproduced only as source provenance/context. No Minnesota severity category or biological threshold is transferred to Kentucky.'
    ) else jsonb_build_object(
      'status',case
        when v_expected_days=0 then 'pending'
        when v_complete_days=v_expected_days then 'complete'
        when v_complete_days>0 then 'partial'
        else 'unavailable' end,
      'season_start',v_season_start,
      'season_end',v_season_end,
      'through_date',v_through,
      'expected_complete_days',v_expected_days,
      'complete_days',v_complete_days,
      'coverage_ratio',case when v_expected_days>0 then round(v_complete_days::numeric/v_expected_days,4) else null end,
      'snow_days_38cm_or_more',v_snow_days,
      'temperature_days_minus17_7c_or_lower',v_temperature_days,
      'known_points',v_points,
      'thresholds',jsonb_build_object('snow_depth_cm',38,'minimum_temperature_c',-17.7),
      'transfer_boundary','The Minnesota WSI is reproduced only as source provenance/context. No Minnesota severity category or biological threshold is transferred to Kentucky.'
    ) end,
    'study_alignment',jsonb_build_object(
      'study','DelGiudice, Fieberg & Sampson 2013, PLOS ONE 8:e65368',
      'direct_model_covariates',jsonb_build_array('daily snow depth (cm)','minimum daily temperature (C)'),
      'study_winter_window','1 November–14 May',
      'wsi_context_window','November–May',
      'coefficient_transfer','not_performed'
    ),
    'source_reconciliation',jsonb_build_object(
      'snow_depth',jsonb_build_object(
        'slug','noaa-nohrsc-national-snow-analysis',
        'authority','NOAA/NWS/NOHRSC',
        'support','operational assimilated national snow analysis; approximately 1 km2 model support',
        'measurement_alignment','source-substituted physical snow-depth estimate'),
      'minimum_daily_temperature',jsonb_build_object(
        'slug','noaa-hrrr-conus-3km',
        'authority','NOAA/NCEP',
        'support','minimum of centrally persisted hourly f00 analyses over the property local calendar day',
        'minimum_required_coverage_ratio',0.75,
        'measurement_alignment','hourly modeled-analysis approximation to minimum daily temperature')
    ),
    'deer_inference_performed',false,
    'coefficient_transfer_performed',false,
    'severity_category_assigned',false,
    'interpretation_boundary',
      'Neutral M08 physical context. Daily snow depth and minimum temperature are source-substituted modeled/assimilated estimates. The Minnesota WSI arithmetic is provenance only; no Kentucky deer response, severity category, dense-cover preference, mortality threshold, or generic cold-weather movement rule is inferred.'
  );
end;
$$;

create or replace function farm_watch.farm_watch_record_snow_winter_severity_sample_v1_internal(
  p_slug text,
  p_sample_date date,
  p_snow_depth_cm numeric,
  p_snow_source_valid_at timestamptz,
  p_snow_source_ingested_at timestamptz,
  p_snow_source_object text,
  p_snow_source_payload_sha256 text,
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
  v_boundary_sha text;
  v_time_zone text;
  v_today date;
  v_row record;
  v_start timestamptz;
  v_end timestamptz;
  v_expected integer;
  v_count integer;
  v_min_temp numeric;
  v_temp_status text;
begin
  if p_slug is null or length(p_slug)>80 or p_slug !~ '^[a-z0-9][a-z0-9-]{0,79}$' then raise exception 'invalid Farm Watch property slug'; end if;
  if p_sample_date is null or p_snow_source_valid_at is null or p_snow_depth_cm is null or p_snow_depth_cm<0 or p_snow_depth_cm>2000 then
    raise exception 'invalid snow sample';
  end if;
  if p_snow_source_payload_sha256 is null or p_snow_source_payload_sha256 !~ '^[0-9a-f]{64}$' then raise exception 'invalid snow source payload hash'; end if;

  select p.id,p.boundary,nullif(p.metadata->>'time_zone','')
  into v_property_id,v_boundary,v_time_zone
  from farm_watch.properties p where p.slug=p_slug and p.status='active' limit 1;
  if v_property_id is null or v_boundary is null or v_time_zone is null then
    return jsonb_build_object('status','missing','property',jsonb_build_object('slug',p_slug));
  end if;
  if not exists(select 1 from pg_timezone_names where name=v_time_zone) then raise exception 'invalid property time zone'; end if;
  if (p_snow_source_valid_at at time zone v_time_zone)::date is distinct from p_sample_date then
    raise exception 'snow source valid time does not match sample local date';
  end if;

  v_boundary_sha := encode(extensions.digest(extensions.st_asewkb(v_boundary),'sha256'),'hex');
  v_today := (now() at time zone v_time_zone)::date;

  insert into farm_watch.property_snow_winter_severity_daily_v1(
    property_id,observation_date,time_zone,status,snow_status,snow_depth_cm,
    snow_source_valid_at,snow_source_ingested_at,snow_source_object,snow_source_payload_sha256,
    temperature_status,boundary_sha256,algorithm_version,output_schema_version,identity_sha256,
    retrieved_at,updated_at
  ) values (
    v_property_id,p_sample_date,v_time_zone,'partial','available',round(p_snow_depth_cm,3),
    p_snow_source_valid_at,p_snow_source_ingested_at,left(coalesce(p_snow_source_object,''),240),p_snow_source_payload_sha256,
    'pending',v_boundary_sha,'delgiudice-daily-snow-temperature-context-v1','snow-winter-severity-context-v1',
    repeat('0',64),coalesce(p_retrieved_at,now()),now()
  )
  on conflict(property_id,observation_date) do update set
    time_zone=excluded.time_zone,
    snow_status='available',
    snow_depth_cm=excluded.snow_depth_cm,
    snow_source_valid_at=excluded.snow_source_valid_at,
    snow_source_ingested_at=excluded.snow_source_ingested_at,
    snow_source_object=excluded.snow_source_object,
    snow_source_payload_sha256=excluded.snow_source_payload_sha256,
    boundary_sha256=excluded.boundary_sha256,
    algorithm_version=excluded.algorithm_version,
    output_schema_version=excluded.output_schema_version,
    retrieved_at=excluded.retrieved_at,
    updated_at=now();

  for v_row in
    select d.observation_date
    from farm_watch.property_snow_winter_severity_daily_v1 d
    where d.property_id=v_property_id
      and d.observation_date<v_today
      and d.temperature_status<>'available'
      and d.observation_date>=v_today-400
    order by d.observation_date
  loop
    v_start := (v_row.observation_date::timestamp at time zone v_time_zone);
    v_end := ((v_row.observation_date+1)::timestamp at time zone v_time_zone);
    v_expected := round(extract(epoch from (v_end-v_start))/3600.0)::integer;

    select count(distinct date_trunc('hour',m.valid_at))::integer,
           min((m.forcing#>>'{fields,air_temperature_2m_c}')::numeric)
    into v_count,v_min_temp
    from farm_watch.property_meteorological_forcing_v1 m
    where m.property_id=v_property_id
      and m.source_state='analysis'
      and m.valid_at>=v_start and m.valid_at<v_end;

    v_temp_status := case
      when coalesce(v_count,0)>=ceil(v_expected*0.75) and v_min_temp is not null then 'available'
      when coalesce(v_count,0)>0 and v_min_temp is not null then 'partial'
      else 'unavailable' end;

    update farm_watch.property_snow_winter_severity_daily_v1 d
    set temperature_status=v_temp_status,
        minimum_daily_temperature_c=case when v_min_temp is null then null else round(v_min_temp,3) end,
        temperature_hour_count=coalesce(v_count,0),
        temperature_expected_hours=v_expected,
        temperature_coverage_ratio=round(coalesce(v_count,0)::numeric/nullif(v_expected,0),4),
        updated_at=now()
    where d.property_id=v_property_id and d.observation_date=v_row.observation_date;
  end loop;

  update farm_watch.property_snow_winter_severity_daily_v1 d
  set status=case
        when d.snow_status='available' and d.temperature_status='available' then 'available'
        when d.snow_status='available' or d.temperature_status in ('pending','partial','available') then 'partial'
        else 'unavailable' end,
      identity_sha256=encode(extensions.digest(convert_to(concat_ws(
        '|',d.property_id::text,d.observation_date::text,d.time_zone,
        coalesce(d.snow_depth_cm::text,''),coalesce(d.snow_source_valid_at::text,''),
        coalesce(d.snow_source_payload_sha256,''),d.temperature_status,
        coalesce(d.minimum_daily_temperature_c::text,''),coalesce(d.temperature_hour_count::text,''),
        coalesce(d.temperature_expected_hours::text,''),d.boundary_sha256,
        d.algorithm_version,d.output_schema_version
      ),'UTF8'),'sha256'),'hex'),
      updated_at=now()
  where d.property_id=v_property_id;

  return farm_watch.farm_watch_get_snow_winter_severity_v1_internal(p_slug,p_sample_date);
end;
$$;

create or replace function farm_watch.farm_watch_refresh_snow_winter_severity_v1_internal(
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

  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS','30000');
  begin
    select * into v_response from extensions.http_post(
      'https://ufpkjaadmmpmeogzhrcq.supabase.co/functions/v1/farm-watch-snow-winter-severity',
      jsonb_build_object('worker_token',v_token,'property',p_slug)::text,'application/json');
  exception when others then
    perform extensions.http_reset_curlopt();
    raise;
  end;
  perform extensions.http_reset_curlopt();

  if v_response.status<200 or v_response.status>=300 then
    raise exception 'Farm Watch snow/winter refresh returned HTTP %: %',v_response.status,left(coalesce(v_response.content,''),500);
  end if;
  begin v_payload := v_response.content::jsonb; exception when others then raise exception 'Farm Watch snow/winter refresh returned non-JSON content'; end;
  if v_payload->>'status' not in ('available','partial') then
    raise exception 'Farm Watch snow/winter refresh failed: %',left(v_response.content,500);
  end if;

  return jsonb_build_object(
    'property',p_slug,
    'http_status',v_response.status,
    'status',v_payload->>'status',
    'sample_date',v_payload#>>'{sample,date}',
    'snow_depth_cm',v_payload#>>'{sample,snow_depth_cm}'
  );
end;
$$;

create or replace function public.farm_watch_get_snow_winter_severity_target_v1_internal(p_slug text)
returns jsonb language sql stable security definer set search_path='pg_catalog'
as $$ select farm_watch.farm_watch_get_snow_winter_severity_target_v1_internal(p_slug); $$;

create or replace function public.farm_watch_record_snow_winter_severity_sample_v1_internal(
  p_slug text,p_sample_date date,p_snow_depth_cm numeric,p_snow_source_valid_at timestamptz,
  p_snow_source_ingested_at timestamptz,p_snow_source_object text,p_snow_source_payload_sha256 text,
  p_retrieved_at timestamptz default now()
)
returns jsonb language sql security definer set search_path='pg_catalog'
as $$ select farm_watch.farm_watch_record_snow_winter_severity_sample_v1_internal(
  p_slug,p_sample_date,p_snow_depth_cm,p_snow_source_valid_at,p_snow_source_ingested_at,
  p_snow_source_object,p_snow_source_payload_sha256,p_retrieved_at); $$;

revoke all on function farm_watch.farm_watch_get_snow_winter_severity_target_v1_internal(text) from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_get_snow_winter_severity_v1_internal(text,date) from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_record_snow_winter_severity_sample_v1_internal(text,date,numeric,timestamptz,timestamptz,text,text,timestamptz) from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_refresh_snow_winter_severity_v1_internal(text) from public,anon,authenticated;
revoke all on function public.farm_watch_get_snow_winter_severity_target_v1_internal(text) from public,anon,authenticated;
revoke all on function public.farm_watch_record_snow_winter_severity_sample_v1_internal(text,date,numeric,timestamptz,timestamptz,text,text,timestamptz) from public,anon,authenticated;

grant execute on function farm_watch.farm_watch_get_snow_winter_severity_target_v1_internal(text) to service_role;
grant execute on function farm_watch.farm_watch_get_snow_winter_severity_v1_internal(text,date) to service_role;
grant execute on function farm_watch.farm_watch_record_snow_winter_severity_sample_v1_internal(text,date,numeric,timestamptz,timestamptz,text,text,timestamptz) to service_role;
grant execute on function farm_watch.farm_watch_refresh_snow_winter_severity_v1_internal(text) to service_role;
grant execute on function public.farm_watch_get_snow_winter_severity_target_v1_internal(text) to service_role;
grant execute on function public.farm_watch_record_snow_winter_severity_sample_v1_internal(text,date,numeric,timestamptz,timestamptz,text,text,timestamptz) to service_role;

CREATE OR REPLACE FUNCTION farm_watch.farm_watch_get_deer_evidence_stack_v1_internal(p_slug text, p_as_of_date date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'farm_watch'
AS $function$
declare
  v_property_id uuid; v_products jsonb; v_surface_water jsonb; v_mast_resource jsonb;
  v_human_footprint jsonb; v_multiscale_cover jsonb; v_multiscale_forest jsonb;
  v_forest_type jsonb; v_snow_winter jsonb; v_extreme_weather jsonb;
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
    'snow_winter_severity_context',v_snow_winter,'extreme_weather_event_context',v_extreme_weather,
    'interpretation_boundary','Neutral Farm Watch evidence inventory for UI review. Availability here does not mean a deer relationship is applicable, a coefficient is transferable, or a deer-use prediction has been made.');
end;
$function$
;

do $$
begin
  if exists(select 1 from cron.job where jobname='farm-watch-snow-winter-severity-daily-v1') then
    perform cron.unschedule('farm-watch-snow-winter-severity-daily-v1');
  end if;
  perform cron.schedule(
    'farm-watch-snow-winter-severity-daily-v1',
    '25 13 * * *',
    $cron$select farm_watch.farm_watch_refresh_snow_winter_severity_v1_internal('validation-property-01');$cron$
  );
end;
$$;

comment on table farm_watch.property_snow_winter_severity_daily_v1 is
'Neutral FW-M08 daily snow-depth and minimum-temperature context. NOAA NOHRSC point snow analysis plus existing HRRR hourly analyses; Minnesota WSI arithmetic retained only as source provenance/context.';
comment on function farm_watch.farm_watch_get_snow_winter_severity_v1_internal(text,date) is
'Reads source-aligned M08 daily physical context and Minnesota WSI arithmetic without assigning a Kentucky severity category or deer response.';
comment on function farm_watch.farm_watch_record_snow_winter_severity_sample_v1_internal(text,date,numeric,timestamptz,timestamptz,text,text,timestamptz) is
'Stores a NOAA NOHRSC snow-depth sample and finalizes prior local-day minimum temperature from centrally persisted HRRR analyses when coverage is sufficient.';

commit;