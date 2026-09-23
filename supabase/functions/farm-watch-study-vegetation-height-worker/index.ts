import 'jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.115.0'
import {
  FARM_WATCH_STUDY_VEGETATION_HEIGHT_LIMITATIONS,
  FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT,
  studyVegetationHeightArtifactPath,
  studyVegetationHeightSourceSignature,
  validateStudyVegetationHeightArtifact,
} from '../_shared/farm-watch-study-vegetation-height-contract.ts'
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

async function landscapeDomain(slug: string) {
  const { data, error } = await admin.rpc('farm_watch_get_landscape_domain_v1_internal', {
    p_slug: slug,
  })
  if (error) throw new Error('landscape domain unavailable: ' + error.message)
  if (
    data?.status !== 'available' ||
    !data?.zones?.local_500m ||
    !/^[0-9a-f]{64}$/.test(String(data?.identity?.identity_sha256 || ''))
  ) {
    throw new Error('current barrier-aware local_500m landscape domain is unavailable')
  }
  return data
}

function sourceSignatureForDomain(domain: any) {
  return studyVegetationHeightSourceSignature({
    landscapeDomainIdentitySha256: String(domain.identity.identity_sha256),
    landscapeDomainAlgorithmVersion: String(domain.identity.algorithm_version || ''),
  })
}

async function studyVegetationHeightQaContext(slug: string) {
  const domain = await landscapeDomain(slug)
  const sourceSignature = sourceSignatureForDomain(domain)

  const [{ data: anchor, error: anchorError }, { data: state, error: stateError }] =
    await Promise.all([
      admin.rpc('farm_watch_get_land_anchor_v1_internal', { p_slug: slug }),
      admin.rpc('farm_watch_get_materialization_v1_internal', {
        p_slug: slug,
        p_product_kind: FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.productKind,
        p_algorithm_version: FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.algorithmVersion,
        p_output_schema_version: FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.outputSchemaVersion,
        p_source_signature: sourceSignature,
      }),
    ])

  if (anchorError || !anchor?.property_id || !anchor?.boundary_geojson) {
    throw new Error(
      'study vegetation-height QA property anchor unavailable' +
        (anchorError?.message ? ': ' + anchorError.message : ''),
    )
  }
  if (
    stateError ||
    state?.status !== 'available' ||
    !state?.materialization?.artifact_sha256 ||
    !state?.materialization?.artifact_size_bytes
  ) {
    throw new Error(
      'study vegetation-height QA production materialization unavailable' +
        (stateError?.message ? ': ' + stateError.message : ''),
    )
  }

  return {
    status: 'available',
    property_id: anchor.property_id,
    property_slug: slug,
    stated_acres: anchor.stated_acres,
    property_boundary_geojson: anchor.boundary_geojson,
    analysis_domain_geojson: domain.zones.local_500m,
    landscape_domain_identity: domain.identity,
    production_materialization: state.materialization,
    contract: {
      schema: FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.outputSchemaVersion,
      method: FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.algorithmVersion,
      source_collection: FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.sourceCollection,
      native_crs: FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.nativeCrs,
      domain_meters: FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.domainMeters,
      cell_meters: FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.cellMeters,
      ground_support_radius_meters:
        FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.groundSupportRadiusMeters,
      first_return_support_radius_meters:
        FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.firstReturnSupportRadiusMeters,
    },
  }
}

