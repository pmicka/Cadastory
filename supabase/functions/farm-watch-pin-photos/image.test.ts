import { ImageMagick, MagickColors, MagickFormat } from 'npm:@imagemagick/magick-wasm@0.0.46'
import { imageDimensions, processPhoto } from './image.ts'
const assert=(x:unknown)=>{if(!x)throw Error('image assertion failed')}
Deno.test('actual WASM converts, resizes, strips metadata and bounds WebP output',async()=>{
 // Initialization is awaited by processPhoto; first process a known tiny PNG.
 const tiny=Uint8Array.from(atob('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC'),c=>c.charCodeAt(0))
 await processPhoto(tiny)
 const source=ImageMagick.read(MagickColors.Red,2400,1200,image=>{image.setAttribute('comment','private GPS-like metadata');return image.write(MagickFormat.Jpeg,data=>new Uint8Array(data))})
 const result=await processPhoto(source)
 assert(result.width===1600&&result.height===800&&result.bytes.length<=524288)
 assert(String.fromCharCode(...result.bytes.slice(0,4))==='RIFF')
 assert(!new TextDecoder().decode(result.bytes).includes('private GPS-like metadata'))
 const roundtrip=await processPhoto(result.bytes);assert(roundtrip.width===1600&&roundtrip.height===800)
 // A real EXIF Orientation=6 JPEG rotates before stripping its metadata.
 const exif=new Uint8Array([69,120,105,102,0,0,73,73,42,0,8,0,0,0,1,0,18,1,3,0,1,0,0,0,6,0,0,0,0,0,0,0])
 const oriented=new Uint8Array(source.length+exif.length+4);oriented.set(source.slice(0,2));oriented.set([255,225,0,exif.length+2],2);oriented.set(exif,6);oriented.set(source.slice(2),6+exif.length)
 const rotated=await processPhoto(oriented);assert(rotated.width===800&&rotated.height===1600)
 assert(!new TextDecoder().decode(rotated.bytes).includes('Exif'))
})
Deno.test('header bounds reject malformed/unsupported images and decompression bombs before decoding',()=>{
 for(const bytes of [new Uint8Array(),new TextEncoder().encode('<svg/>'),new Uint8Array([255,216,255,192,0,2])]){let denied=false;try{imageDimensions(bytes)}catch{denied=true}assert(denied)}
 const png=new Uint8Array(24);png.set([137,80,78,71,13,10,26,10]);png.set([73,72,68,82],12);const v=new DataView(png.buffer);v.setUint32(16,10000);v.setUint32(20,10000)
 let denied=false;try{imageDimensions(png)}catch{denied=true}assert(denied)
})
