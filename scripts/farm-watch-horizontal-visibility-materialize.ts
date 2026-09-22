#!/usr/bin/env -S deno run --allow-env --allow-net

import { FARM_WATCH_GITHUB_OIDC_AUDIENCE } from '../supabase/functions/_shared/github-actions-oidc.ts'
import { FARM_WATCH_HORIZONTAL_VISIBILITY_PRODUCT } from '../supabase/functions/_shared/farm-watch-horizontal-visibility-contract.ts'

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
    operation: 'build',
  }),
})
const payload = await response.json().catch(() => ({}))
if (!response.ok) {
  throw new Error(
    FARM_WATCH_HORIZONTAL_VISIBILITY_PRODUCT.key + ' materialization failed: ' +
      (payload?.detail || payload?.error || response.status),
  )
}
console.log(JSON.stringify({
  product: FARM_WATCH_HORIZONTAL_VISIBILITY_PRODUCT.key,
  status: payload?.status || null,
  identity_sha256: payload?.materialization?.identity_sha256 || payload?.identity?.identity_sha256 || null,
  artifact_sha256: payload?.materialization?.artifact_sha256 || null,
  summary: payload?.materialization?.summary || null,
}, null, 2))
