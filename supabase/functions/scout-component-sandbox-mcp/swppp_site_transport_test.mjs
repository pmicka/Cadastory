import assert from 'node:assert/strict'
import {readFile} from 'node:fs/promises'
import {build} from 'esbuild'
const compiled=await build({entryPoints:['swppp_site_transport.ts'],bundle:true,write:false,format:'esm'})
const {buildScoutSwpppSiteTransport:encode,normalizeScoutSwpppSiteTransport:decode}=await import('data:text/javascript;base64,'+Buffer.from(compiled.outputFiles[0].text).toString('base64'))
const text=await readFile('swppp_site_map_renderer_test.mjs','utf8');const start=text.indexOf('const exemplar = ');const end=text.indexOf('\n}\n',start)+2;const map=Function(text.slice(start,end)+';return exemplar')()
const wire=encode(map);assert.deepEqual(decode(wire),map)
let cases=1
for(const field of ['termination_date','organization_id']) {const raw=structuredClone(map);delete raw[field==='termination_date'?'permit':'buyer'][field];assert.throws(()=>encode(raw));cases++}
for(const omitted of [0,1,2,3]) {const value=structuredClone(wire);if(omitted&1)delete value.permit.termination_date;if(omitted&2)delete value.buyer.organization_id;assert.deepEqual(decode(JSON.parse(JSON.stringify(value))),map);cases++}
for(const path of [['transport_contract'],['permit','termination_state'],['buyer','organization_resolution_state']])for(const replacement of [undefined,null,'',false,'wrong']){
 const value=structuredClone(wire);let obj=value;for(const k of path.slice(0,-1))obj=obj[k];obj[path.at(-1)]=replacement;delete value.permit.termination_date;delete value.buyer.organization_id;assert.equal(decode(value),null);cases++
}
for(const [group,key] of [['permit','termination_date'],['buyer','organization_id']])for(const replacement of ['',false,0,'2026-09-13',{},[]]){const value=structuredClone(wire);value[group][key]=replacement;assert.equal(decode(value),null);assert.throws(()=>encode(value));cases++}
for(const mutate of [v=>v.permit.status='TERMINATED',v=>v.buyer.classification='resolved',v=>v.site_point.geometry_type='Polygon',v=>v.candidate_key='wrong',v=>delete v.source]){const value=structuredClone(wire);mutate(value);assert.equal(decode(value),null);assert.throws(()=>encode(value));cases++}
assert.equal(decode(map),null)
assert.deepEqual(wire.permit.termination_date,null);assert.deepEqual(wire.buyer.organization_id,null)
console.log(`${cases+1} transport evidence/contradiction cases passed`)
