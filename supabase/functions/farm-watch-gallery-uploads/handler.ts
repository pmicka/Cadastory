import { HOME_GALLERY_UPLOAD_BUCKET, cleanHomeGalleryUploads } from '../_shared/farm-watch-gallery-upload-storage.ts'
import { canonicalGalleryWebp } from './optimized-webp.ts'

const ORIGINS = new Set(['https://pmicka.com','https://www.pmicka.com',
  'http://127.0.0.1:8000','http://localhost:8000'])
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const PATH = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.webp$/

export type ProcessedGalleryPhoto = {bytes:Uint8Array;width:number;height:number}

// The Edge Function only writes optimized WebP bytes. Authn and current-role
// authz are checked through the caller's JWT on *every* database mutation.
export function createHomeGalleryUploadsHandler(
  clientForToken:(token:string)=>any,
  adminForStorage:()=>any,
  normalizeImage:(bytes:Uint8Array)=>ProcessedGalleryPhoto|Promise<ProcessedGalleryPhoto> = canonicalGalleryWebp,
) {
  return async (req:Request):Promise<Response> => {
    const origin = req.headers.get('origin')||''
    const headers:Record<string,string> = {
      'content-type':'application/json; charset=utf-8',
      'cache-control':'no-store, max-age=0',
      'x-content-type-options':'nosniff',
      'referrer-policy':'no-referrer',
      vary:'Origin',
    }
    if (ORIGINS.has(origin)) Object.assign(headers, {
      'access-control-allow-origin':origin,
      'access-control-allow-methods':'GET, POST, DELETE, OPTIONS',
      'access-control-allow-headers':'authorization, apikey, content-type',
    })
    const respond = (body:unknown,status=200) =>
      new Response(JSON.stringify(body),{status,headers})
    const failure = (error:any) => {
      const code=String(error?.code||'')
      return respond({
        error:code==='PT409'?'Gallery changed or upload limit reached. Reload gallery.'
          :code==='42501'?'not found'
          :['22023','23514'].includes(code)?'Invalid gallery upload.':
            'Gallery uploads unavailable. Try again.',
      },code==='PT409'?409:code==='42501'?404:
        ['22023','23514'].includes(code)?400:503)
    }

    if (origin&&!ORIGINS.has(origin)) return respond({error:'not found'},404)
    if (req.method==='OPTIONS') return new Response(null,{status:204,headers})
    if (!['GET','POST','DELETE'].includes(req.method)) return respond({error:'not found'},404)
    const token=req.headers.get('authorization')?.match(/^Bearer (\S+)$/i)?.[1]
    if (!token) return respond({error:'not found'},404)
    try {
      const client=clientForToken(token)
      const {data:auth,error:authError}=await client.auth.getUser(token)
      if (authError||!auth?.user||auth.user.is_anonymous||!UUID.test(auth.user.id))
        return respond({error:'not found'},404)
      const url=new URL(req.url)
      const property=url.searchParams.get('property')||''
      const photo=url.searchParams.get('photo')
      if (!/^[a-z0-9][a-z0-9-]{0,79}$/.test(property)||
          (photo!==null&&!UUID.test(photo))||
          [...url.searchParams.keys()].some(k=>!['property','photo','revision'].includes(k))) {
        return respond({error:'invalid input'},400)
      }
      const args:any={p_property_slug:property}
      if(req.method==='GET') {
        if(url.searchParams.has('revision'))return respond({error:'invalid input'},400)
        const {data,error}=await client.rpc('farm_watch_home_gallery_uploads_v1',{
          ...args,p_action:photo?'read':'list',...(photo?{p_photo_id:photo}:{})})
        if(error)return failure(error)
        if(!photo)return respond(data)
        if (!PATH.test(data?.object_path||'') ||
            !Number.isInteger(data?.bytes) || data.bytes<1 || data.bytes>524288)
          return respond({error:'Image unavailable.'},503)
        const download=await adminForStorage().storage.from(HOME_GALLERY_UPLOAD_BUCKET).download(data.object_path)
        if(download.error||!download.data||download.data.size>524288)
          return respond({error:'Image unavailable.'},503)
        return new Response(download.data,{headers:{
          ...headers,'content-type':'image/webp','content-disposition':'inline'}})
      }

      const rawRevision=url.searchParams.get('revision')
      const revision=rawRevision===null?NaN:Number(rawRevision)
      if(!Number.isSafeInteger(revision)||revision<1||
         (req.method==='DELETE'?!photo:photo!==null))
        return respond({error:'invalid input'},400)

      if(req.method==='DELETE') {
        // No JSON body or client-specified object paths.
        if(req.body) {
          const reader=req.body.getReader()
          while(true) {
            const {done,value}=await reader.read()
            if(done)break
            if(value.byteLength){await reader.cancel();return respond({error:'invalid input'},400)}
          }
        }
        const {data,error}=await client.rpc('farm_watch_home_gallery_uploads_v1',{
          ...args,p_action:'delete',p_photo_id:photo,p_expected_revision:revision})
        if(error)return failure(error)
        await cleanHomeGalleryUploads(adminForStorage())
        return respond(data)
      }

      // Mobile JPEG/PNG images are resized and encoded in the browser. The
      // Edge Function refuses raw photos rather than hitting its 2s CPU limit.
      if(req.headers.get('content-type')!=='image/webp')
        return respond({error:'Use the updated gallery admin page to prepare this photo.'},415)
      const id=crypto.randomUUID()
      const permitted=await client.rpc('farm_watch_home_gallery_uploads_v1',{
        ...args,p_action:'prepare',p_photo_id:id,p_expected_revision:revision})
      if(permitted.error)return failure(permitted.error)
      const path=permitted.data?.object_path
      if(typeof path!=='string'||!PATH.test(path))
        return respond({error:'Gallery unavailable.'},503)

      // Read at most 4 MiB even when Content-Length is omitted or dishonest.
      const reader=req.body?.getReader()
      if(!reader)return respond({error:'Choose a photo.'},400)
      const chunks:Uint8Array[]=[]
      let size=0
      while(true){
        const {done,value}=await reader.read()
        if(done)break
        size+=value.byteLength
        if(size>4194304){
          await reader.cancel()
          return respond({error:'Upload a photo under 4 MB.'},413)
        }
        chunks.push(value)
      }
      if(!size)return respond({error:'Choose a photo.'},400)
      const source=new Uint8Array(size)
      let offset=0
      for(const chunk of chunks){source.set(chunk,offset);offset+=chunk.length}
      let processed:ProcessedGalleryPhoto
      try{processed=await normalizeImage(source)}
      catch{return respond({error:'Could not validate optimized WebP photo.'},400)}
      if(!processed.bytes.length||processed.bytes.length>524288||
          ![processed.width,processed.height].every(n=>
            Number.isInteger(n)&&n>0&&n<=1600))
        return respond({error:'Photo could not be optimized.'},400)

      const admin=adminForStorage()
      const uploaded=await admin.storage.from(HOME_GALLERY_UPLOAD_BUCKET).upload(
        path,processed.bytes,{
          contentType:'image/webp',upsert:false,
          metadata:{property_id:path.split('/')[0],photo_id:id,
            created_by:auth.user.id,width:processed.width,height:processed.height},
        })
      if(uploaded.error)return respond({error:'Photo upload failed. Try again.'},503)
      const attached=await client.rpc('farm_watch_home_gallery_uploads_v1',{
        ...args,p_action:'attach',p_photo_id:id,p_expected_revision:revision})
      if(attached.error){
        await cleanHomeGalleryUploads(admin,path)
        return failure(attached.error)
      }
      await cleanHomeGalleryUploads(admin)
      return respond(attached.data,201)
    } catch {
      return respond({error:'Gallery uploads unavailable. Try again.'},503)
    }
  }
}
