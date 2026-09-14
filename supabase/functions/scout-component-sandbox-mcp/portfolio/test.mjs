import assert from 'node:assert/strict'
import {readFile} from 'node:fs/promises'
import {build} from 'esbuild'
const bundled=await build({entryPoints:['portfolio/frame.ts'],bundle:true,write:false,format:'esm'})
const {buildPortfolioFrame}=await import('data:text/javascript;base64,'+Buffer.from(bundled.outputFiles[0].text).toString('base64'))
const fixture=JSON.parse(await readFile('portfolio/warren_fixture.json','utf8'))
for(const width of [280,330,400,456]) {
 const frame=buildPortfolioFrame(fixture,width,210,'/tiles/{z}/{x}/{y}.png')
 assert.equal(frame.status,'ready');assert.deepEqual(frame.counts,{total:24,mapped:24,unresolved:0,omitted:0,documentedNotInService:2,membersWithHistoricalSignals:2})
 assert.equal(new Set(frame.markers.map(m=>m.id)).size,24)
 assert.ok(frame.markers.every(m=>m.left>=24-1e-6&&m.left<=width-24+1e-6&&m.top>=24-1e-6&&m.top<=186+1e-6))
 assert.ok(frame.tiles.length<=12)
 assert.deepEqual(frame,buildPortfolioFrame(fixture,width,210,'/tiles/{z}/{x}/{y}.png'))
 console.log(JSON.stringify({width,zoom:frame.zoom,tiles:frame.tiles.length,overlapPairs:frame.overlapPairs.length}))
}
for(const mutate of [p=>p.members.push(p.members[0]),p=>p.members[0].pwsid='wrong',p=>p.members[0].point={type:'Polygon',coordinates:[]},p=>p.members[0].point.coordinates[0]=NaN,p=>p.members[0].service_state='active',p=>p.relationship='owns',p=>p.members=Array(101).fill(p.members[0])]){
 const p=structuredClone(fixture);mutate(p);assert.throws(()=>buildPortfolioFrame(p,456,210,'/{z}/{x}/{y}'))
}
const unknown=structuredClone(fixture);unknown.members[0].point={type:'unresolved'};const f=buildPortfolioFrame(unknown,456,210,'/{z}/{x}/{y}');assert.equal(f.counts.unresolved,1);assert.equal(f.markers.length,23)
unknown.members.forEach(m=>m.point={type:'unresolved'});assert.equal(buildPortfolioFrame(unknown,456,210,'/{z}/{x}/{y}').status,'no_located_members')
console.log('Portfolio contract and regional framing checks passed')
