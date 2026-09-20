import 'jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.115.0'
import {
  FARM_WATCH_TERRAIN_LIMITATIONS,
  FARM_WATCH_TERRAIN_PRODUCT,
  FARM_WATCH_TERRAIN_SOURCE_SIGNATURE,
  terrainArtifactPath,
} from '../_shared/farm-watch-terrain-contract.ts'
import {
  buildTerrainArtifact,
  sha256Hex,
} from '../_shared/farm-watch-terrain.ts'
import {
  FARM_WATCH_LIDAR_SOURCE_LIMITATIONS,
  FARM_WATCH_LIDAR_SOURCE_PRODUCT,
  FARM_WATCH_LIDAR_SOURCE_SIGNATURE,
  buildLidarSourceArtifact,
  lidarSourceArtifactPath,
} from '../_shared/farm-watch-lidar-source.ts'

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

const ALLOWED_ORIGINS = new Set([
  'https://pmicka.com',
  'https://www.pmicka.com',
  'http://127.0.0.1:8000',
  'http://localhost:8000',
])
const DEFAULT_PROPERTY_SLUG = 'validation-property-01'

type ProductKey = 'terrain' | 'lidar-source-coverage'

function headers(origin = ''): Record<string, string> {
  const out: Record<string, string> = {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store, max-age=0',
    pragma: 'no-cache',
    'referrer-policy': 'no-referrer',
    'x-content-type-options': 'nosniff',
  }
  if (ALLOWED_ORIGINS.has(origin)) {
    out['access-control-allow-origin'] = origin
    out.vary = 'Origin'
    out['access-control-allow-headers'] = 'authorization, content-type, apikey'
    out['access-control-allow-methods'] = 'GET, POST, OPTIONS'
  }
  return out
}

function json(body: unknown, status = 200, origin = '') {
  return new Response(JSON.stringify(body), { status, headers: headers(origin) })
}

function bearer(req: Request) {
  const match = /^Bearer\s+(.+)$/i.exec(req.headers.get('authorization') || '')
  return match?.[1]?.trim() || null
}

function boundedSlug(value: string | null) {
  if (!value) return DEFAULT_PROPERTY_SLUG
  const normalized = value.trim().toLowerCase()
  return /^[a-z0-9][a-z0-9-]{0,79}$/.test(normalized) ? normalized : null
}

function validSha256(value: string | null) {
  return value && /^[0-9a-f]{64}$/.test(value) ? value : null
}

function productKey(value: unknown): ProductKey | null {
  const key = String(value || '')
  return key === FARM_WATCH_TERRAIN_PRODUCT.key ||
      key === FARM_WATCH_LIDAR_SOURCE_PRODUCT.key
    ? key as ProductKey
    : null
}

function productSpec(key: ProductKey) {
  if (key === FARM_WATCH_TERRAIN_PRODUCT.key) {
    return {
      key,
      productKind: FARM_WATCH_TERRAIN_PRODUCT.productKind,
      algorithmVersion: FARM_WATCH_TERRAIN_PRODUCT.algorithmVersion,
      outputSchemaVersion: FARM_WATCH_TERRAIN_PRODUCT.outputSchemaVersion,
      sourceSignature: FARM_WATCH_TERRAIN_SOURCE_SIGNATURE,
    }
  }
  return {
    key,
    productKind: FARM_WATCH_LIDAR_SOURCE_PRODUCT.productKind,
    algorithmVersion: FARM_WATCH_LIDAR_SOURCE_PRODUCT.algorithmVersion,
    outputSchemaVersion: FARM_WATCH_LIDAR_SOURCE_PRODUCT.outputSchemaVersion,
    sourceSignature: FARM_WATCH_LIDAR_SOURCE_SIGNATURE,
  }
}

function validateTerrainArtifact(value: any) {
  const grid = value?.grid
  const contours = value?.contours
  return Boolean(
    value?.schema === FARM_WATCH_TERRAIN_PRODUCT.outputSchemaVersion &&
    value?.method === FARM_WATCH_TERRAIN_PRODUCT.algorithmVersion &&
    grid &&
    Number(grid.size) === FARM_WATCH_TERRAIN_PRODUCT.gridSize &&
    Array.isArray(grid.points) &&
    Array.isArray(grid.values) &&
    grid.points.length === FARM_WATCH_TERRAIN_PRODUCT.gridSize ** 2 &&
    grid.values.length === FARM_WATCH_TERRAIN_PRODUCT.gridSize ** 2 &&
    contours?.summary &&
    Array.isArray(contours?.levels) &&
    Array.isArray(value?.flow_paths)
  )
}