async function claimStudyVegetationHeight(slug: string, identity: any) {
  const domain = await landscapeDomain(slug)
  const sourceSignature = sourceSignatureForDomain(domain)
  const workerId = [
    'github-actions-study-vegetation-height',
    identity.run_id || 'run',
    identity.run_attempt || 'attempt',
  ].join(':')

  const { data: claim, error } = await admin.rpc(
    'farm_watch_claim_materialization_build_v1_internal',
    {
      p_slug: slug,
      p_product_kind: FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.productKind,
      p_algorithm_version: FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.algorithmVersion,
      p_output_schema_version: FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.outputSchemaVersion,
      p_source_signature: sourceSignature,
      p_worker_id: workerId,
      p_lease_seconds: 7200,
    },
  )
  if (error) {
    throw new Error('study vegetation-height materialization claim failed: ' + error.message)
  }

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
    stated_acres: claim.stated_acres,
    property_boundary_geojson: claim.boundary_geojson,
    analysis_domain_geojson: domain.zones.local_500m,
    landscape_domain_identity: domain.identity,
    input_signature_sha256: claim.input_signature_sha256,
    source_signature_sha256: claim.source_signature_sha256,
    contract: {
      schema: FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.outputSchemaVersion,
      method: FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.algorithmVersion,
      source_collection: FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.sourceCollection,
      native_crs: FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.nativeCrs,
      domain_meters: FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.domainMeters,
      cell_meters: FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.cellMeters,
      ground_support_radius_meters:
        FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.groundSupportRadiusMeters,
      first_return_support_radius_meters:
        FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.firstReturnSupportRadiusMeters,
    },
  }
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

async function completeStudyVegetationHeight(slug: string, body: any) {
  const buildId = validUuid(body?.build_id)
  const leaseToken = validUuid(body?.lease_token)
  if (!buildId || !leaseToken) throw new Error('invalid build completion identity')

  const artifact = body?.artifact
  if (!validateStudyVegetationHeightArtifact(artifact)) {
    throw new Error('study vegetation-height artifact failed contract validation')
  }

  const domain = await landscapeDomain(slug)
  const expectedSourceSignature = sourceSignatureForDomain(domain)
  if (
    String(artifact?.domain?.identity_sha256 || '') !==
      String(domain.identity.identity_sha256 || '')
  ) {
    throw new Error('study vegetation-height artifact domain identity is stale')
  }

  const build = await readBuild(buildId)
  if (
    build.product_kind !== FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.productKind ||
    build.algorithm_version !== FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.algorithmVersion ||
    build.output_schema_version !== FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.outputSchemaVersion ||
    build.source_signature !== expectedSourceSignature ||
    build.status !== 'processing' ||
    String(build.lease_token) !== leaseToken
  ) {
    throw new Error('study vegetation-height build lease is incompatible')
  }

  const fingerprint = artifact?.processing_source_fingerprint
  if (
    !fingerprint ||
    String(fingerprint?.domain_identity_sha256 || '') !==
      String(domain.identity.identity_sha256 || '') ||
    !Array.isArray(fingerprint?.items) ||
    fingerprint.items.length === 0
  ) {
    throw new Error('study vegetation-height source fingerprint is incomplete')
  }

  const sampledSourceSha256 = await sha256Hex(JSON.stringify(fingerprint))
  const bytes = new TextEncoder().encode(JSON.stringify(artifact))
  if (bytes.byteLength <= 0 || bytes.byteLength > 10 * 1024 * 1024) {
    throw new Error('study vegetation-height artifact size is invalid')
  }
  const artifactSha256 = await sha256Hex(bytes)
  const artifactPath = studyVegetationHeightArtifactPath(
    String(build.property_id),
    String(build.input_signature_sha256),
    artifactSha256,
  )

  const { error: uploadError } = await admin.storage
    .from(FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.artifactBucket)
    .upload(artifactPath, bytes, {
      contentType: FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.artifactMimeType,
      cacheControl: '31536000',
      upsert: true,
    })
  if (uploadError) {
    throw new Error('study vegetation-height artifact upload failed: ' + uploadError.message)
  }

  const completedAt = new Date()
  const expiresAt = new Date(
    completedAt.getTime() +
      FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.refreshDays * 24 * 60 * 60 * 1000,
  )
  const summary = {
    study_measurement_id: 'FW-M02-vegetation-height',
    domain: artifact.summary.domain,
    property: artifact.summary.property,
    local_ring: artifact.summary.local_ring,
    processing: {
      ground_point_count: artifact.processing_summary.ground_point_count,
      first_return_point_count: artifact.processing_summary.first_return_point_count,
      output_ground_supported_percent:
        artifact.processing_summary.output_ground_supported_percent,
      output_first_return_supported_percent:
        artifact.processing_summary.output_first_return_supported_percent,
      output_height_valid_percent:
        artifact.processing_summary.output_height_valid_percent,
      negative_raw_height_count: artifact.processing_summary.negative_raw_height_count,
      negative_raw_height_percent: artifact.processing_summary.negative_raw_height_percent,
      negative_magnitude_m: artifact.processing_summary.negative_magnitude_m,
      negative_threshold_counts: artifact.processing_summary.negative_threshold_counts,
      negative_support_breakdown: artifact.processing_summary.negative_support_breakdown,
    },
    artifact_size_bytes: bytes.byteLength,
  }
  const sourceProvenance = {
    source_signature: expectedSourceSignature,
    source_plan_artifact_sha256: artifact.source_plan_artifact_sha256,
    processing_source_fingerprint_sha256: sampledSourceSha256,
    processing_source_fingerprint: fingerprint,
    landscape_domain_identity: domain.identity,
    github_workflow: body?.workflow_provenance || null,
    completed_at: completedAt.toISOString(),
  }

  const { data: completed, error: completeError } = await admin.rpc(
    'farm_watch_complete_materialization_build_v1_internal',
    {
      p_build_id: buildId,
      p_lease_token: leaseToken,
      p_sampled_source_sha256: sampledSourceSha256,
      p_evidence_class: FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.evidenceClass,
      p_summary: summary,
      p_source_provenance: sourceProvenance,
      p_limitations: FARM_WATCH_STUDY_VEGETATION_HEIGHT_LIMITATIONS,
      p_artifact_bucket: FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.artifactBucket,
      p_artifact_path: artifactPath,
      p_artifact_format: FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.artifactFormat,
      p_artifact_mime_type: FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.artifactMimeType,
      p_artifact_size_bytes: bytes.byteLength,
      p_artifact_sha256: artifactSha256,
      p_expires_at: expiresAt.toISOString(),
    },
  )
  if (completeError) {
    throw new Error('study vegetation-height build completion failed: ' + completeError.message)
  }

  return {
    status: 'available',
    materialization_id: completed?.materialization_id || null,
    identity_sha256: completed?.identity_sha256 || null,
    artifact_sha256: artifactSha256,
    artifact_size_bytes: bytes.byteLength,
    expires_at: expiresAt.toISOString(),
  }
}

