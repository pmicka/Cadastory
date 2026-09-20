#!/usr/bin/env -S deno run --allow-env --allow-net

import { Buffer } from 'node:buffer'
import { PNG } from 'npm:pngjs@7.0.0'
import {
  FARM_WATCH_LEAF_OFF_PRODUCT,
} from '../supabase/functions/_shared/farm-watch-leaf-off-contract.ts'
import { FARM_WATCH_GITHUB_OIDC_AUDIENCE } from '../supabase/functions/_shared/github-actions-oidc.ts'

const EDGE_URL =
  'https://ufpkjaadmmpmeogzhrcq.supabase.co/functions/v1/farm-watch-leaf-off-worker'
const propertySlug = arg('--property', 'validation-property-01')!

function arg(name: string, fallback: string | null = null) {
  const index = Deno.args.indexOf(name)
  if (index < 0) return fallback
  const value = Deno.args[index + 1]
  if (!value || value.startsWith('--')) throw new Error(name + ' requires a value')
  return value
}

function clamp(value: number, min = 0, max = 1) {
  return Math.max(min, Math.min(max, value))
}

function degrees(value: number) {
  return value * 180 / Math.PI
}

function radians(value: number) {
  return value * Math.PI / 180
}

function solarPosition(timestamp: string, lat: number, lon: number) {
  const date = new Date(timestamp)
  const julianDay = date.getTime() / 86400000 + 2440587.5
  const t = (julianDay - 2451545.0) / 36525
  const meanLongitude = ((280.46646 + t * (36000.76983 + t * 0.0003032)) % 360 + 360) % 360
  const meanAnomaly = 357.52911 + t * (35999.05029 - 0.0001537 * t)
  const eccentricity = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
  const anomaly = radians(meanAnomaly)
  const equationOfCenter =
    (1.914602 - t * (0.004817 + 0.000014 * t)) * Math.sin(anomaly) +
    (0.019993 - 0.000101 * t) * Math.sin(2 * anomaly) +
    0.000289 * Math.sin(3 * anomaly)
  const trueLongitude = meanLongitude + equationOfCenter
  const omega = 125.04 - 1934.136 * t
  const apparentLongitude = trueLongitude - 0.00569 - 0.00478 * Math.sin(radians(omega))
  const meanObliquity = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
  const obliquity = meanObliquity + 0.00256 * Math.cos(radians(omega))
  const declination = degrees(Math.asin(Math.sin(radians(obliquity)) * Math.sin(radians(apparentLongitude))))
  const y = Math.tan(radians(obliquity / 2)) ** 2
  const equationOfTime = 4 * degrees(
    y * Math.sin(2 * radians(meanLongitude)) -
    2 * eccentricity * Math.sin(anomaly) +
    4 * eccentricity * y * Math.sin(anomaly) * Math.cos(2 * radians(meanLongitude)) -
    0.5 * y * y * Math.sin(4 * radians(meanLongitude)) -
    1.25 * eccentricity * eccentricity * Math.sin(2 * anomaly)
  )
  const utcMinutes = date.getUTCHours() * 60 + date.getUTCMinutes() + date.getUTCSeconds() / 60
  const trueSolarMinutes = ((utcMinutes + equationOfTime + 4 * lon) % 1440 + 1440) % 1440
  let hourAngle = trueSolarMinutes / 4 - 180
  if (hourAngle < -180) hourAngle += 360

  const latRad = radians(lat)
  const declinationRad = radians(declination)
  const hourAngleRad = radians(hourAngle)
  const cosZenith = clamp(
    Math.sin(latRad) * Math.sin(declinationRad) +
    Math.cos(latRad) * Math.cos(declinationRad) * Math.cos(hourAngleRad),
    -1,
    1,
  )
  const altitude = 90 - degrees(Math.acos(cosZenith))
  const azimuth = (degrees(Math.atan2(
    Math.sin(hourAngleRad),
    Math.cos(hourAngleRad) * Math.sin(latRad) - Math.tan(declinationRad) * Math.cos(latRad),
  )) + 180 + 360) % 360
  return { altitude, azimuth }
}

function flattenCoordinates(value: any, out: Array<[number, number]> = []) {
  if (!Array.isArray(value)) return out
  if (
    value.length >= 2 &&
    Number.isFinite(Number(value[0])) &&
    Number.isFinite(Number(value[1]))
  ) {
    out.push([Number(value[0]), Number(value[1])])
    return out
  }
  for (const child of value) flattenCoordinates(child, out)
  return out
}

function projectWebMercator(lon: number, lat: number) {
  const radius = 6378137
  const limitedLat = Math.max(-85.05112878, Math.min(85.05112878, lat))
  return [
    radius * radians(lon),
    radius * Math.log(Math.tan(Math.PI / 4 + radians(limitedLat) / 2)),
  ]
}

function projectBoundaryGeometry(geometry: any): any {
  const projectRing = (ring: any[]) =>
    ring.map(([lon, lat]) => projectWebMercator(Number(lon), Number(lat)))
  if (geometry?.type === 'Polygon') {
    return { type: 'Polygon', coordinates: geometry.coordinates.map(projectRing) }
  }
  if (geometry?.type === 'MultiPolygon') {
    return {
      type: 'MultiPolygon',
      coordinates: geometry.coordinates.map((polygon: any[]) => polygon.map(projectRing)),
    }
  }
  return null
}

