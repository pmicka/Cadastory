import { createPinPhotosHandler } from './handler.ts'
const assert=(value:unknown,message='assertion failed')=>{if(!value)throw Error(message)}
const pin='11111111-1111-1111-1111-111111111111',photo='22222222-2222-2222-2222-222222222222'
function fixture(options:any={}) {
 const calls:any[]=[],storage:any[]=[],blob=new Blob([new Uint8Array([82,73,70,70])],{type:'image/webp'})
 const admin={rpc:async(name:string,args:any)=>{storage.push({name,args});return {data:{paths:[]}}},storage:{from:()=>({
  download:async(path:string)=>{storage.push({download:path});return {data:blob}},
  upload:async(path:string,bytes:Uint8Array,args:any)=>{storage.push({upload:path,bytes:bytes.length,args});return {error:options.uploadError}},
  remove:async(paths:string[])=>{storage.push({remove:paths});return {}}})}}
 const handler=createPinPhotosHandler(token=>({auth:{getUser:async()=>({data:{user:token==='valid'?{id:'creator'}:null}})},rpc:async(name:string,args:any)=>{
  calls.push({name,args});return options.denied?{error:{code:options.denied}}:args.p_action==='attach'&&options.conflict?{error:{code:'PT409'}}:{data:args.p_action==='list'?{photos:[]}:{object_path:`${pin}/${pin}/${photo}.webp`,revision:2,photo:{id:photo}}}
 }}),()=>admin,async bytes=>{if(options.badImage)throw Error('invalid');storage.push({processed:bytes.length});return {bytes:new Uint8Array([82,73,70,70]),width:100,height:100}})
 const request=(method='GET',body?:BodyInit,query='',token='valid',type='image/jpeg')=>handler(new Request(`https://test.invalid?property=one&pin=${pin}${query}`,{method,headers:{authorization:`Bearer ${token}`,origin:'https://pmicka.com','content-type':type},...(body===undefined?{}:{body})}))
 return {calls,storage,request,handler}
}
Deno.test('photo list/download use verified caller RPC; privileged Storage only follows authorization',async()=>{
 const {request,calls,storage}=fixture()
 assert((await request()).status===200);assert(storage.length===0)
 const image=await request('GET',undefined,'&photo='+photo)
 assert(image.status===200&&image.headers.get('content-type')==='image/webp'&&image.headers.get('cache-control')?.includes('no-store'))
 assert(calls[1].args.p_action==='read'&&storage[0].download)
 const denied=fixture({denied:'42501'});assert((await denied.request('GET',undefined,'&photo='+photo)).status===404);assert(!denied.storage.length)
 assert((await request('GET',undefined,'','invalid')).status===404);assert(calls.length===2)
})
Deno.test('bounded raw upload converts then attaches; cap/owner denial precedes decode/Storage',async()=>{
 const {request,calls,storage}=fixture()
 assert((await request('POST',new Uint8Array([1,2,3]),'&revision=1')).status===201)
 assert(calls.map(x=>x.args.p_action).join(',')==='prepare,attach')
 assert(!Object.hasOwn(calls[1].args,'created_by')&&!Object.hasOwn(calls[1].args,'object_path'))
 const upload=storage.find(x=>x.upload);assert(upload.args.contentType==='image/webp'&&upload.args.upsert===false&&upload.args.metadata.width===100)
 for(const code of ['42501','PT409']){const f=fixture({denied:code});assert((await f.request('POST',new Uint8Array([1]),'&revision=1')).status===(code==='PT409'?409:404));assert(!f.storage.length)}
 for(const query of ['','&revision=0','&revision=1&created_by='+pin,'&revision=1&photo='+photo])assert((await request('POST',new Uint8Array([1]),query)).status===400)
 assert((await request('POST',new Uint8Array([1]),'&revision=1','valid','image/svg+xml')).status===415)
 const tooLarge=fixture();assert((await tooLarge.request('POST',new Uint8Array(4194305),'&revision=1')).status===413);assert(!tooLarge.storage.length)
 const malformed=fixture({badImage:true});assert((await malformed.request('POST',new Uint8Array([1]),'&revision=1')).status===400);assert(!malformed.storage.length)
})
Deno.test('failed finalize queues cleanup; deletion is creator/revision guarded; no arbitrary body accepted',async()=>{
 const failed=fixture({conflict:true});assert((await failed.request('POST',new Uint8Array([1]),'&revision=1')).status===409)
 assert(failed.storage.some(x=>x.args?.p_queue_path))
 const f=fixture();assert((await f.request('DELETE',undefined,'&revision=1&photo='+photo)).status===200)
 assert(f.calls[0].args.p_expected_revision===1&&f.calls[0].args.p_photo_id===photo)
 assert(f.storage.some(x=>x.name==='farm_watch_pin_photo_cleanup_v1'))
 assert((await f.request('DELETE','{}','&revision=1&photo='+photo)).status===400)
 assert((await f.request('OPTIONS')).status===204)
 assert((await f.handler(new Request('https://test.invalid'))).status===404)
})

Deno.test('framing PATCH accepts only bounded focal JSON and never accesses privileged Storage',async()=>{
 const f=fixture()
 const response=await f.request('PATCH',JSON.stringify({focal_x:0,focal_y:100}),'&revision=1&photo='+photo,'valid','application/json')
 assert(response.status===200)
 assert(f.calls.length===1&&f.calls[0].name==='farm_watch_pin_photo_framing_v1')
 assert(f.calls[0].args.p_photo_id===photo&&f.calls[0].args.p_expected_revision===1)
 assert(f.calls[0].args.p_focal_x===0&&f.calls[0].args.p_focal_y===100)
 assert(f.storage.length===0,'framing never reads or writes Storage')
 for(const payload of [
  {focal_x:-1,focal_y:50},{focal_x:101,focal_y:50},
  {focal_x:50.5,focal_y:50},{focal_x:50},{focal_x:'50',focal_y:50},
  {focal_x:50,focal_y:50,object_path:'injected'},
  {focal_x:50,focal_y:50,created_by:'spoofed'},
 ]) {
  const invalid=await f.request('PATCH',JSON.stringify(payload),'&revision=1&photo='+photo,'valid','application/json')
  assert(invalid.status===400)
 }
 assert((await f.request('PATCH',JSON.stringify({focal_x:50,focal_y:50}),'&revision=1','valid','application/json')).status===400)
 assert((await f.request('PATCH',JSON.stringify({focal_x:50,focal_y:50}),'&revision=1&photo='+photo+'&path=bad','valid','application/json')).status===400)
 assert((await f.request('PATCH','x'.repeat(129),'&revision=1&photo='+photo,'valid','application/json')).status===400)
 assert((await f.request('PATCH','{}','&revision=1&photo='+photo,'valid','text/plain')).status===415)
 const denied=fixture({denied:'42501'})
 assert((await denied.request('PATCH',JSON.stringify({focal_x:50,focal_y:50}),'&revision=1&photo='+photo,'valid','application/json')).status===404)
 const conflict=fixture({denied:'PT409'})
 assert((await conflict.request('PATCH',JSON.stringify({focal_x:50,focal_y:50}),'&revision=1&photo='+photo,'valid','application/json')).status===409)
 assert(!denied.storage.length&&!conflict.storage.length)
})
