insert into ingest.sources(
  slug,name,authority,source_class,geographic_scope,acquisition_method,update_cadence,
  authority_level,status,homepage_url,license_notes,commercial_use_status,notes,updated_at
) values (
  'usda-nrcs-geodata-cg-soils-ssurgo',
  'USDA NRCS Geospatial Data Gateway / SSURGO Map Unit Polygons',
  'USDA Natural Resources Conservation Service',
  'government_dataset',
  'United States',
  'USDA FPAC ArcGIS FeatureServer cg_soils MUPolygon service',
  'NRCS service metadata states annual SSURGO refresh, generally around October 1',
  'federal_authoritative',
  'active',
  'https://apps.geo.fpac.usda.gov/nrcs-geodata/rest/services/soils/cg_soils/FeatureServer',
  'U.S. federal soil survey data; preserve map-scale and interpretation limitations',
  'government_public_data',
  'Farm Watch clips current NRCS SSURGO map-unit polygons to an authenticated private property boundary. Geometry is soil-survey reference mapping, not a legal parcel survey or site-specific engineering investigation.',
  now()
) on conflict(slug) do update set
  name=excluded.name,authority=excluded.authority,source_class=excluded.source_class,
  geographic_scope=excluded.geographic_scope,acquisition_method=excluded.acquisition_method,
  update_cadence=excluded.update_cadence,authority_level=excluded.authority_level,status=excluded.status,
  homepage_url=excluded.homepage_url,license_notes=excluded.license_notes,
  commercial_use_status=excluded.commercial_use_status,notes=excluded.notes,updated_at=now();

create table if not exists farm_watch.property_soil_map_units_v1 (
  property_id uuid not null references farm_watch.properties(id) on delete cascade,
  geometry_source_id uuid not null references ingest.sources(id),
  attribute_source_id uuid not null references ingest.sources(id),
  mukey text not null,
  musym text,
  muname text,
  mukind text,
  farmland_class text,
  non_irrigated_capability integer,
  dominant_component_key text,
  dominant_component_name text,
  dominant_component_pct numeric,
  representative_slope_pct numeric,
  drainage_class text,
  hydrologic_group text,
  dominant_component_drainage_class text,
  dominant_component_hydrologic_group text,
  hydric_rating text,
  available_water_storage_0_100_mm numeric,
  parcel_acres numeric not null,
  parcel_pct numeric not null,
  clipped_geometry extensions.geometry(MultiPolygon,4326) not null,
  attribute_status text not null default 'available',
  http_status integer,
  last_error text,
  source_payload jsonb not null default '{}'::jsonb,
  source_retrieved_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(property_id,mukey)
);

create index if not exists property_soil_map_units_v1_geom_idx
  on farm_watch.property_soil_map_units_v1 using gist(clipped_geometry);
create index if not exists property_soil_map_units_v1_mukey_idx
  on farm_watch.property_soil_map_units_v1(mukey);

alter table farm_watch.property_soil_map_units_v1 enable row level security;
revoke all on farm_watch.property_soil_map_units_v1 from public, anon, authenticated;
grant select,insert,update,delete on farm_watch.property_soil_map_units_v1 to service_role;

comment on table farm_watch.property_soil_map_units_v1 is
'Owner-only cached NRCS SSURGO map-unit polygons clipped to Farm Watch property boundaries. Parcel acreage/share are geometry-derived; soil attributes are NRCS map-unit/component interpretations and are not site-specific laboratory measurements.';

