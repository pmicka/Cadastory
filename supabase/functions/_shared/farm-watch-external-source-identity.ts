import {
  buildLidarSourceArtifact,
  sha256Hex,
} from './farm-watch-lidar-source.ts'
import { FARM_WATCH_TERRAIN_PRODUCT } from './farm-watch-terrain-contract.ts'
import { FARM_WATCH_TERRAIN_FORM_PRODUCT } from './farm-watch-neutral-primitives-contract.ts'
import {
  FARM_WATCH_LEAF_OFF_PRODUCT,
  leafOffSourceCatalogWhere,
  leafOffSourceMosaicRule,
} from './farm-watch-leaf-off-contract.ts'
import {
  FARM_WATCH_SOLAR_TERRAIN_PRODUCT,
  solarCanopyCatalogWhere,
  solarCanopyMosaicRule,
} from './farm-watch-solar-exposure-contract.ts'
import {
  FARM_WATCH_MAST_CAPACITY_GROUPS,
  FARM_WATCH_MAST_CAPACITY_PRODUCT,
} from './farm-watch-mast-capacity-contract.ts'

export const FARM_WATCH_EXTERNAL_DEPENDENCY_KEYS = Object.freeze([
  'external:kyfromabove-phase3-dem',
  'external:kyfromabove-lidar-stac',
  'external:kyfromabove-phase3-copc',
  'external:kyfromabove-phase3-imagery-2024',
  'external:kyfromabove-phase2-imagery-2019',
  'external:nlcd-tcc-v2025-6',
  'external:usgs-3dep-dynamic',
  'external:fia-bigmap-2018-species-biomass',
] as const)

export type FarmWatchExternalDependencyKey =
  typeof FARM_WATCH_EXTERNAL_DEPENDENCY_KEYS[number]

export type FarmWatchExternalSourceObservation = {
  key: FarmWatchExternalDependencyKey
  status: 'available' | 'unavailable'
  authoritative: boolean
  resolution_status: string
  identity_sha256?: string
  observed_at: string
  evidence: Record<string, unknown>
  error?: string
}

const USER_AGENT = 'Cadastory-Farm-Watch-Source-Identity/1.0 (+https://pmicka.com)'
const ARCGIS_ONLINE_ROOT = 'https://www.arcgis.com'
const TCC_ARCGIS_ITEM_ID = '8f6ea42df79f4c4186239cbd42852f14'
const SOURCE_TIMEOUT_MS = 20_000
const SOLAR_DEM_IDENTITY_SUPPORT_METERS =
  FARM_WATCH_TERRAIN_FORM_PRODUCT.landscapeDomainMeters +
  FARM_WATCH_SOLAR_TERRAIN_PRODUCT.horizonSearchRadiusMeters +
  2 * FARM_WATCH_SOLAR_TERRAIN_PRODUCT.supportCellMeters

function finite(value: unknown): number | null {
  const n = Number(value)
  return Number.isFinite(n) ? n : null
}

function stableValue(value: any): any {
  if (Array.isArray(value)) return value.map(stableValue)
  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.keys(value).sort().map((key) => [key, stableValue(value[key])]),
    )
  }
  if (typeof value === 'number' && !Number.isFinite(value)) return null
  return value
}

function stableJson(value: unknown) {
  return JSON.stringify(stableValue(value))
}

function geometryCoordinates(value: any, out: Array<[number, number]> = []) {
  if (!Array.isArray(value)) return out
  if (
    value.length >= 2 &&
    Number.isFinite(Number(value[0])) &&
    Number.isFinite(Number(value[1]))
  ) {
    out.push([Number(value[0]), Number(value[1])])
    return out
  }
  for (const child of value) geometryCoordinates(child, out)
  return out
}

export function farmWatchGeometryBbox(geometry: any): [number, number, number, number] {
  const rows = geometryCoordinates(geometry?.coordinates)
  if (!rows.length) throw new Error('external-source identity boundary is empty')
  const xs = rows.map((row) => row[0])
  const ys = rows.map((row) => row[1])
  return [Math.min(...xs), Math.min(...ys), Math.max(...xs), Math.max(...ys)]
}

function expandBboxMeters(
  bbox: [number, number, number, number],
  meters: number,
): [number, number, number, number] {
  const [west, south, east, north] = bbox
  const latitude = (south + north) / 2
  const latDegrees = meters / 111_320
  const lonDegrees = meters / Math.max(1, 111_320 * Math.cos(latitude * Math.PI / 180))
  return [west - lonDegrees, south - latDegrees, east + lonDegrees, north + latDegrees]
}

