import 'jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.115.0'
import { fromArrayBuffer } from 'npm:geotiff@2.1.3'
import {
  FARM_WATCH_FOREST_TYPE_CONTEXT_PRODUCT,
  validateFarmWatchForestTypeContext,
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

const SOURCE_URL =
  'https://di-nlcd.img.arcgis.com/arcgis/rest/services/USA_NLCD_Annual_LandCover/ImageServer'
const SOURCE_ITEM_URL = 'https://www.arcgis.com/home/item.html?id=32e2ccc6416746a9a72b4d216813f84f'
const SOURCE_TIMEOUT_MS = 45000
const SOURCE_VALID_VALUES = new Set([11, 12, 21, 22, 23, 24, 31, 41, 42, 43, 52, 71, 81, 82, 90, 95])
const NLCD_CLASS_ROWS = [
  { studyClassKey: 'pine_forest', value: 42, sourceClass: 'Evergreen Forest', sourceAlignment: 'broad evergreen-forest analogue for the source pine-forest class; not a pine-species map' },
  { studyClassKey: 'prairie', value: 71, sourceClass: 'Grassland/Herbaceous', sourceAlignment: 'unmanaged herbaceous analogue for the source prairie class; pasture/hay and crops are intentionally excluded' },
  { studyClassKey: 'shrub', value: 52, sourceClass: 'Shrub/Scrub', sourceAlignment: 'broad shrub/scrub analogue for the source shrub class' },
  { studyClassKey: 'hardwood_hammock', value: 41, sourceClass: 'Deciduous Forest', sourceAlignment: 'upland/broad deciduous-hardwood analogue; Florida hardwood hammock is not asserted to occur in Kentucky' },
] as const

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
      accept: 'application/json, */*',
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

function latestSourceYear(metadata: any) {
  const end = Number(metadata?.timeInfo?.timeExtent?.[1])
  if (!Number.isFinite(end)) throw new Error('Annual NLCD source time extent is unavailable')
  const year = new Date(end).getUTCFullYear()
  if (!Number.isInteger(year) || year < 1985 || year > 2100) throw new Error('Annual NLCD latest year is invalid')
  return year
}

function exportUrl(requestData: any, sourceYear: number) {
  const bbox = requestData?.raster_request?.bbox_utm
  const width = Number(requestData?.raster_request?.width)
  const height = Number(requestData?.raster_request?.height)
  if (
    !Array.isArray(bbox) || bbox.length !== 4 ||
    !bbox.every((value: unknown) => Number.isFinite(Number(value))) ||
    !Number.isInteger(width) || !Number.isInteger(height) ||
    width < 1 || height < 1 || width > 400 || height > 400
  ) throw new Error('invalid forest-type raster request')

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

function rasterDistanceToClass(args: {
  raster: ArrayLike<number>
  width: number
  height: number
  xmin: number
  ymax: number
  pixelWidth: number
  pixelHeight: number
  anchorX: number
  anchorY: number
  classValue: number
  searchRadiusM: number
}) {
  const { raster, width, height, xmin, ymax, pixelWidth, pixelHeight, anchorX, anchorY, classValue, searchRadiusM } = args
  let minDistance = Number.POSITIVE_INFINITY
  let matchingCells = 0
  let validCells = 0

  for (let row = 0; row < height; row += 1) {
    const y = ymax - (row + 0.5) * pixelHeight
    for (let col = 0; col < width; col += 1) {
      const x = xmin + (col + 0.5) * pixelWidth
      const distance = Math.hypot(x - anchorX, y - anchorY)
      if (distance > searchRadiusM) continue
      const klass = Math.round(Number(raster[row * width + col]))
      if (!SOURCE_VALID_VALUES.has(klass)) continue
      validCells += 1
      if (klass !== classValue) continue
      matchingCells += 1
      if (distance < minDistance) minDistance = distance
    }
  }

  if (validCells < 1) throw new Error('Annual NLCD raster contains no usable cells in search radius')
  if (matchingCells < 1) {
    return {
      status: 'right_censored',
      distance_m: null,
      distance_lower_bound_m: searchRadiusM,
      matching_cell_count: 0,
      valid_cell_count: validCells,
    }
  }

  const anchorCol = Math.floor((anchorX - xmin) / pixelWidth)
  const anchorRow = Math.floor((ymax - anchorY) / pixelHeight)
  const anchorIndex = anchorRow >= 0 && anchorRow < height && anchorCol >= 0 && anchorCol < width
    ? anchorRow * width + anchorCol : -1
  const anchorClass = anchorIndex >= 0 ? Math.round(Number(raster[anchorIndex])) : null

  return {
    status: 'available',
    distance_m: anchorClass === classValue ? 0 : Math.round(minDistance * 10) / 10,
    distance_lower_bound_m: null,
    matching_cell_count: matchingCells,
    valid_cell_count: validCells,
  }
}

function nwiDistanceRow(requestData: any, key: 'hardwood_swamp' | 'marsh') {
  const row = requestData?.nwi?.distances?.[key]
  const searchRadiusM = FARM_WATCH_FOREST_TYPE_CONTEXT_PRODUCT.searchRadiusM
  const sourceClass = key === 'hardwood_swamp'
    ? 'PFO1* — Palustrine Forested Broad-Leaved Deciduous'
    : 'PEM* — Palustrine Emergent'
  const sourceAlignment = key === 'hardwood_swamp'
    ? 'Cowardin broad-leaved deciduous forested wetland analogue for the source hardwood-swamp class'
    : 'Cowardin palustrine emergent wetland analogue for the source marsh class'

  if (requestData?.nwi?.status !== 'available') {
    return {
      study_class_key: key,
      study_class: key === 'hardwood_swamp' ? 'hardwood swamp' : 'marsh',
      status: 'unavailable',
      distance_m: null,
      source_family: 'nwi',
      source_slug: FARM_WATCH_FOREST_TYPE_CONTEXT_PRODUCT.nwiSourceSlug,
      source_class: sourceClass,
      source_alignment: sourceAlignment,
      exact_source_equivalent: false,
    }
  }

  const distance = Number(row?.distance_m)
  const count = Number(row?.matching_feature_count || 0)
  if (Number.isFinite(distance) && distance >= 0 && count > 0) {
    return {
      study_class_key: key,
      study_class: key === 'hardwood_swamp' ? 'hardwood swamp' : 'marsh',
      status: 'available',
      distance_m: Math.round(distance * 10) / 10,
      distance_lower_bound_m: null,
      matching_feature_count: count,
      source_family: 'nwi',
      source_slug: FARM_WATCH_FOREST_TYPE_CONTEXT_PRODUCT.nwiSourceSlug,
      source_class: sourceClass,
      source_alignment: sourceAlignment,
      exact_source_equivalent: false,
    }
  }

  return {
    study_class_key: key,
    study_class: key === 'hardwood_swamp' ? 'hardwood swamp' : 'marsh',
    status: 'right_censored',
    distance_m: null,
    distance_lower_bound_m: searchRadiusM,
    matching_feature_count: 0,
    source_family: 'nwi',
    source_slug: FARM_WATCH_FOREST_TYPE_CONTEXT_PRODUCT.nwiSourceSlug,
    source_class: sourceClass,
    source_alignment: sourceAlignment,
    exact_source_equivalent: false,
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

    const workerToken = typeof body?.worker_token === 'string' ? body.worker_token : null
    const { data: workerAllowed, error: workerError } = await admin.rpc(
      'farm_watch_validate_materialization_worker_v1_internal',
      { p_token: workerToken },
    )
    if (workerError || workerAllowed !== true) return json({ error: 'not found' }, 404)

    const { data: requestData, error: requestError } = await admin.rpc(
      'farm_watch_get_forest_type_context_request_v1_internal',
      { p_slug: slug, p_lon: lon, p_lat: lat },
    )
    if (requestError) throw new Error(requestError.message)
    if (requestData?.status !== 'available') {
      return json({ ok: true, status: requestData?.status || 'unavailable', property: requestData?.property || { slug } })
    }

    const metadata = await fetchJson(SOURCE_URL + '?f=json')
    const sourceYear = latestSourceYear(metadata.value)
    const metadataSha256 = await sha256Hex(metadata.text)

    const exported = await fetchJson(exportUrl(requestData, sourceYear))
    const href = String(exported.value?.href || '')
    const extent = exported.value?.extent
    if (
      !href.startsWith('https://') || !extent ||
      !Number.isFinite(Number(extent.xmin)) || !Number.isFinite(Number(extent.ymin)) ||
      !Number.isFinite(Number(extent.xmax)) || !Number.isFinite(Number(extent.ymax))
    ) throw new Error('Annual NLCD export did not return a usable image')

    const rasterResponse = await fetch(href, {
      headers: {
        accept: 'image/tiff, application/octet-stream, */*',
        'user-agent': 'Scout-by-Cadastory/1.0 (Farm Watch forest type context)',
      },
      signal: AbortSignal.timeout(SOURCE_TIMEOUT_MS),
    })
    if (!rasterResponse.ok) throw new Error('Annual NLCD raster export returned HTTP ' + rasterResponse.status)

    const arrayBuffer = await rasterResponse.arrayBuffer()
    const rasterSha256 = await sha256Hex(new Uint8Array(arrayBuffer))
    const tiff: any = await fromArrayBuffer(arrayBuffer)
    const image: any = await tiff.getImage()
    const width = Number(image.getWidth())
    const height = Number(image.getHeight())
    const pixels: any = await image.readRasters({ interleave: true })
    if (width !== Number(exported.value?.width) || height !== Number(exported.value?.height) || pixels.length !== width * height) {
      throw new Error('Annual NLCD raster dimensions are inconsistent')
    }

    const xmin = Number(extent.xmin)
    const ymin = Number(extent.ymin)
    const xmax = Number(extent.xmax)
    const ymax = Number(extent.ymax)
    const pixelWidth = (xmax - xmin) / width
    const pixelHeight = (ymax - ymin) / height
    if (Math.abs(pixelWidth - 30) > 0.1 || Math.abs(pixelHeight - 30) > 0.1) {
      throw new Error('Annual NLCD raster support is not 30 m: ' + pixelWidth.toFixed(4) + ' x ' + pixelHeight.toFixed(4))
    }

    const anchorX = Number(requestData?.evaluation_point?.x_utm)
    const anchorY = Number(requestData?.evaluation_point?.y_utm)
    if (!Number.isFinite(anchorX) || !Number.isFinite(anchorY)) throw new Error('forest-type evaluation point is unavailable')

    const searchRadiusM = FARM_WATCH_FOREST_TYPE_CONTEXT_PRODUCT.searchRadiusM
    const nlcdRows = NLCD_CLASS_ROWS.map((entry) => ({
      study_class_key: entry.studyClassKey,
      study_class: entry.studyClassKey.replaceAll('_', ' '),
      ...rasterDistanceToClass({
        raster: pixels, width, height, xmin, ymax, pixelWidth, pixelHeight,
        anchorX, anchorY, classValue: entry.value, searchRadiusM,
      }),
      source_family: 'annual_nlcd',
      source_slug: FARM_WATCH_FOREST_TYPE_CONTEXT_PRODUCT.nlcdSourceSlug,
      source_class: entry.sourceClass + ' (' + entry.value + ')',
      source_alignment: entry.sourceAlignment,
      exact_source_equivalent: false,
    }))

    const habitatDistances = [
      nlcdRows.find((row) => row.study_class_key === 'pine_forest'),
      nwiDistanceRow(requestData, 'hardwood_swamp'),
      nwiDistanceRow(requestData, 'marsh'),
      nlcdRows.find((row) => row.study_class_key === 'prairie'),
      nlcdRows.find((row) => row.study_class_key === 'shrub'),
      nlcdRows.find((row) => row.study_class_key === 'hardwood_hammock'),
    ]

    const retrievedAt = new Date().toISOString()
    const context = {
      schema: FARM_WATCH_FOREST_TYPE_CONTEXT_PRODUCT.outputSchemaVersion,
      method: FARM_WATCH_FOREST_TYPE_CONTEXT_PRODUCT.algorithmVersion,
      evidence_class: 'deterministic_derived',
      evidence_state: 'proxy',
      study_alignment: {
        study: FARM_WATCH_FOREST_TYPE_CONTEXT_PRODUCT.studyCitation,
        study_landcover_source: FARM_WATCH_FOREST_TYPE_CONTEXT_PRODUCT.studyLandcoverSource,
        study_spatial_resolution_m: FARM_WATCH_FOREST_TYPE_CONTEXT_PRODUCT.studyResolutionM,
        study_operation: 'reclassify habitat then calculate Euclidean distance from each raster cell to each habitat class; extract at used and available locations; scale and center model variables',
        study_classes: [...FARM_WATCH_FOREST_TYPE_CONTEXT_PRODUCT.studyClasses],
        coefficient_transfer: 'not_performed',
      },
      source_reconciliation: {
        search_radius_m: searchRadiusM,
        distance_support: 'evaluation-point to source-class geometry; raster classes use source-grid cell centers with zero assigned when the evaluation point falls in that class',
        annual_nlcd: {
          slug: FARM_WATCH_FOREST_TYPE_CONTEXT_PRODUCT.nlcdSourceSlug,
          authority: 'U.S. Geological Survey / Multi-Resolution Land Characteristics Consortium',
          source_item_url: SOURCE_ITEM_URL,
          image_service_url: SOURCE_URL,
          source_year: sourceYear,
          spatial_resolution_m: 30,
          service_metadata_sha256: metadataSha256,
          exported_raster_sha256: rasterSha256,
          class_map: {
            pine_forest: { value: 42, name: 'Evergreen Forest' },
            prairie: { value: 71, name: 'Grassland/Herbaceous' },
            shrub: { value: 52, name: 'Shrub/Scrub' },
            hardwood_hammock: { value: 41, name: 'Deciduous Forest' },
          },
        },
        nwi: {
          slug: FARM_WATCH_FOREST_TYPE_CONTEXT_PRODUCT.nwiSourceSlug,
          authority: 'U.S. Fish & Wildlife Service National Wetlands Inventory',
          status: requestData?.nwi?.status,
          buffer_m: requestData?.nwi?.buffer_m,
          retrieved_at: requestData?.nwi?.retrieved_at,
          class_map: {
            hardwood_swamp: { code_prefix: 'PFO1', name: 'Palustrine Forested Broad-Leaved Deciduous' },
            marsh: { code_prefix: 'PEM', name: 'Palustrine Emergent' },
          },
        },
      },
      evaluation_point: requestData.evaluation_point,
      raster_support: {
        crs: 'EPSG:32616', width, height,
        pixel_width_m: pixelWidth, pixel_height_m: pixelHeight,
        extent_utm: [xmin, ymin, xmax, ymax],
        resampling: 'nearest_neighbor',
      },
      habitat_distances: habitatDistances,
      retrieved_at: retrievedAt,
      deer_inference_performed: false,
      coefficient_transfer_performed: false,
      scoring_performed: false,
      interpretation_boundary:
        'This neutral product reproduces the Abernathy et al. distance-to-habitat measurement form while substituting nationally available source classes for Florida CLC classes. Annual NLCD Evergreen Forest is not asserted to be pine species; Deciduous Forest is an upland-hardwood analogue rather than a Florida hammock; Grassland/Herbaceous is a prairie analogue; NWI PFO1 and PEM supply wetland physiognomy. The product does not assign refuge quality, selection, storm response, survival benefit, or any deer-use score.',
    }

    if (!validateFarmWatchForestTypeContext(context)) throw new Error('forest-type context failed contract validation')

    let materialized: any = null
    if (requestData?.persist_property_center === true) {
      const { data, error } = await admin.rpc(
        'farm_watch_record_forest_type_context_v1_internal',
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

    return json({ ok: true, status: 'available', property: requestData.property, context, materialized })
  } catch (error) {
    console.error('Farm Watch forest-type context failed', error instanceof Error ? error.message : error)
    return json({ ok: false, status: 'unavailable', error: error instanceof Error ? error.message : String(error) }, 500)
  }
})
