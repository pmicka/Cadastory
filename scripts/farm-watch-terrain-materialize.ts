#!/usr/bin/env -S deno run --allow-env --allow-net

import { createClient } from 'npm:@supabase/supabase-js@2.115.0'
import {
  FARM_WATCH_TERRAIN_LIMITATIONS,
  FARM_WATCH_TERRAIN_PRODUCT,
  FARM_WATCH_TERRAIN_SOURCE_SIGNATURE,
  terrainArtifactPath,
} from '../supabase/functions/_shared/farm-watch-terrain-contract.ts'
import {
  buildTerrainArtifact,
  sha256Hex,
} from '../supabase/functions/_shared/farm-watch-terrain.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SERVICE_KEY =
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ||
  (() => {
    try {
      return JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') || '{}')?.default || ''
    } catch {
      return ''
    }
  })()

if (!SUPABASE_URL || !SERVICE_KEY) {
  throw new Error('SUPABASE_URL and a Farm Watch service credential are required')
}

const admin = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
})

function arg(name: string, fallback: string | null = null) {
  const index = Deno.args.indexOf(name)
  if (index < 0) return fallback
  const value = Deno.args[index + 1]
  if (!value || value.startsWith('--')) throw new Error(`${name} requires a value`)
  return value
}

const propertySlug = arg('--property', 'validation-property-01')!
const workerId = arg('--worker', `terrain-import:${Deno.hostname?.() || 'local'}:${Deno.pid}`)!
const leaseSeconds = Number(arg('--lease-seconds', '900'))
if (!Number.isInteger(leaseSeconds) || leaseSeconds < 60 || leaseSeconds > 3600) {
  throw new Error('--lease-seconds must be an integer from 60 to 3600')
}

async function failBuild(buildId: string, leaseToken: string, error: unknown) {
  const message = error instanceof Error ? error.message : String(error)
  const { error: failError } = await admin.rpc('farm_watch_fail_materialization_build_v1_internal', {
    p_build_id: buildId,
    p_lease_token: leaseToken,
    p_error: message,
    p_retry_delay_seconds: 300,
  })
  if (failError) console.error('Failed to record build failure:', failError.message)
}

const { data: claim, error: claimError } = await admin.rpc(
  'farm_watch_claim_materialization_build_v1_internal',
  {
    p_slug: propertySlug,
    p_product_kind: FARM_WATCH_TERRAIN_PRODUCT.productKind,
    p_algorithm_version: FARM_WATCH_TERRAIN_PRODUCT.algorithmVersion,
    p_output_schema_version: FARM_WATCH_TERRAIN_PRODUCT.outputSchemaVersion,
    p_source_signature: FARM_WATCH_TERRAIN_SOURCE_SIGNATURE,
    p_worker_id: workerId,
    p_lease_seconds: leaseSeconds,
  },
)
if (claimError) throw new Error(`terrain build claim failed: ${claimError.message}`)

if (claim?.action === 'reuse') {
  console.log(JSON.stringify({
    status: 'reused',
    property: propertySlug,
    materialization_id: claim.materialization_id,
    artifact_sha256: claim.artifact_sha256,
  }, null, 2))
  Deno.exit(0)
}

if (claim?.action !== 'build') {
  console.log(JSON.stringify({
    status: claim?.action || 'not_claimed',
    property: propertySlug,
    build_id: claim?.build_id || null,
    retry_at: claim?.next_attempt_at || claim?.lease_expires_at || null,
    attempt_count: claim?.attempt_count ?? null,
  }, null, 2))
  Deno.exit(claim?.action === 'busy' || claim?.action === 'retry_later' ? 0 : 2)
}

const buildId = String(claim.build_id)
const leaseToken = String(claim.lease_token)
const propertyId = String(claim.property_id)
const inputSignature = String(claim.input_signature_sha256)
const boundary = claim.boundary_geojson
const statedAcres = claim.stated_acres == null ? null : Number(claim.stated_acres)

try {
  const startedAt = performance.now()
  const { artifact, sampledSourceSha256 } = await buildTerrainArtifact(boundary, statedAcres)
  const artifactJson = JSON.stringify(artifact)
  const artifactBytes = new TextEncoder().encode(artifactJson)
  const artifactSha256 = await sha256Hex(artifactBytes)
  const artifactPath = terrainArtifactPath(propertyId, inputSignature, artifactSha256)

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

  const { data: completed, error: completeError } = await admin.rpc(
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
  if (completeError) throw new Error(`terrain build completion failed: ${completeError.message}`)

  console.log(JSON.stringify({
    status: 'available',
    property: propertySlug,
    build_id: buildId,
    materialization_id: completed?.materialization_id || null,
    identity_sha256: completed?.identity_sha256 || null,
    artifact_sha256: artifactSha256,
    artifact_path: artifactPath,
    sampled_source_sha256: sampledSourceSha256,
    summary,
  }, null, 2))
} catch (error) {
  await failBuild(buildId, leaseToken, error)
  throw error
}
