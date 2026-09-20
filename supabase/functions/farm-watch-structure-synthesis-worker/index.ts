import 'jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.115.0'
import proj4 from 'npm:proj4@2.15.0'
import {
  FARM_WATCH_LIDAR_SOURCE_PRODUCT,
  FARM_WATCH_LIDAR_SOURCE_SIGNATURE,
} from '../_shared/farm-watch-lidar-source.ts'
import {
  FARM_WATCH_LIDAR_PHYSICAL_PRODUCT,
  lidarPhysicalSourceSignature,
  validateLidarPhysicalArtifact,
} from '../_shared/farm-watch-lidar-physical-contract.ts'
import {
  FARM_WATCH_LEAF_OFF_PRODUCT,
  FARM_WATCH_LEAF_OFF_SOURCE_SIGNATURE,
  validateLeafOffArtifact,
} from '../_shared/farm-watch-leaf-off-contract.ts'
import {
  FARM_WATCH_STRUCTURE_SYNTHESIS_LIMITATIONS,
  FARM_WATCH_STRUCTURE_SYNTHESIS_PRODUCT,
  structureSynthesisArtifactPath,
  structureSynthesisSourceSignature,
  validateStructureSynthesisArtifact,
} from '../_shared/farm-watch-structure-synthesis-contract.ts'
import {
  FARM_WATCH_GITHUB_OIDC_AUDIENCE,
  verifyFarmWatchGitHubActionsOidc,
} from '../_shared/github-actions-oidc.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
let SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
try {
  const keys = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') || '{}')
  SERVICE_KEY = keys.default || SERVICE_KEY
} catch { /* legacy fallback */ }
if (!SERVICE_KEY) throw new Error('Farm Watch service credential is unavailable')

const admin = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
})

const COMMON_CRS = 'EPSG:6473'
const COMMON_CRS_DEF =
  '+proj=lcc +lat_0=36.3333333333333 +lon_0=-85.75 +lat_1=37.0833333333333 +lat_2=38.6666666667 +x_0=1500000 +y_0=999999.9998984 +ellps=GRS80 +units=us-ft +no_defs +type=crs'
proj4.defs(COMMON_CRS, COMMON_CRS_DEF)

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store, max-age=0',
      pragma: 'no-cache',
      'referrer-policy': 'no-referrer',
      'x-content-type-options': 'nosniff',
    },
  })
}

function bearer(req: Request) {
  const match = /^Bearer\s+(.+)$/i.exec(req.headers.get('authorization') || '')
  return match?.[1]?.trim() || null
}

function boundedSlug(value: unknown) {
  const normalized = String(value || '').trim().toLowerCase()
  return /^[a-z0-9][a-z0-9-]{0,79}$/.test(normalized) ? normalized : null
}

function clamp(value: number, min = 0, max = 1) {
  return Math.max(min, Math.min(max, value))
}

async function sha256Hex(value: Uint8Array | string) {
  const bytes = typeof value === 'string' ? new TextEncoder().encode(value) : value
  const stable = Uint8Array.from(bytes)
  const digest = await crypto.subtle.digest('SHA-256', stable.buffer)
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, '0')).join('')
}

function validSha(value: unknown) {
  const text = String(value || '').trim().toLowerCase()
  return /^[0-9a-f]{64}$/.test(text) ? text : null
}

async function readState(
  slug: string,
  productKind: string,
  algorithmVersion: string,
  outputSchemaVersion: string,
  sourceSignature: string,
) {
  const { data, error } = await admin.rpc('farm_watch_get_materialization_v1_internal', {
    p_slug: slug,
    p_product_kind: productKind,
    p_algorithm_version: algorithmVersion,
    p_output_schema_version: outputSchemaVersion,
    p_source_signature: sourceSignature,
  })
  if (error) throw new Error('materialization state read failed: ' + error.message)
  return data
}

async function downloadArtifact(state: any) {
  const materialization = state?.materialization
  const bucket = String(materialization?.artifact_bucket || '')
  const path = String(materialization?.artifact_path || '')
  const expectedSha = validSha(materialization?.artifact_sha256)
  if (!bucket || !path || !expectedSha) throw new Error('materialization artifact reference is incomplete')

  const { data, error } = await admin.storage.from(bucket).download(path)
  if (error || !data) throw new Error('materialization artifact download failed: ' + (error?.message || 'missing'))
  const bytes = new Uint8Array(await data.arrayBuffer())
  const actualSha = await sha256Hex(bytes)
  if (actualSha !== expectedSha) throw new Error('materialization artifact checksum mismatch')
  const artifact = JSON.parse(new TextDecoder().decode(bytes))
  return { artifact, artifact_sha256: actualSha, bytes: bytes.byteLength }
}

