import { FARM_WATCH_TERRAIN_PRODUCT } from './farm-watch-terrain-contract.ts'

export type GeoJsonGeometry = {
  type: 'Polygon' | 'MultiPolygon'
  coordinates: any
}

export type TerrainGrid = {
  west: number
  east: number
  south: number
  north: number
  size: number
  points: Array<[number, number]>
  values: Array<number | null>
  min: number
  max: number
  boundary: GeoJsonGeometry
}

export function flattenCoordinates(geometry: GeoJsonGeometry | null | undefined) {
  if (!geometry) return []
  if (geometry.type === 'Polygon') return geometry.coordinates.flat(1)
  if (geometry.type === 'MultiPolygon') return geometry.coordinates.flat(2)
  return []
}

export function polygonBounds(boundary: GeoJsonGeometry) {
  const coords = flattenCoordinates(boundary)
  if (!coords.length) return null
  const lons = coords.map((point: any) => Number(point[0])).filter(Number.isFinite)
  const lats = coords.map((point: any) => Number(point[1])).filter(Number.isFinite)
  if (!lons.length || !lats.length) return null
  return {
    west: Math.min(...lons),
    east: Math.max(...lons),
    south: Math.min(...lats),
    north: Math.max(...lats),
  }
}

export function pointInRing(lon: number, lat: number, ring: any[]) {
  let inside = false
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const xi = Number(ring[i][0])
    const yi = Number(ring[i][1])
    const xj = Number(ring[j][0])
    const yj = Number(ring[j][1])
    const crosses = ((yi > lat) !== (yj > lat)) &&
      (lon < ((xj - xi) * (lat - yi)) / ((yj - yi) || Number.EPSILON) + xi)
    if (crosses) inside = !inside
  }
  return inside
}

export function pointInPolygonGeometry(lon: number, lat: number, geometry: GeoJsonGeometry) {
  const polygons = geometry?.type === 'Polygon'
    ? [geometry.coordinates]
    : geometry?.type === 'MultiPolygon' ? geometry.coordinates : []

  return polygons.some((polygon: any[]) => {
    const [outer, ...holes] = polygon
    if (!outer || !pointInRing(lon, lat, outer)) return false
    return !holes.some((hole) => pointInRing(lon, lat, hole))
  })
}

export function segmentTouchesParcel(segment: any[], boundary: GeoJsonGeometry) {
  const [a, b] = segment
  if (!a || !b) return false
  const midpointLat = (a[0] + b[0]) / 2
  const midpointLon = (a[1] + b[1]) / 2
  return pointInPolygonGeometry(a[1], a[0], boundary) ||
    pointInPolygonGeometry(b[1], b[0], boundary) ||
    pointInPolygonGeometry(midpointLon, midpointLat, boundary)
}

export function buildSampleGrid(boundary: GeoJsonGeometry) {
  const bounds = polygonBounds(boundary)
  if (!bounds) throw new Error('Selected parcel bounds are unavailable')
  const pad = FARM_WATCH_TERRAIN_PRODUCT.boundsPaddingFraction
  const lonPad = (bounds.east - bounds.west) * pad
  const latPad = (bounds.north - bounds.south) * pad
  const west = bounds.west - lonPad
  const east = bounds.east + lonPad
  const south = bounds.south - latPad
  const north = bounds.north + latPad
  const points: Array<[number, number]> = []

  for (let row = 0; row < FARM_WATCH_TERRAIN_PRODUCT.gridSize; row += 1) {
    const lat = south + ((north - south) * row) / (FARM_WATCH_TERRAIN_PRODUCT.gridSize - 1)
    for (let col = 0; col < FARM_WATCH_TERRAIN_PRODUCT.gridSize; col += 1) {
      const lon = west + ((east - west) * col) / (FARM_WATCH_TERRAIN_PRODUCT.gridSize - 1)
      points.push([lon, lat])
    }
  }

  return { west, east, south, north, size: FARM_WATCH_TERRAIN_PRODUCT.gridSize, points }
}