create or replace function public.farm_watch_refresh_soils_v1_internal(p_slug text)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog'
as $function$
declare
  v_property_id uuid;
  v_boundary extensions.geometry;
  v_xmin double precision;
  v_ymin double precision;
  v_xmax double precision;
  v_ymax double precision;
  v_property_area_m2 double precision;
  v_geometry_source_id uuid;
  v_attribute_source_id uuid;
  v_url text;
  v_status integer;
  v_content text;
  v_geojson jsonb;
  v_feature jsonb;
  v_props jsonb;
  v_geom extensions.geometry;
  v_clip extensions.geometry;
  v_mukey text;
  v_query text;
  v_sda_status integer;
  v_sda_content text;
  v_sda_json jsonb;
  v_sda_table jsonb;
  v_row jsonb;
  v_seen text[] := array[]::text[];
  v_refreshed integer := 0;
  v_attribute_failures integer := 0;
  v_started timestamptz := clock_timestamp();
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service_role required';
  end if;

  select p.id,p.boundary,
         extensions.st_xmin(extensions.st_envelope(p.boundary)),
         extensions.st_ymin(extensions.st_envelope(p.boundary)),
         extensions.st_xmax(extensions.st_envelope(p.boundary)),
         extensions.st_ymax(extensions.st_envelope(p.boundary)),
         extensions.st_area(p.boundary::extensions.geography)
  into v_property_id,v_boundary,v_xmin,v_ymin,v_xmax,v_ymax,v_property_area_m2
  from farm_watch.properties p
  where p.slug=p_slug and p.status='active' and p.boundary is not null
  limit 1;

  if v_property_id is null then
    return jsonb_build_object('status','unavailable','reason','property boundary unavailable');
  end if;

  select id into v_geometry_source_id from ingest.sources where slug='usda-nrcs-geodata-cg-soils-ssurgo';
  select id into v_attribute_source_id from ingest.sources where slug='usda-nrcs-soil-data-access-ssurgo';
  if v_geometry_source_id is null or v_attribute_source_id is null then
    raise exception 'NRCS SSURGO sources are not registered';
  end if;

  v_url := format(
    'https://apps.geo.fpac.usda.gov/nrcs-geodata/rest/services/soils/cg_soils/FeatureServer/0/query?where=1%%3D1&geometry=%s,%s,%s,%s&geometryType=esriGeometryEnvelope&inSR=4326&spatialRel=esriSpatialRelIntersects&outFields=areasymbol,muname,mukind,musym,mukey,nationalmusym,farmlndcl,nirrcapcl&returnGeometry=true&outSR=4326&f=geojson',
    v_xmin,v_ymin,v_xmax,v_ymax
  );

  select r.status,r.content into v_status,v_content
  from extensions.http_get(v_url::varchar) r;

  if v_status <> 200 then
    return jsonb_build_object('status','unavailable','reason','NRCS geometry request failed','http_status',v_status);
  end if;

  begin
    v_geojson := v_content::jsonb;
  exception when others then
    return jsonb_build_object('status','unavailable','reason','NRCS geometry response was not JSON');
  end;

  for v_feature in select value from jsonb_array_elements(coalesce(v_geojson->'features','[]'::jsonb))
  loop
    begin
      v_props := coalesce(v_feature->'properties','{}'::jsonb);
      v_mukey := nullif(v_props->>'mukey','');
      if v_mukey is null or v_feature->'geometry' is null then continue; end if;

      v_geom := extensions.st_setsrid(extensions.st_geomfromgeojson((v_feature->'geometry')::text),4326);
      if not extensions.st_intersects(v_geom,v_boundary) then continue; end if;

      v_clip := extensions.st_multi(
        extensions.st_collectionextract(extensions.st_intersection(v_geom,v_boundary),3)
      );
      if v_clip is null or extensions.st_isempty(v_clip) then continue; end if;

      v_seen := array_append(v_seen,v_mukey);
      v_query := format(
        'SELECT TOP 1 m.mukey,m.muname,a.aws0100wta,a.drclassdcd,a.hydgrpdcd,c.cokey,c.compname,c.comppct_r,c.slope_r,c.drainagecl,c.hydgrp,c.hydricrating FROM mapunit m LEFT JOIN muaggatt a ON a.mukey=m.mukey LEFT JOIN component c ON c.mukey=m.mukey WHERE m.mukey=%L ORDER BY ISNULL(c.comppct_r,0) DESC,c.cokey',
        v_mukey
      );

      select r.status,r.content into v_sda_status,v_sda_content
      from extensions.http_post(
        'https://SDMDataAccess.sc.egov.usda.gov/Tabular/post.rest'::varchar,
        jsonb_build_object('query',v_query,'format','JSON+COLUMNNAME')
      ) r;

      v_sda_json := null;
      v_sda_table := null;
      v_row := null;
      if v_sda_status=200 then
        begin
          v_sda_json := v_sda_content::jsonb;
          v_sda_table := v_sda_json->'Table';
          if v_sda_table is not null and jsonb_array_length(v_sda_table)>=2 then
            v_row := v_sda_table->1;
          end if;
        exception when others then
          v_row := null;
        end;
      end if;

      insert into farm_watch.property_soil_map_units_v1(
        property_id,geometry_source_id,attribute_source_id,mukey,musym,muname,mukind,
        farmland_class,non_irrigated_capability,dominant_component_key,dominant_component_name,
        dominant_component_pct,representative_slope_pct,drainage_class,hydrologic_group,
        dominant_component_drainage_class,dominant_component_hydrologic_group,hydric_rating,
        available_water_storage_0_100_mm,parcel_acres,parcel_pct,clipped_geometry,
        attribute_status,http_status,last_error,source_payload,source_retrieved_at,updated_at
      ) values (
        v_property_id,v_geometry_source_id,v_attribute_source_id,v_mukey,
        nullif(v_props->>'musym',''),
        coalesce(nullif(v_row->>1,''),nullif(v_props->>'muname','')),
        nullif(v_props->>'mukind',''),nullif(v_props->>'farmlndcl',''),
        nullif(v_props->>'nirrcapcl','')::integer,
        nullif(v_row->>5,''),nullif(v_row->>6,''),nullif(v_row->>7,'')::numeric,
        nullif(v_row->>8,'')::numeric,
        nullif(v_row->>3,''),nullif(v_row->>4,''),
        nullif(v_row->>9,''),nullif(v_row->>10,''),nullif(v_row->>11,''),
        case when nullif(v_row->>2,'') is null then null else (v_row->>2)::numeric*10 end,
        extensions.st_area(v_clip::extensions.geography)/4046.8564224,
        case when v_property_area_m2>0 then extensions.st_area(v_clip::extensions.geography)/v_property_area_m2*100 else 0 end,
        v_clip::extensions.geometry(MultiPolygon,4326),
        case when v_row is null then 'unavailable' else 'available' end,
        v_sda_status,
        case when v_row is null then left(coalesce(v_sda_content,'NRCS Soil Data Access returned no usable row'),1000) else null end,
        jsonb_build_object(
          'geometry_query_version','farm_watch_ssurgo_polygon_v1',
          'geometry_properties',v_props,
          'attribute_query_version','farm_watch_ssurgo_mapunit_component_v1',
          'attribute_response',coalesce(v_sda_json,'{}'::jsonb)
        ),
        now(),now()
      )
      on conflict(property_id,mukey) do update set
        geometry_source_id=excluded.geometry_source_id,
        attribute_source_id=excluded.attribute_source_id,
        musym=excluded.musym,muname=excluded.muname,mukind=excluded.mukind,
        farmland_class=excluded.farmland_class,
        non_irrigated_capability=excluded.non_irrigated_capability,
        dominant_component_key=excluded.dominant_component_key,
        dominant_component_name=excluded.dominant_component_name,
        dominant_component_pct=excluded.dominant_component_pct,
        representative_slope_pct=excluded.representative_slope_pct,
        drainage_class=excluded.drainage_class,
        hydrologic_group=excluded.hydrologic_group,
        dominant_component_drainage_class=excluded.dominant_component_drainage_class,
        dominant_component_hydrologic_group=excluded.dominant_component_hydrologic_group,
        hydric_rating=excluded.hydric_rating,
        available_water_storage_0_100_mm=excluded.available_water_storage_0_100_mm,
        parcel_acres=excluded.parcel_acres,parcel_pct=excluded.parcel_pct,
        clipped_geometry=excluded.clipped_geometry,
        attribute_status=excluded.attribute_status,http_status=excluded.http_status,last_error=excluded.last_error,
        source_payload=excluded.source_payload,source_retrieved_at=excluded.source_retrieved_at,updated_at=now();

      v_refreshed := v_refreshed+1;
      if v_row is null then v_attribute_failures := v_attribute_failures+1; end if;
    exception when others then
      v_attribute_failures := v_attribute_failures+1;
    end;
  end loop;

  if coalesce(array_length(v_seen,1),0)>0 then
    delete from farm_watch.property_soil_map_units_v1 s
    where s.property_id=v_property_id and not (s.mukey=any(v_seen));
  end if;

  return jsonb_build_object(
    'status',case when v_refreshed>0 then 'available' else 'unavailable' end,
    'map_units_refreshed',v_refreshed,
    'attribute_failures',v_attribute_failures,
    'started_at',v_started,
    'finished_at',clock_timestamp()
  );
