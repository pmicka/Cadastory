import {
  appendFarmWatchExternalIdentitySignature,
  FARM_WATCH_EXTERNAL_DEPENDENCY_KEYS,
  farmWatchExternalIdentityOverrides,
  farmWatchExternalIdentitySignatureKey,
  resolveFarmWatchExternalSourceIdentities,
} from '../supabase/functions/_shared/farm-watch-external-source-identity.ts'
import {
  buildLidarSourceArtifact,
} from '../supabase/functions/_shared/farm-watch-lidar-source.ts'
import {
  FARM_WATCH_LEAF_OFF_PRODUCT,
  leafOffSourceCatalogWhere,
  leafOffSourceMosaicRule,
} from '../supabase/functions/_shared/farm-watch-leaf-off-contract.ts'

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message)
}

const fakeA = 'a'.repeat(64)
const fakeB = 'b'.repeat(64)
const signature = appendFarmWatchExternalIdentitySignature(
  'product=test',
  [
    {
      key: 'external:kyfromabove-phase3-dem',
      status: 'available',
      authoritative: true,
      resolution_status: 'synthetic',
      identity_sha256: fakeB,
      observed_at: '2026-09-29T00:00:00Z',
      evidence: {},
    },
    {
      key: 'external:kyfromabove-lidar-stac',
      status: 'available',
      authoritative: true,
      resolution_status: 'synthetic',
      identity_sha256: fakeA,
      observed_at: '2026-09-29T00:00:00Z',
      evidence: {},
    },
  ],
)
assert(
  signature ===
    'product=test|' +
    farmWatchExternalIdentitySignatureKey('external:kyfromabove-lidar-stac') + '=' + fakeA + '|' +
    farmWatchExternalIdentitySignatureKey('external:kyfromabove-phase3-dem') + '=' + fakeB,
  'external identity source-signature binding is not canonical',
)

const overrides = farmWatchExternalIdentityOverrides([
  {
    key: 'external:kyfromabove-phase3-dem',
    status: 'available',
    authoritative: true,
    resolution_status: 'synthetic',
    identity_sha256: fakeA,
    observed_at: '2026-09-29T00:00:00Z',
    evidence: {},
  },
])
assert(
  overrides['external:kyfromabove-phase3-dem']?.identity_sha256 === fakeA,
  'external identity override is missing',
)

const postgrestExternalDependencyRpc = 'farm_watch_get_materialization_external_deps_v1_internal'
assert(
  postgrestExternalDependencyRpc.length <= 63,
  'PostgREST RPC identifier exceeds PostgreSQL 63-character identifier limit',
)

assert(
  FARM_WATCH_EXTERNAL_DEPENDENCY_KEYS.length === 8 &&
  new Set(FARM_WATCH_EXTERNAL_DEPENDENCY_KEYS).size === 8,
  'external dependency resolver must cover exactly eight unique P0.2 slots',
)



const testBoundary = {
  type: 'Polygon',
  coordinates: [[
    [-84.89, 38.31],
    [-84.88, 38.31],
    [-84.88, 38.32],
    [-84.89, 38.32],
    [-84.89, 38.31],
  ]],
}

function stacFeature(id: string, geometry: any, assetHref: string) {
  return {
    type: 'Feature',
    id,
    bbox: [-84.90, 38.30, -84.87, 38.33],
    geometry,
    properties: {
      datetime: '2024-01-01T00:00:00Z',
      created: '2024-01-01T00:00:00Z',
      updated: '2026-01-01T00:00:00Z',
      'pc:count': 100,
      'pc:density': 12,
      'pc:type': 'lidar',
      'pc:encoding': 'copc',
    },
    assets: {
      data: {
        href: assetHref,
        type: 'application/vnd.laszip+copc',
        roles: ['data'],
      },
    },
  }
}

const geometryA = {
  type: 'Polygon',
  coordinates: [[
    [-84.91, 38.29],
    [-84.86, 38.29],
    [-84.86, 38.34],
    [-84.91, 38.34],
    [-84.91, 38.29],
  ]],
}
const geometryB = {
  type: 'Polygon',
  coordinates: [[
    [-84.91, 38.29],
    [-84.86, 38.29],
    [-84.86, 38.34],
    [-84.885, 38.325],
    [-84.91, 38.34],
    [-84.91, 38.29],
  ]],
}

