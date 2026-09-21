#!/usr/bin/env -S deno run --allow-env --allow-net

import { Buffer } from 'node:buffer'
import proj4 from 'npm:proj4@2.12.1'
import {
  FARM_WATCH_LIDAR_SOURCE_PRODUCT,
  buildLidarSourceArtifact,
  sha256Hex,
} from '../supabase/functions/_shared/farm-watch-lidar-source.ts'
import {
  FARM_WATCH_LEAF_OFF_PRODUCT,
} from '../supabase/functions/_shared/farm-watch-leaf-off-contract.ts'
import {
  FARM_WATCH_LANDSCAPE_STRUCTURE_PRODUCT,
} from '../supabase/functions/_shared/farm-watch-landscape-structure-contract.ts'
import { FARM_WATCH_GITHUB_OIDC_AUDIENCE } from '../supabase/functions/_shared/github-actions-oidc.ts'
import {
  buildLidarPhysicalArtifactForGeometry,
} from './farm-watch-lidar-physical-materialize.ts'
import {
  buildLeafOffSourceProductForGeometry,
} from './farm-watch-leaf-off-materialize.ts'

const EDGE_URL =
  'https://ufpkjaadmmpmeogzhrcq.supabase.co/functions/v1/farm-watch-landscape-structure-worker'
const propertySlug = arg('--property', 'validation-property-01')!
const EPSG_6473 =
  '+proj=lcc +lat_0=36.3333333333333 +lon_0=-85.75 +lat_1=37.0833333333333 +lat_2=38.6666666667 +x_0=1500000 +y_0=999999.9998984 +ellps=GRS80 +units=us-ft +no_defs +type=crs'
proj4.defs('EPSG:6473', EPSG_6473)

function arg(name: string, fallback: string | null = null) {
  const index = Deno.args.indexOf(name)
  if (index < 0) return fallback
  const value = Deno.args[index + 1]
  if (!value || value.startsWith('--')) throw new Error(name + ' requires a value')
  return value
}

function pointInRing(x: number, y: number, ring: any[]) {
  let inside = false
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const xi = Number(ring[i][0])
    const yi = Number(ring[i][1])
    const xj = Number(ring[j][0])
    const yj = Number(ring[j][1])
    const crosses = ((yi > y) !== (yj > y)) &&
      (x < ((xj - xi) * (y - yi)) / ((yj - yi) || Number.EPSILON) + xi)
    if (crosses) inside = !inside
  }
  return inside
}

function pointInGeometry(x: number, y: number, geometry: any) {
  const polygons = geometry?.type === 'Polygon'
    ? [geometry.coordinates]
    : geometry?.type === 'MultiPolygon'
      ? geometry.coordinates
      : []
  return polygons.some((polygon: any[]) => {
    const [outer, ...holes] = polygon || []
    if (!outer || !pointInRing(x, y, outer)) return false
    return !holes.some((hole) => pointInRing(x, y, hole))
  })
}

function encodeU8(values: Uint8Array) {
  return Buffer.from(values).toString('base64')
}

function encodeU16(values: Uint16Array) {
  return Buffer.from(
    new Uint8Array(values.buffer, values.byteOffset, values.byteLength),
  ).toString('base64')
}

function encodeBitset(values: Uint8Array) {
  const packed = new Uint8Array(Math.ceil(values.length / 8))
  for (let index = 0; index < values.length; index += 1) {
    if (values[index]) packed[index >> 3] |= 1 << (index & 7)
  }
  return Buffer.from(packed).toString('base64')
}

function quantile(sorted: number[], q: number) {
  if (!sorted.length) return null
  const position = (sorted.length - 1) * q
  const lower = Math.floor(position)
  const upper = Math.ceil(position)
  if (lower === upper) return sorted[lower]
  const weight = position - lower
  return sorted[lower] * (1 - weight) + sorted[upper] * weight
}

function distribution(values: number[]) {
  if (!values.length) {
    return { count: 0, mean: null, p10: null, p25: null, median: null, p75: null, p90: null }
  }
  const sorted = values.slice().sort((a, b) => a - b)
  const mean = values.reduce((sum, value) => sum + value, 0) / values.length
  return {
    count: values.length,
    mean,
    p10: quantile(sorted, 0.10),
    p25: quantile(sorted, 0.25),
    median: quantile(sorted, 0.50),
    p75: quantile(sorted, 0.75),
    p90: quantile(sorted, 0.90),
  }
}

