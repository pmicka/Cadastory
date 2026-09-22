import 'jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.115.0'
import {
  FARM_WATCH_MAST_CAPACITY_LIMITATIONS,
  FARM_WATCH_MAST_CAPACITY_PRODUCT,
  mastCapacityArtifactPath,
  mastCapacitySourceSignature,
  validateMastCapacityArtifact,
} from '../_shared/farm-watch-mast-capacity-contract.ts'
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
  return /^[0-9a-f]{8}-[0-9a-f-]{27}$/i.test(text) ? text : null
}

async function landscapeDomain(slug: string) {
  const { data, error } = await admin.rpc('farm_watch_get_landscape_domain_v1_internal', {
    p_slug: slug,
  })
  if (error) throw new Error('landscape domain unavailable: ' + error.message)
  if (
    data?.status !== 'available' ||
    !data?.zones?.local_500m ||
    !data?.zones?.landscape_1500m ||
    !data?.zones?.broad_3000m ||
    !/^[0-9a-f]{64}$/.test(String(data?.identity?.identity_sha256 || ''))
  ) throw new Error('current barrier-aware landscape domain is unavailable')
  return data
}

async function claim(slug: string, identity: any) {
  const domain = await landscapeDomain(slug)
  const sourceSignature = mastCapacitySourceSignature({
    landscapeDomainIdentitySha256: String(domain.identity.identity_sha256),
    landscapeDomainAlgorithmVersion: String(domain.identity.algorithm_version || ''),
  })
  const workerId = [
    'github-actions-mast-capacity',
    identity.run_id || 'run',
    identity.run_attempt || 'attempt',
  ].join(':')

  const { data: claim, error } = await admin.rpc(
    'farm_watch_claim_materialization_build_v1_internal',
    {
      p_slug: slug,
      p_product_kind: FARM_WATCH_MAST_CAPACITY_PRODUCT.productKind,
      p_algorithm_version: FARM_WATCH_MAST_CAPACITY_PRODUCT.algorithmVersion,
      p_output_schema_version: FARM_WATCH_MAST_CAPACITY_PRODUCT.outputSchemaVersion,
      p_source_signature: sourceSignature,
      p_worker_id: workerId,
      p_lease_seconds: 3600,
    },
  )
  if (error) throw new Error('mast capacity materialization claim failed: ' + error.message)

  if (claim?.action !== 'build') {
    return {
      action: claim?.action || 'not_claimed',
      build: claim || null,
      landscape_domain_identity_sha256: domain.identity.identity_sha256,
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
    input_signature_sha256: claim.input_signature_sha256,
    source_signature_sha256: claim.source_signature_sha256,
    property_boundary_geojson: claim.boundary_geojson,
    zones: {
      local_500m: domain.zones.local_500m,
      landscape_1500m: domain.zones.landscape_1500m,
      broad_3000m: domain.zones.broad_3000m,
    },
    landscape_domain_identity: domain.identity,
    contract: {
      schema: FARM_WATCH_MAST_CAPACITY_PRODUCT.outputSchemaVersion,
      method: FARM_WATCH_MAST_CAPACITY_PRODUCT.algorithmVersion,
      source_authority: FARM_WATCH_MAST_CAPACITY_PRODUCT.sourceAuthority,
      source_product: FARM_WATCH_MAST_CAPACITY_PRODUCT.sourceProduct,
      source_data_year: FARM_WATCH_MAST_CAPACITY_PRODUCT.sourceDataYear,
      source_service: FARM_WATCH_MAST_CAPACITY_PRODUCT.sourceService,
      source_pixel_meters: FARM_WATCH_MAST_CAPACITY_PRODUCT.sourcePixelMeters,
      source_value_unit: FARM_WATCH_MAST_CAPACITY_PRODUCT.sourceValueUnit,
      domain_scope: FARM_WATCH_MAST_CAPACITY_PRODUCT.domainScope,
    },
  }
}

async function readBuild(buildId: string) {
  const { data, error } = await admin.rpc(
    'farm_watch_get_materialization_build_v1_internal',
    { p_build_id: buildId },
  )
  if (error || !data) throw new Error('materialization build unavailable')
  return data
}

async function complete(slug: string, body: any, identity: any) {
  const buildId = validUuid(body?.build_id)
  const leaseToken = validUuid(body?.lease_token)
  if (!buildId || !leaseToken) throw new Error('invalid build completion identity')

  const artifact = body?.artifact
  if (!validateMastCapacityArtifact(artifact)) {
    throw new Error('mast capacity artifact failed contract validation')
  }

  const domain = await landscapeDomain(slug)
  if (
    String(artifact?.domain?.identity_sha256 || '') !==
    String(domain.identity.identity_sha256 || '')
  ) throw new Error('mast capacity artifact domain identity is stale')

  const expectedSourceSignature = mastCapacitySourceSignature({
    landscapeDomainIdentitySha256: String(domain.identity.identity_sha256),
    landscapeDomainAlgorithmVersion: String(domain.identity.algorithm_version || ''),
  })
  const build = await readBuild(buildId)
  if (
    build.product_kind !== FARM_WATCH_MAST_CAPACITY_PRODUCT.productKind ||
    build.algorithm_version !== FARM_WATCH_MAST_CAPACITY_PRODUCT.algorithmVersion ||
    build.output_schema_version !== FARM_WATCH_MAST_CAPACITY_PRODUCT.outputSchemaVersion ||
    build.source_signature !== expectedSourceSignature ||
    build.status !== 'processing' ||
    String(build.lease_token) !== leaseToken
  ) throw new Error('mast capacity build lease is incompatible')

  const fingerprint = artifact.processing_source_fingerprint
  const sampledSourceSha256 = await sha256Hex(JSON.stringify(fingerprint))
  if (sampledSourceSha256 !== artifact.processing_source_fingerprint_sha256) {
    throw new Error('mast capacity source fingerprint checksum mismatch')
  }

  const bytes = new TextEncoder().encode(JSON.stringify(artifact))
  if (bytes.byteLength <= 0 || bytes.byteLength > 10 * 1024 * 1024) {
    throw new Error('mast capacity artifact size is invalid')
  }
  const artifactSha256 = await sha256Hex(bytes)
  const artifactPath = mastCapacityArtifactPath(
    String(build.property_id),
    String(build.input_signature_sha256),
    artifactSha256,
  )

  const { error: uploadError } = await admin.storage
    .from(FARM_WATCH_MAST_CAPACITY_PRODUCT.artifactBucket)
    .upload(artifactPath, bytes, {
      contentType: FARM_WATCH_MAST_CAPACITY_PRODUCT.artifactMimeType,
      cacheControl: '31536000',
      upsert: true,
    })
  if (uploadError) throw new Error('mast capacity artifact upload failed: ' + uploadError.message)

  const completedAt = new Date()
  const expiresAt = new Date(
    completedAt.getTime() + FARM_WATCH_MAST_CAPACITY_PRODUCT.refreshDays * 86400000,
  )
  const sourceProvenance = {
    ...(artifact.source_provenance || {}),
    landscape_domain_identity: domain.identity,
    github_workflow: identity,
    completed_at: completedAt.toISOString(),
  }
  const { data: completed, error: completeError } = await admin.rpc(
    'farm_watch_complete_materialization_build_v1_internal',
    {
      p_build_id: buildId,
      p_lease_token: leaseToken,
      p_sampled_source_sha256: sampledSourceSha256,
      p_evidence_class: FARM_WATCH_MAST_CAPACITY_PRODUCT.evidenceClass,
      p_summary: artifact.summary,
      p_source_provenance: sourceProvenance,
      p_limitations: FARM_WATCH_MAST_CAPACITY_LIMITATIONS,
      p_artifact_bucket: FARM_WATCH_MAST_CAPACITY_PRODUCT.artifactBucket,
      p_artifact_path: artifactPath,
      p_artifact_format: FARM_WATCH_MAST_CAPACITY_PRODUCT.artifactFormat,
      p_artifact_mime_type: FARM_WATCH_MAST_CAPACITY_PRODUCT.artifactMimeType,
      p_artifact_size_bytes: bytes.byteLength,
      p_artifact_sha256: artifactSha256,
      p_expires_at: expiresAt.toISOString(),
    },
  )
  if (completeError) throw new Error('mast capacity completion failed: ' + completeError.message)

  return {
    status: 'available',
    materialization_id: completed?.materialization_id || null,
    identity_sha256: completed?.identity_sha256 || null,
    artifact_sha256: artifactSha256,
    artifact_size_bytes: bytes.byteLength,
    expires_at: expiresAt.toISOString(),
  }
}

async function fail(body: any) {
  const buildId = validUuid(body?.build_id)
  const leaseToken = validUuid(body?.lease_token)
  if (!buildId || !leaseToken) throw new Error('invalid failed-build identity')
  const { error } = await admin.rpc('farm_watch_fail_materialization_build_v1_internal', {
    p_build_id: buildId,
    p_lease_token: leaseToken,
    p_error: String(body?.error || 'mast capacity materialization failed').slice(0, 4000),
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
    console.error('Farm Watch mast capacity OIDC rejected', error)
    return json({ error: 'not found' }, 404)
  }

  let body: any
  try { body = await req.json() } catch { return json({ error: 'invalid request' }, 400) }
  const slug = boundedSlug(body?.property)
  if (!slug || body?.product !== FARM_WATCH_MAST_CAPACITY_PRODUCT.key) {
    return json({ error: 'invalid request' }, 400)
  }

  try {
    const operation = String(body?.operation || '')
    if (operation === 'claim') {
      return json({
        oidc_audience: FARM_WATCH_GITHUB_OIDC_AUDIENCE,
        identity,
        ...(await claim(slug, identity)),
      })
    }
    if (operation === 'complete') return json(await complete(slug, body, identity))
    if (operation === 'fail') return json(await fail(body))
    return json({ error: 'invalid request' }, 400)
  } catch (error) {
    console.error('Farm Watch mast capacity worker failed', body?.operation, error)
    return json({
      error: 'worker operation failed',
      detail: error instanceof Error ? error.message : String(error),
    }, 503)
  }
})
