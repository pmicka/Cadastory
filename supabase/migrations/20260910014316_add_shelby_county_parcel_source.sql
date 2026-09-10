insert into ingest.sources(
  slug,name,authority,source_class,geographic_scope,acquisition_method,update_cadence,
  authority_level,status,homepage_url,license_notes,commercial_use_status,notes,updated_at
) values (
  'shelby-county-ky-parcels-2026',
  'Shelby County KY PVA Parcels',
  'Shelby County Property Valuation Administrator / Hartman Spatial Data',
  'county_parcel_assessor',
  'Shelby County, Kentucky',
  'Public ArcGIS FeatureServer layer 0, GeoJSON query',
  'Publisher-maintained; service metadata reports data edit 2026-02-27',
  'county_authoritative',
  'active_reference',
  'https://services2.arcgis.com/VqPd1Ybcc46AvijK/ArcGIS/rest/services/Parcels_Service121324/FeatureServer/0',
  'ArcGIS item is public and PVA-attributed but publishes no explicit licenseInfo; raw-data commercial-use rights require separate confirmation.',
  'unknown',
  'Use internally as assessor/landholding evidence. Do not expose or redistribute raw parcel data as a commercial dataset until usage terms are confirmed. Name=owner; Address1=mailing line 1; City used as partial mailing locality; Location=property address. Address2/state/ZIP are retained in raw payload but not yet part of the generic owner-cluster key.',
  now()
) on conflict(slug) do update set
  name=excluded.name,authority=excluded.authority,source_class=excluded.source_class,
  geographic_scope=excluded.geographic_scope,acquisition_method=excluded.acquisition_method,
  update_cadence=excluded.update_cadence,authority_level=excluded.authority_level,status=excluded.status,
  homepage_url=excluded.homepage_url,license_notes=excluded.license_notes,
  commercial_use_status=excluded.commercial_use_status,notes=excluded.notes,updated_at=now();

insert into agriculture.parcel_owner_source_rules(
  source_id,owner_name_key,mailing_address_key,mailing_city_state_zip_key,
  property_address_key,parcel_acres_key,active,notes,updated_at
)
select id,'Name','Address1','City','Location',null,true,
  'Shelby County PVA parcel mapping. Mailing locality is city-only in v1; state/ZIP and second address line remain in raw payload. Geometry supplies parcel acreage when source acreage is absent.',now()
from ingest.sources where slug='shelby-county-ky-parcels-2026'
on conflict(source_id) do update set
  owner_name_key=excluded.owner_name_key,
  mailing_address_key=excluded.mailing_address_key,
  mailing_city_state_zip_key=excluded.mailing_city_state_zip_key,
  property_address_key=excluded.property_address_key,
  parcel_acres_key=excluded.parcel_acres_key,
  active=excluded.active,notes=excluded.notes,updated_at=now();

create or replace function ingest.collect_parcel_pages(
  p_source_slug text,
  p_start_offset integer default 0,
  p_pages integer default 1,
  p_page_size integer default 2000
)
returns table(pages_processed integer,features_fetched integer,rows_inserted integer,next_offset integer)
language plpgsql
set search_path to 'ingest','extensions','public','pg_catalog'
as $function$
declare
  v_source_id uuid;
  v_base_url text;
  v_oid_field text;
  v_page integer;
  v_pages_done integer := 0;
  v_offset integer := greatest(coalesce(p_start_offset,0),0);
  v_resp jsonb;
  v_features jsonb;
  v_feature jsonb;
  v_geom extensions.geometry;
  v_native_id text;
  v_fetched integer := 0;
  v_inserted integer := 0;
  v_this_count integer;
  v_rows integer;
