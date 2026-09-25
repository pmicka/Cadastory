import 'jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.115.0'
import { fromArrayBuffer } from 'npm:geotiff@2.1.3'
import {
  FARM_WATCH_MULTISCALE_FOREST_CONTEXT_PRODUCT,
  validateFarmWatchMultiscaleForestContext,
} from '../_shared/farm-watch-multiscale-forest-contract.ts'

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

const SOURCE_URL =
  'https://ic.imagery1.arcgis.com/arcgis/rest/services/Sentinel2_10m_LandCover/ImageServer'
const SOURCE_ITEM_URL =
  'https://www.arcgis.com/home/item.html?id=785c6233e32843f3b7b1ed43427d3387'
const SOURCE_TIMEOUT_MS = 30000
const VALID_CLASSES = new Set([1, 2, 4, 5, 7, 8, 9, 10, 11])

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
  const bytes = typeof value === 'string' ? new TextEncoder().encode(value) : value
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))
  return [...digest].map((byte) => byte.toString(16).padStart(2, '0')).join('')
}

async function fetchText(url: string, timeoutMs = SOURCE_TIMEOUT_MS) {
  const response = await fetch(url, {
    headers: {
      accept: 'application/json, */*',
      'user-agent': 'Scout-by-Cadastory/1.0 (Farm Watch forest context)',
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
  if (value?.error) {
    throw new Error(value.error?.message || 'ArcGIS source returned an error')
  }
  return { text, value }
}

function latestSourceYear(metadata: any) {
  const end = Number(metadata?.timeInfo?.timeExtent?.[1])
  if (!Number.isFinite(end)) throw new Error('source time extent is unavailable')
  const year = new Date(end).getUTCFullYear()
  if (!Number.isInteger(year) || year < 2017 || year > 2100) {
    throw new Error('source latest annual year is invalid')
  }
  return year
}

function exportUrl(request: any, sourceYear: number) {
  const bbox = request?.raster_request?.bbox_utm
  const width = Number(request?.raster_request?.width)
  const height = Number(request?.raster_request?.height)
  if (
    !Array.isArray(bbox) ||
    bbox.length !== 4 ||
    !bbox.every((value: unknown) => Number.isFinite(Number(value))) ||
    !Number.isInteger(width) ||
    !Number.isInteger(height) ||
    width < 1 ||
    height < 1 ||
    width > 1000 ||
    height > 1000
  ) {
    throw new Error('invalid forest raster request')
  }

  const url = new URL(SOURCE_URL + '/exportImage')
  url.searchParams.set('bbox', bbox.map((value: unknown) => Number(value)).join(','))
  url.searchParams.set('bboxSR', '32616')
  url.searchParams.set('imageSR', '32616')
  url.searchParams.set('size', width + ',' + height)
  url.searchParams.set('format', 'tiff')
  url.searchParams.set('pixelType', 'U8')
  url.searchParams.set('interpolation', 'RSP_NearestNeighbor')
  url.searchParams.set('mosaicRule', JSON.stringify({
    mosaicMethod: 'esriMosaicAttribute',
    sortField: 'Year',
    sortValue: sourceYear,
  }))
  url.searchParams.set('f', 'json')
  return url.toString()
}

function metricForRadius(args: {
  raster: ArrayLike<number>
  width: number
  height: number
  xmin: number
  ymax: number
  pixelWidth: number
  pixelHeight: number
  anchorX: number
  anchorY: number
  radius: 30 | 90 | 270
}) {
  const {
    raster, width, height, xmin, ymax, pixelWidth, pixelHeight,
    anchorX, anchorY, radius,
  } = args

  const inRadius = new Uint8Array(width * height)
  const edgeEligible = new Uint8Array(width * height)
  const forest = new Uint8Array(width * height)

  let validCount = 0
  let forestCount = 0
  let builtCount = 0
  let cloudCount = 0
  let excludedCount = 0
  let edgeMetricCount = 0

  for (let row = 0; row < height; row += 1) {
    const y = ymax - (row + 0.5) * pixelHeight
    for (let col = 0; col < width; col += 1) {
      const x = xmin + (col + 0.5) * pixelWidth
      if (Math.hypot(x - anchorX, y - anchorY) > radius) continue

      const index = row * width + col
      inRadius[index] = 1
      const klass = Math.round(Number(raster[index]))
      if (!VALID_CLASSES.has(klass)) {
        excludedCount += 1
        continue
      }
      if (klass === FARM_WATCH_MULTISCALE_FOREST_CONTEXT_PRODUCT.cloudClassValue) {
        cloudCount += 1
        continue
      }

      validCount += 1
      if (klass === FARM_WATCH_MULTISCALE_FOREST_CONTEXT_PRODUCT.forestClassValue) {
        forestCount += 1
        forest[index] = 1
      }
      if (klass === FARM_WATCH_MULTISCALE_FOREST_CONTEXT_PRODUCT.builtClassValue) {
        builtCount += 1
        continue
      }

      edgeEligible[index] = 1
      edgeMetricCount += 1
    }
  }

  if (validCount < 1 || edgeMetricCount < 1) {
    throw new Error('forest focal window contains no usable land-cover cells at ' + radius + ' m')
  }

  let edgeLengthM = 0
  for (let row = 0; row < height; row += 1) {
    for (let col = 0; col < width; col += 1) {
      const index = row * width + col
      if (!inRadius[index] || !edgeEligible[index]) continue

      if (col + 1 < width) {
        const right = index + 1
        if (
          inRadius[right] &&
          edgeEligible[right] &&
          forest[index] !== forest[right]
        ) {
          edgeLengthM += pixelHeight
        }
      }

      if (row + 1 < height) {
        const down = index + width
        if (
          inRadius[down] &&
          edgeEligible[down] &&
          forest[index] !== forest[down]
        ) {
          edgeLengthM += pixelWidth
        }
      }
    }
  }

  const edgeMetricAreaM2 = edgeMetricCount * pixelWidth * pixelHeight
  const forestProportion = forestCount / validCount

  return {
    radius_m: radius,
    valid_landcover_cell_count: validCount,
    forest_cell_count: forestCount,
    forest_proportion: forestProportion,
    forest_percent: forestProportion * 100,
    built_cell_count: builtCount,
    cloud_cell_count: cloudCount,
    excluded_or_nodata_cell_count: excludedCount,
    edge_metric_cell_count: edgeMetricCount,
    edge_metric_area_ha: edgeMetricAreaM2 / 10000,
    forest_edge_length_m: edgeLengthM,
    forest_edge_density_m_per_ha: edgeLengthM / edgeMetricAreaM2 * 10000,
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return json({ error: 'not found' }, 404)

  try {
    const body = await req.json().catch(() => ({}))
    const slug = boundedSlug(body?.property || 'validation-property-01')
    if (!slug) return json({ error: 'invalid request' }, 400)

    const lon = finiteCoordinate(body?.lon, -180, 180)
    const lat = finiteCoordinate(body?.lat, -90, 90)
    if (Number.isNaN(lon) || Number.isNaN(lat) || ((lon == null) !== (lat == null))) {
      return json({ error: 'invalid request' }, 400)
    }

    const workerToken = typeof body?.worker_token === 'string'
      ? body.worker_token
      : null
    const { data: workerAllowed, error: workerError } = await admin.rpc(
      'farm_watch_validate_materialization_worker_v1_internal',
      { p_token: workerToken },
    )
    if (workerError || workerAllowed !== true) return json({ error: 'not found' }, 404)

    const { data: requestData, error: requestError } = await admin.rpc(
      'farm_watch_get_multiscale_forest_request_v1_internal',
      {
        p_slug: slug,
        p_lon: lon,
        p_lat: lat,
      },
    )
    if (requestError) throw new Error(requestError.message)
    if (requestData?.status !== 'available') {
      return json({
        ok: true,
        status: requestData?.status || 'unavailable',
        property: requestData?.property || { slug },
      })
    }

    const metadata = await fetchJson(SOURCE_URL + '?f=json')
    const sourceYear = latestSourceYear(metadata.value)
    const metadataSha256 = await sha256Hex(metadata.text)

    const exported = await fetchJson(exportUrl(requestData, sourceYear))
    const href = String(exported.value?.href || '')
    const extent = exported.value?.extent
    if (
      !href.startsWith('https://') ||
      !extent ||
      !Number.isFinite(Number(extent.xmin)) ||
      !Number.isFinite(Number(extent.ymin)) ||
      !Number.isFinite(Number(extent.xmax)) ||
      !Number.isFinite(Number(extent.ymax))
    ) {
      throw new Error('forest raster export did not return a usable image')
    }

    const rasterResponse = await fetch(href, {
      headers: {
        accept: 'image/tiff, application/octet-stream, */*',
        'user-agent': 'Scout-by-Cadastory/1.0 (Farm Watch forest context)',
      },
      signal: AbortSignal.timeout(SOURCE_TIMEOUT_MS),
    })
    if (!rasterResponse.ok) {
      throw new Error('forest raster export returned HTTP ' + rasterResponse.status)
    }

    const arrayBuffer = await rasterResponse.arrayBuffer()
    const rasterSha256 = await sha256Hex(new Uint8Array(arrayBuffer))
    const tiff: any = await fromArrayBuffer(arrayBuffer)
    const image: any = await tiff.getImage()
    const width = Number(image.getWidth())
    const height = Number(image.getHeight())
    const pixels: any = await image.readRasters({ interleave: true })

    if (
      width !== Number(exported.value?.width) ||
      height !== Number(exported.value?.height) ||
      pixels.length !== width * height
    ) {
      throw new Error('forest raster dimensions are inconsistent')
    }

    const xmin = Number(extent.xmin)
    const ymin = Number(extent.ymin)
    const xmax = Number(extent.xmax)
    const ymax = Number(extent.ymax)
    const pixelWidth = (xmax - xmin) / width
    const pixelHeight = (ymax - ymin) / height
    if (
      Math.abs(pixelWidth - 10) > 0.05 ||
      Math.abs(pixelHeight - 10) > 0.05
    ) {
      throw new Error(
        'forest raster support is not 10 m: ' +
          pixelWidth.toFixed(4) + ' x ' + pixelHeight.toFixed(4),
      )
    }

    const anchorX = Number(requestData?.evaluation_point?.x_utm)
    const anchorY = Number(requestData?.evaluation_point?.y_utm)
    if (!Number.isFinite(anchorX) || !Number.isFinite(anchorY)) {
      throw new Error('forest evaluation point is unavailable')
    }

    const focalMetrics = FARM_WATCH_MULTISCALE_FOREST_CONTEXT_PRODUCT.focalRadiiM
      .map((radius) => metricForRadius({
        raster: pixels,
        width,
        height,
        xmin,
        ymax,
        pixelWidth,
        pixelHeight,
        anchorX,
        anchorY,
        radius,
      }))

    const retrievedAt = new Date().toISOString()
    const context = {
      schema: FARM_WATCH_MULTISCALE_FOREST_CONTEXT_PRODUCT.outputSchemaVersion,
      method: FARM_WATCH_MULTISCALE_FOREST_CONTEXT_PRODUCT.algorithmVersion,
      evidence_class: 'deterministic_derived',
      source: {
        slug: FARM_WATCH_MULTISCALE_FOREST_CONTEXT_PRODUCT.sourceSlug,
        name: FARM_WATCH_MULTISCALE_FOREST_CONTEXT_PRODUCT.sourceName,
        authority: 'Impact Observatory / Esri / Microsoft',
        source_item_url: SOURCE_ITEM_URL,
        image_service_url: SOURCE_URL,
        source_year: sourceYear,
        spatial_resolution_m:
          FARM_WATCH_MULTISCALE_FOREST_CONTEXT_PRODUCT.sourceResolutionM,
        forest_class: 'Trees',
        forest_class_value:
          FARM_WATCH_MULTISCALE_FOREST_CONTEXT_PRODUCT.forestClassValue,
        built_class: 'Built Area',
        built_class_value:
          FARM_WATCH_MULTISCALE_FOREST_CONTEXT_PRODUCT.builtClassValue,
        cloud_class_value:
          FARM_WATCH_MULTISCALE_FOREST_CONTEXT_PRODUCT.cloudClassValue,
        license: 'CC BY 4.0',
        attribution:
          'Impact Observatory, Microsoft, and Esri; source imagery ESA Sentinel-2',
        service_metadata_sha256: metadataSha256,
      },
      evaluation_point: requestData.evaluation_point,
      raster_support: {
        crs: 'EPSG:32616',
        width,
        height,
        pixel_width_m: pixelWidth,
        pixel_height_m: pixelHeight,
        extent_utm: [xmin, ymin, xmax, ymax],
        exported_raster_sha256: rasterSha256,
        resampling: 'nearest_neighbor',
      },
      source_method_alignment: {
        study: 'Stephens et al. 2024, Landscape Ecology 39:84',
        study_landcover_source:
          'Dynamic World 10 m dominant LULC composite, 2015-06-01 through 2019-12-31',
        study_forest_class: 'trees',
        study_focal_radii_m: [30, 90, 270],
        study_forest_metric: 'proportion',
        study_forest_edge_metric:
          'landscape edge density (m/ha), forest relative to other land-cover types with built removed',
        study_edge_package:
          'landscapemetrics 1.5.6 lsm_l_ed; count_boundary default false',
        farm_watch_source_substitution:
          FARM_WATCH_MULTISCALE_FOREST_CONTEXT_PRODUCT.sourceSubstitution,
        farm_watch_edge_algorithm:
          'binary Trees-versus-other rook-adjacency internal edge length; Built Area and cloud/no-data removed; focal-window boundary not counted',
      },
      focal_metrics: focalMetrics,
      retrieved_at: retrievedAt,
      deer_inference_performed: false,
      coefficient_transfer_performed: false,
      scoring_performed: false,
      interpretation_boundary:
        'This product reproduces the forest-proportion/configuration variable family and source spatial scales. It does not assign forest selection, infer dispersal, classify the property as equivalent to either Missouri study landscape, or transfer any Stephens coefficient/direction. The land-cover source is a documented 10 m Sentinel-2 classification substitution for Dynamic World.',
    }

    if (!validateFarmWatchMultiscaleForestContext(context)) {
      throw new Error('forest context failed contract validation')
    }

    let materialized: any = null
    if (requestData?.persist_property_center === true) {
      const { data, error } = await admin.rpc(
        'farm_watch_record_multiscale_forest_context_v1_internal',
        {
          p_slug: slug,
          p_source_year: sourceYear,
          p_source_metadata_sha256: metadataSha256,
          p_context: context,
          p_retrieved_at: retrievedAt,
        },
      )
      if (error) throw new Error(error.message)
      materialized = data
    }

    return json({
      ok: true,
      status: 'available',
      property: requestData.property,
      context,
      materialized,
    })
  } catch (error) {
    console.error(
      'Farm Watch multiscale forest context failed',
      error instanceof Error ? error.message : error,
    )
    return json(
      { ok: false, status: 'unavailable', error: error instanceof Error ? error.message : String(error) },
      500,
    )
  }
})
