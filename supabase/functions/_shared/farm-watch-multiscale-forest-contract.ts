export const FARM_WATCH_MULTISCALE_FOREST_CONTEXT_PRODUCT = Object.freeze({
  key: 'multiscale-forest-context',
  algorithmVersion: 'stephens-forest-focal-context-v1',
  outputSchemaVersion: 'multiscale-forest-context-v1',
  sourceSlug: 'esri-sentinel2-10m-lulc',
  sourceName: 'Sentinel-2 10m Land Use/Land Cover Time Series',
  sourceResolutionM: 10,
  forestClassValue: 2,
  builtClassValue: 7,
  cloudClassValue: 10,
  focalRadiiM: Object.freeze([30, 90, 270] as const),
  sourceSubstitution:
    'Stephens et al. 2024 used a Dynamic World 10 m 2015-2019 dominant composite. Farm Watch uses the open CC-BY-4.0 Impact Observatory/Esri/Microsoft annual Sentinel-2 10 m LULC product and preserves the same 10 m physical support, tree-class proportion, built-excluded forest/nonforest edge-density form, and 30/90/270 m focal radii.',
})

export type FarmWatchForestFocalMetric = {
  radius_m: 30 | 90 | 270
  valid_landcover_cell_count: number
  forest_cell_count: number
  forest_proportion: number
  forest_percent: number
  edge_metric_cell_count: number
  forest_edge_length_m: number
  forest_edge_density_m_per_ha: number
}

export function validateFarmWatchMultiscaleForestContext(value: any) {
  const p = FARM_WATCH_MULTISCALE_FOREST_CONTEXT_PRODUCT
  if (
    value?.schema !== p.outputSchemaVersion ||
    value?.method !== p.algorithmVersion ||
    value?.evidence_class !== 'deterministic_derived' ||
    value?.source?.slug !== p.sourceSlug ||
    Number(value?.source?.spatial_resolution_m) !== p.sourceResolutionM ||
    Number(value?.source?.forest_class_value) !== p.forestClassValue ||
    Number(value?.source?.built_class_value) !== p.builtClassValue ||
    value?.deer_inference_performed !== false ||
    value?.coefficient_transfer_performed !== false ||
    !Array.isArray(value?.focal_metrics) ||
    value.focal_metrics.length !== p.focalRadiiM.length
  ) return false

  const radii = value.focal_metrics
    .map((row: any) => Number(row.radius_m))
    .sort((a: number, b: number) => a - b)
  if (JSON.stringify(radii) !== JSON.stringify([...p.focalRadiiM])) return false

  return value.focal_metrics.every((row: any) =>
    Number.isInteger(Number(row.valid_landcover_cell_count)) &&
    Number(row.valid_landcover_cell_count) > 0 &&
    Number.isInteger(Number(row.forest_cell_count)) &&
    Number(row.forest_cell_count) >= 0 &&
    Number.isFinite(Number(row.forest_proportion)) &&
    Number(row.forest_proportion) >= 0 &&
    Number(row.forest_proportion) <= 1 &&
    Number.isInteger(Number(row.edge_metric_cell_count)) &&
    Number(row.edge_metric_cell_count) > 0 &&
    Number.isFinite(Number(row.forest_edge_length_m)) &&
    Number(row.forest_edge_length_m) >= 0 &&
    Number.isFinite(Number(row.forest_edge_density_m_per_ha)) &&
    Number(row.forest_edge_density_m_per_ha) >= 0
  )
}
