import {
  canReadFarmWatchMaterializationArtifact,
  farmWatchPresentationCapabilities,
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

Deno.test('owner retains full landscape structure artifact access', () => {
  if (!canReadFarmWatchMaterializationArtifact('owner', 'landscape-structure-context')) {
    throw new Error('owner should retain landscape structure artifact access')
  }
  if (!farmWatchPresentationCapabilities('owner').landscape_structure_map) {
    throw new Error('owner landscape structure map capability should be true')
  }
})

Deno.test('viewer capability explicitly disables landscape structure map presentation', () => {
  const capabilities = farmWatchPresentationCapabilities('viewer')
  if (capabilities.landscape_structure_map !== false) {
    throw new Error('viewer landscape structure map capability should be false')
  }
  if (capabilities.qa_controls !== false) {
    throw new Error('viewer QA controls should remain disabled')
  }
})

Deno.test('unknown account roles fail closed', () => {
  if (normalizeFarmWatchAccountRole('view') !== null) {
    throw new Error('unknown role should not be normalized')
  }
})


Deno.test('viewer receives summaries only for new neutral fine-grid materializations', () => {
  for (const product of ['terrain-form-permeability','spatial-edge-patch-context','solar-terrain-context','solar-exposure-context']) {
    if (canReadFarmWatchMaterializationArtifact('viewer', product)) {
      throw new Error('viewer must not receive raw ' + product + ' artifact')
    }
    if (materializationPresentationMode('viewer', product) !== 'summary_only') {
      throw new Error(product + ' viewer mode must be summary_only')
    }
    if (!canReadFarmWatchMaterializationArtifact('owner', product)) {
      throw new Error('owner should retain raw ' + product + ' artifact access')
    }
  }
})
