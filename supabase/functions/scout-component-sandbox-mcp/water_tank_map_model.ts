import type { ScoutSandboxWaterTankMap } from './contract.ts'

export const SCOUT_WATER_TANK_POINT_ZOOM = 17

export type ScoutWaterTankPointMapModel = {
  contract_version: 'water_tank_single_site_map_v1'
  opportunity_type: 'water_tank'
  tank_id: string
  candidate_key: string
  name: string
  system_name: string
  center: {
    lon: number
    lat: number
  }
  marker: {
    lon: number
    lat: number
    source: 'kentucky_wris_water_tank'
    source_slug: 'ky-kia-water-tanks'
    source_name: string
    source_authority: string
    source_native_id: string
    wris_fid: string
    pwsid: string
    retrieved_at: string
  }
  zoom: number
}

export function buildScoutWaterTankPointMapModel(
  data: ScoutSandboxWaterTankMap,
): ScoutWaterTankPointMapModel {
  const lon = data.site_point.lon
  const lat = data.site_point.lat

  return {
    contract_version: 'water_tank_single_site_map_v1',
    opportunity_type: 'water_tank',
    tank_id: data.tank_id,
    candidate_key: data.candidate_key,
    name: data.name,
    system_name: data.system_name,
    center: { lon, lat },
    marker: {
      lon,
      lat,
      source: 'kentucky_wris_water_tank',
      source_slug: 'ky-kia-water-tanks',
      source_name: data.site_point.source_name,
      source_authority: data.site_point.source_authority,
      source_native_id: data.site_point.source_native_id,
      wris_fid: data.site_point.wris_fid,
      pwsid: data.site_point.pwsid,
      retrieved_at: data.site_point.retrieved_at,
    },
    zoom: SCOUT_WATER_TANK_POINT_ZOOM,
  }
}