function validateLidarSourceArtifact(value: any) {
  if (
    value?.schema !== FARM_WATCH_LIDAR_SOURCE_PRODUCT.outputSchemaVersion ||
    value?.method !== FARM_WATCH_LIDAR_SOURCE_PRODUCT.algorithmVersion ||
    !Array.isArray(value?.collections)
  ) return false

  const expected = new Set(FARM_WATCH_LIDAR_SOURCE_PRODUCT.collections.map((row) => row.id))
  for (const collection of value.collections) {
    if (!expected.has(String(collection?.id || ''))) return false
    if (!Array.isArray(collection?.items) || !Array.isArray(collection?.processing_items)) return false
    if (!collection?.coverage || !Array.isArray(collection.coverage.processing_item_ids)) return false
  }
  return true
}

function validateArtifact(key: ProductKey, value: any) {
  return key === FARM_WATCH_TERRAIN_PRODUCT.key
    ? validateTerrainArtifact(value)
    : validateLidarSourceArtifact(value)
}

async function readState(slug: string, key: ProductKey) {
  const spec = productSpec(key)
  const { data, error } = await admin.rpc('farm_watch_get_materialization_v1_internal', {
    p_slug: slug,
    p_product_kind: spec.productKind,
    p_algorithm_version: spec.algorithmVersion,
    p_output_schema_version: spec.outputSchemaVersion,
    p_source_signature: spec.sourceSignature,
  })
  if (error) throw new Error(`materialization state read failed: ${error.message}`)
  return data
}

async function claimBuild(slug: string, key: ProductKey, workerId: string) {
  const spec = productSpec(key)
  const { data, error } = await admin.rpc('farm_watch_claim_materialization_build_v1_internal', {
    p_slug: slug,
    p_product_kind: spec.productKind,
    p_algorithm_version: spec.algorithmVersion,
    p_output_schema_version: spec.outputSchemaVersion,
    p_source_signature: spec.sourceSignature,
    p_worker_id: workerId,
    p_lease_seconds: 900,
  })
  if (error) throw new Error(`materialization claim failed: ${error.message}`)
  return data
}

async function failBuild(buildId: string, leaseToken: string, error: unknown) {
  const { error: failError } = await admin.rpc('farm_watch_fail_materialization_build_v1_internal', {
    p_build_id: buildId,
    p_lease_token: leaseToken,
    p_error: error instanceof Error ? error.message : String(error),
    p_retry_delay_seconds: 300,
  })
  if (failError) console.error('Failed to persist materialization failure', failError.message)
}

async function completeBuild(args: {
  buildId: string
  leaseToken: string
  sampledSourceSha256: string
  evidenceClass: string
  summary: any
  sourceProvenance: any
  limitations: readonly string[]
  bucket: string
  path: string
  format: string
  mimeType: string
  bytes: Uint8Array
  artifactSha256: string
  expiresAt: string
}) {
  const { error } = await admin.rpc('farm_watch_complete_materialization_build_v1_internal', {
    p_build_id: args.buildId,
    p_lease_token: args.leaseToken,
    p_sampled_source_sha256: args.sampledSourceSha256,
    p_evidence_class: args.evidenceClass,
    p_summary: args.summary,
    p_source_provenance: args.sourceProvenance,
    p_limitations: args.limitations,
    p_artifact_bucket: args.bucket,
    p_artifact_path: args.path,
    p_artifact_format: args.format,
    p_artifact_mime_type: args.mimeType,
    p_artifact_size_bytes: args.bytes.byteLength,
    p_artifact_sha256: args.artifactSha256,
    p_expires_at: args.expiresAt,
  })
  if (error) throw new Error(`materialization completion failed: ${error.message}`)
}

