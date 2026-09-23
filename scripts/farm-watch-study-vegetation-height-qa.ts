#!/usr/bin/env -S deno run --allow-env --allow-net

import {
  buildLidarSourceArtifact,
  sha256Hex,
} from '../supabase/functions/_shared/farm-watch-lidar-source.ts'
import { FARM_WATCH_GITHUB_OIDC_AUDIENCE } from '../supabase/functions/_shared/github-actions-oidc.ts'
import {
  buildStudyAlignedVegetationHeightArtifactForGeometry,
  qaStudyAlignedVegetationHeightProfiles,
} from './farm-watch-lidar-physical-materialize.ts'

const EDGE_URL =
  'https://ufpkjaadmmpmeogzhrcq.supabase.co/functions/v1/farm-watch-study-vegetation-height-worker'

function arg(name: string, fallback: string | null = null) {
  const index = Deno.args.indexOf(name)
  if (index < 0) return fallback
  const value = Deno.args[index + 1]
  if (!value || value.startsWith('--')) throw new Error(name + ' requires a value')
  return value
}

const propertySlug = arg('--property', 'validation-property-01')!

async function freshOidcToken() {
  const requestUrl = Deno.env.get('ACTIONS_ID_TOKEN_REQUEST_URL') || ''
  const requestToken = Deno.env.get('ACTIONS_ID_TOKEN_REQUEST_TOKEN') || ''
  if (!requestUrl || !requestToken) throw new Error('GitHub Actions OIDC environment unavailable')
  const url = new URL(requestUrl)
  url.searchParams.set('audience', FARM_WATCH_GITHUB_OIDC_AUDIENCE)
  const response = await fetch(url, {
    headers: { authorization: 'Bearer ' + requestToken, accept: 'application/json' },
  })
  if (!response.ok) throw new Error('GitHub OIDC token request failed: ' + response.status)
  const payload = await response.json()
  if (!payload?.value) throw new Error('GitHub OIDC token response was empty')
  return String(payload.value)
}

async function workerRequest(body: any) {
  const token = await freshOidcToken()
  const response = await fetch(EDGE_URL, {
    method: 'POST',
    headers: {
      authorization: 'Bearer ' + token,
      'content-type': 'application/json',
      accept: 'application/json',
    },
    body: JSON.stringify({
      property: propertySlug,
      product: 'study-aligned-vegetation-height-context',
      ...body,
    }),
  })
  const payload = await response.json().catch(() => ({}))
  if (!response.ok) {
    throw new Error(payload?.detail || payload?.error || ('worker API returned ' + response.status))
  }
  return payload
}

async function main() {
  const context = await workerRequest({ operation: 'qa_context' })
  if (context?.status !== 'available') throw new Error('production QA context unavailable')

  const domain = context.analysis_domain_geojson
  const propertyBoundary = context.property_boundary_geojson
  const production = context.production_materialization
  if (!domain || !propertyBoundary || !production?.artifact_sha256) {
    throw new Error('production QA context is incomplete')
  }

  console.log('Resolving Phase 3 LiDAR coverage for production QA domain')
  const sourceBuild = await buildLidarSourceArtifact(
    domain,
    fetch,
    [String(context.contract.source_collection)],
  )
  const sourcePlan = sourceBuild.artifact
  const phase3 = sourcePlan.collections?.find(
    (row: any) => row?.id === String(context.contract.source_collection),
  )
  const coveragePercent = Number(
    phase3?.coverage?.sampled_analysis_coverage_percent ??
    phase3?.coverage?.sampled_parcel_coverage_percent
  )
  if (
    phase3?.coverage?.coverage_status !== 'complete_sampled' ||
    !Number.isFinite(coveragePercent) ||
    coveragePercent < 99.5 ||
    !Array.isArray(phase3?.processing_items) ||
    !phase3.processing_items.length
  ) {
    throw new Error('Phase 3 LiDAR coverage is incomplete for QA domain')
  }

  const sourcePlanArtifactSha256 = await sha256Hex(JSON.stringify(sourcePlan))
  console.log('Rebuilding production vegetation-height artifact for checksum match')
  const artifact = await buildStudyAlignedVegetationHeightArtifactForGeometry({
    analysisGeometry: domain,
    propertyBoundary,
    sourceItems: phase3.processing_items,
    contract: context.contract,
    sourcePlanArtifactSha256,
    landscapeDomainIdentity: context.landscape_domain_identity,
  })

  const artifactBytes = new TextEncoder().encode(JSON.stringify(artifact))
  const rebuiltArtifactSha256 = await sha256Hex(artifactBytes)
  const rebuiltArtifactSizeBytes = artifactBytes.byteLength
  if (rebuiltArtifactSha256 !== String(production.artifact_sha256)) {
    throw new Error(
      'QA deterministic rebuild hash mismatch: production=' +
        production.artifact_sha256 + ' rebuilt=' + rebuiltArtifactSha256,
    )
  }
  if (rebuiltArtifactSizeBytes !== Number(production.artifact_size_bytes)) {
    throw new Error(
      'QA deterministic rebuild size mismatch: production=' +
        production.artifact_size_bytes + ' rebuilt=' + rebuiltArtifactSizeBytes,
    )
  }

  console.log('Running raw COPC point/profile QA for representative and negative-outlier cells')
  const qa = await qaStudyAlignedVegetationHeightProfiles({
    artifact,
    analysisGeometry: domain,
    propertyBoundary,
    sourceItems: phase3.processing_items,
    representativePerClass: 3,
    negativeOutlierCount: 10,
  })

  console.log(JSON.stringify({
    status: 'qa_complete',
    property: propertySlug,
    production_materialization: production,
    deterministic_rebuild: {
      artifact_sha256: rebuiltArtifactSha256,
      artifact_size_bytes: rebuiltArtifactSizeBytes,
      hash_matches_production: true,
      size_matches_production: true,
      sampled_domain_coverage_percent: coveragePercent,
      processing_item_ids: artifact.processing_item_ids,
    },
    qa,
  }, null, 2))
}

if (import.meta.main) await main()
