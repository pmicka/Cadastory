const GITHUB_OIDC_ISSUER = 'https://token.actions.githubusercontent.com'
export const FARM_WATCH_GITHUB_OIDC_AUDIENCE =
  'https://ufpkjaadmmpmeogzhrcq.supabase.co/farm-watch-materialization-worker'

const TRUST = Object.freeze({
  repository: 'pmicka/Cadastory',
  repositoryId: '1359671390',
  repositoryOwner: 'pmicka',
  repositoryOwnerId: '30001949',
  actor: 'pmicka',
  actorId: '30001949',
  ref: 'refs/heads/main',
  eventName: 'issues',
  workflowRefs: [
    'pmicka/Cadastory/.github/workflows/farm-watch-lidar-physical.yml@refs/heads/main',
    'pmicka/Cadastory/.github/workflows/farm-watch-leaf-off.yml@refs/heads/main',
    'pmicka/Cadastory/.github/workflows/farm-watch-structure-synthesis.yml@refs/heads/main',
    'pmicka/Cadastory/.github/workflows/farm-watch-landscape-structure.yml@refs/heads/main',
    'pmicka/Cadastory/.github/workflows/farm-watch-neutral-primitives.yml@refs/heads/main',
    'pmicka/Cadastory/.github/workflows/farm-watch-hls-field-observations.yml@refs/heads/main',
    'pmicka/Cadastory/.github/workflows/farm-watch-mast-capacity.yml@refs/heads/main',
    'pmicka/Cadastory/.github/workflows/farm-watch-mast-capacity.yml@refs/heads/main',
  ],
})

let jwksPromise: Promise<any> | null = null

function base64UrlBytes(value: string) {
  const padded = value.replace(/-/g, '+').replace(/_/g, '/')
    .padEnd(Math.ceil(value.length / 4) * 4, '=')
  const decoded = atob(padded)
  return Uint8Array.from(decoded, (char) => char.charCodeAt(0))
}

function base64UrlJson(value: string) {
  return JSON.parse(new TextDecoder().decode(base64UrlBytes(value)))
}

async function githubJwks() {
  if (!jwksPromise) {
    jwksPromise = (async () => {
      const discoveryResponse = await fetch(
        GITHUB_OIDC_ISSUER + '/.well-known/openid-configuration',
        { headers: { accept: 'application/json' } },
      )
      if (!discoveryResponse.ok) {
        throw new Error('GitHub OIDC discovery unavailable')
      }
      const discovery = await discoveryResponse.json()
      if (
        discovery?.issuer !== GITHUB_OIDC_ISSUER ||
        typeof discovery?.jwks_uri !== 'string' ||
        !discovery.jwks_uri.startsWith(GITHUB_OIDC_ISSUER + '/')
      ) {
        throw new Error('GitHub OIDC discovery response is incompatible')
      }

      const jwksResponse = await fetch(discovery.jwks_uri, {
        headers: { accept: 'application/json' },
      })
      if (!jwksResponse.ok) throw new Error('GitHub OIDC JWKS unavailable')
      const jwks = await jwksResponse.json()
      if (!Array.isArray(jwks?.keys)) throw new Error('GitHub OIDC JWKS is invalid')
      return jwks
    })().catch((error) => {
      jwksPromise = null
      throw error
    })
  }
  return await jwksPromise
}

function claimString(claims: any, key: string) {
  const value = claims?.[key]
  return typeof value === 'string' ? value : ''
}

function audienceMatches(value: unknown) {
  if (typeof value === 'string') return value === FARM_WATCH_GITHUB_OIDC_AUDIENCE
  return Array.isArray(value) && value.includes(FARM_WATCH_GITHUB_OIDC_AUDIENCE)
}

export async function verifyFarmWatchGitHubActionsOidc(token: string) {
  const parts = String(token || '').split('.')
  if (parts.length !== 3) throw new Error('invalid GitHub OIDC token')

  const header = base64UrlJson(parts[0])
  const claims = base64UrlJson(parts[1])
  if (header?.alg !== 'RS256' || typeof header?.kid !== 'string') {
    throw new Error('unsupported GitHub OIDC signing metadata')
  }

  const jwks = await githubJwks()
  const jwk = jwks.keys.find((key: any) =>
    key?.kid === header.kid &&
    key?.kty === 'RSA' &&
    (!key?.use || key.use === 'sig') &&
    (!key?.alg || key.alg === 'RS256')
  )
  if (!jwk) throw new Error('GitHub OIDC signing key unavailable')

  const key = await crypto.subtle.importKey(
    'jwk',
    jwk,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['verify'],
  )
  const validSignature = await crypto.subtle.verify(
    'RSASSA-PKCS1-v1_5',
    key,
    base64UrlBytes(parts[2]),
    new TextEncoder().encode(parts[0] + '.' + parts[1]),
  )
  if (!validSignature) throw new Error('invalid GitHub OIDC signature')

  const now = Math.floor(Date.now() / 1000)
  const skew = 60
  if (claimString(claims, 'iss') !== GITHUB_OIDC_ISSUER) throw new Error('invalid GitHub OIDC issuer')
  if (!audienceMatches(claims?.aud)) throw new Error('invalid GitHub OIDC audience')
  if (!Number.isFinite(Number(claims?.exp)) || Number(claims.exp) < now - skew) {
    throw new Error('expired GitHub OIDC token')
  }
  if (Number.isFinite(Number(claims?.nbf)) && Number(claims.nbf) > now + skew) {
    throw new Error('GitHub OIDC token is not active')
  }
  if (Number.isFinite(Number(claims?.iat)) && Number(claims.iat) > now + skew) {
    throw new Error('invalid GitHub OIDC issued-at time')
  }

  const required = [
    ['repository', TRUST.repository],
    ['repository_id', TRUST.repositoryId],
    ['repository_owner', TRUST.repositoryOwner],
    ['repository_owner_id', TRUST.repositoryOwnerId],
    ['actor', TRUST.actor],
    ['actor_id', TRUST.actorId],
    ['ref', TRUST.ref],
    ['event_name', TRUST.eventName],
  ]
  for (const [keyName, expected] of required) {
    if (claimString(claims, keyName) !== expected) {
      throw new Error('untrusted GitHub OIDC claim: ' + keyName)
    }
  }
  if (!TRUST.workflowRefs.includes(claimString(claims, 'workflow_ref'))) {
    throw new Error('untrusted GitHub OIDC claim: workflow_ref')
  }

  return {
    repository: claims.repository,
    actor: claims.actor,
    run_id: claimString(claims, 'run_id'),
    run_attempt: claimString(claims, 'run_attempt'),
    workflow_ref: claims.workflow_ref,
    workflow_sha: claimString(claims, 'workflow_sha'),
    jti: claimString(claims, 'jti'),
  }
}