async function buildTerrainMaterialization(slug: string, workerId: string) {
  const claim = await claimBuild(slug, FARM_WATCH_TERRAIN_PRODUCT.key, workerId)
  if (claim?.action === 'reuse') return await readState(slug, FARM_WATCH_TERRAIN_PRODUCT.key)
  if (claim?.action !== 'build') {
    return { status: claim?.action || 'not_claimed', build: claim || null, materialization: null }
  }

  const buildId = String(claim.build_id)
  const leaseToken = String(claim.lease_token)
  try {
    const startedAt = performance.now()
    const { artifact, sampledSourceSha256 } = await buildTerrainArtifact(
      claim.boundary_geojson,
      claim.stated_acres == null ? null : Number(claim.stated_acres),
    )
    const bytes = new TextEncoder().encode(JSON.stringify(artifact))
    const artifactSha256 = await sha256Hex(bytes)
    const path = terrainArtifactPath(
      String(claim.property_id),
      String(claim.input_signature_sha256),
      artifactSha256,
    )
    const { error: uploadError } = await admin.storage
      .from(FARM_WATCH_TERRAIN_PRODUCT.artifactBucket)
      .upload(path, bytes, {
        contentType: FARM_WATCH_TERRAIN_PRODUCT.artifactMimeType,
        cacheControl: '31536000',
        upsert: true,
      })
    if (uploadError) throw new Error(`terrain artifact upload failed: ${uploadError.message}`)

    const completedAt = new Date()
    const expiresAt = new Date(
      completedAt.getTime() + FARM_WATCH_TERRAIN_PRODUCT.refreshDays * 24 * 60 * 60 * 1000,
    )
    await completeBuild({
      buildId,
      leaseToken,
      sampledSourceSha256,
      evidenceClass: FARM_WATCH_TERRAIN_PRODUCT.evidenceClass,
      summary: {
        grid_size: artifact.grid.size,
        raster_observation_count: artifact.grid.values.filter(Number.isFinite).length,
        grid_extent_min_ft: artifact.grid.min,
        grid_extent_max_ft: artifact.grid.max,
        contour_interval_ft: artifact.contours.summary.interval,
        contour_path_count: artifact.contours.summary.pathCount,
        flow_trace_count: artifact.flow_paths.length,
        terrain_anatomy_available: Boolean(artifact.anatomy),
        artifact_size_bytes: bytes.byteLength,
        worker_elapsed_ms: Math.round(performance.now() - startedAt),
      },
      sourceProvenance: {
        source_slug: FARM_WATCH_TERRAIN_PRODUCT.sourceSlug,
        source_url: FARM_WATCH_TERRAIN_PRODUCT.sourceUrl,
        source_signature: FARM_WATCH_TERRAIN_SOURCE_SIGNATURE,
        source_signature_sha256: claim.source_signature_sha256,
        source_revision_status: FARM_WATCH_TERRAIN_PRODUCT.sourceRevisionStatus,
        sampled_source_sha256: sampledSourceSha256,
        operation: 'ImageServer/getSamples',
        grid_size: FARM_WATCH_TERRAIN_PRODUCT.gridSize,
        bounds_padding_fraction: FARM_WATCH_TERRAIN_PRODUCT.boundsPaddingFraction,
        input_srid: 4326,
        requested_at: completedAt.toISOString(),
      },
      limitations: FARM_WATCH_TERRAIN_LIMITATIONS,
      bucket: FARM_WATCH_TERRAIN_PRODUCT.artifactBucket,
      path,
      format: FARM_WATCH_TERRAIN_PRODUCT.artifactFormat,
      mimeType: FARM_WATCH_TERRAIN_PRODUCT.artifactMimeType,
      bytes,
      artifactSha256,
      expiresAt: expiresAt.toISOString(),
    })
    return await readState(slug, FARM_WATCH_TERRAIN_PRODUCT.key)
  } catch (error) {
    await failBuild(buildId, leaseToken, error)
    throw error
  }
}

