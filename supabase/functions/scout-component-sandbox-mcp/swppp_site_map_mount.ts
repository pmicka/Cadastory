import type { ScoutSandboxSwpppSiteMap } from './swppp_site_map_model.ts'
import { buildScoutSwpppSiteRasterFrame, type ScoutSwpppSiteRasterFrameOptions } from './swppp_site_map_renderer.ts'

export type ScoutSwpppSiteMapMountOptions = ScoutSwpppSiteRasterFrameOptions & {
  attributionLabel: string
  attributionUrl: string
  timeoutMs?: number
  onReady?: () => void
  onError?: (error: Error) => void
  embeddedTiles?: Record<string, string>
}

const DEFAULT_TIMEOUT_MS = 7000
const PNG_DATA_URL_PREFIX = 'data:image/png;base64,'

async function decodeRasterTile(dataUrl: string) {
  if (!dataUrl.startsWith(PNG_DATA_URL_PREFIX)) throw new Error('Scout embedded raster tile is invalid')
  const binary = atob(dataUrl.slice(PNG_DATA_URL_PREFIX.length))
  const bytes = new Uint8Array(binary.length)
  for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index)
  return await createImageBitmap(new Blob([bytes], { type: 'image/png' }))
}

export function mountScoutSwpppSiteMap(container: HTMLElement, data: ScoutSandboxSwpppSiteMap, options: ScoutSwpppSiteMapMountOptions) {
  let destroyed = false
  let generation = 0
  let timeout: ReturnType<typeof setTimeout> | null = null
  let lastWidth = -1
  let lastHeight = -1
  const clearTimer = () => { if (timeout !== null) { clearTimeout(timeout); timeout = null } }

  const render = (force = false) => {
    if (destroyed) return
    const frame = buildScoutSwpppSiteRasterFrame(data, container.clientWidth, container.clientHeight, options)
    if (!force && frame.width === lastWidth && frame.height === lastHeight) return
    lastWidth = frame.width
    lastHeight = frame.height
    clearTimer()
    generation += 1
    const current = generation
    container.replaceChildren()
    let loaded = 0
    let settled = 0
    let ready = false
    const markReady = () => { if (!destroyed && current === generation && !ready) { ready = true; clearTimer(); options.onReady?.() } }
    const markFailed = () => { if (!destroyed && current === generation && !ready) { clearTimer(); options.onError?.(new Error('Scout raster tiles did not load')) } }

    const embeddedFrame = frame.tiles.length > 0 && frame.tiles.every((tile) => options.embeddedTiles?.[tile.url])
    if (embeddedFrame) {
      const canvas = document.createElement('canvas')
      canvas.width = frame.width
      canvas.height = frame.height
      canvas.style.position = 'absolute'
      canvas.style.inset = '0'
      canvas.style.width = `${frame.width}px`
      canvas.style.height = `${frame.height}px`
      container.appendChild(canvas)
      const context = canvas.getContext('2d')
      if (!context) return markFailed()
      void Promise.allSettled(frame.tiles.map(async (tile) => {
        const bitmap = await decodeRasterTile(options.embeddedTiles![tile.url])
        if (!destroyed && current === generation) {
          context.drawImage(bitmap, tile.left, tile.top, 256, 256)
          loaded += 1
        }
        bitmap.close()
      })).then(() => {
        settled = frame.tiles.length
        if (loaded > 0) markReady()
        else markFailed()
      })
    } else {
      for (const tile of frame.tiles) {
        const image = document.createElement('img')
        image.alt = ''
        image.draggable = false
        image.decoding = 'async'
        image.loading = 'eager'
        image.referrerPolicy = 'origin'
        image.src = tile.url
        image.style.left = `${tile.left}px`
        image.style.top = `${tile.top}px`
        image.addEventListener('load', () => { if (!destroyed && current === generation) { loaded += 1; settled += 1; if (loaded === 1) markReady() } }, { once: true })
        image.addEventListener('error', () => { if (!destroyed && current === generation) { settled += 1; if (settled === frame.tiles.length && loaded === 0) markFailed() } }, { once: true })
        container.appendChild(image)
      }
    }

    const marker = document.createElement('span')
    marker.className = 'scout-site-marker'
    marker.style.left = `${frame.marker.left}px`
    marker.style.top = `${frame.marker.top}px`
    marker.title = data.site_name
    marker.setAttribute('aria-hidden', 'true')
    const dot = document.createElement('span')
    dot.className = 'scout-site-marker-dot'
    marker.appendChild(dot)
    container.appendChild(marker)

    const attribution = document.createElement('span')
    attribution.className = 'scout-map-attribution'
    const link = document.createElement('a')
    link.href = options.attributionUrl
    link.target = '_blank'
    link.rel = 'noreferrer'
    link.textContent = options.attributionLabel
    attribution.appendChild(link)
    container.appendChild(attribution)

    if (frame.tiles.length === 0) return markFailed()
    timeout = setTimeout(() => loaded > 0 ? markReady() : markFailed(), options.timeoutMs ?? DEFAULT_TIMEOUT_MS)
  }

  render(true)
  return {
    resize: () => render(false),
    destroy: () => { if (!destroyed) { destroyed = true; generation += 1; clearTimer(); container.replaceChildren() } },
  }
}
