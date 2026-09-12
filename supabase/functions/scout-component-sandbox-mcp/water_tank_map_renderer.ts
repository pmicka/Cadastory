import type { ScoutSandboxWaterTankMap } from './contract.ts'
import type {
  ScoutRasterFrame,
  ScoutSingleSiteMapRendererOptions,
} from './single_site_map_renderer.ts'
import { buildScoutWaterTankPointMapModel } from './water_tank_map_model.ts'

const TILE_SIZE = 256
const MAX_MERCATOR_LAT = 85.05112878
const DEFAULT_MIN_ZOOM = 5
const DEFAULT_MAX_ZOOM = 18

export type ScoutWaterTankRasterFrameOptions = Pick<
  ScoutSingleSiteMapRendererOptions,
  'tileUrlTemplate' | 'minZoom' | 'maxZoom'
>

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

export function buildScoutWaterTankRasterFrame(
  data: ScoutSandboxWaterTankMap,
  width: number,
  height: number,
  options: ScoutWaterTankRasterFrameOptions,
): ScoutRasterFrame {
  const model = buildScoutWaterTankPointMapModel(data)
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
  const tiles = []

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