begin
  if p_pages < 1 or p_pages > 10 then raise exception 'p_pages must be between 1 and 10'; end if;
  if p_page_size < 1 or p_page_size > 2000 then raise exception 'p_page_size must be between 1 and 2000'; end if;
  select id into v_source_id from ingest.sources where slug = p_source_slug;
  if v_source_id is null then raise exception 'Unknown parcel source: %', p_source_slug; end if;

  case p_source_slug
    when 'hardin-county-parcels-2023' then
      v_base_url := 'https://services7.arcgis.com/0lcDOI9cfUh0KYbz/arcgis/rest/services/HC_PLANNING_MAP_WFL1/FeatureServer/2/query?where=1%3D1&outFields=*&returnGeometry=true&outSR=4326&f=geojson'; v_oid_field := 'FID';
    when 'jefferson-county-parcels' then
      v_base_url := 'https://gis.lojic.org/maps/rest/services/LojicSolutions/OpenDataPVA/MapServer/1/query?where=1%3D1&outFields=*&returnGeometry=true&outSR=4326&f=geojson'; v_oid_field := 'OBJECTID';
    when 'fayette-county-parcels' then
      v_base_url := 'https://maps.lexingtonky.gov/lfucggis/rest/services/property/MapServer/1/query?where=1%3D1&outFields=*&returnGeometry=true&outSR=4326&f=geojson'; v_oid_field := 'OBJECTID';
    when 'shelby-county-ky-parcels-2026' then
      v_base_url := 'https://services2.arcgis.com/VqPd1Ybcc46AvijK/ArcGIS/rest/services/Parcels_Service121324/FeatureServer/0/query?where=1%3D1&outFields=*&returnGeometry=true&outSR=4326&f=geojson'; v_oid_field := 'OBJECTID'; p_page_size := least(p_page_size,1000);
    else raise exception 'Source is not enabled in closed-list parcel collector: %', p_source_slug;
  end case;

  for v_page in 1..p_pages loop
    v_resp := (extensions.http_get(v_base_url || '&resultOffset=' || v_offset || '&resultRecordCount=' || p_page_size)).content::jsonb;
    if v_resp ? 'error' then raise exception 'ArcGIS error at offset %: %', v_offset, v_resp->'error'; end if;
    v_features := coalesce(v_resp->'features','[]'::jsonb);
    v_this_count := jsonb_array_length(v_features);
    exit when v_this_count = 0;
    v_pages_done := v_pages_done + 1;
    v_fetched := v_fetched + v_this_count;
    for v_feature in select value from jsonb_array_elements(v_features) loop
      begin
        if v_feature->'geometry' is null or v_feature->'geometry'='null'::jsonb then v_geom := null;
        else v_geom := extensions.st_setsrid(extensions.st_geomfromgeojson((v_feature->'geometry')::text),4326); end if;
      exception when others then v_geom := null; end;
      v_native_id := coalesce(v_feature->'properties'->>v_oid_field,v_feature->>'id',encode(extensions.digest(v_feature::text,'sha256'),'hex'));
      insert into ingest.raw_records(source_id,source_native_id,source_url,retrieved_at,observed_at,content_hash,parser_version,parse_status,provisional_entity_type,location,within_pilot_radius,raw_payload,geometry)
      values(v_source_id,v_native_id,split_part(v_base_url,'/query?',1),now(),null,encode(extensions.digest(v_feature::text,'sha256'),'hex'),'arcgis-geojson-parcel-v1',
        case when v_geom is null then 'geometry_missing_or_parse_error' when not extensions.st_isvalid(v_geom) then 'geometry_invalid' else 'raw' end,
        'parcel',case when v_geom is null or extensions.st_isempty(v_geom) then null else extensions.st_pointonsurface(v_geom)::extensions.geography end,true,(v_feature-'geometry'),v_geom)
      on conflict(source_id,source_native_id,content_hash) do nothing;
      get diagnostics v_rows=row_count; v_inserted:=v_inserted+v_rows;
    end loop;
    v_offset:=v_offset+v_this_count;
    exit when v_this_count<p_page_size;
  end loop;
  pages_processed:=v_pages_done; features_fetched:=v_fetched; rows_inserted:=v_inserted; next_offset:=v_offset; return next;
end;
$function$;