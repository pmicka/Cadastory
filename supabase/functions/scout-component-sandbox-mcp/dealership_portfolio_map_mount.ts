import type { ScoutSandboxDealershipPortfolioMap } from './dealership_portfolio_map_model.ts'
import {
  buildScoutDealershipPortfolioRasterFrame,
  type ScoutDealershipPortfolioRasterFrameOptions,
} from './dealership_portfolio_map_renderer.ts'

const DEFAULT_TIMEOUT_MS = 7000
const PNG_DATA_URL_PREFIX = 'data:image/png;base64,'
const SINGLE_BUILDING_COLOR = '#4d7c5d'
const MULTI_BUILDING_COLOR = '#b96a2d'

async function decodeEmbeddedRasterTile(dataUrl: string) {
  if (!dataUrl.startsWith(PNG_DATA_URL_PREFIX)) throw new Error('Scout embedded raster tile is invalid')
  const binary = atob(dataUrl.slice(PNG_DATA_URL_PREFIX.length))
  const bytes = new Uint8Array(binary.length)
  for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index)
  return await createImageBitmap(new Blob([bytes], { type: 'image/png' }))
}

export type ScoutDealershipPortfolioMapMountOptions = ScoutDealershipPortfolioRasterFrameOptions & {
  attributionLabel: string
  attributionUrl: string
  timeoutMs?: number
  embeddedTiles?: Record<string, string>
  onError?: (error: Error) => void
  onReady?: () => void
}

export type ScoutDealershipPortfolioMapMountHandle = {
  destroy: () => void
  resize: () => void
}

export function mountScoutDealershipPortfolioMap(
  container: HTMLElement,
  data: ScoutSandboxDealershipPortfolioMap,
  options: ScoutDealershipPortfolioMapMountOptions,
): ScoutDealershipPortfolioMapMountHandle {
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
    const frame = buildScoutDealershipPortfolioRasterFrame(data, container.clientWidth, container.clientHeight, options)
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
      if (!context) {
        finishError()
        return
      }
      void Promise.allSettled(frame.tiles.map(async (tile) => {
        const bitmap = await decodeEmbeddedRasterTile(options.embeddedTiles![tile.url])
        if (!destroyed && generation === renderGeneration) {
          context.drawImage(bitmap, tile.left, tile.top, 256, 256)
          loadedTiles += 1
        }
        bitmap.close()
      })).then(() => {
        settledTiles = frame.tiles.length
        if (loadedTiles > 0) finishReady()
        else finishError()
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
    }

    for (const markerData of frame.markers) {
      const multiBuilding = markerData.resolutionState === 'multi_building_resolved'
      const color = multiBuilding ? MULTI_BUILDING_COLOR : SINGLE_BUILDING_COLOR
      const marker = document.createElement('span')
      marker.className = 'scout-portfolio-marker'
      marker.style.left = `${markerData.left}px`
      marker.style.top = `${markerData.top}px`
      marker.style.setProperty('--scout-portfolio-marker-color', color)
      marker.style.backgroundColor = color
      if (multiBuilding) {
        marker.style.outline = '1px solid #263128'
        marker.style.outlineOffset = '1px'
      }
      const brands = markerData.brands.length ? ` · ${markerData.brands.join(' / ')}` : ''
      marker.title = `${markerData.name}${brands} · ${markerData.resolvedBuildingCount} resolved building${markerData.resolvedBuildingCount === 1 ? '' : 's'}`
      marker.setAttribute('aria-hidden', 'true')
      container.appendChild(marker)
    }

    const legend = document.createElement('span')
    legend.className = 'scout-portfolio-legend'
    legend.setAttribute('aria-hidden', 'true')
    for (const [label, color] of [['Single-building site', SINGLE_BUILDING_COLOR], ['Multi-building site', MULTI_BUILDING_COLOR]] as const) {
      const item = document.createElement('span')
      item.className = 'scout-portfolio-legend-item'
      const swatch = document.createElement('span')
      swatch.className = 'scout-portfolio-legend-swatch'
      swatch.style.backgroundColor = color
      const text = document.createElement('span')
      text.textContent = label
      item.append(swatch, text)
      legend.appendChild(item)
    }
    const unresolvedCount = data.member_count - data.resolved_member_count
    if (unresolvedCount > 0) {
      const statusKey = document.createElement('span')
      statusKey.className = 'scout-portfolio-legend-status'
      statusKey.textContent = `${unresolvedCount} roster site${unresolvedCount === 1 ? '' : 's'} unresolved · not mapped`
      legend.appendChild(statusKey)
    }
    container.appendChild(legend)

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