async function buildLidarSourceMaterialization(slug: string, workerId: string) {
  const claim = await claimBuild(slug, FARM_WATCH_LIDAR_SOURCE_PRODUCT.key, workerId)
  if (claim?.action === 'reuse') return await readState(slug, FARM_WATCH_LIDAR_SOURCE_PRODUCT.key)
  if (claim?.action !== 'build') {
    return { status: claim?.action || 'not_claimed', build: claim || null, materialization: null }
  }

  const buildId = String(claim.build_id)
  const leaseToken = String(claim.lease_token)
  try {
    const startedAt = performance.now()
    const { artifact, sampledSourceSha256 } = await buildLidarSourceArtifact(claim.boundary_geojson)
    const bytes = new TextEncoder().encode(JSON.stringify(artifact))
    const artifactSha256 = await sha256Hex(bytes)
    const path = lidarSourceArtifactPath(
      String(claim.property_id),
      String(claim.input_signature_sha256),
      artifactSha256,
    )
    const { error: uploadError } = await admin.storage
      .from(FARM_WATCH_LIDAR_SOURCE_PRODUCT.artifactBucket)
      .upload(path, bytes, {
        contentType: FARM_WATCH_LIDAR_SOURCE_PRODUCT.artifactMimeType,
        cacheControl: '31536000',
        upsert: true,
      })
    if (uploadError) throw new Error(`LiDAR source artifact upload failed: ${uploadError.message}`)

    const completedAt = new Date()
    const expiresAt = new Date(
      completedAt.getTime() + FARM_WATCH_LIDAR_SOURCE_PRODUCT.refreshDays * 24 * 60 * 60 * 1000,
    )
    const collectionSummary = Object.fromEntries(artifact.collections.map((collection: any) => [
      collection.id,
      {
        matched_item_count: collection.matched_item_count,
        selected_item_count: collection.coverage?.intersecting_usable_item_count ?? 0,
        processing_mode: collection.coverage?.processing_mode || 'unavailable',
        sampled_parcel_coverage_percent:
          collection.coverage?.sampled_parcel_coverage_percent ?? null,
        processing_item_ids: collection.coverage?.processing_item_ids || [],
      },
    ]))

    await completeBuild({
      buildId,
      leaseToken,
      sampledSourceSha256,
      evidenceClass: FARM_WATCH_LIDAR_SOURCE_PRODUCT.evidenceClass,
      summary: {
        collections: collectionSummary,
        artifact_size_bytes: bytes.byteLength,
        worker_elapsed_ms: Math.round(performance.now() - startedAt),
      },
      sourceProvenance: {
        source_slug: 'kyfromabove-lidar-stac',
        source_url: FARM_WATCH_LIDAR_SOURCE_PRODUCT.stacRoot,
        source_signature: FARM_WATCH_LIDAR_SOURCE_SIGNATURE,
        source_signature_sha256: claim.source_signature_sha256,
        source_revision_status: 'provider_catalog_revision_unresolved',
        sampled_source_sha256: sampledSourceSha256,
        operation: 'STAC POST /search',
        requested_at: completedAt.toISOString(),
      },
      limitations: FARM_WATCH_LIDAR_SOURCE_LIMITATIONS,
      bucket: FARM_WATCH_LIDAR_SOURCE_PRODUCT.artifactBucket,
      path,
      format: FARM_WATCH_LIDAR_SOURCE_PRODUCT.artifactFormat,
      mimeType: FARM_WATCH_LIDAR_SOURCE_PRODUCT.artifactMimeType,
      bytes,
      artifactSha256,
      expiresAt: expiresAt.toISOString(),
    })
    return await readState(slug, FARM_WATCH_LIDAR_SOURCE_PRODUCT.key)
  } catch (error) {
    await failBuild(buildId, leaseToken, error)
    throw error
  }
}

async function buildMaterialization(slug: string, key: ProductKey, workerId: string) {
  return key === FARM_WATCH_TERRAIN_PRODUCT.key
    ? buildTerrainMaterialization(slug, workerId)
    : buildLidarSourceMaterialization(slug, workerId)
}