async function resolveDependencies(slug: string) {
  const sourceState = await readState(
    slug,
    FARM_WATCH_LIDAR_SOURCE_PRODUCT.productKind,
    FARM_WATCH_LIDAR_SOURCE_PRODUCT.algorithmVersion,
    FARM_WATCH_LIDAR_SOURCE_PRODUCT.outputSchemaVersion,
    FARM_WATCH_LIDAR_SOURCE_SIGNATURE,
  )
  if (sourceState?.status !== 'available') throw new Error('current LiDAR source plan is unavailable')
  const sourcePayload = await downloadArtifact(sourceState)

  const physicalSourceSignature = lidarPhysicalSourceSignature(
    sourcePayload.artifact,
    sourcePayload.artifact_sha256,
  )
  const physicalState = await readState(
    slug,
    FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.productKind,
    FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.algorithmVersion,
    FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.outputSchemaVersion,
    physicalSourceSignature,
  )
  if (physicalState?.status !== 'available') throw new Error('current LiDAR physical structure is unavailable')

  const leafState = await readState(
    slug,
    FARM_WATCH_LEAF_OFF_PRODUCT.productKind,
    FARM_WATCH_LEAF_OFF_PRODUCT.algorithmVersion,
    FARM_WATCH_LEAF_OFF_PRODUCT.outputSchemaVersion,
    FARM_WATCH_LEAF_OFF_SOURCE_SIGNATURE,
  )
  if (leafState?.status !== 'available') throw new Error('current leaf-off structure is unavailable')

  const physicalSha = validSha(physicalState?.materialization?.artifact_sha256)
  const leafSha = validSha(leafState?.materialization?.artifact_sha256)
  if (!physicalSha || !leafSha) throw new Error('structure synthesis dependency checksum is unavailable')

  return {
    physicalState,
    leafState,
    sourceSignature: structureSynthesisSourceSignature(physicalSha, leafSha),
  }
}

function decodeBase64(value: unknown) {
  const binary = atob(String(value || ''))
  return Uint8Array.from(binary, (char) => char.charCodeAt(0))
}

function encodeBase64(value: Uint8Array) {
  let binary = ''
  const chunk = 0x8000
  for (let index = 0; index < value.length; index += chunk) {
    binary += String.fromCharCode(...value.subarray(index, Math.min(value.length, index + chunk)))
  }
  return btoa(binary)
}

function sortedQuantile(values: number[], q: number) {
  if (!values.length) return null
  const sorted = values.slice().sort((a, b) => a - b)
  const position = clamp(q) * (sorted.length - 1)
  const lower = Math.floor(position)
  const upper = Math.ceil(position)
  if (lower === upper) return sorted[lower]
  const weight = position - lower
  return sorted[lower] * (1 - weight) + sorted[upper] * weight
}

function summarizeScalar(values: number[]) {
  const clean = values.filter(Number.isFinite)
  if (!clean.length) return {
    count: 0,
    mean: null,
    p10: null,
    p25: null,
    median: null,
    p75: null,
    p90: null,
  }
  const mean = clean.reduce((sum, value) => sum + value, 0) / clean.length
  return {
    count: clean.length,
    mean,
    p10: sortedQuantile(clean, 0.10),
    p25: sortedQuantile(clean, 0.25),
    median: sortedQuantile(clean, 0.50),
    p75: sortedQuantile(clean, 0.75),
    p90: sortedQuantile(clean, 0.90),
  }
}

function averageRanks(values: number[]) {
  const ordered = values
    .map((value, index) => ({ value, index }))
    .sort((a, b) => a.value - b.value)
  const ranks = new Float64Array(values.length)
  let cursor = 0
  while (cursor < ordered.length) {
    let end = cursor + 1
    while (end < ordered.length && ordered[end].value === ordered[cursor].value) end += 1
    const rank = (cursor + 1 + end) / 2
    for (let i = cursor; i < end; i += 1) ranks[ordered[i].index] = rank
    cursor = end
  }
  return ranks
}

function pearson(a: ArrayLike<number>, b: ArrayLike<number>) {
  if (a.length !== b.length || a.length < 3) return null
  let sumA = 0
  let sumB = 0
  let sumA2 = 0
  let sumB2 = 0
  let sumAB = 0
  for (let i = 0; i < a.length; i += 1) {
    const x = Number(a[i])
    const y = Number(b[i])
    sumA += x
    sumB += y
    sumA2 += x * x
    sumB2 += y * y
    sumAB += x * y
  }
  const n = a.length
  const numerator = n * sumAB - sumA * sumB
  const denominator = Math.sqrt(
    Math.max(0, n * sumA2 - sumA * sumA) *
    Math.max(0, n * sumB2 - sumB * sumB),
  )
  return denominator > 0 ? numerator / denominator : null
}

function spearman(a: number[], b: number[]) {
  if (a.length !== b.length || a.length < 3) return null
  return pearson(averageRanks(a), averageRanks(b))
}

function normalizedBandEntropy(shares: number[]) {
  if (!Array.isArray(shares) || !shares.length) return null
  let entropy = 0
  let positive = 0
  for (const share of shares) {
    const value = Number(share)
    if (!(value > 0)) continue
    entropy -= value * Math.log(value)
    positive += 1
  }
  if (positive < 2) return 0
  return entropy / Math.log(shares.length)
}

function bandProfileSpread(shares: number[]) {
  if (!Array.isArray(shares) || !shares.length) return null
  let mean = 0
  let total = 0
  for (let band = 0; band < shares.length; band += 1) {
    const share = Number(shares[band])
    if (!Number.isFinite(share) || share < 0) continue
    mean += band * share
    total += share
  }
  if (!(total > 0)) return null
  mean /= total
  let variance = 0
  for (let band = 0; band < shares.length; band += 1) {
    const share = Number(shares[band])
    if (!Number.isFinite(share) || share < 0) continue
    variance += share * (band - mean) ** 2
  }
  return Math.sqrt(variance / total)
}

function dominantShare(shares: number[]) {
  let best = 0
  for (const share of shares || []) {
    const value = Number(share)
    if (Number.isFinite(value) && value > best) best = value
  }
  return best
}

