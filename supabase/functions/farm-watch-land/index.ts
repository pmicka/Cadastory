import 'jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.115.0'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
let SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
try {
  const keys = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') || '{}')
  SERVICE_KEY = keys.default || SERVICE_KEY
} catch { /* legacy fallback */ }
if (!SERVICE_KEY) throw new Error('Farm Watch service credential is unavailable')

const admin = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
})

const ALLOWED_ORIGINS = new Set([
  'https://pmicka.com',
  'https://www.pmicka.com',
  'http://127.0.0.1:8000',
  'http://localhost:8000',
])
const DEFAULT_PROPERTY_SLUG = 'validation-property-01'
const CACHE_TTL_MS = 30 * 24 * 60 * 60 * 1000
const SOURCE_TIMEOUT_MS = 12000

const SOURCES = {
  geology: 'https://kgs.uky.edu/arcgis/rest/services/GeologicMapData/KY24KGeologicFormations_WGS84/MapServer/0',
  lithology: 'https://kgs.uky.edu/arcgis/rest/services/GeologicMapData/KY24KLitho_WGS84/MapServer/0',
  sinkholes: 'https://kgs.uky.edu/arcgis/rest/services/KYWater/KYSinkholes/MapServer/0',
  huc: 'https://kygisserver.ky.gov/arcgis/rest/services/WGS84WM_Services/Ky_8_10_12_Digit_Hydrologic_Units_WGS84WM/MapServer/0',
  dem: 'https://kyraster.ky.gov/arcgis/rest/services/ElevationServices/Ky_DEM_KYAPED_2FT_Phase3_WGS84WM/ImageServer',
}

type Json = Record<string, any>
type Anchor = {
  property_id?: string
  stated_acres?: number | null
  lat?: number
  lon?: number
  boundary_geojson?: Json | null
}

function responseHeaders(origin = ''): Record<string, string> {
  const headers: Record<string, string> = {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store, max-age=0',
    pragma: 'no-cache',
    'referrer-policy': 'no-referrer',
    'x-content-type-options': 'nosniff',
  }
  if (ALLOWED_ORIGINS.has(origin)) {
    headers['access-control-allow-origin'] = origin
    headers.vary = 'Origin'
    headers['access-control-allow-headers'] = 'authorization, content-type, apikey'
    headers['access-control-allow-methods'] = 'GET, OPTIONS'
  }
  return headers
}

function json(body: unknown, status = 200, origin = '') {
  return new Response(JSON.stringify(body), { status, headers: responseHeaders(origin) })
}

function bearer(req: Request): string | null {
  const match = /^Bearer\s+(.+)$/i.exec(req.headers.get('authorization') || '')
  return match?.[1]?.trim() || null
}

function boundedSlug(value: string | null): string | null {
  if (!value) return DEFAULT_PROPERTY_SLUG
  const normalized = value.trim().toLowerCase()
  return /^[a-z0-9][a-z0-9-]{0,79}$/.test(normalized) ? normalized : null
}

async function fetchJson(url: string, timeoutMs = SOURCE_TIMEOUT_MS) {
  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), timeoutMs)
  try {
    const response = await fetch(url, {
      signal: controller.signal,
      headers: {
        accept: 'application/json, application/geo+json, */*',
        'user-agent': 'Cadastory-Farm-Watch/0.5 (https://pmicka.com)',
      },
    })
    const text = await response.text()
    if (!response.ok) throw new Error(`source returned ${response.status}`)
    try { return JSON.parse(text) } catch { throw new Error('source returned non-JSON content') }
  } finally {
    clearTimeout(timeout)
  }
}

function geojsonToEsriPolygon(geometry: Json | null | undefined) {
  if (!geometry) return null
  const rings: any[] = []
  if (geometry.type === 'Polygon') rings.push(...(geometry.coordinates || []))
  if (geometry.type === 'MultiPolygon') {
    for (const polygon of geometry.coordinates || []) rings.push(...polygon)
  }
  return rings.length ? { rings, spatialReference: { wkid: 4326 } } : null
}

function value(props: Json, ...keys: string[]) {
  const entries = Object.entries(props || {})
  for (const key of keys) {
    const found = entries.find(([candidate]) => candidate.toLowerCase() === key.toLowerCase())
    if (found) return found[1]
  }
  return null
}

