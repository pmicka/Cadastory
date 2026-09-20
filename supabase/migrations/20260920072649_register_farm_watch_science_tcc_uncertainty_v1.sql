insert into ingest.sources (
  slug, name, authority, source_class, geographic_scope, acquisition_method,
  update_cadence, authority_level, status, homepage_url, license_notes,
  commercial_use_status, notes
)
values
(
  'science-tree-canopy-cover-2025',
  'National Annual Tree Canopy Cover 2025 (Science TCC CONUS v2025-6)',
  'USDA Forest Service / Multi-Resolution Land Characteristics Consortium',
  'tree_canopy_cover_model_raster',
  'Conterminous United States',
  'Public USFS ArcGIS ImageServer; 30 m annual Science TCC direct model output selected with the 2025 mosaic catalog filter; Farm Watch computes exact-property histogram summaries without copying source pixels into Postgres',
  'annual',
  'federal_authoritative_modeled',
  'active_reference',
  'https://www.mrlc.gov/data/type/science-tree-canopy-cover',
  'Public U.S. Government geospatial product. Retain USDA Forest Service/MRLC product attribution, product version/year, Science-model semantics, and source caveats.',
  'allowed',
  'Direct annual random-forest model output for percent tree canopy cover. Pair with the matching Science TCC standard-error raster for uncertainty analysis. Do not substitute this product for field-measured canopy or infer habitat quality or animal use from it.'
),
(
  'science-tree-canopy-cover-se-2025',
  'National Annual Tree Canopy Cover 2025 (Science TCC Standard Error CONUS v2025-6)',
  'USDA Forest Service / Multi-Resolution Land Characteristics Consortium',
  'tree_canopy_cover_model_uncertainty_raster',
  'Conterminous United States',
  'Public USFS ArcGIS ImageServer; 30 m annual Science TCC standard-error raster selected with the 2025 mosaic catalog filter; published standard-error integer values are scaled by 100 and Farm Watch converts them back to canopy percentage points',
  'annual',
  'federal_authoritative_modeled',
  'active_reference',
  'https://www.mrlc.gov/data/type/science-tree-canopy-cover-standard-error',
  'Public U.S. Government geospatial product. Retain USDA Forest Service/MRLC product attribution, product version/year, standard-error scaling semantics, and source caveats.',
  'allowed',
  'Uncertainty companion to the Science TCC random-forest output. Values 0–approximately 4500 represent standard error multiplied by 100; 65534 is the non-processing mask and 65535 background. This is not a confidence interval for the post-processed NLCD TCC layer or field measurement error.'
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
