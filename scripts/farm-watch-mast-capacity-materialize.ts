#!/usr/bin/env -S deno run --allow-env --allow-net

import { Buffer } from 'node:buffer'
import proj4 from 'npm:proj4@2.12.1'
import { fromArrayBuffer } from 'npm:geotiff@2.1.3'
import {
  FARM_WATCH_MAST_CAPACITY_GROUPS,
  FARM_WATCH_MAST_CAPACITY_PRODUCT,
} from '../supabase/functions/_shared/farm-watch-mast-capacity-contract.ts'
import { FARM_WATCH_GITHUB_OIDC_AUDIENCE } from '../supabase/functions/_shared/github-actions-oidc.ts'
import { sha256Hex } from '../supabase/functions/_shared/farm-watch-terrain.ts'

const EDGE_URL =
  'https://ufpkjaadmmpmeogzhrcq.supabase.co/functions/v1/farm-watch-mast-capacity-worker'
const propertySlug = arg('--property', 'validation-property-01')!
const localSourceManifest = arg('--local-source-manifest')
const ESRI_102039 =
  '+proj=aea +lat_1=29.5 +lat_2=45.5 +lat_0=23 +lon_0=-96 +x_0=0 +y_0=0 +datum=NAD83 +units=m +no_defs +type=crs'
proj4.defs('ESRI:102039', ESRI_102039)

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

function coordinates(geometry: any) {
  const out: number[][] = []
  function walk(value: any) {
    if (!Array.isArray(value)) return
    if (
      value.length >= 2 &&
      Number.isFinite(Number(value[0])) &&
      Number.isFinite(Number(value[1])) &&
      typeof value[0] !== 'object'
    ) {
      out.push([Number(value[0]), Number(value[1])])
      return
    }
    for (const child of value) walk(child)
  }
  walk(geometry?.coordinates)
  return out
}

function nativeBigmapBounds(geometry: any) {
  const points = coordinates(geometry)
  if (!points.length) throw new Error('mast capacity analysis geometry is empty')
  let xmin = Infinity, ymin = Infinity, xmax = -Infinity, ymax = -Infinity
  for (const [lon, lat] of points) {
    const [x, y] = proj4('EPSG:4326', 'ESRI:102039', [lon, lat])
    xmin = Math.min(xmin, x)
    ymin = Math.min(ymin, y)
    xmax = Math.max(xmax, x)
    ymax = Math.max(ymax, y)
  }
  const cell = FARM_WATCH_MAST_CAPACITY_PRODUCT.sourcePixelMeters
  xmin = Math.floor(xmin / cell) * cell
  ymin = Math.floor(ymin / cell) * cell
  xmax = Math.ceil(xmax / cell) * cell
  ymax = Math.ceil(ymax / cell) * cell
  return [xmin, ymin, xmax, ymax]
}

function encodeU8(values: Uint8Array) {
  return Buffer.from(values).toString('base64')
}

function encodeF32(values: Float32Array) {
  return Buffer.from(
    new Uint8Array(values.buffer, values.byteOffset, values.byteLength),
  ).toString('base64')
}

function quantile(sorted: number[], q: number) {
  if (!sorted.length) return null
  const position = (sorted.length - 1) * q
  const lower = Math.floor(position)
  const upper = Math.ceil(position)
  if (lower === upper) return sorted[lower]
  return sorted[lower] * (1 - (position - lower)) + sorted[upper] * (position - lower)
}

function groupSummary(mask: Uint8Array, values: Float32Array) {
  let cells = 0
  let positive = 0
  const observed: number[] = []
  for (let i = 0; i < mask.length; i += 1) {
    if (!mask[i]) continue
    cells += 1
    const value = Number(values[i] || 0)
    observed.push(value)
    if (value > 0) positive += 1
  }
  observed.sort((a, b) => a - b)
  const mean = observed.length
    ? observed.reduce((sum, value) => sum + value, 0) / observed.length
    : null
  return {
    modeled_cell_count: cells,
    positive_biomass_cell_count: positive,
    positive_biomass_cell_share_percent: cells ? positive / cells * 100 : null,
    biomass_tons_per_acre: {
      mean,
      median: quantile(observed, 0.5),
      p90: quantile(observed, 0.9),
      max: observed.length ? observed[observed.length - 1] : null,
    },
  }
}