export async function sampleDemBatch(
  points: Array<[number, number]>,
  offset: number,
  values: Array<number | null>,
  fetchImpl: typeof fetch = fetch,
) {
  const geometry = JSON.stringify({
    points,
    spatialReference: { wkid: 4326 },
  })
  const body = new URLSearchParams({
    geometryType: 'esriGeometryMultipoint',
    geometry,
    returnFirstValueOnly: 'true',
    f: 'json',
  })
  const response = await fetchImpl(`${FARM_WATCH_TERRAIN_PRODUCT.sourceUrl}/getSamples`, {
    method: 'POST',
    headers: {
      'content-type': 'application/x-www-form-urlencoded;charset=UTF-8',
      accept: 'application/json',
      'user-agent': 'Cadastory-Farm-Watch-Materializer/1.0',
    },
    body,
  })
  if (!response.ok) throw new Error(`Terrain samples returned ${response.status}`)
  const payload = await response.json()
  if (!Array.isArray(payload?.samples)) throw new Error('Terrain samples are unavailable')

  for (const sample of payload.samples) {
    const localIndex = Number(sample.locationId)
    const value = Number(sample.value)
    const globalIndex = offset + localIndex
    if (
      Number.isInteger(localIndex) &&
      localIndex >= 0 &&
      localIndex < points.length &&
      globalIndex < values.length &&
      Number.isFinite(value)
    ) values[globalIndex] = value
  }
}

export async function sampleDem(boundary: GeoJsonGeometry, fetchImpl: typeof fetch = fetch) {
  const grid = buildSampleGrid(boundary)
  const values: Array<number | null> = new Array(grid.points.length).fill(null)

  for (let offset = 0; offset < grid.points.length; offset += FARM_WATCH_TERRAIN_PRODUCT.sampleBatchSize) {
    const points = grid.points.slice(offset, offset + FARM_WATCH_TERRAIN_PRODUCT.sampleBatchSize)
    await sampleDemBatch(points, offset, values, fetchImpl)
  }

  const valid = values.filter((value): value is number => Number.isFinite(value))
  if (valid.length < grid.points.length * 0.7) throw new Error('Terrain coverage is incomplete for this parcel')
  return {
    ...grid,
    values,
    min: Math.min(...valid),
    max: Math.max(...valid),
    boundary,
  } satisfies TerrainGrid
}

export function gridPoint(grid: TerrainGrid, row: number, col: number) {
  const index = row * grid.size + col
  return {
    index,
    lon: grid.west + ((grid.east - grid.west) * col) / (grid.size - 1),
    lat: grid.south + ((grid.north - grid.south) * row) / (grid.size - 1),
    value: grid.values[index],
  }
}

export function interpolateEdge(a: any, b: any, level: number) {
  const delta = b.value - a.value
  const t = Math.abs(delta) < Number.EPSILON ? 0.5 : (level - a.value) / delta
  return [a.lat + (b.lat - a.lat) * t, a.lon + (b.lon - a.lon) * t]
}

export function contourSegments(grid: TerrainGrid, level: number) {
  const segments: any[] = []
  for (let row = 0; row < grid.size - 1; row += 1) {
    for (let col = 0; col < grid.size - 1; col += 1) {
      const sw = gridPoint(grid, row, col)
      const se = gridPoint(grid, row, col + 1)
      const ne = gridPoint(grid, row + 1, col + 1)
      const nw = gridPoint(grid, row + 1, col)
      if (![sw.value, se.value, ne.value, nw.value].every(Number.isFinite)) continue

      const edges = [[sw, se], [se, ne], [ne, nw], [nw, sw]]
      const crossings: any[] = []
      for (let edge = 0; edge < edges.length; edge += 1) {
        const [a, b] = edges[edge]
        const aValue = Number(a.value)
        const bValue = Number(b.value)
        if ((aValue < level && bValue >= level) || (bValue < level && aValue >= level)) {
          crossings.push({ edge, point: interpolateEdge(a, b, level) })
        }
      }

      if (crossings.length === 2) {
        segments.push([crossings[0].point, crossings[1].point])
      } else if (crossings.length === 4) {
        const center = (Number(sw.value) + Number(se.value) + Number(ne.value) + Number(nw.value)) / 4
        const byEdge = new Map(crossings.map((item) => [item.edge, item.point]))
        const pairs = center >= level ? [[0, 1], [2, 3]] : [[0, 3], [1, 2]]
        for (const [a, b] of pairs) segments.push([byEdge.get(a), byEdge.get(b)])
      }
    }
  }
  return segments
}

