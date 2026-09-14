import type { ScoutSandboxWaterUtilityPortfolioMap, ScoutWaterUtilityPortfolioMorphology } from './water_portfolio_map_model.ts'
import {
  buildScoutWaterUtilityPortfolioRasterFrame,
  type ScoutWaterUtilityPortfolioRasterFrameOptions,
} from './water_portfolio_map_renderer.ts'

const DEFAULT_TIMEOUT_MS = 7000
const PNG_DATA_URL_PREFIX = 'data:image/png;base64,'

const MORPHOLOGY_STYLES: Record<ScoutWaterUtilityPortfolioMorphology, { label: string; color: string }> = {
  elevated: { label: 'Elevated', color: '#3769b2' },
  ground_storage: { label: 'Ground storage', color: '#4d7c5d' },
  standpipe: { label: 'Standpipe', color: '#b96a2d' },
  fluted_column: { label: 'Fluted column', color: '#7656a8' },
  unknown: { label: 'Unclassified', color: '#747d73' },
}

const MORPHOLOGY_ORDER: ScoutWaterUtilityPortfolioMorphology[] = [
  'elevated',
  'ground_storage',
  'standpipe',
  'fluted_column',
  'unknown',
]

async function decodeEmbeddedRasterTile(dataUrl: string) {
  if (!dataUrl.startsWith(PNG_DATA_URL_PREFIX)) throw new Error('Scout embedded raster tile is invalid')
  const binary = atob(dataUrl.slice(PNG_DATA_URL_PREFIX.length))
  const bytes = new Uint8Array(binary.length)
  for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index)
  return await createImageBitmap(new Blob([bytes], { type: 'image/png' }))
}

export type ScoutWaterUtilityPortfolioMapMountOptions = ScoutWaterUtilityPortfolioRasterFrameOptions & {
  attributionLabel: string
  attributionUrl: string
  timeoutMs?: number
  embeddedTiles?: Record<string, string>
  onError?: (error: Error) => void
  onReady?: () => void
}

export type ScoutWaterUtilityPortfolioMapMountHandle = {
  destroy: () => void
  resize: () => void
}

export function mountScoutWaterUtilityPortfolioMap(
  container: HTMLElement,
  data: ScoutSandboxWaterUtilityPortfolioMap,
  options: ScoutWaterUtilityPortfolioMapMountOptions,
): ScoutWaterUtilityPortfolioMapMountHandle {
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
    const frame = buildScoutWaterUtilityPortfolioRasterFrame(data, container.clientWidth, container.clientHeight, options)
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
      const morphology = MORPHOLOGY_STYLES[markerData.morphology]
      const marker = document.createElement('span')
      marker.className = 'scout-portfolio-marker'
      if (markerData.historicalRehab) marker.classList.add('scout-portfolio-marker--historical')
      if (markerData.serviceState === 'documented_not_in_service') marker.classList.add('scout-portfolio-marker--not-in-service')
      marker.style.left = `${markerData.left}px`
      marker.style.top = `${markerData.top}px`
      marker.style.backgroundColor = morphology.color
      marker.title = `${markerData.name} · ${morphology.label}${markerData.serviceState === 'documented_not_in_service' ? ' · documented not in service' : ' · current service state unverified'}${markerData.historicalRehab ? ' · historical rehab record' : ''}`
      marker.setAttribute('aria-hidden', 'true')
      container.appendChild(marker)
    }

    const presentMorphologies = new Set(frame.markers.map((marker) => marker.morphology))
    const legend = document.createElement('span')
    legend.className = 'scout-portfolio-legend'
    legend.setAttribute('aria-hidden', 'true')
    for (const morphologyKey of MORPHOLOGY_ORDER) {
      if (!presentMorphologies.has(morphologyKey)) continue
      const style = MORPHOLOGY_STYLES[morphologyKey]
      const item = document.createElement('span')
      item.className = 'scout-portfolio-legend-item'
      const swatch = document.createElement('span')
      swatch.className = 'scout-portfolio-legend-swatch'
      swatch.style.backgroundColor = style.color
      const text = document.createElement('span')
      text.textContent = style.label
      item.append(swatch, text)
      legend.appendChild(item)
    }
    const statusKey = document.createElement('span')
    statusKey.className = 'scout-portfolio-legend-status'
    statusKey.textContent = 'Ring = historical rehab · Slash = not in service'
    legend.appendChild(statusKey)
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
