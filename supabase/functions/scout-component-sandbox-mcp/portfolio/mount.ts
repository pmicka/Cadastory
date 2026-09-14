import { buildPortfolioFrame } from './frame.ts'
import { mountPortfolioMembers } from './member_view.ts'
import { PORTFOLIO_TILE_TEMPLATE, validatePortfolioTiles } from './raster.ts'

type Options = {
  onReady: () => void
  onError: (error: Error) => void
  onDiagnostic: (fields: Record<string,string|number|boolean>) => void
}
export function mountPortfolioMap(container: HTMLElement, controls: HTMLElement, value: unknown, entries: unknown, options: Options) {
  const tiles = validatePortfolioTiles(value, entries)
  let destroyed = false, generation = 0, previousWidth = 0
  const canvas = document.createElement('canvas'), markers = document.createElement('div')
  canvas.style.cssText = 'position:absolute;inset:0;width:100%;height:210px;pointer-events:none'
  markers.style.cssText = 'position:absolute;inset:0;pointer-events:none'
  const attribution = document.createElement('div')
  attribution.className = 'scout-map-attribution'
  const link = document.createElement('a')
  link.href = 'https://www.openstreetmap.org/copyright'; link.target = '_blank'; link.rel = 'noopener noreferrer'
  link.textContent = '© OpenStreetMap contributors · HOT'; attribution.appendChild(link)
  container.replaceChildren(canvas,markers,attribution)
  const width = () => Math.max(280,Math.min(456,Math.round(container.clientWidth || 330)))
  const members = mountPortfolioMembers(controls,markers,value,width())
  const context = canvas.getContext('2d')
  options.onDiagnostic({branch:'portfolio_canvas',context2d:context?'available':'unavailable',embeddedValidCount:tiles.size})
  let bitmaps: ImageBitmap[] = []
  let timer: ReturnType<typeof setTimeout> | undefined
  const close = () => { for (const bitmap of bitmaps) bitmap.close(); bitmaps = [] }
  const fail = (category: string) => {
    generation++; if (timer) clearTimeout(timer); close()
    options.onDiagnostic({rendererReady:false,lastError:category})
    options.onError(new Error(category))
  }
  const resize = () => {
    if (destroyed) return
    const nextWidth = width()
    if (nextWidth === previousWidth) return
    previousWidth = nextWidth
    const current = ++generation
    if (timer) clearTimeout(timer)
    close()
    const frame = buildPortfolioFrame(value,nextWidth,210,PORTFOLIO_TILE_TEMPLATE)
    canvas.width = nextWidth; canvas.height = 210; members.resize(nextWidth)
    options.onDiagnostic({requiredTiles:frame.tiles.length,matchingTiles:frame.tiles.filter(t=>tiles.has(t.url)).length,decodedTiles:0,rendererReady:false,generation:current})
    if (!context) { fail('context_unavailable'); return }
    if (!frame.tiles.length) { fail('no_located_members'); return }
    if (typeof createImageBitmap !== 'function') { fail('decoder_unavailable'); return }
    timer = setTimeout(() => { if (!destroyed && current === generation) fail('decode_timeout') },8000)
    void Promise.all(frame.tiles.map(async tile => {
      let bitmap: ImageBitmap
      try { bitmap = await createImageBitmap(new Blob([tiles.get(tile.url)!],{type:'image/png'})) }
      catch { if (!destroyed && current === generation) fail('decode_failed'); return }
      if (destroyed || current !== generation) { bitmap.close(); return }
      bitmaps.push(bitmap)
      try {
        if (bitmap.width !== 256 || bitmap.height !== 256) { fail('decoded_dimensions'); return }
        context.drawImage(bitmap,tile.left,tile.top,256,256)
        options.onDiagnostic({decodedTiles:bitmaps.length})
      } catch { fail('paint_failed') }
    })).then(() => {
      if (destroyed || current !== generation) return
      if (timer) clearTimeout(timer)
      close(); options.onDiagnostic({rendererReady:true,lastError:'none'}); options.onReady()
    })
  }
  resize()
  return {resize,destroy(){destroyed=true;generation++;if(timer)clearTimeout(timer);close();members.destroy();container.replaceChildren()}}
}