function lidarRegionSummary(
  mask: Uint8Array,
  lidarValid: Uint8Array,
  dominantBand: Uint8Array,
  total: number[],
  counts: number[],
  bandCount: number,
) {
  const bandTotals = new Float64Array(bandCount)
  const dominantCounts = new Uint32Array(bandCount)
  let cellCount = 0
  let returnCount = 0
  for (let index = 0; index < mask.length; index += 1) {
    if (!mask[index] || !lidarValid[index]) continue
    cellCount += 1
    const cellTotal = Number(total[index] || 0)
    returnCount += cellTotal
    const dominant = Number(dominantBand[index])
    if (dominant >= 0 && dominant < bandCount) dominantCounts[dominant] += 1
    for (let band = 0; band < bandCount; band += 1) {
      bandTotals[band] += Number(counts[index * bandCount + band] || 0)
    }
  }
  const bandShares = Array.from(bandTotals).map((value) =>
    returnCount ? value / returnCount : 0
  )
  return {
    eligible_cell_count: cellCount,
    normalized_return_count: returnCount,
    neutral_band_shares: bandShares,
    share_0_4_ft: bandShares[0] || 0,
    share_4_32_ft: (bandShares[1] || 0) + (bandShares[2] || 0),
    share_32plus_ft: (bandShares[3] || 0) + (bandShares[4] || 0),
    dominant_band_cell_shares: Array.from(dominantCounts).map((value) =>
      cellCount ? value / cellCount : 0
    ),
  }
}

function leafRegionSummary(
  mask: Uint8Array,
  leafValid: Uint8Array,
  leafScore: Uint8Array,
  leafConfidence: Uint8Array,
  leafSpectralSupport: Uint8Array,
) {
  let domainCells = 0
  let validCells = 0
  let highConfidence = 0
  let supported = 0
  const scores: number[] = []
  for (let index = 0; index < mask.length; index += 1) {
    if (!mask[index]) continue
    domainCells += 1
    if (!leafValid[index]) continue
    validCells += 1
    scores.push(leafScore[index] / 255)
    if (leafConfidence[index] / 255 >= 0.65) highConfidence += 1
    if (leafSpectralSupport[index] / 255 >= 0.50) supported += 1
  }
  return {
    domain_cell_count: domainCells,
    valid_cell_count: validCells,
    observation_coverage_percent: domainCells ? validCells / domainCells * 100 : null,
    high_confidence_percent: validCells ? highConfidence / validCells * 100 : null,
    spectral_support_50_percent: validCells ? supported / validCells * 100 : null,
    score_distribution: distribution(scores),
  }
}

