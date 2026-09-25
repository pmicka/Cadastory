begin;

create or replace function farm_watch.farm_watch_deer_tier1_context_contract_v1()
returns jsonb
language sql
immutable
security definer
set search_path='pg_catalog'
as $$
  select jsonb_build_object(
    'human_footprint',jsonb_build_object(
      'algorithm_version','fema-usastructures-osm-human-footprint-v1',
      'output_schema_version','human-footprint-context-v1',
      'building_study_area_km2',10.36,
      'building_source','FEMA USA Structures View',
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
        'https://services2.arcgis.com/FiaPA4ga0iQKduv3/arcgis/rest/services/USA_Structures_View/FeatureServer/0'
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
    'building_source','fema-usa-structures-current',
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
      'fema-usastructures-osm-human-footprint-v1',
      'human-footprint-context-v1',
      v_source_signature_sha256
    ),'UTF8'),'sha256'),'hex'
  );

  v_context := jsonb_build_object(
    'schema','human-footprint-context-v1',
    'method','fema-usastructures-osm-human-footprint-v1',
    'evidence_class','deterministic_derived',
    'building_development',jsonb_build_object(
      'source','FEMA USA Structures View',
      'source_url','https://services2.arcgis.com/FiaPA4ga0iQKduv3/arcgis/rest/services/USA_Structures_View/FeatureServer/0',
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
    v_source_signature_sha256,'fema-usastructures-osm-human-footprint-v1',
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
      'algorithm_version','fema-usastructures-osm-human-footprint-v1',
      'output_schema_version','human-footprint-context-v1'
    )
  );
end;
$$;

comment on table farm_watch.property_human_footprint_context_v1 is
'Neutral Farm Watch building/road context for deer-science measurement fidelity. Building count follows the Delisle 10.36 km2 landscape scale using the current unfiltered FEMA USA Structures View; road geometry remains a neutral source for Stephens-style road-distance context.';

commit;