function bboxPolygon(bbox: [number, number, number, number]) {
  const [west, south, east, north] = bbox
  return {
    type: 'Polygon',
    coordinates: [[
      [west, south],
      [east, south],
      [east, north],
      [west, north],
      [west, south],
    ]],
  }
}

function gridPoints(
  bbox: [number, number, number, number],
  size: number,
): Array<[number, number]> {
  const [west, south, east, north] = bbox
  const out: Array<[number, number]> = []
  for (let row = 0; row < size; row += 1) {
    const lat = south + (north - south) * (row + 0.5) / size
    for (let col = 0; col < size; col += 1) {
      const lon = west + (east - west) * (col + 0.5) / size
      out.push([lon, lat])
    }
  }
  return out
}

async function fetchWithTimeout(
  url: string,
  init: RequestInit = {},
  fetchImpl: typeof fetch = fetch,
) {
  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), SOURCE_TIMEOUT_MS)
  try {
    return await fetchImpl(url, {
      ...init,
      signal: controller.signal,
      headers: {
        'user-agent': USER_AGENT,
        ...(init.headers || {}),
      },
    })
  } finally {
    clearTimeout(timeout)
  }
}

async function postFormJson(
  url: string,
  params: Record<string, string>,
  fetchImpl: typeof fetch,
) {
  const body = new URLSearchParams(params)
  const response = await fetchWithTimeout(url, {
    method: 'POST',
    headers: {
      accept: 'application/json',
      'content-type': 'application/x-www-form-urlencoded; charset=UTF-8',
    },
    body: body.toString(),
  }, fetchImpl)
  const text = await response.text()
  if (!response.ok) throw new Error('source request returned ' + response.status)
  let payload: any
  try {
    payload = JSON.parse(text)
  } catch {
    throw new Error('source request did not return JSON')
  }
  if (payload?.error) throw new Error(String(payload.error?.message || 'source request failed'))
  return payload
}

async function getJson(
  url: string,
  fetchImpl: typeof fetch,
) {
  const response = await fetchWithTimeout(url, {
    headers: { accept: 'application/json' },
  }, fetchImpl)
  const text = await response.text()
  if (!response.ok) throw new Error('source request returned ' + response.status)
  try {
    const payload = JSON.parse(text)
    if (payload?.error) throw new Error(String(payload.error?.message || 'source request failed'))
    return payload
  } catch (error) {
    if (error instanceof Error && error.message.startsWith('source request failed')) throw error
    throw new Error('source request did not return JSON')
  }
}

function serviceMetadataSubset(payload: any) {
  return stableValue({
    name: payload?.name ?? null,
    serviceDescription: payload?.serviceDescription ?? null,
    description: payload?.description ?? null,
    copyrightText: payload?.copyrightText ?? null,
    serviceDataType: payload?.serviceDataType ?? null,
    serviceSourceType: payload?.serviceSourceType ?? null,
    extent: payload?.extent ?? payload?.fullExtent ?? null,
    pixelSizeX: finite(payload?.pixelSizeX),
    pixelSizeY: finite(payload?.pixelSizeY),
    meanPixelSize: finite(payload?.meanPixelSize),
    datasetFormat: payload?.datasetFormat ?? null,
    bandCount: finite(payload?.bandCount),
    bandNames: payload?.bandNames ?? null,
    pixelType: payload?.pixelType ?? null,
    minValues: payload?.minValues ?? null,
    maxValues: payload?.maxValues ?? null,
    meanValues: payload?.meanValues ?? null,
    stdvValues: payload?.stdvValues ?? null,
    capabilities: payload?.capabilities ?? null,
    serviceItemId: payload?.serviceItemId ?? null,
    fields: Array.isArray(payload?.fields)
      ? payload.fields.map((field: any) => ({
        name: field?.name ?? null,
        type: field?.type ?? null,
        alias: field?.alias ?? null,
      }))
      : [],
  })
}

async function serviceMetadata(
  serviceUrl: string,
  fetchImpl: typeof fetch,
) {
  try {
    return await postFormJson(serviceUrl, { f: 'json' }, fetchImpl)
  } catch {
    return await getJson(serviceUrl + '?f=json', fetchImpl)
  }
}

