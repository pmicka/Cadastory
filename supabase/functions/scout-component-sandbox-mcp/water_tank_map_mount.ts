import type { ScoutSandboxWaterTankMap } from './contract.ts'
import { buildScoutWaterTankRasterFrame, type ScoutWaterTankRasterFrameOptions } from './water_tank_map_renderer.ts'

const DEFAULT_TIMEOUT_MS = 7000

export type ScoutWaterTankMapMountOptions = ScoutWaterTankRasterFrameOptions & {
  attributionLabel: string
  attributionUrl: string
  timeoutMs?: number
  onError?: (error: Error) => void
  onReady?: () => void
}

export type ScoutWaterTankMapMountHandle = {
  destroy: () => void
  resize: () => void
}

export function mountScoutWaterTankMap(
  container: HTMLElement,
  data: ScoutSandboxWaterTankMap,
  options: ScoutWaterTankMapMountOptions,
): ScoutWaterTankMapMountHandle {
  let destroyed = false
  let renderGeneration = 0
  let timeout: ReturnType<typeof setTimeout> | null = null
  let lastFrameWidth = -1
  let lastFrameHeight = -1

  const clearTimeoutIfNeeded = () => {
    if (timeout !== null) {
      clearTimeout(timeout)
      timeout = null
    }
  }

  const render = (force = false) => {
    if (destroyed) return

    const frame = buildScoutWaterTankRasterFrame(
      data,
      container.clientWidth,
      container.clientHeight,
      options,
    )
    if (!force && frame.width === lastFrameWidth && frame.height === lastFrameHeight) return
    lastFrameWidth = frame.width
    lastFrameHeight = frame.height

    clearTimeoutIfNeeded()
    renderGeneration += 1
    const generation = renderGeneration
    container.replaceChildren()
    let loadedTiles = 0
    let settledTiles = 0
    let readySent = false

    const finishReady = () => {
      if (destroyed || generation !== renderGeneration || readySent) return
      readySent = true
      clearTimeoutIfNeeded()
      options.onReady?.()
    }

    const finishError = () => {
      if (destroyed || generation !== renderGeneration || readySent) return
      clearTimeoutIfNeeded()
      options.onError?.(new Error('Scout raster tiles did not load'))
    }

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
      image.addEventListener('load', () => {
        if (destroyed || generation !== renderGeneration) return
        loadedTiles += 1
        settledTiles += 1
        if (loadedTiles === 1) finishReady()
      }, { once: true })
      image.addEventListener('error', () => {
        if (destroyed || generation !== renderGeneration) return
        settledTiles += 1
        if (settledTiles === frame.tiles.length && loadedTiles === 0) finishError()
      }, { once: true })
      container.appendChild(image)
    }

    const marker = document.createElement('span')
    marker.className = 'scout-site-marker'
    marker.style.left = `${frame.marker.left}px`
    marker.style.top = `${frame.marker.top}px`
    marker.title = data.name
    marker.setAttribute('aria-hidden', 'true')
    const markerDot = document.createElement('span')
    markerDot.className = 'scout-site-marker-dot'
    marker.appendChild(markerDot)
    container.appendChild(marker)

    const attribution = document.createElement('span')
    attribution.className = 'scout-map-attribution'
    const attributionLink = document.createElement('a')
    attributionLink.href = options.attributionUrl
    attributionLink.target = '_blank'
    attributionLink.rel = 'noreferrer'
    attributionLink.textContent = options.attributionLabel
    attribution.appendChild(attributionLink)
    container.appendChild(attribution)

    if (frame.tiles.length === 0) {
      finishError()
      return
    }

    timeout = setTimeout(() => {
      if (loadedTiles > 0) finishReady()
      else finishError()
    }, options.timeoutMs ?? DEFAULT_TIMEOUT_MS)
  }

  render(true)

  return {
    resize() {
      render(false)
    },
    destroy() {
      if (destroyed) return
      destroyed = true
      renderGeneration += 1
      clearTimeoutIfNeeded()
      container.replaceChildren()
    },
  }
}