function solveLinearSystem(matrix: number[][], vector: number[]) {
  const n = vector.length
  const a = matrix.map((row, index) => row.slice().concat(vector[index]))
  for (let col = 0; col < n; col += 1) {
    let pivot = col
    for (let row = col + 1; row < n; row += 1) {
      if (Math.abs(a[row][col]) > Math.abs(a[pivot][col])) pivot = row
    }
    if (Math.abs(a[pivot][col]) < 1e-10) return null
    if (pivot !== col) [a[pivot], a[col]] = [a[col], a[pivot]]
    const divisor = a[col][col]
    for (let j = col; j <= n; j += 1) a[col][j] /= divisor
    for (let row = 0; row < n; row += 1) {
      if (row === col) continue
      const factor = a[row][col]
      if (!factor) continue
      for (let j = col; j <= n; j += 1) a[row][j] -= factor * a[col][j]
    }
  }
  return a.map((row) => row[n])
}

function fitStandardizedRidge(rows: any[], featureNames: string[], ridge = 1e-6) {
  if (rows.length < featureNames.length + 3) return null
  const means = new Array(featureNames.length).fill(0)
  const stds = new Array(featureNames.length).fill(0)

  for (const row of rows) {
    for (let j = 0; j < featureNames.length; j += 1) means[j] += row.features[featureNames[j]]
  }
  for (let j = 0; j < featureNames.length; j += 1) means[j] /= rows.length

  for (const row of rows) {
    for (let j = 0; j < featureNames.length; j += 1) {
      const delta = row.features[featureNames[j]] - means[j]
      stds[j] += delta * delta
    }
  }
  for (let j = 0; j < featureNames.length; j += 1) {
    stds[j] = Math.sqrt(stds[j] / Math.max(1, rows.length - 1))
    if (!(stds[j] > 1e-8)) stds[j] = 1
  }

  const p = featureNames.length + 1
  const xtx = Array.from({ length: p }, () => new Array(p).fill(0))
  const xty = new Array(p).fill(0)
  for (const row of rows) {
    const x = [1]
    for (let j = 0; j < featureNames.length; j += 1) {
      x.push((row.features[featureNames[j]] - means[j]) / stds[j])
    }
    for (let i = 0; i < p; i += 1) {
      xty[i] += x[i] * row.y
      for (let j = 0; j < p; j += 1) xtx[i][j] += x[i] * x[j]
    }
  }
  for (let i = 1; i < p; i += 1) xtx[i][i] += ridge

  const coefficients = solveLinearSystem(xtx, xty)
  return coefficients ? { coefficients, means, stds, featureNames } : null
}

function predictStandardized(model: any, features: Record<string, number>) {
  if (!model) return null
  let value = model.coefficients[0]
  for (let j = 0; j < model.featureNames.length; j += 1) {
    const name = model.featureNames[j]
    value += model.coefficients[j + 1] *
      ((features[name] - model.means[j]) / model.stds[j])
  }
  return value
}

function spatialFold(index: number, width: number, foldCount = 5) {
  const col = index % width
  return Math.min(foldCount - 1, Math.floor(col * foldCount / Math.max(1, width)))
}

function crossValidatedProfileModel(records: any[], gridWidth: number) {
  const featureNames = [
    'share_4_16',
    'share_16_32',
    'share_32_64',
    'share_64_plus',
    'entropy',
    'profile_spread',
  ]
  const rows = records.map((row) => ({
    index: row.index,
    y: row.leafScore,
    features: {
      share_4_16: row.shares[1] || 0,
      share_16_32: row.shares[2] || 0,
      share_32_64: row.shares[3] || 0,
      share_64_plus: row.shares[4] || 0,
      entropy: normalizedBandEntropy(row.shares) || 0,
      profile_spread: bandProfileSpread(row.shares) || 0,
    },
  })).filter((row) =>
    Number.isFinite(row.y) &&
    featureNames.every((name) => Number.isFinite(row.features[name]))
  )

  if (rows.length < 100) {
    return { status: 'insufficient_overlap', cell_count: rows.length, prediction_records: [] }
  }

  const observed: number[] = []
  const predicted: number[] = []
  const predictionRecords: any[] = []
  const folds = []
  const foldCount = 5
  for (let fold = 0; fold < foldCount; fold += 1) {
    const training = rows.filter((row) => spatialFold(row.index, gridWidth, foldCount) !== fold)
    const testing = rows.filter((row) => spatialFold(row.index, gridWidth, foldCount) === fold)
    if (training.length < 50 || testing.length < 10) continue
    const model = fitStandardizedRidge(training, featureNames)
    if (!model) continue
    for (const row of testing) {
      const estimate = predictStandardized(model, row.features)
      if (!Number.isFinite(estimate)) continue
      observed.push(row.y)
      predicted.push(Number(estimate))
      predictionRecords.push({
        index: row.index,
        observed: row.y,
        predicted: Number(estimate),
        residual: row.y - Number(estimate),
      })
    }
    folds.push({ fold, training_cells: training.length, testing_cells: testing.length })
  }

  if (observed.length < 50) {
    return {
      status: 'insufficient_cross_validation',
      cell_count: rows.length,
      predicted_cell_count: observed.length,
      prediction_records: predictionRecords,
    }
  }

  const meanObserved = observed.reduce((sum, value) => sum + value, 0) / observed.length
  let sse = 0
  let sst = 0
  for (let index = 0; index < observed.length; index += 1) {
    sse += (observed[index] - predicted[index]) ** 2
    sst += (observed[index] - meanObserved) ** 2
  }

  return {
    status: 'available',
    method: 'blocked_5fold_vertical_profile_ridge_v1',
    cell_count: rows.length,
    predicted_cell_count: observed.length,
    fold_count: folds.length,
    folds,
    features: featureNames,
    cross_validated_r2: sst > 0 ? 1 - sse / sst : null,
    predicted_vs_observed_r: pearson(predicted, observed),
    predictor_spearman_rho: {
      share_0_4: spearman(records.map((row) => row.leafScore), records.map((row) => row.shares[0] || 0)),
      share_4_16: spearman(records.map((row) => row.leafScore), records.map((row) => row.shares[1] || 0)),
      share_16_32: spearman(records.map((row) => row.leafScore), records.map((row) => row.shares[2] || 0)),
      share_32_64: spearman(records.map((row) => row.leafScore), records.map((row) => row.shares[3] || 0)),
      share_64_plus: spearman(records.map((row) => row.leafScore), records.map((row) => row.shares[4] || 0)),
      entropy: spearman(records.map((row) => row.leafScore), records.map((row) => normalizedBandEntropy(row.shares) || 0)),
      profile_spread: spearman(records.map((row) => row.leafScore), records.map((row) => bandProfileSpread(row.shares) || 0)),
      dominant_share: spearman(records.map((row) => row.leafScore), records.map((row) => dominantShare(row.shares) || 0)),
    },
    prediction_records: predictionRecords,
    interpretation_boundary:
      'Exploratory current-state explanatory model only. Five east-west spatial blocks are held out in turn. The model uses the full neutral LiDAR height-band composition plus vertical entropy and profile spread to estimate the frozen 2024 leaf-off score; it does not retune either source or imply that unexplained leaf-off variation is vegetation.',
  }
}