async function arcgisCatalog(
  serviceUrl: string,
  bbox: [number, number, number, number] | null,
  where: string,
  outFields: string,
  fetchImpl: typeof fetch,
) {
  const baseParams: Record<string, string> = {
    f: 'json',
    where,
    outFields,
    returnGeometry: 'false',
    orderByFields: 'OBJECTID',
    resultRecordCount: '1000',
  }
  if (bbox) {
    baseParams.geometryType = 'esriGeometryEnvelope'
    baseParams.geometry = bbox.join(',')
    baseParams.inSR = '4326'
    baseParams.spatialRel = 'esriSpatialRelIntersects'
  }

  const rows: any[] = []
  let resultOffset = 0
  let pageCount = 0
  while (true) {
    pageCount += 1
    if (pageCount > 100) {
      throw new Error('bounded source catalog pagination exceeded page limit')
    }
    const payload = await postFormJson(
      serviceUrl.replace(/\/$/, '') + '/query',
      {
        ...baseParams,
        resultOffset: String(resultOffset),
      },
      fetchImpl,
    )
    const pageRows = Array.isArray(payload?.features)
      ? payload.features.map((feature: any) =>
        stableValue(feature?.attributes || {})
      )
      : []
    rows.push(...pageRows)

    if (payload?.exceededTransferLimit !== true) {
      if (pageRows.length >= Number(baseParams.resultRecordCount)) {
        throw new Error(
          'bounded source catalog completeness is unproven at the page limit',
        )
      }
      break
    }
    if (!pageRows.length) {
      throw new Error('bounded source catalog pagination stalled')
    }
    resultOffset += pageRows.length
  }

  const rowKeys = rows.map((row: any) =>
    String(row?.OBJECTID ?? row?.objectid ?? row?.Name ?? row?.name ?? '')
  )
  if (new Set(rowKeys).size !== rowKeys.length) {
    throw new Error('bounded source catalog pagination returned duplicate records')
  }

  return {
    rows: rows.sort((a: any, b: any) =>
      String(
        a?.OBJECTID ?? a?.objectid ?? a?.Name ?? a?.name ?? '',
      ).localeCompare(
        String(
          b?.OBJECTID ?? b?.objectid ?? b?.Name ?? b?.name ?? '',
        ),
      )
    ),
    page_count: pageCount,
    complete: true,
  }
}

async function arcgisSamples(
  serviceUrl: string,
  bbox: [number, number, number, number],
  size: number,
  extra: Record<string, string>,
  fetchImpl: typeof fetch,
) {
  const points = gridPoints(bbox, size)
  const payload = await postFormJson(
    serviceUrl.replace(/\/$/, '') + '/getSamples',
    {
      f: 'json',
      geometryType: 'esriGeometryMultipoint',
      geometry: JSON.stringify({
        points,
        spatialReference: { wkid: 4326 },
      }),
      returnFirstValueOnly: 'true',
      ...extra,
    },
    fetchImpl,
  )
  const samples = Array.isArray(payload?.samples) ? payload.samples : []
  const byIndex = new Map<number, any>()
  samples.forEach((sample: any, ordinal: number) => {
    const locationId = Number(sample?.locationId)
    const index =
      Number.isInteger(locationId) &&
        locationId >= 0 &&
        locationId < points.length
        ? locationId
        : ordinal < points.length ? ordinal : -1
    if (index >= 0) {
      byIndex.set(index, stableValue({
        value: sample?.value ?? null,
        attributes: sample?.attributes ?? null,
      }))
    }
  })
  const rows = points.map((point, index) => ({
    point,
    sample: byIndex.get(index) ?? null,
  }))
  return {
    rows,
    requested_count: points.length,
    returned_count: byIndex.size,
    complete: byIndex.size === points.length,
  }
}

async function arcgisImageProbe(
  serviceUrl: string,
  bbox: [number, number, number, number],
  fetchImpl: typeof fetch,
) {
  const url = new URL(serviceUrl.replace(/\/$/, '') + '/exportImage')
  url.searchParams.set('bbox', bbox.join(','))
  url.searchParams.set('bboxSR', '4326')
  url.searchParams.set('imageSR', '4326')
  url.searchParams.set('size', '96,96')
  url.searchParams.set('adjustAspectRatio', 'false')
  url.searchParams.set('format', 'png32')
  url.searchParams.set('interpolation', 'RSP_BilinearInterpolation')
  url.searchParams.set('f', 'image')
  const response = await fetchWithTimeout(url.toString(), {
    headers: { accept: 'image/png,image/*' },
  }, fetchImpl)
  if (!response.ok) throw new Error('image probe returned ' + response.status)
  const bytes = new Uint8Array(await response.arrayBuffer())
  if (!bytes.byteLength) throw new Error('image probe returned an empty body')
  return {
    sha256: await sha256Hex(bytes),
    size_bytes: bytes.byteLength,
  }
}

