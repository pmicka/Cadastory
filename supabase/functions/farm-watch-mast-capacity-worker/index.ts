import 'jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.115.0'
import {
  FARM_WATCH_MAST_CAPACITY_GROUPS,
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

const EXPECTED_SPECIES_CODES = new Set(
  FARM_WATCH_MAST_CAPACITY_PRODUCT.groupOrder.flatMap((group) =>
    FARM_WATCH_MAST_CAPACITY_GROUPS[group].map((row) => row.spcd)
  ),
)

function bytesToBase64(bytes: Uint8Array) {
  let binary = ''
  const chunk = 0x8000
  for (let offset = 0; offset < bytes.length; offset += chunk) {
    binary += String.fromCharCode(...bytes.subarray(offset, Math.min(bytes.length, offset + chunk)))
  }
  return btoa(binary)
}

async function bigmapJson(path: string, params: URLSearchParams) {
  const response = await fetch(FARM_WATCH_MAST_CAPACITY_PRODUCT.sourceService + path, {
    method: 'POST',
    headers: {
      accept: 'application/json',
      'content-type': 'application/x-www-form-urlencoded; charset=UTF-8',
      'user-agent': 'Cadastory-Farm-Watch/1.0 (+https://pmicka.com)',
    },
    body: params.toString(),
  })
  if (!response.ok) {
    const detail = await response.text().catch(() => '')
    throw new Error(
      'BIGMAP source request failed: ' + response.status +
      (detail ? ' ' + detail.slice(0, 500) : ''),
    )
  }
  const payload = await response.json()
  if (payload?.error) throw new Error('BIGMAP source error: ' + JSON.stringify(payload.error))
  return payload
}

async function bigmapCatalog(codes?: number[]) {
  const requested = (codes?.length ? codes : Array.from(EXPECTED_SPECIES_CODES))
    .map(Number)
    .filter((value) => Number.isInteger(value) && EXPECTED_SPECIES_CODES.has(value))
  if (!requested.length) throw new Error('BIGMAP species request is empty')
  const params = new URLSearchParams()
  params.set('f', 'json')
  params.set('where', 'category=1 AND spcd IN (' + requested.join(',') + ')')
  params.set('outFields', 'objectid,spcd,common_name,genus,species,name')
  params.set('returnGeometry', 'false')
  params.set('orderByFields', 'spcd')
  const payload = await bigmapJson('/query', params)
  const records = (payload?.features || []).map((feature: any) => feature?.attributes || {})
  for (const code of requested) {
    const matches = records.filter((row: any) => Number(row?.spcd) === code)
    if (matches.length !== 1) throw new Error('BIGMAP primary species catalog mismatch for SPCD ' + code)
  }
  return records
}

async function sourceCatalog() {
  return {
    status: 'available',
    source_service: FARM_WATCH_MAST_CAPACITY_PRODUCT.sourceService,
    source_data_year: FARM_WATCH_MAST_CAPACITY_PRODUCT.sourceDataYear,
    source_native_crs: FARM_WATCH_MAST_CAPACITY_PRODUCT.sourceNativeCrs,
    source_native_wkid: FARM_WATCH_MAST_CAPACITY_PRODUCT.sourceNativeWkid,
    source_pixel_meters: FARM_WATCH_MAST_CAPACITY_PRODUCT.sourcePixelMeters,
    records: await bigmapCatalog(),
  }
}

async function sourceExport(body: any) {
  const spcd = Number(body?.spcd)
  if (!Number.isInteger(spcd) || !EXPECTED_SPECIES_CODES.has(spcd)) {
    throw new Error('BIGMAP species code is not authorized')
  }
  const bbox = Array.isArray(body?.bbox) ? body.bbox.map(Number) : []
  const width = Number(body?.width)
  const height = Number(body?.height)
  if (
    bbox.length !== 4 || bbox.some((value: number) => !Number.isFinite(value)) ||
    !Number.isInteger(width) || width <= 0 || width > 400 ||
    !Number.isInteger(height) || height <= 0 || height > 400
  ) throw new Error('BIGMAP export bounds are invalid')

  const cell = FARM_WATCH_MAST_CAPACITY_PRODUCT.sourcePixelMeters
  const expectedWidth = (bbox[2] - bbox[0]) / cell
  const expectedHeight = (bbox[3] - bbox[1]) / cell
  if (
    Math.abs(expectedWidth - width) > 1e-6 ||
    Math.abs(expectedHeight - height) > 1e-6
  ) throw new Error('BIGMAP export grid is not native 30 m')

  const record = (await bigmapCatalog([spcd]))[0]
  const params = new URLSearchParams()
  params.set('f', 'json')
  params.set('bbox', bbox.join(','))
  params.set('bboxSR', String(FARM_WATCH_MAST_CAPACITY_PRODUCT.sourceNativeWkid))
  params.set('imageSR', String(FARM_WATCH_MAST_CAPACITY_PRODUCT.sourceNativeWkid))
  params.set('size', width + ',' + height)
  params.set('format', 'tiff')
  params.set('pixelType', 'F32')
  params.set('interpolation', 'RSP_NearestNeighbor')
  params.set('mosaicRule', JSON.stringify({
    mosaicMethod: 'esriMosaicLockRaster',
    lockRasterIds: [Number(record.objectid)],
  }))
  const exported = await bigmapJson('/exportImage', params)
  const href = String(exported?.href || '')
  if (!href.startsWith('https://imagery.geoplatform.gov/iipp/rest/directories/system/arcgisoutput/')) {
    throw new Error('BIGMAP export URL is invalid')
  }

  const response = await fetch(href, {
    headers: { 'user-agent': 'Cadastory-Farm-Watch/1.0 (+https://pmicka.com)' },
  })
  if (!response.ok) throw new Error('BIGMAP TIFF fetch failed: ' + response.status)
  const bytes = new Uint8Array(await response.arrayBuffer())
  if (bytes.byteLength <= 0 || bytes.byteLength > 5 * 1024 * 1024) {
    throw new Error('BIGMAP TIFF size is invalid')
  }
  return {
    status: 'available',
    spcd,
    record,
    width: Number(exported?.width || width),
    height: Number(exported?.height || height),
    extent: exported?.extent || null,
    source_tiff_size_bytes: bytes.byteLength,
    source_tiff_sha256: await sha256Hex(bytes),
    source_tiff_base64: bytesToBase64(bytes),
  }
}


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
    if (operation === 'source_catalog') return json(await sourceCatalog())
    if (operation === 'source_export') return json(await sourceExport(body))
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
