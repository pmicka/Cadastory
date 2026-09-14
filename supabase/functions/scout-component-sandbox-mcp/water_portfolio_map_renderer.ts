import type { ScoutSandboxWaterUtilityPortfolioMap, ScoutWaterUtilityPortfolioMorphology } from './water_portfolio_map_model.ts'

const TILE_SIZE = 256
const MAX_MERCATOR_LAT = 85.05112878
const DEFAULT_MIN_ZOOM = 5
const DEFAULT_MAX_ZOOM = 18
const DEFAULT_PADDING_PX = 24

export type ScoutWaterUtilityPortfolioRasterTile = {
  z: number
  x: number
  y: number
  left: number
  top: number
  url: string
}

export type ScoutWaterUtilityPortfolioMarker = {
  left: number
  top: number
  name: string
  morphology: ScoutWaterUtilityPortfolioMorphology
  serviceState: 'unverified' | 'documented_not_in_service'
  historicalRehab: boolean
}

export type ScoutWaterUtilityPortfolioRasterFrame = {
  zoom: number
  width: number
  height: number
  tiles: ScoutWaterUtilityPortfolioRasterTile[]
  markers: ScoutWaterUtilityPortfolioMarker[]
}

export type ScoutWaterUtilityPortfolioRasterFrameOptions = {
  tileUrlTemplate: string
  minZoom?: number
  maxZoom?: number
  paddingPx?: number
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

function fitZoom(
  data: ScoutSandboxWaterUtilityPortfolioMap,
  width: number,
  height: number,
  minZoom: number,
  maxZoom: number,
  paddingPx: number,
) {
  const usableWidth = Math.max(1, width - paddingPx * 2)
  const usableHeight = Math.max(1, height - paddingPx * 2)
  const west = worldX(data.bounds.west)
  const east = worldX(data.bounds.east)
  const north = worldY(data.bounds.north)
  const south = worldY(data.bounds.south)
  const spanX = Math.max(1e-12, Math.abs(east - west))
  const spanY = Math.max(1e-12, Math.abs(south - north))

  for (let zoom = maxZoom; zoom >= minZoom; zoom -= 1) {
    const world = TILE_SIZE * Math.pow(2, zoom)
    if (spanX * world <= usableWidth && spanY * world <= usableHeight) return zoom
  }
  return minZoom
}

export function buildScoutWaterUtilityPortfolioRasterFrame(
  data: ScoutSandboxWaterUtilityPortfolioMap,
  width: number,
  height: number,
  options: ScoutWaterUtilityPortfolioRasterFrameOptions,
): ScoutWaterUtilityPortfolioRasterFrame {
  const frameWidth = Math.max(280, Math.round(width || 0))
  const frameHeight = Math.max(180, Math.round(height || 0))
  const minZoom = options.minZoom ?? DEFAULT_MIN_ZOOM
  const maxZoom = options.maxZoom ?? DEFAULT_MAX_ZOOM
  const paddingPx = options.paddingPx ?? DEFAULT_PADDING_PX
  const zoom = fitZoom(data, frameWidth, frameHeight, minZoom, maxZoom, paddingPx)
  const world = TILE_SIZE * Math.pow(2, zoom)
  const westX = worldX(data.bounds.west)
  const eastX = worldX(data.bounds.east)
  const northY = worldY(data.bounds.north)
  const southY = worldY(data.bounds.south)
  const centerPxX = ((westX + eastX) / 2) * world
  const centerPxY = ((northY + southY) / 2) * world
  const left = centerPxX - frameWidth / 2
  const top = centerPxY - frameHeight / 2
  const startX = Math.floor(left / TILE_SIZE)
  const endX = Math.floor((left + frameWidth - 1) / TILE_SIZE)
  const startY = Math.floor(top / TILE_SIZE)
  const endY = Math.floor((top + frameHeight - 1) / TILE_SIZE)
  const tileCount = Math.pow(2, zoom)
  const tiles: ScoutWaterUtilityPortfolioRasterTile[] = []

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

  const markers: ScoutWaterUtilityPortfolioMarker[] = []
  for (const member of data.members) {
    if (member.point.type !== 'Point') continue
    const [lon, lat] = member.point.coordinates
    markers.push({
      left: worldX(lon) * world - left,
      top: worldY(lat) * world - top,
      name: member.name,
      morphology: member.morphology,
      serviceState: member.service_state,
      historicalRehab: member.signals.some((signal) => signal.kind === 'historical_rehab_record'),
    })
  }

  return { zoom, width: frameWidth, height: frameHeight, tiles, markers }
}
