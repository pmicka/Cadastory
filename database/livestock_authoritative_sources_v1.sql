insert into ingest.sources(
  slug,name,authority,source_class,geographic_scope,acquisition_method,
  update_cadence,authority_level,status,homepage_url,commercial_use_status,notes
) values
(
  'kentucky-eec-cafo-afo-esearch',
  'Kentucky EEC AFO/CAFO Permits and Annual Reporting',
  'Kentucky Energy and Environment Cabinet',
  'regulated_agricultural_facility',
  'Kentucky',
  'EEC eSearch issued approvals/documents and KPDES/CAFO reporting records',
  'weekly',
  'state_authoritative',
  'active_reference',
  'https://eec.ky.gov/Environmental-Protection/Water/PermitCert/KPDES/Pages/AFOs-and-CAFOs.aspx',
  'public_record_review_required',
  'Authoritative Kentucky AFO/CAFO evidence lane. CAFO annual reporting includes animal type/count data; eSearch exposes permit/approval records and downloadable documents. Use facility-specific records only; do not infer smaller unpermitted farm counts from regulatory thresholds.'
),
(
  'ohio-epa-npdes-cafo',
  'Ohio EPA Concentrated Animal Feeding Operations (NPDES Permits)',
  'Ohio Environmental Protection Agency',
  'regulated_agricultural_facility',
  'Ohio',
  'Ohio EPA ArcGIS NPDES CAFO feature service plus linked permit documents',
  'weekly',
  'state_authoritative',
  'active_reference',
  'https://geo.epa.ohio.gov/arcgis/rest/services/SurfaceWater/NPDES/MapServer/5',
  'public_record_review_required',
  'Authoritative Ohio CAFO facility discovery layer with coordinates, facility identity, permit status and linked permit records. Species/capacity should be extracted only when documented in facility fields or linked permit materials.'
)
on conflict(slug) do update set
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