function scopeSummary(mask: Uint8Array, groups: Record<string, Float32Array>) {
  return {
    cell_count: Array.from(mask).reduce((sum, value) => sum + (value ? 1 : 0), 0),
    groups: Object.fromEntries(
      FARM_WATCH_MAST_CAPACITY_PRODUCT.groupOrder.map((group) => [
        group,
        groupSummary(mask, groups[group]),
      ]),
    ),
  }
}


async function postArcgis(path: string, params: URLSearchParams) {
  const response = await fetch(FARM_WATCH_MAST_CAPACITY_PRODUCT.sourceService + path, {
    method: 'POST',
    headers: {
      accept: 'application/json',
      'content-type': 'application/x-www-form-urlencoded; charset=UTF-8',
      'user-agent': 'Cadastory-Farm-Watch/1.0 (+https://pmicka.com)',
    },
    body: params.toString(),
  })
  if (!response.ok) {
    const detail = await response.text().catch(() => '')
    throw new Error(
      'BIGMAP request failed: ' + response.status +
      (detail ? ' ' + detail.slice(0, 500) : ''),
    )
  }
  const payload = await response.json()
  if (payload?.error) throw new Error('BIGMAP service error: ' + JSON.stringify(payload.error))
  return payload
}

async function querySpeciesCatalog() {
  const allCodes = FARM_WATCH_MAST_CAPACITY_PRODUCT.groupOrder.flatMap((group) =>
    FARM_WATCH_MAST_CAPACITY_GROUPS[group].map((row) => row.spcd)
  )
  const params = new URLSearchParams()
  params.set('f', 'json')
  params.set('where', 'category=1 AND spcd IN (' + allCodes.join(',') + ')')
  params.set('outFields', 'objectid,spcd,common_name,genus,species,name')
  params.set('returnGeometry', 'false')
  params.set('orderByFields', 'spcd')
  const body = await postArcgis('/query', params)
  const records = (body?.features || []).map((feature: any) => feature?.attributes || {})
  const byCode = new Map<number, any>()
  for (const record of records) {
    const code = Number(record.spcd)
    if (!Number.isInteger(code)) continue
    if (byCode.has(code)) throw new Error('BIGMAP catalog returned duplicate primary species code ' + code)
    byCode.set(code, record)
  }
  for (const code of allCodes) {
    if (!byCode.has(code)) throw new Error('BIGMAP catalog is missing expected species code ' + code)
  }
  return byCode
}

