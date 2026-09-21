begin;

insert into ingest.sources (
  slug,
  name,
  authority,
  source_class,
  geographic_scope,
  acquisition_method,
  update_cadence,
  authority_level,
  status,
  homepage_url,
  license_notes,
  commercial_use_status,
  notes
)
values (
  'usgs-3dep-dynamic-elevation',
  'USGS 3DEP Dynamic Elevation ImageServer',
  'U.S. Geological Survey',
  'elevation_model',
  'United States',
  'USGS National Map 3DEP Dynamic Elevation ArcGIS ImageServer getSamples',
  'source-vintage dependent',
  'federal_primary',
  'active_reference',
  'https://www.usgs.gov/3d-elevation-program',
  'Public U.S. government elevation data; retain USGS 3DEP provenance and source-vintage context.',
  'public_government',
  'Farm Watch Solar Terrain v3 uses this source only as an authoritative cell-level fallback for required horizon-support samples that remain unresolved from the primary KyFromAbove Phase 3 DEM after the documented retry policy. Values are returned in meters and converted to feet before entering the common support grid.'
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

commit;
