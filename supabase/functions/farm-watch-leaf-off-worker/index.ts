import 'jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.115.0'
import {
  FARM_WATCH_LEAF_OFF_LIMITATIONS,
  FARM_WATCH_LEAF_OFF_PRODUCT,
  FARM_WATCH_LEAF_OFF_SOURCE_SIGNATURE,
  leafOffArtifactPath,
  validateLeafOffArtifact,
} from '../_shared/farm-watch-leaf-off-contract.ts'
import {
  FARM_WATCH_GITHUB_OIDC_AUDIENCE,
  verifyFarmWatchGitHubActionsOidc,
} from '../_shared/github-actions-oidc.ts'
import { sha256Hex } from '../_shared/farm-watch-terrain.ts'

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

function validUuid(value: unknown) {
  const text = String(value || '')
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(text)
    ? text
    : null
}

async function readBuild(buildId: string) {
  const { data, error } = await admin.rpc(
    'farm_watch_get_materialization_build_v1_internal',
    { p_build_id: buildId },
  )
  if (error || !data) {
    throw new Error(
      'materialization build unavailable' + (error?.message ? ': ' + error.message : ''),
    )
  }
  return data
}

async function propertyCenter(slug: string) {
  const { data, error } = await admin.rpc('farm_watch_get_property_v1_internal', { p_slug: slug })
  if (error || !data) return null
  const coordinates = data?.center_geojson?.coordinates
  if (!Array.isArray(coordinates) || coordinates.length < 2) return null
  const lon = Number(coordinates[0])
  const lat = Number(coordinates[1])
  return Number.isFinite(lat) && Number.isFinite(lon) ? { lat, lon } : null
}

async function claimLeafOff(slug: string, identity: any) {
  const workerId = [
    'github-actions-leaf-off',
    identity.run_id || 'run',
    identity.run_attempt || 'attempt',
  ].join(':')

  const { data: claim, error } = await admin.rpc(
    'farm_watch_claim_materialization_build_v1_internal',
    {
      p_slug: slug,
      p_product_kind: FARM_WATCH_LEAF_OFF_PRODUCT.productKind,
      p_algorithm_version: FARM_WATCH_LEAF_OFF_PRODUCT.algorithmVersion,
      p_output_schema_version: FARM_WATCH_LEAF_OFF_PRODUCT.outputSchemaVersion,
      p_source_signature: FARM_WATCH_LEAF_OFF_SOURCE_SIGNATURE,
      p_worker_id: workerId,
      p_lease_seconds: 3600,
    },
  )
  if (error) throw new Error('leaf-off materialization claim failed: ' + error.message)

  if (claim?.action !== 'build') {
    return {
      action: claim?.action || 'not_claimed',
      build: claim || null,
    }
  }

  return {
    action: 'build',
    build_id: claim.build_id,
    lease_token: claim.lease_token,
    lease_expires_at: claim.lease_expires_at,
    attempt_count: claim.attempt_count,
    property_id: claim.property_id,
    property_slug: claim.property_slug,
    stated_acres: claim.stated_acres,
    boundary_sha256: claim.boundary_sha256,
    boundary_geojson: claim.boundary_geojson,
    input_signature_sha256: claim.input_signature_sha256,
    center: await propertyCenter(slug),
    contract: {
      schema: FARM_WATCH_LEAF_OFF_PRODUCT.outputSchemaVersion,
      method: FARM_WATCH_LEAF_OFF_PRODUCT.algorithmVersion,
      target_neighborhood_meters: FARM_WATCH_LEAF_OFF_PRODUCT.targetNeighborhoodMeters,
      imagery_target_pixel_meters: FARM_WATCH_LEAF_OFF_PRODUCT.imageryTargetPixelMeters,
      terrain_target_pixel_meters: FARM_WATCH_LEAF_OFF_PRODUCT.terrainTargetPixelMeters,
    },
  }
}

