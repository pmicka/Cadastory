#!/usr/bin/env -S deno run --allow-env --allow-net

import {
  FARM_WATCH_SPATIAL_PATTERN_PRODUCT,
  FARM_WATCH_TERRAIN_FORM_PRODUCT,
} from '../supabase/functions/_shared/farm-watch-neutral-primitives-contract.ts'
import { FARM_WATCH_GITHUB_OIDC_AUDIENCE } from '../supabase/functions/_shared/github-actions-oidc.ts'

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
const requestedProduct = arg('--product', 'all')!
const products = requestedProduct === 'all'
  ? [FARM_WATCH_TERRAIN_FORM_PRODUCT.key, FARM_WATCH_SPATIAL_PATTERN_PRODUCT.key]
  : [requestedProduct]

for (const product of products) {
  if (
    product !== FARM_WATCH_TERRAIN_FORM_PRODUCT.key &&
    product !== FARM_WATCH_SPATIAL_PATTERN_PRODUCT.key
  ) throw new Error('unsupported neutral primitive product: ' + product)
}

async function freshOidcToken() {
  const requestUrl = Deno.env.get('ACTIONS_ID_TOKEN_REQUEST_URL') || ''
  const requestToken = Deno.env.get('ACTIONS_ID_TOKEN_REQUEST_TOKEN') || ''
  if (!requestUrl || !requestToken) throw new Error('GitHub Actions OIDC environment unavailable')
  const url = new URL(requestUrl)
  url.searchParams.set('audience', FARM_WATCH_GITHUB_OIDC_AUDIENCE)
  const response = await fetch(url, {
    headers: {
      authorization: 'Bearer ' + requestToken,
      accept: 'application/json',
    },
  })
  if (!response.ok) throw new Error('GitHub OIDC token request failed: ' + response.status)
  const payload = await response.json()
  if (!payload?.value) throw new Error('GitHub OIDC token response was empty')
  return String(payload.value)
}

async function build(product: string) {
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
      product,
      operation: 'build',
    }),
  })
  const payload = await response.json().catch(() => ({}))
  if (!response.ok) {
    throw new Error(
      product + ' materialization failed: ' +
      (payload?.detail || payload?.error || response.status),
    )
  }
  return payload
}

for (const product of products) {
  console.log('Materializing ' + product + ' for ' + propertySlug)
  const result = await build(product)
  console.log(JSON.stringify({
    product,
    status: result?.status || null,
    identity_sha256: result?.materialization?.identity_sha256 || result?.identity?.identity_sha256 || null,
    artifact_sha256: result?.materialization?.artifact_sha256 || null,
    summary: result?.materialization?.summary || null,
  }, null, 2))
}