async function arcgisPortalItem(
  serviceUrl: string,
  service: any,
  fetchImpl: typeof fetch,
  fixedItemId: string | null = null,
  fallbackTitle: string | null = null,
  portalRoot: string = ARCGIS_ONLINE_ROOT,
) {
  let itemId = fixedItemId || String(service?.serviceItemId || '').trim()
  if (!itemId) {
    try {
      const query = 'url:"' + serviceUrl + '"'
      const search = await getJson(
        portalRoot.replace(/\/$/, '') + '/sharing/rest/search?f=json&num=10&q=' + encodeURIComponent(query),
        fetchImpl,
      )
      const rows = Array.isArray(search?.results) ? search.results : []
      const exact = rows.find((row: any) => String(row?.url || '').replace(/\/$/, '') === serviceUrl.replace(/\/$/, ''))
      itemId = String(exact?.id || '')
    } catch {
      itemId = ''
    }
    if (!itemId && fallbackTitle) {
      try {
        const search = await getJson(
          portalRoot.replace(/\/$/, '') + '/sharing/rest/search?f=json&num=20&q=' +
            encodeURIComponent('title:"' + fallbackTitle + '"'),
          fetchImpl,
        )
        const rows = Array.isArray(search?.results) ? search.results : []
        const exact = rows.find((row: any) =>
          String(row?.title || '') === fallbackTitle &&
          (!row?.url || String(row.url).replace(/\/$/, '') === serviceUrl.replace(/\/$/, ''))
        ) || rows.find((row: any) => String(row?.title || '') === fallbackTitle)
        itemId = String(exact?.id || '')
      } catch {
        itemId = ''
      }
    }
  }
  if (!itemId) return null
  try {
    const item = await getJson(
      portalRoot.replace(/\/$/, '') + '/sharing/rest/content/items/' + itemId + '?f=json',
      fetchImpl,
    )
    return stableValue({
      id: item?.id ?? itemId,
      owner: item?.owner ?? null,
      title: item?.title ?? null,
      type: item?.type ?? null,
      created: item?.created ?? null,
      modified: item?.modified ?? null,
      size: item?.size ?? null,
      url: item?.url ?? null,
      typeKeywords: item?.typeKeywords ?? null,
      access: item?.access ?? null,
    })
  } catch {
    return null
  }
}

async function providerObservedArcgis(args: {
  key: FarmWatchExternalDependencyKey
  serviceUrl: string
  bbox: [number, number, number, number] | null
  where?: string
  outFields?: string
  sampleGrid?: number
  sampleExtra?: Record<string, string>
  imageProbe?: boolean
  fixedItemId?: string | null
  portalSearchTitle?: string | null
  portalRoot?: string | null
  requireCatalog?: boolean
  expectedCatalogCount?: number | null
  requireSamples?: boolean
  minimumSampleCoverage?: number
  fetchImpl: typeof fetch
}) {
  const service = await serviceMetadata(args.serviceUrl, args.fetchImpl).catch(() => null)
  const metadata = service ? serviceMetadataSubset(service) : null
  const portalItem = await arcgisPortalItem(
    args.serviceUrl,
    service,
    args.fetchImpl,
    args.fixedItemId || null,
    args.portalSearchTitle || null,
    args.portalRoot || ARCGIS_ONLINE_ROOT,
  )
  let catalog: any[] | null = null
  let catalogObservation: any = null
  let samples: any[] | null = null
  let sampleObservation: any = null
  let imageProbe: any = null
  if (args.where || args.bbox) {
    try {
      const observedCatalog = await arcgisCatalog(
        args.serviceUrl,
        args.bbox,
        args.where || '1=1',
        args.outFields || '*',
        args.fetchImpl,
      )
      catalog = observedCatalog.rows
      catalogObservation = {
        page_count: observedCatalog.page_count,
        returned_record_count: observedCatalog.rows.length,
        complete: observedCatalog.complete,
      }
      if (args.requireCatalog && (catalog?.length ?? 0) === 0) {
        throw new Error('bounded source catalog probe returned no records')
      }
      if (
        args.expectedCatalogCount != null &&
        catalog.length !== args.expectedCatalogCount
      ) {
        throw new Error(
          'bounded source catalog selection returned ' +
          catalog.length + ' records; expected ' + args.expectedCatalogCount,
        )
      }
    } catch (error) {
      if (args.requireCatalog) throw error
    }
  }
  if (args.sampleGrid && args.bbox) {
    try {
      const observedSamples = await arcgisSamples(
        args.serviceUrl,
        args.bbox,
        args.sampleGrid,
        args.sampleExtra || {},
        args.fetchImpl,
      )
      samples = observedSamples.rows
      const sampleCoverage = observedSamples.requested_count
        ? observedSamples.returned_count / observedSamples.requested_count
        : 0
      const minimumSampleCoverage = Math.max(
        0,
        Math.min(1, args.minimumSampleCoverage ?? 1),
      )
      sampleObservation = {
        requested_count: observedSamples.requested_count,
        returned_count: observedSamples.returned_count,
        complete: observedSamples.complete,
        coverage_fraction: sampleCoverage,
        minimum_coverage_fraction: minimumSampleCoverage,
        coverage_requirement_met: sampleCoverage >= minimumSampleCoverage,
      }
      if (
        args.requireSamples &&
        sampleCoverage < minimumSampleCoverage
      ) {
        throw new Error(
          'bounded source sample coverage incomplete: returned ' +
          observedSamples.returned_count + ' of ' +
          observedSamples.requested_count +
          '; minimum_fraction=' + minimumSampleCoverage,
        )
      }
    } catch (error) {
      if (args.requireSamples) throw error
    }
  }
  if (args.imageProbe && args.bbox) {
    imageProbe = await arcgisImageProbe(args.serviceUrl, args.bbox, args.fetchImpl)
  }
  if (!metadata && !portalItem && !catalog && !samples && !imageProbe) {
    throw new Error('authoritative source observation is unavailable')
  }
  const evidence = stableValue({
    strategy: 'arcgis-provider-observation-v1',
    service_url: args.serviceUrl,
    service_metadata: metadata,
    portal_item: portalItem,
    catalog,
    catalog_observation: catalogObservation,
    samples,
    sample_observation: sampleObservation,
    image_probe: imageProbe,
    probe_bbox: args.bbox,
  })
  return {
    identity_sha256: await sha256Hex(stableJson(evidence)),
    evidence,
    resolution_status: portalItem
      ? 'provider_item_and_bounded_observation'
      : 'provider_bounded_observation',
  }
}

