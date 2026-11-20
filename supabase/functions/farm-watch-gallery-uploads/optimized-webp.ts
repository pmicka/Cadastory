// Fast, bounded, metadata-stripping WebP container normalization.
//
// Browser canvas encoders often emit an extended WebP wrapper with ICCP data.
// Repackage exactly one opaque VP8 key frame as a simple WebP RIFF container.
// No untrusted EXIF/XMP/ICCP/animation/alpha chunks survive. There is no image
// decoding/encoding inside the Supabase Edge CPU budget.
//
// This validates the *container*, not the compressed VP8 bitstream. Media is
// stored privately and must still be treated as untrusted when viewed.
const MAX_REQUEST_BYTES=4194304
const MAX_STORED_BYTES=524288
const ascii=(bytes:Uint8Array,at:number,length:number)=>
  String.fromCharCode(...bytes.subarray(at,at+length))

export type CanonicalWebp={bytes:Uint8Array;width:number;height:number}

export function canonicalGalleryWebp(input:Uint8Array):CanonicalWebp {
  if (!(input instanceof Uint8Array) || input.length<30 ||
      input.length>MAX_REQUEST_BYTES || ascii(input,0,4)!=='RIFF' ||
      ascii(input,8,4)!=='WEBP') throw Error('invalid WebP container')
  const view=new DataView(input.buffer,input.byteOffset,input.byteLength)
  if (view.getUint32(4,true)!==input.length-8) throw Error('invalid RIFF size')

  let cursor=12,frameStart=-1,frameLength=0,width=0,height=0
  let extended=false,extensionWidth=0,extensionHeight=0
  while(cursor<input.length) {
    if (cursor+8>input.length) throw Error('truncated chunk')
    const fourcc=ascii(input,cursor,4)
    const length=view.getUint32(cursor+4,true)
    const start=cursor+8
    const end=start+length
    if (!Number.isSafeInteger(end) || end>input.length ||
        end+(length%2)>input.length) throw Error('chunk out of range')

    if (fourcc==='VP8X') {
      if (extended || cursor!==12 || length!==10) throw Error('invalid VP8X')
      extended=true
      const flags=input[start]
      // Alpha/animation are forbidden; flags may only describe metadata which
      // we deliberately strip. All reserved bits must be zero.
      if ((flags&~0x2c)!==0 || input[start+1]!==0 ||
          input[start+2]!==0 || input[start+3]!==0) throw Error('unsupported WebP features')
      extensionWidth=1+input[start+4]+(input[start+5]<<8)+(input[start+6]<<16)
      extensionHeight=1+input[start+7]+(input[start+8]<<8)+(input[start+9]<<16)
    } else if (fourcc==='VP8 ') {
      if (frameStart>=0 || length<10) throw Error('invalid VP8 frame')
      // VP8 key frame only, with the expected frame-start marker.
      if ((input[start]&1)!==0 ||
          input[start+3]!==0x9d || input[start+4]!==0x01 ||
          input[start+5]!==0x2a) throw Error('unsupported VP8 frame')
      width=view.getUint16(start+6,true)&0x3fff
      height=view.getUint16(start+8,true)&0x3fff
      frameStart=start
      frameLength=length
    } else if (!['ICCP','EXIF','XMP '].includes(fourcc)) {
      // Reject VP8L, alpha, animation and any unknown/active chunk.
      throw Error('unsupported WebP chunk')
    } else if (!extended) {
      throw Error('unexpected metadata in simple WebP')
    }
    cursor=end+(length%2)
  }
  if (cursor!==input.length || frameStart<0 || width<1 || height<1 ||
      width>1600 || height>1600 || width*height>2560000 ||
      (extended && (extensionWidth!==width || extensionHeight!==height)))
    throw Error('unsupported WebP dimensions')

  const size=20+frameLength+(frameLength%2)
  if (size>MAX_STORED_BYTES) throw Error('optimized WebP too large')
  const bytes=new Uint8Array(size)
  bytes.set([82,73,70,70],0) // RIFF
  const out=new DataView(bytes.buffer)
  out.setUint32(4,size-8,true)
  bytes.set([87,69,66,80,86,80,56,32],8) // WEBP VP8<space>
  out.setUint32(16,frameLength,true)
  bytes.set(input.subarray(frameStart,frameStart+frameLength),20)
  return {bytes,width,height}
}
