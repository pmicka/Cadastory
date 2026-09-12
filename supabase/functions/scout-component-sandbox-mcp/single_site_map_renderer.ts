import { Map as MapLibreMap, type StyleSpecification } from 'maplibre-gl'
import 'maplibre-gl/dist/maplibre-gl.css'
import type { ScoutSandboxSingleSiteMap } from './contract.ts'
import { buildScoutSingleSiteMapRenderModel } from './single_site_map_model.ts'

export const SCOUT_SINGLE_SITE_SOURCE_ID = 'scout-single-site-footprint'
export const SCOUT_SINGLE_SITE_FILL_LAYER_ID = 'scout-single-site-footprint-fill'
export const SCOUT_SINGLE_SITE_LINE_LAYER_ID = 'scout-single-site-footprint-line'

export type ScoutSingleSiteMapRendererOptions = {
  style: string | StyleSpecification
  padding?: number
  maxZoom?: number
  onError?: (error: Error) => void
}

export type ScoutSingleSiteMapRendererHandle = {
  map: MapLibreMap
  destroy: () => void
}

function toError(value: unknown) {
  return value instanceof Error ? value : new Error('Scout single-site map renderer error')
}

export function mountScoutSingleSiteMap(
  container: HTMLElement,
  data: ScoutSandboxSingleSiteMap,
  options: ScoutSingleSiteMapRendererOptions,
): ScoutSingleSiteMapRendererHandle {
  const model = buildScoutSingleSiteMapRenderModel(data)
  let destroyed = false

  const map = new MapLibreMap({
    container,
    style: options.style,
    center: model.center,
    zoom: 17,
    interactive: false,
    attributionControl: {},
    maplibreLogo: false,
    renderWorldCopies: false,
    fadeDuration: 0,
    trackResize: true,
  })

  map.on('error', (event) => {
    if (!destroyed) options.onError?.(toError(event.error))
  })

  map.once('load', () => {
    if (destroyed) return

    map.addSource(SCOUT_SINGLE_SITE_SOURCE_ID, {
      type: 'geojson',
      data: model.footprint,
    })

    map.addLayer({
      id: SCOUT_SINGLE_SITE_FILL_LAYER_ID,
      type: 'fill',
      source: SCOUT_SINGLE_SITE_SOURCE_ID,
      paint: {
        'fill-color': '#4d6b52',
        'fill-opacity': 0.28,
      },
    })

    map.addLayer({
      id: SCOUT_SINGLE_SITE_LINE_LAYER_ID,
      type: 'line',
      source: SCOUT_SINGLE_SITE_SOURCE_ID,
      layout: {
        'line-cap': 'round',
        'line-join': 'round',
      },
      paint: {
        'line-color': '#263128',
        'line-width': 2,
      },
    })

    map.fitBounds(model.bounds, {
      padding: options.padding ?? 24,
      maxZoom: options.maxZoom ?? 19,
      duration: 0,
    })
  })

  return {
    map,
    destroy() {
      if (destroyed) return
      destroyed = true
      map.remove()
    },
  }
}
