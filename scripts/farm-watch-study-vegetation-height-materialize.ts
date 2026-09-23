#!/usr/bin/env -S deno run --allow-env --allow-net

import {
  buildLidarSourceArtifact,
  sha256Hex,
} from '../supabase/functions/_shared/farm-watch-lidar-source.ts'
import { FARM_WATCH_GITHUB_OIDC_AUDIENCE } from '../supabase/functions/_shared/github-actions-oidc.ts'
import {
  buildStudyAlignedVegetationHeightArtifactForGeometry,
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
  const claim = await workerRequest({ operation: 'claim' })
  if (claim?.action === 'reuse') {
    console.log(JSON.stringify({ status: 'reused', build: claim.build || null }, null, 2))
    return
  }
  if (claim?.action !== 'build') {
    console.log(JSON.stringify({
      status: claim?.action || 'not_claimed',
      build: claim.build || null,
    }, null, 2))
    return
  }

  const buildId = String(claim.build_id)
  const leaseToken = String(claim.lease_token)

  try {
    const domain = claim.analysis_domain_geojson
    const propertyBoundary = claim.property_boundary_geojson
    if (!domain || !propertyBoundary) {
      throw new Error('analysis or property geometry unavailable')
    }

    console.log('Resolving Phase 3 LiDAR coverage for barrier-aware local_500m domain')
    const sourceBuild = await buildLidarSourceArtifact(
      domain,
      fetch,
      [String(claim.contract.source_collection)],
    )
    const sourcePlan = sourceBuild.artifact
    const phase3 = sourcePlan.collections?.find(
      (row: any) => row?.id === String(claim.contract.source_collection),
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
      throw new Error('Phase 3 LiDAR coverage is incomplete for local_500m domain')
    }

    const sourcePlanArtifactSha256 = await sha256Hex(JSON.stringify(sourcePlan))
    console.log('Building study-aligned 1.2 m first-return minus ground vegetation height')
    const artifact = await buildStudyAlignedVegetationHeightArtifactForGeometry({
      analysisGeometry: domain,
      propertyBoundary,
      sourceItems: phase3.processing_items,
      contract: claim.contract,
      sourcePlanArtifactSha256,
      landscapeDomainIdentity: claim.landscape_domain_identity,
    })

    const completion = await workerRequest({
      operation: 'complete',
      build_id: buildId,
      lease_token: leaseToken,
      artifact,
    })

    console.log(JSON.stringify({
      status: 'available',
      property: propertySlug,
      domain_identity_sha256: artifact.domain.identity_sha256,
      processing_item_ids: artifact.processing_item_ids,
      sampled_domain_coverage_percent: coveragePercent,
      study_alignment: artifact.study_alignment,
      summary: artifact.summary,
      processing_summary: artifact.processing_summary,
      completion,
    }, null, 2))
  } catch (error) {
    try {
      await workerRequest({
        operation: 'fail',
        build_id: buildId,
        lease_token: leaseToken,
        error: error instanceof Error ? error.stack || error.message : String(error),
      })
    } catch (failError) {
      console.error('Failed to report study vegetation-height worker failure:', failError)
    }
    throw error
  }
}

if (import.meta.main) await main()