async function failStudyVegetationHeight(body: any) {
  const buildId = validUuid(body?.build_id)
  const leaseToken = validUuid(body?.lease_token)
  if (!buildId || !leaseToken) throw new Error('invalid failed-build identity')
  const { error } = await admin.rpc('farm_watch_fail_materialization_build_v1_internal', {
    p_build_id: buildId,
    p_lease_token: leaseToken,
    p_error: String(body?.error || 'GitHub Actions study vegetation-height worker failed')
      .slice(0, 4000),
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
  if (!slug || body?.product !== FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT.key) {
    return json({ error: 'invalid request' }, 400)
  }

  try {
    const operation = String(body?.operation || '')
    if (operation === 'qa_context') {
      return json({
        oidc_audience: FARM_WATCH_GITHUB_OIDC_AUDIENCE,
        identity,
        ...(await studyVegetationHeightQaContext(slug)),
      })
    }
    if (operation === 'claim') {
      return json({
        oidc_audience: FARM_WATCH_GITHUB_OIDC_AUDIENCE,
        identity,
        ...(await claimStudyVegetationHeight(slug, identity)),
      })
    }
    if (operation === 'complete') {
      return json(await completeStudyVegetationHeight(slug, {
        ...body,
        workflow_provenance: identity,
      }))
    }
    if (operation === 'fail') return json(await failStudyVegetationHeight(body))
    return json({ error: 'invalid request' }, 400)
  } catch (error) {
    console.error('Farm Watch study vegetation-height worker operation failed', body?.operation, error)
    return json({
      error: 'worker operation failed',
      detail: error instanceof Error ? error.message : String(error),
    }, 503)
  }
})