async function completeLeafOff(slug: string, body: any) {
  const buildId = validUuid(body?.build_id)
  const leaseToken = validUuid(body?.lease_token)
  if (!buildId || !leaseToken) throw new Error('invalid build completion identity')

  const artifact = body?.artifact
  if (!validateLeafOffArtifact(artifact)) {
    throw new Error('leaf-off artifact failed contract validation')
  }

  const build = await readBuild(buildId)
  if (
    build.product_kind !== FARM_WATCH_LEAF_OFF_PRODUCT.productKind ||
    build.algorithm_version !== FARM_WATCH_LEAF_OFF_PRODUCT.algorithmVersion ||
    build.output_schema_version !== FARM_WATCH_LEAF_OFF_PRODUCT.outputSchemaVersion ||
    build.source_signature !== FARM_WATCH_LEAF_OFF_SOURCE_SIGNATURE ||
    build.status !== 'processing' ||
    String(build.lease_token) !== leaseToken
  ) {
    throw new Error('leaf-off build lease is incompatible')
  }

  const fingerprint = artifact?.processing_source_fingerprint
  if (!fingerprint || !Array.isArray(fingerprint?.sources) || fingerprint.sources.length !== 2) {
    throw new Error('leaf-off processing source fingerprint is incomplete')
  }
  if (String(fingerprint.property_boundary_sha256 || '') !== String(build.boundary_sha256 || '')) {
    throw new Error('leaf-off artifact boundary fingerprint is stale')
  }

  const sampledSourceSha256 = await sha256Hex(JSON.stringify(fingerprint))
  const bytes = new TextEncoder().encode(JSON.stringify(artifact))
  if (bytes.byteLength <= 0 || bytes.byteLength > 10 * 1024 * 1024) {
    throw new Error('leaf-off artifact size is invalid')
  }
  const artifactSha256 = await sha256Hex(bytes)
  const artifactPath = leafOffArtifactPath(
    String(build.property_id),
    String(build.input_signature_sha256),
    artifactSha256,
  )

  const { error: uploadError } = await admin.storage
    .from(FARM_WATCH_LEAF_OFF_PRODUCT.artifactBucket)
    .upload(artifactPath, bytes, {
      contentType: FARM_WATCH_LEAF_OFF_PRODUCT.artifactMimeType,
      cacheControl: '31536000',
      upsert: true,
    })
  if (uploadError) throw new Error('leaf-off artifact upload failed: ' + uploadError.message)

  const completedAt = new Date()
  const expiresAt = new Date(
    completedAt.getTime() + FARM_WATCH_LEAF_OFF_PRODUCT.refreshDays * 24 * 60 * 60 * 1000,
  )
  const productSummary = Object.fromEntries(
    artifact.products.map((product: any) => [
      product.sourceId,
      {
        source_year: product.sourceYear,
        source_tile: product.sourceTile,
        grid_width: product.grid.width,
        grid_height: product.grid.height,
        valid_cell_count: product.scoreDistribution?.sample_count ?? null,
        high_confidence_percent: product.highConfidencePercent,
        nir_rescue_percent: product.nirRescuePercent,
        neighborhood_meters: product.neighborhoodDiameterM,
      },
    ]),
  )
  const summary = {
    products: productSummary,
    transfer_diagnostic: artifact.transfer_diagnostic,
    artifact_size_bytes: bytes.byteLength,
  }
  const sourceProvenance = {
    source_signature: FARM_WATCH_LEAF_OFF_SOURCE_SIGNATURE,
    processing_source_fingerprint_sha256: sampledSourceSha256,
    processing_source_fingerprint: fingerprint,
    github_workflow: body?.workflow_provenance || null,
    completed_at: completedAt.toISOString(),
  }

  const { data: completed, error: completeError } = await admin.rpc(
    'farm_watch_complete_materialization_build_v1_internal',
    {
      p_build_id: buildId,
      p_lease_token: leaseToken,
      p_sampled_source_sha256: sampledSourceSha256,
      p_evidence_class: FARM_WATCH_LEAF_OFF_PRODUCT.evidenceClass,
      p_summary: summary,
      p_source_provenance: sourceProvenance,
      p_limitations: FARM_WATCH_LEAF_OFF_LIMITATIONS,
      p_artifact_bucket: FARM_WATCH_LEAF_OFF_PRODUCT.artifactBucket,
      p_artifact_path: artifactPath,
      p_artifact_format: FARM_WATCH_LEAF_OFF_PRODUCT.artifactFormat,
      p_artifact_mime_type: FARM_WATCH_LEAF_OFF_PRODUCT.artifactMimeType,
      p_artifact_size_bytes: bytes.byteLength,
      p_artifact_sha256: artifactSha256,
      p_expires_at: expiresAt.toISOString(),
    },
  )
  if (completeError) throw new Error('leaf-off build completion failed: ' + completeError.message)

  return {
    status: 'available',
    materialization_id: completed?.materialization_id || null,
    identity_sha256: completed?.identity_sha256 || null,
    artifact_sha256: artifactSha256,
    artifact_size_bytes: bytes.byteLength,
    expires_at: expiresAt.toISOString(),
  }
}

async function failLeafOff(body: any) {
  const buildId = validUuid(body?.build_id)
  const leaseToken = validUuid(body?.lease_token)
  if (!buildId || !leaseToken) throw new Error('invalid failed-build identity')
  const { error } = await admin.rpc('farm_watch_fail_materialization_build_v1_internal', {
    p_build_id: buildId,
    p_lease_token: leaseToken,
    p_error: String(body?.error || 'GitHub Actions leaf-off worker failed').slice(0, 4000),
    p_retry_delay_seconds: 900,
  })
  if (error) throw new Error('failed-build persistence failed: ' + error.message)
  return { status: 'failed' }
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
  if (!slug || body?.product !== FARM_WATCH_LEAF_OFF_PRODUCT.key) {
    return json({ error: 'invalid request' }, 400)
  }

  try {
    const operation = String(body?.operation || '')
    if (operation === 'claim') {
      return json({
        oidc_audience: FARM_WATCH_GITHUB_OIDC_AUDIENCE,
        identity,
        ...(await claimLeafOff(slug, identity)),
      })
    }
    if (operation === 'complete') {
      return json(await completeLeafOff(slug, {
        ...body,
        workflow_provenance: identity,
      }))
    }
    if (operation === 'fail') return json(await failLeafOff(body))
    return json({ error: 'invalid request' }, 400)
  } catch (error) {
    console.error('Farm Watch leaf-off worker operation failed', body?.operation, error)
    return json({
      error: 'worker operation failed',
      detail: error instanceof Error ? error.message : String(error),
    }, 503)
  }
})
