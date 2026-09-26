import 'jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.115.0'
import { fromArrayBuffer } from 'npm:geotiff@2.1.3'
import {
  FARM_WATCH_CONIFER_COVER_PRODUCT,
  coniferStudyClass,
  validateFarmWatchConiferCoverContext,
} from '../_shared/farm-watch-conifer-cover-contract.ts'

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

const LANDCOVER_URL =
  'https://di-nlcd.img.arcgis.com/arcgis/rest/services/USA_NLCD_Annual_LandCover/ImageServer'
const TCC_URL =
  'https://imagery.geoplatform.gov/iipp/rest/services/Vegetation/USFS_EDW_NLCD_TCC_CONUS/ImageServer'
const SOURCE_TIMEOUT_MS = 45_000
const VALID_LANDCOVER_VALUES = new Set([11,12,21,22,23,24,31,41,42,43,52,71,81,82,90,95])

type Json = Record<string, any>
type Point = [number, number]

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

async function sha256Hex(value: string | Uint8Array) {
  const source = typeof value === 'string' ? new TextEncoder().encode(value) : value
  const bytes = new Uint8Array(source.byteLength)
  bytes.set(source)
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes.buffer))
  return [...digest].map((byte) => byte.toString(16).padStart(2, '0')).join('')
}

async function fetchText(url: string, accept = 'application/json, */*') {
  const response = await fetch(url, {
    headers: {
      accept,
      'user-agent': 'Scout-by-Cadastory/1.0 (Farm Watch M09 conifer cover)',
    },
    signal: AbortSignal.timeout(SOURCE_TIMEOUT_MS),
  })
  const text = await response.text()
  if (!response.ok) throw new Error('source returned HTTP ' + response.status)
  return text
}

async function fetchJson(url: string) {
  const text = await fetchText(url)
  let value: any
  try {
    value = JSON.parse(text)
  } catch {
    throw new Error('source returned non-JSON content')
  }
  if (value?.error) throw new Error(value.error?.message || 'ArcGIS source returned an error')
  return { text, value }
}

function sourceLatestYear(metadata: any) {
  const end = Number(metadata?.timeInfo?.timeExtent?.[1])
  if (!Number.isFinite(end)) throw new Error('source time extent is unavailable')
  const year = new Date(end).getUTCFullYear()
  if (!Number.isInteger(year) || year < 1985 || year > 2100) {
    throw new Error('source latest year is invalid')
  }
  return year
}

function exportImageUrl(base: string, requestData: any, sourceYear: number, source: 'landcover' | 'tcc') {
  const bbox = requestData?.raster_request?.bbox_utm
  const width = Number(requestData?.raster_request?.width)
  const height = Number(requestData?.raster_request?.height)
  if (
    !Array.isArray(bbox) || bbox.length !== 4 ||
    !bbox.every((value: unknown) => Number.isFinite(Number(value))) ||
    !Number.isInteger(width) || !Number.isInteger(height) ||
    width < 1 || height < 1 || width > 400 || height > 400
  ) throw new Error('invalid conifer raster request')

  const url = new URL(base + '/exportImage')
  url.searchParams.set('bbox', bbox.map(Number).join(','))
  url.searchParams.set('bboxSR', '32616')
  url.searchParams.set('imageSR', '32616')
  url.searchParams.set('size', width + ',' + height)
  url.searchParams.set('format', 'tiff')
  url.searchParams.set('pixelType', 'U8')
  url.searchParams.set('interpolation', 'RSP_NearestNeighbor')
  if (source === 'landcover') {
    url.searchParams.set('mosaicRule', JSON.stringify({
      mosaicMethod: 'esriMosaicAttribute',
      sortField: 'Year',
      sortValue: sourceYear,
    }))
  } else {
    url.searchParams.set('mosaicRule', JSON.stringify({
      mosaicMethod: 'esriMosaicNorthwest',
      where: 'beginyear = ' + sourceYear,
    }))
  }
  url.searchParams.set('f', 'json')
  return url.toString()
}

