const registryMigration = await Deno.readTextFile(
  'supabase/migrations/20260929220800_farm_watch_materialization_dependency_registry_v1.sql',
)
const manifestMigration = await Deno.readTextFile(
  'supabase/migrations/20260929220900_farm_watch_materialization_dependency_manifest_v1.sql',
)
const doc = await Deno.readTextFile(
  'docs/FARM_WATCH_MATERIALIZATION_DEPENDENCY_MANIFEST_V1.md',
)

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message)
}

const match = registryMigration.match(/\$registry\$([\s\S]+?)\$registry\$/)
assert(match, 'canonical registry JSON literal is missing')
const registry = JSON.parse(match[1])

assert(
  registry.registry_version === 'farm-watch-materialization-dependency-registry-v1',
  'registry version mismatch',
)
assert(
  registry.manifest_schema === 'farm-watch-materialization-dependency-manifest-v1',
  'manifest schema mismatch',
)
assert(registry.p0_1_external_resolution === 'contract_only', 'P0.1 external boundary drifted')

const expectedProducts = [
  'terrain-analysis',
  'lidar-source-coverage',
  'lidar-physical-structure',
  'leaf-off-woody-structure',
  'structure-complementarity',
  'landscape-structure-context',
  'terrain-form-permeability',
  'spatial-edge-patch-context',
  'solar-terrain-context',
  'solar-exposure-context',
  'thermal-exposure-context',
  'horizontal-visibility-context',
  'mast-capacity',
]
const expectedExternal = [
  'external:kyfromabove-phase3-dem',
  'external:kyfromabove-lidar-stac',
  'external:kyfromabove-phase3-copc',
  'external:kyfromabove-phase3-imagery-2024',
  'external:kyfromabove-phase2-imagery-2019',
  'external:nlcd-tcc-v2025-6',
  'external:usgs-3dep-dynamic',
  'external:fia-bigmap-2018-species-biomass',
]

const products = new Map(
  registry.products.map((product: any) => [String(product.product_kind), product]),
)
assert(products.size === 14, 'canonical registry must contain exactly 14 products')
for (const product of expectedProducts) {
  assert(products.has(product), 'missing canonical product: ' + product)
}

const external = new Map(
  registry.external_sources.map((source: any) => [String(source.key), source]),
)
assert(external.size === 8, 'canonical registry must contain exactly 8 external source slots')
for (const key of expectedExternal) {
  const source: any = external.get(key)
  assert(source, 'missing external source slot: ' + key)
  assert(source.resolution_status === 'contract_only', key + ' must remain contract_only in P0.1')
  assert(source.authoritative === false, key + ' must not claim authoritative freshness in P0.1')
  assert(typeof source.contract_seed === 'string' && source.contract_seed.length > 0,
    key + ' is missing a deterministic contract seed')
}

const edges = new Map<string, string[]>()
for (const [name, product] of products) {
  const deps = Array.isArray((product as any).dependencies) ? (product as any).dependencies : []
  const targets: string[] = []
  for (const dep of deps) {
    assert(typeof dep.key === 'string' && dep.key.length > 0, name + ' has unnamed dependency')
    assert(['materialization', 'context', 'state', 'temporal', 'external'].includes(dep.kind),
      name + ' has unsupported dependency kind ' + dep.kind)
    if (dep.kind === 'materialization') {
      assert(products.has(dep.product_kind),
        name + ' references unregistered materialization ' + dep.product_kind)
      targets.push(dep.product_kind)
    }
    if (dep.kind === 'external') {
      assert(external.has(dep.key), name + ' references unregistered external source ' + dep.key)
    }
  }
  edges.set(name, targets)
}

function visit(node: string, stack = new Set<string>(), seen = new Set<string>()) {
  if (stack.has(node)) throw new Error('materialization dependency cycle at ' + node)
  if (seen.has(node)) return
  stack.add(node)
  for (const next of edges.get(node) || []) visit(next, stack, seen)
  stack.delete(node)
  seen.add(node)
}
for (const product of expectedProducts) visit(product)