async function exportSpecies(
  record: any,
  requestBbox: number[],
  width: number,
  height: number,
) {
  const params = new URLSearchParams()
  params.set('f', 'json')
  params.set('bbox', requestBbox.join(','))
  params.set('bboxSR', String(FARM_WATCH_MAST_CAPACITY_PRODUCT.sourceNativeWkid))
  params.set('imageSR', String(FARM_WATCH_MAST_CAPACITY_PRODUCT.sourceNativeWkid))
  params.set('size', width + ',' + height)
  params.set('format', 'tiff')
  params.set('pixelType', 'F32')
  params.set('interpolation', 'RSP_NearestNeighbor')
  params.set('mosaicRule', JSON.stringify({
    mosaicMethod: 'esriMosaicLockRaster',
    lockRasterIds: [Number(record.objectid)],
  }))
  const exported = await postArcgis('/exportImage', params)
  const href = String(exported?.href || '')
  if (!href.startsWith('https://')) {
    throw new Error('BIGMAP export did not return a secure TIFF URL for SPCD ' + record.spcd)
  }
  const response = await fetch(href, {
    headers: { 'user-agent': 'Cadastory-Farm-Watch/1.0 (+https://pmicka.com)' },
  })
  if (!response.ok) throw new Error('BIGMAP TIFF download failed: ' + response.status)
  const bytes = new Uint8Array(await response.arrayBuffer())
  if (bytes.byteLength <= 0 || bytes.byteLength > 5 * 1024 * 1024) {
    throw new Error('BIGMAP TIFF size is invalid for SPCD ' + record.spcd)
  }
  const sourceSha256 = await sha256Hex(bytes)
  const tiff = await fromArrayBuffer(bytes.buffer)
  const image = await tiff.getImage()
  const rasterWidth = image.getWidth()
  const rasterHeight = image.getHeight()
  if (rasterWidth !== width || rasterHeight !== height) {
    throw new Error(
      'BIGMAP TIFF dimensions changed for SPCD ' + record.spcd +
      ': ' + rasterWidth + 'x' + rasterHeight,
    )
  }
  const raster = await image.readRasters({ interleave: true })
  const values = new Float32Array(width * height)
  for (let i = 0; i < values.length; i += 1) {
    const value = Number((raster as any)[i])
    values[i] = Number.isFinite(value) && value > 0 && value < 100000 ? value : 0
  }
  return {
    values,
    bbox: image.getBoundingBox().map(Number),
    sourceSha256,
    sourceBytes: bytes.byteLength,
    sourceHrefHost: new URL(href).host,
  }
}

async function loadLocalSourceManifest(path: string) {
  const payload = JSON.parse(await Deno.readTextFile(path))
  if (payload?.schema !== 'farm-watch-bigmap-local-crop-manifest-v1') {
    throw new Error('local BIGMAP manifest schema is invalid')
  }
  if (String(payload?.crop?.property_slug || '') !== propertySlug) {
    throw new Error('local BIGMAP manifest property does not match materialization target')
  }
  const expected = FARM_WATCH_MAST_CAPACITY_PRODUCT.groupOrder
    .flatMap((group) => FARM_WATCH_MAST_CAPACITY_GROUPS[group].map((row) => row.spcd))
    .sort((a, b) => a - b)
  const present = Array.isArray(payload?.present_species_codes)
    ? payload.present_species_codes.map(Number).sort((a: number, b: number) => a - b)
    : []
  if (JSON.stringify(expected) !== JSON.stringify(present)) {
    throw new Error('local BIGMAP manifest does not contain the complete mast species set')
  }
  return payload
}

function siblingFile(manifestPath: string, fileName: string) {
  if (!/^[A-Za-z0-9._-]+$/.test(fileName)) {
    throw new Error('local BIGMAP crop filename is invalid')
  }
  const slash = manifestPath.lastIndexOf('/')
  return (slash >= 0 ? manifestPath.slice(0, slash + 1) : '') + fileName
}