function buildCombinedGrid(args: {
  domain: any
  propertyBoundary: any
  lidar: any
  leaf: any
}) {
  const lidarGrid = args.lidar.grid
  const width = Number(lidarGrid.width)
  const height = Number(lidarGrid.height)
  const length = width * height
  const bandCount = Number(lidarGrid.bandCount)
  const minReturns = Number(args.lidar.minimum_cell_returns || 10)
  const domainValid = new Uint8Array(length)
  const propertyMask = new Uint8Array(length)
  const localRingMask = new Uint8Array(length)
  const lidarValid = new Uint8Array(length)
  const lidarDominantBand = new Uint8Array(length)
  const lidarTotalReturns = new Uint16Array(length)
  const lidarBandShares = Array.from({ length: bandCount }, () => new Uint8Array(length))
  const leafValid = new Uint8Array(length)
  const leafScore = new Uint8Array(length)
  const leafConfidence = new Uint8Array(length)
  const leafSpectralSupport = new Uint8Array(length)

  const leafProduct = args.leaf.product
  const leafBounds = leafProduct.bounds
  const leafWidth = Number(leafProduct.width)
  const leafHeight = Number(leafProduct.height)
  const total = args.lidar.grid.total as number[]
  const counts = args.lidar.grid.counts as number[]

  let domainCellCount = 0
  let propertyCellCount = 0
  let localRingCellCount = 0

  for (let row = 0; row < height; row += 1) {
    const nativeY = Number(lidarGrid.bbox[1]) + (row + 0.5) * Number(lidarGrid.cellSize)
    for (let col = 0; col < width; col += 1) {
      const index = row * width + col
      const nativeX = Number(lidarGrid.bbox[0]) + (col + 0.5) * Number(lidarGrid.cellSize)
      const [lon, lat] = proj4('EPSG:6473', 'EPSG:4326', [nativeX, nativeY])
      if (!pointInGeometry(lon, lat, args.domain)) continue

      domainValid[index] = 1
      domainCellCount += 1
      const insideProperty = pointInGeometry(lon, lat, args.propertyBoundary)
      if (insideProperty) {
        propertyMask[index] = 1
        propertyCellCount += 1
      } else {
        localRingMask[index] = 1
        localRingCellCount += 1
      }

      const cellTotal = Number(total[index] || 0)
      if (cellTotal >= minReturns) {
        lidarValid[index] = 1
        lidarTotalReturns[index] = Math.min(65535, Math.round(cellTotal))
        let dominant = 0
        let dominantCount = -1
        for (let band = 0; band < bandCount; band += 1) {
          const count = Number(counts[index * bandCount + band] || 0)
          lidarBandShares[band][index] = Math.round(Math.max(0, Math.min(1, count / cellTotal)) * 255)
          if (count > dominantCount) {
            dominant = band
            dominantCount = count
          }
        }
        lidarDominantBand[index] = dominant
      }

      const [webX, webY] = proj4('EPSG:4326', 'EPSG:3857', [lon, lat])
      const xFraction = (webX - Number(leafBounds.west)) /
        (Number(leafBounds.east) - Number(leafBounds.west))
      const yFraction = (Number(leafBounds.north) - webY) /
        (Number(leafBounds.north) - Number(leafBounds.south))
      const leafCol = Math.floor(xFraction * leafWidth)
      const leafRow = Math.floor(yFraction * leafHeight)
      if (
        leafCol < 0 || leafCol >= leafWidth ||
        leafRow < 0 || leafRow >= leafHeight
      ) continue
      const leafIndex = leafRow * leafWidth + leafCol
      if (!leafProduct.valid[leafIndex]) continue
      leafValid[index] = 1
      leafScore[index] = leafProduct.score[leafIndex]
      leafConfidence[index] = leafProduct.confidence[leafIndex]
      leafSpectralSupport[index] = leafProduct.spectralSupport[leafIndex]
    }
  }

  const leafDiffs: number[] = []
  const lidarProfileDistances: number[] = []
  let boundaryPairCount = 0
  let combinedPairCount = 0
  let leafPairCount = 0
  let lidarPairCount = 0
  let dominantAgreementCount = 0
  const offsets = [[1, 0], [0, 1], [1, 1], [-1, 1]]

  for (let row = 0; row < height; row += 1) {
    for (let col = 0; col < width; col += 1) {
      const a = row * width + col
      if (!domainValid[a]) continue
      for (const [dx, dy] of offsets) {
        const otherCol = col + dx
        const otherRow = row + dy
        if (otherCol < 0 || otherCol >= width || otherRow < 0 || otherRow >= height) continue
        const b = otherRow * width + otherCol
        if (!domainValid[b] || propertyMask[a] === propertyMask[b]) continue
        boundaryPairCount += 1

        const hasLeaf = Boolean(leafValid[a] && leafValid[b])
        const hasLidar = Boolean(lidarValid[a] && lidarValid[b])
        if (hasLeaf) {
          leafPairCount += 1
          leafDiffs.push(Math.abs(leafScore[a] - leafScore[b]) / 255)
        }
        if (hasLidar) {
          lidarPairCount += 1
          let l1 = 0
          for (let band = 0; band < bandCount; band += 1) {
            l1 += Math.abs(lidarBandShares[band][a] - lidarBandShares[band][b]) / 255
          }
          lidarProfileDistances.push(l1 / 2)
          if (lidarDominantBand[a] === lidarDominantBand[b]) dominantAgreementCount += 1
        }
        if (hasLeaf && hasLidar) combinedPairCount += 1
      }
    }
  }

  const propertyLidar = lidarRegionSummary(
    propertyMask, lidarValid, lidarDominantBand, total, counts, bandCount,
  )
  const ringLidar = lidarRegionSummary(
    localRingMask, lidarValid, lidarDominantBand, total, counts, bandCount,
  )
  const propertyLeaf = leafRegionSummary(
    propertyMask, leafValid, leafScore, leafConfidence, leafSpectralSupport,
  )
  const ringLeaf = leafRegionSummary(
    localRingMask, leafValid, leafScore, leafConfidence, leafSpectralSupport,
  )

  return {
    compact: {
      native_crs: args.lidar.native_crs,
      bbox: lidarGrid.bbox,
      cell_size_native: lidarGrid.cellSize,
      cell_meters: Number(args.lidar.cell_meters),
      width,
      height,
      thresholds_ft: lidarGrid.thresholds,
      band_count: bandCount,
      encoding: 'base64-u8-v1',
      domain_valid_base64: encodeU8(domainValid),
      property_mask_base64: encodeU8(propertyMask),
      lidar_valid_base64: encodeU8(lidarValid),
      lidar_dominant_band_base64: encodeU8(lidarDominantBand),
      lidar_band_shares_base64: lidarBandShares.map(encodeU8),
      lidar_total_returns_u16_base64: encodeU16(lidarTotalReturns),
      leaf_valid_base64: encodeU8(leafValid),
      leaf_score_base64: encodeU8(leafScore),
      leaf_confidence_base64: encodeU8(leafConfidence),
      leaf_spectral_support_base64: encodeU8(leafSpectralSupport),
    },
    summary: {
      domain_cell_count: domainCellCount,
      property_cell_count: propertyCellCount,
      local_ring_cell_count: localRingCellCount,
      lidar: {
        property: propertyLidar,
        local_ring: ringLidar,
      },
      leaf_off: {
        property: propertyLeaf,
        local_ring: ringLeaf,
      },
      cross_boundary_adjacency: {
        method: 'cross_boundary_8_neighbor_profile_and_texture_contrast_v1',
        boundary_pair_count: boundaryPairCount,
        leaf_pair_count: leafPairCount,
        lidar_pair_count: lidarPairCount,
        combined_pair_count: combinedPairCount,
        leaf_score_absolute_difference: distribution(leafDiffs),
        lidar_profile_total_variation_distance: distribution(lidarProfileDistances),
        lidar_dominant_band_agreement_percent:
          lidarPairCount ? dominantAgreementCount / lidarPairCount * 100 : null,
        interpretation_boundary:
          'Descriptive adjacency across the property boundary only. Similarity or contrast is not a corridor, funnel, security-cover, habitat, or animal-movement classification.',
      },
    },
  }
}

