insert into ingest.sources (
  slug,name,authority,source_class,geographic_scope,acquisition_method,update_cadence,
  authority_level,status,homepage_url,commercial_use_status,notes
) values (
  'kyfromabove-phase3-dem',
  'KyFromAbove Phase 3 Digital Elevation Model',
  'Kentucky Division of Geographic Information / KyFromAbove',
  'elevation_model',
  'Kentucky',
  'ArcGIS ImageServer; exact parcel polygon passed to computeStatisticsHistograms for geometry-clipped elevation statistics',
  'source-vintage dependent',
  'state',
  'active_reference',
  'https://kyraster.ky.gov/arcgis/rest/services/ElevationServices/Ky_DEM_KYAPED_2FT_Phase3_WGS84WM/ImageServer',
  'reviewed_reference',
  'Farm Watch canonical parcel elevation source. Geometry-clipped raster statistics supersede coarse grid-sample extrema for displayed property min/max/relief; grid sampling remains for contours, flow, and slope derivatives.'
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
  commercial_use_status=excluded.commercial_use_status,
  notes=excluded.notes,
  updated_at=now();
