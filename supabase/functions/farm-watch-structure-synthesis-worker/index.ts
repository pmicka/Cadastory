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
  const physicalGrid = physical.grid
  const physicalLength = Number(physicalGrid.width) * Number(physicalGrid.height)
  const scoreSum = new Float64Array(physicalLength)
  const confidenceSum = new Float64Array(physicalLength)
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
    const lowerShare = (shares[1] || 0) + (shares[2] || 0)
    const upperShare = (shares[3] || 0) + (shares[4] || 0)
    records.push({
      index,
      leafScore: leafMean,
      leafConfidence: confidenceMean,
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