async function readPayload(
  slug: string,
  key: ProductKey,
  state: any,
  knownSha256: string | null = null,
) {
  const status = String(state?.status || 'missing')
  const materialization = state?.materialization || null
  const safeState = {
    status,
    identity: state?.identity || null,
    build: state?.build || null,
    materialization: materialization ? {
      id: materialization.id,
      identity_sha256: materialization.identity_sha256,
      evidence_class: materialization.evidence_class,
      summary: materialization.summary || {},
      source_provenance: materialization.source_provenance || {},
      limitations: materialization.limitations || [],
      artifact_format: materialization.artifact_format,
      artifact_size_bytes: materialization.artifact_size_bytes,
      artifact_sha256: materialization.artifact_sha256,
      completed_at: materialization.completed_at,
      expires_at: materialization.expires_at,
    } : null,
  }

  if (status !== 'available' || !materialization) {
    return {
      property: { slug },
      product: key,
      ...safeState,
      artifact: null,
      not_modified: false,
    }
  }

  const artifactSha256 = validSha256(String(materialization.artifact_sha256 || ''))
  if (!artifactSha256) throw new Error('materialization artifact checksum is invalid')
  if (knownSha256 === artifactSha256) {
    return {
      property: { slug },
      product: key,
      ...safeState,
      artifact: null,
      not_modified: true,
    }
  }

  const { data: blob, error: downloadError } = await admin.storage
    .from(String(materialization.artifact_bucket))
    .download(String(materialization.artifact_path))
  if (downloadError || !blob) {
    throw new Error(`materialization artifact download failed: ${downloadError?.message || 'empty artifact'}`)
  }

  const bytes = new Uint8Array(await blob.arrayBuffer())
  const downloadedSha256 = await sha256Hex(bytes)
  if (downloadedSha256 !== artifactSha256) throw new Error('materialization artifact checksum mismatch')

  let artifact: any
  try {
    artifact = JSON.parse(new TextDecoder().decode(bytes))
  } catch {
    throw new Error('materialization artifact JSON is invalid')
  }
  if (!validateArtifact(key, artifact)) throw new Error('materialization artifact is incompatible')

  return {
    property: { slug },
    product: key,
    ...safeState,
    artifact,
    not_modified: false,
  }
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get('origin') || ''
  if (origin && !ALLOWED_ORIGINS.has(origin)) return json({ error: 'not found' }, 404)
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: headers(origin) })

  if (req.method === 'POST') {
    let body: any = null
    try { body = await req.json() } catch { return json({ error: 'invalid request' }, 400, origin) }

    const workerToken = typeof body?.worker_token === 'string' ? body.worker_token : null
    const { data: workerAllowed, error: workerError } = await admin.rpc(
      'farm_watch_validate_materialization_worker_v1_internal',
      { p_token: workerToken },
    )
    if (workerError || workerAllowed !== true) return json({ error: 'not found' }, 404, origin)

    const slug = boundedSlug(typeof body?.property === 'string' ? body.property : null)
    const key = productKey(body?.product)
    if (!slug || !key) return json({ error: 'invalid request' }, 400, origin)

    try {
      const operation = body?.operation === 'read' ? 'read' : 'build'
      const state = operation === 'read'
        ? await readState(slug, key)
        : await buildMaterialization(slug, key, 'farm-watch-materialization-edge-v2')
      const knownSha256 = validSha256(
        typeof body?.known_artifact_sha256 === 'string'
          ? body.known_artifact_sha256.trim().toLowerCase()
          : null,
      )
      return json(await readPayload(slug, key, state, knownSha256), 200, origin)
    } catch (error) {
      console.error('Farm Watch materialization worker failed', key, error)
      return json({ error: 'materialization build failed' }, 503, origin)
    }
  }

  if (req.method !== 'GET') return json({ error: 'not found' }, 404, origin)

  const token = bearer(req)
  if (!token) return json({ error: 'not found' }, 404, origin)

  const { data: userData, error: userError } = await admin.auth.getUser(token)
  const user = userData?.user
  if (userError || !user) return json({ error: 'not found' }, 404, origin)

  const { data: allowed, error: accessError } = await admin.rpc('farm_watch_authorize_user_v1_internal', {
    p_user_id: user.id,
  })
  if (accessError || allowed !== true) return json({ error: 'not found' }, 404, origin)

  const url = new URL(req.url)
  const slug = boundedSlug(url.searchParams.get('property'))
  const key = productKey(url.searchParams.get('product') || FARM_WATCH_TERRAIN_PRODUCT.key)
  if (!slug || !key) return json({ error: 'invalid request' }, 400, origin)

  try {
    const state = await readState(slug, key)
    const knownSha256 = validSha256(url.searchParams.get('known_artifact_sha256'))
    return json(await readPayload(slug, key, state, knownSha256), 200, origin)
  } catch (error) {
    console.error('Farm Watch materialization read failed', key, error)
    return json({ error: 'materialization unavailable' }, 503, origin)
  }
})