async function fetchRaster(base: string, requestData: any, sourceYear: number, source: 'landcover' | 'tcc') {
  const exported = await fetchJson(exportImageUrl(base, requestData, sourceYear, source))
  const href = String(exported.value?.href || '')
  const extent = exported.value?.extent
  if (
    !href.startsWith('https://') || !extent ||
    !Number.isFinite(Number(extent.xmin)) || !Number.isFinite(Number(extent.ymin)) ||
    !Number.isFinite(Number(extent.xmax)) || !Number.isFinite(Number(extent.ymax))
  ) throw new Error(source + ' export did not return a usable image')

  const response = await fetch(href, {
    headers: {
      accept: 'image/tiff, application/octet-stream, */*',
      'user-agent': 'Scout-by-Cadastory/1.0 (Farm Watch M09 conifer cover)',
    },
    signal: AbortSignal.timeout(SOURCE_TIMEOUT_MS),
  })
  if (!response.ok) throw new Error(source + ' raster export returned HTTP ' + response.status)

  const buffer = await response.arrayBuffer()
  const hash = await sha256Hex(new Uint8Array(buffer))
  const tiff: any = await fromArrayBuffer(buffer)
  const image: any = await tiff.getImage()
  const width = Number(image.getWidth())
  const height = Number(image.getHeight())
  const pixels: any = await image.readRasters({ interleave: true })
  if (
    width !== Number(exported.value?.width) ||
    height !== Number(exported.value?.height) ||
    pixels.length !== width * height
  ) throw new Error(source + ' raster dimensions are inconsistent')

  return {
    pixels,
    width,
    height,
    extent: {
      xmin: Number(extent.xmin),
      ymin: Number(extent.ymin),
      xmax: Number(extent.xmax),
      ymax: Number(extent.ymax),
    },
    sha256: hash,
  }
}

function pointInRing(x: number, y: number, ring: Point[]) {
  let inside = false
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const xi = Number(ring[i]?.[0])
    const yi = Number(ring[i]?.[1])
    const xj = Number(ring[j]?.[0])
    const yj = Number(ring[j]?.[1])
    if (![xi, yi, xj, yj].every(Number.isFinite)) continue
    const intersects = ((yi > y) !== (yj > y)) &&
      (x < (xj - xi) * (y - yi) / ((yj - yi) || Number.EPSILON) + xi)
    if (intersects) inside = !inside
  }
  return inside
}

function pointInPolygon(x: number, y: number, polygon: Point[][]) {
  if (!Array.isArray(polygon) || !polygon.length || !pointInRing(x, y, polygon[0])) return false
  for (let i = 1; i < polygon.length; i += 1) {
    if (pointInRing(x, y, polygon[i])) return false
  }
  return true
}

function pointInGeoJson(x: number, y: number, geometry: any) {
  if (geometry?.type === 'Polygon') return pointInPolygon(x, y, geometry.coordinates || [])
  if (geometry?.type === 'MultiPolygon') {
    return (geometry.coordinates || []).some((polygon: Point[][]) => pointInPolygon(x, y, polygon))
  }
  return false
}

function rounded(value: number, digits = 4) {
  const factor = 10 ** digits
  return Math.round(value * factor) / factor
}

type DomainAccumulator = {
  domainCellCount: number
  validPairCount: number
  moderateCount: number
  denseCount: number
  otherCount: number
  openConiferCount: number
  mixedForestCount: number
  evergreenCount: number
  tccSumEvergreen: number
}

function emptyAccumulator(): DomainAccumulator {
  return {
    domainCellCount: 0,
    validPairCount: 0,
    moderateCount: 0,
    denseCount: 0,
    otherCount: 0,
    openConiferCount: 0,
    mixedForestCount: 0,
    evergreenCount: 0,
    tccSumEvergreen: 0,
  }
}

function availabilityRow(count: number, total: number) {
  return {
    cell_count: count,
    area_ha: rounded(count * 0.09, 3),
    percent_of_valid_habitat: rounded(total > 0 ? count / total * 100 : 0, 4),
  }
}

