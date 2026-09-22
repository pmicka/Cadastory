import {
  FARM_WATCH_MAST_CAPACITY_GROUPS,
  FARM_WATCH_MAST_CAPACITY_PRODUCT,
  mastCapacitySourceSignature,
} from './farm-watch-mast-capacity-contract.ts'

function assert(condition: unknown, message = 'assertion failed'): asserts condition {
  if (!condition) throw new Error(message)
}

Deno.test('mast groups remain distinct and source-controlled', () => {
  const seen = new Set<number>()
  for (const group of FARM_WATCH_MAST_CAPACITY_PRODUCT.groupOrder) {
    assert(FARM_WATCH_MAST_CAPACITY_GROUPS[group].length > 0)
    for (const row of FARM_WATCH_MAST_CAPACITY_GROUPS[group]) {
      assert(!seen.has(row.spcd), 'species code appears in more than one mast group')
      seen.add(row.spcd)
    }
  }
  assert(FARM_WATCH_MAST_CAPACITY_GROUPS.white_oak.some((x) => x.spcd === 802))
  assert(FARM_WATCH_MAST_CAPACITY_GROUPS.red_oak.some((x) => x.spcd === 833))
  assert(FARM_WATCH_MAST_CAPACITY_GROUPS.hickory.some((x) => x.spcd === 407))
  assert(FARM_WATCH_MAST_CAPACITY_GROUPS.beech.some((x) => x.spcd === 531))
})

Deno.test('mast source signature binds the landscape-domain identity', () => {
  const a = mastCapacitySourceSignature({
    landscapeDomainIdentitySha256: 'a'.repeat(64),
    landscapeDomainAlgorithmVersion: 'barrier-aware-landscape-domain-v3',
  })
  const b = mastCapacitySourceSignature({
    landscapeDomainIdentitySha256: 'b'.repeat(64),
    landscapeDomainAlgorithmVersion: 'barrier-aware-landscape-domain-v3',
  })
  assert(a !== b)
  assert(a.includes('source_year=2018'))
  assert(a.includes('scope=broad_3000m'))
})

Deno.test('Batch 5A is capacity only', () => {
  assert(FARM_WATCH_MAST_CAPACITY_PRODUCT.semanticEvidenceClass === 'modeled_species_capacity')
  assert(FARM_WATCH_MAST_CAPACITY_PRODUCT.sourceValueUnit === 'tons_per_acre_live_tree_aboveground_biomass')
})