async function readLocalSpecies(
  manifest: any,
  manifestPath: string,
  expected: any,
  requestBbox: number[],
  width: number,
  height: number,
) {
  const crop = manifest?.crop
  const manifestBbox = Array.isArray(crop?.bbox_esri_102039)
    ? crop.bbox_esri_102039.map(Number)
    : []
  if (
    Number(crop?.window?.width) !== width ||
    Number(crop?.window?.height) !== height ||
    manifestBbox.length !== 4 ||
    manifestBbox.some((value: number, i: number) => Math.abs(value - requestBbox[i]) > 0.01)
  ) throw new Error('local BIGMAP crop grid does not match current Farm Watch landscape domain')

  const item = (manifest?.items || []).find((row: any) => Number(row?.spcd) === expected.spcd)
  if (!item) throw new Error('local BIGMAP manifest is missing SPCD ' + expected.spcd)
  const filePath = siblingFile(manifestPath, String(item.crop_file || ''))
  const bytes = await Deno.readFile(filePath)
  const sourceSha256 = await sha256Hex(bytes)
  if (sourceSha256 !== String(item.crop_sha256 || '').toLowerCase()) {
    throw new Error('local BIGMAP crop checksum mismatch for SPCD ' + expected.spcd)
  }

  const tiff = await fromArrayBuffer(bytes.buffer)
  const image = await tiff.getImage()
  if (image.getWidth() !== width || image.getHeight() !== height) {
    throw new Error('local BIGMAP crop dimensions changed for SPCD ' + expected.spcd)
  }
  const bbox = image.getBoundingBox().map(Number)
  if (bbox.some((value, i) => Math.abs(value - requestBbox[i]) > 0.01)) {
    throw new Error('local BIGMAP crop bounds changed for SPCD ' + expected.spcd)
  }

  const raster = await image.readRasters({ interleave: true })
  const values = new Float32Array(width * height)
  for (let i = 0; i < values.length; i += 1) {
    const value = Number((raster as any)[i])
    values[i] = Number.isFinite(value) && value > 0 && value < 100000 ? value : 0
  }
  return {
    values,
    bbox,
    sourceSha256,
    sourceBytes: bytes.byteLength,
    sourceFileName: String(item.source_tiff_name || ''),
    transport: 'operator_workstation_usfs_raster_gateway_bounded_crop',
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
      product: FARM_WATCH_MAST_CAPACITY_PRODUCT.key,
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
    console.log(JSON.stringify({ status: claim?.action || 'not_claimed', build: claim.build || null }, null, 2))
    return
  }

  const buildId = String(claim.build_id)
  const leaseToken = String(claim.lease_token)
  try {
    const broad = claim?.zones?.broad_3000m
    const local = claim?.zones?.local_500m
    const landscape = claim?.zones?.landscape_1500m
    const property = claim?.property_boundary_geojson
    if (!broad || !local || !landscape || !property) throw new Error('mast capacity analysis zones unavailable')

    const requestBbox = nativeBigmapBounds(broad)
    const cell = FARM_WATCH_MAST_CAPACITY_PRODUCT.sourcePixelMeters
    const width = Math.max(1, Math.round((requestBbox[2] - requestBbox[0]) / cell))
    const height = Math.max(1, Math.round((requestBbox[3] - requestBbox[1]) / cell))
    if (width * height > 250000) throw new Error('mast capacity bounded grid is unexpectedly large')

    const localManifest = localSourceManifest
      ? await loadLocalSourceManifest(localSourceManifest)
      : null
    if (localManifest) {
      console.log('Using operator-cropped official USDA Raster Data Gateway BIGMAP sources')
    } else {
      console.log('Querying BIGMAP 2018 species catalog from official public ArcGIS service')
    }
    const catalog = localManifest ? null : await querySpeciesCatalog()
    const groupValues: Record<string, Float32Array> = Object.fromEntries(
      FARM_WATCH_MAST_CAPACITY_PRODUCT.groupOrder.map((group) => [
        group,
        new Float32Array(width * height),
      ]),
    )
    const sourceGroups: Record<string, any[]> = Object.fromEntries(
      FARM_WATCH_MAST_CAPACITY_PRODUCT.groupOrder.map((group) => [group, []]),
    )
    const sourceItems: any[] = []
    let rasterBbox: number[] | null = null

    for (const group of FARM_WATCH_MAST_CAPACITY_PRODUCT.groupOrder) {
      for (const expected of FARM_WATCH_MAST_CAPACITY_GROUPS[group]) {
        const record = localManifest
          ? {
              objectid: null,
              spcd: expected.spcd,
              common_name: expected.common_name,
              genus: expected.scientific_name.split(' ')[0],
              species: expected.scientific_name.split(' ').slice(1).join(' '),
            }
          : catalog!.get(expected.spcd)
        console.log(`Sampling BIGMAP SPCD ${expected.spcd} ${expected.common_name}`)
        const exported = localManifest
          ? await readLocalSpecies(
              localManifest,
              localSourceManifest!,
              expected,
              requestBbox,
              width,
              height,
            )
          : await exportSpecies(record, requestBbox, width, height)
        if (!rasterBbox) rasterBbox = exported.bbox
        else if (exported.bbox.some((value, i) => Math.abs(value - rasterBbox![i]) > 0.01)) {
          throw new Error('BIGMAP export grids are not co-registered')
        }
        const target = groupValues[group]
        for (let i = 0; i < target.length; i += 1) target[i] += exported.values[i]

        const item = {
          object_id: record.objectid == null ? null : Number(record.objectid),
          spcd: expected.spcd,
          common_name: String(record.common_name || expected.common_name),
          genus: String(record.genus || expected.scientific_name.split(' ')[0]),
          species: String(record.species || expected.scientific_name.split(' ').slice(1).join(' ')),
          scientific_name: expected.scientific_name,
          source_tiff_sha256: exported.sourceSha256,
          source_tiff_size_bytes: exported.sourceBytes,
          source_transport: localManifest
            ? 'operator_workstation_usfs_raster_gateway_bounded_crop'
            : 'github_actions_public_usfs_arcgis',
          source_file_name: localManifest && 'sourceFileName' in exported
            ? exported.sourceFileName
            : null,
        }
        sourceGroups[group].push(item)
        sourceItems.push({ group, ...item })
      }
    }
    if (!rasterBbox) throw new Error('BIGMAP source grid was not produced')

    console.log('Masking BIGMAP grid to barrier-aware Farm Watch landscape domains')
    const domainMask = new Uint8Array(width * height)
    const propertyMask = new Uint8Array(width * height)
    const localMask = new Uint8Array(width * height)
    const landscapeMask = new Uint8Array(width * height)
    const xStep = (rasterBbox[2] - rasterBbox[0]) / width
    const yStep = (rasterBbox[3] - rasterBbox[1]) / height
    for (let row = 0; row < height; row += 1) {
      const y = rasterBbox[3] - (row + 0.5) * yStep
      for (let col = 0; col < width; col += 1) {
        const index = row * width + col
        const x = rasterBbox[0] + (col + 0.5) * xStep
        const [lon, lat] = proj4('ESRI:102039', 'EPSG:4326', [x, y])
        if (!pointInGeometry(lon, lat, broad)) continue
        domainMask[index] = 1
        if (pointInGeometry(lon, lat, landscape)) landscapeMask[index] = 1
        if (pointInGeometry(lon, lat, local)) localMask[index] = 1
        if (pointInGeometry(lon, lat, property)) propertyMask[index] = 1
      }
    }

    for (const group of FARM_WATCH_MAST_CAPACITY_PRODUCT.groupOrder) {
      const values = groupValues[group]
      for (let i = 0; i < values.length; i += 1) if (!domainMask[i]) values[i] = 0
    }

    const fingerprint = {
      source_authority: FARM_WATCH_MAST_CAPACITY_PRODUCT.sourceAuthority,
      source_product: FARM_WATCH_MAST_CAPACITY_PRODUCT.sourceProduct,
      source_service: FARM_WATCH_MAST_CAPACITY_PRODUCT.sourceService,
      source_data_year: FARM_WATCH_MAST_CAPACITY_PRODUCT.sourceDataYear,
      source_value_unit: FARM_WATCH_MAST_CAPACITY_PRODUCT.sourceValueUnit,
      export_request: {
        bbox_esri_102039: requestBbox,
        raster_bbox_esri_102039: rasterBbox,
        width,
        height,
        interpolation: 'RSP_NearestNeighbor',
        transport: localManifest
          ? 'operator_workstation_usfs_raster_gateway_bounded_crop'
          : 'github_actions_public_usfs_arcgis',
        bulk_download_page: localManifest
          ? String(localManifest?.source?.bulk_download_page || '')
          : null,
      },
      landscape_domain_identity_sha256: claim.landscape_domain_identity.identity_sha256,
      source_items: sourceItems,
    }
    const fingerprintSha256 = await sha256Hex(JSON.stringify(fingerprint))

    const artifact = {
      schema: FARM_WATCH_MAST_CAPACITY_PRODUCT.outputSchemaVersion,
      method: FARM_WATCH_MAST_CAPACITY_PRODUCT.algorithmVersion,
      status: 'available',
      evidence_class: FARM_WATCH_MAST_CAPACITY_PRODUCT.semanticEvidenceClass,
      domain: {
        scope: FARM_WATCH_MAST_CAPACITY_PRODUCT.domainScope,
        identity_sha256: claim.landscape_domain_identity.identity_sha256,
        algorithm_version: claim.landscape_domain_identity.algorithm_version,
        output_schema_version: claim.landscape_domain_identity.output_schema_version,
        barrier_aware: true,
      },
      source: {
        authority: FARM_WATCH_MAST_CAPACITY_PRODUCT.sourceAuthority,
        product: FARM_WATCH_MAST_CAPACITY_PRODUCT.sourceProduct,
        data_year: FARM_WATCH_MAST_CAPACITY_PRODUCT.sourceDataYear,
        service: FARM_WATCH_MAST_CAPACITY_PRODUCT.sourceService,
        native_pixel_meters: FARM_WATCH_MAST_CAPACITY_PRODUCT.sourcePixelMeters,
        value_unit: FARM_WATCH_MAST_CAPACITY_PRODUCT.sourceValueUnit,
        groups: sourceGroups,
      },
      grid: {
        crs: FARM_WATCH_MAST_CAPACITY_PRODUCT.sourceNativeCrs,
        bbox: rasterBbox,
        width,
        height,
        cell_meters: FARM_WATCH_MAST_CAPACITY_PRODUCT.sourcePixelMeters,
        encoding: 'base64-f32le-v1',
        domain_mask_encoding: 'base64-u8-v1',
        domain_mask_base64: encodeU8(domainMask),
        groups: Object.fromEntries(
          FARM_WATCH_MAST_CAPACITY_PRODUCT.groupOrder.map((group) => [
            group,
            { biomass_tons_per_acre_base64: encodeF32(groupValues[group]) },
          ]),
        ),
      },
      summary: {
        scopes: {
          property: scopeSummary(propertyMask, groupValues),
          local_500m: scopeSummary(localMask, groupValues),
          landscape_1500m: scopeSummary(landscapeMask, groupValues),
          broad_3000m: scopeSummary(domainMask, groupValues),
        },
      },
      source_provenance: {
        sampled_species_count: sourceItems.length,
        sampled_species_codes: sourceItems.map((row) => row.spcd).sort((a, b) => a - b),
        raw_source_persisted: false,
        bounded_source_transport: localManifest
          ? 'operator_workstation_usfs_raster_gateway_bounded_crop'
          : 'github_actions_public_usfs_arcgis',
      },
      processing_source_fingerprint: fingerprint,
      processing_source_fingerprint_sha256: fingerprintSha256,
      annual_mast_inference_performed: false,
      behavioral_inference_performed: false,
      scoring_performed: false,
      interpretation_boundary:
        'Modeled mast-producing tree species biomass capacity only. The product does not establish observed trees at each pixel, current-year mast production, mast fall, ground availability, deer use, attraction, habitat quality, or management action.',
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
      grid: { width, height, cell_count: width * height },
      sampled_species_count: sourceItems.length,
      summary: artifact.summary,
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
      console.error('Failed to report mast capacity worker failure:', failError)
    }
    throw error
  }
}

if (import.meta.main) await main()
