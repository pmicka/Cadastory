import assert from 'node:assert/strict'
import { build } from 'esbuild'
import { makePortfolioPayload } from './sandbox_portfolio_test_fixtures.mjs'

const directory = new URL('./', import.meta.url)
const registryBuild = await build({
  entryPoints: [new URL('portfolio_registry.ts', directory).pathname],
  bundle: true,
  format: 'esm',
  platform: 'node',
  target: 'node22',
  write: false,
})
const registryModule = await import(`data:text/javascript;base64,${Buffer.from(registryBuild.outputFiles[0].text).toString('base64')}`)
const manifestBuild = await build({
  entryPoints: [new URL('../_shared/scout_sandbox_manifest.ts', directory).pathname],
  bundle: true,
  format: 'esm',
  platform: 'node',
  target: 'node22',
  write: false,
})
const manifestModule = await import(`data:text/javascript;base64,${Buffer.from(manifestBuild.outputFiles[0].text).toString('base64')}`)
const { SCOUT_SANDBOX_PORTFOLIO_TYPES, SCOUT_SANDBOX_PORTFOLIO_MANIFEST } = manifestModule
const { SCOUT_SANDBOX_PORTFOLIO_IMPLEMENTATIONS, assertScoutSandboxPortfolioImplementationCoverage } = registryModule

assert.doesNotThrow(() => assertScoutSandboxPortfolioImplementationCoverage())

for (const type of SCOUT_SANDBOX_PORTFOLIO_TYPES) {
  const implementation = SCOUT_SANDBOX_PORTFOLIO_IMPLEMENTATIONS[type]
  assert.ok(implementation, `missing runtime implementation for ${type}`)

  const canonical = makePortfolioPayload(type)
  const normalized = implementation.normalizeMap(canonical)
  assert.ok(normalized, `${type} rejected its canonical payload`)
  assert.equal(normalized.opportunity_type, type)
  const opportunity = implementation.buildOpportunity(normalized)
  assert.ok(implementation.normalizeOpportunity(opportunity), `${type} rejected its canonical opportunity`)
  assert.equal(implementation.identityMatches(normalized, opportunity), true)

  if (SCOUT_SANDBOX_PORTFOLIO_MANIFEST[type].hostNormalization === 'unresolved_link_confidence_null_elision') {
    const explicitNull = structuredClone(canonical)
    const unresolved = explicitNull.members.find((member) => member.resolution_state === 'unresolved')
    assert.equal(unresolved.link_confidence, null, `${type} fixture must explicitly exercise nullable confidence`)
    assert.ok(implementation.normalizeMap(explicitNull), `${type} rejected explicit unresolved null confidence`)

    const hostElided = structuredClone(canonical)
    const hostUnresolved = hostElided.members.find((member) => member.resolution_state === 'unresolved')
    delete hostUnresolved.link_confidence
    const hostNormalized = implementation.normalizeMap(hostElided)
    assert.ok(hostNormalized, `${type} rejected host-elided unresolved confidence`)
    assert.equal(hostNormalized.members.find((member) => member.resolution_state === 'unresolved').link_confidence, null)

    const malformedResolved = structuredClone(canonical)
    const resolved = malformedResolved.members.find((member) => member.resolution_state !== 'unresolved')
    delete resolved.link_confidence
    assert.equal(implementation.normalizeMap(malformedResolved), null, `${type} accepted host-elided confidence on a resolved member`)
  }
}

console.log(`Scout generic portfolio contract checks passed for ${SCOUT_SANDBOX_PORTFOLIO_TYPES.join(', ')}.`)