const pagedStacFetch: typeof fetch = async (input, init) => {
  const url = String(input)
  if (!url.includes('/search')) throw new Error('unexpected STAC test URL: ' + url)
  const body = JSON.parse(String(init?.body || '{}'))
  const second = body.token === 'page-2'
  const feature = second
    ? stacFeature('tile-2', geometryA, 'https://example.test/tile-2.copc.laz')
    : stacFeature('tile-1', geometryA, 'https://example.test/tile-1.copc.laz')
  return new Response(JSON.stringify({
    type: 'FeatureCollection',
    numberMatched: 2,
    features: [feature],
    links: second
      ? []
      : [{
        rel: 'next',
        href: 'https://spved5ihrl.execute-api.us-west-2.amazonaws.com/search',
        method: 'POST',
        body: { token: 'page-2' },
      }],
  }), {
    status: 200,
    headers: { 'content-type': 'application/geo+json' },
  })
}

const pagedStac = await buildLidarSourceArtifact(
  testBoundary,
  pagedStacFetch,
  ['laz-phase3'],
)
assert(
  pagedStac.artifact.collections[0]?.matched_item_count === 2 &&
  pagedStac.artifact.collections[0]?.search?.page_count === 2 &&
  pagedStac.artifact.collections[0]?.search?.pagination_complete === true,
  'STAC pagination did not consume the complete selected item set',
)

async function stacIdentityWithGeometry(geometry: any) {
  const mockFetch: typeof fetch = async (input, init) => {
    const url = String(input)
    if (String(init?.method || 'GET').toUpperCase() === 'HEAD') {
      return new Response(null, {
        status: 200,
        headers: { etag: '"geometry-test-etag"' },
      })
    }
    if (url.includes('/search')) {
      const body = JSON.parse(String(init?.body || '{}'))
      const collection = String(body?.collections?.[0] || 'unknown')
      return new Response(JSON.stringify({
        type: 'FeatureCollection',
        numberMatched: 1,
        features: [
          stacFeature(
            collection + '-tile',
            geometry,
            'https://example.test/' + collection + '.copc.laz',
          ),
        ],
        links: [],
      }), {
        status: 200,
        headers: { 'content-type': 'application/geo+json' },
      })
    }
    throw new Error('unexpected STAC identity URL: ' + url)
  }
  const rows = await resolveFarmWatchExternalSourceIdentities({
    boundary: testBoundary,
    dependencyKeys: ['external:kyfromabove-lidar-stac'],
    fetchImpl: mockFetch,
  })
  return String(rows[0]?.identity_sha256 || '')
}

const geometryIdentityA = await stacIdentityWithGeometry(geometryA)
const geometryIdentityB = await stacIdentityWithGeometry(geometryB)
assert(
  geometryIdentityA !== geometryIdentityB,
  'STAC identity did not change when footprint geometry changed under the same item/bbox',
)

function arcgisMock(args: {
  incompleteSamples?: boolean
  paginatedCatalog?: boolean
} = {}): typeof fetch {
  return async (input, init) => {
    const url = String(input)
    const method = String(init?.method || 'GET').toUpperCase()
    if (method === 'POST' && /ImageServer\/?$/.test(url)) {
      return new Response(JSON.stringify({
        name: 'Mock/ImageServer',
        serviceItemId: null,
        fields: [{ name: 'OBJECTID', type: 'esriFieldTypeOID', alias: 'OBJECTID' }],
      }), { status: 200, headers: { 'content-type': 'application/json' } })
    }
    if (url.includes('/sharing/rest/search?')) {
      return new Response(JSON.stringify({ results: [] }), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      })
    }
    if (method === 'POST' && url.endsWith('/query')) {
      const params = new URLSearchParams(String(init?.body || ''))
      const offset = Number(params.get('resultOffset') || 0)
      const first = offset === 0
      return new Response(JSON.stringify({
        exceededTransferLimit: Boolean(args.paginatedCatalog && first),
        features: [{
          attributes: {
            OBJECTID: first ? 1 : 2,
            Name: first ? 'first' : 'second',
          },
        }],
      }), { status: 200, headers: { 'content-type': 'application/json' } })
    }
    if (method === 'POST' && url.endsWith('/getSamples')) {
      const params = new URLSearchParams(String(init?.body || ''))
      const geometry = JSON.parse(String(params.get('geometry') || '{}'))
      const points = Array.isArray(geometry?.points) ? geometry.points : []
      const count = args.incompleteSamples ? Math.min(1, points.length) : points.length
      return new Response(JSON.stringify({
        samples: Array.from({ length: count }, (_, index) => ({
          locationId: index,
          value: String(100 + index),
        })),
      }), { status: 200, headers: { 'content-type': 'application/json' } })
    }
    throw new Error('unexpected ArcGIS test URL: ' + method + ' ' + url)
  }
}