async function resolveStacAndCopc(
  boundary: any,
  fetchImpl: typeof fetch,
) {
  const expanded = expandBboxMeters(farmWatchGeometryBbox(boundary), 650)
  const probeBoundary = bboxPolygon(expanded)
  const result = await buildLidarSourceArtifact(probeBoundary, fetchImpl)
  const phase3Collection = (result.artifact?.collections || [])
    .find((collection: any) => collection?.id === 'laz-phase3')
  const processingItems = (phase3Collection?.processing_items || [])
    .filter((item: any) => item?.primary_asset_href)
    .sort((a: any, b: any) => String(a.id).localeCompare(String(b.id)))
  const validators = []
  for (const item of processingItems) {
    const href = String(item.primary_asset_href)
    const response = await fetchWithTimeout(href, { method: 'HEAD' }, fetchImpl)
    if (!response.ok) throw new Error('COPC object validator returned ' + response.status)
    const row: any = {
      id: String(item.id || ''),
      asset_identity: String(item.primary_asset_identity || href.split('?')[0]),
      etag: response.headers.get('etag'),
      last_modified: response.headers.get('last-modified'),
      content_length: response.headers.get('content-length'),
      version_id: response.headers.get('x-amz-version-id'),
      checksum_sha256: response.headers.get('x-amz-checksum-sha256'),
    }
    if (!row.version_id && !row.checksum_sha256 && !row.etag) {
      const range = await fetchWithTimeout(href, {
        headers: { range: 'bytes=0-65535', accept: 'application/octet-stream' },
      }, fetchImpl)
      if (!range.ok && range.status !== 206) {
        throw new Error('COPC object has no strong validator and range probe failed')
      }
      row.range_probe_sha256 = await sha256Hex(new Uint8Array(await range.arrayBuffer()))
    }
    validators.push(stableValue(row))
  }
  if (!processingItems.length) throw new Error('LiDAR source observation found no usable COPC assets')
  const stacEvidence = stableValue({
    strategy: 'stac-selected-item-snapshot-v2',
    expanded_bbox: expanded,
    sampled_source_sha256: result.sampledSourceSha256,
    collections: (result.artifact?.collections || []).map((collection: any) => ({
      id: collection?.id,
      search: collection?.search || null,
      processing_items: (collection?.processing_items || []).map((item: any) => ({
        id: item?.id,
        bbox: item?.bbox,
        geometry: item?.geometry,
        datetime: item?.datetime,
        start_datetime: item?.start_datetime,
        end_datetime: item?.end_datetime,
        created: item?.created,
        updated: item?.updated,
        pc_count: item?.pc_count,
        pc_density: item?.pc_density,
        pc_type: item?.pc_type,
        pc_encoding: item?.pc_encoding,
        primary_asset_key: item?.primary_asset_key,
        primary_asset_identity: item?.primary_asset_identity,
        primary_asset_type: item?.primary_asset_type,
      })),
    })),
  })
  const copcEvidence = stableValue({
    strategy: 'copc-object-validator-v1',
    expanded_bbox: expanded,
    validators,
  })
  return {
    stac: {
      identity_sha256: await sha256Hex(stableJson(stacEvidence)),
      evidence: stacEvidence,
      resolution_status: 'provider_complete_catalog_geometry_snapshot',
    },
    copc: {
      identity_sha256: await sha256Hex(stableJson(copcEvidence)),
      evidence: copcEvidence,
      resolution_status: 'provider_object_validator',
    },
  }
}