function summarizeDomain(acc: DomainAccumulator, exactAreaHa: number | null) {
  if (acc.domainCellCount < 1 || acc.validPairCount < 1) {
    return { status: 'unavailable' }
  }
  return {
    status: 'available',
    exact_domain_area_ha: Number.isFinite(exactAreaHa) ? rounded(Number(exactAreaHa), 3) : null,
    domain_cell_count: acc.domainCellCount,
    center_sampled_area_ha: rounded(acc.domainCellCount * 0.09, 3),
    valid_pair_cell_count: acc.validPairCount,
    valid_pair_coverage_ratio: rounded(acc.validPairCount / acc.domainCellCount, 4),
    study_availability: {
      moderately_dense_conifer: availabilityRow(acc.moderateCount, acc.validPairCount),
      dense_conifer: availabilityRow(acc.denseCount, acc.validPairCount),
      other: availabilityRow(acc.otherCount, acc.validPairCount),
    },
    diagnostics: {
      evergreen_dominant_cell_count: acc.evergreenCount,
      open_conifer_cell_count: acc.openConiferCount,
      mixed_forest_cell_count: acc.mixedForestCount,
      mean_tcc_percent_within_evergreen:
        acc.evergreenCount > 0 ? rounded(acc.tccSumEvergreen / acc.evergreenCount, 2) : null,
      mixed_forest_treatment: 'other',
    },
  }
}

