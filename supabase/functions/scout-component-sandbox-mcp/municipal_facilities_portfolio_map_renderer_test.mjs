
import assert from 'node:assert/strict'
import{build}from'esbuild'
import{makePortfolioPayload}from'./sandbox_portfolio_test_fixtures.mjs'
const directory=new URL('./',import.meta.url)
async function bundle(path){const result=await build({entryPoints:[new URL(path,directory).pathname],bundle:true,format:'esm',platform:'node',target:'node22',write:false});return await import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`)}
const model=await bundle('municipal_facilities_portfolio_map_model.ts'),renderer=await bundle('municipal_facilities_portfolio_map_renderer.ts')
const map=model.normalizeScoutSandboxMunicipalFacilitiesPortfolioMap(makePortfolioPayload('municipal_facilities_portfolio'))
assert.ok(map)
assert.equal(map.member_count,6)
assert.equal(map.signaled_member_count,1)
assert.deepEqual(map.bounds,{west:-85.7740749981969,south:38.2214560226262,east:-85.7465172343292,north:38.2546422629059})
const frame=renderer.buildScoutMunicipalFacilitiesPortfolioRasterFrame(map,456,210,{tileUrlTemplate:'https://sandbox.invalid/map-tile/{z}/{x}/{y}.png'})
assert.equal(frame.zoom,12)
assert.equal(frame.markers.length,6)
assert.deepEqual(frame.tiles.map(tile=>`${tile.z}/${tile.x}/${tile.y}`),['12/1071/1576','12/1072/1576','12/1073/1576'])
assert.equal(frame.markers.filter(marker=>marker.signalState==='site_signal_present').length,1)
assert.equal(map.member_signals[0].site_attribution,'judicial_center_only')
const opportunity=model.buildScoutSandboxMunicipalFacilitiesPortfolioOpportunity(map)
assert.equal(opportunity.signaled_member_name,'Judicial Center')
assert.equal(opportunity.signal_confidence,0.52)
console.log('Scout municipal-facilities portfolio renderer checks passed.')
