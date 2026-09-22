import proj4 from 'npm:proj4@2.12.1'
import {
  FARM_WATCH_HORIZONTAL_VISIBILITY_PRODUCT,
  horizontalVisibilitySourceSignature,
  validateHorizontalVisibilityArtifact,
} from './farm-watch-horizontal-visibility-contract.ts'
import { buildHorizontalVisibilityArtifact } from './farm-watch-horizontal-visibility.ts'

function assert(condition: unknown, message = 'assertion failed'): asserts condition {
  if (!condition) throw new Error(message)
}

const EPSG_6473 = 'EPSG:6473'
proj4.defs(
  EPSG_6473,
  '+proj=lcc +lat_0=36.3333333333333 +lon_0=-85.75 +lat_1=37.0833333333333 +lat_2=38.6666666667 +x_0=1500000 +y_0=999999.9998984 +ellps=GRS80 +units=us-ft +no_defs +type=crs',
)

function encodeU8(values: Uint8Array) {
  let binary = ''
  for (const value of values) binary += String.fromCharCode(value)
  return btoa(binary)
}

function encodeU16(values: Uint16Array) {
  return encodeU8(new Uint8Array(values.buffer))
}

function terrainArtifact() {
  const width = 50
  const height = 50
  const count = width * height
  const domain = new Uint8Array(count).fill(1)
  const elevation = new Uint16Array(count).fill(10000)
  return {
    local_form_grid: {
      native_crs: 'EPSG:32616',
      bbox: { west: 679800, east: 680300, south: 4239800, north: 4240300 },
      cell_meters: 10,
      width,
      height,
      domain_valid_base64: encodeU8(domain),
      elevation_offset_ft: 0,
      elevation_tenths_ft_u16_base64: encodeU16(elevation),
    },
  }
}

function structureArtifact(blocked: boolean) {
  const width = 48
  const height = 48
  const count = width * height
  const base = proj4('EPSG:32616', EPSG_6473, [679880, 4239880])
  const domain = new Uint8Array(count).fill(1)
  const property = new Uint8Array(count).fill(1)
  const valid = new Uint8Array(count).fill(1)
  const shares = Array.from({ length: 5 }, () => new Uint8Array(count))
  if (blocked) shares[1].fill(220)
  return {
    domain: { identity_sha256: 'a'.repeat(64) },
    combined_grid: {
      native_crs: EPSG_6473,
      bbox: [Number(base[0]), Number(base[1]), Number(base[0]) + width * 16.404199, Number(base[1]) + height * 16.404199],
      cell_size_native: 16.404199,
      cell_meters: 5,
      width,
      height,
      domain_valid_base64: encodeU8(domain),
      property_mask_base64: encodeU8(property),
      lidar_valid_base64: encodeU8(valid),
      lidar_band_shares_base64: shares.map(encodeU8),
    },
  }
}

function build(blocked: boolean) {
  return buildHorizontalVisibilityArtifact({
    landscapeStructureArtifact: structureArtifact(blocked),
    terrainFormArtifact: terrainArtifact(),
    landscapeDomainIdentitySha256: 'a'.repeat(64),
    landscapeStructureIdentitySha256: 'b'.repeat(64),
    landscapeStructureArtifactSha256: 'c'.repeat(64),
    terrainFormIdentitySha256: 'd'.repeat(64),
    terrainFormArtifactSha256: 'e'.repeat(64),
    sourceSignature: horizontalVisibilitySourceSignature({
      landscapeDomainIdentitySha256: 'a'.repeat(64),
      landscapeStructureIdentitySha256: 'b'.repeat(64),
      landscapeStructureArtifactSha256: 'c'.repeat(64),
      terrainFormIdentitySha256: 'd'.repeat(64),
      terrainFormArtifactSha256: 'e'.repeat(64),
    }),
  })
}

Deno.test('horizontal visibility source signature binds every dependency and physics parameter', () => {
  const args = {
    landscapeDomainIdentitySha256: 'a'.repeat(64),
    landscapeStructureIdentitySha256: 'b'.repeat(64),
    landscapeStructureArtifactSha256: 'c'.repeat(64),
    terrainFormIdentitySha256: 'd'.repeat(64),
    terrainFormArtifactSha256: 'e'.repeat(64),
  }
  const first = horizontalVisibilitySourceSignature(args)
  const changed = horizontalVisibilitySourceSignature({ ...args, terrainFormArtifactSha256: 'f'.repeat(64) })
  assert(first !== changed)
  assert(first.includes('scope=barrier-aware-local-500m'))
  assert(first.includes('observer_heights_m=1.5,3,6'))
  assert(first.includes('distance_bands_m=10,25,50,100'))
})

Deno.test('flat supported terrain produces open continuous visibility summaries', async () => {
  const built = await build(false)
  assert(validateHorizontalVisibilityArtifact(built.artifact))
  assert(built.artifact.scoring_performed === false)
  assert(built.artifact.behavioral_inference_performed === false)
  assert(built.artifact.source_provenance.source_signature.startsWith('product=horizontal-visibility-context|'))
  assert(!Object.prototype.hasOwnProperty.call(built.artifact, 'deer_score'))
  assert(built.artifact.summary.domain_cell_count === 2304)
  const scenario = built.artifact.summary.height_scenarios[0]
  assert(scenario.combined_visible_distance_m_p50_at_100m === 100)
  assert(scenario.combined_obstruction_fraction_by_band[3] === 0)
})

Deno.test('adding supported vertical returns monotonically reduces combined visibility', async () => {
  const open = await build(false)
  const blocked = await build(true)
  const openMedian = open.artifact.summary.height_scenarios[0].combined_visible_distance_m_p50_at_100m
  const blockedMedian = blocked.artifact.summary.height_scenarios[0].combined_visible_distance_m_p50_at_100m
  assert(blockedMedian < openMedian)
  assert(blocked.artifact.summary.height_scenarios[0].combined_obstruction_fraction_by_band[0] > 0)
})

Deno.test('artifact validator rejects wrong array support and preserves explicit height scenarios', async () => {
  const built = await build(false)
  assert(validateHorizontalVisibilityArtifact(built.artifact))
  assert(built.artifact.observer_height_scenarios.length === 3)
  built.artifact.grid.combined_obstruction_fraction_by_band_u8_base64 = encodeU8(new Uint8Array(1))
  assert(!validateHorizontalVisibilityArtifact(built.artifact))
})
