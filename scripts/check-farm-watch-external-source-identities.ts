import {
  appendFarmWatchExternalIdentitySignature,
  FARM_WATCH_EXTERNAL_DEPENDENCY_KEYS,
  farmWatchExternalIdentityOverrides,
  farmWatchExternalIdentitySignatureKey,
  resolveFarmWatchExternalSourceIdentities,
} from '../supabase/functions/_shared/farm-watch-external-source-identity.ts'

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message)
}

const fakeA = 'a'.repeat(64)
const fakeB = 'b'.repeat(64)
const signature = appendFarmWatchExternalIdentitySignature(
  'product=test',
  [
    {
      key: 'external:kyfromabove-phase3-dem',
      status: 'available',
      authoritative: true,
      resolution_status: 'synthetic',
      identity_sha256: fakeB,
      observed_at: '2026-09-29T00:00:00Z',
      evidence: {},
    },
    {
      key: 'external:kyfromabove-lidar-stac',
      status: 'available',
      authoritative: true,
      resolution_status: 'synthetic',
      identity_sha256: fakeA,
      observed_at: '2026-09-29T00:00:00Z',
      evidence: {},
    },
  ],
)
assert(
  signature ===
    'product=test|' +
    farmWatchExternalIdentitySignatureKey('external:kyfromabove-lidar-stac') + '=' + fakeA + '|' +
    farmWatchExternalIdentitySignatureKey('external:kyfromabove-phase3-dem') + '=' + fakeB,
  'external identity source-signature binding is not canonical',
)

const overrides = farmWatchExternalIdentityOverrides([
  {
    key: 'external:kyfromabove-phase3-dem',
    status: 'available',
    authoritative: true,
    resolution_status: 'synthetic',
    identity_sha256: fakeA,
    observed_at: '2026-09-29T00:00:00Z',
    evidence: {},
  },
])
assert(
  overrides['external:kyfromabove-phase3-dem']?.identity_sha256 === fakeA,
  'external identity override is missing',
)

assert(
  FARM_WATCH_EXTERNAL_DEPENDENCY_KEYS.length === 8 &&
  new Set(FARM_WATCH_EXTERNAL_DEPENDENCY_KEYS).size === 8,
  'external dependency resolver must cover exactly eight unique P0.2 slots',
)

if (Deno.args.includes('--live')) {
  // Bounded validation geometry covering the Flat Creek validation-property area.
  // The resolver itself expands only as required by each product contract.
  const boundary = {
    type: 'Polygon',
    coordinates: [[
      [-84.8920, 38.3100],
      [-84.8720, 38.3100],
      [-84.8720, 38.3280],
      [-84.8920, 38.3280],
      [-84.8920, 38.3100],
    ]],
  }

  const first = await resolveFarmWatchExternalSourceIdentities({
    boundary,
    dependencyKeys: [...FARM_WATCH_EXTERNAL_DEPENDENCY_KEYS],
    requireAll: false,
  })
  const unavailable = first.filter((row) => row.status !== 'available')
  if (unavailable.length) {
    throw new Error(
      'live external identity resolution failed: ' +
      unavailable.map((row) => row.key + '=' + (row.error || row.status)).join('; '),
    )
  }
  for (const row of first) {
    assert(row.authoritative === true, row.key + ' did not resolve authoritatively')
    assert(
      /^[0-9a-f]{64}$/.test(String(row.identity_sha256 || '')),
      row.key + ' returned an invalid identity',
    )
    assert(
      row.resolution_status !== 'contract_only',
      row.key + ' unexpectedly fell back to contract-only identity',
    )
  }

  // A second bounded observation must be stable when providers did not change
  // between the two probes. observed_at is intentionally excluded from identity.
  const second = await resolveFarmWatchExternalSourceIdentities({
    boundary,
    dependencyKeys: [...FARM_WATCH_EXTERNAL_DEPENDENCY_KEYS],
    requireAll: false,
  })
  const firstByKey = new Map(first.map((row) => [row.key, row]))
  for (const row of second) {
    const before = firstByKey.get(row.key)
    assert(before, 'second observation returned an unexpected source: ' + row.key)
    assert(row.status === 'available', 'second observation unavailable: ' + row.key)
    assert(
      row.identity_sha256 === before.identity_sha256,
      row.key + ' provider identity changed between immediate probes',
    )
  }

  console.log(JSON.stringify({
    status: 'passed',
    source_count: first.length,
    sources: first.map((row) => ({
      key: row.key,
      resolution_status: row.resolution_status,
      identity_sha256: row.identity_sha256,
    })),
  }, null, 2))
} else {
  console.log('Farm Watch external source identity invariants passed')
}
