export const FARM_WATCH_TCC_SOURCE = Object.freeze({
  key: 'external:nlcd-tcc-v2025-6',
  year: 2025,
  productVersion: 'v2025-6',
  catalogName: 'nlcd_tcc_conus_wgs84_v2025_6_20250101_20251231',
  sourceUrl:
    'https://imagery.geoplatform.gov/iipp/rest/services/Vegetation/USFS_EDW_NLCD_TCC_CONUS/ImageServer',
})

export function farmWatchTccCatalogWhere() {
  return "name = '" +
    FARM_WATCH_TCC_SOURCE.catalogName.replaceAll("'", "''") +
    "'"
}

export function farmWatchTccMosaicRule() {
  return {
    mosaicMethod: 'esriMosaicNorthwest',
    where: farmWatchTccCatalogWhere(),
  }
}