function compactLeafOffForLandscape(built: any) {
  const compact = built.compact
  return {
    sourceId: compact.sourceId,
    sourceYear: compact.sourceYear,
    sourceLabel: compact.sourceLabel,
    sourceTile: compact.sourceTile,
    acquisitionDate: compact.acquisitionDate,
    acquisitionTimestamp: compact.acquisitionTimestamp,
    acquisitionNote: compact.acquisitionNote,
    solarMode: compact.solarMode,
    frameTimeBasis: compact.frameTimeBasis,
    solar: compact.solar,
    bounds: compact.bounds,
    neighborhoodDiameterM: compact.neighborhoodDiameterM,
    highConfidencePercent: compact.highConfidencePercent,
    nirRescuePercent: compact.nirRescuePercent,
    scoreDistribution: compact.scoreDistribution,
    normalization: compact.normalization,
    grid: {
      width: compact.grid.width,
      height: compact.grid.height,
      source_pixel_m: compact.grid.source_pixel_m,
      terrain_pixel_m: compact.grid.terrain_pixel_m,
      target_neighborhood_m: compact.grid.target_neighborhood_m,
      encoding: 'landscape-leaf-highres-v1',
      score_encoding: 'base64-u8-v1',
      validity_encoding: 'base64-bitset-lsb-v1',
      score_base64: compact.grid.score_base64,
      valid_bitset_base64: encodeBitset(built.product.valid),
      valid_cell_count: built.product.valid.reduce(
        (sum: number, value: number) => sum + (value ? 1 : 0),
        0,
      ),
    },
  }
}

async function freshOidcToken() {
  const requestUrl = Deno.env.get('ACTIONS_ID_TOKEN_REQUEST_URL') || ''
  const requestToken = Deno.env.get('ACTIONS_ID_TOKEN_REQUEST_TOKEN') || ''
  if (!requestUrl || !requestToken) throw new Error('GitHub Actions OIDC environment unavailable')
  const url = new URL(requestUrl)
  url.searchParams.set('audience', FARM_WATCH_GITHUB_OIDC_AUDIENCE)
  const response = await fetch(url, {
    headers: { authorization: 'Bearer ' + requestToken, accept: 'application/json' },
  })
  if (!response.ok) throw new Error('GitHub OIDC token request failed: ' + response.status)
  const payload = await response.json()
  if (!payload?.value) throw new Error('GitHub OIDC token response was empty')
  return String(payload.value)
}