function mastSpeciesCodes() {
  return FARM_WATCH_MAST_CAPACITY_PRODUCT.groupOrder.flatMap((group) =>
    FARM_WATCH_MAST_CAPACITY_GROUPS[group].map((row) => row.spcd)
  )
}

async function resolveOne(
  key: FarmWatchExternalDependencyKey,
  boundary: any,
  fetchImpl: typeof fetch,
  cache: Map<string, any>,
): Promise<FarmWatchExternalSourceObservation> {
  const observedAt = new Date().toISOString()
  try {
    if (
      key === 'external:kyfromabove-lidar-stac' ||
      key === 'external:kyfromabove-phase3-copc'
    ) {
      let pairPromise = cache.get('lidar')
      if (!pairPromise) {
        pairPromise = resolveStacAndCopc(boundary, fetchImpl)
        cache.set('lidar', pairPromise)
      }
      const pair = await pairPromise
      const source = key.endsWith('lidar-stac') ? pair.stac : pair.copc
      return {
        key,
        status: 'available',
        authoritative: true,
        resolution_status: source.resolution_status,
        identity_sha256: source.identity_sha256,
        observed_at: observedAt,
        evidence: source.evidence,
      }
    }

    const propertyBbox = farmWatchGeometryBbox(boundary)
    if (key === 'external:kyfromabove-phase3-dem') {
      const source = await providerObservedArcgis({
        key,
        serviceUrl: FARM_WATCH_TERRAIN_PRODUCT.sourceUrl,
        bbox: expandBboxMeters(propertyBbox, SOLAR_DEM_IDENTITY_SUPPORT_METERS),
        outFields: 'OBJECTID,Name,MinPS,MaxPS,LowPS,HighPS,Category,Tag,GroupName,ProductName,CenterX,CenterY,ZOrder',
        sampleGrid: 7,
        requireCatalog: true,
        requireSamples: true,
        minimumSampleCoverage: 0.9,
        fetchImpl,
      })
      return { key, status: 'available', authoritative: true, observed_at: observedAt, ...source }
    }

    if (key === 'external:nlcd-tcc-v2025-6') {
      const source = await providerObservedArcgis({
        key,
        serviceUrl: FARM_WATCH_SOLAR_TERRAIN_PRODUCT.canopySourceUrl,
        bbox: expandBboxMeters(propertyBbox, 3200),
        where: solarCanopyCatalogWhere(),
        outFields: '*',
        sampleGrid: 7,
        sampleExtra: {
          mosaicRule: JSON.stringify(solarCanopyMosaicRule()),
        },
        fixedItemId: TCC_ARCGIS_ITEM_ID,
        requireCatalog: true,
        expectedCatalogCount: 1,
        requireSamples: true,
        fetchImpl,
      })
      return {
        key,
        status: 'available',
        authoritative: true,
        observed_at: observedAt,
        ...source,
        resolution_status: 'provider_fixed_catalog_item_and_complete_sample',
      }
    }

    if (key === 'external:usgs-3dep-dynamic') {
      const source = await providerObservedArcgis({
        key,
        serviceUrl: FARM_WATCH_SOLAR_TERRAIN_PRODUCT.demFallbackSourceUrl,
        bbox: expandBboxMeters(propertyBbox, SOLAR_DEM_IDENTITY_SUPPORT_METERS),
        outFields: 'OBJECTID,Name,Category,Dataset_ID,Best,DEM_Type,Source,VerticalDatum,AcquisitionDate,URL,Metadata,pubdate,title,Resolution_X,Resolution_Y',
        sampleGrid: 5,
        requireCatalog: true,
        requireSamples: true,
        minimumSampleCoverage: 0.9,
        fetchImpl,
      })
      return { key, status: 'available', authoritative: true, observed_at: observedAt, ...source }
    }

    if (
      key === 'external:kyfromabove-phase3-imagery-2024' ||
      key === 'external:kyfromabove-phase2-imagery-2019'
    ) {
      const wanted = key.includes('phase3')
        ? FARM_WATCH_LEAF_OFF_PRODUCT.sources.find((row) => row.id === 'ky-phase3')
        : FARM_WATCH_LEAF_OFF_PRODUCT.sources.find((row) => row.id === 'ky-franklin-2019')
      if (!wanted) throw new Error('fixed imagery contract is unavailable')
      const bbox = expandBboxMeters(
        propertyBbox,
        FARM_WATCH_LEAF_OFF_PRODUCT.analysisPadMeters,
      )
      const where = leafOffSourceCatalogWhere(wanted)
      const mosaicRule = leafOffSourceMosaicRule(wanted)
      const sampleExtra = {
        mosaicRule: JSON.stringify(mosaicRule),
      }
      const [rgb, ir] = await Promise.all([
        providerObservedArcgis({
          key,
          serviceUrl: wanted.imageryUrl,
          bbox,
          where,
          outFields: '*',
          sampleGrid: 5,
          sampleExtra,
          requireCatalog: true,
          expectedCatalogCount: 1,
          requireSamples: true,
          fetchImpl,
        }),
        providerObservedArcgis({
          key,
          serviceUrl: wanted.infraredUrl,
          bbox,
          where,
          outFields: '*',
          sampleGrid: 5,
          sampleExtra,
          requireCatalog: true,
          expectedCatalogCount: 1,
          requireSamples: true,
          fetchImpl,
        }),
      ])
      const evidence = stableValue({
        strategy: 'fixed-imagery-pair-provider-selection-v2',
        source_id: wanted.id,
        configured_reference_tile: wanted.sourceTile,
        provider_catalog_name: wanted.providerCatalogName,
        configured_acquisition_date: wanted.acquisitionDate,
        consumed_mosaic_rule: mosaicRule,
        rgb: rgb.evidence,
        infrared: ir.evidence,
      })
      return {
        key,
        status: 'available',
        authoritative: true,
        resolution_status: 'provider_fixed_catalog_item_and_complete_sample',
        identity_sha256: await sha256Hex(stableJson(evidence)),
        observed_at: observedAt,
        evidence,
      }
    }

    if (key === 'external:fia-bigmap-2018-species-biomass') {
      const codes = mastSpeciesCodes().slice().sort((a, b) => a - b)
      const gatewayUrl = 'https://data.fs.usda.gov/geodata/rastergateway/bigmap/'
      const response = await fetchWithTimeout(gatewayUrl, {
        headers: { accept: 'text/html' },
      }, fetchImpl)
      if (!response.ok) throw new Error('BIGMAP Raster Gateway returned ' + response.status)
      const html = await response.text()
      const checksums = codes.map((spcd) => {
        const padded = String(spcd).padStart(4, '0')
        const pattern = new RegExp(
          'data\\.spcd=["\\\']' + padded + '["\\\'][^>]*data\\.checksum=["\\\']([0-9A-Fa-f]{64})["\\\']',
          'i',
        )
        const reversePattern = new RegExp(
          'data\\.checksum=["\\\']([0-9A-Fa-f]{64})["\\\'][^>]*data\\.spcd=["\\\']' + padded + '["\\\']',
          'i',
        )
        const match = pattern.exec(html) || reversePattern.exec(html)
        if (!match) throw new Error('BIGMAP checksum unavailable for SPCD ' + padded)
        return { spcd, sha256: match[1].toLowerCase() }
      })
      const evidence = stableValue({
        strategy: 'fixed-bigmap-raster-gateway-sha256-v1',
        gateway_url: gatewayUrl,
        source_product: FARM_WATCH_MAST_CAPACITY_PRODUCT.sourceProduct,
        source_data_year: FARM_WATCH_MAST_CAPACITY_PRODUCT.sourceDataYear,
        checksums,
      })
      return {
        key,
        status: 'available',
        authoritative: true,
        resolution_status: 'provider_published_sha256_checksums',
        identity_sha256: await sha256Hex(stableJson(evidence)),
        observed_at: observedAt,
        evidence,
      }
    }

    throw new Error('unsupported external dependency key')
  } catch (error) {
    return {
      key,
      status: 'unavailable',
      authoritative: false,
      resolution_status: 'provider_observation_failed',
      observed_at: observedAt,
      evidence: {},
      error: error instanceof Error ? error.message : String(error),
    }
  }
}

