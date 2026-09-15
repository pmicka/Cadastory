-- Reuse the generic bounded ArcGIS point-owner provider for Daviess County.
-- The public Schneider parcel layer exposes Name + PARCEL_ID and supports
-- spatial queries. Ownership remains property-responsibility evidence only.

insert into ingest.sources(
  slug,name,authority,source_class,geographic_scope,acquisition_method,
  update_cadence,authority_level,status,homepage_url,commercial_use_status,notes,updated_at
) values (
  'daviess-county-ky-parcels-live',
  'Daviess County KY PVA Parcels',
  'Daviess County Property Valuation Administrator / Schneider Geospatial',
  'county_parcel_assessor',
  'Daviess County, Kentucky',
  'Public ArcGIS MapServer point query',
  'publisher-maintained live service',
  'county_authoritative',
  'active_reference',
  'https://wfs.schneidercorp.com/arcgis/rest/services/DaviessCountyKY_WFS/MapServer/0',
  'unknown',
  'Public parcel layer exposes PARCEL_ID and Name. Scout queries only current opportunity points; it does not bulk-mirror or redistribute the county dataset. Ownership is responsibility evidence only and does not imply management, operation, or purchasing authority.',
  now()
)
on conflict(slug) do update set
  name=excluded.name,authority=excluded.authority,source_class=excluded.source_class,
  geographic_scope=excluded.geographic_scope,acquisition_method=excluded.acquisition_method,
  update_cadence=excluded.update_cadence,authority_level=excluded.authority_level,
  status=excluded.status,homepage_url=excluded.homepage_url,
  commercial_use_status=excluded.commercial_use_status,notes=excluded.notes,updated_at=now();

insert into research.responsible_party_source_profiles(
  profile_key,state_code,county_name,provider_kind,parcel_source_slug,
  owner_lookup_url_template,source_authority,source_url,active,priority,attributes
) values (
  'ky_daviess_arcgis_owner','KY','Daviess','arcgis_point_owner','daviess-county-ky-parcels-live',
  'https://wfs.schneidercorp.com/arcgis/rest/services/DaviessCountyKY_WFS/MapServer/0/query',
  'Daviess County Property Valuation Administrator / Schneider Geospatial',
  'https://wfs.schneidercorp.com/arcgis/rest/services/DaviessCountyKY_WFS/MapServer/0',
  true,20,
  jsonb_build_object(
    'eligible_source_kinds',jsonb_build_array('exterior_cleaning'),
    'owner_field','Name','parcel_id_field','PARCEL_ID','query_sr',4326,
    'identity_scope','property_owner_only','query_mode','point_intersection',
    'buyer_authority_not_implied',true,'property_manager_not_implied',true,
    'operator_not_implied',true,'bulk_mirror',false
  )
)
on conflict(profile_key) do update set
  state_code=excluded.state_code,county_name=excluded.county_name,
  provider_kind=excluded.provider_kind,parcel_source_slug=excluded.parcel_source_slug,
  owner_lookup_url_template=excluded.owner_lookup_url_template,
  source_authority=excluded.source_authority,source_url=excluded.source_url,
  active=excluded.active,priority=excluded.priority,attributes=excluded.attributes,updated_at=now();

do $$
declare v_attrs jsonb;
begin
  select attributes into v_attrs from research.responsible_party_source_profiles
  where profile_key='ky_daviess_arcgis_owner';
  if v_attrs is null
     or not pg_catalog.jsonb_exists(v_attrs->'eligible_source_kinds','exterior_cleaning')
     or v_attrs->>'owner_field' <> 'Name'
     or v_attrs->>'parcel_id_field' <> 'PARCEL_ID' then
    raise exception 'Daviess ArcGIS owner provider contract regression';
  end if;
end
$$;
