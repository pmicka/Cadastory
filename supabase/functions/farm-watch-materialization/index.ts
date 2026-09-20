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
    out['access-control-allow-methods'] = 'GET, OPTIONS'
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


async function readTerrainState(slug: string) {
  const { data, error } = await admin.rpc('farm_watch_get_materialization_v1_internal', {
    p_slug: slug,
    p_product_kind: FARM_WATCH_TERRAIN_PRODUCT.productKind,
    p_algorithm_version: FARM_WATCH_TERRAIN_PRODUCT.algorithmVersion,
    p_output_schema_version: FARM_WATCH_TERRAIN_PRODUCT.outputSchemaVersion,
    p_source_signature: FARM_WATCH_TERRAIN_SOURCE_SIGNATURE,
  })
  if (error) throw new Error(`materialization state read failed: ${error.message}`)
  return data
}

async function buildTerrainMaterialization(slug: string, workerId: string) {
  const { data: claim, error: claimError } = await admin.rpc(
    'farm_watch_claim_materialization_build_v1_internal',
    {
      p_slug: slug,
      p_product_kind: FARM_WATCH_TERRAIN_PRODUCT.productKind,
      p_algorithm_version: FARM_WATCH_TERRAIN_PRODUCT.algorithmVersion,
      p_output_schema_version: FARM_WATCH_TERRAIN_PRODUCT.outputSchemaVersion,
      p_source_signature: FARM_WATCH_TERRAIN_SOURCE_SIGNATURE,
      p_worker_id: workerId,
      p_lease_seconds: 900,
    },
  )
  if (claimError) throw new Error(`materialization claim failed: ${claimError.message}`)

  if (claim?.action === 'reuse') return await readTerrainState(slug)
  if (claim?.action !== 'build') {
    return {
      status: claim?.action || 'not_claimed',
      build: claim || null,
      materialization: null,
    }
  }

  const buildId = String(claim.build_id)
  const leaseToken = String(claim.lease_token)
  try {
    const startedAt = performance.now()
    const { artifact, sampledSourceSha256 } = await buildTerrainArtifact(
      claim.boundary_geojson,
      claim.stated_acres == null ? null : Number(claim.stated_acres),
    )
    const artifactJson = JSON.stringify(artifact)
    const artifactBytes = new TextEncoder().encode(artifactJson)
    const artifactSha256 = await sha256Hex(artifactBytes)
    const artifactPath = terrainArtifactPath(
      String(claim.property_id),
      String(claim.input_signature_sha256),
      artifactSha256,
    )

    const { error: uploadError } = await admin.storage
      .from(FARM_WATCH_TERRAIN_PRODUCT.artifactBucket)
      .upload(artifactPath, artifactBytes, {
        contentType: FARM_WATCH_TERRAIN_PRODUCT.artifactMimeType,
        cacheControl: '31536000',
        upsert: true,
      })
    if (uploadError) throw new Error(`terrain artifact upload failed: ${uploadError.message}`)

    const completedAt = new Date()
    const expiresAt = new Date(
      completedAt.getTime() + FARM_WATCH_TERRAIN_PRODUCT.refreshDays * 24 * 60 * 60 * 1000,
    )
    const summary = {
      grid_size: artifact.grid.size,
      raster_observation_count: artifact.grid.values.filter(Number.isFinite).length,
      elevation_min_ft: artifact.grid.min,
      elevation_max_ft: artifact.grid.max,
      contour_interval_ft: artifact.contours.summary.interval,
      contour_path_count: artifact.contours.summary.pathCount,
      flow_trace_count: artifact.flow_paths.length,
      terrain_anatomy_available: Boolean(artifact.anatomy),
      artifact_size_bytes: artifactBytes.byteLength,
      worker_elapsed_ms: Math.round(performance.now() - startedAt),
    }
    const sourceProvenance = {
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
    }

    const { error: completeError } = await admin.rpc(
      'farm_watch_complete_materialization_build_v1_internal',
      {
        p_build_id: buildId,
        p_lease_token: leaseToken,
        p_sampled_source_sha256: sampledSourceSha256,
        p_evidence_class: FARM_WATCH_TERRAIN_PRODUCT.evidenceClass,
        p_summary: summary,
        p_source_provenance: sourceProvenance,
        p_limitations: FARM_WATCH_TERRAIN_LIMITATIONS,
        p_artifact_bucket: FARM_WATCH_TERRAIN_PRODUCT.artifactBucket,
        p_artifact_path: artifactPath,
        p_artifact_format: FARM_WATCH_TERRAIN_PRODUCT.artifactFormat,
        p_artifact_mime_type: FARM_WATCH_TERRAIN_PRODUCT.artifactMimeType,
        p_artifact_size_bytes: artifactBytes.byteLength,
        p_artifact_sha256: artifactSha256,
        p_expires_at: expiresAt.toISOString(),
      },
    )
    if (completeError) throw new Error(`materialization completion failed: ${completeError.message}`)
    return await readTerrainState(slug)
  } catch (error) {
    const { error: failError } = await admin.rpc('farm_watch_fail_materialization_build_v1_internal', {
      p_build_id: buildId,
      p_lease_token: leaseToken,
      p_error: error instanceof Error ? error.message : String(error),
      p_retry_delay_seconds: 300,
    })
    if (failError) console.error('Failed to persist materialization failure', failError.message)
    throw error
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
    if (!slug || body?.product !== FARM_WATCH_TERRAIN_PRODUCT.key) {
      return json({ error: 'invalid request' }, 400, origin)
    }

    try {
      const state = await buildTerrainMaterialization(slug, 'farm-watch-materialization-edge-v1')
      return json({
        property: { slug },
        product: FARM_WATCH_TERRAIN_PRODUCT.key,
        ...state,
      }, 200, origin)
    } catch (error) {
      console.error('Farm Watch terrain materialization worker failed', error)
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
  if (!slug) return json({ error: 'invalid request' }, 400, origin)
  if ((url.searchParams.get('product') || 'terrain') !== FARM_WATCH_TERRAIN_PRODUCT.key) {
    return json({ error: 'invalid request' }, 400, origin)
  }

  const knownSha256 = validSha256(url.searchParams.get('known_artifact_sha256'))

  const { data: state, error: stateError } = await admin.rpc('farm_watch_get_materialization_v1_internal', {
    p_slug: slug,
    p_product_kind: FARM_WATCH_TERRAIN_PRODUCT.productKind,
    p_algorithm_version: FARM_WATCH_TERRAIN_PRODUCT.algorithmVersion,
    p_output_schema_version: FARM_WATCH_TERRAIN_PRODUCT.outputSchemaVersion,
    p_source_signature: FARM_WATCH_TERRAIN_SOURCE_SIGNATURE,
  })
  if (stateError) {
    console.error('farm_watch_get_materialization_v1_internal failed', stateError.message)
    return json({ error: 'materialization unavailable' }, 503, origin)
  }

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
    return json({
      property: { slug },
      product: FARM_WATCH_TERRAIN_PRODUCT.key,
      ...safeState,
      artifact: null,
      not_modified: false,
    }, 200, origin)
  }

  const artifactSha256 = validSha256(String(materialization.artifact_sha256 || ''))
  if (!artifactSha256) {
    console.error('Farm Watch materialization artifact checksum is invalid')
    return json({ error: 'materialization unavailable' }, 503, origin)
  }

  if (knownSha256 === artifactSha256) {
    return json({
      property: { slug },
      product: FARM_WATCH_TERRAIN_PRODUCT.key,
      ...safeState,
      artifact: null,
      not_modified: true,
    }, 200, origin)
  }

  const { data: blob, error: downloadError } = await admin.storage
    .from(String(materialization.artifact_bucket))
    .download(String(materialization.artifact_path))
  if (downloadError || !blob) {
    console.error('Farm Watch materialization download failed', downloadError?.message || 'empty artifact')
    return json({ error: 'materialization unavailable' }, 503, origin)
  }

  const bytes = new Uint8Array(await blob.arrayBuffer())
  const downloadedSha256 = await sha256Hex(bytes)
  if (downloadedSha256 !== artifactSha256) {
    console.error('Farm Watch materialization checksum mismatch')
    return json({ error: 'materialization integrity failure' }, 503, origin)
  }

  let artifact: any
  try {
    artifact = JSON.parse(new TextDecoder().decode(bytes))
  } catch {
    return json({ error: 'materialization integrity failure' }, 503, origin)
  }
  if (!validateTerrainArtifact(artifact)) {
    return json({ error: 'materialization incompatible' }, 503, origin)
  }

  return json({
    property: { slug },
    product: FARM_WATCH_TERRAIN_PRODUCT.key,
    ...safeState,
    artifact,
    not_modified: false,
  }, 200, origin)
})
