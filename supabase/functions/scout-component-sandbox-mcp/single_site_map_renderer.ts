import type { ScoutSandboxSingleSiteMap } from './contract.ts'

const TILE_SIZE = 256
const MAX_MERCATOR_LAT = 85.05112878
const DEFAULT_MIN_ZOOM = 5
const DEFAULT_MAX_ZOOM = 18
const DEFAULT_TIMEOUT_MS = 7000

export type ScoutSingleSiteMapRendererOptions = {
  tileUrlTemplate: string
  attributionLabel: string
  attributionUrl: string
  minZoom?: number
  maxZoom?: number
  timeoutMs?: number
  onError?: (error: Error) => void
  onReady?: () => void
}

export type ScoutRasterTile = {
  z: number
  x: number
  y: number
  left: number
  top: number
  url: string
}

export type ScoutRasterFrame = {
  zoom: number
  width: number
  height: number
  tiles: ScoutRasterTile[]
  marker: { left: number; top: number }
}

export type ScoutSingleSiteMapRendererHandle = {
  destroy: () => void
  resize: () => void
}

type Bounds = { west: number; south: number; east: number; north: number }

function clampLat(lat: number) {
  return Math.max(-MAX_MERCATOR_LAT, Math.min(MAX_MERCATOR_LAT, lat))
}

function worldX(lon: number) {
  return (lon + 180) / 360
}

function worldY(lat: number) {
  const radians = clampLat(lat) * Math.PI / 180
  return (1 - Math.log(Math.tan(radians) + 1 / Math.cos(radians)) / Math.PI) / 2
}

function expandSingleSiteBounds(bounds: Bounds): Bounds {
  let { west, south, east, north } = bounds
  const centerLat = (south + north) / 2
  const metersPerDegreeLat = 111320
  const metersPerDegreeLon = Math.max(15000, 111320 * Math.cos(centerLat * Math.PI / 180))
  const widthM = (east - west) * metersPerDegreeLon
  const heightM = (north - south) * metersPerDegreeLat

  if (widthM < 180) {
    const add = (180 - widthM) / metersPerDegreeLon / 2
    west -= add
    east += add
  }
  if (heightM < 150) {
    const add = (150 - heightM) / metersPerDegreeLat / 2
    south -= add
    north += add
  }

  const lonPad = (east - west) * 0.05
  const latPad = (north - south) * 0.05
  return {
    west: west - lonPad,
    south: south - latPad,
    east: east + lonPad,
    north: north + latPad,
  }
}

function fitZoom(bounds: Bounds, width: number, height: number, minZoom: number, maxZoom: number) {
  const xSpan = Math.abs(worldX(bounds.east) - worldX(bounds.west))
  const ySpan = Math.abs(worldY(bounds.north) - worldY(bounds.south))
  for (let zoom = maxZoom; zoom >= minZoom; zoom -= 1) {
    const world = TILE_SIZE * Math.pow(2, zoom)
    if (xSpan * world <= width * 0.94 && ySpan * world <= height * 0.90) return zoom
  }
  return minZoom
}

function tileUrl(template: string, z: number, x: number, y: number) {
  return template
    .replace('{z}', String(z))
    .replace('{x}', String(x))
    .replace('{y}', String(y))
}

export function buildScoutSingleSiteRasterFrame(
  data: ScoutSandboxSingleSiteMap,
  width: number,
  height: number,
  options: Pick<ScoutSingleSiteMapRendererOptions, 'tileUrlTemplate' | 'minZoom' | 'maxZoom'>,
): ScoutRasterFrame {
  const frameWidth = Math.max(280, Math.round(width || 0))
  const frameHeight = Math.max(180, Math.round(height || 0))
  const bounds = expandSingleSiteBounds(data.footprint.bounds)
  const minZoom = options.minZoom ?? DEFAULT_MIN_ZOOM
  const maxZoom = options.maxZoom ?? DEFAULT_MAX_ZOOM
  const zoom = fitZoom(bounds, frameWidth, frameHeight, minZoom, maxZoom)
  const world = TILE_SIZE * Math.pow(2, zoom)
  const centerLon = (bounds.west + bounds.east) / 2
  const centerLat = (bounds.south + bounds.north) / 2
  const centerPxX = worldX(centerLon) * world
  const centerPxY = worldY(centerLat) * world
  const left = centerPxX - frameWidth / 2
  const top = centerPxY - frameHeight / 2
  const startX = Math.floor(left / TILE_SIZE)
  const endX = Math.floor((left + frameWidth - 1) / TILE_SIZE)
  const startY = Math.floor(top / TILE_SIZE)
  const endY = Math.floor((top + frameHeight - 1) / TILE_SIZE)
  const tileCount = Math.pow(2, zoom)
  const tiles: ScoutRasterTile[] = []

  for (let tx = startX; tx <= endX; tx += 1) {
    for (let ty = startY; ty <= endY; ty += 1) {
      if (ty < 0 || ty >= tileCount) continue
      const wrappedX = ((tx % tileCount) + tileCount) % tileCount
      tiles.push({
        z: zoom,
        x: wrappedX,
        y: ty,
        left: tx * TILE_SIZE - left,
        top: ty * TILE_SIZE - top,
        url: tileUrl(options.tileUrlTemplate, zoom, wrappedX, ty),
      })
    }
  }

  const markerLon = (data.footprint.bounds.west + data.footprint.bounds.east) / 2
  const markerLat = (data.footprint.bounds.south + data.footprint.bounds.north) / 2
  return {
    zoom,
    width: frameWidth,
    height: frameHeight,
    tiles,
    marker: {
      left: worldX(markerLon) * world - left,
      top: worldY(markerLat) * world - top,
    },
  }
}

export function mountScoutSingleSiteMap(
  container: HTMLElement,
  data: ScoutSandboxSingleSiteMap,
  options: ScoutSingleSiteMapRendererOptions,
): ScoutSingleSiteMapRendererHandle {
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

    const frame = buildScoutSingleSiteRasterFrame(
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
