import 'jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.115.0'
import {
  FARM_WATCH_LIDAR_SOURCE_PRODUCT,
  FARM_WATCH_LIDAR_SOURCE_SIGNATURE,
} from '../_shared/farm-watch-lidar-source.ts'
import {
  FARM_WATCH_LIDAR_PHYSICAL_LIMITATIONS,
  FARM_WATCH_LIDAR_PHYSICAL_PRODUCT,
  lidarPhysicalArtifactPath,
  lidarPhysicalSourceDescriptor,
  lidarPhysicalSourceSignature,
  validateLidarPhysicalArtifact,
} from '../_shared/farm-watch-lidar-physical-contract.ts'
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

function validSha256(value: unknown) {
  const text = String(value || '').toLowerCase()
  return /^[0-9a-f]{64}$/.test(text) ? text : null
}

async function readSourcePlanState(slug: string) {
  const { data, error } = await admin.rpc('farm_watch_get_materialization_v1_internal', {
    p_slug: slug,
    p_product_kind: FARM_WATCH_LIDAR_SOURCE_PRODUCT.productKind,
    p_algorithm_version: FARM_WATCH_LIDAR_SOURCE_PRODUCT.algorithmVersion,
    p_output_schema_version: FARM_WATCH_LIDAR_SOURCE_PRODUCT.outputSchemaVersion,
    p_source_signature: FARM_WATCH_LIDAR_SOURCE_SIGNATURE,
  })
  if (error) throw new Error('LiDAR source-plan state unavailable: ' + error.message)
  return data
}

async function downloadStoredArtifact(materialization: any) {
  const expectedSha = validSha256(materialization?.artifact_sha256)
  if (!expectedSha) throw new Error('stored artifact checksum unavailable')
  const { data: blob, error } = await admin.storage
    .from(String(materialization?.artifact_bucket || ''))
    .download(String(materialization?.artifact_path || ''))
  if (error || !blob) throw new Error('stored artifact unavailable: ' + (error?.message || 'empty artifact'))
  const bytes = new Uint8Array(await blob.arrayBuffer())
  const actualSha = await sha256Hex(bytes)
  if (actualSha !== expectedSha) throw new Error('stored artifact checksum mismatch')
  let artifact: any
  try {
    artifact = JSON.parse(new TextDecoder().decode(bytes))
  } catch {
    throw new Error('stored artifact JSON invalid')
  }
  return { artifact, bytes, sha256: actualSha }
}

async function sourceContext(slug: string) {
  const state = await readSourcePlanState(slug)
  if (state?.status !== 'available' || !state?.materialization) {
    throw new Error('central LiDAR source coverage is not available')
  }
  const stored = await downloadStoredArtifact(state.materialization)
  if (
    stored.artifact?.schema !== FARM_WATCH_LIDAR_SOURCE_PRODUCT.outputSchemaVersion ||
    stored.artifact?.method !== FARM_WATCH_LIDAR_SOURCE_PRODUCT.algorithmVersion
  ) {
    throw new Error('central LiDAR source coverage is incompatible')
  }

  const phase3 = stored.artifact.collections?.find(
    (row: any) => row?.id === FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.sourceCollection,
  )
  const processingItems = Array.isArray(phase3?.processing_items)
    ? phase3.processing_items.slice().sort((a: any, b: any) => String(a.id).localeCompare(String(b.id)))
    : []
  const sampledCoverage = Number(phase3?.coverage?.sampled_parcel_coverage_percent)
  if (
    processingItems.length === 0 ||
    phase3?.coverage?.coverage_status !== 'complete_sampled' ||
    !Number.isFinite(sampledCoverage) ||
    sampledCoverage < 99.5
  ) {
    throw new Error('Phase 3 source coverage is incomplete or unresolved')
  }

  const sourceSignature = lidarPhysicalSourceSignature(stored.artifact, stored.sha256)
  return {
    sourceState: state,
    sourceArtifact: stored.artifact,
    sourceArtifactSha256: stored.sha256,
    sourceSignature,
    sourceDescriptor: lidarPhysicalSourceDescriptor(stored.artifact, stored.sha256),
    phase3,
    processingItems,
  }
}

