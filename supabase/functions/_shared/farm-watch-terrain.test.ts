import {
  buildFlowPaths,
  buildSampleGrid,
  buildTerrainArtifact,
  deriveTerrainAnatomy,
  pointInPolygonGeometry,
  sampleDem,
} from './farm-watch-terrain.ts'

function assert(condition: unknown, message = 'assertion failed'): asserts condition {
  if (!condition) throw new Error(message)
}

function assertEquals(actual: unknown, expected: unknown, message = 'values differ') {
  const a = JSON.stringify(actual)
  const e = JSON.stringify(expected)
  if (a !== e) throw new Error(`${message}\nactual: ${a}\nexpected: ${e}`)
}

const square = {
  type: 'Polygon' as const,
  coordinates: [[
    [-84.89, 38.32],
    [-84.88, 38.32],
    [-84.88, 38.33],
    [-84.89, 38.33],
    [-84.89, 38.32],
  ]],
}

const holed = {
  type: 'Polygon' as const,
  coordinates: [
    square.coordinates[0],
    [
      [-84.886, 38.324],
      [-84.884, 38.324],
      [-84.884, 38.326],
      [-84.886, 38.326],
      [-84.886, 38.324],
    ],
  ],
}

const multipart = {
  type: 'MultiPolygon' as const,
  coordinates: [
    [[
      [-84.89, 38.32],
      [-84.886, 38.32],
      [-84.886, 38.324],
      [-84.89, 38.324],
      [-84.89, 38.32],
    ]],
    [[
      [-84.884, 38.326],
      [-84.88, 38.326],
      [-84.88, 38.33],
      [-84.884, 38.33],
      [-84.884, 38.326],
    ]],
  ],
}

function mockDemFetch(options: { missingModulo?: number; allMissingAfter?: number } = {}) {
  return async (_url: string | URL | Request, init?: RequestInit) => {
    const params = new URLSearchParams(String(init?.body || ''))
    const geometry = JSON.parse(params.get('geometry') || '{}')
    const points = Array.isArray(geometry.points) ? geometry.points : []
    const samples = points.flatMap((point: number[], index: number) => {
      if (options.missingModulo && index % options.missingModulo === 0) return []
      if (options.allMissingAfter != null && index >= options.allMissingAfter) return []
      const lon = Number(point[0])
      const lat = Number(point[1])
      const value = 700 + (lon + 84.89) * 1200 + (lat - 38.32) * 1800
      return [{ locationId: index, value }]
    })
    return new Response(JSON.stringify({ samples }), {
      status: 200,
      headers: { 'content-type': 'application/json' },
    })
  }
}

Deno.test('61x61 terrain grid preserves browser geometry contract', () => {
  const grid = buildSampleGrid(square)
  assertEquals(grid.size, 61)
  assertEquals(grid.points.length, 3721)
  assert(grid.west < -84.89)
  assert(grid.east > -84.88)
  assert(grid.south < 38.32)
  assert(grid.north > 38.33)
})

Deno.test('parcel geometry honors holes and multipart membership', () => {
  assert(pointInPolygonGeometry(-84.888, 38.322, holed))
  assert(!pointInPolygonGeometry(-84.885, 38.325, holed), 'hole must not be treated as parcel interior')
  assert(pointInPolygonGeometry(-84.888, 38.322, multipart))
  assert(pointInPolygonGeometry(-84.882, 38.328, multipart))
  assert(!pointInPolygonGeometry(-84.885, 38.325, multipart))
})

Deno.test('partial DEM no-data remains valid above the existing 70 percent coverage threshold', async () => {
  const grid = await sampleDem(square, mockDemFetch({ missingModulo: 5 }) as typeof fetch)
  const valid = grid.values.filter(Number.isFinite).length
  assert(valid >= Math.ceil(3721 * 0.7))
  assert(valid < 3721)
})

Deno.test('incomplete DEM coverage still fails below the existing threshold', async () => {
  let failed = false
  try {
    await sampleDem(square, mockDemFetch({ missingModulo: 2 }) as typeof fetch)
  } catch (error) {
    failed = /coverage is incomplete/i.test(String(error))
  }
  assert(failed, 'coverage failure should be explicit')
})

Deno.test('terrain artifact is deterministic for identical source samples', async () => {
  const fetchImpl = mockDemFetch() as typeof fetch
  const a = await buildTerrainArtifact(square, 42.92, fetchImpl)
  const b = await buildTerrainArtifact(square, 42.92, fetchImpl)
  assertEquals(a.sampledSourceSha256, b.sampledSourceSha256)
  assertEquals(a.artifact, b.artifact)
  assertEquals(a.artifact.grid.values.length, 3721)
  assert(Array.isArray(a.artifact.contours.levels))
  assert(Array.isArray(a.artifact.flow_paths))
})

Deno.test('stated acreage affects only acreage-bearing anatomy output, not sampled source or flow paths', async () => {
  const fetchImpl = mockDemFetch() as typeof fetch
  const base = await buildTerrainArtifact(square, 40, fetchImpl)
  const grid = base.artifact.grid
  const a = deriveTerrainAnatomy(grid, 40)
  const b = deriveTerrainAnatomy(grid, 80)
  assertEquals(buildFlowPaths(grid), base.artifact.flow_paths)
  assertEquals(a?.outlet_routed_percent, b?.outlet_routed_percent)
  if ((a?.outlet_zones?.length || 0) > 0) {
    const aAcres = Number(a?.outlet_zones?.[0]?.estimated_acres)
    const bAcres = Number(b?.outlet_zones?.[0]?.estimated_acres)
    assert(Math.abs(bAcres - aAcres * 2) < 1e-9)
  }
})