async function arcgisPolygon(base: string, polygon: Json, outFields: string) {
  const url = new URL(`${base.replace(/\/$/, '')}/query`)
  for (const [key, val] of Object.entries({
    f: 'geojson',
    where: '1=1',
    geometry: JSON.stringify(polygon),
    geometryType: 'esriGeometryPolygon',
    inSR: '4326',
    spatialRel: 'esriSpatialRelIntersects',
    outFields,
    returnGeometry: 'true',
    outSR: '4326',
  })) url.searchParams.set(key, val)
  const payload = await fetchJson(url.toString())
  if (payload?.error) throw new Error(payload.error.message || 'ArcGIS polygon query failed')
  if (!Array.isArray(payload?.features)) throw new Error('ArcGIS response did not contain features')
  return payload
}

async function arcgisZonalStats(base: string, polygon: Json, renderingRule?: Json) {
  const url = new URL(`${base.replace(/\/$/, '')}/computeStatisticsHistograms`)
  url.searchParams.set('f', 'json')
  url.searchParams.set('geometry', JSON.stringify(polygon))
  url.searchParams.set('geometryType', 'esriGeometryPolygon')
  if (renderingRule) url.searchParams.set('renderingRule', JSON.stringify(renderingRule))
  const payload = await fetchJson(url.toString())
  if (payload?.error) throw new Error(payload.error.message || 'ArcGIS raster statistics query failed')
  if (!Array.isArray(payload?.statistics) || !payload.statistics.length) {
    throw new Error('Raster statistics response did not contain statistics')
  }
  return payload
}

async function arcgisNearby(base: string, lat: number, lon: number, meters: number, outFields: string) {
  const url = new URL(`${base.replace(/\/$/, '')}/query`)
  for (const [key, val] of Object.entries({
    f: 'geojson',
    where: '1=1',
    geometry: `${lon},${lat}`,
    geometryType: 'esriGeometryPoint',
    inSR: '4326',
    spatialRel: 'esriSpatialRelIntersects',
    distance: String(meters),
    units: 'esriSRUnit_Meter',
    outFields,
    returnGeometry: 'true',
    outSR: '4326',
  })) url.searchParams.set(key, val)
  const payload = await fetchJson(url.toString())
  if (payload?.error) throw new Error(payload.error.message || 'ArcGIS nearby query failed')
  if (!Array.isArray(payload?.features)) throw new Error('ArcGIS response did not contain features')
  return payload
}

function normalizeGeology(payload: Json, lithologyPayload: Json | null) {
  const lithologyByCode = new Map<string, string>()
  for (const feature of lithologyPayload?.features || []) {
    const props = feature?.properties || {}
    const code = String(value(props, 'formation_code') || '').trim()
    const lith = String(value(props, 'KLitho_txt_DOMINANT_LITHOLOGY', 'dominant_lithology') || '').trim()
    if (code && lith) lithologyByCode.set(code, lith)
  }
  return {
    type: 'FeatureCollection',
    features: (payload?.features || []).map((feature: Json) => {
      const props = feature?.properties || {}
      const formationCode = String(value(props, 'formation_code') || '').trim()
      return {
        type: 'Feature',
        geometry: feature.geometry,
        properties: {
          map_symbol: value(props, 'map_symbol'),
          formation_code: formationCode || null,
          formation_name: value(props, 'formation_name'),
          dominant_lithology: lithologyByCode.get(formationCode) || null,
          maximum_age: value(props, 'maximum_age'),
          minimum_age: value(props, 'minimum_age'),
          quadrangle_name: value(props, 'quadrangle_name'),
          description: value(props, 'description'),
          source_name: value(props, 'sourceName', 'source_name'),
          source_uri: value(props, 'source_uri'),
        },
      }
    }),
  }
}

function normalizeHuc(payload: Json) {
  return {
    type: 'FeatureCollection',
    features: (payload?.features || []).map((feature: Json) => {
      const props = feature?.properties || {}
      return {
        type: 'Feature',
        geometry: feature.geometry,
        properties: {
          huc12: value(props, 'HUC12', 'huc12'),
          name: value(props, 'Name', 'name'),
          hu_type: value(props, 'HUType', 'hutype'),
          hu_mod: value(props, 'HUMod', 'humod'),
          to_huc: value(props, 'ToHUC', 'tohuc'),
          area_acres: value(props, 'AreaAcres', 'areaacres'),
        },
      }
    }),
  }
}

