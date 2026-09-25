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
      'algorithm_version','fema-usastructures-osm-human-footprint-v2',
      'output_schema_version','human-footprint-context-v1',
      'building_study_area_km2',10.36,
      'building_source','FEMA USA Structures View',
      'building_known_minimum_structure_area_sqft',450,
      'building_spatial_completeness_status','not_quantified_by_source',
      'road_source','OpenStreetMap Geofabrik Access Snapshot',
      'road_study_sampling_radii_m',jsonb_build_array(30,90,270)
    ),
    'road_focal',jsonb_build_object(
      'algorithm_version','stephens-road-distance-focal-10m-v1',
      'output_schema_version','road-focal-context-v1',
      'road_source','OpenStreetMap Geofabrik Access Snapshot',
      'raster_resolution_m',10,
      'focal_radii_m',jsonb_build_array(30,90,270)
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

create or replace function farm_watch.farm_watch_record_human_footprint_context_v2_internal(
  p_slug text,
  p_building_count integer,
  p_building_metadata_sha256 text,
  p_building_source_profile jsonb,
  p_building_checked_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','farm_watch','extensions'
as $$
declare
  v_base jsonb;
  v_property_id uuid;
  v_status text;
  v_context jsonb;
  v_boundary_sha256 text;
  v_old_source_signature text;
  v_source_signature text;
  v_source_signature_sha256 text;
  v_profile_sha256 text;
  v_source_fingerprint jsonb;
  v_source_fingerprint_sha256 text;
  v_identity_sha256 text;
begin
  if p_building_source_profile is null
     or jsonb_typeof(p_building_source_profile) <> 'object' then
    raise exception 'building source profile is required';
  end if;
  if coalesce(p_building_source_profile#>>'{service,service_item_id}','') = '' then
    raise exception 'building source profile service item is required';
  end if;
  if (p_building_source_profile#>>'{completeness,queried_feature_count}')::integer
       <> p_building_count then
    raise exception 'building source profile count does not match building count';
  end if;
  if (p_building_source_profile#>>'{completeness,known_minimum_structure_area_sqft}')::numeric
       <> 450 then
    raise exception 'unexpected FEMA USA Structures minimum structure area';
  end if;
  if p_building_source_profile#>>'{completeness,spatial_completeness_status}'
       <> 'not_quantified_by_source' then
    raise exception 'building spatial completeness must remain unquantified unless the source provides a defensible denominator';
  end if;
  if p_building_source_profile#>>'{completeness,transfer_limit_risk}'
       <> 'none_for_aggregate_statistics' then
    raise exception 'building query completeness contract is not satisfied';
  end if;

  v_base := farm_watch.farm_watch_record_human_footprint_context_v1_internal(
    p_slug,
    p_building_count,
    p_building_metadata_sha256,
    p_building_checked_at
  );

  if v_base->>'status'='missing' then
    return v_base;
  end if;

  v_property_id := (v_base->'property'->>'id')::uuid;

  select
    h.status,
    h.context,
    h.boundary_sha256,
    h.source_signature
  into
    v_status,
    v_context,
    v_boundary_sha256,
    v_old_source_signature
  from farm_watch.property_human_footprint_context_v1 h
  where h.property_id=v_property_id
  limit 1;

  if v_context is null then
    raise exception 'human-footprint context was not materialized';
  end if;

  v_profile_sha256 := encode(
    extensions.digest(
      convert_to(p_building_source_profile::text,'UTF8'),
      'sha256'
    ),
    'hex'
  );

  v_source_fingerprint :=
    coalesce(v_context->'source_fingerprint','{}'::jsonb)
    || jsonb_build_object(
      'building_source_profile_sha256',v_profile_sha256,
      'building_source_service_item_id',
        p_building_source_profile#>>'{service,service_item_id}',
      'building_source_data_last_edit_at',
        p_building_source_profile#>>'{service,data_last_edit_at}',
      'building_source_production_date_min',
        p_building_source_profile#>>'{local_feature_vintage,production_date,min}',
      'building_source_production_date_max',
        p_building_source_profile#>>'{local_feature_vintage,production_date,max}',
      'building_spatial_completeness_status',
        p_building_source_profile#>>'{completeness,spatial_completeness_status}',
      'building_known_minimum_structure_area_sqft',450
    );

  v_source_fingerprint_sha256 := encode(
    extensions.digest(
      convert_to(v_source_fingerprint::text,'UTF8'),
      'sha256'
    ),
    'hex'
  );

  v_source_signature := concat_ws(
    '|',
    v_old_source_signature,
    'building_source_profile_sha256='||v_profile_sha256,
    'algorithm=fema-usastructures-osm-human-footprint-v2'
  );
  v_source_signature_sha256 := encode(
    extensions.digest(
      convert_to(v_source_signature,'UTF8'),
      'sha256'
    ),
    'hex'
  );

  v_identity_sha256 := encode(
    extensions.digest(
      convert_to(concat_ws(
        '|',
        v_property_id::text,
        v_boundary_sha256,
        'fema-usastructures-osm-human-footprint-v2',
        'human-footprint-context-v1',
        v_source_signature_sha256
      ),'UTF8'),
      'sha256'
    ),
    'hex'
  );

  v_context := jsonb_set(
    v_context,
    '{method}',
    to_jsonb('fema-usastructures-osm-human-footprint-v2'::text),
    true
  );
  v_context := jsonb_set(
    v_context,
    '{building_development,source_profile}',
    p_building_source_profile,
    true
  );
  v_context := jsonb_set(
    v_context,
    '{source_fingerprint}',
    v_source_fingerprint,
    true
  );
  v_context := jsonb_set(
    v_context,
    '{source_fingerprint_sha256}',
    to_jsonb(v_source_fingerprint_sha256),
    true
  );

  update farm_watch.property_human_footprint_context_v1 h
  set
    context=v_context,
    source_signature=v_source_signature,
    source_signature_sha256=v_source_signature_sha256,
    algorithm_version='fema-usastructures-osm-human-footprint-v2',
    identity_sha256=v_identity_sha256,
    retrieved_at=now(),
    updated_at=now()
  where h.property_id=v_property_id;

  return jsonb_build_object(
    'status',v_status,
    'property',jsonb_build_object('slug',p_slug,'id',v_property_id),
    'context',v_context,
    'identity',jsonb_build_object(
      'boundary_sha256',v_boundary_sha256,
      'building_source_profile_sha256',v_profile_sha256,
      'source_signature_sha256',v_source_signature_sha256,
      'identity_sha256',v_identity_sha256,
      'algorithm_version','fema-usastructures-osm-human-footprint-v2',
      'output_schema_version','human-footprint-context-v1'
    )
  );
end;
$$;

create or replace function public.farm_watch_record_human_footprint_context_v2_internal(
  p_slug text,
  p_building_count integer,
  p_building_metadata_sha256 text,
  p_building_source_profile jsonb,
  p_building_checked_at timestamptz default now()
)
returns jsonb
language sql
security definer
set search_path='pg_catalog'
as $$
  select farm_watch.farm_watch_record_human_footprint_context_v2_internal(
    p_slug,
    p_building_count,
    p_building_metadata_sha256,
    p_building_source_profile,
    p_building_checked_at
  );
$$;

revoke all on function farm_watch.farm_watch_record_human_footprint_context_v2_internal(
  text,integer,text,jsonb,timestamptz
) from public,anon,authenticated;
revoke all on function public.farm_watch_record_human_footprint_context_v2_internal(
  text,integer,text,jsonb,timestamptz
) from public,anon,authenticated;

grant execute on function farm_watch.farm_watch_record_human_footprint_context_v2_internal(
  text,integer,text,jsonb,timestamptz
) to service_role;
grant execute on function public.farm_watch_record_human_footprint_context_v2_internal(
  text,integer,text,jsonb,timestamptz
) to service_role;

update ingest.sources
set notes = case
  when notes ilike '%FW-M24 completeness%' then notes
  else concat_ws(
    ' ',
    notes,
    'FW-M24 completeness: the FEMA USA Structures inventory is designed for structures greater than 450 square feet. Farm Watch records live service edit dates and local feature production/imagery date coverage, but does not claim spatial completeness because the source publishes no defensible property-window completeness denominator.'
  )
end
where slug='fema-usa-structures-current';

comment on function farm_watch.farm_watch_record_human_footprint_context_v2_internal(
  text,integer,text,jsonb,timestamptz
) is
'Records FW-M24 building density plus live FEMA USA Structures service edit dates, local feature production/imagery vintage coverage, known >450 sq ft inventory threshold, and explicit unquantified spatial completeness.';

commit;