export async function resolveFarmWatchExternalSourceIdentities(args: {
  boundary: any
  dependencyKeys: string[]
  fetchImpl?: typeof fetch
  requireAll?: boolean
}) {
  const fetchImpl = args.fetchImpl || fetch
  const requestedKeys = [...new Set(args.dependencyKeys.map(String))]
  const unknownKeys = requestedKeys.filter((value) =>
    !(FARM_WATCH_EXTERNAL_DEPENDENCY_KEYS as readonly string[]).includes(value)
  )
  if (unknownKeys.length) {
    throw new Error(
      'unsupported external dependency key(s): ' + unknownKeys.sort().join(', '),
    )
  }
  const keys = requestedKeys
    .filter((value): value is FarmWatchExternalDependencyKey =>
      (FARM_WATCH_EXTERNAL_DEPENDENCY_KEYS as readonly string[]).includes(value)
    )
    .sort()
  const cache = new Map<string, any>()
  const observations = await Promise.all(
    keys.map((key) => resolveOne(key, args.boundary, fetchImpl, cache)),
  )
  const unavailable = observations.filter((row) => row.status !== 'available')
  if (args.requireAll !== false && unavailable.length) {
    throw new Error(
      'external source identity unavailable: ' +
      unavailable.map((row) => row.key + '=' + (row.error || row.status)).join('; '),
    )
  }
  return observations
}