export function contourPointKey(point: number[]) {
  return `${Number(point[0]).toFixed(10)},${Number(point[1]).toFixed(10)}`
}

export function stitchContourSegments(segments: any[]) {
  if (!segments.length) return []
  const endpointKeys = segments.map((segment) => segment.map(contourPointKey))
  const adjacency = new Map<string, any[]>()

  for (let index = 0; index < endpointKeys.length; index += 1) {
    for (let side = 0; side < 2; side += 1) {
      const key = endpointKeys[index][side]
      const connections = adjacency.get(key) || []
      connections.push({ index, side })
      adjacency.set(key, connections)
    }
  }

  const visited = new Set<number>()
  const paths: any[] = []

  function walk(startIndex: number, startSide: number) {
    const path = [segments[startIndex][startSide]]
    let currentIndex = startIndex
    let currentKey = endpointKeys[startIndex][startSide]

    while (!visited.has(currentIndex)) {
      visited.add(currentIndex)
      const segment = segments[currentIndex]
      const keys = endpointKeys[currentIndex]
      const fromSide = keys[0] === currentKey ? 0 : 1
      const toSide = fromSide === 0 ? 1 : 0
      path.push(segment[toSide])
      currentKey = keys[toSide]

      const next = (adjacency.get(currentKey) || []).find((connection) => !visited.has(connection.index))
      if (!next) break
      currentIndex = next.index
    }

    return path
  }

  for (const connections of adjacency.values()) {
    if (connections.length !== 1) continue
    const [{ index, side }] = connections
    if (!visited.has(index)) paths.push(walk(index, side))
  }

  for (let index = 0; index < segments.length; index += 1) {
    if (!visited.has(index)) paths.push(walk(index, 0))
  }

  return paths.filter((path) => path.length >= 2)
}

export function buildContourProduct(grid: TerrainGrid) {
  const range = grid.max - grid.min
  const interval = range > 220 ? 20 : 10
  const first = Math.ceil(grid.min / interval) * interval
  const last = Math.floor(grid.max / interval) * interval
  const levels: any[] = []
  let segmentCount = 0
  let pathCount = 0

  for (let level = first; level <= last; level += interval) {
    const major = level % 50 === 0
    const segments = contourSegments(grid, level)
      .filter((segment) => segmentTouchesParcel(segment, grid.boundary))
    segmentCount += segments.length
    const paths = stitchContourSegments(segments)
    pathCount += paths.length
    levels.push({ level, major, paths })
  }

  return {
    summary: {
      interval,
      segmentCount,
      pathCount,
      sampleCount: grid.values.filter(Number.isFinite).length,
      min: grid.min,
      max: grid.max,
    },
    levels,
  }
}

export function gridCellMetrics(grid: TerrainGrid) {
  const centerLat = (grid.south + grid.north) / 2
  const lonStep = Math.abs(grid.east - grid.west) / Math.max(1, grid.size - 1)
  const latStep = Math.abs(grid.north - grid.south) / Math.max(1, grid.size - 1)
  const eastWestM = lonStep * 111320 * Math.max(0.2, Math.cos(centerLat * Math.PI / 180))
  const northSouthM = latStep * 111320
  const cellAreaM2 = eastWestM * northSouthM
  return {
    east_west_m: eastWestM,
    north_south_m: northSouthM,
    cell_area_m2: cellAreaM2,
    cell_area_acres: cellAreaM2 / 4046.8564224,
  }
}

export function neighborCells(grid: TerrainGrid, index: number) {
  const row = Math.floor(index / grid.size)
  const col = index % grid.size
  const metrics = gridCellMetrics(grid)
  const neighbors: Array<{ index: number; distance_m: number }> = []
  for (let dr = -1; dr <= 1; dr += 1) {
    for (let dc = -1; dc <= 1; dc += 1) {
      if (dr === 0 && dc === 0) continue
      const r = row + dr
      const c = col + dc
      if (r < 0 || r >= grid.size || c < 0 || c >= grid.size) continue
      const dx = Math.abs(dc) * metrics.east_west_m
      const dy = Math.abs(dr) * metrics.north_south_m
      neighbors.push({
        index: r * grid.size + c,
        distance_m: Math.hypot(dx, dy),
      })
    }
  }
  return neighbors
}