function pointInRing(x: number, y: number, ring: any[]) {
  let inside = false
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const xi = Number(ring[i][0])
    const yi = Number(ring[i][1])
    const xj = Number(ring[j][0])
    const yj = Number(ring[j][1])
    const crosses = ((yi > y) !== (yj > y)) &&
      (x < ((xj - xi) * (y - yi)) / ((yj - yi) || Number.EPSILON) + xi)
    if (crosses) inside = !inside
  }
  return inside
}

function pointInPolygonGeometry(x: number, y: number, geometry: any) {
  const polygons = geometry?.type === 'Polygon'
    ? [geometry.coordinates]
    : geometry?.type === 'MultiPolygon' ? geometry.coordinates : []
  return polygons.some((polygon: any[]) => {
    const [outer, ...holes] = polygon
    if (!outer || !pointInRing(x, y, outer)) return false
    return !holes.some((hole) => pointInRing(x, y, hole))
  })
}

function projectedBounds(geometry: any) {
  const coords = flattenCoordinates(geometry?.coordinates)
  if (!coords.length) return null
  const projected = coords.map(([lon, lat]) => projectWebMercator(lon, lat))
  const xs = projected.map((point) => point[0])
  const ys = projected.map((point) => point[1])
  return {
    west: Math.min(...xs) - FARM_WATCH_LEAF_OFF_PRODUCT.analysisPadMeters,
    east: Math.max(...xs) + FARM_WATCH_LEAF_OFF_PRODUCT.analysisPadMeters,
    south: Math.min(...ys) - FARM_WATCH_LEAF_OFF_PRODUCT.analysisPadMeters,
    north: Math.max(...ys) + FARM_WATCH_LEAF_OFF_PRODUCT.analysisPadMeters,
  }
}

function rasterDimensions(bounds: any, targetPixelM: number, maxDimension: number) {
  const widthM = bounds.east - bounds.west
  const heightM = bounds.north - bounds.south
  const pixelM = Math.max(targetPixelM, widthM / maxDimension, heightM / maxDimension)
  return {
    width: Math.max(1, Math.ceil(widthM / pixelM)),
    height: Math.max(1, Math.ceil(heightM / pixelM)),
    pixelM,
  }
}

async function sha256Hex(value: Uint8Array | string) {
  const bytes = typeof value === 'string' ? new TextEncoder().encode(value) : value
  const stableBytes = Uint8Array.from(bytes)
  const digest = await crypto.subtle.digest('SHA-256', stableBytes.buffer)
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, '0')).join('')
}

function trimPngStream(bytes: Uint8Array) {
  const signature = [137, 80, 78, 71, 13, 10, 26, 10]
  if (bytes.length < 20 || !signature.every((value, index) => bytes[index] === value)) {
    throw new Error('Raster response is not a PNG stream')
  }
  let offset = 8
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength)
  while (offset + 12 <= bytes.length) {
    const length = view.getUint32(offset, false)
    const typeOffset = offset + 4
    const end = offset + 12 + length
    if (end > bytes.length) throw new Error('PNG chunk exceeds response length')
    const type = String.fromCharCode(
      bytes[typeOffset],
      bytes[typeOffset + 1],
      bytes[typeOffset + 2],
      bytes[typeOffset + 3],
    )
    if (type === 'IEND') return bytes.slice(0, end)
    offset = end
  }
  throw new Error('PNG IEND chunk is unavailable')
}

async function fetchRaster(
  baseUrl: string,
  bounds: any,
  dimensions: any,
  renderingRule: any = null,
) {
  const url = new URL(baseUrl + '/exportImage')
  url.searchParams.set('bbox', [bounds.west, bounds.south, bounds.east, bounds.north].join(','))
  url.searchParams.set('bboxSR', '3857')
  url.searchParams.set('imageSR', '3857')
  url.searchParams.set('size', dimensions.width + ',' + dimensions.height)
  url.searchParams.set('adjustAspectRatio', 'false')
  url.searchParams.set('format', 'png32')
  url.searchParams.set('interpolation', 'RSP_BilinearInterpolation')
  url.searchParams.set('f', 'image')
  if (renderingRule) url.searchParams.set('renderingRule', JSON.stringify(renderingRule))

  let lastError: Error | null = null
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    try {
      const response = await fetch(url, {
        headers: {
          accept: 'image/png,image/*',
          'user-agent': 'Cadastory-Farm-Watch/0.6 (https://pmicka.com)',
        },
      })
      if (!response.ok) throw new Error('Raster source returned ' + response.status)
      const bytes = new Uint8Array(await response.arrayBuffer())
      const isPng =
        bytes.length >= 8 &&
        bytes[0] === 137 && bytes[1] === 80 && bytes[2] === 78 && bytes[3] === 71 &&
        bytes[4] === 13 && bytes[5] === 10 && bytes[6] === 26 && bytes[7] === 10
      if (!isPng) {
        const contentType = response.headers.get('content-type') || 'unknown'
        const prefix = new TextDecoder().decode(bytes.slice(0, Math.min(240, bytes.length)))
          .replace(/\\s+/g, ' ')
          .slice(0, 240)
        throw new Error(
          'Raster response is not PNG; content-type=' + contentType +
          '; bytes=' + bytes.length + '; prefix=' + prefix,
        )
      }
      const pngBytes = trimPngStream(bytes)
      const png = PNG.sync.read(Buffer.from(pngBytes))
      if (png.width !== dimensions.width || png.height !== dimensions.height) {
        throw new Error(
          'Raster dimension mismatch: expected ' + dimensions.width + 'x' + dimensions.height +
          ', received ' + png.width + 'x' + png.height,
        )
      }
      return {
        rgba: new Uint8Array(png.data),
        sha256: await sha256Hex(bytes),
        request_url: url.toString(),
        byte_length: bytes.byteLength,
      }
    } catch (error) {
      lastError = error instanceof Error ? error : new Error(String(error))
      if (attempt < 3) await new Promise((resolve) => setTimeout(resolve, attempt * 1000))
    }
  }
  throw lastError || new Error('Raster source unavailable')
}

