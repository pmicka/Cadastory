import 'jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.115.0'
import { fromArrayBuffer } from 'npm:geotiff@2.1.3'
import {
  FARM_WATCH_FOREST_TYPE_CONTEXT_LIMITATIONS,
  FARM_WATCH_FOREST_TYPE_CONTEXT_PRODUCT,
  validateForestTypeContext,
} from '../_shared/farm-watch-forest-type-context-contract.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
let SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
try {
  const keys = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') || '{}')
  SERVICE_KEY = keys.default || SERVICE_KEY
} catch { /* legacy fallback */ }
if (!SERVICE_KEY) throw new Error('Farm Watch service credential is unavailable')

const admin: any = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
})

const SOURCE_TIMEOUT_MS = 30000
const MIN_LANDFIRE_VERSION = 2024

type Json = Record<string, any>
type EvtRow = {
  value: number
  evt_name: string
  evt_lf: string
  evt_phys: string
  evt_gp: string
  evt_gp_n: string
  saf_srm: string
  evt_order: string
  evt_class: string
  evt_sbcls: string
}
type SourceBundle = {
  version: number
  evtService: string
  evcService: string
  evtTableUrl: string
  evcTableUrl: string
  evtValue: number
  evcValue: number
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store, max-age=0',
      pragma: 'no-cache',
      'referrer-policy': 'no-referrer',
      'x-content-type-options': 'nosniff',
    },
  })
}

function boundedSlug(value: unknown) {
  const normalized = String(value || '').trim().toLowerCase()
  return /^[a-z0-9][a-z0-9-]{0,79}$/.test(normalized) ? normalized : null
}

function finiteCoordinate(value: unknown, min: number, max: number) {
  if (value == null || value === '') return null
  const number = Number(value)
  return Number.isFinite(number) && number >= min && number <= max ? number : NaN
}

async function sha256Hex(value: string | Uint8Array) {
  const source = typeof value === 'string' ? new TextEncoder().encode(value) : value
  const bytes = new Uint8Array(source.byteLength)
  bytes.set(source)
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes.buffer))
  return [...digest].map((byte) => byte.toString(16).padStart(2, '0')).join('')
}

async function fetchText(url: string, timeoutMs = SOURCE_TIMEOUT_MS) {
  const response = await fetch(url, {
    headers: {
      accept: 'application/json,text/csv,*/*',
      'user-agent': 'Scout-by-Cadastory/1.0 (Farm Watch forest type context)',
    },
    signal: AbortSignal.timeout(timeoutMs),
  })
  const text = await response.text()
  if (!response.ok) throw new Error('source returned HTTP ' + response.status)
  return text
}

async function fetchJson(url: string, timeoutMs = SOURCE_TIMEOUT_MS) {
  const text = await fetchText(url, timeoutMs)
  let value: any
  try {
    value = JSON.parse(text)
  } catch {
    throw new Error('source returned non-JSON content')
  }
  if (value?.error) throw new Error(value.error?.message || 'ArcGIS source returned an error')
  return { text, value }
}

function serviceUrls(version: number) {
  return {
    evtService:
      `https://lfps.usgs.gov/arcgis/rest/services/Landfire_LF${version}/LF${version}_EVT_CONUS/ImageServer`,
    evcService:
      `https://lfps.usgs.gov/arcgis/rest/services/Landfire_LF${version}/LF${version}_EVC_CONUS/ImageServer`,
    evtTableUrl:
      `https://www.landfire.gov/sites/default/files/CSV/${version}/LF${version}_EVT.csv`,
    evcTableUrl:
      `https://www.landfire.gov/sites/default/files/CSV/${version}/LF${version}_EVC.csv`,
  }
}

async function identifyValue(base: string, x: number, y: number) {
  const url = new URL(base.replace(/\/$/, '') + '/identify')
  url.searchParams.set('geometry', JSON.stringify({
    x,
    y,
    spatialReference: { wkid: FARM_WATCH_FOREST_TYPE_CONTEXT_PRODUCT.sourceNativeWkid },
  }))
  url.searchParams.set('geometryType', 'esriGeometryPoint')
  url.searchParams.set('returnGeometry', 'false')
  url.searchParams.set('f', 'json')
  const { value } = await fetchJson(url.toString())
  const number = Number(value?.value)
  return Number.isFinite(number) ? Math.round(number) : null
}

