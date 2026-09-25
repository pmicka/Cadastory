begin;

create table if not exists farm_watch.property_human_footprint_context_v1 (
  property_id uuid primary key references farm_watch.properties(id) on delete cascade,
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
  updated_at timestamptz not null default now()
);

create table if not exists farm_watch.property_study_scale_windows_v1 (
  property_id uuid not null references farm_watch.properties(id) on delete cascade,
  scale_key text not null check (scale_key in ('nagy_reis_1km2','nagy_reis_9km2')),
  area_km2 numeric not null check (area_km2 in (1,9)),
  side_m numeric not null check (side_m > 0),
  geometry extensions.geometry(Polygon,4326) not null,
  geometry_basis text not null,
  projected_crs text not null,
  source_study text not null,
  boundary_sha256 text not null check (boundary_sha256 ~ '^[0-9a-f]{64}$'),
  identity_sha256 text not null check (identity_sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(property_id,scale_key)
);

create table if not exists farm_watch.property_extreme_weather_event_context_v1 (
  property_id uuid primary key references farm_watch.properties(id) on delete cascade,
  as_of_at timestamptz not null,
  status text not null check (status in ('available','inactive','unavailable')),
  context jsonb not null default '{}'::jsonb,
  boundary_sha256 text not null check (boundary_sha256 ~ '^[0-9a-f]{64}$'),
  source_signature text not null,
  source_signature_sha256 text not null check (source_signature_sha256 ~ '^[0-9a-f]{64}$'),
  algorithm_version text not null,
  output_schema_version text not null,
  identity_sha256 text not null check (identity_sha256 ~ '^[0-9a-f]{64}$'),
  retrieved_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table farm_watch.property_human_footprint_context_v1 enable row level security;
alter table farm_watch.property_study_scale_windows_v1 enable row level security;
alter table farm_watch.property_extreme_weather_event_context_v1 enable row level security;

revoke all on farm_watch.property_human_footprint_context_v1 from public,anon,authenticated;
revoke all on farm_watch.property_study_scale_windows_v1 from public,anon,authenticated;
revoke all on farm_watch.property_extreme_weather_event_context_v1 from public,anon,authenticated;

grant select,insert,update,delete on farm_watch.property_human_footprint_context_v1 to service_role;
grant select,insert,update,delete on farm_watch.property_study_scale_windows_v1 to service_role;
grant select,insert,update,delete on farm_watch.property_extreme_weather_event_context_v1 to service_role;

create or replace function farm_watch.farm_watch_deer_tier1_context_contract_v1()
returns jsonb
language sql
immutable
security definer
set search_path='pg_catalog'
as $$
  select jsonb_build_object(
    'human_footprint',jsonb_build_object(
      'algorithm_version','ky-ornl-osm-human-footprint-context-v1',
      'output_schema_version','human-footprint-context-v1',
      'building_study_area_km2',10.36,
      'building_source','Kentucky ORNL / FEMA USA Structures Building Footprints',
      'road_source','OpenStreetMap Geofabrik Access Snapshot',
      'road_study_sampling_radii_m',jsonb_build_array(30,90,270)
    ),
    'multiscale_cover',jsonb_build_object(
      'algorithm_version','nagy-reis-property-centered-grid-scales-v1',
      'output_schema_version','multiscale-cover-context-v1',
      'source_study_areas_km2',jsonb_build_array(1,9),
      'projected_crs','EPSG:32616'
    ),
    'extreme_weather',jsonb_build_object(
      'algorithm_version','nws-tropical-extreme-event-gate-v1',
      'output_schema_version','extreme-weather-event-context-v1',
      'source','NOAA National Weather Service Alerts API',
      'qualifying_event_types',jsonb_build_array(
        'Hurricane Warning','Hurricane Watch',
        'Tropical Storm Warning','Tropical Storm Watch',
        'Storm Surge Warning','Storm Surge Watch',
        'Extreme Wind Warning'
      )
    )
  );
$$;

create or replace function farm_watch.farm_watch_get_human_footprint_query_v1_internal(
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
  v_state_code text;
  v_center_utm extensions.geometry;
  v_side double precision := sqrt(10.36 * 1000000.0);
  v_half double precision;
  v_window extensions.geometry;
begin
  select p.id,p.center,p.state_code
  into v_property_id,v_center,v_state_code
  from farm_watch.properties p
  where p.slug=p_slug and p.status='active'
  limit 1;

  if v_property_id is null or v_center is null then
    return jsonb_build_object('status','missing','property',jsonb_build_object('slug',p_slug));
  end if;
  if v_state_code <> 'KY' then
    return jsonb_build_object(
      'status','unsupported_state',
      'property',jsonb_build_object('slug',p_slug,'id',v_property_id),
      'state_code',v_state_code
    );
  end if;

  v_center_utm := extensions.st_transform(v_center,32616);
  v_half := v_side / 2.0;
  v_window := extensions.st_makeenvelope(
    extensions.st_x(v_center_utm)-v_half,
    extensions.st_y(v_center_utm)-v_half,
    extensions.st_x(v_center_utm)+v_half,
    extensions.st_y(v_center_utm)+v_half,
    32616
  );

  return jsonb_build_object(
    'status','available',
    'property',jsonb_build_object('slug',p_slug,'id',v_property_id,'state_code',v_state_code),
    'building_query',jsonb_build_object(
      'area_km2',10.36,
      'side_m',v_side,
      'geometry_type','esriGeometryEnvelope',
      'in_sr',32616,
      'envelope',jsonb_build_array(
        extensions.st_x(v_center_utm)-v_half,
        extensions.st_y(v_center_utm)-v_half,
        extensions.st_x(v_center_utm)+v_half,
        extensions.st_y(v_center_utm)+v_half
      ),
      'source_url',
        'https://kygisserver.ky.gov/arcgis/rest/services/WGS84WM_Services/Ky_ORNL_Building_Footprints_WGS84WM/MapServer/0'
    )
  );
end;
$$;

create or replace function farm_watch.farm_watch_record_human_footprint_context_v1_internal(
  p_slug text,
  p_building_count integer,
  p_building_metadata_sha256 text,
  p_building_checked_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','farm_watch','extensions','decisioning','ingest'
as $$
declare
  v_property_id uuid;
  v_boundary extensions.geometry;
  v_center extensions.geometry;
  v_state_code text;
  v_domains farm_watch.property_landscape_domains_v1%rowtype;
  v_boundary_sha256 text;
  v_road_source_id uuid;
  v_road_source_timestamp timestamptz;
  v_local jsonb;
  v_landscape jsonb;
  v_broad jsonb;
  v_nearest_road_m numeric;
  v_source_fingerprint jsonb;
  v_source_fingerprint_sha256 text;
  v_source_signature text;
  v_source_signature_sha256 text;
  v_identity_sha256 text;
  v_context jsonb;
  v_status text;
begin
  if p_building_count is null or p_building_count < 0 then
    raise exception 'invalid building count';
  end if;
  if p_building_metadata_sha256 is null or p_building_metadata_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid building metadata hash';
  end if;

  select p.id,p.boundary,p.center,p.state_code
  into v_property_id,v_boundary,v_center,v_state_code
  from farm_watch.properties p
  where p.slug=p_slug and p.status='active'
  limit 1;

  if v_property_id is null or v_boundary is null or v_center is null then
    return jsonb_build_object('status','missing','property',jsonb_build_object('slug',p_slug));
  end if;

  select * into v_domains
  from farm_watch.property_landscape_domains_v1 d
  where d.property_id=v_property_id and d.status='available'
  limit 1;

  select s.id into v_road_source_id
  from ingest.sources s
  where s.slug='openstreetmap-geofabrik-access-snapshot'
  limit 1;

  select r.current_source_timestamp
  into v_road_source_timestamp
  from decisioning.site_access_snapshot_regions r
  where r.state_code=v_state_code and r.status='ready'
  order by r.current_source_timestamp desc nulls last
  limit 1;

  v_boundary_sha256 := encode(
    extensions.digest(extensions.st_asewkb(v_boundary),'sha256'),'hex'
  );

  select jsonb_build_object(
    'road_feature_count',count(distinct f.id),
    'road_length_m',round(coalesce(sum(
      extensions.st_length(
        extensions.st_intersection(
          extensions.st_transform(f.geometry,32616),
          extensions.st_transform(v_domains.local_500m,32616)
        )
      )
    ),0)::numeric,1),
    'domain_area_km2',round((extensions.st_area(v_domains.local_500m::geography)/1000000.0)::numeric,6)
  )
  into v_local
  from decisioning.site_access_features f
  where f.source_id=v_road_source_id
    and f.feature_class='road'
    and v_domains.local_500m is not null
    and extensions.st_intersects(f.geometry,v_domains.local_500m);

  select jsonb_build_object(
    'road_feature_count',count(distinct f.id),
    'road_length_m',round(coalesce(sum(
      extensions.st_length(
        extensions.st_intersection(
          extensions.st_transform(f.geometry,32616),
          extensions.st_transform(v_domains.landscape_1500m,32616)
        )
      )
    ),0)::numeric,1),
    'domain_area_km2',round((extensions.st_area(v_domains.landscape_1500m::geography)/1000000.0)::numeric,6)
  )
  into v_landscape
  from decisioning.site_access_features f
  where f.source_id=v_road_source_id
    and f.feature_class='road'
    and v_domains.landscape_1500m is not null
    and extensions.st_intersects(f.geometry,v_domains.landscape_1500m);

  select jsonb_build_object(
    'road_feature_count',count(distinct f.id),
    'road_length_m',round(coalesce(sum(
      extensions.st_length(
        extensions.st_intersection(
          extensions.st_transform(f.geometry,32616),
          extensions.st_transform(v_domains.broad_3000m,32616)
        )
      )
    ),0)::numeric,1),
    'domain_area_km2',round((extensions.st_area(v_domains.broad_3000m::geography)/1000000.0)::numeric,6)
  )
  into v_broad
  from decisioning.site_access_features f
  where f.source_id=v_road_source_id
    and f.feature_class='road'
    and v_domains.broad_3000m is not null
    and extensions.st_intersects(f.geometry,v_domains.broad_3000m);

  select round(min(extensions.st_distance(f.geometry::geography,v_center::geography))::numeric,1)
  into v_nearest_road_m
  from decisioning.site_access_features f
  where f.source_id=v_road_source_id
    and f.feature_class='road'
    and extensions.st_dwithin(f.geometry::geography,v_center::geography,10000);

  v_status := case
    when v_domains.property_id is null or v_road_source_id is null or v_road_source_timestamp is null
      then 'partial'
    else 'available'
  end;

  v_source_fingerprint := jsonb_build_object(
    'building_source','ky-ornl-building-footprints',
    'building_metadata_sha256',p_building_metadata_sha256,
    'building_count',p_building_count,
    'building_study_area_km2',10.36,
    'road_source','openstreetmap-geofabrik-access-snapshot',
    'road_source_timestamp',v_road_source_timestamp,
    'landscape_domain_identity_sha256',v_domains.identity_sha256
  );
  v_source_fingerprint_sha256 := encode(
    extensions.digest(convert_to(v_source_fingerprint::text,'UTF8'),'sha256'),'hex'
  );
  v_source_signature := concat_ws(
    '|',
    'product=human-footprint-context',
    'building_count='||p_building_count::text,
    'building_metadata_sha256='||p_building_metadata_sha256,
    'road_source_timestamp='||coalesce(v_road_source_timestamp::text,'unavailable'),
    'landscape_domain_identity='||coalesce(v_domains.identity_sha256,'unavailable')
  );
  v_source_signature_sha256 := encode(
    extensions.digest(convert_to(v_source_signature,'UTF8'),'sha256'),'hex'
  );
  v_identity_sha256 := encode(
    extensions.digest(convert_to(concat_ws(
      '|',v_property_id::text,v_boundary_sha256,
      'ky-ornl-osm-human-footprint-context-v1',
      'human-footprint-context-v1',
      v_source_signature_sha256
    ),'UTF8'),'sha256'),'hex'
  );

  v_context := jsonb_build_object(
    'schema','human-footprint-context-v1',
    'method','ky-ornl-osm-human-footprint-context-v1',
    'evidence_class','deterministic_derived',
    'building_development',jsonb_build_object(
      'source','Kentucky ORNL / FEMA USA Structures Building Footprints',
      'source_url','https://kygisserver.ky.gov/arcgis/rest/services/WGS84WM_Services/Ky_ORNL_Building_Footprints_WGS84WM/MapServer/0',
      'study_alignment','Delisle et al. 2024 counted buildings within fixed 10.36 km2 landscapes',
      'window_basis','property_centered_equal_area_square_v1',
      'study_area_km2',10.36,
      'building_count',p_building_count,
      'building_density_per_km2',p_building_count/10.36,
      'source_checked_at',p_building_checked_at,
      'metadata_sha256',p_building_metadata_sha256
    ),
    'road_context',jsonb_build_object(
      'source','OpenStreetMap Geofabrik Access Snapshot',
      'source_timestamp',v_road_source_timestamp,
      'included_feature_class','road',
      'excluded_access_classes',jsonb_build_array('driveway','service_road','parking_aisle','sidewalk'),
      'study_alignment','Stephens et al. 2024 used paved and unpaved road geometry to derive distance-to-road at 10 m resolution and 30/90/270 m focal scales',
      'study_sampling_radii_m',jsonb_build_array(30,90,270),
      'property_center_nearest_road_m',v_nearest_road_m,
      'scopes',jsonb_build_object(
        'local_500m',coalesce(v_local,'{}'::jsonb),
        'landscape_1500m',coalesce(v_landscape,'{}'::jsonb),
        'broad_3000m',coalesce(v_broad,'{}'::jsonb)
      ),
      'future_step_local_boundary','This neutral product preserves road geometry/proximity context. A future step-selection module must perform source-style 30/90/270 m focal extraction rather than treating road density as a universal deer sign.'
    ),
    'source_fingerprint',v_source_fingerprint,
    'source_fingerprint_sha256',v_source_fingerprint_sha256,
    'scoring_performed',false,
    'deer_inference_performed',false,
    'interpretation_boundary','Building and road context are neutral anthropogenic geometry. No deer activity, avoidance, selection, mortality risk, or movement direction is inferred.'
  );

  insert into farm_watch.property_human_footprint_context_v1(
    property_id,status,context,boundary_sha256,source_signature,
    source_signature_sha256,algorithm_version,output_schema_version,
    identity_sha256,retrieved_at,updated_at
  ) values (
    v_property_id,v_status,v_context,v_boundary_sha256,v_source_signature,
    v_source_signature_sha256,'ky-ornl-osm-human-footprint-context-v1',
    'human-footprint-context-v1',v_identity_sha256,now(),now()
  )
  on conflict(property_id) do update set
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

  return jsonb_build_object(
    'status',v_status,
    'property',jsonb_build_object('slug',p_slug,'id',v_property_id),
    'context',v_context,
    'identity',jsonb_build_object(
      'boundary_sha256',v_boundary_sha256,
      'source_signature_sha256',v_source_signature_sha256,
      'identity_sha256',v_identity_sha256,
      'algorithm_version','ky-ornl-osm-human-footprint-context-v1',
      'output_schema_version','human-footprint-context-v1'
    )
  );
end;
$$;

create or replace function farm_watch.farm_watch_refresh_multiscale_cover_context_v1_internal(
  p_slug text
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','farm_watch','extensions'
as $$
declare
  v_property_id uuid;
  v_boundary extensions.geometry;
  v_center extensions.geometry;
  v_center_utm extensions.geometry;
  v_boundary_sha256 text;
  v_area integer;
  v_side double precision;
  v_half double precision;
  v_geom_utm extensions.geometry;
  v_geom extensions.geometry;
  v_scale_key text;
  v_identity text;
  v_windows jsonb;
begin
  select p.id,p.boundary,p.center
  into v_property_id,v_boundary,v_center
  from farm_watch.properties p
  where p.slug=p_slug and p.status='active'
  limit 1;

  if v_property_id is null or v_boundary is null or v_center is null then
    return jsonb_build_object('status','missing','property',jsonb_build_object('slug',p_slug));
  end if;

  v_boundary_sha256 := encode(
    extensions.digest(extensions.st_asewkb(v_boundary),'sha256'),'hex'
  );
  v_center_utm := extensions.st_transform(v_center,32616);

  foreach v_area in array array[1,9]
  loop
    v_side := sqrt(v_area * 1000000.0);
    v_half := v_side/2.0;
    v_geom_utm := extensions.st_makeenvelope(
      extensions.st_x(v_center_utm)-v_half,
      extensions.st_y(v_center_utm)-v_half,
      extensions.st_x(v_center_utm)+v_half,
      extensions.st_y(v_center_utm)+v_half,
      32616
    );
    v_geom := extensions.st_transform(v_geom_utm,4326);
    v_scale_key := case when v_area=1 then 'nagy_reis_1km2' else 'nagy_reis_9km2' end;
    v_identity := encode(
      extensions.digest(convert_to(concat_ws(
        '|',v_property_id::text,v_boundary_sha256,v_scale_key,
        'nagy-reis-property-centered-grid-scales-v1',
        encode(extensions.digest(extensions.st_asewkb(v_geom),'sha256'),'hex')
      ),'UTF8'),'sha256'),'hex'
    );

    insert into farm_watch.property_study_scale_windows_v1(
      property_id,scale_key,area_km2,side_m,geometry,geometry_basis,
      projected_crs,source_study,boundary_sha256,identity_sha256,updated_at
    ) values (
      v_property_id,v_scale_key,v_area,v_side,v_geom,
      'property_centered_square_matching_source_virtual_grid_cell_area',
      'EPSG:32616',
      'Nagy-Reis et al. 2019, Journal of Environmental Management 248:109299',
      v_boundary_sha256,v_identity,now()
    )
    on conflict(property_id,scale_key) do update set
      area_km2=excluded.area_km2,
      side_m=excluded.side_m,
      geometry=excluded.geometry,
      geometry_basis=excluded.geometry_basis,
      projected_crs=excluded.projected_crs,
      source_study=excluded.source_study,
      boundary_sha256=excluded.boundary_sha256,
      identity_sha256=excluded.identity_sha256,
      updated_at=now();
  end loop;

  select jsonb_agg(
    jsonb_build_object(
      'scale_key',w.scale_key,
      'area_km2',w.area_km2,
      'side_m',w.side_m,
      'geometry_basis',w.geometry_basis,
      'projected_crs',w.projected_crs,
      'geometry_geojson',extensions.st_asgeojson(w.geometry)::jsonb,
      'identity_sha256',w.identity_sha256
    )
    order by w.area_km2
  )
  into v_windows
  from farm_watch.property_study_scale_windows_v1 w
  where w.property_id=v_property_id;

  return jsonb_build_object(
    'status','available',
    'property',jsonb_build_object('slug',p_slug,'id',v_property_id),
    'context',jsonb_build_object(
      'schema','multiscale-cover-context-v1',
      'method','nagy-reis-property-centered-grid-scales-v1',
      'evidence_class','deterministic_derived',
      'source_study','Nagy-Reis et al. 2019',
      'source_method','virtual grids of 1.0 km2 and 9.0 km2 superimposed on survey units',
      'windows',coalesce(v_windows,'[]'::jsonb),
      'hunting_unit_scale_status','not_transferred',
      'deer_inference_performed',false,
      'interpretation_boundary','The product reproduces exact 1 km2 and 9 km2 square areas as property-centered analytical windows. It does not transfer North Dakota hunting-unit geometry or any deer occurrence/abundance coefficient.'
    )
  );
end;
$$;

create or replace function farm_watch.farm_watch_get_multiscale_cover_context_v1_internal(
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
  v_windows jsonb;
begin
  select p.id into v_property_id
  from farm_watch.properties p
  where p.slug=p_slug and p.status='active'
  limit 1;

  if v_property_id is null then
    return jsonb_build_object('status','missing','property',jsonb_build_object('slug',p_slug));
  end if;

  select jsonb_agg(
    jsonb_build_object(
      'scale_key',w.scale_key,
      'area_km2',w.area_km2,
      'side_m',w.side_m,
      'geometry_basis',w.geometry_basis,
      'projected_crs',w.projected_crs,
      'geometry_geojson',extensions.st_asgeojson(w.geometry)::jsonb,
      'identity_sha256',w.identity_sha256
    )
    order by w.area_km2
  )
  into v_windows
  from farm_watch.property_study_scale_windows_v1 w
  where w.property_id=v_property_id;

  if v_windows is null then
    return jsonb_build_object(
      'status','missing',
      'property',jsonb_build_object('slug',p_slug,'id',v_property_id),
      'context',null
    );
  end if;

  return jsonb_build_object(
    'status','available',
    'property',jsonb_build_object('slug',p_slug,'id',v_property_id),
    'context',jsonb_build_object(
      'schema','multiscale-cover-context-v1',
      'method','nagy-reis-property-centered-grid-scales-v1',
      'evidence_class','deterministic_derived',
      'source_study','Nagy-Reis et al. 2019',
      'windows',v_windows,
      'hunting_unit_scale_status','not_transferred',
      'deer_inference_performed',false
    )
  );
end;
$$;

create or replace function farm_watch.farm_watch_resolve_extreme_weather_event_context_v1_internal(
  p_slug text,
  p_as_of_at timestamptz default now()
)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','farm_watch','extensions','intelligence'
as $$
declare
  v_property_id uuid;
  v_boundary extensions.geometry;
  v_boundary_sha256 text;
  v_events jsonb;
  v_count integer;
  v_source_signature text;
  v_source_signature_sha256 text;
  v_identity_sha256 text;
  v_context jsonb;
  v_status text;
begin
  select p.id,p.boundary
  into v_property_id,v_boundary
  from farm_watch.properties p
  where p.slug=p_slug and p.status='active'
  limit 1;

  if v_property_id is null or v_boundary is null then
    return jsonb_build_object('status','missing','property',jsonb_build_object('slug',p_slug));
  end if;

  v_boundary_sha256 := encode(
    extensions.digest(extensions.st_asewkb(v_boundary),'sha256'),'hex'
  );

  select
    coalesce(jsonb_agg(
      jsonb_strip_nulls(jsonb_build_object(
        'canonical_key',e.canonical_key,
        'event_type',e.event_type,
        'severity',e.severity,
        'certainty',e.certainty,
        'urgency',e.urgency,
        'headline',e.headline,
        'effective_at',e.effective_at,
        'onset_at',e.onset_at,
        'ends_at',e.ends_at,
        'expires_at',e.expires_at,
        'source_slug',e.source_slug,
        'source_native_id',e.source_native_id
      ))
      order by coalesce(e.onset_at,e.effective_at,e.sent_at),e.canonical_key
    ),'[]'::jsonb),
    count(*)::integer
  into v_events,v_count
  from intelligence.weather_events e
  where e.source_slug='nws-alerts-api'
    and e.event_type = any(array[
      'Hurricane Warning','Hurricane Watch',
      'Tropical Storm Warning','Tropical Storm Watch',
      'Storm Surge Warning','Storm Surge Watch',
      'Extreme Wind Warning'
    ])
    and coalesce(e.onset_at,e.effective_at,e.sent_at) <= p_as_of_at
    and coalesce(e.ends_at,e.expires_at,e.last_observed_at + interval '1 hour') >= p_as_of_at
    and e.geometry is not null
    and extensions.st_intersects(e.geometry,v_boundary);

  v_status := case when v_count>0 then 'available' else 'inactive' end;
  v_source_signature := concat_ws(
    '|',
    'product=extreme-weather-event-context',
    'as_of_minute='||date_trunc('minute',p_as_of_at)::text,
    'qualifying_event_count='||v_count::text,
    'event_keys='||coalesce((
      select string_agg(x->>'canonical_key',',' order by x->>'canonical_key')
      from jsonb_array_elements(v_events) x
    ),'')
  );
  v_source_signature_sha256 := encode(
    extensions.digest(convert_to(v_source_signature,'UTF8'),'sha256'),'hex'
  );
  v_identity_sha256 := encode(
    extensions.digest(convert_to(concat_ws(
      '|',v_property_id::text,v_boundary_sha256,
      'nws-tropical-extreme-event-gate-v1',
      'extreme-weather-event-context-v1',
      v_source_signature_sha256
    ),'UTF8'),'sha256'),'hex'
  );

  v_context := jsonb_build_object(
    'schema','extreme-weather-event-context-v1',
    'method','nws-tropical-extreme-event-gate-v1',
    'evidence_class','authoritative_event_context',
    'as_of_at',p_as_of_at,
    'event_active',v_count>0,
    'events',v_events,
    'qualifying_event_types',jsonb_build_array(
      'Hurricane Warning','Hurricane Watch',
      'Tropical Storm Warning','Tropical Storm Watch',
      'Storm Surge Warning','Storm Surge Watch',
      'Extreme Wind Warning'
    ),
    'ordinary_weather_activation_allowed',false,
    'source','NOAA National Weather Service Alerts API',
    'source_fingerprint_sha256',v_source_signature_sha256,
    'scoring_performed',false,
    'deer_inference_performed',false,
    'interpretation_boundary','This is an explicit tropical/extreme wind event gate for FW-D18. Severe thunderstorms, routine wind, ordinary rainfall, heat, and generic storminess do not activate the relationship.'
  );

  return jsonb_build_object(
    'status',v_status,
    'property',jsonb_build_object('slug',p_slug,'id',v_property_id),
    'context',v_context,
    'identity',jsonb_build_object(
      'boundary_sha256',v_boundary_sha256,
      'source_signature',v_source_signature,
      'source_signature_sha256',v_source_signature_sha256,
      'algorithm_version','nws-tropical-extreme-event-gate-v1',
      'output_schema_version','extreme-weather-event-context-v1',
      'identity_sha256',v_identity_sha256
    )
  );
end;
$$;

create or replace function farm_watch.farm_watch_refresh_extreme_weather_event_context_v1_internal(
  p_slug text,
  p_as_of_at timestamptz default now()
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
  v_resolved := farm_watch.farm_watch_resolve_extreme_weather_event_context_v1_internal(
    p_slug,p_as_of_at
  );
  if v_resolved->>'status'='missing' then return v_resolved; end if;

  v_property_id := (v_resolved->'property'->>'id')::uuid;

  insert into farm_watch.property_extreme_weather_event_context_v1(
    property_id,as_of_at,status,context,boundary_sha256,source_signature,
    source_signature_sha256,algorithm_version,output_schema_version,
    identity_sha256,retrieved_at,updated_at
  ) values (
    v_property_id,p_as_of_at,v_resolved->>'status',v_resolved->'context',
    v_resolved->'identity'->>'boundary_sha256',
    v_resolved->'identity'->>'source_signature',
    v_resolved->'identity'->>'source_signature_sha256',
    v_resolved->'identity'->>'algorithm_version',
    v_resolved->'identity'->>'output_schema_version',
    v_resolved->'identity'->>'identity_sha256',
    now(),now()
  )
  on conflict(property_id) do update set
    as_of_at=excluded.as_of_at,
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

  return v_resolved;
end;
$$;

create or replace function public.farm_watch_get_human_footprint_query_v1_internal(p_slug text)
returns jsonb
language sql
stable
security definer
set search_path='pg_catalog'
as $$
  select farm_watch.farm_watch_get_human_footprint_query_v1_internal(p_slug);
$$;

create or replace function public.farm_watch_record_human_footprint_context_v1_internal(
  p_slug text,
  p_building_count integer,
  p_building_metadata_sha256 text,
  p_building_checked_at timestamptz default now()
)
returns jsonb
language sql
security definer
set search_path='pg_catalog'
as $$
  select farm_watch.farm_watch_record_human_footprint_context_v1_internal(
    p_slug,p_building_count,p_building_metadata_sha256,p_building_checked_at
  );
$$;

revoke all on function farm_watch.farm_watch_deer_tier1_context_contract_v1() from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_get_human_footprint_query_v1_internal(text) from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_record_human_footprint_context_v1_internal(text,integer,text,timestamptz) from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_refresh_multiscale_cover_context_v1_internal(text) from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_get_multiscale_cover_context_v1_internal(text) from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_resolve_extreme_weather_event_context_v1_internal(text,timestamptz) from public,anon,authenticated;
revoke all on function farm_watch.farm_watch_refresh_extreme_weather_event_context_v1_internal(text,timestamptz) from public,anon,authenticated;
revoke all on function public.farm_watch_get_human_footprint_query_v1_internal(text) from public,anon,authenticated;
revoke all on function public.farm_watch_record_human_footprint_context_v1_internal(text,integer,text,timestamptz) from public,anon,authenticated;

grant execute on function farm_watch.farm_watch_deer_tier1_context_contract_v1() to service_role;
grant execute on function farm_watch.farm_watch_get_human_footprint_query_v1_internal(text) to service_role;
grant execute on function farm_watch.farm_watch_record_human_footprint_context_v1_internal(text,integer,text,timestamptz) to service_role;
grant execute on function farm_watch.farm_watch_refresh_multiscale_cover_context_v1_internal(text) to service_role;
grant execute on function farm_watch.farm_watch_get_multiscale_cover_context_v1_internal(text) to service_role;
grant execute on function farm_watch.farm_watch_resolve_extreme_weather_event_context_v1_internal(text,timestamptz) to service_role;
grant execute on function farm_watch.farm_watch_refresh_extreme_weather_event_context_v1_internal(text,timestamptz) to service_role;
grant execute on function public.farm_watch_get_human_footprint_query_v1_internal(text) to service_role;
grant execute on function public.farm_watch_record_human_footprint_context_v1_internal(text,integer,text,timestamptz) to service_role;

insert into ingest.collector_routes(slug,enabled,allow_dispatch,updated_at)
values('collect-farm-watch-human-footprint',true,true,now())
on conflict(slug) do update set
  enabled=excluded.enabled,
  allow_dispatch=excluded.allow_dispatch,
  updated_at=excluded.updated_at;

select farm_watch.farm_watch_refresh_multiscale_cover_context_v1_internal('validation-property-01');
select farm_watch.farm_watch_refresh_extreme_weather_event_context_v1_internal('validation-property-01',now());

do $$
begin
  if exists(select 1 from cron.job where jobname='farm-watch-human-footprint-monthly-v1') then
    perform cron.unschedule('farm-watch-human-footprint-monthly-v1');
  end if;
  perform cron.schedule(
    'farm-watch-human-footprint-monthly-v1',
    '15 14 1 * *',
    $cron$
      select ingest.invoke_edge_collector(
        'collect-farm-watch-human-footprint',
        jsonb_build_object('property','validation-property-01')
      );
    $cron$
  );

  if exists(select 1 from cron.job where jobname='farm-watch-extreme-weather-context-v1') then
    perform cron.unschedule('farm-watch-extreme-weather-context-v1');
  end if;
  perform cron.schedule(
    'farm-watch-extreme-weather-context-v1',
    '*/10 * * * *',
    $cron$
      select farm_watch.farm_watch_refresh_extreme_weather_event_context_v1_internal(
        'validation-property-01',
        now()
      );
    $cron$
  );
end;
$$;

comment on table farm_watch.property_human_footprint_context_v1 is
'Neutral Farm Watch building/road context for deer-science measurement fidelity. Building count follows the Delisle 10.36 km2 landscape scale; road geometry remains a neutral source for Stephens-style road-distance context.';
comment on table farm_watch.property_study_scale_windows_v1 is
'Exact-area 1 km2 and 9 km2 square analytical windows reproducing the Nagy-Reis fixed grid-cell scales around the selected Farm Watch property center; North Dakota hunting-unit geometry is not transferred.';
comment on table farm_watch.property_extreme_weather_event_context_v1 is
'Authoritative NWS tropical/extreme-wind event gate for FW-D18. Ordinary weather never activates this context.';

commit;