function impactedByExternal(externalKey: string) {
  const direct = new Set<string>()
  for (const [name, product] of products) {
    if ((product as any).dependencies.some((dep: any) =>
      dep.kind === 'external' && dep.key === externalKey
    )) direct.add(name)
  }
  const impacted = new Set(direct)
  let changed = true
  while (changed) {
    changed = false
    for (const [name, deps] of edges) {
      if (impacted.has(name)) continue
      if (deps.some((dep) => impacted.has(dep))) {
        impacted.add(name)
        changed = true
      }
    }
  }
  return impacted
}

function expectImpact(key: string, required: string[]) {
  const impacted = impactedByExternal(key)
  for (const product of required) {
    assert(impacted.has(product), key + ' failed to propagate to ' + product)
  }
}

// Synthetic graph mutations: these model an upstream identity change without touching real data.
expectImpact('external:kyfromabove-phase3-dem', [
  'terrain-analysis',
  'leaf-off-woody-structure',
  'landscape-structure-context',
  'study-aligned-vegetation-height-context',
  'terrain-form-permeability',
  'spatial-edge-patch-context',
  'solar-terrain-context',
  'solar-exposure-context',
  'thermal-exposure-context',
  'horizontal-visibility-context',
  'structure-complementarity',
])
expectImpact('external:kyfromabove-phase3-copc', [
  'lidar-physical-structure',
  'landscape-structure-context',
  'study-aligned-vegetation-height-context',
  'structure-complementarity',
  'spatial-edge-patch-context',
  'solar-terrain-context',
  'solar-exposure-context',
  'thermal-exposure-context',
  'horizontal-visibility-context',
])
expectImpact('external:nlcd-tcc-v2025-6', [
  'spatial-edge-patch-context',
  'solar-terrain-context',
  'solar-exposure-context',
  'thermal-exposure-context',
])

for (const required of [
  'farm_watch_materialization_dependency_registry_v1',
  'farm_watch_materialization_dependency_contract_v1',
  'farm_watch_external_dependency_contract_v1',
  'farm_watch_compare_materialization_dependency_v1',
]) assert(registryMigration.includes(required), 'missing registry SQL invariant: ' + required)

for (const required of [
  'farm_watch_resolve_materialization_dependency_v1_internal',
  'farm_watch_resolve_materialization_dependency_manifest_v1_internal',
  'farm_watch_materialization_dependency_mismatches_v1_internal',
  'farm_watch_get_current_materialization_ref_with_overrides_v1_internal',
  'farm_watch_assert_materialization_dependency_registry_v1',
  'authoritative_external_resolution_complete',
  'dependency-aware-materialization-v1',
  'kyfromabove_phase3_dem_identity_changed',
  'lidar_physical_artifact_changed',
  'calendar_date_mismatch',
  'meteorological_source_records_changed',
  'select farm_watch.farm_watch_assert_materialization_dependency_registry_v1();',
]) assert(manifestMigration.includes(required), 'missing manifest SQL invariant: ' + required)

assert(
  manifestMigration.includes(
    'revoke all on function farm_watch.farm_watch_get_current_materialization_ref_with_overrides_v1_internal',
  ) &&
  manifestMigration.includes('from public,anon,authenticated,service_role'),
  'synthetic override resolver must not be callable by runtime roles',
)
assert(
  manifestMigration.includes(
    'grant execute on function farm_watch.farm_watch_get_current_materialization_ref_v1_internal',
  ) && manifestMigration.includes('to service_role'),
  'standard current materialization resolver must remain service-role only',
)

for (const required of [
  '14 materialized product kinds',
  'resolution_status=contract_only',
  'P0.2',
  'Synthetic identity testing',
  'authoritative_external_resolution_complete=false',
]) assert(doc.includes(required), 'dependency-manifest documentation is incomplete: ' + required)

for (const forbidden of [
  'deer_score',
  'habitat_score',
  'bedding_score',
  'movement_score',
]) {
  assert(!registryMigration.includes(forbidden), 'forbidden scoring semantic in registry: ' + forbidden)
  assert(!manifestMigration.includes(forbidden), 'forbidden scoring semantic in manifest: ' + forbidden)
}

console.log(
  'Farm Watch materialization dependency registry invariants passed: ' +
    products.size + ' products, ' + external.size + ' external slots',
)