function standardDeviation(values: number[]) {
  const clean = values.filter(Number.isFinite)
  if (clean.length < 2) return null
  const mean = clean.reduce((sum, value) => sum + value, 0) / clean.length
  let ss = 0
  for (const value of clean) ss += (value - mean) ** 2
  return Math.sqrt(ss / (clean.length - 1))
}

function residualSpatialSummary(
  records: any[],
  predictionRecords: any[],
  gridWidth: number,
  gridHeight: number,
  cellMeters: number,
) {
  const byIndex = new Map(predictionRecords.map((row) => [row.index, row]))
  const joined = records.map((row) => {
    const prediction = byIndex.get(row.index)
    if (!prediction) return null
    return {
      index: row.index,
      residual: prediction.residual,
      confidence: row.leafConfidence,
      spectral_support: row.leafSpectralSupport,
    }
  }).filter(Boolean) as any[]

  const allStd = standardDeviation(joined.map((row) => row.residual))
  if (!(Number(allStd) > 0)) return { status: 'unavailable', cell_count: joined.length }

  const confidenceMinimum = 0.65
  const spectralMinimum = 0.50
  const eligible = joined.filter((row) =>
    Number.isFinite(row.residual) &&
    Number.isFinite(row.confidence) &&
    Number.isFinite(row.spectral_support) &&
    row.confidence >= confidenceMinimum &&
    row.spectral_support >= spectralMinimum
  )
  const p80 = sortedQuantile(
    eligible.map((row) => row.residual).sort((a, b) => a - b),
    0.80,
  )
  const threshold = Number.isFinite(p80) ? Math.max(0, Number(p80)) : null
  if (!Number.isFinite(threshold)) {
    return { status: 'insufficient_overlap', cell_count: joined.length, eligible_cell_count: eligible.length }
  }

  const selected = new Map(
    eligible
      .filter((row) => row.residual >= Number(threshold))
      .map((row) => [row.index, row]),
  )
  const visited = new Set<number>()
  const patches: any[] = []
  for (const [seed] of selected) {
    if (visited.has(seed)) continue
    const queue = [seed]
    visited.add(seed)
    const cells: any[] = []
    while (queue.length) {
      const index = Number(queue.pop())
      const row = selected.get(index)
      if (!row) continue
      cells.push(row)
      const gridRow = Math.floor(index / gridWidth)
      const col = index % gridWidth
      for (let dy = -1; dy <= 1; dy += 1) {
        for (let dx = -1; dx <= 1; dx += 1) {
          if (!dx && !dy) continue
          const rr = gridRow + dy
          const cc = col + dx
          if (rr < 0 || cc < 0 || rr >= gridHeight || cc >= gridWidth) continue
          const neighbor = rr * gridWidth + cc
          if (!selected.has(neighbor) || visited.has(neighbor)) continue
          visited.add(neighbor)
          queue.push(neighbor)
        }
      }
    }
    const residuals = cells.map((row) => row.residual)
    patches.push({
      cell_count: cells.length,
      area_square_meters: cells.length * cellMeters * cellMeters,
      mean_residual: residuals.reduce((sum, value) => sum + value, 0) / residuals.length,
      max_residual: Math.max(...residuals),
    })
  }

  patches.sort((a, b) =>
    b.cell_count - a.cell_count ||
    b.mean_residual - a.mean_residual ||
    b.max_residual - a.max_residual
  )
  const multiCell = patches.filter((patch) => patch.cell_count >= 2)
  const multiCellSelected = multiCell.reduce((sum, patch) => sum + patch.cell_count, 0)

  return {
    status: 'available',
    method: 'leaf_off_profile_residual_spatial_v1',
    cell_count: joined.length,
    residual_stddev: allStd,
    confidence_minimum: confidenceMinimum,
    spectral_support_minimum: spectralMinimum,
    positive_threshold_quantile: 0.80,
    positive_residual_threshold: threshold,
    eligible_cell_count: eligible.length,
    selected_cell_count: selected.size,
    contiguous_patch_count: patches.length,
    multi_cell_patch_count: multiCell.length,
    selected_cells_in_multi_cell_patches: multiCellSelected,
    selected_multi_cell_fraction: selected.size ? multiCellSelected / selected.size : null,
    largest_patch: patches.length ? patches[0] : null,
    representative_patches: patches.slice(0, 6),
    interpretation_boundary:
      'Out-of-fold residual grouping only. High-positive cells are the gated upper 20% of residuals, clamped at zero and grouped by eight-neighbor connectivity. Multi-cell patches indicate descriptive spatial organization on this grid; this is not a spatial significance test, independent replication, vegetation class, habitat class, or causal attribution.',
  }
}