type FlowConditioning = {
  filledValues: Array<number | null>
  parent: number[]
  routableMask: boolean[]
  filledCellCount: number
  maxFillDepthFt: number
  excludedDisconnectedCellCount: number
}

function conditionFlowSurface(grid: TerrainGrid): FlowConditioning {
  const count = grid.values.length
  const filledValues: Array<number | null> = grid.values.map((value) =>
    Number.isFinite(value) ? Number(value) : null
  )
  const parent = new Array(count).fill(-1)
  const visited = new Array(count).fill(false)
  const heap: Array<{ index: number; elevation: number }> = []

  function heapPush(item: { index: number; elevation: number }) {
    heap.push(item)
    let i = heap.length - 1
    while (i > 0) {
      const p = Math.floor((i - 1) / 2)
      if (heap[p].elevation <= heap[i].elevation) break
      ;[heap[p], heap[i]] = [heap[i], heap[p]]
      i = p
    }
  }

  function heapPop() {
    if (!heap.length) return null
    const root = heap[0]
    const last = heap.pop()!
    if (heap.length) {
      heap[0] = last
      let i = 0
      while (true) {
        const left = i * 2 + 1
        const right = left + 1
        let smallest = i
        if (left < heap.length && heap[left].elevation < heap[smallest].elevation) smallest = left
        if (right < heap.length && heap[right].elevation < heap[smallest].elevation) smallest = right
        if (smallest === i) break
        ;[heap[i], heap[smallest]] = [heap[smallest], heap[i]]
        i = smallest
      }
    }
    return root
  }

  function seed(index: number) {
    if (visited[index] || !Number.isFinite(filledValues[index])) return
    visited[index] = true
    heapPush({ index, elevation: Number(filledValues[index]) })
  }

  for (let index = 0; index < count; index += 1) {
    if (!Number.isFinite(filledValues[index])) continue
    const row = Math.floor(index / grid.size)
    const col = index % grid.size
    const perimeter = row === 0 || col === 0 || row === grid.size - 1 || col === grid.size - 1
    if (perimeter) seed(index)
  }

  let filledCellCount = 0
  let maxFillDepthFt = 0

  function flood() {
    while (heap.length) {
      const current = heapPop()!
      for (const neighbor of neighborCells(grid, current.index)) {
        if (visited[neighbor.index] || !Number.isFinite(filledValues[neighbor.index])) continue
        visited[neighbor.index] = true
        const original = Number(grid.values[neighbor.index])
        const conditioned = Math.max(original, current.elevation)
        filledValues[neighbor.index] = conditioned
        parent[neighbor.index] = current.index
        const fillDepth = conditioned - original
        if (fillDepth > 1e-9) {
          filledCellCount += 1
          maxFillDepthFt = Math.max(maxFillDepthFt, fillDepth)
        }
        heapPush({ index: neighbor.index, elevation: conditioned })
      }
    }
  }

  flood()

  const excludedDisconnectedCellCount = filledValues.reduce(
    (countDisconnected, value, index) =>
      Number.isFinite(value) && !visited[index] ? countDisconnected + 1 : countDisconnected,
    0,
  )

  return {
    filledValues,
    parent,
    routableMask: visited,
    filledCellCount,
    maxFillDepthFt,
    excludedDisconnectedCellCount,
  }
}