end;
$function$;

revoke all on function public.farm_watch_refresh_soils_v1_internal(text) from public, anon, authenticated;
grant execute on function public.farm_watch_refresh_soils_v1_internal(text) to service_role;

create or replace function public.farm_watch_get_soils_v1_internal(p_slug text)
returns jsonb
language sql
stable security definer
set search_path='pg_catalog'
as $function$
  with property as (
    select p.id from farm_watch.properties p
    where p.slug=p_slug and p.status='active'
    limit 1
  ), units as (
    select s.* from farm_watch.property_soil_map_units_v1 s
    join property p on p.id=s.property_id
  ), summary as (
    select count(*)::integer as map_unit_count,
           coalesce(sum(parcel_acres),0) as covered_acres,
           coalesce(sum(parcel_pct),0) as covered_pct,
           max(source_retrieved_at) as retrieved_at
    from units
  )
  select jsonb_build_object(
    'status',case when summary.map_unit_count>0 then 'available' else 'unavailable' end,
    'feature_collection',jsonb_build_object(
      'type','FeatureCollection',
      'features',coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'type','Feature',
            'id',u.mukey,
            'geometry',extensions.st_asgeojson(u.clipped_geometry,6)::jsonb,
            'properties',jsonb_strip_nulls(jsonb_build_object(
              'mukey',u.mukey,'musym',u.musym,'muname',u.muname,'mukind',u.mukind,
              'farmland_class',u.farmland_class,'non_irrigated_capability',u.non_irrigated_capability,
              'dominant_component_name',u.dominant_component_name,
              'dominant_component_pct',u.dominant_component_pct,
              'representative_slope_pct',u.representative_slope_pct,
              'drainage_class',u.drainage_class,'hydrologic_group',u.hydrologic_group,
              'hydric_rating',u.hydric_rating,
              'available_water_storage_0_100_mm',u.available_water_storage_0_100_mm,
              'parcel_acres',round(u.parcel_acres,2),'parcel_pct',round(u.parcel_pct,1),
              'attribute_status',u.attribute_status
            ))
          ) order by u.parcel_acres desc,u.mukey
        ) from units u
      ),'[]'::jsonb)
    ),
    'summary',jsonb_build_object(
      'map_unit_count',summary.map_unit_count,
      'covered_acres',round(summary.covered_acres,2),
      'covered_pct',round(summary.covered_pct,1),
      'retrieved_at',summary.retrieved_at,
      'source','USDA NRCS SSURGO / Soil Data Access'
    )
  )
  from summary;
$function$;

revoke all on function public.farm_watch_get_soils_v1_internal(text) from public, anon, authenticated;
grant execute on function public.farm_watch_get_soils_v1_internal(text) to service_role;