function histogramQuantile(payload: Json, quantile: number) {
  const histogram = payload?.histograms?.[0]
  const counts = Array.isArray(histogram?.counts) ? histogram.counts.map(Number) : []
  const min = Number(histogram?.min)
  const max = Number(histogram?.max)
  const size = Number(histogram?.size)
  const total = counts.reduce((sum: number, value: number) => sum + (Number.isFinite(value) ? value : 0), 0)
  if (!counts.length || !Number.isFinite(min) || !Number.isFinite(max) || !Number.isFinite(size) || size <= 0 || total <= 0) return null
  const target = Math.min(1, Math.max(0, quantile)) * total
  const width = (max - min) / size
  let cumulative = 0
  for (let index = 0; index < counts.length; index += 1) {
    const count = Number(counts[index]) || 0
    if (cumulative + count >= target) {
      const within = count > 0 ? (target - cumulative) / count : 0.5
      return min + (index + within) * width
    }
    cumulative += count
  }
  return max
}

function remapClassRows(payload: Json, definitions: Array<Json>, parcelAcres: number | null) {
  const histogram = payload?.histograms?.[0]
  const counts = Array.isArray(histogram?.counts) ? histogram.counts.map(Number) : []
  const min = Number(histogram?.min)
  const max = Number(histogram?.max)
  const size = Number(histogram?.size)
  if (!counts.length || !Number.isFinite(min) || !Number.isFinite(max) || !Number.isFinite(size) || size <= 0) return []
  const width = (max - min) / size
  const byClass = new Map<number, number>()
  counts.forEach((count: number, index: number) => {
    if (!Number.isFinite(count) || count <= 0) return
    const center = min + (index + 0.5) * width
    const classValue = Math.round(center)
    byClass.set(classValue, (byClass.get(classValue) || 0) + count)
  })
  const total = definitions.reduce((sum, definition) => sum + (byClass.get(Number(definition.value)) || 0), 0)
  return definitions.map((definition) => {
    const count = byClass.get(Number(definition.value)) || 0
    const fraction = total > 0 ? count / total : 0
    return {
      ...definition,
      count,
      parcel_percent: fraction * 100,
      parcel_acres: parcelAcres == null ? null : parcelAcres * fraction,
    }
  })
}

function normalizeSlope(payload: Json, classPayload: Json, parcelAcres: number | null) {
  const stats = payload?.statistics?.[0] || {}
  const count = Number(stats.count)
  const definitions = [
    { value: 1, label: '0–10%', min_percent: 0, max_percent: 10 },
    { value: 2, label: '10–20%', min_percent: 10, max_percent: 20 },
    { value: 3, label: '20–30%', min_percent: 20, max_percent: 30 },
    { value: 4, label: '30–50%', min_percent: 30, max_percent: 50 },
    { value: 5, label: '50%+', min_percent: 50, max_percent: null },
  ]
  return {
    method: 'geometry_clipped_slope_raster_function',
    source: 'KyFromAbove Phase 3 DEM',
    z_factor: 0.3048,
    slope_type: 'percent_rise',
    min_percent: Number(stats.min),
    max_percent: Number(stats.max),
    mean_percent: Number(stats.mean),
    median_percent: Number(stats.median),
    p90_percent: histogramQuantile(payload, 0.9),
    standard_deviation_percent: Number(stats.standardDeviation),
    raster_observation_count: Number.isFinite(count) ? count : null,
    bands: remapClassRows(classPayload, definitions, parcelAcres),
  }
}

function normalizeAspect(classPayload: Json, parcelAcres: number | null) {
  const definitions = [
    { value: 1, direction: 'N', label: 'North' },
    { value: 2, direction: 'NE', label: 'Northeast' },
    { value: 3, direction: 'E', label: 'East' },
    { value: 4, direction: 'SE', label: 'Southeast' },
    { value: 5, direction: 'S', label: 'South' },
    { value: 6, direction: 'SW', label: 'Southwest' },
    { value: 7, direction: 'W', label: 'West' },
    { value: 8, direction: 'NW', label: 'Northwest' },
  ]
  const sectors = remapClassRows(classPayload, definitions, parcelAcres)
  return {
    method: 'geometry_clipped_aspect_raster_function',
    source: 'KyFromAbove Phase 3 DEM',
    sectors,
    dominant_sectors: sectors.slice().sort((a: Json, b: Json) => Number(b.parcel_percent) - Number(a.parcel_percent)).slice(0, 3),
    raster_observation_count: sectors.reduce((sum: number, row: Json) => sum + Number(row.count || 0), 0),
  }
}

