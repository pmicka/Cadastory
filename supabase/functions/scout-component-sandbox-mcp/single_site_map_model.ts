import type { ScoutSandboxSingleSiteMap } from './contract.ts'

export type ScoutSingleSiteMapBounds = [[number, number], [number, number]]

export type ScoutSingleSiteFootprintFeatureCollection = {
  type: 'FeatureCollection'
  features: Array<{
    type: 'Feature'
    id: string
    properties: {
      opportunity_id: string
      opportunity_type: 'premium_exterior'
      name: string
      geometry_source_slug: string
      linkage_status: 'reconciled_existing_evidence'
    }
    geometry: ScoutSandboxSingleSiteMap['footprint']['geometry']
  }>
}

export type ScoutSingleSiteMapRenderModel = {
  bounds: ScoutSingleSiteMapBounds
  center: [number, number]
  footprint: ScoutSingleSiteFootprintFeatureCollection
}

export function buildScoutSingleSiteMapRenderModel(data: ScoutSandboxSingleSiteMap): ScoutSingleSiteMapRenderModel {
  const { west, south, east, north } = data.footprint.bounds
  return {
    bounds: [[west, south], [east, north]],
    center: [(west + east) / 2, (south + north) / 2],
    footprint: {
      type: 'FeatureCollection',
      features: [{
        type: 'Feature',
        id: data.opportunity_id,
        properties: {
          opportunity_id: data.opportunity_id,
          opportunity_type: 'premium_exterior',
          name: data.name,
          geometry_source_slug: data.footprint.source.slug,
          linkage_status: 'reconciled_existing_evidence',
        },
        geometry: data.footprint.geometry,
      }],
    },
  }
}