function bandLabels(thresholds: number[]) {
  const labels: string[] = []
  let lower = 0
  for (const upper of thresholds) {
    labels.push(lower + '–' + upper + 'ft')
    lower = upper
  }
  labels.push(lower + '+ft')
  return labels
}

function bandShares(grid: any, index: number) {
  const total = Number(grid.total[index])
  if (!(total > 0)) return null
  const shares = new Array(Number(grid.bandCount))
  for (let band = 0; band < Number(grid.bandCount); band += 1) {
    shares[band] = Number(grid.counts[index * Number(grid.bandCount) + band]) / total
  }
  return shares
}

function dominantBand(grid: any, index: number) {
  let bestBand = 0
  let bestCount = -1
  for (let band = 0; band < Number(grid.bandCount); band += 1) {
    const count = Number(grid.counts[index * Number(grid.bandCount) + band])
    if (count > bestCount) {
      bestBand = band
      bestCount = count
    }
  }
  return bestBand
}

function variancePartition(records: any[]) {
  const values = records.map((row) => row.leafScore)
  if (!values.length) return {
    cell_count: 0,
    explained_by_dominant_band_fraction: null,
    remaining_within_band_fraction: null,
  }

  const overallMean = values.reduce((sum, value) => sum + value, 0) / values.length
  let totalSs = 0
  for (const value of values) totalSs += (value - overallMean) ** 2
  if (!(totalSs > 0)) return {
    cell_count: values.length,
    explained_by_dominant_band_fraction: null,
    remaining_within_band_fraction: null,
  }

  const groups = new Map<number, number[]>()
  for (const row of records) {
    if (!groups.has(row.dominantBand)) groups.set(row.dominantBand, [])
    groups.get(row.dominantBand)!.push(row.leafScore)
  }

  let betweenSs = 0
  for (const group of groups.values()) {
    const mean = group.reduce((sum, value) => sum + value, 0) / group.length
    betweenSs += group.length * (mean - overallMean) ** 2
  }
  const explained = clamp(betweenSs / totalSs)
  return {
    cell_count: values.length,
    group_count: groups.size,
    explained_by_dominant_band_fraction: explained,
    remaining_within_band_fraction: 1 - explained,
  }
}

function lowerStrataQuartiles(records: any[]) {
  if (!records.length) return []
  const ordered = records.slice().sort((a, b) => a.lowerShare - b.lowerShare)
  const output = []
  for (let quartile = 0; quartile < 4; quartile += 1) {
    const start = Math.floor(quartile * ordered.length / 4)
    const end = Math.floor((quartile + 1) * ordered.length / 4)
    const subset = ordered.slice(start, Math.max(start + 1, end))
    if (!subset.length) continue
    output.push({
      quartile: quartile + 1,
      cell_count: subset.length,
      lower_4_32_share: summarizeScalar(subset.map((row) => row.lowerShare)),
      leaf_off_score: summarizeScalar(subset.map((row) => row.leafScore)),
    })
  }
  return output
}

function physicalGridIndex(grid: any, x: number, y: number) {
  const col = Math.floor((x - Number(grid.bbox[0])) / Number(grid.cellSize))
  const row = Math.floor((y - Number(grid.bbox[1])) / Number(grid.cellSize))
  if (col < 0 || row < 0 || col >= Number(grid.width) || row >= Number(grid.height)) return -1
  return row * Number(grid.width) + col
}