async function chooseSourceVersion(x: number, y: number): Promise<SourceBundle> {
  const currentYear = new Date().getUTCFullYear()
  const candidates = Array.from(
    { length: Math.max(1, currentYear - MIN_LANDFIRE_VERSION + 1) },
    (_, index) => currentYear - index,
  ).filter((version) => version >= MIN_LANDFIRE_VERSION)

  const failures: string[] = []
  for (const version of candidates) {
    const urls = serviceUrls(version)
    try {
      const [evtValue, evcValue] = await Promise.all([
        identifyValue(urls.evtService, x, y),
        identifyValue(urls.evcService, x, y),
      ])
      if (evtValue !== null && evcValue !== null) {
        return { version, ...urls, evtValue, evcValue }
      }
      failures.push(`LF${version}: NoData at evaluation point`)
    } catch (error) {
      failures.push(
        `LF${version}: ${error instanceof Error ? error.message : String(error)}`,
      )
    }
  }
  throw new Error(
    'No current LANDFIRE EVT/EVC version is available at the evaluation point: ' +
      failures.join('; '),
  )
}

function parseCsv(text: string) {
  const rows: string[][] = []
  let row: string[] = []
  let field = ''
  let quoted = false
  for (let i = 0; i < text.length; i += 1) {
    const ch = text[i]
    if (quoted) {
      if (ch === '"' && text[i + 1] === '"') {
        field += '"'
        i += 1
      } else if (ch === '"') {
        quoted = false
      } else {
        field += ch
      }
      continue
    }
    if (ch === '"') {
      quoted = true
    } else if (ch === ',') {
      row.push(field)
      field = ''
    } else if (ch === '\n') {
      row.push(field.replace(/\r$/, ''))
      if (row.some((value) => value !== '')) rows.push(row)
      row = []
      field = ''
    } else {
      field += ch
    }
  }
  if (field || row.length) {
    row.push(field.replace(/\r$/, ''))
    if (row.some((value) => value !== '')) rows.push(row)
  }
  return rows
}

function tableRecords(text: string) {
  const rows = parseCsv(text)
  if (rows.length < 2) throw new Error('LANDFIRE attribute table is empty')
  const headers = rows[0].map((value) => value.trim())
  return rows.slice(1).map((values) =>
    Object.fromEntries(headers.map((header, index) => [header, values[index] ?? '']))
  )
}

function evtCatalog(text: string) {
  const map = new Map<number, EvtRow>()
  for (const row of tableRecords(text)) {
    const value = Number(row.VALUE)
    if (!Number.isInteger(value) || value < 0) continue
    map.set(value, {
      value,
      evt_name: String(row.EVT_NAME || ''),
      evt_lf: String(row.EVT_LF || ''),
      evt_phys: String(row.EVT_PHYS || ''),
      evt_gp: String(row.EVT_GP || ''),
      evt_gp_n: String(row.EVT_GP_N || ''),
      saf_srm: String(row.SAF_SRM || ''),
      evt_order: String(row.EVT_ORDER || ''),
      evt_class: String(row.EVT_CLASS || ''),
      evt_sbcls: String(row.EVT_SBCLS || ''),
    })
  }
  if (!map.size) throw new Error('LANDFIRE EVT attribute catalog did not parse')
  return map
}

function evcTreeCoverCatalog(text: string) {
  const map = new Map<number, number | null>()
  for (const row of tableRecords(text)) {
    const value = Number(row.VALUE)
    if (!Number.isInteger(value) || value < 0) continue
    const match = /^Tree Cover\s*=\s*(\d+(?:\.\d+)?)%$/i.exec(
      String(row.CLASSNAMES || '').trim(),
    )
    map.set(value, match ? Number(match[1]) : null)
  }
  if (!map.size) throw new Error('LANDFIRE EVC attribute catalog did not parse')
  return map
}

