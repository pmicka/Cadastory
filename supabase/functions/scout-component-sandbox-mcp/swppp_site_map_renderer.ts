import type { ScoutSandboxSwpppSiteMap } from './swppp_site_map_model.ts'
import { buildScoutSwpppSitePointMapModel } from './swppp_site_point_map_model.ts'

const TILE_SIZE = 256
const MAX_MERCATOR_LAT = 85.05112878
const DEFAULT_MIN_ZOOM = 5
const DEFAULT_MAX_ZOOM = 18

export type ScoutSwpppSiteRasterTile = {
  z: number
  x: number
  y: number
  left: number
  top: number
  url: string
}

export type ScoutSwpppSiteRasterFrame = {
  zoom: number
  width: number
  height: number
  tiles: ScoutSwpppSiteRasterTile[]
  marker: { left: number; top: number }
}

export type ScoutSwpppSiteRasterFrameOptions = {
  tileUrlTemplate: string
  minZoom?: number
  maxZoom?: number
}

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

function tileUrl(template: string, z: number, x: number, y: number) {
  return template
    .replace('{z}', String(z))
    .replace('{x}', String(x))
    .replace('{y}', String(y))
}

export function buildScoutSwpppSiteRasterFrame(
  data: ScoutSandboxSwpppSiteMap,
  width: number,
  height: number,
  options: ScoutSwpppSiteRasterFrameOptions,
): ScoutSwpppSiteRasterFrame {
  const model = buildScoutSwpppSitePointMapModel(data)
  const frameWidth = Math.max(280, Math.round(width || 0))
  const frameHeight = Math.max(180, Math.round(height || 0))
  const minZoom = options.minZoom ?? DEFAULT_MIN_ZOOM
  const maxZoom = options.maxZoom ?? DEFAULT_MAX_ZOOM
  const zoom = Math.max(minZoom, Math.min(maxZoom, Math.round(model.zoom)))
  const world = TILE_SIZE * Math.pow(2, zoom)
  const centerPxX = worldX(model.center.lon) * world
  const centerPxY = worldY(model.center.lat) * world
  const left = centerPxX - frameWidth / 2
  const top = centerPxY - frameHeight / 2
  const startX = Math.floor(left / TILE_SIZE)
  const endX = Math.floor((left + frameWidth - 1) / TILE_SIZE)
  const startY = Math.floor(top / TILE_SIZE)
  const endY = Math.floor((top + frameHeight - 1) / TILE_SIZE)
  const tileCount = Math.pow(2, zoom)
  const tiles: ScoutSwpppSiteRasterTile[] = []

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

  return {
    zoom,
    width: frameWidth,
    height: frameHeight,
    tiles,
    marker: {
      left: frameWidth / 2,
      top: frameHeight / 2,
    },
  }
}
