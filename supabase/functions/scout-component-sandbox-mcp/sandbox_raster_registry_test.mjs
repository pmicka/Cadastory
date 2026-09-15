import assert from 'node:assert/strict'
import { build } from 'esbuild'
import { makePortfolioPayload } from './sandbox_portfolio_test_fixtures.mjs'

const directory = new URL('./', import.meta.url)
async function bundleModule(path) {
  const result = await build({ entryPoints: [new URL(path, directory).pathname], bundle: true, format: 'esm', platform: 'node', target: 'node22', write: false })
  return await import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`)
}
const manifest = await bundleModule('../_shared/scout_sandbox_manifest.ts')
const runtime = await bundleModule('portfolio_registry.ts')
const {
  SCOUT_SANDBOX_PORTFOLIO_TYPES,
  SCOUT_SANDBOX_PORTFOLIO_MANIFEST,
  SCOUT_SANDBOX_MAX_EMBEDDED_RASTER_TILES,
  isScoutSandboxRasterTileAllowed,
} = manifest
const { SCOUT_SANDBOX_PORTFOLIO_IMPLEMENTATIONS } = runtime

const uniqueTiles = new Set()
for (const type of SCOUT_SANDBOX_PORTFOLIO_TYPES) {
  const manifestEntry = SCOUT_SANDBOX_PORTFOLIO_MANIFEST[type]
  const implementation = SCOUT_SANDBOX_PORTFOLIO_IMPLEMENTATIONS[type]
  const map = implementation.normalizeMap(makePortfolioPayload(type))
  assert.ok(map, `missing normalized raster fixture for ${type}`)
  assert.ok(manifestEntry.rasterFrames.length > 0, `${type} must register at least one bounded raster frame`)
  for (const frameSize of manifestEntry.rasterFrames) {
    const frame = implementation.buildRasterFrame(map, frameSize.width, frameSize.height, { tileUrlTemplate: 'https://sandbox.invalid/map-tile/{z}/{x}/{y}.png' })
    assert.ok(frame.tiles.length > 0, `${type} ${frameSize.width}x${frameSize.height} produced no raster tiles`)
    for (const tile of frame.tiles) {
      const key = `${tile.z}/${tile.x}/${tile.y}`
      assert.equal(isScoutSandboxRasterTileAllowed(tile.z, tile.x, tile.y), true, `${type} requires tile ${key} outside the registered bounded allowlist`)
      uniqueTiles.add(key)
    }
  }
}
assert.ok(uniqueTiles.size <= SCOUT_SANDBOX_MAX_EMBEDDED_RASTER_TILES, `registered portfolio fixtures require ${uniqueTiles.size} tiles, exceeding embedded ceiling ${SCOUT_SANDBOX_MAX_EMBEDDED_RASTER_TILES}`)
console.log(`Scout raster registry checks passed: ${uniqueTiles.size}/${SCOUT_SANDBOX_MAX_EMBEDDED_RASTER_TILES} unique portfolio tiles required.`)