function buildIntegral(values: Float32Array, width: number, height: number) {
  const stride = width + 1
  const integral = new Float64Array((width + 1) * (height + 1))
  for (let y = 0; y < height; y += 1) {
    let rowSum = 0
    const outRow = (y + 1) * stride
    const previousRow = y * stride
    const rowOffset = y * width
    for (let x = 0; x < width; x += 1) {
      rowSum += values[rowOffset + x]
      integral[outRow + x + 1] = integral[previousRow + x + 1] + rowSum
    }
  }
  return integral
}

function rectSum(
  integral: Float64Array,
  width: number,
  height: number,
  x0: number,
  y0: number,
  x1: number,
  y1: number,
) {
  const stride = width + 1
  const left = Math.max(0, x0)
  const top = Math.max(0, y0)
  const right = Math.min(width, x1)
  const bottom = Math.min(height, Math.max(top, y1))
  if (right <= left || bottom <= top) return 0
  return integral[bottom * stride + right] -
    integral[top * stride + right] -
    integral[bottom * stride + left] +
    integral[top * stride + left]
}

function buildTextureIntegrals(rgba: Uint8Array, width: number, height: number) {
  const count = width * height
  const luminance = new Float32Array(count)
  const valid = new Float32Array(count)
  const gradient = new Float32Array(count)
  const gradientValid = new Float32Array(count)

  for (let index = 0; index < count; index += 1) {
    const alpha = rgba[index * 4 + 3]
    if (alpha <= 0) continue
    const r = rgba[index * 4]
    const g = rgba[index * 4 + 1]
    const b = rgba[index * 4 + 2]
    luminance[index] = 0.2126 * r + 0.7152 * g + 0.0722 * b
    valid[index] = 1
  }

  for (let y = 1; y < height - 1; y += 1) {
    for (let x = 1; x < width - 1; x += 1) {
      const index = y * width + x
      const left = index - 1
      const right = index + 1
      const up = index - width
      const down = index + width
      if (!(valid[index] && valid[left] && valid[right] && valid[up] && valid[down])) continue
      const gx = (luminance[right] - luminance[left]) / 2
      const gy = (luminance[down] - luminance[up]) / 2
      gradient[index] = Math.hypot(gx, gy)
      gradientValid[index] = 1
    }
  }

  const luminanceSquared = new Float32Array(count)
  for (let index = 0; index < count; index += 1) {
    if (valid[index]) luminanceSquared[index] = luminance[index] * luminance[index]
  }

  return {
    luminance: buildIntegral(luminance, width, height),
    luminanceSquared: buildIntegral(luminanceSquared, width, height),
    valid: buildIntegral(valid, width, height),
    gradient: buildIntegral(gradient, width, height),
    gradientValid: buildIntegral(gradientValid, width, height),
  }
}

function windowTexture(
  integrals: any,
  width: number,
  height: number,
  centerX: number,
  centerY: number,
  radius: number,
) {
  const x0 = centerX - radius
  const y0 = centerY - radius
  const x1 = centerX + radius + 1
  const y1 = centerY + radius + 1
  const count = rectSum(integrals.valid, width, height, x0, y0, x1, y1)
  const expected = Math.max(
    1,
    (Math.min(width, x1) - Math.max(0, x0)) * (Math.min(height, y1) - Math.max(0, y0)),
  )
  if (count < expected * 0.85) return null

  const sum = rectSum(integrals.luminance, width, height, x0, y0, x1, y1)
  const sumSquared = rectSum(integrals.luminanceSquared, width, height, x0, y0, x1, y1)
  const mean = sum / count
  const variance = Math.max(0, sumSquared / count - mean * mean)
  const gradientCount = rectSum(integrals.gradientValid, width, height, x0, y0, x1, y1)
  const gradientMean = gradientCount > 0
    ? rectSum(integrals.gradient, width, height, x0, y0, x1, y1) / gradientCount
    : 0
  return { mean, standardDeviation: Math.sqrt(variance), gradientMean }
}

function buildFalseColorIntegrals(rgba: Uint8Array, width: number, height: number) {
  const count = width * height
  const red = new Float32Array(count)
  const green = new Float32Array(count)
  const blue = new Float32Array(count)
  const valid = new Float32Array(count)

  for (let index = 0; index < count; index += 1) {
    if (rgba[index * 4 + 3] <= 0) continue
    red[index] = rgba[index * 4]
    green[index] = rgba[index * 4 + 1]
    blue[index] = rgba[index * 4 + 2]
    valid[index] = 1
  }

  return {
    red: buildIntegral(red, width, height),
    green: buildIntegral(green, width, height),
    blue: buildIntegral(blue, width, height),
    valid: buildIntegral(valid, width, height),
  }
}

