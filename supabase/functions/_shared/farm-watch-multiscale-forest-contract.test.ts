import {
  FARM_WATCH_MULTISCALE_FOREST_CONTEXT_PRODUCT,
  validateFarmWatchMultiscaleForestContext,
} from './farm-watch-multiscale-forest-contract.ts'

function assert(condition: unknown, message = 'assertion failed'): asserts condition {
  if (!condition) throw new Error(message)
}

Deno.test('M35 forest context preserves 10 m support and 30/90/270 m source scales', () => {
  const p = FARM_WATCH_MULTISCALE_FOREST_CONTEXT_PRODUCT
  const value = {
    schema: p.outputSchemaVersion,
    method: p.algorithmVersion,
    evidence_class: 'deterministic_derived',
    source: {
      slug: p.sourceSlug,
      spatial_resolution_m: 10,
      forest_class_value: 2,
      built_class_value: 7,
    },
    focal_metrics: [
      {
        radius_m: 30,
        valid_landcover_cell_count: 28,
        forest_cell_count: 18,
        forest_proportion: 18 / 28,
        forest_percent: 100 * 18 / 28,
        edge_metric_cell_count: 27,
        forest_edge_length_m: 60,
        forest_edge_density_m_per_ha: 222.222,
      },
      {
        radius_m: 90,
        valid_landcover_cell_count: 254,
        forest_cell_count: 190,
        forest_proportion: 190 / 254,
        forest_percent: 100 * 190 / 254,
        edge_metric_cell_count: 250,
        forest_edge_length_m: 280,
        forest_edge_density_m_per_ha: 112,
      },
      {
        radius_m: 270,
        valid_landcover_cell_count: 2288,
        forest_cell_count: 1700,
        forest_proportion: 1700 / 2288,
        forest_percent: 100 * 1700 / 2288,
        edge_metric_cell_count: 2250,
        forest_edge_length_m: 1200,
        forest_edge_density_m_per_ha: 53.333,
      },
    ],
    deer_inference_performed: false,
    coefficient_transfer_performed: false,
  }

  assert(validateFarmWatchMultiscaleForestContext(value))
  assert(!validateFarmWatchMultiscaleForestContext({
    ...value,
    source: { ...value.source, spatial_resolution_m: 30 },
  }))
  assert(!validateFarmWatchMultiscaleForestContext({
    ...value,
    focal_metrics: value.focal_metrics.slice(1),
  }))
})
