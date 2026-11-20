import { cleanHomeGalleryUploads } from '../_shared/farm-watch-gallery-upload-storage.ts'
const path='11111111-1111-1111-1111-111111111111/22222222-2222-2222-2222-222222222222.webp'
const assert=(ok:unknown)=>{if(!ok)throw Error('gallery cleanup assertion failed')}

Deno.test('failed deletions remain queued; successful storage removal is acknowledged',async()=>{
  const calls:any[]=[]
  let fail=true
  const admin={
    rpc:async(_name:string,args:any)=>{
      calls.push(args)
      return {data:{paths:[path]}}
    },
    storage:{from:()=>({remove:async(paths:string[])=>{
      calls.push(paths)
      return {error:fail?'temporary':null}
    }})},
  }
  await cleanHomeGalleryUploads(admin,path)
  assert(calls.length===2&&calls[0].p_queue_path===path)
  fail=false
  await cleanHomeGalleryUploads(admin)
  assert(calls.length===5&&calls[4].p_ack_paths?.[0]===path)
})
Deno.test('malicious, cross-bucket and oversized cleanup lists are never sent to privileged Storage',async()=>{
  for(const paths of [['../other/file'],['faked/upload.webp'],Array(21).fill(path)]){
    let deleted=false
    await cleanHomeGalleryUploads({
      rpc:async()=>({data:{paths}}),
      storage:{from:()=>({remove:()=>{deleted=true;return {}}})},
    })
    assert(!deleted)
  }
})