function windowFalseColorSupport(
  integrals: any,
  width: number,
  height: number,
  centerX: number,
  centerY: number,
  radius: number,
) {
  const x0 = centerX - radius
  const y0 = centerY - radius
  const x1 = centerX + radius + 1
  const y1 = centerY + radius + 1
  const count = rectSum(integrals.valid, width, height, x0, y0, x1, y1)
  const expected = Math.max(
    1,
    (Math.min(width, x1) - Math.max(0, x0)) * (Math.min(height, y1) - Math.max(0, y0)),
  )
  if (count < expected * 0.85) return null
  const red = rectSum(integrals.red, width, height, x0, y0, x1, y1) / count
  const green = rectSum(integrals.green, width, height, x0, y0, x1, y1) / count
  const blue = rectSum(integrals.blue, width, height, x0, y0, x1, y1) / count
  const redVsGreen = (red - green) / Math.max(1, red + green)
  const redVsBlue = (red - blue) / Math.max(1, red + blue)
  return Math.min(redVsGreen, redVsBlue)
}

function percentile(values: number[], p: number) {
  if (!values.length) return null
  const sorted = values.slice().sort((a, b) => a - b)
  const position = clamp(p) * (sorted.length - 1)
  const lower = Math.floor(position)
  const upper = Math.ceil(position)
  if (lower === upper) return sorted[lower]
  const weight = position - lower
  return sorted[lower] * (1 - weight) + sorted[upper] * weight
}

function robustNormalize(value: number, low: number | null, high: number | null) {
  if (![value, low, high].every(Number.isFinite) || Number(high) <= Number(low)) return 0
  return clamp((value - Number(low)) / (Number(high) - Number(low)))
}

function slopeEncodingRule() {
  const slope = {
    rasterFunction: 'Slope',
    rasterFunctionArguments: {
      ZFactor: 0.3048,
      SlopeType: 2,
      RemoveEdgeEffect: true,
    },
    outputPixelType: 'F32',
    variableName: 'DEM',
  }
  return {
    rasterFunction: 'Stretch',
    rasterFunctionArguments: {
      StretchType: 5,
      Statistics: [[0, 100, 25, 20]],
      Min: 0,
      Max: 255,
      UseGamma: false,
      Raster: slope,
    },
    outputPixelType: 'U8',
    variableName: 'Raster',
  }
}

function hillshadeRule(sun: any) {
  return {
    rasterFunction: 'Hillshade',
    rasterFunctionArguments: {
      HillshadeType: 0,
      Azimuth: sun.azimuth,
      Altitude: sun.altitude,
      ZFactor: 0.3048,
      SlopeType: 1,
      RemoveEdgeEffect: true,
    },
    outputPixelType: 'U8',
    variableName: 'DEM',
  }
}

function scaleRadiusPixels(targetDiameterM: number, pixelM: number) {
  return Math.max(1, Math.round((targetDiameterM - pixelM) / (2 * pixelM)))
}

function summarizeScoreDistribution(score: Uint8Array, valid: Uint8Array) {
  const values: number[] = []
  const bins = new Array(10).fill(0)
  let exactZero = 0
  let exactOne = 0
  let lowEndpoint = 0
  let highEndpoint = 0
  let sum = 0

  for (let index = 0; index < score.length; index += 1) {
    if (!valid[index]) continue
    const value = score[index] / 255
    values.push(value)
    sum += value
    bins[Math.min(9, Math.floor(value * 10))] += 1
    if (score[index] === 0) exactZero += 1
    if (score[index] === 255) exactOne += 1
    if (value <= 0.05) lowEndpoint += 1
    if (value >= 0.95) highEndpoint += 1
  }

  const count = values.length
  if (!count) return null
  return {
    sample_count: count,
    mean: sum / count,
    p10: percentile(values, 0.10),
    p25: percentile(values, 0.25),
    median: percentile(values, 0.50),
    p75: percentile(values, 0.75),
    p90: percentile(values, 0.90),
    exact_zero_percent: exactZero / count * 100,
    exact_one_percent: exactOne / count * 100,
    low_endpoint_percent: lowEndpoint / count * 100,
    high_endpoint_percent: highEndpoint / count * 100,
    histogram_10pct: bins.map((binCount, index) => ({
      min: index / 10,
      max: (index + 1) / 10,
      percent: binCount / count * 100,
    })),
  }
}

function rankLookupForOverlap(score: Uint8Array, validA: Uint8Array, validB: Uint8Array) {
  const counts = new Uint32Array(256)
  let count = 0
  for (let index = 0; index < score.length; index += 1) {
    if (!validA[index] || !validB[index]) continue
    counts[score[index]] += 1
    count += 1
  }
  if (!count) return null
  const averageRank = new Float64Array(256)
  let cumulative = 0
  for (let value = 0; value < 256; value += 1) {
    const n = counts[value]
    if (!n) continue
    averageRank[value] = cumulative + (n + 1) / 2
    cumulative += n
  }
  return { count, averageRank }
}

function pearsonFromRankLookups(a: any, b: any, lookupA: any, lookupB: any) {
  const count = lookupA?.count || 0
  if (!count || count !== lookupB?.count) return null
  let sumA = 0
  let sumB = 0
  let sumA2 = 0
  let sumB2 = 0
  let sumAB = 0
  for (let index = 0; index < a.score.length; index += 1) {
    if (!a.valid[index] || !b.valid[index]) continue
    const rankA = lookupA.averageRank[a.score[index]]
    const rankB = lookupB.averageRank[b.score[index]]
    sumA += rankA
    sumB += rankB
    sumA2 += rankA * rankA
    sumB2 += rankB * rankB
    sumAB += rankA * rankB
  }
  const numerator = count * sumAB - sumA * sumB
  const denominator = Math.sqrt(
    Math.max(0, count * sumA2 - sumA * sumA) *
    Math.max(0, count * sumB2 - sumB * sumB)
  )
  return denominator > 0 ? numerator / denominator : null
}

