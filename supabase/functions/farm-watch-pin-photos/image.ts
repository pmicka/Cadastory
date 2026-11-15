import { ImageMagick, initializeImageMagick, MagickFormat, ResourceLimits } from 'npm:@imagemagick/magick-wasm@0.0.46'
import type { ProcessedPhoto } from './handler.ts'
// Official Supabase WASM image-processing approach; no native Sharp dependency.
const initialized=initializeImageMagick(await Deno.readFile(new URL('x86/magick.wasm',import.meta.resolve('npm:@imagemagick/magick-wasm@0.0.46')))).then(()=>{
 ResourceLimits.memory=96n*1024n*1024n;ResourceLimits.maxMemoryRequest=64n*1024n*1024n;ResourceLimits.disk=0n
 ResourceLimits.width=10000n;ResourceLimits.height=10000n;ResourceLimits.maxProfileSize=4n*1024n*1024n
})

export function imageDimensions(bytes:Uint8Array):[number,number] {
 const view=new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength),ascii=(at:number,size:number)=>String.fromCharCode(...bytes.subarray(at,at+size))
 let width=0,height=0
 if(bytes.length>=24&&ascii(0,8)==='\x89PNG\r\n\x1a\n'&&ascii(12,4)==='IHDR'){
  width=view.getUint32(16);height=view.getUint32(20)
  for(let at=8;at+12<=bytes.length;){const length=view.getUint32(at);if(at+12+length>bytes.length)throw Error('invalid PNG');if(ascii(at+4,4)==='acTL')throw Error('animated image');at+=12+length}
 }
 else if(bytes.length>=30&&ascii(0,4)==='RIFF'&&ascii(8,4)==='WEBP') {
  const type=ascii(12,4)
  if(type==='VP8X') {if(bytes[20]&2)throw Error('animated image');width=1+bytes[24]+(bytes[25]<<8)+(bytes[26]<<16);height=1+bytes[27]+(bytes[28]<<8)+(bytes[29]<<16)}
  else if(type==='VP8 '&&ascii(23,3)==='\x9d\x01\x2a'){width=view.getUint16(26,true)&0x3fff;height=view.getUint16(28,true)&0x3fff}
  else if(type==='VP8L'&&bytes[20]===0x2f){width=1+bytes[21]+((bytes[22]&63)<<8);height=1+(bytes[22]>>6)+(bytes[23]<<2)+((bytes[24]&15)<<10)}
 } else if(bytes[0]===0xff&&bytes[1]===0xd8) {
  let at=2
  while(at+4<bytes.length){if(bytes[at++]!==0xff)throw Error('invalid JPEG');while(bytes[at]===0xff)at++;const marker=bytes[at++];if(marker===0xda||marker===0xd9)break
   const length=view.getUint16(at);if(length<2||at+length>bytes.length)throw Error('invalid JPEG')
   if([0xc0,0xc1,0xc2].includes(marker)&&length>=8){height=view.getUint16(at+3);width=view.getUint16(at+5);break}at+=length
  }
 }
 if(width<1||height<1||width>10000||height>10000||width*height>8000000)throw Error('unsupported or oversized image')
 return [width,height]
}
export async function processPhoto(bytes:Uint8Array):Promise<ProcessedPhoto> {
 imageDimensions(bytes) // Reject header bombs/unsupported formats before decoding.
 await initialized
 return ImageMagick.read(bytes,image=>{
  image.autoOrient();image.strip()
  for(const [edge,quality] of [[1600,78],[1280,70],[960,65]]) {
   const scale=Math.min(1,edge/Math.max(image.width,image.height))
   if(scale<1)image.resize(Math.max(1,Math.round(image.width*scale)),Math.max(1,Math.round(image.height*scale)))
   image.quality=quality
   const output=image.write(MagickFormat.WebP,data=>new Uint8Array(data))
   if(output.length<=524288)return {bytes:output,width:image.width,height:image.height}
  }
  throw Error('image too large')
 })
}
