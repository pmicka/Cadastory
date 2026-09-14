import {build} from 'esbuild'
import assert from 'node:assert/strict'
import {readFile} from 'node:fs/promises'
const load=async file=>{const b=await build({entryPoints:[file],bundle:true,write:false,format:'esm'});return import('data:text/javascript;base64,'+Buffer.from(b.outputFiles[0].text).toString('base64'))}
const {createPortfolioSelection}=await load('portfolio/selection.ts')
const {loadWarrenPortfolio}=await load('portfolio/backend.ts')
const data=JSON.parse(await readFile('portfolio/warren_fixture.json','utf8')),before=JSON.stringify(data)
const selection=createPortfolioSelection(data)
for(const member of data.members){selection.select(member.id);assert.equal(selection.snapshot().member.id,member.id);assert.ok(selection.snapshot().description.includes(member.name))}
assert.throws(()=>selection.select('not-a-member'));selection.select('');assert.equal(selection.snapshot().member,undefined);assert.equal(JSON.stringify(data),before)
let called;const result=await loadWarrenPortfolio({rpc:async name=>{called=name;return {data,error:null}}});assert.equal(called,'scout_get_component_sandbox_water_portfolio_v1_internal');assert.equal(result.members.length,24)
await assert.rejects(()=>loadWarrenPortfolio({rpc:async()=>({data,error:{message:'private'}})}),/Portfolio roster unavailable/)
await assert.rejects(()=>loadWarrenPortfolio({rpc:async()=>({data:{...data,pwsid:'wrong'},error:null})}),/failed validation/)
console.log('24 member selections, overview, identity isolation, and bounded backend loader passed')