function quintileForRank(rank: number, count: number) {
  if (!(count > 1) || !Number.isFinite(rank)) return 2
  const percentileRank = (rank - 1) / (count - 1)
  return Math.min(4, Math.max(0, Math.floor(percentileRank * 5)))
}

function diceOverlap(intersection: number, countA: number, countB: number) {
  const denominator = countA + countB
  return denominator ? 2 * intersection / denominator : null
}

function compareIndependentStructureProducts(a: any, b: any) {
  if (!a || !b) return null
  if (a.width !== b.width || a.height !== b.height || a.score.length !== b.score.length) {
    return { status: 'grid_mismatch' }
  }
  const lookupA = rankLookupForOverlap(a.score, a.valid, b.valid)
  const lookupB = rankLookupForOverlap(b.score, b.valid, a.valid)
  const count = lookupA?.count || 0
  if (!lookupA || !lookupB || count < 100 || count !== lookupB.count) {
    return { status: 'insufficient_overlap', overlap_cell_count: count }
  }

  const spearman = pearsonFromRankLookups(a, b, lookupA, lookupB)
  let exact = 0
  let withinOne = 0
  let sparseA = 0
  let sparseB = 0
  let sparseBoth = 0
  let denseA = 0
  let denseB = 0
  let denseBoth = 0
  for (let index = 0; index < a.score.length; index += 1) {
    if (!a.valid[index] || !b.valid[index]) continue
    const qa = quintileForRank(lookupA.averageRank[a.score[index]], count)
    const qb = quintileForRank(lookupB.averageRank[b.score[index]], count)
    const difference = Math.abs(qa - qb)
    if (difference === 0) exact += 1
    if (difference <= 1) withinOne += 1
    if (qa === 0) sparseA += 1
    if (qb === 0) sparseB += 1
    if (qa === 0 && qb === 0) sparseBoth += 1
    if (qa === 4) denseA += 1
    if (qb === 4) denseB += 1
    if (qa === 4 && qb === 4) denseBoth += 1
  }

  return {
    status: 'available',
    method: 'independent_relative_rank_transfer_v1',
    source_a: a.sourceId,
    source_b: b.sourceId,
    overlap_cell_count: count,
    spearman_rank_correlation: spearman,
    exact_quintile_agreement_percent: exact / count * 100,
    within_one_quintile_percent: withinOne / count * 100,
    sparse_20_dice_overlap_percent: Number(diceOverlap(sparseBoth, sparseA, sparseB)) * 100,
    dense_20_dice_overlap_percent: Number(diceOverlap(denseBoth, denseA, denseB)) * 100,
    interpretation_boundary:
      'Spatial transfer diagnostic only. Independently normalized relative observations are not subtracted and disagreement is not classified as vegetation change.',
  }
}

function encodeBase64(bytes: Uint8Array) {
  return Buffer.from(bytes).toString('base64')
}

