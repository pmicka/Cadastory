begin;

create or replace function farm_watch.farm_watch_resolve_road_focal_context_v1_internal(
  p_slug text,
  p_lon double precision default null,
  p_lat double precision default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','farm_watch','extensions','decisioning','ingest'
as $$
declare
  v_property_id uuid;
  v_state_code text;
  v_property_center extensions.geometry;
  v_anchor extensions.geometry;
  v_anchor_utm extensions.geometry;
  v_broad extensions.geometry;
  v_road_source_id uuid;
  v_road_source_timestamp timestamptz;
  v_center_nearest_m double precision;
  v_candidate_radius_m double precision;
  v_x double precision;
  v_y double precision;
  v_r30_mean numeric;
  v_r90_mean numeric;
  v_r270_mean numeric;
  v_r30_count integer;
  v_r90_count integer;
  v_r270_count integer;
  v_source_signature text;
  v_source_signature_sha256 text;
  v_identity_sha256 text;
begin
  if (p_lon is null) <> (p_lat is null) then
    raise exception 'road focal longitude and latitude must be supplied together';
  end if;
  if p_lon is not null and (p_lon < -180 or p_lon > 180 or p_lat < -90 or p_lat > 90) then
    raise exception 'invalid road focal longitude/latitude';
  end if;

  select p.id,p.state_code,p.center,d.broad_3000m
  into v_property_id,v_state_code,v_property_center,v_broad
  from farm_watch.properties p
  left join farm_watch.property_landscape_domains_v1 d
    on d.property_id=p.id and d.status='available'
  where p.slug=p_slug and p.status='active'
  limit 1;

  if v_property_id is null or v_property_center is null then
    return jsonb_build_object(
      'status','missing',
      'schema','road-focal-context-v1',
      'property',jsonb_build_object('slug',p_slug)
    );
  end if;

  v_anchor := case
    when p_lon is null then v_property_center
    else extensions.st_setsrid(extensions.st_makepoint(p_lon,p_lat),4326)
  end;

  if p_lon is not null and (
    v_broad is null or not extensions.st_covers(v_broad,v_anchor)
  ) then
    return jsonb_build_object(
      'status','out_of_scope',
      'schema','road-focal-context-v1',
      'property',jsonb_build_object('slug',p_slug,'id',v_property_id),
      'interpretation_boundary',
        'On-demand road focal evaluation is bounded to the current Farm Watch broad landscape domain for this property.'
    );
  end if;

  select s.id
  into v_road_source_id
  from ingest.sources s
  where s.slug='openstreetmap-geofabrik-access-snapshot'
    and s.status='active'
  limit 1;

  select r.current_source_timestamp
  into v_road_source_timestamp
  from decisioning.site_access_snapshot_regions r
  where r.state_code=v_state_code
    and r.status='ready'
  order by r.current_source_timestamp desc nulls last
  limit 1;

  if v_road_source_id is null or v_road_source_timestamp is null then
    return jsonb_build_object(
      'status','unavailable',
      'schema','road-focal-context-v1',
      'property',jsonb_build_object('slug',p_slug,'id',v_property_id),
      'reason','canonical road snapshot unavailable'
    );
  end if;

  select min(extensions.st_distance(f.geometry::geography,v_anchor::geography))
  into v_center_nearest_m
  from decisioning.site_access_features f
  where f.source_id=v_road_source_id
    and f.feature_class='road'
    and extensions.st_dwithin(f.geometry::geography,v_anchor::geography,50000);

  if v_center_nearest_m is null then
    return jsonb_build_object(
      'status','unavailable',
      'schema','road-focal-context-v1',
      'property',jsonb_build_object('slug',p_slug,'id',v_property_id),
      'reason','no canonical road geometry found within 50 km'
    );
  end if;

  v_anchor_utm := extensions.st_transform(v_anchor,32616);
  v_x := extensions.st_x(v_anchor_utm);
  v_y := extensions.st_y(v_anchor_utm);

  -- Triangle-inequality bound: for any sample cell within 270 m, a road
  -- farther than center-nearest + 2*270 m from the anchor cannot become
  -- the nearest road to that sample cell. Add 20 m for grid-edge tolerance.
  v_candidate_radius_m := v_center_nearest_m + 560.0;

  with roads as materialized (
    select extensions.st_transform(f.geometry,32616) as geom
    from decisioning.site_access_features f
    where f.source_id=v_road_source_id
      and f.feature_class='road'
      and extensions.st_dwithin(
        f.geometry::geography,
        v_anchor::geography,
        v_candidate_radius_m
      )
  ),
  grid as (
    select
      gx::double precision as gx,
      gy::double precision as gy,
      sqrt(power(gx-v_x,2)+power(gy-v_y,2)) as radius_m,
      extensions.st_setsrid(extensions.st_makepoint(gx,gy),32616) as geom
    from generate_series(
      (floor((v_x-270.0)/10.0)*10.0+5.0)::numeric,
      (ceil((v_x+270.0)/10.0)*10.0-5.0)::numeric,
      10.0::numeric
    ) gx
    cross join generate_series(
      (floor((v_y-270.0)/10.0)*10.0+5.0)::numeric,
      (ceil((v_y+270.0)/10.0)*10.0-5.0)::numeric,
      10.0::numeric
    ) gy
    where sqrt(power(gx-v_x,2)+power(gy-v_y,2)) <= 270.0
  ),
  cell_distance as (
    select
      g.gx,
      g.gy,
      g.radius_m,
      min(extensions.st_distance(g.geom,r.geom)) as road_distance_m
    from grid g
    cross join roads r
    group by g.gx,g.gy,g.radius_m
  )
  select
    round(avg(road_distance_m) filter (where radius_m <= 30.0)::numeric,3),
    count(*) filter (where radius_m <= 30.0)::integer,
    round(avg(road_distance_m) filter (where radius_m <= 90.0)::numeric,3),
    count(*) filter (where radius_m <= 90.0)::integer,
    round(avg(road_distance_m) filter (where radius_m <= 270.0)::numeric,3),
    count(*) filter (where radius_m <= 270.0)::integer
  into
    v_r30_mean,v_r30_count,
    v_r90_mean,v_r90_count,
    v_r270_mean,v_r270_count
  from cell_distance;

  if v_r270_count is null or v_r270_count=0 or v_r270_mean is null then
    return jsonb_build_object(
      'status','unavailable',
      'schema','road-focal-context-v1',
      'property',jsonb_build_object('slug',p_slug,'id',v_property_id),
      'reason','road-distance focal grid could not be evaluated'
    );
  end if;

  v_source_signature := concat_ws(
    '|',
    'source=openstreetmap-geofabrik-access-snapshot',
    'source_timestamp='||v_road_source_timestamp::text,
    'algorithm=stephens-road-distance-focal-10m-v1',
    'grid=epsg32616-global-10m-cell-centers',
    'radii=30,90,270'
  );
  v_source_signature_sha256 := encode(
    extensions.digest(convert_to(v_source_signature,'UTF8'),'sha256'),'hex'
  );
  v_identity_sha256 := encode(
    extensions.digest(convert_to(concat_ws(
      '|',
      v_property_id::text,
      round(extensions.st_x(v_anchor)::numeric,7)::text,
      round(extensions.st_y(v_anchor)::numeric,7)::text,
      v_source_signature_sha256
    ),'UTF8'),'sha256'),'hex'
  );

  return jsonb_build_object(
    'status','available',
    'schema','road-focal-context-v1',
    'method','stephens-road-distance-focal-10m-v1',
    'evidence_class','deterministic_derived',
    'property',jsonb_build_object('slug',p_slug,'id',v_property_id),
    'evaluation_point',jsonb_build_object(
      'lon',round(extensions.st_x(v_anchor)::numeric,7),
      'lat',round(extensions.st_y(v_anchor)::numeric,7),
      'basis',case when p_lon is null then 'property_center' else 'explicit_point' end
    ),
    'road_source',jsonb_build_object(
      'slug','openstreetmap-geofabrik-access-snapshot',
      'name','OpenStreetMap Geofabrik Access Snapshot',
      'source_timestamp',v_road_source_timestamp,
      'included_feature_class','road',
      'source_substitution',
        'Stephens et al. 2024 used U.S. Census TIGER county-level road shapefiles. Farm Watch uses the centrally maintained OSM road snapshot as current road geometry; the distance/focal transformation is source-method aligned but source geometry is not identical.'
    ),
    'source_method',jsonb_build_object(
      'study','Stephens et al. 2024',
      'study_road_raster_resolution_m',10,
      'study_focal_radii_m',jsonb_build_array(30,90,270),
      'farm_watch_grid_crs','EPSG:32616',
      'farm_watch_grid_resolution_m',10,
      'farm_watch_grid_alignment','global UTM grid with cell centers at easting/northing multiples of 10 m plus 5 m',
      'aggregation','mean distance-to-nearest-road across 10 m cell centers within each circular focal radius'
    ),
    'point_distance_to_nearest_road_m',round(v_center_nearest_m::numeric,3),
    'focal_mean_distance_to_road_m',jsonb_build_object(
      '30m',jsonb_build_object('mean_m',v_r30_mean,'cell_count',v_r30_count),
      '90m',jsonb_build_object('mean_m',v_r90_mean,'cell_count',v_r90_count),
      '270m',jsonb_build_object('mean_m',v_r270_mean,'cell_count',v_r270_count)
    ),
    'source_signature_sha256',v_source_signature_sha256,
    'identity_sha256',v_identity_sha256,
    'deer_inference_performed',false,
    'coefficient_transfer_performed',false,
    'interpretation_boundary',
      'This product reproduces the physical road-distance/focal-mean covariate form only. It does not assign road selection or avoidance, infer dispersal, or transfer Missouri coefficients. Biological use still requires the FW-D14 movement-state and landscape-context gates.'
  );
end;
$$;

create or replace function public.farm_watch_resolve_road_focal_context_v1_internal(
  p_slug text,
  p_lon double precision default null,
  p_lat double precision default null
)
returns jsonb
language sql
stable
security definer
set search_path='pg_catalog'
as $$
  select farm_watch.farm_watch_resolve_road_focal_context_v1_internal(
    p_slug,p_lon,p_lat
  );
$$;

revoke all on function farm_watch.farm_watch_resolve_road_focal_context_v1_internal(
  text,double precision,double precision
) from public,anon,authenticated;
revoke all on function public.farm_watch_resolve_road_focal_context_v1_internal(
  text,double precision,double precision
) from public,anon,authenticated;

grant execute on function farm_watch.farm_watch_resolve_road_focal_context_v1_internal(
  text,double precision,double precision
) to service_role;
grant execute on function public.farm_watch_resolve_road_focal_context_v1_internal(
  text,double precision,double precision
) to service_role;

comment on function farm_watch.farm_watch_resolve_road_focal_context_v1_internal(
  text,double precision,double precision
) is
'Neutral source-method-aligned road-distance evaluator for FW-M36. Reproduces a 10 m distance-to-nearest-road grid and 30/90/270 m focal means using the canonical OSM road snapshot; performs no deer inference or coefficient transfer.';

commit;
