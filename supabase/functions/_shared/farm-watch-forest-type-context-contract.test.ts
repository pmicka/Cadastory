import {
  FARM_WATCH_FOREST_TYPE_CONTEXT_PRODUCT,
  validateForestTypeContext,
} from './farm-watch-forest-type-context-contract.ts'

function assert(condition: unknown, message = 'assertion failed'): asserts condition {
  if (!condition) throw new Error(message)
}

function scope() {
  return {
    modeled_cell_count: 100,
    tree_cell_count: 80,
    hardwood_cell_count: 70,
    hardwood_cell_share_percent: 70,
    hardwood_share_of_tree_cells_percent: 87.5,
    hardwood_canopy_equivalent_percent_of_area: 52,
    mean_tree_cover_percent_within_hardwood_cells: 74.285714,
  }
}

Deno.test('M43 forest type context preserves source substitution and abstention boundaries', () => {
  const p = FARM_WATCH_FOREST_TYPE_CONTEXT_PRODUCT
  const value = {
    schema: p.outputSchemaVersion,
    method: p.algorithmVersion,
    status: 'available',
    evidence_class: p.semanticEvidenceClass,
    source: {
      authority: p.sourceAuthority,
      product: p.sourceProduct,
      landfire_version: 2024,
      spatial_resolution_m: 30,
      native_crs: 'EPSG:5070',
      evt_service_metadata_sha256: 'a'.repeat(64),
      evc_service_metadata_sha256: 'b'.repeat(64),
      evt_attribute_table_sha256: 'c'.repeat(64),
      evc_attribute_table_sha256: 'd'.repeat(64),
    },
    source_alignment: {
      source_study: 'Darlington et al. 2022, Scientific Reports 12:1072',
      source_measurement: 'Alberta Vegetation Inventory percent crown closure of dominant overstorey species',
      farm_watch_alignment: 'calibrated_proxy',
    },
    summary: {
      scopes: {
        property: scope(),
        local_500m: scope(),
        landscape_1500m: scope(),
        broad_3000m: scope(),
      },
    },
    source_selection: {
      probe_basis: 'property_center_internal_source_health_only',
      pixel_interpretation_exposed: false,
    },
    intactness_metric_performed: false,
    behavioral_inference_performed: false,
    coefficient_transfer_performed: false,
    scoring_performed: false,
    interpretation_boundary: 'neutral',
  }

  assert(validateForestTypeContext(value))
  assert(!validateForestTypeContext({ ...value, intactness_metric_performed: true }))
  assert(!validateForestTypeContext({
    ...value,
    source_alignment: { ...value.source_alignment, farm_watch_alignment: 'derived_equivalent' },
  }))
})
