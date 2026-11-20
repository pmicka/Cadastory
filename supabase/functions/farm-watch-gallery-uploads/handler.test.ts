import { createHomeGalleryUploadsHandler } from './handler.ts'

const OWNER='00000000-0000-0000-0000-000000000002'
const PROPERTY='10000000-0000-0000-0000-000000000002'
const PHOTO='33333333-3333-3333-3333-333333333333'
const path=(id:string)=>PROPERTY+'/'+id+'.webp'
const assert=(ok:unknown,message='assertion failed')=>{if(!ok)throw Error(message)}

function fixture(options:any={}) {
  const calls:any[]=[],storage:any[]=[]
  const blob=new Blob([new Uint8Array([82,73,70,70])],{type:'image/webp'})
  const admin={
    rpc:async(name:string,args:any)=>{storage.push({name,args});return {data:{paths:[]}}},
    storage:{from:(bucket:string)=>({
      download:async(p:string)=>{storage.push({bucket,download:p});return {data:blob}},
      upload:async(p:string,bytes:Uint8Array,metadata:any)=>{
        storage.push({bucket,upload:p,bytes:bytes.length,metadata})
        return {error:options.uploadError||null}
      },
      remove:async(paths:string[])=>{storage.push({bucket,remove:paths});return {error:null}},
    })},
  }
  const handler=createHomeGalleryUploadsHandler(token=>({
    auth:{getUser:async()=>({
      data:{user:token==='valid'?{id:OWNER}:null},error:null,
    })},
    rpc:async(name:string,args:any)=>{
      calls.push({name,args})
      if(options.denied)return {data:null,error:{code:options.denied}}
      if(args.p_action==='attach'&&options.conflict)
        return {data:null,error:{code:'PT409'}}
      if(args.p_action==='list')return {data:{revision:1,photos:[],staged_only:true}}
      if(name==='farm_watch_home_gallery_image_v1')return {data:{object_path:path(args.p_photo_id),bytes:4}}
      if(args.p_action==='prepare')return {data:{
        object_path:options.badPath?'../../unsafe':path(args.p_photo_id)}}
      return {data:{revision:2,staged_only:true,photo:{id:args.p_photo_id}}}
    },
  }),()=>admin,async bytes=>{
    if(options.badImage)throw Error('bad image')
    storage.push({processed:bytes.length})
    return {bytes:new Uint8Array([82,73,70,70]),width:100,height:120}
  })
  const request=(method='GET',body?:BodyInit,query='',token='valid',type='image/webp')=>
    handler(new Request('https://test.invalid/?property=one'+query,{
      method,
      headers:{authorization:'Bearer '+token,origin:'https://pmicka.com',
        ...(type?{'content-type':type}:{})},
      ...(body===undefined?{}:{body}),
    }))
  return {calls,storage,request,handler}
}

Deno.test('only a verified caller can list or read staged media; no Storage until RPC authorizes',async()=>{
  const f=fixture()
  assert((await f.request()).status===200)
  assert(!f.storage.length)
  const image=await f.request('GET',undefined,'&photo='+PHOTO)
  assert(image.status===200)
  assert(image.headers.get('content-type')==='image/webp')
  assert(image.headers.get('cache-control')?.includes('no-store'))
  assert(f.calls[1].name==='farm_watch_home_gallery_image_v1')
  assert(f.calls[1].args.p_photo_id===PHOTO)
  assert(f.storage.some(s=>s.download===path(PHOTO)))
  const denied=fixture({denied:'42501'})
  assert((await denied.request('GET',undefined,'&photo='+PHOTO)).status===404)
  assert(denied.storage.length===0)
  assert((await f.request('GET',undefined,'','invalid')).status===404)
  assert(f.calls.length===2)
  assert((await f.request('GET',undefined,'&revision=1')).status===400)
  assert((await f.request('GET',undefined,'&other=1')).status===400)
})

Deno.test('upload checks owner role/revision before decoding, optimizes and attaches with private Storage',async()=>{
  const f=fixture()
  const response=await f.request('POST',new Uint8Array([1,2,3]),'&revision=1')
  assert(response.status===201)
  assert(f.calls.map(x=>x.args.p_action).join(',')==='prepare,attach')
  const uploaded=f.storage.find(x=>x.upload)
  assert(uploaded?.bucket==='farm-watch-home-gallery-uploads')
  assert(uploaded.metadata.contentType==='image/webp'&&!uploaded.metadata.upsert)
  assert(uploaded.metadata.metadata.created_by===OWNER)
  assert(uploaded.metadata.metadata.property_id===PROPERTY)
  assert(uploaded.metadata.metadata.width===100)
  assert(uploaded.upload===path(f.calls[0].args.p_photo_id))
  assert(!Object.hasOwn(f.calls[1].args,'object_path')&&!Object.hasOwn(f.calls[1].args,'created_by'))

  for(const denied of ['42501','PT409']){
    const f=fixture({denied})
    assert((await f.request('POST',new Uint8Array([1]),'&revision=1')).status===
      (denied==='PT409'?409:404))
    assert(f.storage.length===0)
  }
  for(const query of ['', '&revision=0','&revision=1&other=1',
      '&revision=1&photo='+PHOTO]){
    assert((await f.request('POST',new Uint8Array([1]),query)).status===400)
  }
  assert((await f.request('POST',new Uint8Array([1]),'&revision=1','valid','image/svg+xml')).status===415)
  assert((await f.request('POST',new Uint8Array([1]),'&revision=1','valid','image/jpeg')).status===415)
  assert((await f.request('POST',new Uint8Array([1]),'&revision=1','valid','image/png')).status===415)
  const tooLarge=fixture()
  assert((await tooLarge.request('POST',new Uint8Array(4194305),'&revision=1')).status===413)
  assert(!tooLarge.storage.length)
  const malformed=fixture({badImage:true})
  assert((await malformed.request('POST',new Uint8Array([1]),'&revision=1')).status===400)
  assert(!malformed.storage.some(x=>x.upload))
  const wrongPath=fixture({badPath:true})
  assert((await wrongPath.request('POST',new Uint8Array([1]),'&revision=1')).status===503)
  assert(!wrongPath.storage.length)
})

Deno.test('finalization conflict queues cleanup; deletion requires revision and cannot accept body/path',async()=>{
  const failed=fixture({conflict:true})
  assert((await failed.request('POST',new Uint8Array([1]),'&revision=1')).status===409)
  assert(failed.storage.some(x=>x.name==='farm_watch_home_gallery_upload_cleanup_v1'&&x.args.p_queue_path))
  const f=fixture()
  assert((await f.request('DELETE',undefined,'&photo='+PHOTO+'&revision=1')).status===200)
  assert(f.calls[0].args.p_photo_id===PHOTO&&f.calls[0].args.p_expected_revision===1)
  assert(f.storage.some(x=>x.name==='farm_watch_home_gallery_upload_cleanup_v1'))
  assert((await f.request('DELETE','{}','&photo='+PHOTO+'&revision=1')).status===400)
  assert((await f.request('DELETE',undefined,'&revision=1')).status===400)
  assert((await f.request('OPTIONS')).status===204)
  assert((await f.handler(new Request('https://test.invalid'))).status===404)
  const otherOrigin=new Request('https://test.invalid/?property=one',{
    headers:{origin:'https://malicious.example',authorization:'Bearer valid'},
  })
  assert((await f.handler(otherOrigin)).status===404)
})