export function buildFlowNetwork(grid: TerrainGrid) {
  const conditioning = conditionFlowSurface(grid)
  const downstream = new Array(grid.values.length).fill(-1)
  const accumulation = new Array(grid.values.length).fill(0)
  const validIndexes = grid.values
    .map((value, index) =>
      Number.isFinite(value) && conditioning.routableMask[index] ? index : -1
    )
    .filter((index) => index >= 0)

  for (const index of validIndexes) {
    const value = Number(conditioning.filledValues[index])
    let best = -1
    let bestSlope = 0
    for (const neighbor of neighborCells(grid, index)) {
      const neighborValue = conditioning.filledValues[neighbor.index]
      if (!Number.isFinite(neighborValue) || neighbor.distance_m <= 0) continue
      const drop = value - Number(neighborValue)
      if (drop <= 1e-9) continue
      const slope = drop / neighbor.distance_m
      if (slope > bestSlope) {
        best = neighbor.index
        bestSlope = slope
      }
    }

    if (best < 0) {
      const parent = conditioning.parent[index]
      if (
        parent >= 0 &&
        Number.isFinite(conditioning.filledValues[parent]) &&
        Number(conditioning.filledValues[parent]) <= value + 1e-9
      ) best = parent
    }

    downstream[index] = best
    accumulation[index] = 1
  }

  const upstream: number[][] = Array.from({ length: grid.values.length }, () => [])
  const indegree = new Array(grid.values.length).fill(0)
  for (const index of validIndexes) {
    const next = downstream[index]
    if (next < 0) continue
    upstream[next].push(index)
    indegree[next] += 1
  }

  const queue = validIndexes.filter((index) => indegree[index] === 0)
  let cursor = 0
  let processed = 0
  while (cursor < queue.length) {
    const index = queue[cursor++]
    processed += 1
    const next = downstream[index]
    if (next < 0) continue
    accumulation[next] += accumulation[index]
    indegree[next] -= 1
    if (indegree[next] === 0) queue.push(next)
  }

  return {
    downstream,
    accumulation,
    upstream,
    validIndexes,
    conditioning: {
      filled_cell_count: conditioning.filledCellCount,
      max_fill_depth_ft: conditioning.maxFillDepthFt,
      excluded_disconnected_cell_count: conditioning.excludedDisconnectedCellCount,
      unresolved_flow_cell_count: Math.max(0, validIndexes.length - processed),
      routing_surface: 'priority_flood_conditioned_sampled_dem',
    },
    cell_metrics: gridCellMetrics(grid),
  }
}

export function gridDirection(grid: TerrainGrid, index: number) {
  const [lon, lat] = grid.points[index] || []
  if (!Number.isFinite(lon) || !Number.isFinite(lat)) return 'unknown'
  const centerLon = (grid.west + grid.east) / 2
  const centerLat = (grid.south + grid.north) / 2
  const dx = (lon - centerLon) / Math.max(Number.EPSILON, grid.east - grid.west)
  const dy = (lat - centerLat) / Math.max(Number.EPSILON, grid.north - grid.south)
  if (Math.abs(dx) < 0.12 && Math.abs(dy) < 0.12) return 'central'
  const angle = (Math.atan2(dx, dy) * 180 / Math.PI + 360) % 360
  const labels = ['north', 'northeast', 'east', 'southeast', 'south', 'southwest', 'west', 'northwest']
  return labels[Math.round(angle / 45) % 8]
}