async function workerRequest(body: any) {
  const token = await freshOidcToken()
  const response = await fetch(EDGE_URL, {
    method: 'POST',
    headers: {
      authorization: 'Bearer ' + token,
      'content-type': 'application/json',
      accept: 'application/json',
    },
    body: JSON.stringify({
      property: propertySlug,
      product: FARM_WATCH_LANDSCAPE_STRUCTURE_PRODUCT.key,
      ...body,
    }),
  })
  const payload = await response.json().catch(() => ({}))
  if (!response.ok) {
    throw new Error(payload?.detail || payload?.error || ('worker API returned ' + response.status))
  }
  return payload
}

async function main() {
  const claim = await workerRequest({ operation: 'claim' })
  if (claim?.action === 'reuse') {
    console.log(JSON.stringify({ status: 'reused', build: claim.build || null }, null, 2))
    return
  }
  if (claim?.action !== 'build') {
    console.log(JSON.stringify({
      status: claim?.action || 'not_claimed',
      build: claim.build || null,
    }, null, 2))
    return
  }

  const buildId = String(claim.build_id)
  const leaseToken = String(claim.lease_token)
  try {
    const domain = claim.analysis_domain_geojson
    const propertyBoundary = claim.property_boundary_geojson
    if (!domain || !propertyBoundary) throw new Error('landscape or property geometry unavailable')

    const center = claim.center
    if (!Number.isFinite(Number(center?.lat)) || !Number.isFinite(Number(center?.lon))) {
      throw new Error('property center unavailable')
    }

    console.log('Resolving Phase 3 LiDAR coverage for barrier-aware local_500m domain')
    const phase3CollectionId = String(claim.contract.lidar.source_collection)
    const sourceBuild = await buildLidarSourceArtifact(domain, fetch, [phase3CollectionId])
    const sourcePlan = sourceBuild.artifact
    const phase3 = sourcePlan.collections?.find(
      (row: any) => row?.id === phase3CollectionId,
    )
    const coveragePercent = Number(
      phase3?.coverage?.sampled_analysis_coverage_percent ??
      phase3?.coverage?.sampled_parcel_coverage_percent
    )
    if (
      phase3?.coverage?.coverage_status !== 'complete_sampled' ||
      !Number.isFinite(coveragePercent) ||
      coveragePercent < 99.5 ||
      !Array.isArray(phase3?.processing_items) ||
      !phase3.processing_items.length
    ) {
      throw new Error('Phase 3 LiDAR coverage is incomplete for local_500m domain')
    }
    const sourcePlanArtifactSha256 = await sha256Hex(JSON.stringify(sourcePlan))

    console.log('Building local_500m Phase 3 LiDAR physical structure')
    const lidar = await buildLidarPhysicalArtifactForGeometry({
      analysisGeometry: domain,
      sourceItems: phase3.processing_items,
      contract: claim.contract.lidar,
      sourcePlanArtifactSha256,
      interpretationBoundary:
        'Barrier-aware local_500m Phase 3 physical height-above-ground evidence. Neutral height strata are used only for structural continuity context; they are not species, understory, habitat, security-cover, bedding, or animal-use classes.',
    })

    console.log('Building local_500m 2024 leaf-off woody-pattern structure')
    const leaf = await buildLeafOffSourceProductForGeometry(
      String(claim.contract.leaf_off.source_id),
      domain,
      { lat: Number(center.lat), lon: Number(center.lon) },
    )

    console.log('Synthesizing common 5 m property-boundary continuity grid')
    const combined = buildCombinedGrid({
      domain,
      propertyBoundary,
      lidar,
      leaf,
    })

    const processingFingerprint = {
      landscape_domain_identity_sha256: claim.landscape_domain_identity.identity_sha256,
      landscape_domain_algorithm_version: claim.landscape_domain_identity.algorithm_version,
      lidar: {
        source_plan_artifact_sha256: sourcePlanArtifactSha256,
        source_plan_sampled_source_sha256: sourceBuild.sampledSourceSha256,
        processing_items: phase3.processing_items.map((item: any) => ({
          id: item.id,
          updated: item.updated || null,
          pc_count: item.pc_count ?? null,
          pc_density: item.pc_density ?? null,
          primary_asset_identity: item.primary_asset_identity || null,
          bbox: item.bbox || null,
        })),
        physical_processing_source_fingerprint: lidar.processing_source_fingerprint,
      },
      leaf_off: leaf.fingerprint,
    }

    const artifact = {
      schema: claim.contract.schema,
      method: claim.contract.method,
      status: 'available',
      evidence_class: 'deterministic_derived',
      domain: {
        radius_m: Number(claim.contract.domain_meters),
        identity_sha256: claim.landscape_domain_identity.identity_sha256,
        algorithm_version: claim.landscape_domain_identity.algorithm_version,
        output_schema_version: claim.landscape_domain_identity.output_schema_version,
        barrier_aware: true,
      },
      lidar_physical: {
        source_collection: lidar.source_collection,
        source_plan_artifact_sha256: lidar.source_plan_artifact_sha256,
        processing_item_ids: lidar.processing_item_ids,
        native_crs: lidar.native_crs,
        height_unit: lidar.height_unit,
        cell_meters: lidar.cell_meters,
        minimum_cell_returns: lidar.minimum_cell_returns,
        acquisition_utc_range: lidar.acquisition_utc_range,
        acquisition_time_basis: lidar.acquisition_time_basis,
        processing_summary: {
          support_ground_point_count: lidar.processing_summary.support_ground_point_count,
          analysis_ground_cell_count: lidar.processing_summary.parcel_ground_cell_count,
          analysis_direct_ground_cell_count: lidar.processing_summary.parcel_direct_ground_cell_count,
          analysis_supported_ground_cell_count: lidar.processing_summary.parcel_supported_ground_cell_count,
          ground_supported_analysis_percent:
            lidar.processing_summary.ground_supported_parcel_percent,
          primary_structure_point_count: lidar.processing_summary.primary_structure_point_count,
          normalized_structure_point_count: lidar.processing_summary.normalized_structure_point_count,
          normalization_unavailable_count: lidar.processing_summary.normalization_unavailable_count,
          negative_height_count: lidar.processing_summary.negative_height_count,
          below_minus_one_foot_count: lidar.processing_summary.below_minus_one_foot_count,
          overlap_policy: lidar.processing_summary.overlap_policy,
        },
        processing_source_fingerprint: lidar.processing_source_fingerprint,
        interpretation_boundary: lidar.interpretation_boundary,
        grid_storage_note:
          'Full local_500m LiDAR cell counts are represented in combined_grid as 5 m band-share bytes plus uint16 return counts; the duplicate raw JSON count arrays are intentionally not stored.',
      },
      leaf_off_2024: compactLeafOffForLandscape(leaf),
      combined_grid: combined.compact,
      summary: combined.summary,
      source_provenance: {
        lidar: {
          source_collection: claim.contract.lidar.source_collection,
          source_plan_artifact_sha256: sourcePlanArtifactSha256,
          selected_item_ids: phase3.processing_items.map((item: any) => item.id),
          sampled_domain_coverage_percent: coveragePercent,
        },
        leaf_off: {
          source_id: leaf.product.sourceId,
          source_year: leaf.product.sourceYear,
          source_tile: leaf.product.sourceTile,
          acquisition_date: leaf.product.acquisitionDate,
          imagery_source_pixel_m: leaf.product.sourcePixelM,
          terrain_pixel_m: leaf.product.terrainPixelM,
        },
      },
      processing_source_fingerprint: processingFingerprint,
      interpretation_boundary:
        'Fine structural context over the exact barrier-aware local_500m domain. The product describes physical continuity and contrast across the property boundary; it performs no deer scoring, movement prediction, security-cover classification, bedding prediction, habitat-quality classification, or hunting recommendation.',
    }

    const completion = await workerRequest({
      operation: 'complete',
      build_id: buildId,
      lease_token: leaseToken,
      artifact,
    })

    console.log(JSON.stringify({
      status: 'available',
      property: propertySlug,
      domain_identity_sha256: artifact.domain.identity_sha256,
      lidar_processing_item_ids: artifact.source_provenance.lidar.selected_item_ids,
      lidar_sampled_domain_coverage_percent:
        artifact.source_provenance.lidar.sampled_domain_coverage_percent,
      combined_grid: {
        width: artifact.combined_grid.width,
        height: artifact.combined_grid.height,
        domain_cell_count: artifact.summary.domain_cell_count,
        property_cell_count: artifact.summary.property_cell_count,
        local_ring_cell_count: artifact.summary.local_ring_cell_count,
      },
      cross_boundary_adjacency: artifact.summary.cross_boundary_adjacency,
      completion,
    }, null, 2))
  } catch (error) {
    try {
      await workerRequest({
        operation: 'fail',
        build_id: buildId,
        lease_token: leaseToken,
        error: error instanceof Error ? error.stack || error.message : String(error),
      })
    } catch (failError) {
      console.error('Failed to report landscape structure worker failure:', failError)
    }
    throw error
  }
}

if (import.meta.main) await main()
