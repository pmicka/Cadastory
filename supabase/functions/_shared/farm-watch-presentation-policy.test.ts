import {
  canReadFarmWatchMaterializationArtifact,
  farmWatchPresentationCapabilities,
  farmWatchPresentationProfile,
  materializationPresentationMode,
  normalizeFarmWatchAccountRole,
} from './farm-watch-presentation-policy.ts'

Deno.test('viewer cannot receive the fine landscape structure artifact', () => {
  if (canReadFarmWatchMaterializationArtifact('viewer', 'landscape-structure-context')) {
    throw new Error('viewer must not receive landscape structure artifact')
  }
  if (materializationPresentationMode('viewer', 'landscape-structure-context') !== 'summary_only') {
    throw new Error('viewer landscape structure mode must be summary_only')
  }
})

Deno.test('viewer can still receive ordinary materialization artifacts', () => {
  if (!canReadFarmWatchMaterializationArtifact('viewer', 'terrain')) {
    throw new Error('viewer terrain artifact behavior should remain unchanged')
  }
})

Deno.test('owner and admin use the technical presentation profile', () => {
  for (const role of ['owner', 'admin'] as const) {
    if (farmWatchPresentationProfile(role) !== 'technical') {
      throw new Error(role + ' should use technical presentation')
    }
    if (!canReadFarmWatchMaterializationArtifact(role, 'landscape-structure-context')) {
      throw new Error(role + ' should retain landscape structure artifact access')
    }
    const capabilities = farmWatchPresentationCapabilities(role)
    if (!capabilities.qa_controls || !capabilities.landscape_structure_map) {
      throw new Error(role + ' should retain technical Farm Watch capabilities')
    }
    if (!capabilities.technical_evidence || capabilities.guided_interpretation) {
      throw new Error(role + ' presentation capabilities are inconsistent')
    }
  }
})

Deno.test('viewer uses guided interpretation without technical controls', () => {
  if (farmWatchPresentationProfile('viewer') !== 'guided') {
    throw new Error('viewer should use guided presentation')
  }
  const capabilities = farmWatchPresentationCapabilities('viewer')
  if (capabilities.presentation_profile !== 'guided') {
    throw new Error('viewer presentation profile should be guided')
  }
  if (capabilities.guided_interpretation !== true) {
    throw new Error('viewer guided interpretation capability should be true')
  }
  if (
    capabilities.qa_controls !== false ||
    capabilities.landscape_structure_map !== false ||
    capabilities.technical_evidence !== false ||
    capabilities.field_evidence_table !== false
  ) {
    throw new Error('viewer technical capabilities must remain disabled')
  }
})

Deno.test('unknown account roles fail closed', () => {
  if (normalizeFarmWatchAccountRole('view') !== null) {
    throw new Error('unknown role should not be normalized')
  }
})

Deno.test('admin is an explicit role, not an owner alias', () => {
  if (normalizeFarmWatchAccountRole('admin') !== 'admin') {
    throw new Error('admin should normalize as its own account role')
  }
})

Deno.test('viewer receives summaries only for neutral fine-grid materializations', () => {
  for (const product of [
    'terrain-form-permeability',
    'spatial-edge-patch-context',
    'solar-terrain-context',
    'solar-exposure-context',
    'thermal-exposure-context',
    'horizontal-visibility-context',
  ]) {
    if (canReadFarmWatchMaterializationArtifact('viewer', product)) {
      throw new Error('viewer must not receive raw ' + product + ' artifact')
    }
    if (materializationPresentationMode('viewer', product) !== 'summary_only') {
      throw new Error(product + ' viewer mode must be summary_only')
    }
    for (const role of ['owner', 'admin'] as const) {
      if (!canReadFarmWatchMaterializationArtifact(role, product)) {
        throw new Error(role + ' should retain raw ' + product + ' artifact access')
      }
    }
  }
})