export function deriveTerrainAnatomy(
  grid: TerrainGrid,
  statedAcres: number | null | undefined,
  network = buildFlowNetwork(grid),
) {
  const interior = network.validIndexes.filter((index) => {
    const [lon, lat] = grid.points[index]
    return pointInPolygonGeometry(lon, lat, grid.boundary)
  })
  if (!interior.length) return null

  const highIndex = interior.reduce(
    (best, index) => Number(grid.values[index]) > Number(grid.values[best]) ? index : best,
    interior[0],
  )
  const lowIndex = interior.reduce(
    (best, index) => Number(grid.values[index]) < Number(grid.values[best]) ? index : best,
    interior[0],
  )

  const terminalMemo = new Map<number, { kind: string; index: number }>()
  function terminalFor(start: number) {
    if (terminalMemo.has(start)) return terminalMemo.get(start)!
    const path: number[] = []
    const seen = new Set<number>()
    let cursor = start
    let terminal: { kind: string; index: number } | null = null

    while (cursor >= 0 && !seen.has(cursor)) {
      if (terminalMemo.has(cursor)) {
        terminal = terminalMemo.get(cursor)!
        break
      }
      seen.add(cursor)
      path.push(cursor)
      const [lon, lat] = grid.points[cursor]
      const inside = pointInPolygonGeometry(lon, lat, grid.boundary)
      if (!inside && cursor !== start) {
        terminal = { kind: 'exit', index: cursor }
        break
      }
      const next = network.downstream[cursor]
      if (next < 0) {
        terminal = { kind: 'grid_terminal', index: cursor }
        break
      }
      cursor = next
    }

    if (!terminal) terminal = { kind: 'grid_terminal', index: cursor >= 0 ? cursor : start }
    for (const index of path) terminalMemo.set(index, terminal)
    return terminal
  }

  const exitGroups = new Map<number, { index: number; count: number }>()
  for (const index of interior) {
    const terminal = terminalFor(index)
    if (terminal.kind !== 'exit') continue
    const row = exitGroups.get(terminal.index) || { index: terminal.index, count: 0 }
    row.count += 1
    exitGroups.set(terminal.index, row)
  }

  const exitRows = [...exitGroups.values()]
  const remaining = new Set(exitRows.map((row) => row.index))
  const clusters: Array<{ count: number; index: number }> = []

  while (remaining.size) {
    const seed = remaining.values().next().value as number
    const queue = [seed]
    remaining.delete(seed)
    const members: Array<{ index: number; count: number }> = []
    while (queue.length) {
      const current = queue.shift()!
      members.push(exitGroups.get(current)!)
      const currentRow = Math.floor(current / grid.size)
      const currentCol = current % grid.size
      for (const candidate of [...remaining]) {
        const row = Math.floor(candidate / grid.size)
        const col = candidate % grid.size
        if (Math.abs(row - currentRow) <= 2 && Math.abs(col - currentCol) <= 2) {
          remaining.delete(candidate)
          queue.push(candidate)
        }
      }
    }
    const count = members.reduce((sum, member) => sum + member.count, 0)
    const representative = members.slice().sort((a, b) => b.count - a.count)[0]
    clusters.push({ count, index: representative.index })
  }

  const total = interior.length
  const acres = Number(statedAcres)
  const outletZones = clusters
    .map((cluster) => ({
      direction: gridDirection(grid, cluster.index),
      sampled_cell_count: cluster.count,
      sampled_percent: cluster.count / total * 100,
      estimated_acres: Number.isFinite(acres) ? acres * cluster.count / total : null,
    }))
    .sort((a, b) => b.sampled_percent - a.sampled_percent)

  const routedExitCount = [...exitGroups.values()].reduce((sum, row) => sum + row.count, 0)

  return {
    method: '61x61_sampled_dem_conditioned_d8',
    routing_scope: 'priority_flood_conditioned_metric_d8',
    sample_count: total,
    sampled_high: {
      elevation_ft: grid.values[highIndex],
      parcel_sector: gridDirection(grid, highIndex),
    },
    sampled_low: {
      elevation_ft: grid.values[lowIndex],
      parcel_sector: gridDirection(grid, lowIndex),
    },
    outlet_zone_count: outletZones.length,
    outlet_zones: outletZones,
    outlet_routed_percent: routedExitCount / total * 100,
    conditioning: network.conditioning,
  }
}

function traceFlowIndexes(grid: TerrainGrid, downstream: number[], start: number) {
  const indexes: number[] = []
  const seen = new Set<number>()
  let cursor = start
  while (cursor >= 0 && indexes.length < grid.values.length && !seen.has(cursor)) {
    seen.add(cursor)
    indexes.push(cursor)
    const [lon, lat] = grid.points[cursor]
    if (!pointInPolygonGeometry(lon, lat, grid.boundary) && indexes.length > 1) break
    cursor = downstream[cursor]
  }
  return indexes
}