function pointClassification(
  evtValue: number,
  evcValue: number,
  evt: Map<number, EvtRow>,
  evc: Map<number, number | null>,
) {
  const row = evt.get(evtValue)
  if (!row) throw new Error('LANDFIRE EVT value is absent from the matching attribute table')
  const treeCoverPercent = evc.get(evcValue) ?? null
  const hardwood = row.evt_lf === 'Tree' && row.evt_phys === 'Hardwood'
  return {
    evt: {
      value: row.value,
      name: row.evt_name,
      lifeform: row.evt_lf,
      physiognomy: row.evt_phys,
      group_code: row.evt_gp || null,
      group_name: row.evt_gp_n || null,
      saf_srm: row.saf_srm || null,
      physiognomic_order: row.evt_order || null,
      physiognomic_class: row.evt_class || null,
      physiognomic_subclass: row.evt_sbcls || null,
    },
    evc_value: evcValue,
    tree_cover_percent: treeCoverPercent,
    hardwood_deciduous_proxy: hardwood,
    proxy_basis:
      'LANDFIRE EVT lifeform=Tree and physiognomy=Hardwood. This is a mapped hardwood/deciduous composition proxy, not an AVI species-specific crown-closure measurement or biological intactness score.',
  }
}

async function exportRaster(
  base: string,
  bbox: number[],
  width: number,
  height: number,
) {
  const url = new URL(base.replace(/\/$/, '') + '/exportImage')
  url.searchParams.set('bbox', bbox.join(','))
  url.searchParams.set('bboxSR', String(FARM_WATCH_FOREST_TYPE_CONTEXT_PRODUCT.sourceNativeWkid))
  url.searchParams.set('imageSR', String(FARM_WATCH_FOREST_TYPE_CONTEXT_PRODUCT.sourceNativeWkid))
  url.searchParams.set('size', width + ',' + height)
  url.searchParams.set('format', 'tiff')
  url.searchParams.set('pixelType', 'S16')
  url.searchParams.set('interpolation', 'RSP_NearestNeighbor')
  url.searchParams.set('f', 'json')

  const { value: exported } = await fetchJson(url.toString())
  const href = String(exported?.href || '')
  if (!href.startsWith('https://')) {
    throw new Error('LANDFIRE export did not return a secure TIFF URL')
  }

  const response = await fetch(href, {
    headers: {
      accept: 'image/tiff,application/octet-stream,*/*',
      'user-agent': 'Scout-by-Cadastory/1.0 (Farm Watch forest type context)',
    },
    signal: AbortSignal.timeout(SOURCE_TIMEOUT_MS),
  })
  if (!response.ok) throw new Error('LANDFIRE TIFF export returned HTTP ' + response.status)

  const bytes = new Uint8Array(await response.arrayBuffer())
  if (!bytes.byteLength || bytes.byteLength > 15 * 1024 * 1024) {
    throw new Error('LANDFIRE TIFF export size is invalid')
  }
  const sourceSha256 = await sha256Hex(bytes)
  const tiff: any = await fromArrayBuffer(bytes.buffer)
  const image: any = await tiff.getImage()
  const rasterWidth = Number(image.getWidth())
  const rasterHeight = Number(image.getHeight())
  if (rasterWidth !== width || rasterHeight !== height) {
    throw new Error(
      'LANDFIRE raster dimensions changed: ' + rasterWidth + 'x' + rasterHeight,
    )
  }
  const pixels: any = await image.readRasters({ interleave: true })
  if (pixels.length !== width * height) {
    throw new Error('LANDFIRE raster pixel count is inconsistent')
  }

  const imageBbox = image.getBoundingBox().map(Number)
  const xStep = (imageBbox[2] - imageBbox[0]) / width
  const yStep = (imageBbox[3] - imageBbox[1]) / height
  if (
    Math.abs(xStep - FARM_WATCH_FOREST_TYPE_CONTEXT_PRODUCT.sourcePixelMeters) > 0.05 ||
    Math.abs(yStep - FARM_WATCH_FOREST_TYPE_CONTEXT_PRODUCT.sourcePixelMeters) > 0.05
  ) {
    throw new Error(
      'LANDFIRE raster support is not 30 m: ' +
        xStep.toFixed(4) + ' x ' + yStep.toFixed(4),
    )
  }

  return {
    pixels,
    bbox: imageBbox,
    width,
    height,
    xStep,
    yStep,
    sha256: sourceSha256,
    byteLength: bytes.byteLength,
  }
}