const completeArcgis = await resolveFarmWatchExternalSourceIdentities({
  boundary: testBoundary,
  dependencyKeys: ['external:kyfromabove-phase3-dem'],
  fetchImpl: arcgisMock({ paginatedCatalog: true }),
  requireAll: false,
})
assert(
  completeArcgis[0]?.status === 'available' &&
  (completeArcgis[0]?.evidence as any)?.catalog_observation?.page_count === 2 &&
  (completeArcgis[0]?.evidence as any)?.catalog_observation?.complete === true &&
  (completeArcgis[0]?.evidence as any)?.sample_observation?.complete === true,
  'ArcGIS provider observation did not preserve complete catalog/sample scope',
)

const incompleteArcgis = await resolveFarmWatchExternalSourceIdentities({
  boundary: testBoundary,
  dependencyKeys: ['external:kyfromabove-phase3-dem'],
  fetchImpl: arcgisMock({ incompleteSamples: true }),
  requireAll: false,
})
assert(
  incompleteArcgis[0]?.status === 'unavailable' &&
  String(incompleteArcgis[0]?.error || '').includes('sample probe incomplete'),
  'incomplete ArcGIS sample responses must fail closed',
)

let unknownKeyRejected = false
try {
  await resolveFarmWatchExternalSourceIdentities({
    boundary: testBoundary,
    dependencyKeys: ['external:not-a-real-source'],
    fetchImpl: arcgisMock(),
  })
} catch {
  unknownKeyRejected = true
}
assert(unknownKeyRejected, 'unknown external dependency keys must fail closed')

const phase3 = FARM_WATCH_LEAF_OFF_PRODUCT.sources.find((row) => row.id === 'ky-phase3')!
const phase2 = FARM_WATCH_LEAF_OFF_PRODUCT.sources.find((row) => row.id === 'ky-franklin-2019')!
assert(
  leafOffSourceCatalogWhere(phase3) ===
    "Name = 'N071E278_2024_Season1_3IN_cog'" &&
  leafOffSourceCatalogWhere(phase2) === "Name = 'N071E278_2019'",
  'fixed historical imagery catalog selection is not exact',
)
assert(
  leafOffSourceMosaicRule(phase3).where === leafOffSourceCatalogWhere(phase3) &&
  leafOffSourceMosaicRule(phase2).where === leafOffSourceCatalogWhere(phase2),
  'fixed imagery resolver and builder mosaic selection can drift',
)

const materializationEdge = await Deno.readTextFile(
  'supabase/functions/farm-watch-materialization/index.ts',
)
const lidarMaterializer = await Deno.readTextFile(
  'scripts/farm-watch-lidar-physical-materialize.ts',
)
const leafOffMaterializer = await Deno.readTextFile(
  'scripts/farm-watch-leaf-off-materialize.ts',
)
const terrainMaterializer = await Deno.readTextFile(
  'scripts/farm-watch-terrain-materialize.ts',
)
const externalResolver = await Deno.readTextFile(
  'supabase/functions/_shared/farm-watch-external-source-identity.ts',
)
assert(
  materializationEdge.includes(
    "pmicka/Cadastory/.github/workflows/farm-watch-lidar-physical.yml@refs/heads/main",
  ),
  'LiDAR physical workflow is not authorized to refresh canonical source coverage',
)
assert(
  lidarMaterializer.includes("product: 'lidar-source-coverage'") &&
  lidarMaterializer.indexOf('ensureCurrentLidarSourceCoverage()') <
    lidarMaterializer.indexOf("workerRequest({ operation: 'claim' })"),
  'LiDAR physical materializer must refresh source coverage before physical claim',
)
assert(
  terrainMaterializer.includes('resolveFarmWatchExternalSourceSignatureForProperty') &&
  terrainMaterializer.includes('p_source_signature: authoritativeSource.sourceSignature') &&
  terrainMaterializer.includes('external_source_observations: authoritativeSource.observations'),
  'terrain CLI can bypass authoritative DEM identity binding',
)