function buildScaleSurface(args: any) {
  const {
    source,
    targetDiameterM,
    bounds,
    projectedBoundary,
    imageryDimensions,
    terrainDimensions,
    integrals,
    falseColorIntegrals,
    slopeRgba,
    hillshadeRgba,
    sun,
  } = args
  const terrainCount = terrainDimensions.width * terrainDimensions.height
  const stdValues = new Float32Array(terrainCount)
  const gradientValues = new Float32Array(terrainCount)
  const meanValues = new Float32Array(terrainCount)
  const slopeValues = new Float32Array(terrainCount)
  const illuminationValues = new Float32Array(terrainCount)
  const falseColorValues = new Float32Array(terrainCount)
  const valid = new Uint8Array(terrainCount)
  const stdForPercentiles: number[] = []
  const gradientForPercentiles: number[] = []
  const brightnessForPercentiles: number[] = []
  const falseColorForPercentiles: number[] = []
  const imageryRadius = scaleRadiusPixels(targetDiameterM, imageryDimensions.pixelM)
  const actualDiameterM =
    imageryRadius * 2 * imageryDimensions.pixelM + imageryDimensions.pixelM

  for (let row = 0; row < terrainDimensions.height; row += 1) {
    const y = bounds.north -
      ((row + 0.5) / terrainDimensions.height) * (bounds.north - bounds.south)
    for (let col = 0; col < terrainDimensions.width; col += 1) {
      const index = row * terrainDimensions.width + col
      const x = bounds.west +
        ((col + 0.5) / terrainDimensions.width) * (bounds.east - bounds.west)
      if (!pointInPolygonGeometry(x, y, projectedBoundary)) continue
      if (slopeRgba[index * 4 + 3] <= 0) continue
      if (hillshadeRgba && hillshadeRgba[index * 4 + 3] <= 0) continue

      const imageX = Math.min(
        imageryDimensions.width - 1,
        Math.max(0, Math.floor(((col + 0.5) / terrainDimensions.width) * imageryDimensions.width)),
      )
      const imageY = Math.min(
        imageryDimensions.height - 1,
        Math.max(0, Math.floor(((row + 0.5) / terrainDimensions.height) * imageryDimensions.height)),
      )
      const texture = windowTexture(
        integrals,
        imageryDimensions.width,
        imageryDimensions.height,
        imageX,
        imageY,
        imageryRadius,
      )
      const falseColor = windowFalseColorSupport(
        falseColorIntegrals,
        imageryDimensions.width,
        imageryDimensions.height,
        imageX,
        imageY,
        imageryRadius,
      )
      if (!texture || falseColor == null) continue

      const slopePercent = slopeRgba[index * 4] / 255 * 100
      const illumination = hillshadeRgba ? hillshadeRgba[index * 4] / 255 : Number.NaN
      stdValues[index] = texture.standardDeviation
      gradientValues[index] = texture.gradientMean
      meanValues[index] = texture.mean
      slopeValues[index] = slopePercent
      illuminationValues[index] = illumination
      falseColorValues[index] = falseColor
      valid[index] = 1
      stdForPercentiles.push(texture.standardDeviation)
      gradientForPercentiles.push(texture.gradientMean)
      brightnessForPercentiles.push(texture.mean)
      falseColorForPercentiles.push(falseColor)
    }
  }

  if (stdForPercentiles.length < 100) {
    throw new Error(targetDiameterM + ' m leaf-off aerial-texture coverage is insufficient for the parcel')
  }

  const stdLow = percentile(stdForPercentiles, 0.1)
  const stdHigh = percentile(stdForPercentiles, 0.9)
  const gradientLow = percentile(gradientForPercentiles, 0.1)
  const gradientHigh = percentile(gradientForPercentiles, 0.9)
  const brightnessLow = percentile(brightnessForPercentiles, 0.03)
  const brightnessHigh = percentile(brightnessForPercentiles, 0.97)
  const falseColorLow = percentile(falseColorForPercentiles, 0.55)
  const falseColorHigh = percentile(falseColorForPercentiles, 0.95)
  const adjusted = new Float32Array(terrainCount)
  const adjustedValues: number[] = []

  for (let index = 0; index < terrainCount; index += 1) {
    if (!valid[index]) continue
    const std = robustNormalize(stdValues[index], stdLow, stdHigh)
    const gradient = robustNormalize(gradientValues[index], gradientLow, gradientHigh)
    const textureSignal = 0.45 * std + 0.55 * gradient
    const slopeRatio = slopeValues[index] / 100
    const surfaceFactor = 1 / Math.sqrt(1 + slopeRatio * slopeRatio)
    adjusted[index] = textureSignal * surfaceFactor
    adjustedValues.push(adjusted[index])
  }

  const adjustedLow = percentile(adjustedValues, 0.05)
  const adjustedHigh = percentile(adjustedValues, 0.95)
  const score = new Uint8Array(terrainCount)
  const confidence = new Uint8Array(terrainCount)
  const spectralSupport = new Uint8Array(terrainCount)
  const slopePercent = new Uint8Array(terrainCount)
  const illumination = new Uint8Array(terrainCount)
  let highConfidence = 0
  let validCount = 0
  let rescuedCount = 0

  for (let index = 0; index < terrainCount; index += 1) {
    if (!valid[index]) continue
    const normalized = robustNormalize(adjusted[index], adjustedLow, adjustedHigh)
    const illuminationValue = illuminationValues[index]
    const mean = meanValues[index]
    const support = robustNormalize(falseColorValues[index], falseColorLow, falseColorHigh)
    let confidenceValue: number
    let preRescueConfidence: number

    if (source.solarMode === 'documented' && Number.isFinite(illuminationValue)) {
      const illuminationConfidence = clamp((illuminationValue - 0.12) / 0.5)
      confidenceValue = 0.25 + 0.75 * illuminationConfidence
      if (Number.isFinite(brightnessLow) && mean < Number(brightnessLow)) confidenceValue *= 0.7
      if (Number.isFinite(brightnessHigh) && mean > Number(brightnessHigh)) confidenceValue *= 0.8
      const shadowPressure = 1 - illuminationConfidence
      const rescueStrength = shadowPressure * support * 0.85
      preRescueConfidence = confidenceValue
      if (rescueStrength > 0 && confidenceValue < 0.72) {
        confidenceValue += (0.72 - confidenceValue) * rescueStrength
      }
    } else {
      confidenceValue = 0.65
      if (Number.isFinite(brightnessLow) && mean < Number(brightnessLow)) confidenceValue *= 0.7
      if (Number.isFinite(brightnessHigh) && mean > Number(brightnessHigh)) confidenceValue *= 0.8
      preRescueConfidence = confidenceValue
    }

    score[index] = Math.round(normalized * 255)
    confidence[index] = Math.round(clamp(confidenceValue) * 255)
    spectralSupport[index] = Math.round(support * 255)
    slopePercent[index] = Math.round(clamp(slopeValues[index] / 100) * 100)
    illumination[index] = Number.isFinite(illuminationValue)
      ? Math.round(clamp(illuminationValue) * 255)
      : 0
    validCount += 1
    if (confidenceValue - preRescueConfidence >= 0.05) rescuedCount += 1
    if (confidenceValue >= 0.65) highConfidence += 1
  }

  return {
    sourceId: source.id,
    sourceYear: source.year,
    sourceLabel: source.label,
    sourceTile: source.sourceTile,
    acquisitionDate: source.acquisitionDate,
    acquisitionTimestamp: source.acquisitionTimestamp,
    acquisitionNote: source.acquisitionNote,
    solarMode: source.solarMode,
    frameTimeBasis: source.frameTimeBasis,
    solar: sun,
    bounds,
    width: terrainDimensions.width,
    height: terrainDimensions.height,
    targetNeighborhoodM: targetDiameterM,
    neighborhoodDiameterM: actualDiameterM,
    score,
    confidence,
    spectralSupport,
    valid,
    slopePercent,
    illumination,
    highConfidencePercent: validCount ? highConfidence / validCount * 100 : 0,
    nirRescuePercent: validCount ? rescuedCount / validCount * 100 : 0,
    scoreDistribution: summarizeScoreDistribution(score, valid),
    normalization: {
      texture_standard_deviation_p10: stdLow,
      texture_standard_deviation_p90: stdHigh,
      gradient_p10: gradientLow,
      gradient_p90: gradientHigh,
      brightness_p03: brightnessLow,
      brightness_p97: brightnessHigh,
      false_color_support_p55: falseColorLow,
      false_color_support_p95: falseColorHigh,
      terrain_adjusted_p05: adjustedLow,
      terrain_adjusted_p95: adjustedHigh,
      texture_weights: { standard_deviation: 0.45, gradient: 0.55 },
      terrain_surface_factor: '1/sqrt(1+(slope_percent/100)^2)',
    },
    sourcePixelM: imageryDimensions.pixelM,
    terrainPixelM: terrainDimensions.pixelM,
  }
}

