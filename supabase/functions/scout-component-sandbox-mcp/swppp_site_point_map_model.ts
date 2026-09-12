import type { ScoutSandboxSwpppSiteMap } from './swppp_site_map_model.ts'

export const SCOUT_SWPPP_SITE_POINT_ZOOM = 15

export type ScoutSwpppSitePointMapModel = {
  contract_version: 'swppp_site_map_v1'
  opportunity_type: 'swppp_site'
  candidate_key: string
  site_name: string
  location_label: string
  project_reference: string
  center: {
    lon: number
    lat: number
  }
  marker: {
    lon: number
    lat: number
    geometry_type: 'Point'
    semantics: 'authoritative_permit_location_point'
    source_slug: 'ohio-epa-npdes-construction'
    source_authority: string
    source_native_id: string
    permit_number: string
    observed_at: string
  }
  zoom: number
}

export function buildScoutSwpppSitePointMapModel(
  data: ScoutSandboxSwpppSiteMap,
): ScoutSwpppSitePointMapModel {
  const lon = data.site_point.lon
  const lat = data.site_point.lat

  return {
    contract_version: 'swppp_site_map_v1',
    opportunity_type: 'swppp_site',
    candidate_key: data.candidate_key,
    site_name: data.site_name,
    location_label: data.location_label,
    project_reference: data.project_reference,
    center: { lon, lat },
    marker: {
      lon,
      lat,
      geometry_type: 'Point',
      semantics: 'authoritative_permit_location_point',
      source_slug: 'ohio-epa-npdes-construction',
      source_authority: data.source.authority,
      source_native_id: data.source.source_native_id,
      permit_number: data.permit.permit_number,
      observed_at: data.source.last_seen_at,
    },
    zoom: SCOUT_SWPPP_SITE_POINT_ZOOM,
  }
}