assert(
  leafOffMaterializer.includes('leafOffSourceMosaicRule(source)') &&
  leafOffMaterializer.includes("url.searchParams.set('mosaicRule'") &&
  leafOffMaterializer.includes('fixedImageryMosaicRule'),
  'leaf-off builder does not consume the same exact fixed imagery selection as freshness',
)
assert(
  externalResolver.includes('stac-selected-item-snapshot-v2') &&
  externalResolver.includes('geometry: item?.geometry') &&
  externalResolver.includes('SOLAR_DEM_IDENTITY_SUPPORT_METERS') &&
  externalResolver.includes('expectedCatalogCount: 1') &&
  externalResolver.includes('fixed-imagery-pair-provider-selection-v2'),
  'external resolver is missing source-selection fidelity invariants',
)

if (Deno.args.includes('--bigmap-diagnostic')) {
  const url = 'https://data.fs.usda.gov/geodata/rastergateway/bigmap/'
  const response = await fetch(url)
  const html = await response.text()
  console.log('BIGMAP_GATEWAY_STATUS=' + response.status)
  for (const code of ['0400','0802','0833']) {
    const index = html.indexOf(code)
    console.log('BIGMAP_GATEWAY_SNIPPET_' + code + '=' +
      (index >= 0 ? html.slice(Math.max(0, index - 500), index + 1500) : 'NOT_FOUND'))
  }
}

if (Deno.args.includes('--live')) {
  // Bounded validation geometry covering the Flat Creek validation-property area.
  // The resolver itself expands only as required by each product contract.
  const boundary = {
    type: 'Polygon',
    coordinates: [[
      [-84.8920, 38.3100],
      [-84.8720, 38.3100],
      [-84.8720, 38.3280],
      [-84.8920, 38.3280],
      [-84.8920, 38.3100],
    ]],
  }

  const first = await resolveFarmWatchExternalSourceIdentities({
    boundary,
    dependencyKeys: [...FARM_WATCH_EXTERNAL_DEPENDENCY_KEYS],
    requireAll: false,
  })
  const unavailable = first.filter((row) => row.status !== 'available')
  if (unavailable.length) {
    throw new Error(
      'live external identity resolution failed: ' +
      unavailable.map((row) => row.key + '=' + (row.error || row.status)).join('; '),
    )
  }
  for (const row of first) {
    assert(row.authoritative === true, row.key + ' did not resolve authoritatively')
    assert(
      /^[0-9a-f]{64}$/.test(String(row.identity_sha256 || '')),
      row.key + ' returned an invalid identity',
    )
    assert(
      row.resolution_status !== 'contract_only',
      row.key + ' unexpectedly fell back to contract-only identity',
    )
  }

  // A second bounded observation must be stable when providers did not change
  // between the two probes. observed_at is intentionally excluded from identity.
  const second = await resolveFarmWatchExternalSourceIdentities({
    boundary,
    dependencyKeys: [...FARM_WATCH_EXTERNAL_DEPENDENCY_KEYS],
    requireAll: false,
  })
  const firstByKey = new Map(first.map((row) => [row.key, row]))
  for (const row of second) {
    const before = firstByKey.get(row.key)
    assert(before, 'second observation returned an unexpected source: ' + row.key)
    assert(row.status === 'available', 'second observation unavailable: ' + row.key)
    assert(
      row.identity_sha256 === before.identity_sha256,
      row.key + ' provider identity changed between immediate probes',
    )
  }

  console.log(JSON.stringify({
    status: 'passed',
    source_count: first.length,
    sources: first.map((row) => ({
      key: row.key,
      resolution_status: row.resolution_status,
      identity_sha256: row.identity_sha256,
    })),
  }, null, 2))
} else {
  console.log('Farm Watch external source identity invariants passed')
}
