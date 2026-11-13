import { farmWatchMaterializationExpiresAt } from './farm-watch-materialization-expiry.ts'
import { FARM_WATCH_TERRAIN_PRODUCT } from './farm-watch-terrain-contract.ts'
import { FARM_WATCH_LIDAR_SOURCE_PRODUCT } from './farm-watch-lidar-source.ts'
import { FARM_WATCH_LIDAR_PHYSICAL_PRODUCT } from './farm-watch-lidar-physical-contract.ts'
import { FARM_WATCH_LEAF_OFF_PRODUCT } from './farm-watch-leaf-off-contract.ts'
import { FARM_WATCH_STRUCTURE_SYNTHESIS_PRODUCT } from './farm-watch-structure-synthesis-contract.ts'
import { FARM_WATCH_LANDSCAPE_STRUCTURE_PRODUCT } from './farm-watch-landscape-structure-contract.ts'
import { FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT } from './farm-watch-study-vegetation-height-contract.ts'
import { FARM_WATCH_TERRAIN_FORM_PRODUCT, FARM_WATCH_SPATIAL_PATTERN_PRODUCT } from './farm-watch-neutral-primitives-contract.ts'
import { FARM_WATCH_SOLAR_TERRAIN_PRODUCT, FARM_WATCH_SOLAR_EXPOSURE_PRODUCT } from './farm-watch-solar-exposure-contract.ts'
import { FARM_WATCH_HORIZONTAL_VISIBILITY_PRODUCT } from './farm-watch-horizontal-visibility-contract.ts'
import { FARM_WATCH_MAST_CAPACITY_PRODUCT } from './farm-watch-mast-capacity-contract.ts'
import { FARM_WATCH_THERMAL_EXPOSURE_PRODUCT } from './farm-watch-thermal-exposure-contract.ts'

const stable = [
  FARM_WATCH_TERRAIN_PRODUCT, FARM_WATCH_LIDAR_SOURCE_PRODUCT,
  FARM_WATCH_LIDAR_PHYSICAL_PRODUCT, FARM_WATCH_LEAF_OFF_PRODUCT,
  FARM_WATCH_STRUCTURE_SYNTHESIS_PRODUCT, FARM_WATCH_LANDSCAPE_STRUCTURE_PRODUCT,
  FARM_WATCH_STUDY_VEGETATION_HEIGHT_PRODUCT, FARM_WATCH_TERRAIN_FORM_PRODUCT,
  FARM_WATCH_SPATIAL_PATTERN_PRODUCT, FARM_WATCH_SOLAR_TERRAIN_PRODUCT,
  FARM_WATCH_HORIZONTAL_VISIBILITY_PRODUCT, FARM_WATCH_MAST_CAPACITY_PRODUCT,
]
const completedAt = new Date('2026-09-30T00:00:00Z')

Deno.test('stable source snapshots do not acquire a calendar expiry', () => {
  for (const product of stable) {
    if (farmWatchMaterializationExpiresAt(completedAt, product.refreshDays) !== null) {
      throw new Error(product.productKind + ' still expires with age')
    }
  }
})

Deno.test('worker contracts and database stable-product allowlist agree exactly', async () => {
  const sql = await Deno.readTextFile(new URL('../../migrations/20261113222551_farm_watch_static_product_validity_v1.sql', import.meta.url))
  const allowlist = sql.split('select coalesce(p_product_kind in (')[1].split('), false)')[0]
  const kinds = [...allowlist.matchAll(/'([^']+)'/g)].map((match) => match[1]).sort()
  if (JSON.stringify(kinds) !== JSON.stringify(stable.map((product) => product.productKind).sort())) {
    throw new Error('database and worker expiry policies differ')
  }
})

Deno.test('dated solar and weather products retain their retention policy', () => {
  for (const product of [FARM_WATCH_SOLAR_EXPOSURE_PRODUCT, FARM_WATCH_THERMAL_EXPOSURE_PRODUCT]) {
    if (farmWatchMaterializationExpiresAt(completedAt, product.refreshDays) === null) {
      throw new Error(product.productKind + ' unexpectedly lost its retention policy')
    }
  }
  // Date, forcing, and dependency validity remain enforced by the canonical reader.
  if (farmWatchMaterializationExpiresAt(completedAt, 1) !== '2026-10-01T00:00:00.000Z') {
    throw new Error('temporal expiry calculation changed')
  }
})

Deno.test('invalid finite expiry configurations fail closed', () => {
  for (const value of [0, -1, NaN, Infinity]) {
    let failed = false
    try { farmWatchMaterializationExpiresAt(completedAt, value) } catch { failed = true }
    if (!failed) throw new Error('invalid expiry accepted')
  }
})