export async function buildLeafOffSourceProduct(
  source: any,
  boundary: any,
  projectedBoundary: any,
  bounds: any,
  center: { lat: number; lon: number },
) {
  const sun = source.acquisitionTimestamp
    ? solarPosition(source.acquisitionTimestamp, center.lat, center.lon)
    : null
  if (sun && !(sun.altitude > 0)) throw new Error('Source-frame solar geometry is invalid')

  const imageryDimensions = rasterDimensions(
    bounds,
    FARM_WATCH_LEAF_OFF_PRODUCT.imageryTargetPixelMeters,
    FARM_WATCH_LEAF_OFF_PRODUCT.maxImageryDimension,
  )
  const terrainDimensions = rasterDimensions(
    bounds,
    FARM_WATCH_LEAF_OFF_PRODUCT.terrainTargetPixelMeters,
    FARM_WATCH_LEAF_OFF_PRODUCT.maxTerrainDimension,
  )

  const hillshadePromise = sun
    ? fetchRaster(FARM_WATCH_LEAF_OFF_PRODUCT.demUrl, bounds, terrainDimensions, hillshadeRule(sun))
    : Promise.resolve(null)

  const [imagery, infrared, slope, hillshade] = await Promise.all([
    fetchRaster(source.imageryUrl, bounds, imageryDimensions),
    fetchRaster(source.infraredUrl, bounds, imageryDimensions),
    fetchRaster(FARM_WATCH_LEAF_OFF_PRODUCT.demUrl, bounds, terrainDimensions, slopeEncodingRule()),
    hillshadePromise,
  ])

  const integrals = buildTextureIntegrals(
    imagery.rgba,
    imageryDimensions.width,
    imageryDimensions.height,
  )
  const falseColorIntegrals = buildFalseColorIntegrals(
    infrared.rgba,
    imageryDimensions.width,
    imageryDimensions.height,
  )
  const product = buildScaleSurface({
    source,
    targetDiameterM: FARM_WATCH_LEAF_OFF_PRODUCT.targetNeighborhoodMeters,
    bounds,
    projectedBoundary,
    imageryDimensions,
    terrainDimensions,
    integrals,
    falseColorIntegrals,
    slopeRgba: slope.rgba,
    hillshadeRgba: hillshade?.rgba || null,
    sun,
  })

  const compact = {
    sourceId: product.sourceId,
    sourceYear: product.sourceYear,
    sourceLabel: product.sourceLabel,
    sourceTile: product.sourceTile,
    acquisitionDate: product.acquisitionDate,
    acquisitionTimestamp: product.acquisitionTimestamp,
    acquisitionNote: product.acquisitionNote,
    solarMode: product.solarMode,
    frameTimeBasis: product.frameTimeBasis,
    solar: product.solar,
    bounds: product.bounds,
    neighborhoodDiameterM: product.neighborhoodDiameterM,
    highConfidencePercent: product.highConfidencePercent,
    nirRescuePercent: product.nirRescuePercent,
    scoreDistribution: product.scoreDistribution,
    normalization: product.normalization,
    grid: {
      width: product.width,
      height: product.height,
      source_pixel_m: product.sourcePixelM,
      terrain_pixel_m: product.terrainPixelM,
      target_neighborhood_m: product.targetNeighborhoodM,
      encoding: 'base64-u8-v1',
      score_base64: encodeBase64(product.score),
      confidence_base64: encodeBase64(product.confidence),
      spectral_support_base64: encodeBase64(product.spectralSupport),
      valid_base64: encodeBase64(product.valid),
      slope_percent_base64: encodeBase64(product.slopePercent),
      illumination_base64: encodeBase64(product.illumination),
    },
  }

  const fingerprint = {
    source_id: source.id,
    source_tile: source.sourceTile,
    acquisition_date: source.acquisitionDate,
    imagery: {
      service: source.imageryUrl,
      export_request: imagery.request_url,
      bytes: imagery.byte_length,
      sha256: imagery.sha256,
    },
    infrared: {
      service: source.infraredUrl,
      export_request: infrared.request_url,
      bytes: infrared.byte_length,
      sha256: infrared.sha256,
    },
    slope: {
      service: FARM_WATCH_LEAF_OFF_PRODUCT.demUrl,
      export_request: slope.request_url,
      bytes: slope.byte_length,
      sha256: slope.sha256,
    },
    hillshade: hillshade ? {
      service: FARM_WATCH_LEAF_OFF_PRODUCT.demUrl,
      export_request: hillshade.request_url,
      bytes: hillshade.byte_length,
      sha256: hillshade.sha256,
    } : null,
  }

  return { product, compact, fingerprint }
}

