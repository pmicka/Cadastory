import { canonicalGalleryWebp } from './optimized-webp.ts'
import { assert, assertEquals, assertThrows } from 'jsr:@std/assert@1.0.14'

const VP8_FRAME=new Uint8Array([
  0x10,0x00,0x00,0x9d,0x01,0x2a,0x80,0x02,0xe0,0x01,
  0x00,0x00,0x00,0x00,0x00,0x00,
]) // 640 × 480 VP8 key-frame header. Parser does not decode the bitstream.

function chunk(name:string,payload:Uint8Array):Uint8Array {
  const bytes=new Uint8Array(8+payload.length+(payload.length&1))
  for(let i=0;i<4;i++) bytes[i]=name.charCodeAt(i)
  new DataView(bytes.buffer).setUint32(4,payload.length,true)
  bytes.set(payload,8)
  return bytes
}
function riff(parts:Uint8Array[]):Uint8Array {
  const len=12+parts.reduce((n,p)=>n+p.length,0)
  const bytes=new Uint8Array(len)
  bytes.set([82,73,70,70],0)
  new DataView(bytes.buffer).setUint32(4,len-8,true)
  bytes.set([87,69,66,80],8)
  let pos=12
  for(const part of parts) {bytes.set(part,pos);pos+=part.length}
  return bytes
}
function extended(flags=0x20):Uint8Array {
  const bytes=new Uint8Array(10)
  bytes[0]=flags
  bytes.set([0x7f,0x02,0x00,0xdf,0x01,0x00],4) // 640x480, minus one
  return bytes
}

Deno.test('accept a plain VP8 frame and preserve keyframe dimensions',()=>{
  const original=riff([chunk('VP8 ',VP8_FRAME)])
  const parsed=canonicalGalleryWebp(original)
  assertEquals([parsed.width,parsed.height],[640,480])
  assertEquals(parsed.bytes,original)
})

Deno.test('strip ICCP, EXIF and XMP metadata emitted by browser canvas; repackage opaque VP8',()=>{
  const original=riff([
    chunk('VP8X',extended(0x2c)),
    chunk('ICCP',new Uint8Array([1,2,3,4,5])),
    chunk('VP8 ',VP8_FRAME),
    chunk('EXIF',new Uint8Array([71,80,83,0])),
    chunk('XMP ',new Uint8Array([42,42])),
  ])
  const parsed=canonicalGalleryWebp(original)
  assertEquals(parsed.bytes,riff([chunk('VP8 ',VP8_FRAME)]))
  assertEquals([parsed.width,parsed.height],[640,480])
  assert(parsed.bytes.length<original.length)
})

Deno.test('reject animated, alpha, lossless, truncated, conflicting dimensions and invalid frames',()=>{
  const good=chunk('VP8 ',VP8_FRAME)
  const bad:Uint8Array[]=[
    riff([chunk('VP8X',extended(0x02)),good]), // animation flag
    riff([chunk('VP8X',extended(0x10)),good]), // alpha flag
    riff([chunk('VP8X',extended(0x20)),chunk('ALPH',new Uint8Array([0])),good]),
    riff([chunk('VP8X',extended(0x20)),chunk('ANIM',new Uint8Array([0])),good]),
    riff([chunk('VP8L',new Uint8Array(10))]),
    riff([good,good]),
    riff([chunk('EXIF',new Uint8Array([1])),good]), // undeclared metadata
    riff([chunk('VP8X',extended()),chunk('VP8 ',new Uint8Array([0]))]),
    riff([chunk('VP8X',new Uint8Array(9)),good]),
    riff([chunk('VP8X',Uint8Array.from({...extended(),4:0})),good]), // wrong dims
    riff([chunk('FOO ',new Uint8Array([1])),good]),
    riff([chunk('VP8 ',Uint8Array.from({...VP8_FRAME,0:0x11}))]), // interframe
    riff([chunk('VP8 ',Uint8Array.from({...VP8_FRAME,3:0}))]), // bad sync
    riff([chunk('VP8 ',Uint8Array.from({...VP8_FRAME,6:0,7:0}))]), // zero width
  ]
  for(const v of bad)assertThrows(()=>canonicalGalleryWebp(v))
  const valid=riff([good])
  assertThrows(()=>canonicalGalleryWebp(valid.subarray(0,valid.length-1)))
  assertThrows(()=>canonicalGalleryWebp(new Uint8Array([1,2,3])))
  const badSize=new Uint8Array(valid)
  new DataView(badSize.buffer).setUint32(4,2,true)
  assertThrows(()=>canonicalGalleryWebp(badSize))
})

Deno.test('reject frames over 1600 pixels and excessive uncompressed payloads',()=>{
  const oversized=VP8_FRAME.slice()
  oversized[6]=0x41;oversized[7]=0x06 // 1601px
  assertThrows(()=>canonicalGalleryWebp(riff([chunk('VP8 ',oversized)])))
  const large=new Uint8Array(524288)
  large.set(VP8_FRAME,0)
  assertThrows(()=>canonicalGalleryWebp(riff([chunk('VP8 ',large)])))
})