function normalizeElevationBands(classPayload: Json, parcelAcres: number | null) {
  const definitions = [
    { value: 1, label: '<650 ft', min_ft: null, max_ft: 650 },
    { value: 2, label: '650–700 ft', min_ft: 650, max_ft: 700 },
    { value: 3, label: '700–750 ft', min_ft: 700, max_ft: 750 },
    { value: 4, label: '750–800 ft', min_ft: 750, max_ft: 800 },
    { value: 5, label: '800 ft+', min_ft: 800, max_ft: null },
  ]
  return {
    method: 'geometry_clipped_elevation_remap',
    source: 'KyFromAbove Phase 3 DEM',
    bands: remapClassRows(classPayload, definitions, parcelAcres),
  }
}

function normalizeElevation(payload: Json) {
  const stats = payload?.statistics?.[0] || {}
  const minFt = Number(stats.min)
  const maxFt = Number(stats.max)
  const meanFt = Number(stats.mean)
  const medianFt = Number(stats.median)
  const stdDevFt = Number(stats.standardDeviation)
  const count = Number(stats.count)
  if (![minFt, maxFt].every(Number.isFinite)) throw new Error('Raster elevation statistics are incomplete')
  return {
    method: 'geometry_clipped_raster_statistics',
    source: 'KyFromAbove Phase 3 DEM',
    min_ft: minFt,
    max_ft: maxFt,
    relief_ft: maxFt - minFt,
    mean_ft: Number.isFinite(meanFt) ? meanFt : null,
    median_ft: Number.isFinite(medianFt) ? medianFt : null,
    standard_deviation_ft: Number.isFinite(stdDevFt) ? stdDevFt : null,
    raster_observation_count: Number.isFinite(count) ? count : null,
  }
}

function normalizeSinkholes(payload: Json) {
  return {
    type: 'FeatureCollection',
    features: (payload?.features || []).map((feature: Json) => {
      const props = feature?.properties || {}
      return {
        type: 'Feature',
        geometry: feature.geometry,
        properties: {
          objectid: value(props, 'ObjectID', 'objectid'),
          county_name: value(props, 'county_name'),
          quadrangle_name: value(props, 'quadrangle_name'),
          mapped_acres: value(props, 'Acres', 'acres'),
        },
      }
    }),
  }
}

