#!/usr/bin/env -S deno run --allow-env --allow-net

import { FARM_WATCH_GITHUB_OIDC_AUDIENCE } from '../supabase/functions/_shared/github-actions-oidc.ts'
import {
  FARM_WATCH_HORIZONTAL_VISIBILITY_PRODUCT,
} from '../supabase/functions/_shared/farm-watch-horizontal-visibility-contract.ts'
import { buildHorizontalVisibilityArtifact } from '../supabase/functions/_shared/farm-watch-horizontal-visibility.ts'

const EDGE_URL =
  'https://ufpkjaadmmpmeogzhrcq.supabase.co/functions/v1/farm-watch-materialization'

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

async function workerRequest(body: Record<string, unknown>) {
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
      product: FARM_WATCH_HORIZONTAL_VISIBILITY_PRODUCT.key,
      ...body,
    }),
  })
  const payload = await response.json().catch(() => ({}))
  if (!response.ok) {
    throw new Error(
      FARM_WATCH_HORIZONTAL_VISIBILITY_PRODUCT.key + ' materialization failed: ' +
        (payload?.detail || payload?.error || response.status),
    )
  }
  return payload
}

const prepared = await workerRequest({ operation: 'prepare' })
if (prepared?.action === 'reuse') {
  console.log(JSON.stringify({
    product: FARM_WATCH_HORIZONTAL_VISIBILITY_PRODUCT.key,
    status: 'reused',
    identity_sha256: prepared?.materialization?.materialization?.identity_sha256 || null,
    artifact_sha256: prepared?.materialization?.materialization?.artifact_sha256 || null,
    summary: prepared?.materialization?.materialization?.summary || null,
  }, null, 2))
  Deno.exit(0)
}
if (prepared?.action !== 'build') {
  throw new Error('horizontal visibility worker did not claim a build: ' + (prepared?.action || 'unknown'))
}

try {
  const dependencies = prepared.dependencies
  const built = await buildHorizontalVisibilityArtifact({
    landscapeStructureArtifact: dependencies.landscape_structure_artifact,
    terrainFormArtifact: dependencies.terrain_form_artifact,
    landscapeDomainIdentitySha256: dependencies.landscape_domain_identity_sha256,
    landscapeStructureIdentitySha256: dependencies.landscape_structure_identity_sha256,
    landscapeStructureArtifactSha256: dependencies.landscape_structure_artifact_sha256,
    terrainFormIdentitySha256: dependencies.terrain_form_identity_sha256,
    terrainFormArtifactSha256: dependencies.terrain_form_artifact_sha256,
    sourceSignature: prepared.source_signature,
  })
  const completed = await workerRequest({
    operation: 'complete',
    build_id: prepared.build_id,
    lease_token: prepared.lease_token,
    sampled_source_sha256: built.sampledSourceSha256,
    artifact: built.artifact,
  })
  const materialization = completed?.materialization || {}
  console.log(JSON.stringify({
    product: FARM_WATCH_HORIZONTAL_VISIBILITY_PRODUCT.key,
    status: completed?.status || null,
    identity_sha256: materialization.identity_sha256 || null,
    artifact_sha256: materialization.artifact_sha256 || null,
    summary: materialization.summary || null,
  }, null, 2))
} catch (error) {
  try {
    await workerRequest({
      operation: 'fail',
      build_id: prepared.build_id,
      lease_token: prepared.lease_token,
      error: error instanceof Error ? error.message : String(error),
    })
  } catch (failureError) {
    console.error('horizontal visibility failure persistence failed', failureError)
  }
  throw error
}