async function claimPhysical(slug: string, identity: any) {
  const source = await sourceContext(slug)
  const workerId = [
    'github-actions-lidar',
    identity.run_id || 'run',
    identity.run_attempt || 'attempt',
  ].join(':')

  const { data: claim, error } = await admin.rpc(
    'farm_watch_claim_materialization_build_v1_internal',
    {
      p_slug: slug,
      p_product_kind: FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.productKind,
      p_algorithm_version: FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.algorithmVersion,
      p_output_schema_version: FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.outputSchemaVersion,
      p_source_signature: source.sourceSignature,
      p_worker_id: workerId,
      p_lease_seconds: 3600,
    },
  )
  if (error) throw new Error('physical materialization claim failed: ' + error.message)

  if (claim?.action !== 'build') {
    return {
      action: claim?.action || 'not_claimed',
      build: claim || null,
      source_plan_artifact_sha256: source.sourceArtifactSha256,
      source_descriptor: source.sourceDescriptor,
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
    boundary_geojson: claim.boundary_geojson,
    input_signature_sha256: claim.input_signature_sha256,
    source_plan_artifact_sha256: source.sourceArtifactSha256,
    source_descriptor: source.sourceDescriptor,
    phase3: {
      coverage: source.phase3.coverage,
      processing_items: source.processingItems,
    },
    contract: {
      schema: FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.outputSchemaVersion,
      method: FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.algorithmVersion,
      source_collection: FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.sourceCollection,
      native_crs: FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.nativeCrs,
      ground_cell_meters: FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.groundCellMeters,
      ground_support_radius_meters: FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.groundSupportRadiusMeters,
      structure_cell_meters: FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.structureCellMeters,
      minimum_cell_returns: FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.minimumCellReturns,
      thresholds_ft: FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.thresholdsFt,
    },
  }
}

async function readBuild(buildId: string) {
  const { data, error } = await admin
    .schema('farm_watch')
    .from('property_materialization_builds_v1')
    .select(
      'id,property_id,product_kind,algorithm_version,output_schema_version,input_signature_sha256,source_signature,status,lease_token,lease_expires_at',
    )
    .eq('id', buildId)
    .maybeSingle()
  if (error || !data) throw new Error('materialization build unavailable')
  return data
}

function sameStringSet(a: unknown, b: unknown) {
  if (!Array.isArray(a) || !Array.isArray(b)) return false
  const aa = a.map(String).sort()
  const bb = b.map(String).sort()
  return aa.length === bb.length && aa.every((value, index) => value === bb[index])
}

async function completePhysical(slug: string, body: any) {
  const buildId = validUuid(body?.build_id)
  const leaseToken = validUuid(body?.lease_token)
  if (!buildId || !leaseToken) throw new Error('invalid build completion identity')

  const artifact = body?.artifact
  if (!validateLidarPhysicalArtifact(artifact)) throw new Error('physical artifact failed contract validation')

  const source = await sourceContext(slug)
  if (artifact.source_plan_artifact_sha256 !== source.sourceArtifactSha256) {
    throw new Error('physical artifact source plan is stale')
  }
  const expectedItemIds = source.processingItems.map((item: any) => String(item.id))
  if (!sameStringSet(artifact.processing_item_ids, expectedItemIds)) {
    throw new Error('physical artifact source item set does not match current plan')
  }

  const build = await readBuild(buildId)
  if (
    build.product_kind !== FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.productKind ||
    build.algorithm_version !== FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.algorithmVersion ||
    build.output_schema_version !== FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.outputSchemaVersion ||
    build.source_signature !== source.sourceSignature ||
    build.status !== 'processing' ||
    String(build.lease_token) !== leaseToken
  ) {
    throw new Error('physical build lease is incompatible')
  }

  const fingerprint = artifact?.processing_source_fingerprint
  if (!fingerprint || !sameStringSet(
    fingerprint?.items?.map((row: any) => row?.id),
    expectedItemIds,
  )) {
    throw new Error('physical source fingerprint is incomplete')
  }
  const sampledSourceSha256 = await sha256Hex(JSON.stringify(fingerprint))

  const bytes = new TextEncoder().encode(JSON.stringify(artifact))
  if (bytes.byteLength <= 0 || bytes.byteLength > 10 * 1024 * 1024) {
    throw new Error('physical artifact size is invalid')
  }
  const artifactSha256 = await sha256Hex(bytes)
  const artifactPath = lidarPhysicalArtifactPath(
    String(build.property_id),
    String(build.input_signature_sha256),
    artifactSha256,
  )

  const { error: uploadError } = await admin.storage
    .from(FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.artifactBucket)
    .upload(artifactPath, bytes, {
      contentType: FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.artifactMimeType,
      cacheControl: '31536000',
      upsert: true,
    })
  if (uploadError) throw new Error('physical artifact upload failed: ' + uploadError.message)

  const completedAt = new Date()
  const expiresAt = new Date(
    completedAt.getTime() + FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.refreshDays * 24 * 60 * 60 * 1000,
  )
  const summary = {
    source_collection: artifact.source_collection,
    processing_item_count: artifact.processing_item_ids.length,
    processing_item_ids: artifact.processing_item_ids,
    grid_width: artifact.grid.width,
    grid_height: artifact.grid.height,
    structure_cell_meters: artifact.cell_meters,
    eligible_cell_count: artifact.current_summary?.eligible_cell_count ?? null,
    normalized_structure_point_count:
      artifact.processing_summary?.normalized_structure_point_count ?? null,
    ground_supported_parcel_percent:
      artifact.processing_summary?.ground_supported_parcel_percent ?? null,
    artifact_size_bytes: bytes.byteLength,
  }
  const sourceProvenance = {
    source_product: FARM_WATCH_LIDAR_SOURCE_PRODUCT.productKind,
    source_plan_artifact_sha256: source.sourceArtifactSha256,
    source_descriptor: source.sourceDescriptor,
    processing_source_fingerprint_sha256: sampledSourceSha256,
    github_workflow: body?.workflow_provenance || null,
    completed_at: completedAt.toISOString(),
  }

  const { data: completed, error: completeError } = await admin.rpc(
    'farm_watch_complete_materialization_build_v1_internal',
    {
      p_build_id: buildId,
      p_lease_token: leaseToken,
      p_sampled_source_sha256: sampledSourceSha256,
      p_evidence_class: FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.evidenceClass,
      p_summary: summary,
      p_source_provenance: sourceProvenance,
      p_limitations: FARM_WATCH_LIDAR_PHYSICAL_LIMITATIONS,
      p_artifact_bucket: FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.artifactBucket,
      p_artifact_path: artifactPath,
      p_artifact_format: FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.artifactFormat,
      p_artifact_mime_type: FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.artifactMimeType,
      p_artifact_size_bytes: bytes.byteLength,
      p_artifact_sha256: artifactSha256,
      p_expires_at: expiresAt.toISOString(),
    },
  )
  if (completeError) throw new Error('physical build completion failed: ' + completeError.message)

  return {
    status: 'available',
    materialization_id: completed?.materialization_id || null,
    identity_sha256: completed?.identity_sha256 || null,
    artifact_sha256: artifactSha256,
    artifact_size_bytes: bytes.byteLength,
    expires_at: expiresAt.toISOString(),
  }
}

async function failPhysical(body: any) {
  const buildId = validUuid(body?.build_id)
  const leaseToken = validUuid(body?.lease_token)
  if (!buildId || !leaseToken) throw new Error('invalid failed-build identity')
  const { error } = await admin.rpc('farm_watch_fail_materialization_build_v1_internal', {
    p_build_id: buildId,
    p_lease_token: leaseToken,
    p_error: String(body?.error || 'GitHub Actions LiDAR physical worker failed').slice(0, 4000),
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
  if (!slug || body?.product !== FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.key) {
    return json({ error: 'invalid request' }, 400)
  }

  try {
    const operation = String(body?.operation || '')
    if (operation === 'claim') {
      return json({
        oidc_audience: FARM_WATCH_GITHUB_OIDC_AUDIENCE,
        identity,
        ...(await claimPhysical(slug, identity)),
      })
    }
    if (operation === 'complete') {
      return json(await completePhysical(slug, {
        ...body,
        workflow_provenance: identity,
      }))
    }
    if (operation === 'fail') return json(await failPhysical(body))
    return json({ error: 'invalid request' }, 400)
  } catch (error) {
    console.error('Farm Watch LiDAR worker operation failed', body?.operation, error)
    return json({
      error: 'worker operation failed',
      detail: error instanceof Error ? error.message : String(error),
    }, 503)
  }
})