async function refresh(slug: string, anchor: Anchor) {
  const polygon = geojsonToEsriPolygon(anchor.boundary_geojson)
  const lat = Number(anchor.lat)
  const lon = Number(anchor.lon)
  if (!polygon || !Number.isFinite(lat) || !Number.isFinite(lon)) {
    throw new Error('selected parcel geometry is unavailable')
  }

  const slopeRule = {
    rasterFunction: 'Slope',
    rasterFunctionArguments: {
      ZFactor: 0.3048,
      SlopeType: 2,
      RemoveEdgeEffect: true,
    },
    outputPixelType: 'F32',
    variableName: 'DEM',
  }
  const slopeClassRule = {
    rasterFunction: 'Remap',
    rasterFunctionArguments: {
      InputRanges: [0,10,10,20,20,30,30,50,50,1000],
      OutputValues: [1,2,3,4,5],
      AllowUnmatched: false,
      Raster: slopeRule,
    },
    outputPixelType: 'U8',
    variableName: 'Raster',
  }
  const aspectClassRule = {
    rasterFunction: 'Remap',
    rasterFunctionArguments: {
      InputRanges: [0,22.5,22.5,67.5,67.5,112.5,112.5,157.5,157.5,202.5,202.5,247.5,247.5,292.5,292.5,337.5,337.5,360.1],
      OutputValues: [1,2,3,4,5,6,7,8,1],
      AllowUnmatched: false,
      Raster: { rasterFunction: 'Aspect' },
    },
    outputPixelType: 'U8',
    variableName: 'Raster',
  }
  const elevationBandRule = {
    rasterFunction: 'Remap',
    rasterFunctionArguments: {
      InputRanges: [0,650,650,700,700,750,750,800,800,10000],
      OutputValues: [1,2,3,4,5],
      AllowUnmatched: false,
      Raster: '$$',
    },
    outputPixelType: 'U8',
    variableName: 'Raster',
  }

  const results = await Promise.allSettled([
    arcgisPolygon(SOURCES.geology, polygon, 'map_symbol,formation_code,formation_name,maximum_age,minimum_age,quadrangle_name,description,sourceName,source_uri'),
    arcgisPolygon(SOURCES.lithology, polygon, 'formation_code,KLitho_txt_DOMINANT_LITHOLOGY'),
    arcgisPolygon(SOURCES.huc, polygon, 'HUC12,Name,HUType,HUMod,ToHUC,AreaAcres'),
    arcgisNearby(SOURCES.sinkholes, lat, lon, 10000, 'county_name,quadrangle_name,Acres,ObjectID'),
    arcgisZonalStats(SOURCES.dem, polygon),
    arcgisZonalStats(SOURCES.dem, polygon, slopeRule),
    arcgisZonalStats(SOURCES.dem, polygon, slopeClassRule),
    arcgisZonalStats(SOURCES.dem, polygon, aspectClassRule),
    arcgisZonalStats(SOURCES.dem, polygon, elevationBandRule),
  ])

  const names = ['geology', 'lithology', 'watershed', 'sinkholes', 'elevation', 'slope', 'slope_classes', 'aspect', 'elevation_bands']
  const sourceStatus: Record<string, string> = {}
  const sourceErrors: Record<string, string> = {}
  const payloads: Array<Json | null> = results.map((result, index) => {
    const name = names[index]
    if (result.status === 'fulfilled') {
      sourceStatus[name] = 'available'
      return result.value as Json
    }
    sourceStatus[name] = 'unavailable'
    sourceErrors[name] = result.reason instanceof Error ? result.reason.message : String(result.reason)
    return null
  })

  const geology = payloads[0] ? normalizeGeology(payloads[0]!, payloads[1]) : { type: 'FeatureCollection', features: [] }
  const huc = payloads[2] ? normalizeHuc(payloads[2]!) : { type: 'FeatureCollection', features: [] }
  const sinkholes = payloads[3] ? normalizeSinkholes(payloads[3]!) : { type: 'FeatureCollection', features: [] }
  const elevation = payloads[4] ? normalizeElevation(payloads[4]!) : null

  const { data: computed, error: computeError } = await admin.rpc('farm_watch_compute_land_context_v1_internal', {
    p_slug: slug,
    p_geology: geology,
    p_huc: huc,
    p_sinkholes: sinkholes,
  })
  if (computeError || !computed) throw new Error(computeError?.message || 'land geometry computation failed')

  const parcelAcres = Number(computed?.parcel_geodesic_acres)
  const normalizedParcelAcres = Number.isFinite(parcelAcres) ? parcelAcres : null
  const slope = payloads[5] && payloads[6] ? normalizeSlope(payloads[5]!, payloads[6]!, normalizedParcelAcres) : null
  const aspect = payloads[7] ? normalizeAspect(payloads[7]!, normalizedParcelAcres) : null
  const elevationBands = payloads[8] ? normalizeElevationBands(payloads[8]!, normalizedParcelAcres) : null

  const retrievedAt = new Date().toISOString()
  const context = {
    ...computed,
    context_version: 3,
    elevation,
    terrain_surface: {
      slope,
      aspect,
      elevation_bands: elevationBands,
    },
    retrieved_at: retrievedAt,
    source_status: sourceStatus,
    source_errors: sourceErrors,
    provenance: {
      geology: {
        authority: 'Kentucky Geological Survey',
        scale: '1:24,000',
        source: 'digitized KGS/USGS 7.5-minute geologic quadrangle mapping',
        meaning: 'mapped bedrock geology; not a site boring or geotechnical investigation',
      },
      lithology: {
        authority: 'Kentucky Geological Survey',
        meaning: 'KGS-derived dominant lithology attribute from mapped geologic formations; not a field sample',
      },
      sinkholes: {
        authority: 'Kentucky Geological Survey',
        meaning: 'mapped closed topographic depressions digitized from 7.5-minute topographic contours; mapped absence is not proof of physical absence',
      },
      watershed: {
        authority: 'USGS / Kentucky Division of Water',
        meaning: 'Watershed Boundary Dataset hydrologic unit boundaries for water-resource management and localized studies',
      },
      elevation: {
        authority: 'Kentucky Division of Geographic Information / KyFromAbove',
        source: 'KyFromAbove Phase 3 DEM',
        method: 'exact parcel polygon passed to ArcGIS ImageServer computeStatisticsHistograms',
        meaning: 'canonical displayed parcel elevation min/max/relief from geometry-clipped raster statistics; not a ground survey',
      },
      terrain_surface: {
        authority: 'Kentucky Division of Geographic Information / KyFromAbove',
        source: 'KyFromAbove Phase 3 DEM',
        method: 'ArcGIS Slope/Aspect raster functions and geometry-clipped histogram statistics on the exact parcel polygon',
        slope_z_factor: 0.3048,
        slope_units: 'percent rise',
        meaning: 'canonical parcel slope/aspect distributions from the DEM raster; elevation bands are direct DEM remaps. These are terrain-model derivatives, not a ground survey or engineering-grade surface analysis.',
      },
      faults_in_primary_view: false,
      karst_potential_used: false,
      financial_context_included: false,
      ownership_context_included: false,
      imagery_pixels_analyzed: false,
    },
  }

  const availableCount = Object.values(sourceStatus).filter((status) => status === 'available').length
  const status = availableCount === names.length ? 'available' : availableCount > 0 ? 'partial' : 'unavailable'
  await admin.rpc('farm_watch_upsert_land_context_v1_internal', {
    p_slug: slug,
    p_status: status,
    p_context: context,
    p_retrieved_at: retrievedAt,
  })
  return { status, context, retrieved_at: retrievedAt, cache: 'miss' }
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get('origin') || ''
  if (origin && !ALLOWED_ORIGINS.has(origin)) return json({ error: 'not found' }, 404)
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: responseHeaders(origin) })
  if (req.method !== 'GET') return json({ error: 'not found' }, 404, origin)

  const token = bearer(req)
  if (!token) return json({ error: 'not found' }, 404, origin)
  const { data: userData, error: userError } = await admin.auth.getUser(token)
  const user = userData?.user
  if (userError || !user) return json({ error: 'not found' }, 404, origin)
  const { data: allowed, error: accessError } = await admin.rpc('farm_watch_authorize_user_v1_internal', { p_user_id: user.id })
  if (accessError || allowed !== true) return json({ error: 'not found' }, 404, origin)

  const url = new URL(req.url)
  const slug = boundedSlug(url.searchParams.get('property'))
  if (!slug) return json({ error: 'invalid request' }, 400, origin)

  const { data: anchor, error: anchorError } = await admin.rpc('farm_watch_get_land_anchor_v1_internal', { p_slug: slug })
  if (anchorError || !anchor?.property_id) return json({ error: 'land context unavailable' }, 503, origin)

  const { data: cached } = await admin.rpc('farm_watch_get_land_context_v1_internal', { p_slug: slug })
  const cachedAt = Date.parse(cached?.retrieved_at || '')
  let result: any

  const cacheHasCanonicalTerrain =
    cached?.context?.context_version === 3 &&
    cached?.context?.elevation?.method === 'geometry_clipped_raster_statistics' &&
    Number.isFinite(Number(cached?.context?.elevation?.min_ft)) &&
    Number.isFinite(Number(cached?.context?.elevation?.max_ft)) &&
    cached?.context?.terrain_surface?.slope?.method === 'geometry_clipped_slope_raster_function' &&
    Array.isArray(cached?.context?.terrain_surface?.slope?.bands) &&
    cached?.context?.terrain_surface?.aspect?.method === 'geometry_clipped_aspect_raster_function' &&
    Array.isArray(cached?.context?.terrain_surface?.aspect?.sectors) &&
    cached?.context?.terrain_surface?.elevation_bands?.method === 'geometry_clipped_elevation_remap' &&
    Array.isArray(cached?.context?.terrain_surface?.elevation_bands?.bands)

  if (cached?.context && cacheHasCanonicalTerrain && Number.isFinite(cachedAt) && Date.now() - cachedAt < CACHE_TTL_MS) {
    result = {
      status: cached.status || 'unknown',
      context: cached.context,
      retrieved_at: cached.retrieved_at,
      cache: 'hit',
    }
  } else {
    try {
      result = await refresh(slug, anchor as Anchor)
    } catch (error) {
      result = {
        status: cached?.status || 'unavailable',
        context: cached?.context || {},
        retrieved_at: cached?.retrieved_at || null,
        cache: cached?.context ? 'stale' : 'miss',
        error: error instanceof Error ? error.message : String(error),
      }
    }
  }

  return json({
    property: { slug },
    land: result,
    product_boundaries: {
      faults_in_primary_view: false,
      karst_potential_used: false,
      financial_context_included: false,
      ownership_context_included: false,
      imagery_analysis_performed: false,
    },
  }, 200, origin)
})