function buildSynthesis(physical: any, leaf: any) {
  if (!validateLidarPhysicalArtifact(physical)) throw new Error('LiDAR physical artifact failed validation')
  if (!validateLeafOffArtifact(leaf)) throw new Error('leaf-off artifact failed validation')

  const leafProduct = leaf.products.find(
    (candidate: any) => candidate?.sourceId === FARM_WATCH_STRUCTURE_SYNTHESIS_PRODUCT.leafSourceId,
  )
  if (!leafProduct) throw new Error('2024 leaf-off product is unavailable')

  const leafGrid = leafProduct.grid
  const leafScore = decodeBase64(leafGrid.score_base64)
  const leafValid = decodeBase64(leafGrid.valid_base64)
  const leafConfidence = decodeBase64(leafGrid.confidence_base64)
  const leafSpectralSupport = decodeBase64(leafGrid.spectral_support_base64)
  const physicalGrid = physical.grid
  const physicalLength = Number(physicalGrid.width) * Number(physicalGrid.height)
  const scoreSum = new Float64Array(physicalLength)
  const confidenceSum = new Float64Array(physicalLength)
  const spectralSupportSum = new Float64Array(physicalLength)
  const sampleCount = new Uint32Array(physicalLength)

  const leafWidth = Number(leafGrid.width)
  const leafHeight = Number(leafGrid.height)
  const bounds = leafProduct.bounds
  for (let row = 0; row < leafHeight; row += 1) {
    const y3857 = Number(bounds.north) -
      ((row + 0.5) / leafHeight) * (Number(bounds.north) - Number(bounds.south))
    for (let col = 0; col < leafWidth; col += 1) {
      const leafIndex = row * leafWidth + col
      if (!leafValid[leafIndex]) continue
      const x3857 = Number(bounds.west) +
        ((col + 0.5) / leafWidth) * (Number(bounds.east) - Number(bounds.west))
      const [x, y] = proj4('EPSG:3857', COMMON_CRS, [x3857, y3857])
      const target = physicalGridIndex(physicalGrid, x, y)
      if (target < 0) continue
      scoreSum[target] += leafScore[leafIndex] / 255
      confidenceSum[target] += leafConfidence[leafIndex] / 255
      spectralSupportSum[target] += leafSpectralSupport[leafIndex] / 255
      sampleCount[target] += 1
    }
  }

  const expectedSamples = Math.max(
    1,
    (Number(physical.cell_meters) / Math.max(0.1, Number(leafGrid.terrain_pixel_m))) ** 2,
  )
  const minimumLeafSamples = Math.max(2, Math.ceil(expectedSamples * 0.5))
  const labels = bandLabels(physicalGrid.thresholds.map(Number))
  const records: any[] = []

  for (let index = 0; index < physicalLength; index += 1) {
    if (
      Number(physicalGrid.total[index]) < Number(physical.minimum_cell_returns) ||
      sampleCount[index] < minimumLeafSamples
    ) continue
    const shares = bandShares(physicalGrid, index)
    if (!shares) continue
    const leafMean = scoreSum[index] / sampleCount[index]
    const confidenceMean = confidenceSum[index] / sampleCount[index]
    const spectralSupportMean = spectralSupportSum[index] / sampleCount[index]
    const lowerShare = (shares[1] || 0) + (shares[2] || 0)
    const upperShare = (shares[3] || 0) + (shares[4] || 0)
    records.push({
      index,
      leafScore: leafMean,
      leafConfidence: confidenceMean,
      leafSpectralSupport: spectralSupportMean,
      shares,
      lowerShare,
      upperShare,
      dominantBand: dominantBand(physicalGrid, index),
    })
  }

  if (records.length < 100) throw new Error('insufficient shared leaf-off/LiDAR cells')

  const leafValues = records.map((row) => row.leafScore)
  const quintileThresholds = [0.2, 0.4, 0.6, 0.8].map((q) => Number(sortedQuantile(leafValues, q)))
  const valid = new Uint8Array(physicalLength)
  const dominant = new Uint8Array(physicalLength)
  const leafScoreU8 = new Uint8Array(physicalLength)
  const leafQuintile = new Uint8Array(physicalLength)
  const lowerShareU8 = new Uint8Array(physicalLength)
  const upperShareU8 = new Uint8Array(physicalLength)
  dominant.fill(255)
  leafQuintile.fill(255)

  const matrixCounts = Array.from({ length: labels.length }, () => new Array(5).fill(0))
  for (const row of records) {
    let quintile = 0
    while (quintile < quintileThresholds.length && row.leafScore > quintileThresholds[quintile]) {
      quintile += 1
    }
    valid[row.index] = 1
    dominant[row.index] = row.dominantBand
    leafScoreU8[row.index] = Math.round(clamp(row.leafScore) * 255)
    leafQuintile[row.index] = quintile
    lowerShareU8[row.index] = Math.round(clamp(row.lowerShare) * 255)
    upperShareU8[row.index] = Math.round(clamp(row.upperShare) * 255)
    matrixCounts[row.dominantBand][quintile] += 1
  }

  const dominantDistribution = labels.map((label, band) => {
    const subset = records.filter((row) => row.dominantBand === band)
    return {
      band,
      label,
      cell_count: subset.length,
      leaf_off_score: summarizeScalar(subset.map((row) => row.leafScore)),
      leaf_off_confidence: summarizeScalar(subset.map((row) => row.leafConfidence)),
      lower_4_32_share: summarizeScalar(subset.map((row) => row.lowerShare)),
      upper_32plus_share: summarizeScalar(subset.map((row) => row.upperShare)),
    }
  })

  const overstory = records.filter(
    (row) => row.upperShare >= FARM_WATCH_STRUCTURE_SYNTHESIS_PRODUCT.minimumUpperShare,
  )
  const fullProfile = crossValidatedProfileModel(records, Number(physicalGrid.width))
  if (fullProfile.status !== 'available') {
    throw new Error('full vertical-profile cross-validation is unavailable')
  }
  const predictionRecords = fullProfile.prediction_records || []
  const residualSpatial = residualSpatialSummary(
    records,
    predictionRecords,
    Number(physicalGrid.width),
    Number(physicalGrid.height),
    Number(physical.cell_meters),
  )
  if (residualSpatial.status !== 'available') {
    throw new Error('out-of-fold residual spatial product is unavailable')
  }
  delete fullProfile.prediction_records

  const matrix = []
  for (let band = 0; band < labels.length; band += 1) {
    for (let quintile = 0; quintile < 5; quintile += 1) {
      const count = matrixCounts[band][quintile]
      matrix.push({
        dominant_band: band,
        dominant_label: labels[band],
        leaf_off_quintile: quintile + 1,
        cell_count: count,
        shared_cell_percent: count / records.length * 100,
      })
    }
  }

  return {
    schema: FARM_WATCH_STRUCTURE_SYNTHESIS_PRODUCT.outputSchemaVersion,
    method: FARM_WATCH_STRUCTURE_SYNTHESIS_PRODUCT.algorithmVersion,
    status: 'available',
    source_pairing: {
      leaf_off_source_id: leafProduct.sourceId,
      leaf_off_acquisition_date: leafProduct.acquisitionDate,
      lidar_acquisition_utc_range: physical.acquisition_utc_range,
      note:
        'The leaf-off observation predates the current LiDAR acquisition. The sensors are not contemporaneous; this is structural context, not a same-day fusion or change product.',
    },
    summary: {
      shared_cell_count: records.length,
      minimum_lidar_returns_per_cell: Number(physical.minimum_cell_returns),
      minimum_leaf_samples_per_cell: minimumLeafSamples,
      leaf_off_score: summarizeScalar(records.map((row) => row.leafScore)),
      leaf_off_confidence: summarizeScalar(records.map((row) => row.leafConfidence)),
      dominant_band_texture_distribution: dominantDistribution,
      dominant_band_variance_partition: variancePartition(records),
      full_vertical_profile_model: fullProfile,
      out_of_fold_residual_spatial: residualSpatial,
      overstory_conditioned: {
        upper_32plus_minimum_share: FARM_WATCH_STRUCTURE_SYNTHESIS_PRODUCT.minimumUpperShare,
        cell_count: overstory.length,
        lower_4_32_share_vs_leaf_off_score_rho: spearman(
          overstory.map((row) => row.lowerShare),
          overstory.map((row) => row.leafScore),
        ),
        lower_4_32_share_quartiles: lowerStrataQuartiles(overstory),
      },
      leaf_off_quintile_thresholds: quintileThresholds,
      vertical_horizontal_matrix: matrix,
      lidar_parcel_band_shares: physical.current_summary.parcel_band_shares,
      leaf_off_transfer_context: leaf.transfer_diagnostic || null,
    },
    combined_grid: {
      native_crs: physical.native_crs,
      bbox: physicalGrid.bbox,
      cellSize: physicalGrid.cellSize,
      cell_meters: physical.cell_meters,
      width: physicalGrid.width,
      height: physicalGrid.height,
      thresholds_ft: physicalGrid.thresholds,
      encoding: 'base64-u8-v1',
      share_encoding: '0..255 represents 0..1',
      invalid_class_value: 255,
      valid_base64: encodeBase64(valid),
      dominant_band_base64: encodeBase64(dominant),
      leaf_score_base64: encodeBase64(leafScoreU8),
      leaf_quintile_base64: encodeBase64(leafQuintile),
      lower_4_32_share_base64: encodeBase64(lowerShareU8),
      upper_32plus_share_base64: encodeBase64(upperShareU8),
    },
    context_integration: {
      canopy: 'display alongside canonical 2025 canopy context; not fused into a score',
      terrain: 'display alongside canonical terrain context; not used to relabel structure',
      soils: 'display alongside canonical SSURGO context; not used to infer vegetation or habitat',
    },
    interpretation_boundary:
      'Current-state structural complementarity only. It describes how the independent 2024 leaf-off horizontal woody-pattern signal varies across 2025 LiDAR height-band composition. Within-band variation is evidence that the layers contain non-identical structural information; it does not prove understory density, vegetation identity, habitat, management condition, causation, or change.',
  }
}

