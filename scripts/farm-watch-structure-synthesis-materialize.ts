#!/usr/bin/env -S deno run --allow-env --allow-net

import { FARM_WATCH_GITHUB_OIDC_AUDIENCE } from '../supabase/functions/_shared/github-actions-oidc.ts'

const EDGE_URL =
  'https://ufpkjaadmmpmeogzhrcq.supabase.co/functions/v1/farm-watch-structure-synthesis-worker'

function arg(name: string, fallback: string | null = null) {
  const index = Deno.args.indexOf(name)
  if (index < 0) return fallback
  const value = Deno.args[index + 1]
  if (!value || value.startsWith('--')) throw new Error(name + ' requires a value')
  return value
}

async function oidcToken() {
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

const property = arg('--property', 'validation-property-01')!
const token = await oidcToken()
const response = await fetch(EDGE_URL, {
  method: 'POST',
  headers: {
    authorization: 'Bearer ' + token,
    'content-type': 'application/json',
    accept: 'application/json',
  },
  body: JSON.stringify({
    operation: 'materialize',
    property,
    product: 'structure-complementarity',
  }),
})
const payload = await response.json().catch(() => ({}))
if (!response.ok) {
  throw new Error(payload?.detail || payload?.error || ('worker returned ' + response.status))
}
console.log(JSON.stringify(payload, null, 2))
