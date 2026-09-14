import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { build } from 'esbuild'
const load=async file=>{const b=await build({entryPoints:[file],bundle:true,write:false,format:'esm'});return import('data:text/javascript;base64,'+Buffer.from(b.outputFiles[0].text).toString('base64'))}
const {requiredPortfolioTiles,validatePortfolioTiles,MAX_TILE_BYTES}=await load('portfolio/raster.ts')
const {prepareWarrenResource}=await load('portfolio/resource.ts')
const {buildPortfolioResult,normalizePortfolioResult}=await load('portfolio/result.ts')
const data=JSON.parse(await readFile('portfolio/warren_fixture.json','utf8'))
const required=requiredPortfolioTiles(data);assert.equal(required.length,6)
// Header fixture for transport validation; actual image decoding is covered by browser_test.
const bytes=new Uint8Array(33);bytes.set([137,80,78,71,13,10,26,10,0,0,0,13,73,72,68,82]);const view=new DataView(bytes.buffer);view.setUint32(16,256);view.setUint32(20,256)
const entries=required.map(t=>({url:t.url,data_url:'data:image/png;base64,'+Buffer.from(bytes).toString('base64')}))
assert.equal(validatePortfolioTiles(data,entries).size,6)
for(const bad of [entries.slice(1),[...entries,entries[0]],entries.map((e,i)=>i?e:{...e,url:'https://other.invalid/'}),entries.map((e,i)=>i?e:{...e,data_url:'data:image/png;base64,broken'})])assert.throws(()=>validatePortfolioTiles(data,bad))
const result=buildPortfolioResult(data);assert.ok(normalizePortfolioResult(result));assert.equal(normalizePortfolioResult({...result,opportunity:{...result.opportunity,organization_id:'other'}}),null)
const db={rpc:async()=>({data,error:null})},calls=[]
const prepared=await prepareWarrenResource(db,'<script>__SCOUT_EMBEDDED_RASTER_TILES__</script>',async(url,options)=>{calls.push(url);assert.equal(options.redirect,'error');assert.ok(options.signal);return new Response(bytes,{headers:{'content-type':'image/png'}})})
assert.equal(calls.length,6);assert.ok(calls.every(url=>/^https:\/\/a.tile.openstreetmap.fr\/hot\/9\/\d+\/\d+.png$/.test(url)))
assert.ok(!prepared.html.includes('__SCOUT_EMBEDDED'));assert.equal(prepared.portfolio.members.length,24)
for(const response of [()=>new Response('bad',{status:503}),()=>new Response(bytes,{headers:{'content-type':'image/jpeg'}}),()=>new Response(new Uint8Array(MAX_TILE_BYTES+1),{headers:{'content-type':'image/png'}})])await assert.rejects(()=>prepareWarrenResource(db,'__SCOUT_EMBEDDED_RASTER_TILES__',async()=>response()))
console.log('Portfolio raster coverage, identity, fixed-origin delivery, size and response rejection passed')