async function claim(slug: string, sourceSignature: string, identity: any) {
  const workerId = [
    'github-actions-structure-synthesis',
    identity.run_id || 'run',
    identity.run_attempt || 'attempt',
  ].join(':')
  const { data, error } = await admin.rpc('farm_watch_claim_materialization_build_v1_internal', {
    p_slug: slug,
    p_product_kind: FARM_WATCH_STRUCTURE_SYNTHESIS_PRODUCT.productKind,
    p_algorithm_version: FARM_WATCH_STRUCTURE_SYNTHESIS_PRODUCT.algorithmVersion,
    p_output_schema_version: FARM_WATCH_STRUCTURE_SYNTHESIS_PRODUCT.outputSchemaVersion,
    p_source_signature: sourceSignature,
    p_worker_id: workerId,
    p_lease_seconds: 900,
  })
  if (error) throw new Error('structure synthesis claim failed: ' + error.message)
  return data
}

async function materialize(slug: string, identity: any) {
  const dependencies = await resolveDependencies(slug)
  const claimed = await claim(slug, dependencies.sourceSignature, identity)
  if (claimed?.action !== 'build') {
    return { status: claimed?.action || 'not_claimed', build: claimed || null }
  }

  const buildId = String(claimed.build_id)
  const leaseToken = String(claimed.lease_token)
  try {
    const [physicalPayload, leafPayload] = await Promise.all([
      downloadArtifact(dependencies.physicalState),
      downloadArtifact(dependencies.leafState),
    ])
    const artifact = buildSynthesis(physicalPayload.artifact, leafPayload.artifact)
    if (!validateStructureSynthesisArtifact(artifact)) {
      throw new Error('structure synthesis artifact failed contract validation')
    }

    const bytes = new TextEncoder().encode(JSON.stringify(artifact))
    if (bytes.byteLength <= 0 || bytes.byteLength > 10 * 1024 * 1024) {
      throw new Error('structure synthesis artifact size is invalid')
    }
    const artifactSha256 = await sha256Hex(bytes)
    const artifactPath = structureSynthesisArtifactPath(
      String(claimed.property_id),
      String(claimed.input_signature_sha256),
      artifactSha256,
    )
    const { error: uploadError } = await admin.storage
      .from(FARM_WATCH_STRUCTURE_SYNTHESIS_PRODUCT.artifactBucket)
      .upload(artifactPath, bytes, {
        contentType: FARM_WATCH_STRUCTURE_SYNTHESIS_PRODUCT.artifactMimeType,
        cacheControl: '31536000',
        upsert: true,
      })
    if (uploadError) throw new Error('structure synthesis artifact upload failed: ' + uploadError.message)

    const now = new Date()
    const defaultExpiry = new Date(
      now.getTime() + FARM_WATCH_STRUCTURE_SYNTHESIS_PRODUCT.refreshDays * 24 * 60 * 60 * 1000,
    )
    const dependencyExpiries = [
      dependencies.physicalState?.materialization?.expires_at,
      dependencies.leafState?.materialization?.expires_at,
    ]
      .map((value) => Date.parse(String(value || '')))
      .filter(Number.isFinite)
    const expiresAt = dependencyExpiries.length
      ? new Date(Math.min(defaultExpiry.getTime(), ...dependencyExpiries))
      : defaultExpiry

    const provenance = {
      dependency_materializations: {
        lidar_physical: {
          id: dependencies.physicalState?.materialization?.id || null,
          artifact_sha256: physicalPayload.artifact_sha256,
        },
        leaf_off: {
          id: dependencies.leafState?.materialization?.id || null,
          artifact_sha256: leafPayload.artifact_sha256,
        },
      },
      source_signature: dependencies.sourceSignature,
      github_workflow: identity,
      completed_at: now.toISOString(),
    }
    const sampledSourceSha256 = await sha256Hex(JSON.stringify(provenance.dependency_materializations))
    const summary = {
      shared_cell_count: artifact.summary.shared_cell_count,
      dominant_band_variance_partition: artifact.summary.dominant_band_variance_partition,
      full_vertical_profile_model: artifact.summary.full_vertical_profile_model,
      out_of_fold_residual_spatial: artifact.summary.out_of_fold_residual_spatial,
      overstory_conditioned: artifact.summary.overstory_conditioned,
      artifact_size_bytes: bytes.byteLength,
    }

    const { data: completed, error: completeError } = await admin.rpc(
      'farm_watch_complete_materialization_build_v1_internal',
      {
        p_build_id: buildId,
        p_lease_token: leaseToken,
        p_sampled_source_sha256: sampledSourceSha256,
        p_evidence_class: FARM_WATCH_STRUCTURE_SYNTHESIS_PRODUCT.evidenceClass,
        p_summary: summary,
        p_source_provenance: provenance,
        p_limitations: FARM_WATCH_STRUCTURE_SYNTHESIS_LIMITATIONS,
        p_artifact_bucket: FARM_WATCH_STRUCTURE_SYNTHESIS_PRODUCT.artifactBucket,
        p_artifact_path: artifactPath,
        p_artifact_format: FARM_WATCH_STRUCTURE_SYNTHESIS_PRODUCT.artifactFormat,
        p_artifact_mime_type: FARM_WATCH_STRUCTURE_SYNTHESIS_PRODUCT.artifactMimeType,
        p_artifact_size_bytes: bytes.byteLength,
        p_artifact_sha256: artifactSha256,
        p_expires_at: expiresAt.toISOString(),
      },
    )
    if (completeError) throw new Error('structure synthesis completion failed: ' + completeError.message)

    return {
      status: 'available',
      materialization_id: completed?.materialization_id || null,
      identity_sha256: completed?.identity_sha256 || null,
      artifact_sha256: artifactSha256,
      artifact_size_bytes: bytes.byteLength,
      shared_cell_count: artifact.summary.shared_cell_count,
      expires_at: expiresAt.toISOString(),
    }
  } catch (error) {
    try {
      await admin.rpc('farm_watch_fail_materialization_build_v1_internal', {
        p_build_id: buildId,
        p_lease_token: leaseToken,
        p_error: String(error instanceof Error ? error.stack || error.message : error).slice(0, 4000),
        p_retry_delay_seconds: 900,
      })
    } catch (failError) {
      console.error('Failed to persist structure synthesis failure', failError)
    }
    throw error
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return json({ error: 'not found' }, 404)
  const token = bearer(req)
  if (!token) return json({ error: 'not found' }, 404)

  let identity: any
  try {
    identity = await verifyFarmWatchGitHubActionsOidc(token)
  } catch (error) {
    console.error('Farm Watch GitHub Actions OIDC rejected', error)
    return json({ error: 'not found' }, 404)
  }

  let body: any
  try {
    body = await req.json()
  } catch {
    return json({ error: 'invalid request' }, 400)
  }
  const slug = boundedSlug(body?.property)
  if (
    !slug ||
    body?.product !== FARM_WATCH_STRUCTURE_SYNTHESIS_PRODUCT.key ||
    body?.operation !== 'materialize'
  ) return json({ error: 'invalid request' }, 400)

  try {
    return json(await materialize(slug, identity))
  } catch (error) {
    console.error('Farm Watch structure synthesis failed', error)
    return json({
      error: 'structure synthesis failed',
      detail: error instanceof Error ? error.message : String(error),
    }, 503)
  }
})