async function freshOidcToken() {
  const requestUrl = Deno.env.get('ACTIONS_ID_TOKEN_REQUEST_URL') || ''
  const requestToken = Deno.env.get('ACTIONS_ID_TOKEN_REQUEST_TOKEN') || ''
  if (!requestUrl || !requestToken) throw new Error('GitHub Actions OIDC environment unavailable')
  const url = new URL(requestUrl)
  url.searchParams.set('audience', FARM_WATCH_GITHUB_OIDC_AUDIENCE)
  const response = await fetch(url, {
    headers: { authorization: 'Bearer ' + requestToken, accept: 'application/json' },
  })
  if (!response.ok) throw new Error('GitHub OIDC token request failed: ' + response.status)
  const payload = await response.json()
  if (!payload?.value) throw new Error('GitHub OIDC token response was empty')
  return String(payload.value)
}

async function workerRequest(body: any) {
  const token = await freshOidcToken()
  const response = await fetch(EDGE_URL, {
    method: 'POST',
    headers: {
      authorization: 'Bearer ' + token,
      'content-type': 'application/json',
      accept: 'application/json',
    },
    body: JSON.stringify({
      property: propertySlug,
      product: FARM_WATCH_LEAF_OFF_PRODUCT.key,
      ...body,
    }),
  })
  const payload = await response.json().catch(() => ({}))
  if (!response.ok) {
    throw new Error(payload?.detail || payload?.error || ('worker API returned ' + response.status))
  }
  return payload
}

async function main() {
  const claim = await workerRequest({ operation: 'claim' })
  if (claim?.action === 'reuse') {
    console.log(JSON.stringify({ status: 'reused', build: claim.build || null }, null, 2))
    return
  }
  if (claim?.action !== 'build') {
    console.log(JSON.stringify({
      status: claim?.action || 'not_claimed',
      build: claim.build || null,
    }, null, 2))
    return
  }

  const buildId = String(claim.build_id)
  const leaseToken = String(claim.lease_token)
  try {
    const boundary = claim.boundary_geojson
    const projectedBoundary = projectBoundaryGeometry(boundary)
    const bounds = projectedBounds(boundary)
    if (!boundary || !projectedBoundary || !bounds) throw new Error('property boundary unavailable')

    const coordinates = flattenCoordinates(boundary?.coordinates)
    if (!coordinates.length) throw new Error('property coordinate set unavailable')
    const fallbackLon =
      coordinates.reduce((sum, point) => sum + Number(point[0]), 0) / coordinates.length
    const fallbackLat =
      coordinates.reduce((sum, point) => sum + Number(point[1]), 0) / coordinates.length
    const center = {
      lon: Number.isFinite(Number(claim?.center?.lon)) ? Number(claim.center.lon) : fallbackLon,
      lat: Number.isFinite(Number(claim?.center?.lat)) ? Number(claim.center.lat) : fallbackLat,
    }

    const built = []
    for (const source of FARM_WATCH_LEAF_OFF_PRODUCT.sources) {
      console.log('Building leaf-off source', source.id)
      built.push(await buildLeafOffSourceProduct(source, boundary, projectedBoundary, bounds, center))
    }

    const transfer = compareIndependentStructureProducts(built[1].product, built[0].product)
    const processingFingerprint = {
      property_boundary_sha256: claim.boundary_sha256,
      algorithm_version: FARM_WATCH_LEAF_OFF_PRODUCT.algorithmVersion,
      output_schema_version: FARM_WATCH_LEAF_OFF_PRODUCT.outputSchemaVersion,
      sources: built.map((row) => row.fingerprint),
    }

    const artifact = {
      schema: FARM_WATCH_LEAF_OFF_PRODUCT.outputSchemaVersion,
      method: FARM_WATCH_LEAF_OFF_PRODUCT.algorithmVersion,
      interpretationClass: 'experimental_horizontal_woody_spatial_context',
      interpretationBoundary:
        'Use as complementary horizontal woody-pattern context alongside LiDAR vertical structure. Blinded LiDAR-matched QA supports recurring coarse/articulated morphology differences but not a single density or continuity class. Do not infer understory density, stem density, regeneration, species, habitat quality, management condition, or absolute cross-year density without field verification.',
      supportedUses: [
        'scouting_triage',
        'woody_edge_and_opening_context',
        'horizontal_spatial_organization_comparison',
        'candidate_field_verification_targeting',
      ],
      fieldVerificationRequiredFor: [
        'understory_density',
        'stem_density',
        'regeneration',
        'species',
        'habitat_quality',
        'management_condition',
      ],
      products: built.map((row) => row.compact),
      transfer_diagnostic: transfer,
      processing_source_fingerprint: processingFingerprint,
    }

    const completion = await workerRequest({
      operation: 'complete',
      build_id: buildId,
      lease_token: leaseToken,
      artifact,
    })
    console.log(JSON.stringify({
      status: 'available',
      property: propertySlug,
      products: artifact.products.map((product: any) => ({
        source_id: product.sourceId,
        width: product.grid.width,
        height: product.grid.height,
        high_confidence_percent: product.highConfidencePercent,
      })),
      transfer_diagnostic: artifact.transfer_diagnostic,
      completion,
    }, null, 2))
  } catch (error) {
    try {
      await workerRequest({
        operation: 'fail',
        build_id: buildId,
        lease_token: leaseToken,
        error: error instanceof Error ? error.stack || error.message : String(error),
      })
    } catch (failError) {
      console.error('Failed to report leaf-off worker failure:', failError)
    }
    throw error
  }
}

if (import.meta.main) await main()