export function buildFlowProduct(grid: TerrainGrid, network = buildFlowNetwork(grid)) {
  const minAreaAcres = FARM_WATCH_TERRAIN_PRODUCT.flowMinContributingAreaAcres
  const thresholdCells = Math.max(
    2,
    Math.ceil(minAreaAcres / Math.max(Number.EPSILON, network.cell_metrics.cell_area_acres)),
  )

  const channelIndexes = network.validIndexes.filter((index) => {
    const [lon, lat] = grid.points[index]
    return network.accumulation[index] >= thresholdCells &&
      pointInPolygonGeometry(lon, lat, grid.boundary)
  })
  const channelSet = new Set(channelIndexes)

  let starts = channelIndexes.filter((index) => {
    const upstreamInside = network.upstream[index].filter((upstreamIndex) => {
      if (!channelSet.has(upstreamIndex)) return false
      const [lon, lat] = grid.points[upstreamIndex]
      return pointInPolygonGeometry(lon, lat, grid.boundary)
    })
    return upstreamInside.length === 0
  })

  if (!starts.length && channelIndexes.length) starts = channelIndexes.slice()

  const ranked = starts
    .map((index) => ({
      index,
      fullPath: traceFlowIndexes(grid, network.downstream, index),
      startAccumulation: network.accumulation[index],
    }))
    .sort((a, b) =>
      b.fullPath.length - a.fullPath.length ||
      b.startAccumulation - a.startAccumulation ||
      a.index - b.index
    )

  const used = new Set<number>()
  const paths: number[][][] = []

  for (const candidate of ranked) {
    if (paths.length >= FARM_WATCH_TERRAIN_PRODUCT.flowMaxTraces) break
    const indexes: number[] = []
    const seen = new Set<number>()
    let cursor = candidate.index

    while (cursor >= 0 && indexes.length < grid.values.length && !seen.has(cursor)) {
      seen.add(cursor)
      if (used.has(cursor) && indexes.length > 0) {
        indexes.push(cursor)
        break
      }
      indexes.push(cursor)
      used.add(cursor)
      const [lon, lat] = grid.points[cursor]
      if (!pointInPolygonGeometry(lon, lat, grid.boundary) && indexes.length > 1) break
      cursor = network.downstream[cursor]
    }

    if (indexes.length >= 3) {
      paths.push(indexes.map((index) => [grid.points[index][1], grid.points[index][0]]))
    }
  }

  return {
    paths,
    summary: {
      routing_scope: 'priority_flood_conditioned_metric_d8',
      min_contributing_area_acres: minAreaAcres,
      threshold_cells: thresholdCells,
      cell_area_acres: network.cell_metrics.cell_area_acres,
      cell_east_west_m: network.cell_metrics.east_west_m,
      cell_north_south_m: network.cell_metrics.north_south_m,
      channel_cell_count: channelIndexes.length,
      headwater_candidate_count: starts.length,
      path_count: paths.length,
      max_trace_count: FARM_WATCH_TERRAIN_PRODUCT.flowMaxTraces,
      conditioning: network.conditioning,
    },
  }
}

export function buildFlowPaths(grid: TerrainGrid) {
  return buildFlowProduct(grid).paths
}

export async function sha256Hex(value: string | Uint8Array) {
  const source = typeof value === 'string' ? new TextEncoder().encode(value) : value
  const bytes = new Uint8Array(source.byteLength)
  bytes.set(source)
  const digest = await crypto.subtle.digest('SHA-256', bytes.buffer)
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('')
}

export async function buildTerrainArtifact(
  boundary: GeoJsonGeometry,
  statedAcres: number | null | undefined,
  fetchImpl: typeof fetch = fetch,
) {
  const grid = await sampleDem(boundary, fetchImpl)
  const contours = buildContourProduct(grid)
  const flowNetwork = buildFlowNetwork(grid)
  const flowProduct = buildFlowProduct(grid, flowNetwork)
  const anatomy = deriveTerrainAnatomy(grid, statedAcres, flowNetwork)
  const sampledSourceSha256 = await sha256Hex(JSON.stringify(grid.values))

  return {
    sampledSourceSha256,
    artifact: {
      schema: FARM_WATCH_TERRAIN_PRODUCT.outputSchemaVersion,
      method: FARM_WATCH_TERRAIN_PRODUCT.algorithmVersion,
      grid,
      contours,
      flow_paths: flowProduct.paths,
      flow_summary: flowProduct.summary,
      anatomy,
    },
  }
}