export function farmWatchExternalIdentitySignatureKey(key: string) {
  return 'external_identity_' +
    String(key || '').replace(/^external:/, '').toLowerCase().replace(/[^a-z0-9]+/g, '_')
}

export function appendFarmWatchExternalIdentitySignature(
  sourceSignature: string,
  observations: FarmWatchExternalSourceObservation[],
) {
  const base = String(sourceSignature || '').trim()
  if (!base) throw new Error('materialization source signature is required')
  const tokens = observations
    .slice()
    .sort((a, b) => a.key.localeCompare(b.key))
    .map((row) => {
      if (
        row.status !== 'available' ||
        row.authoritative !== true ||
        !/^[0-9a-f]{64}$/.test(String(row.identity_sha256 || ''))
      ) throw new Error('external source identity is not authoritative: ' + row.key)
      return farmWatchExternalIdentitySignatureKey(row.key) + '=' + row.identity_sha256
    })
  return tokens.length ? base + '|' + tokens.join('|') : base
}

export function farmWatchExternalIdentityOverrides(
  observations: FarmWatchExternalSourceObservation[],
) {
  return Object.fromEntries(observations.map((row) => [
    row.key,
    {
      status: row.status,
      authoritative: row.authoritative,
      resolution_status: row.resolution_status,
      identity_sha256: row.identity_sha256 || null,
      observed_at: row.observed_at,
    },
  ]))
}


async function rpcValue(admin: any, fn: string, args: Record<string, unknown>) {
  const { data, error } = await admin.rpc(fn, args)
  if (error) throw new Error(fn + ' failed: ' + error.message)
  return data
}

export async function resolveFarmWatchExternalSourceSignatureForProperty(args: {
  admin: any
  slug: string
  productKind: string
  sourceSignature: string
  fetchImpl?: typeof fetch
}) {
  const dependencyKeys = await rpcValue(
    args.admin,
    'farm_watch_get_materialization_external_deps_v1_internal',
    { p_product_kind: args.productKind },
  )
  const keys = Array.isArray(dependencyKeys)
    ? dependencyKeys.map(String).filter(Boolean)
    : []
  if (!keys.length) {
    return {
      sourceSignature: args.sourceSignature,
      observations: [] as FarmWatchExternalSourceObservation[],
    }
  }

  const context = await rpcValue(
    args.admin,
    'farm_watch_get_materialization_identity_context_v1_internal',
    { p_slug: args.slug },
  )
  if (context?.status !== 'available' || !context?.boundary_geojson) {
    throw new Error('materialization identity boundary is unavailable')
  }
  const observations = await resolveFarmWatchExternalSourceIdentities({
    boundary: context.boundary_geojson,
    dependencyKeys: keys,
    fetchImpl: args.fetchImpl,
  })
  return {
    sourceSignature: appendFarmWatchExternalIdentitySignature(
      args.sourceSignature,
      observations,
    ),
    observations,
  }
}

export async function resolveFarmWatchAllExternalSourceOverridesForProperty(args: {
  admin: any
  slug: string
  fetchImpl?: typeof fetch
}) {
  const [dependencyKeys, context] = await Promise.all([
    rpcValue(
      args.admin,
      'farm_watch_get_all_external_dependencies_v1_internal',
      {},
    ),
    rpcValue(
      args.admin,
      'farm_watch_get_materialization_identity_context_v1_internal',
      { p_slug: args.slug },
    ),
  ])
  if (context?.status !== 'available' || !context?.boundary_geojson) {
    throw new Error('materialization identity boundary is unavailable')
  }
  const keys = Array.isArray(dependencyKeys)
    ? dependencyKeys.map(String).filter(Boolean)
    : []
  const observations = await resolveFarmWatchExternalSourceIdentities({
    boundary: context.boundary_geojson,
    dependencyKeys: keys,
    fetchImpl: args.fetchImpl,
    requireAll: false,
  })
  return {
    observations,
    overrides: farmWatchExternalIdentityOverrides(observations),
  }
}
