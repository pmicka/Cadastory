import type { ScoutSandboxWaterTankMap } from './contract.ts'
import {
  buildScoutCenteredPointRasterFrame,
  type ScoutRasterFrame,
  type ScoutSingleSiteMapRendererOptions,
} from './single_site_map_renderer.ts'
import { buildScoutWaterTankPointMapModel } from './water_tank_map_model.ts'

export type ScoutWaterTankRasterFrameOptions = Pick<
  ScoutSingleSiteMapRendererOptions,
  'tileUrlTemplate' | 'minZoom' | 'maxZoom'
>

export function buildScoutWaterTankRasterFrame(
  data: ScoutSandboxWaterTankMap,
  width: number,
  height: number,
  options: ScoutWaterTankRasterFrameOptions,
): ScoutRasterFrame {
  const model = buildScoutWaterTankPointMapModel(data)
  return buildScoutCenteredPointRasterFrame(
    model.center,
    width,
    height,
    {
      ...options,
      zoom: model.zoom,
    },
  )
}
