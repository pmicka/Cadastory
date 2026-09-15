import assert from 'node:assert/strict'
import { build } from 'esbuild'
import { makePortfolioPayload } from './sandbox_portfolio_test_fixtures.mjs'
const directory=new URL('./',import.meta.url)
async function bundle(path){const result=await build({entryPoints:[new URL(path,directory).pathname],bundle:true,format:'esm',platform:'node',target:'node22',write:false});return await import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`)}
const model=await bundle('school_district_portfolio_map_model.ts'),renderer=await bundle('school_district_portfolio_map_renderer.ts')
const map=model.normalizeScoutSandboxSchoolDistrictPortfolioMap(makePortfolioPayload('school_district_portfolio'))
assert.ok(map)
assert.equal(map.member_count,6)
assert.deepEqual(map.bounds,{west:-85.781081,south:38.6503,east:-85.6264,north:38.7373})
const frame=renderer.buildScoutSchoolDistrictPortfolioRasterFrame(map,456,210,{tileUrlTemplate:'https://sandbox.invalid/map-tile/{z}/{x}/{y}.png'})
assert.equal(frame.zoom,10)
assert.equal(frame.markers.length,6)
assert.deepEqual(frame.tiles.map((tile)=>`${tile.z}/${tile.x}/${tile.y}`),['10/267/392','10/268/392','10/269/392'])
assert.equal(map.capital_signals[0].site_attribution,'district_only_unresolved')
const opportunity=model.buildScoutSandboxSchoolDistrictPortfolioOpportunity(map)
assert.equal(opportunity.roof_project_estimated_cost,500000)
assert.equal(opportunity.project_site_attribution,'district_only_unresolved')
console.log('Scout school-district portfolio renderer checks passed.')
