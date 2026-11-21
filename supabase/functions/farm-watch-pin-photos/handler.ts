import { PHOTO_BUCKET, cleanPinPhotos } from '../_shared/farm-watch-pin-photo-storage.ts'
const ORIGINS=new Set(['https://pmicka.com','https://www.pmicka.com','http://127.0.0.1:8000','http://localhost:8000'])
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
export type ProcessedPhoto={bytes:Uint8Array;width:number;height:number}
export function createPinPhotosHandler(clientForToken:(token:string)=>any,adminForStorage:()=>any,processImage:(bytes:Uint8Array)=>Promise<ProcessedPhoto>) {
 return async(req:Request):Promise<Response>=>{
  const origin=req.headers.get('origin')||'',headers:Record<string,string>={'content-type':'application/json; charset=utf-8','cache-control':'no-store, max-age=0','x-content-type-options':'nosniff','referrer-policy':'no-referrer',vary:'Origin'}
  if(ORIGINS.has(origin))Object.assign(headers,{'access-control-allow-origin':origin,'access-control-allow-methods':'GET, POST, PATCH, DELETE, OPTIONS','access-control-allow-headers':'authorization, apikey, content-type'})
  const respond=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers})
  const failure=(error:any)=>respond({error:error?.code==='PT409'?'Pin changed or four photos reached. Reload pins.':error?.code==='42501'?'not found':error?.code==='22023'||error?.code==='23514'?'Invalid photo.':'Photos unavailable. Try again.'},error?.code==='PT409'?409:error?.code==='42501'?404:['22023','23514'].includes(error?.code)?400:503)
  if(origin&&!ORIGINS.has(origin))return respond({error:'not found'},404)
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers})
  if(!['GET','POST','PATCH','DELETE'].includes(req.method))return respond({error:'not found'},404)
  const token=req.headers.get('authorization')?.match(/^Bearer (\S+)$/i)?.[1]
  if(!token)return respond({error:'not found'},404)
  try {
   const client=clientForToken(token),{data:auth,error:authError}=await client.auth.getUser(token)
   if(authError||!auth?.user||auth.user.is_anonymous)return respond({error:'not found'},404)
   const url=new URL(req.url),property=url.searchParams.get('property')||'',pin=url.searchParams.get('pin')||'',photo=url.searchParams.get('photo')
   if(!/^[a-z0-9][a-z0-9-]{0,79}$/.test(property)||!UUID.test(pin)||(photo!==null&&!UUID.test(photo))||[...url.searchParams.keys()].some(k=>!['property','pin','photo','revision','focal_x','focal_y'].includes(k)))return respond({error:'invalid input'},400)
   const args:any={p_property_slug:property,p_pin_id:pin}
   const x=url.searchParams.getAll('focal_x'),y=url.searchParams.getAll('focal_y')
   const hasFraming=x.length>0||y.length>0
   const isPercent=(value:string)=>/^(?:[0-9]|[1-9][0-9]|100)$/.test(value)
   if(hasFraming&&(x.length!==1||y.length!==1||!isPercent(x[0])||!isPercent(y[0])||!['POST','PATCH'].includes(req.method))
    ||req.method==='PATCH'&&!hasFraming)return respond({error:'invalid framing'},400)
   const focalArgs=hasFraming?{p_focal_x:Number(x[0]),p_focal_y:Number(y[0])}:{}
   if(req.method==='GET') {
    const {data,error}=await client.rpc('farm_watch_pin_photos_v1',{...args,p_action:photo?'read':'list',...(photo?{p_photo_id:photo}:{})})
    if(error)return failure(error)
    if(!photo)return respond(data)
    const admin=adminForStorage(),download=await admin.storage.from(PHOTO_BUCKET).download(data.object_path)
    if(download.error||!download.data||download.data.size>524288)return respond({error:'Photo unavailable.'},503)
    return new Response(download.data,{headers:{...headers,'content-type':'image/webp','content-disposition':'inline'}})
   }
   const revision=Number(url.searchParams.get('revision'))
   if(!Number.isSafeInteger(revision)||revision<1||(req.method==='POST'?photo!==null:!photo))return respond({error:'invalid input'},400)
   if(req.method==='DELETE'||req.method==='PATCH') {
    // No arbitrary JSON/body fields, image paths or ownership metadata accepted.
    if(req.body){const reader=req.body.getReader();while(true){const {done,value}=await reader.read();if(done)break;if(value.byteLength){await reader.cancel();return respond({error:'invalid input'},400)}}}
    const result=await client.rpc('farm_watch_pin_photos_v1',{...args,p_action:req.method==='PATCH'?'frame':'delete',p_photo_id:photo,p_expected_revision:revision,...focalArgs})
    if(result.error)return failure(result.error)
    if(req.method==='DELETE')await cleanPinPhotos(adminForStorage())
    return respond(result.data)
   }
   if(!['image/jpeg','image/png','image/webp'].includes(req.headers.get('content-type')||''))return respond({error:'Choose a JPEG, PNG or WebP photo.'},415)
   const id=crypto.randomUUID()
   const permitted=await client.rpc('farm_watch_pin_photos_v1',{...args,p_action:'prepare',p_photo_id:id,p_expected_revision:revision})
   if(permitted.error)return failure(permitted.error)
   // Bound a streamed body even without Content-Length, before image decoding.
   const reader=req.body?.getReader();if(!reader)return respond({error:'Choose a photo.'},400)
   const chunks:Uint8Array[]=[];let size=0
   while(true){const {done,value}=await reader.read();if(done)break;size+=value.byteLength;if(size>4194304){await reader.cancel();return respond({error:'Upload a photo under 4 MB.'},413)}chunks.push(value)}
   if(!size)return respond({error:'Choose a photo.'},400)
   const source=new Uint8Array(size);let offset=0;for(const chunk of chunks){source.set(chunk,offset);offset+=chunk.length}
   let processed:ProcessedPhoto
   try{processed=await processImage(source)}catch{return respond({error:'This photo could not be processed. Choose a JPEG, PNG or WebP image.'},400)}
   if(!processed.bytes.length||processed.bytes.length>524288||![processed.width,processed.height].every(n=>Number.isInteger(n)&&n>0&&n<=1600))return respond({error:'Photo could not be optimized.'},400)
   const admin=adminForStorage(),path=permitted.data.object_path
   const uploaded=await admin.storage.from(PHOTO_BUCKET).upload(path,processed.bytes,{contentType:'image/webp',upsert:false,metadata:{pin_id:pin,photo_id:id,width:processed.width,height:processed.height}})
   if(uploaded.error)return respond({error:'Photo upload failed. Try again.'},503)
   const attached=await client.rpc('farm_watch_pin_photos_v1',{...args,p_action:'attach',p_photo_id:id,p_expected_revision:revision,...focalArgs})
   if(attached.error){await cleanPinPhotos(admin,path);return failure(attached.error)}
   await cleanPinPhotos(admin)
   return respond(attached.data,201)
  }catch{return respond({error:'Photos unavailable. Try again.'},503)}
 }
}