function pointInRing(x: number, y: number, ring: any[]) {
  let inside = false
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const xi = Number(ring[i]?.[0])
    const yi = Number(ring[i]?.[1])
    const xj = Number(ring[j]?.[0])
    const yj = Number(ring[j]?.[1])
    const crosses =
      ((yi > y) !== (yj > y)) &&
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

function scopeSummary(args: {
  geometry: Json
  evtRaster: any
  evcRaster: any
  rasterBbox: number[]
  width: number
  height: number
  evt: Map<number, EvtRow>
  evc: Map<number, number | null>
}) {
  const {
    geometry,
    evtRaster,
    evcRaster,
    rasterBbox,
    width,
    height,
    evt,
    evc,
  } = args
  const xStep = (rasterBbox[2] - rasterBbox[0]) / width
  const yStep = (rasterBbox[3] - rasterBbox[1]) / height

  let modeled = 0
  let trees = 0
  let hardwood = 0
  let hardwoodCoverObserved = 0
  let hardwoodCoverSum = 0
  const classes = new Map<number, number>()
  const physiognomy = new Map<string, number>()

  for (let row = 0; row < height; row += 1) {
    const y = rasterBbox[3] - (row + 0.5) * yStep
    for (let col = 0; col < width; col += 1) {
      const x = rasterBbox[0] + (col + 0.5) * xStep
      if (!pointInGeometry(x, y, geometry)) continue
      const index = row * width + col
      const evtValue = Math.round(Number(evtRaster[index]))
      const evtRow = evt.get(evtValue)
      if (!evtRow) continue

      modeled += 1
      classes.set(evtValue, (classes.get(evtValue) || 0) + 1)
      physiognomy.set(
        evtRow.evt_phys || 'Unknown',
        (physiognomy.get(evtRow.evt_phys || 'Unknown') || 0) + 1,
      )

      if (evtRow.evt_lf === 'Tree') trees += 1
      const isHardwood = evtRow.evt_lf === 'Tree' && evtRow.evt_phys === 'Hardwood'
      if (!isHardwood) continue

      hardwood += 1
      const evcValue = Math.round(Number(evcRaster[index]))
      const cover = evc.get(evcValue)
      if (typeof cover === 'number' && Number.isFinite(cover)) {
        hardwoodCoverObserved += 1
        hardwoodCoverSum += cover
      }
    }
  }

  if (modeled <= 0) throw new Error('forest type scope contains no modeled LANDFIRE cells')

  const topEvtClasses = [...classes.entries()]
    .sort((a, b) => b[1] - a[1] || a[0] - b[0])
    .slice(0, 12)
    .map(([value, cellCount]) => {
      const row = evt.get(value)!
      return {
        value,
        name: row.evt_name,
        lifeform: row.evt_lf,
        physiognomy: row.evt_phys,
        group_name: row.evt_gp_n || null,
        cell_count: cellCount,
        cell_share_percent: cellCount / modeled * 100,
      }
    })

  const physiognomyShares = [...physiognomy.entries()]
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
    .map(([name, cellCount]) => ({
      physiognomy: name,
      cell_count: cellCount,
      cell_share_percent: cellCount / modeled * 100,
    }))

  return {
    modeled_cell_count: modeled,
    tree_cell_count: trees,
    hardwood_cell_count: hardwood,
    hardwood_cell_share_percent: hardwood / modeled * 100,
    hardwood_share_of_tree_cells_percent: trees ? hardwood / trees * 100 : null,
    hardwood_canopy_observed_cell_count: hardwoodCoverObserved,
    hardwood_canopy_equivalent_percent_of_area:
      hardwoodCoverObserved ? hardwoodCoverSum / modeled : null,
    mean_tree_cover_percent_within_hardwood_cells:
      hardwoodCoverObserved ? hardwoodCoverSum / hardwoodCoverObserved : null,
    top_evt_classes: topEvtClasses,
    physiognomy_shares: physiognomyShares,
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return json({ error: 'not found' }, 404)

  try {
    const body = await req.json().catch(() => ({}))
    const slug = boundedSlug(body?.property || 'validation-property-01')
    if (!slug) return json({ error: 'invalid request' }, 400)

    const workerToken = typeof body?.worker_token === 'string' ? body.worker_token : null
    const { data: workerAllowed, error: workerError } = await admin.rpc(
      'farm_watch_validate_materialization_worker_v1_internal',
      { p_token: workerToken },
    )
    if (workerError || workerAllowed !== true) return json({ error: 'not found' }, 404)

    const { data: requestData, error: requestError } = await admin.rpc(
      'farm_watch_get_forest_type_context_request_v1_internal',
      { p_slug: slug },
    )
    if (requestError) throw new Error(requestError.message)
    if (requestData?.status !== 'available') {
      return json({
        ok: true,
        status: requestData?.status || 'unavailable',
        property: requestData?.property || { slug },
      })
    }

    const pointX = Number(requestData?.evaluation_point?.x_5070)
    const pointY = Number(requestData?.evaluation_point?.y_5070)
    if (!Number.isFinite(pointX) || !Number.isFinite(pointY)) {
      throw new Error('forest type evaluation point is unavailable')
    }

    const selected = await chooseSourceVersion(pointX, pointY)
    const [evtMetadata, evcMetadata, evtTableText, evcTableText] = await Promise.all([
      fetchText(selected.evtService + '?f=json'),
      fetchText(selected.evcService + '?f=json'),
      fetchText(selected.evtTableUrl),
      fetchText(selected.evcTableUrl),
    ])
    const evt = evtCatalog(evtTableText)
    const evc = evcTreeCoverCatalog(evcTableText)
    const source = {
      authority: FARM_WATCH_FOREST_TYPE_CONTEXT_PRODUCT.sourceAuthority,
      product: FARM_WATCH_FOREST_TYPE_CONTEXT_PRODUCT.sourceProduct,
      landfire_version: selected.version,
      spatial_resolution_m: FARM_WATCH_FOREST_TYPE_CONTEXT_PRODUCT.sourcePixelMeters,
      native_crs: FARM_WATCH_FOREST_TYPE_CONTEXT_PRODUCT.sourceNativeCrs,
      evt_service_url: selected.evtService,
      evc_service_url: selected.evcService,
      evt_attribute_table_url: selected.evtTableUrl,
      evc_attribute_table_url: selected.evcTableUrl,
      evt_service_metadata_sha256: await sha256Hex(evtMetadata),
      evc_service_metadata_sha256: await sha256Hex(evcMetadata),
      evt_attribute_table_sha256: await sha256Hex(evtTableText),
      evc_attribute_table_sha256: await sha256Hex(evcTableText),
      evt_hardwood_proxy_rule: 'EVT_LF=Tree AND EVT_PHYS=Hardwood',
      evc_tree_cover_rule: 'CLASSNAMES=Tree Cover = N%',
    }

    const bbox = (requestData?.raster_request?.bbox_5070 || []).map(Number)
    const width = Number(requestData?.raster_request?.width)
    const height = Number(requestData?.raster_request?.height)
    if (
      bbox.length !== 4 ||
      !bbox.every(Number.isFinite) ||
      !Number.isInteger(width) ||
      !Number.isInteger(height) ||
      width <= 0 ||
      height <= 0 ||
      width * height > 300000
    ) {
      throw new Error('forest type raster request is invalid')
    }

    const [evtRaster, evcRaster] = await Promise.all([
      exportRaster(selected.evtService, bbox, width, height),
      exportRaster(selected.evcService, bbox, width, height),
    ])
    if (
      evtRaster.bbox.some((value: number, index: number) =>
        Math.abs(value - evcRaster.bbox[index]) > 0.01
      )
    ) {
      throw new Error('LANDFIRE EVT and EVC grids are not co-registered')
    }

    const zones = requestData?.zones_5070 || {}
    const scopes = Object.fromEntries(
      FARM_WATCH_FOREST_TYPE_CONTEXT_PRODUCT.scopeOrder.map((scope) => {
        const geometry = zones?.[scope]
        if (!geometry) throw new Error('forest type zone unavailable: ' + scope)
        return [scope, scopeSummary({
          geometry,
          evtRaster: evtRaster.pixels,
          evcRaster: evcRaster.pixels,
          rasterBbox: evtRaster.bbox,
          width,
          height,
          evt,
          evc,
        })]
      }),
    )

    const retrievedAt = new Date().toISOString()
    const context = {
      schema: FARM_WATCH_FOREST_TYPE_CONTEXT_PRODUCT.outputSchemaVersion,
      method: FARM_WATCH_FOREST_TYPE_CONTEXT_PRODUCT.algorithmVersion,
      status: 'available',
      evidence_class: FARM_WATCH_FOREST_TYPE_CONTEXT_PRODUCT.semanticEvidenceClass,
      source: {
        ...source,
        evt_export_sha256: evtRaster.sha256,
        evc_export_sha256: evcRaster.sha256,
      },
      source_alignment: {
        source_study: 'Darlington et al. 2022, Scientific Reports 12:1072',
        source_measurement:
          'Alberta Vegetation Inventory percent crown closure of dominant overstorey species',
        source_natural_variables:
          'species-specific PCT overstorey crown-closure variables plus distance to wetland',
        farm_watch_alignment: 'calibrated_proxy',
        reason:
          'LANDFIRE 30 m EVT hardwood physiognomy plus EVC tree cover provides an authoritative mapped deciduous/hardwood composition proxy for Kentucky, but it is not the source AVI species-specific crown-closure measurement.',
      },
      grid_support: {
        crs: FARM_WATCH_FOREST_TYPE_CONTEXT_PRODUCT.sourceNativeCrs,
        bbox: evtRaster.bbox,
        width,
        height,
        cell_meters: FARM_WATCH_FOREST_TYPE_CONTEXT_PRODUCT.sourcePixelMeters,
        resampling: 'nearest_neighbor',
      },
      source_selection: {
        selected_landfire_version: selected.version,
        probe_basis: 'property_center_internal_source_health_only',
        pixel_interpretation_exposed: false,
        probe_evt_value: selected.evtValue,
        probe_evc_value: selected.evcValue,
      },
      summary: { scopes },
      limitations: FARM_WATCH_FOREST_TYPE_CONTEXT_LIMITATIONS,
      intactness_metric_performed: false,
      behavioral_inference_performed: false,
      coefficient_transfer_performed: false,
      scoring_performed: false,
      retrieved_at: retrievedAt,
      interpretation_boundary:
        'Neutral aggregated mapped forest type/canopy context. The product does not calculate a generic intactness or fragmentation score and does not expose individual LANDFIRE pixels as M43 evidence. Hardwood EVT physiognomy is a calibrated deciduous-composition proxy for FW-M43; the Darlington relationship remains unavailable without its industrial human-footprint and wolf-occurrence inputs.',
    }

    if (!validateForestTypeContext(context)) {
      throw new Error('forest type context failed contract validation')
    }

    const { data: materialized, error: materializeError } = await admin.rpc(
      'farm_watch_record_forest_type_context_v1_internal',
      {
        p_slug: slug,
        p_landfire_version: selected.version,
        p_context: context,
        p_retrieved_at: retrievedAt,
      },
    )
    if (materializeError) throw new Error(materializeError.message)

    return json({
      ok: true,
      status: 'available',
      property: requestData.property,
      context,
      materialized,
    })
  } catch (error) {
    console.error(
      'Farm Watch forest type context failed',
      error instanceof Error ? error.message : error,
    )
    return json(
      {
        ok: false,
        status: 'unavailable',
        error: error instanceof Error ? error.message : String(error),
      },
      500,
    )
  }
})
