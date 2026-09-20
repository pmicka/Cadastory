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
  'nlcd-tree-canopy-cover-2025',
  'National Annual Tree Canopy Cover 2025 (NLCD TCC CONUS v2025-6)',
  'USDA Forest Service / Multi-Resolution Land Characteristics Consortium',
  'tree_canopy_cover_raster',
  'Conterminous United States',
  'Public USFS ArcGIS ImageServer; 30 m NLCD percent-tree-canopy raster selected with the 2025 mosaic catalog filter; Farm Watch computes exact-property histogram summaries without copying source pixels into Postgres',
  'annual',
  'federal_authoritative_modeled',
  'active_reference',
  'https://www.mrlc.gov/data/type/nlcd-tree-canopy-cover',
  'Public U.S. Government geospatial product. Retain USDA Forest Service/MRLC product attribution, version/year, modeled-data semantics, and source-specific caveats.',
  'allowed',
  '2025 NLCD TCC values represent modeled percent tree canopy cover at 30 m after NLCD post-processing. Use as canopy context, not as field-measured canopy, species composition, understory density, mast availability, habitat quality, bedding cover, or animal-use evidence.'
)
on conflict (slug) do update set
  name = excluded.name,
  authority = excluded.authority,
  source_class = excluded.source_class,
  geographic_scope = excluded.geographic_scope,
  acquisition_method = excluded.acquisition_method,
  update_cadence = excluded.update_cadence,
  authority_level = excluded.authority_level,
  status = excluded.status,
  homepage_url = excluded.homepage_url,
  license_notes = excluded.license_notes,
  commercial_use_status = excluded.commercial_use_status,
  notes = excluded.notes,
  updated_at = now();
