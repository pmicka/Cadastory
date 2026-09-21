begin;

create table if not exists farm_watch.property_diel_photoperiod_context_v1 (
  property_id uuid not null references farm_watch.properties(id) on delete cascade,
  solar_date date not null,
  status text not null check (status in ('available','unavailable')),
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
  primary key (property_id, solar_date)
);

create index if not exists property_diel_photoperiod_date_idx
  on farm_watch.property_diel_photoperiod_context_v1 (solar_date desc, retrieved_at desc);

alter table farm_watch.property_diel_photoperiod_context_v1 enable row level security;
revoke all on farm_watch.property_diel_photoperiod_context_v1 from public, anon, authenticated;
grant select, insert, update, delete on farm_watch.property_diel_photoperiod_context_v1 to service_role;

create table if not exists farm_watch.deer_regional_breeding_evidence_v1 (
  evidence_id text primary key,
  state_code text not null check (state_code ~ '^[A-Z]{2}$'),
  scope_type text not null check (scope_type in ('statewide_summary','physiographic_region','peer_reviewed_reference')),
  region_code text,
  region_name text,
  breeding_start_month smallint check (breeding_start_month between 1 and 12),
  breeding_end_month smallint check (breeding_end_month between 1 and 12),
  peak_timing_label text,
  exact_peak_start_md text check (exact_peak_start_md is null or exact_peak_start_md ~ '^[0-1][0-9]-[0-3][0-9]$'),
  exact_peak_end_md text check (exact_peak_end_md is null or exact_peak_end_md ~ '^[0-1][0-9]-[0-3][0-9]$'),
  evidence_class text not null,
  source_ids jsonb not null default '[]'::jsonb,
  ledger_ids jsonb not null default '[]'::jsonb,
  source_url text,
  source_year integer,
  status text not null default 'active' check (status in ('active','reference_only','retired')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table farm_watch.deer_regional_breeding_evidence_v1 enable row level security;
revoke all on farm_watch.deer_regional_breeding_evidence_v1 from public, anon, authenticated;
grant select, insert, update, delete on farm_watch.deer_regional_breeding_evidence_v1 to service_role;

insert into ingest.sources (
  slug,name,authority,source_class,geographic_scope,acquisition_method,update_cadence,
  authority_level,status,homepage_url,license_notes,commercial_use_status,notes
)
values
(
  'kdfwr-deer-fetal-breeding-phenology',
  'Kentucky Fish and Wildlife deer fetal breeding phenology',
  'Kentucky Department of Fish and Wildlife Resources',
  'deer_breeding_phenology',
  'Kentucky',
  'Annual biological sampling of road-killed does; fetal development is used to back-calculate prior-fall conception timing and summarize peak breeding by physiographic region',
  'annual / program dependent',
  'state_primary',
  'active_reference',
  'https://fw.ky.gov/',
  'State wildlife-agency biological monitoring; retain year/region provenance when exact annual map values are captured.',
  'public_government',
  'The v1 biological-state contract uses this source as evidence that Kentucky maintains direct fetal-derived breeding phenology. Exact physiographic-region dates are not hard-coded until an authoritative annual map is captured in a source-controlled structured form.'
),
(
  'uky-white-tailed-deer-biology-kentucky',
  'University of Kentucky white-tailed deer biology reference',
  'University of Kentucky Cooperative Extension / Forestry and Natural Resources',
  'regional_species_biology_reference',
  'Kentucky',
  'University extension species-biology summary',
  'reference',
  'state_university_extension',
  'active_reference',
  'https://forestry.mgcafe.uky.edu/deer',
  'Public university-extension educational reference.',
  'public_reference',
  'Documents that Kentucky white-tailed deer breed from October through January and that peak breeding activity usually occurs in mid-November.'
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

insert into farm_watch.deer_regional_breeding_evidence_v1 (
  evidence_id,state_code,scope_type,region_code,region_name,
  breeding_start_month,breeding_end_month,peak_timing_label,
  exact_peak_start_md,exact_peak_end_md,evidence_class,
  source_ids,ledger_ids,source_url,source_year,status,notes
)
values (
  'ky-statewide-qualitative-v1',
  'KY',
  'statewide_summary',
  null,
  'Kentucky statewide qualitative breeding context',
  10,
  1,
  'mid-November',
  null,
  null,
  'authoritative_regional_summary',
  jsonb_build_array(
    'kdfwr-deer-fetal-breeding-phenology',
    'uky-white-tailed-deer-biology-kentucky'
  ),
  jsonb_build_array('FW-D21','FW-D23'),
  'https://forestry.mgcafe.uky.edu/deer',
  2026,
  'active',
  'Kentucky has direct fetal-derived breeding phenology monitoring, but this row intentionally stores only the statewide qualitative summary. The current contract does not infer an individual deer conception/estrus state and does not hard-code annual physiographic-region dates from secondary reproductions.'
)
on conflict (evidence_id) do update set
  state_code=excluded.state_code,
  scope_type=excluded.scope_type,
  region_code=excluded.region_code,
  region_name=excluded.region_name,
  breeding_start_month=excluded.breeding_start_month,
  breeding_end_month=excluded.breeding_end_month,
  peak_timing_label=excluded.peak_timing_label,
  exact_peak_start_md=excluded.exact_peak_start_md,
  exact_peak_end_md=excluded.exact_peak_end_md,
  evidence_class=excluded.evidence_class,
  source_ids=excluded.source_ids,
  ledger_ids=excluded.ledger_ids,
  source_url=excluded.source_url,
  source_year=excluded.source_year,
  status=excluded.status,
  notes=excluded.notes,
  updated_at=now();

create or replace function farm_watch.farm_watch_diel_photoperiod_contract_v1()
returns jsonb
language sql
immutable
security definer
set search_path='pg_catalog'
as $$
  select jsonb_build_object(
    'algorithm_version','farm-watch-diel-photoperiod-v1',
    'output_schema_version','diel-photoperiod-context-v1',
    'evidence_class','deterministic_derived',
    'solar_geometry','NOAA-style geometric solar equations aligned to Farm Watch Solar Exposure v1',
    'sunrise_sunset_altitude_deg',0,
    'civil_twilight_altitude_deg',-6,
    'solar_phase_vocabulary',jsonb_build_array(
      'night','morning_civil_twilight','day','evening_civil_twilight'
    )
  );
$$;

create or replace function farm_watch.farm_watch_solar_position_v1(
  p_at timestamptz,
  p_latitude double precision,
  p_longitude double precision
)
returns jsonb
language plpgsql
immutable
security definer
set search_path='pg_catalog'
as $$
declare
  v_jd double precision;
  v_t double precision;
  v_l0 double precision;
  v_m double precision;
  v_e double precision;
  v_center double precision;
  v_true_long double precision;
  v_omega double precision;
  v_apparent_long double precision;
  v_mean_obliq double precision;
  v_obliq double precision;
  v_declination double precision;
  v_y double precision;
  v_eqtime double precision;
  v_minutes_utc double precision;
  v_true_solar double precision;
  v_hour_angle double precision;
  v_lat_rad double precision;
  v_dec_rad double precision;
  v_ha_rad double precision;
  v_cos_zenith double precision;
  v_elevation double precision;
  v_azimuth double precision;
begin
  if p_at is null or p_latitude is null or p_longitude is null then
    raise exception 'solar-position timestamp and coordinates are required';
  end if;
  if p_latitude < -90 or p_latitude > 90 or p_longitude < -180 or p_longitude > 180 then
    raise exception 'solar-position coordinates are invalid';
  end if;

  v_jd := extract(epoch from p_at) / 86400.0 + 2440587.5;
  v_t := (v_jd - 2451545.0) / 36525.0;
  v_l0 := 280.46646 + v_t * (36000.76983 + v_t * 0.0003032);
  v_l0 := v_l0 - floor(v_l0 / 360.0) * 360.0;
  if v_l0 < 0 then v_l0 := v_l0 + 360.0; end if;

  v_m := 357.52911 + v_t * (35999.05029 - 0.0001537 * v_t);
  v_e := 0.016708634 - v_t * (0.000042037 + 0.0000001267 * v_t);
  v_center :=
      sin(radians(v_m)) * (1.914602 - v_t * (0.004817 + 0.000014 * v_t))
    + sin(radians(2 * v_m)) * (0.019993 - 0.000101 * v_t)
    + sin(radians(3 * v_m)) * 0.000289;
  v_true_long := v_l0 + v_center;
  v_omega := 125.04 - 1934.136 * v_t;
  v_apparent_long := v_true_long - 0.00569 - 0.00478 * sin(radians(v_omega));
  v_mean_obliq :=
    23 + (26 + (21.448 - v_t * (46.815 + v_t * (0.00059 - v_t * 0.001813))) / 60) / 60;
  v_obliq := v_mean_obliq + 0.00256 * cos(radians(v_omega));
  v_declination := degrees(asin(sin(radians(v_obliq)) * sin(radians(v_apparent_long))));
  v_y := power(tan(radians(v_obliq) / 2), 2);
  v_eqtime := 4.0 / (pi() / 180.0) * (
      v_y * sin(2 * radians(v_l0))
    - 2 * v_e * sin(radians(v_m))
    + 4 * v_e * v_y * sin(radians(v_m)) * cos(2 * radians(v_l0))
    - 0.5 * v_y * v_y * sin(4 * radians(v_l0))
    - 1.25 * v_e * v_e * sin(2 * radians(v_m))
  );

  v_minutes_utc :=
      extract(hour from (p_at at time zone 'UTC')) * 60
    + extract(minute from (p_at at time zone 'UTC'))
    + extract(second from (p_at at time zone 'UTC')) / 60.0;
  v_true_solar := v_minutes_utc + v_eqtime + 4 * p_longitude;
  v_true_solar := v_true_solar - floor(v_true_solar / 1440.0) * 1440.0;
  if v_true_solar < 0 then v_true_solar := v_true_solar + 1440.0; end if;

  v_hour_angle := v_true_solar / 4.0 - 180.0;
  if v_hour_angle < -180 then v_hour_angle := v_hour_angle + 360.0; end if;

  v_lat_rad := radians(p_latitude);
  v_dec_rad := radians(v_declination);
  v_ha_rad := radians(v_hour_angle);
  v_cos_zenith := greatest(
    -1.0,
    least(
      1.0,
      sin(v_lat_rad) * sin(v_dec_rad)
      + cos(v_lat_rad) * cos(v_dec_rad) * cos(v_ha_rad)
    )
  );
  v_elevation := 90.0 - degrees(acos(v_cos_zenith));
  v_azimuth := degrees(atan2(
    sin(v_ha_rad),
    cos(v_ha_rad) * sin(v_lat_rad) - tan(v_dec_rad) * cos(v_lat_rad)
  )) + 180.0;
  v_azimuth := v_azimuth - floor(v_azimuth / 360.0) * 360.0;
  if v_azimuth < 0 then v_azimuth := v_azimuth + 360.0; end if;

  return jsonb_build_object(
    'elevation_deg',v_elevation,
    'azimuth_deg',v_azimuth,
    'declination_deg',v_declination,
    'equation_of_time_min',v_eqtime,
    'hour_angle_deg',v_hour_angle
  );
end;
$$;

create or replace function farm_watch.farm_watch_solar_events_v1(
  p_solar_date date,
  p_latitude double precision,
  p_longitude double precision
)
returns jsonb
language plpgsql
immutable
security definer
set search_path='pg_catalog'
as $$
declare
  v_noon_pos jsonb;
  v_declination double precision;
  v_eqtime double precision;
  v_lat_rad double precision;
  v_dec_rad double precision;
  v_cos_hour double precision;
  v_cos_civil double precision;
  v_hour_angle double precision;
  v_civil_hour_angle double precision;
  v_solar_noon_min double precision;
  v_sunrise_min double precision;
  v_sunset_min double precision;
  v_civil_dawn_min double precision;
  v_civil_dusk_min double precision;
  v_base timestamptz;
begin
  if p_solar_date is null then raise exception 'solar date is required'; end if;

  v_noon_pos := farm_watch.farm_watch_solar_position_v1(
    (p_solar_date::timestamp + interval '12 hours') at time zone 'UTC',
    p_latitude,
    p_longitude
  );
  v_declination := (v_noon_pos->>'declination_deg')::double precision;
  v_eqtime := (v_noon_pos->>'equation_of_time_min')::double precision;
  v_lat_rad := radians(p_latitude);
  v_dec_rad := radians(v_declination);
  v_solar_noon_min := 720.0 - 4.0 * p_longitude - v_eqtime;

  v_cos_hour := -tan(v_lat_rad) * tan(v_dec_rad);
  if v_cos_hour >= 1 then
    v_sunrise_min := 720.0;
    v_sunset_min := 720.0;
  elsif v_cos_hour <= -1 then
    v_sunrise_min := 0.0;
    v_sunset_min := 1440.0;
  else
    v_hour_angle := degrees(acos(v_cos_hour));
    v_sunrise_min := v_solar_noon_min - 4.0 * v_hour_angle;
    v_sunset_min := v_solar_noon_min + 4.0 * v_hour_angle;
  end if;

  v_cos_civil := (
    cos(radians(96.0)) - sin(v_lat_rad) * sin(v_dec_rad)
  ) / nullif(cos(v_lat_rad) * cos(v_dec_rad),0);
  if v_cos_civil >= 1 then
    v_civil_dawn_min := v_sunrise_min;
    v_civil_dusk_min := v_sunset_min;
  elsif v_cos_civil <= -1 then
    v_civil_dawn_min := 0.0;
    v_civil_dusk_min := 1440.0;
  else
    v_civil_hour_angle := degrees(acos(v_cos_civil));
    v_civil_dawn_min := v_solar_noon_min - 4.0 * v_civil_hour_angle;
    v_civil_dusk_min := v_solar_noon_min + 4.0 * v_civil_hour_angle;
  end if;

  v_base := p_solar_date::timestamp at time zone 'UTC';

  return jsonb_build_object(
    'civil_dawn',v_base + make_interval(secs => v_civil_dawn_min * 60.0),
    'sunrise',v_base + make_interval(secs => v_sunrise_min * 60.0),
    'solar_noon',v_base + make_interval(secs => v_solar_noon_min * 60.0),
    'sunset',v_base + make_interval(secs => v_sunset_min * 60.0),
    'civil_dusk',v_base + make_interval(secs => v_civil_dusk_min * 60.0),
    'daylight_minutes',greatest(0.0,v_sunset_min-v_sunrise_min),
    'civil_light_minutes',greatest(0.0,v_civil_dusk_min-v_civil_dawn_min),
    'civil_twilight_altitude_deg',-6,
    'sunrise_sunset_altitude_deg',0
  );
end;
$$;

create or replace function farm_watch.farm_watch_resolve_diel_photoperiod_v1_internal(
  p_slug text,
  p_solar_date date default current_date
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
  v_latitude double precision;
  v_longitude double precision;
  v_boundary_sha256 text;
  v_contract jsonb;
  v_events jsonb;
  v_source_signature text;
  v_source_signature_sha256 text;
  v_identity_sha256 text;
  v_context jsonb;
begin
  if p_slug is null or p_slug !~ '^[a-z0-9][a-z0-9-]{0,79}$' then
    raise exception 'invalid Farm Watch property slug';
  end if;
  if p_solar_date is null then raise exception 'solar date is required'; end if;

  select p.id,coalesce(p.center,extensions.st_pointonsurface(p.boundary)),p.boundary
  into v_property_id,v_center,v_boundary
  from farm_watch.properties p
  where p.slug=p_slug and p.status='active'
  limit 1;

  if v_property_id is null or v_center is null or v_boundary is null then
    return jsonb_build_object(
      'status','missing',
      'property',jsonb_build_object('slug',p_slug),
      'solar_date',p_solar_date,
      'context',null
    );
  end if;

  if extensions.st_srid(v_center) <> 4326 then
    v_center := extensions.st_transform(v_center,4326);
  end if;
  v_longitude := extensions.st_x(v_center);
  v_latitude := extensions.st_y(v_center);
  v_boundary_sha256 := encode(
    extensions.digest(extensions.st_asewkb(v_boundary),'sha256'),
    'hex'
  );
  v_contract := farm_watch.farm_watch_diel_photoperiod_contract_v1();
  v_events := farm_watch.farm_watch_solar_events_v1(
    p_solar_date,v_latitude,v_longitude
  );

  v_source_signature := concat_ws(
    '|',
    'product=diel-photoperiod-context',
    'solar_date=' || p_solar_date::text,
    'latitude=' || round(v_latitude::numeric,8)::text,
    'longitude=' || round(v_longitude::numeric,8)::text,
    'solar_geometry=noaa-style-geometric-v1',
    'civil_twilight_altitude_deg=-6'
  );
  v_source_signature_sha256 := encode(
    extensions.digest(convert_to(v_source_signature,'UTF8'),'sha256'),'hex'
  );
  v_identity_sha256 := encode(
    extensions.digest(
      convert_to(
        concat_ws(
          '|',
          v_property_id::text,
          p_solar_date::text,
          v_contract->>'algorithm_version',
          v_contract->>'output_schema_version',
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
    'schema',v_contract->>'output_schema_version',
    'method',v_contract->>'algorithm_version',
    'solar_date',p_solar_date,
    'evidence_class',v_contract->>'evidence_class',
    'anchor',jsonb_build_object(
      'latitude',v_latitude,
      'longitude',v_longitude,
      'basis','Farm Watch property center or point-on-surface'
    ),
    'events',v_events,
    'solar_phase_vocabulary',v_contract->'solar_phase_vocabulary',
    'scoring_performed',false,
    'behavioral_inference_performed',false,
    'interpretation_boundary','Deterministic solar timing only. Civil twilight is a neutral light-transition proxy and is not itself a measured deer activity period.'
  );

  return jsonb_build_object(
    'status','available',
    'property',jsonb_build_object('slug',p_slug,'id',v_property_id),
    'solar_date',p_solar_date,
    'context',v_context,
    'identity',jsonb_build_object(
      'boundary_sha256',v_boundary_sha256,
      'source_signature',v_source_signature,
      'source_signature_sha256',v_source_signature_sha256,
      'algorithm_version',v_contract->>'algorithm_version',
      'output_schema_version',v_contract->>'output_schema_version',
      'identity_sha256',v_identity_sha256
    )
  );
end;
$$;

create or replace function farm_watch.farm_watch_refresh_diel_photoperiod_v1_internal(
  p_slug text,
  p_solar_date date default current_date
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
  v_resolved := farm_watch.farm_watch_resolve_diel_photoperiod_v1_internal(
    p_slug,p_solar_date
  );
  if v_resolved->>'status'='missing' then return v_resolved; end if;
  v_property_id := (v_resolved->'property'->>'id')::uuid;

  insert into farm_watch.property_diel_photoperiod_context_v1(
    property_id,solar_date,status,context,boundary_sha256,
    source_signature,source_signature_sha256,algorithm_version,
    output_schema_version,identity_sha256,retrieved_at,updated_at
  ) values (
    v_property_id,p_solar_date,'available',v_resolved->'context',
    v_resolved->'identity'->>'boundary_sha256',
    v_resolved->'identity'->>'source_signature',
    v_resolved->'identity'->>'source_signature_sha256',
    v_resolved->'identity'->>'algorithm_version',
    v_resolved->'identity'->>'output_schema_version',
    v_resolved->'identity'->>'identity_sha256',
    now(),now()
  )
  on conflict(property_id,solar_date) do update set
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

  return farm_watch.farm_watch_get_diel_photoperiod_v1_internal(p_slug,p_solar_date);
end;
$$;

create or replace function farm_watch.farm_watch_get_diel_photoperiod_v1_internal(
  p_slug text,
  p_solar_date date default current_date
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
  v_row farm_watch.property_diel_photoperiod_context_v1%rowtype;
begin
  select p.id,p.boundary
  into v_property_id,v_boundary
  from farm_watch.properties p
  where p.slug=p_slug and p.status='active'
  limit 1;

  if v_property_id is null or v_boundary is null then
    return jsonb_build_object(
      'status','missing','property',jsonb_build_object('slug',p_slug),
      'solar_date',p_solar_date,'context',null
    );
  end if;

  select * into v_row
  from farm_watch.property_diel_photoperiod_context_v1 d
  where d.property_id=v_property_id and d.solar_date=p_solar_date
  limit 1;

  if not found then
    return jsonb_build_object(
      'status','missing','property',jsonb_build_object('slug',p_slug,'id',v_property_id),
      'solar_date',p_solar_date,'context',null
    );
  end if;

  v_boundary_sha256 := encode(
    extensions.digest(extensions.st_asewkb(v_boundary),'sha256'),'hex'
  );
  v_contract := farm_watch.farm_watch_diel_photoperiod_contract_v1();

  if v_row.boundary_sha256 is distinct from v_boundary_sha256 then
    return jsonb_build_object(
      'status','stale','property',jsonb_build_object('slug',p_slug,'id',v_property_id),
      'solar_date',p_solar_date,'context',null,
      'invalidation_reason','property_boundary_changed',
      'stored_identity_sha256',v_row.identity_sha256
    );
  end if;

  if v_row.algorithm_version is distinct from (v_contract->>'algorithm_version')
     or v_row.output_schema_version is distinct from (v_contract->>'output_schema_version') then
    return jsonb_build_object(
      'status','stale','property',jsonb_build_object('slug',p_slug,'id',v_property_id),
      'solar_date',p_solar_date,'context',null,
      'invalidation_reason','diel_photoperiod_contract_changed',
      'stored_identity_sha256',v_row.identity_sha256
    );
  end if;

  return jsonb_build_object(
    'status',v_row.status,
    'property',jsonb_build_object('slug',p_slug,'id',v_property_id),
    'solar_date',v_row.solar_date,
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

create or replace function farm_watch.farm_watch_resolve_diel_state_v1_internal(
  p_slug text,
  p_at timestamptz
)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','farm_watch'
as $$
declare
  v_date date;
  v_day jsonb;
  v_context jsonb;
  v_position jsonb;
  v_elevation double precision;
  v_hour_angle double precision;
  v_phase text;
begin
  if p_at is null then raise exception 'diel timestamp is required'; end if;
  v_date := (p_at at time zone 'UTC')::date;
  v_day := farm_watch.farm_watch_resolve_diel_photoperiod_v1_internal(p_slug,v_date);
  if v_day->>'status' <> 'available' then return v_day; end if;
  v_context := v_day->'context';
  v_position := farm_watch.farm_watch_solar_position_v1(
    p_at,
    (v_context->'anchor'->>'latitude')::double precision,
    (v_context->'anchor'->>'longitude')::double precision
  );
  v_elevation := (v_position->>'elevation_deg')::double precision;
  v_hour_angle := (v_position->>'hour_angle_deg')::double precision;

  v_phase := case
    when v_elevation >= 0 then 'day'
    when v_elevation >= -6 and v_hour_angle < 0 then 'morning_civil_twilight'
    when v_elevation >= -6 then 'evening_civil_twilight'
    else 'night'
  end;

  return jsonb_build_object(
    'status','available',
    'property',v_day->'property',
    'at',p_at,
    'solar_date',v_date,
    'context',v_context,
    'identity',v_day->'identity',
    'diel',jsonb_build_object(
      'solar_phase',v_phase,
      'solar_elevation_deg',v_elevation,
      'solar_azimuth_deg',(v_position->>'azimuth_deg')::double precision,
      'hour_angle_deg',v_hour_angle,
      'civil_twilight_is_activity_proxy',false
    )
  );
end;
$$;

create or replace function farm_watch.farm_watch_deer_biological_state_contract_v1()
returns jsonb
language sql
immutable
security definer
set search_path='pg_catalog'
as $$
  select jsonb_build_object(
    'algorithm_version','farm-watch-deer-biological-state-v1',
    'output_schema_version','deer-biological-state-v1',
    'species','Odocoileus virginianus',
    'sex_vocabulary',jsonb_build_array('male','female','unknown'),
    'age_vocabulary',jsonb_build_array('juvenile','yearling','adult','unknown'),
    'movement_vocabulary',jsonb_build_array('resident','dispersal','unknown'),
    'individual_reproductive_vocabulary',jsonb_build_array(
      'unknown','nonbreeding','estrus','pregnant','parturition','lactation'
    ),
    'regional_breeding_vocabulary',jsonb_build_array(
      'outside_documented_breeding_season',
      'within_documented_breeding_season',
      'within_peak_month_context',
      'unavailable'
    ),
    'relationship_ids',jsonb_build_array('FW-D05','FW-D06','FW-D21','FW-D22','FW-D23')
  );
$$;

create or replace function farm_watch.farm_watch_resolve_deer_biological_state_v1_internal(
  p_slug text,
  p_at timestamptz,
  p_sex text default 'unknown',
  p_age_class text default 'unknown',
  p_movement_state text default 'unknown',
  p_individual_reproductive_state text default 'unknown'
)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','farm_watch'
as $$
declare
  v_property_id uuid;
  v_state_code text;
  v_diel jsonb;
  v_evidence farm_watch.deer_regional_breeding_evidence_v1%rowtype;
  v_month integer;
  v_within boolean := false;
  v_regional_phase text := 'unavailable';
  v_season text;
  v_age_timing text := 'not_resolved';
  v_ids text[] := array['FW-D05'];
begin
  if p_at is null then raise exception 'deer biological-state timestamp is required'; end if;
  if p_sex not in ('male','female','unknown') then raise exception 'invalid deer sex'; end if;
  if p_age_class not in ('juvenile','yearling','adult','unknown') then raise exception 'invalid deer age class'; end if;
  if p_movement_state not in ('resident','dispersal','unknown') then raise exception 'invalid deer movement state'; end if;
  if p_individual_reproductive_state not in (
    'unknown','nonbreeding','estrus','pregnant','parturition','lactation'
  ) then raise exception 'invalid individual reproductive state'; end if;

  select p.id,p.state_code
  into v_property_id,v_state_code
  from farm_watch.properties p
  where p.slug=p_slug and p.status='active'
  limit 1;

  if v_property_id is null then
    return jsonb_build_object(
      'status','missing',
      'property',jsonb_build_object('slug',p_slug),
      'context',null
    );
  end if;

  v_diel := farm_watch.farm_watch_resolve_diel_state_v1_internal(p_slug,p_at);
  if v_diel->>'status' <> 'available' then
    return jsonb_build_object(
      'status','unavailable',
      'property',v_diel->'property',
      'at',p_at,
      'context',null,
      'reason','diel_context_unavailable'
    );
  end if;

  select *
  into v_evidence
  from farm_watch.deer_regional_breeding_evidence_v1 e
  where e.state_code=v_state_code
    and e.scope_type='statewide_summary'
    and e.status='active'
  order by e.source_year desc nulls last,e.updated_at desc
  limit 1;

  v_month := extract(month from (p_at at time zone 'UTC'))::integer;
  if found and v_evidence.breeding_start_month is not null and v_evidence.breeding_end_month is not null then
    if v_evidence.breeding_start_month <= v_evidence.breeding_end_month then
      v_within := v_month between v_evidence.breeding_start_month and v_evidence.breeding_end_month;
    else
      v_within := v_month >= v_evidence.breeding_start_month
        or v_month <= v_evidence.breeding_end_month;
    end if;
    if not v_within then
      v_regional_phase := 'outside_documented_breeding_season';
    elsif v_month=11 and lower(coalesce(v_evidence.peak_timing_label,'')) like '%mid-november%' then
      v_regional_phase := 'within_peak_month_context';
    else
      v_regional_phase := 'within_documented_breeding_season';
    end if;
  end if;

  v_season := case
    when v_month in (12,1,2) then 'winter'
    when v_month in (3,4,5) then 'spring'
    when v_month in (6,7,8) then 'summer'
    else 'fall'
  end;

  if v_state_code='KY' then
    v_ids := array_append(v_ids,'FW-D21');
    v_ids := array_append(v_ids,'FW-D23');
  end if;

  if p_sex='female' and p_age_class <> 'unknown' then
    v_ids := array_append(v_ids,'FW-D22');
    v_age_timing := case
      when p_age_class='juvenile'
        then 'illinois_reference_supports_later_conception_than_yearling_adult'
      else 'illinois_reference_supports_earlier_conception_than_fawn'
    end;
  end if;

  if p_sex='male'
     and p_age_class <> 'unknown'
     and v_regional_phase in ('within_documented_breeding_season','within_peak_month_context') then
    v_ids := array_append(v_ids,'FW-D06');
  end if;

  return jsonb_build_object(
    'status','available',
    'property',jsonb_build_object('slug',p_slug,'id',v_property_id,'state_code',v_state_code),
    'context',jsonb_build_object(
      'schema','deer-biological-state-v1',
      'method','farm-watch-deer-biological-state-v1',
      'species','Odocoileus virginianus',
      'at',p_at,
      'sex',p_sex,
      'age_class',p_age_class,
      'movement_state',p_movement_state,
      'individual_reproductive_state',p_individual_reproductive_state,
      'season',v_season,
      'diel',v_diel->'diel',
      'regional_reproductive_context',jsonb_build_object(
        'phase',v_regional_phase,
        'scope',case when found then v_evidence.evidence_id else 'unavailable' end,
        'peak_timing_label',case when found then v_evidence.peak_timing_label else null end,
        'evidence_class',case when found then v_evidence.evidence_class else null end,
        'source_ids',case when found then v_evidence.source_ids else '[]'::jsonb end,
        'ledger_ids',case when found then v_evidence.ledger_ids else '[]'::jsonb end,
        'individual_state_inferred',false,
        'interpretation_boundary','Regional breeding phenology is population context only and does not establish estrus, conception, mating, pregnancy, or rut movement for an individual deer.'
      ),
      'age_timing_context',jsonb_build_object(
        'state',v_age_timing,
        'coefficient_transfer_authorized',false,
        'source_relationship_id',case
          when p_sex='female' and p_age_class <> 'unknown' then 'FW-D22'
          else null
        end
      ),
      'applicable_relationship_ids',to_jsonb(
        (select array_agg(distinct id order by id) from unnest(v_ids) as id)
      ),
      'state_provenance',jsonb_build_object(
        'sex',case when p_sex='unknown' then 'unknown' else 'explicit_scenario_input' end,
        'age_class',case when p_age_class='unknown' then 'unknown' else 'explicit_scenario_input' end,
        'movement_state',case when p_movement_state='unknown' then 'unknown' else 'explicit_scenario_input' end,
        'individual_reproductive_state',case
          when p_individual_reproductive_state='unknown' then 'unknown'
          else 'explicit_scenario_input'
        end,
        'diel','deterministic_solar_context',
        'regional_reproductive_context',case
          when v_regional_phase='unavailable' then 'unavailable'
          else 'regional_evidence'
        end
      ),
      'confidence',jsonb_build_object(
        'diel','deterministic',
        'regional_reproductive_context',case
          when v_regional_phase='unavailable' then 'unavailable'
          else 'regional_summary'
        end,
        'individual_reproductive_state',case
          when p_individual_reproductive_state='unknown' then 'unknown'
          else 'scenario_declared'
        end
      ),
      'scoring_performed',false,
      'behavioral_inference_performed',false,
      'interpretation_boundary','Explicit deer biological scenario and regional timing context only. Unknown individual states remain unknown; no deer-use, movement-rate, habitat-quality, bedding, travel, or management score is produced.'
    )
  );
end;
$$;

revoke all on function farm_watch.farm_watch_diel_photoperiod_contract_v1() from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_solar_position_v1(timestamptz,double precision,double precision) from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_solar_events_v1(date,double precision,double precision) from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_resolve_diel_photoperiod_v1_internal(text,date) from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_refresh_diel_photoperiod_v1_internal(text,date) from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_get_diel_photoperiod_v1_internal(text,date) from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_resolve_diel_state_v1_internal(text,timestamptz) from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_deer_biological_state_contract_v1() from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_resolve_deer_biological_state_v1_internal(text,timestamptz,text,text,text,text) from public,anon,authenticated;

grant execute on function farm_watch.farm_watch_diel_photoperiod_contract_v1() to postgres,service_role;
grant execute on function farm_watch.farm_watch_solar_position_v1(timestamptz,double precision,double precision) to postgres,service_role;
grant execute on function farm_watch.farm_watch_solar_events_v1(date,double precision,double precision) to postgres,service_role;
grant execute on function farm_watch.farm_watch_resolve_diel_photoperiod_v1_internal(text,date) to service_role;
grant execute on function farm_watch.farm_watch_refresh_diel_photoperiod_v1_internal(text,date) to service_role;
grant execute on function farm_watch.farm_watch_get_diel_photoperiod_v1_internal(text,date) to service_role;
grant execute on function farm_watch.farm_watch_resolve_diel_state_v1_internal(text,timestamptz) to service_role;
grant execute on function farm_watch.farm_watch_deer_biological_state_contract_v1() to postgres,service_role;
grant execute on function farm_watch.farm_watch_resolve_deer_biological_state_v1_internal(text,timestamptz,text,text,text,text) to service_role;

create or replace function public.farm_watch_refresh_diel_photoperiod_v1_internal(
  p_slug text,
  p_solar_date date default current_date
)
returns jsonb
language sql
security definer
set search_path='pg_catalog'
as $$
  select farm_watch.farm_watch_refresh_diel_photoperiod_v1_internal(p_slug,p_solar_date);
$$;

create or replace function public.farm_watch_get_diel_photoperiod_v1_internal(
  p_slug text,
  p_solar_date date default current_date
)
returns jsonb
language sql
stable
security definer
set search_path='pg_catalog'
as $$
  select farm_watch.farm_watch_get_diel_photoperiod_v1_internal(p_slug,p_solar_date);
$$;

create or replace function public.farm_watch_resolve_deer_biological_state_v1_internal(
  p_slug text,
  p_at timestamptz,
  p_sex text default 'unknown',
  p_age_class text default 'unknown',
  p_movement_state text default 'unknown',
  p_individual_reproductive_state text default 'unknown'
)
returns jsonb
language sql
stable
security definer
set search_path='pg_catalog'
as $$
  select farm_watch.farm_watch_resolve_deer_biological_state_v1_internal(
    p_slug,p_at,p_sex,p_age_class,p_movement_state,p_individual_reproductive_state
  );
$$;

revoke all on function public.farm_watch_refresh_diel_photoperiod_v1_internal(text,date)
  from public,anon,authenticated;
revoke all on function public.farm_watch_get_diel_photoperiod_v1_internal(text,date)
  from public,anon,authenticated;
revoke all on function public.farm_watch_resolve_deer_biological_state_v1_internal(text,timestamptz,text,text,text,text)
  from public,anon,authenticated;

grant execute on function public.farm_watch_refresh_diel_photoperiod_v1_internal(text,date)
  to service_role;
grant execute on function public.farm_watch_get_diel_photoperiod_v1_internal(text,date)
  to service_role;
grant execute on function public.farm_watch_resolve_deer_biological_state_v1_internal(text,timestamptz,text,text,text,text)
  to service_role;

comment on table farm_watch.property_diel_photoperiod_context_v1 is
'Date-keyed deterministic Farm Watch solar timing context. Civil twilight and daylight are physical light-state boundaries only and are not deer activity labels.';

comment on table farm_watch.deer_regional_breeding_evidence_v1 is
'Regional/state breeding-phenology evidence for explicit deer biological-state context. Regional population timing must never be promoted to an individual reproductive state.';

comment on function farm_watch.farm_watch_resolve_deer_biological_state_v1_internal(text,timestamptz,text,text,text,text) is
'Builds an explicit white-tailed-deer scenario object from deterministic diel context, regional breeding evidence, and caller-supplied sex/age/movement/individual reproductive state. No deer-use or management scoring is performed.';

commit;
