import {
  buildFlowNetwork,
  buildFlowPaths,
  buildFlowProduct,
  buildSampleGrid,
  buildTerrainArtifact,
  deriveTerrainAnatomy,
  gridCellMetrics,
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


function syntheticGrid(values: number[][]) {
  const size = values.length
  const west = -84.89
  const east = -84.88
  const south = 38.32
  const north = 38.33
  const points: Array<[number, number]> = []
  for (let row = 0; row < size; row += 1) {
    const lat = south + ((north - south) * row) / (size - 1)
    for (let col = 0; col < size; col += 1) {
      const lon = west + ((east - west) * col) / (size - 1)
      points.push([lon, lat])
    }
  }
  const flat = values.flat()
  return {
    west,east,south,north,size,points,
    values: flat,
    min: Math.min(...flat),
    max: Math.max(...flat),
    boundary: {
      type: 'Polygon' as const,
      coordinates: [[
        [west + 0.001, south + 0.001],
        [east - 0.001, south + 0.001],
        [east - 0.001, north - 0.001],
        [west + 0.001, north - 0.001],
        [west + 0.001, south + 0.001],
      ]],
    },
  }
}

Deno.test('metric D8 uses physical grid spacing rather than unit cell steps', () => {
  const grid = syntheticGrid([
    [10,9,8,7,6],
    [11,10,9,8,7],
    [12,11,10,9,8],
    [13,12,11,10,9],
    [14,13,12,11,10],
  ])
  const metrics = gridCellMetrics(grid)
  assert(metrics.east_west_m > 0)
  assert(metrics.north_south_m > 0)
  assert(Math.abs(metrics.east_west_m - metrics.north_south_m) > 1, 'geographic grid should not be treated as square index steps')
})

Deno.test('priority-flood conditioning routes an enclosed sampled sink toward the grid exterior', () => {
  const grid = syntheticGrid([
    [12,11,10,9,8],
    [13,12,11,10,7],
    [14,13,1,9,6],
    [15,14,13,8,5],
    [16,15,14,7,4],
  ])
  const center = 2 * grid.size + 2
  const network = buildFlowNetwork(grid)
  assert(network.conditioning.filled_cell_count > 0, 'sampled sink should be conditioned')
  assert(network.conditioning.max_fill_depth_ft > 0)

  const seen = new Set<number>()
  let cursor = center
  let reachedExterior = false
  for (let step = 0; step < grid.values.length && cursor >= 0 && !seen.has(cursor); step += 1) {
    seen.add(cursor)
    const [lon, lat] = grid.points[cursor]
    if (!pointInPolygonGeometry(lon, lat, grid.boundary) && cursor !== center) {
      reachedExterior = true
      break
    }
    cursor = network.downstream[cursor]
  }
  assert(reachedExterior, 'conditioned sink should route beyond the parcel rather than terminate locally')
})

Deno.test('conditioned flow product reports contributing-area and conditioning metadata', () => {
  const grid = syntheticGrid([
    [12,11,10,9,8],
    [13,12,11,10,7],
    [14,13,8,9,6],
    [15,14,10,8,5],
    [16,15,14,7,4],
  ])
  const product = buildFlowProduct(grid)
  assert(product.summary.min_contributing_area_acres > 0)
  assert(product.summary.threshold_cells >= 2)
  assert(product.summary.cell_area_acres > 0)
  assert(typeof product.summary.conditioning.filled_cell_count === 'number')
  assert(Array.isArray(product.paths))
})