function representativeCandidates(points: Record<string, any[]>) {
  const rows: any[] = []
  for (const key of ['dense_conifer','moderately_dense_conifer','open_conifer','mixed_forest']) {
    const values = points[key] || []
    if (!values.length) continue
    const indices = [...new Set([0, Math.floor((values.length - 1) / 2), values.length - 1])]
    for (const index of indices) rows.push({ class_key: key, ...values[index] })
  }
  return rows
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
      'farm_watch_get_conifer_cover_request_v1_internal',
      { p_slug: slug },
    )
    if (requestError) throw new Error(requestError.message)
    if (requestData?.status !== 'available') {
      return json({
        ok: true,
        status: requestData?.status || 'unavailable',
        property: requestData?.property || { slug },
        reason: requestData?.reason || null,
      })
    }

    const [landcoverMeta, tccMeta] = await Promise.all([
      fetchJson(LANDCOVER_URL + '?f=json'),
      fetchJson(TCC_URL + '?f=json'),
    ])
    const landcoverLatestYear = sourceLatestYear(landcoverMeta.value)
    const tccLatestYear = sourceLatestYear(tccMeta.value)
    const commonSourceYear = Math.min(landcoverLatestYear, tccLatestYear)
    const [landcoverMetadataSha256, tccMetadataSha256] = await Promise.all([
      sha256Hex(landcoverMeta.text),
      sha256Hex(tccMeta.text),
    ])

    const [landcoverRaster, tccRaster] = await Promise.all([
      fetchRaster(LANDCOVER_URL, requestData, commonSourceYear, 'landcover'),
      fetchRaster(TCC_URL, requestData, commonSourceYear, 'tcc'),
    ])

    if (
      landcoverRaster.width !== tccRaster.width ||
      landcoverRaster.height !== tccRaster.height
    ) throw new Error('source raster dimensions do not match')

    const extentKeys = ['xmin','ymin','xmax','ymax'] as const
    for (const key of extentKeys) {
      if (Math.abs(landcoverRaster.extent[key] - tccRaster.extent[key]) > 0.1) {
        throw new Error('source raster extents do not match')
      }
    }

    const width = landcoverRaster.width
    const height = landcoverRaster.height
    const { xmin, ymin, xmax, ymax } = landcoverRaster.extent
    const pixelWidth = (xmax - xmin) / width
    const pixelHeight = (ymax - ymin) / height
    if (
      Math.abs(pixelWidth - FARM_WATCH_CONIFER_COVER_PRODUCT.pixelSizeM) > 0.1 ||
      Math.abs(pixelHeight - FARM_WATCH_CONIFER_COVER_PRODUCT.pixelSizeM) > 0.1
    ) throw new Error('M09 raster support is not 30 m')

    const domainRows = requestData?.domains || {}
    const domainGeometries: Record<string, any> = {}
    const domainAreas: Record<string, number | null> = {}
    for (const key of FARM_WATCH_CONIFER_COVER_PRODUCT.domainKeys) {
      const geometry = domainRows?.[key]?.geometry_utm_geojson
      if (!geometry || !['Polygon','MultiPolygon'].includes(String(geometry.type))) {
        throw new Error('M09 domain geometry unavailable: ' + key)
      }
      domainGeometries[key] = geometry
      const area = Number(domainRows?.[key]?.exact_area_ha)
      domainAreas[key] = Number.isFinite(area) ? area : null
    }

    const accumulators = Object.fromEntries(
      FARM_WATCH_CONIFER_COVER_PRODUCT.domainKeys.map((key) => [key, emptyAccumulator()]),
    ) as Record<string, DomainAccumulator>

    const candidatePool: Record<string, any[]> = {
      dense_conifer: [],
      moderately_dense_conifer: [],
      open_conifer: [],
      mixed_forest: [],
    }

    for (let row = 0; row < height; row += 1) {
      const y = ymax - (row + 0.5) * pixelHeight
      for (let col = 0; col < width; col += 1) {
        const x = xmin + (col + 0.5) * pixelWidth
        const domainHits = FARM_WATCH_CONIFER_COVER_PRODUCT.domainKeys.filter(
          (key) => pointInGeoJson(x, y, domainGeometries[key]),
        )
        if (!domainHits.length) continue

        const index = row * width + col
        const landcover = Math.round(Number(landcoverRaster.pixels[index]))
        const tcc = Math.round(Number(tccRaster.pixels[index]))
        const validLandcover = VALID_LANDCOVER_VALUES.has(landcover)
        const validTcc = tcc >= 0 && tcc <= 100

        for (const key of domainHits) accumulators[key].domainCellCount += 1
        if (!validLandcover || !validTcc) continue

        const studyClass = coniferStudyClass(landcover, tcc)
        for (const key of domainHits) {
          const acc = accumulators[key]
          acc.validPairCount += 1
          if (studyClass === 'dense_conifer') acc.denseCount += 1
          else if (studyClass === 'moderately_dense_conifer') acc.moderateCount += 1
          else acc.otherCount += 1

          if (landcover === FARM_WATCH_CONIFER_COVER_PRODUCT.evergreenLandcoverValue) {
            acc.evergreenCount += 1
            acc.tccSumEvergreen += tcc
            if (tcc < FARM_WATCH_CONIFER_COVER_PRODUCT.moderateMinimumPercent) {
              acc.openConiferCount += 1
            }
          }
          if (landcover === FARM_WATCH_CONIFER_COVER_PRODUCT.mixedForestLandcoverValue) {
            acc.mixedForestCount += 1
          }
        }

        if (domainHits.includes('broad_3000m')) {
          let key: string | null = null
          if (landcover === FARM_WATCH_CONIFER_COVER_PRODUCT.mixedForestLandcoverValue) {
            key = 'mixed_forest'
          } else if (landcover === FARM_WATCH_CONIFER_COVER_PRODUCT.evergreenLandcoverValue) {
            if (tcc >= FARM_WATCH_CONIFER_COVER_PRODUCT.denseMinimumPercent) key = 'dense_conifer'
            else if (tcc >= FARM_WATCH_CONIFER_COVER_PRODUCT.moderateMinimumPercent) key = 'moderately_dense_conifer'
            else key = 'open_conifer'
          }
          if (key && candidatePool[key].length < 300) {
            candidatePool[key].push({
              x_utm: rounded(x, 3),
              y_utm: rounded(y, 3),
              landcover_value: landcover,
              tcc_percent: tcc,
            })
          }
        }
      }
    }

    const domains: Record<string, any> = {}
    for (const key of FARM_WATCH_CONIFER_COVER_PRODUCT.domainKeys) {
      domains[key] = summarizeDomain(accumulators[key], domainAreas[key])
      if (domains[key].status !== 'available') {
        throw new Error('M09 domain classification unavailable: ' + key)
      }
    }

    const retrievedAt = new Date().toISOString()
    const context = {
      schema: FARM_WATCH_CONIFER_COVER_PRODUCT.outputSchemaVersion,
      method: FARM_WATCH_CONIFER_COVER_PRODUCT.algorithmVersion,
      evidence_class: 'deterministic_derived',
      evidence_state: FARM_WATCH_CONIFER_COVER_PRODUCT.evidenceState,
      measurement_alignment: FARM_WATCH_CONIFER_COVER_PRODUCT.measurementAlignment,
      study_alignment: {
        study: FARM_WATCH_CONIFER_COVER_PRODUCT.studyCitation,
        source_method:
          'leaf-off color-infrared aerial photography delineation of dominant tree species and conifer canopy closure; open <40%, moderately dense 40% to <70%, dense >=70%; model availability categories were moderate conifer, dense conifer, and other',
        study_availability_classes: [...FARM_WATCH_CONIFER_COVER_PRODUCT.studyAvailabilityClasses],
        other_definition:
          'open conifer below 40% canopy closure plus openings and hardwoods',
        coefficient_transfer: 'not_performed',
      },
      source_reconciliation: {
        common_source_year: commonSourceYear,
        latest_years_at_retrieval: {
          annual_nlcd_landcover: landcoverLatestYear,
          nlcd_tree_canopy_cover: tccLatestYear,
        },
        temporal_rule:
          'use the latest year present in both source families; do not mix a newer canopy year with an older vegetation-type year',
        landcover: {
          slug: FARM_WATCH_CONIFER_COVER_PRODUCT.landcoverSourceSlug,
          authority: 'U.S. Geological Survey / Multi-Resolution Land Characteristics Consortium',
          image_service_url: LANDCOVER_URL,
          source_year: commonSourceYear,
          spatial_resolution_m: 30,
          service_metadata_sha256: landcoverMetadataSha256,
          exported_raster_sha256: landcoverRaster.sha256,
          conifer_dominant_proxy: {
            value: 42,
            class: 'Evergreen Forest',
            source_definition:
              'tree-dominated cover with more than 75% of tree species maintaining foliage year-round',
          },
          mixed_forest_treatment: {
            value: 43,
            class: 'Mixed Forest',
            treatment: 'other',
            reason:
              'neither deciduous nor evergreen exceeds 75% of tree cover, so conifer dominance is not asserted',
          },
        },
        canopy: {
          slug: FARM_WATCH_CONIFER_COVER_PRODUCT.canopySourceSlug,
          authority: 'USDA Forest Service / Multi-Resolution Land Characteristics Consortium',
          image_service_url: TCC_URL,
          source_year: commonSourceYear,
          product_version: 'v2025-6',
          spatial_resolution_m: 30,
          service_metadata_sha256: tccMetadataSha256,
          exported_raster_sha256: tccRaster.sha256,
          modeled_percent_tree_canopy_cover: true,
        },
        classification: {
          open_conifer: 'Annual NLCD Evergreen Forest AND TCC <40%; diagnostic only and folded into study class other',
          moderately_dense_conifer: 'Annual NLCD Evergreen Forest AND TCC >=40% AND TCC <70%',
          dense_conifer: 'Annual NLCD Evergreen Forest AND TCC >=70%',
          other: 'all other valid land cover, including open conifer, Mixed Forest, openings, and hardwoods',
        },
      },
      landscape_domain_identity_sha256: requestData?.landscape_domain_identity_sha256,
      domains,
      qa_candidates: representativeCandidates(candidatePool),
      raster_support: {
        crs: 'EPSG:32616',
        width,
        height,
        pixel_width_m: pixelWidth,
        pixel_height_m: pixelHeight,
        extent_utm: [xmin, ymin, xmax, ymax],
        resampling: 'nearest_neighbor',
        domain_membership: '30 m output-cell center inside exact Farm Watch domain geometry',
      },
      retrieved_at: retrievedAt,
      deer_inference_performed: false,
      coefficient_transfer_performed: false,
      scoring_performed: false,
      interpretation_boundary:
        'Neutral M09 physical context. Annual NLCD Evergreen Forest is a conservative conifer-dominant proxy and NLCD TCC is modeled canopy cover, not the study air-photo observation protocol. Mixed Forest is intentionally treated as other. The product reports study-style availability classes but does not infer winter cover use, bedding, habitat quality, snow shelter value, mortality, movement, or any Kentucky biological threshold.',
    }

    if (!validateFarmWatchConiferCoverContext(context)) {
      throw new Error('M09 conifer-cover context failed contract validation')
    }

    const { data: materialized, error: recordError } = await admin.rpc(
      'farm_watch_record_conifer_cover_context_v1_internal',
      {
        p_slug: slug,
        p_source_year: commonSourceYear,
        p_landcover_metadata_sha256: landcoverMetadataSha256,
        p_tcc_metadata_sha256: tccMetadataSha256,
        p_context: context,
        p_retrieved_at: retrievedAt,
      },
    )
    if (recordError) throw new Error(recordError.message)

    return json({
      ok: true,
      status: 'available',
      property: requestData.property,
      context,
      materialized,
    })
  } catch (error) {
    console.error('Farm Watch M09 conifer-cover context failed', error instanceof Error ? error.message : error)
    return json({
      ok: false,
      status: 'unavailable',
      error: error instanceof Error ? error.message : String(error),
    }, 500)
  }
})
