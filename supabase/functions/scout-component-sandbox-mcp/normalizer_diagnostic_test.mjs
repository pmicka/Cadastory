import assert from 'node:assert/strict'
import {execFileSync} from 'node:child_process'
import {readFile} from 'node:fs/promises'
import {transform} from 'esbuild'
const load=async text=>import('data:text/javascript;base64,'+Buffer.from((await transform(text,{loader:'ts',format:'esm'})).code).toString('base64'))
const prior=await load(execFileSync('git',['show','5b5f624: supabase/functions/scout-component-sandbox-mcp/swppp_site_map_model.ts'.replace(': ',':')],{encoding:'utf8'}))
const current=await load(await readFile('swppp_site_map_model.ts','utf8'))
const fixture=await readFile('swppp_site_map_renderer_test.mjs','utf8');const start=fixture.indexOf('const exemplar = ');const end=fixture.indexOf('\n}\n',start)+2;const exemplar=Function(fixture.slice(start,end)+';return exemplar')()
let count=0
function check(value){let detail;const result=current.normalizeScoutSandboxSwpppSiteMap(value,d=>detail=d);assert.deepEqual(result,prior.normalizeScoutSandboxSwpppSiteMap(value));if(!result)assert.ok(detail?.field);assert.deepEqual(current.normalizeScoutSandboxSwpppSiteMap(value,()=>{throw Error('observer')}),result);count++;return detail}
check(exemplar)
for(const v of [null,undefined,[],{},0,'private'])check(v)
const paths=[];function walk(obj,prefix=[]){for(const [k,v] of Object.entries(obj)){const path=[...prefix,k];paths.push(path);if(v&&typeof v==='object')walk(v,path)}}walk(exemplar)
for(const path of paths)for(const replacement of [undefined,null,[],{},0,-1,Infinity,true,'','PRIVATE_SENTINEL','x'.repeat(1001)]){
 const value=structuredClone(exemplar);let target=value;for(const k of path.slice(0,-1))target=target[k];target[path.at(-1)]=replacement
 const detail=check(value);assert.ok(!JSON.stringify(detail??{}).includes('PRIVATE_SENTINEL'))
}
for(const path of [['permit','termination_date'],['buyer','organization_id']]){
 const value=structuredClone(exemplar);delete value[path[0]][path[1]];const detail=check(value);assert.equal(detail.field,path.join('.'));assert.equal(detail.actualType,'undefined');assert.equal(detail.check,'null_required')
}
console.log(`${count} normalizer parity and bounded-report cases passed`)
