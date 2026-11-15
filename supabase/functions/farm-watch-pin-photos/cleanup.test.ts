import { cleanPinPhotos } from '../_shared/farm-watch-pin-photo-storage.ts'
const path='11111111-1111-1111-1111-111111111111/22222222-2222-2222-2222-222222222222/33333333-3333-3333-3333-333333333333.webp'
const assert=(x:unknown)=>{if(!x)throw Error('cleanup assertion failed')}
Deno.test('cleanup retains failed deletions; successful storage removal acknowledges only trusted queued paths',async()=>{
 const calls:any[]=[];let fail=true
 const admin={rpc:async(name:string,args:any)=>{calls.push(args);return {data:{paths:[path]}}},storage:{from:()=>({remove:async(paths:string[])=>{calls.push(paths);return {error:fail?'retry':null}}})}}
 await cleanPinPhotos(admin,path);assert(calls.length===2&&calls[0].p_queue_path===path)
 fail=false;await cleanPinPhotos(admin);assert(calls.length===5&&calls[4].p_ack_paths[0]===path)
})
Deno.test('malformed/oversized cleanup responses never become privileged deletion paths',async()=>{
 for(const paths of [['other-bucket/file'],Array(21).fill(path)]){
  let removed=false
  await cleanPinPhotos({rpc:async()=>({data:{paths}}),storage:{from:()=>({remove:()=>{removed=true}})}})
  assert(!removed)
 }
})
