
import type{ScoutSandboxSingleSiteType}from'../_shared/scout_sandbox_manifest.ts'
import{normalizeScoutSandboxSingleSiteMap,normalizeScoutSandboxWaterTankMap}from'./contract.ts'
import{mountScoutSingleSiteMap}from'./single_site_map_renderer.ts'
import{mountScoutWaterTankMap}from'./water_tank_map_mount.ts'
import{normalizeScoutSwpppSiteTransport}from'./swppp_site_transport.ts'
import{mountScoutSwpppSiteMap}from'./swppp_site_map_mount.ts'
import{normalizeScoutSandboxTelecomChangeMap}from'./telecom_change_map_model.ts'
import{mountScoutTelecomChangeMap}from'./telecom_change_map_mount.ts'
export const SCOUT_SANDBOX_SINGLE_SITE_VIEW_IMPLEMENTATIONS={
 premium_exterior:{normalizeMap:(value:unknown)=>normalizeScoutSandboxSingleSiteMap(value),mount:mountScoutSingleSiteMap,ariaLabel:(map:any)=>`Site map for ${map.name}`},
 water_tank:{normalizeMap:(value:unknown)=>normalizeScoutSandboxWaterTankMap(value),mount:mountScoutWaterTankMap,ariaLabel:(map:any)=>`Site map for ${map.name}`},
 swppp_site:{normalizeMap:(value:unknown,onReject?:any)=>normalizeScoutSwpppSiteTransport(value,onReject),mount:mountScoutSwpppSiteMap,ariaLabel:(map:any)=>`Permit location map for ${map.site_name}`},
 telecom_change:{normalizeMap:(value:unknown)=>normalizeScoutSandboxTelecomChangeMap(value),mount:mountScoutTelecomChangeMap,ariaLabel:(map:any)=>`FCC ASR registration point map for ${map.registration_number}`},
}as const satisfies Record<ScoutSandboxSingleSiteType,{normalizeMap:any;mount:any;ariaLabel:(map:any)=>string}>
export function scoutSandboxSingleSiteViewImplementation(type:ScoutSandboxSingleSiteType){return SCOUT_SANDBOX_SINGLE_SITE_VIEW_IMPLEMENTATIONS[type] as any}
