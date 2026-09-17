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
const STATIC_TTL_MS = 12 * 60 * 60 * 1000
const FAA_TTL_MS = 5 * 60 * 1000
const SOURCE_TIMEOUT_MS = 10000

const SOURCES = {
  zoning: 'https://services2.arcgis.com/BxXA8zJZUU4360ND/arcgis/rest/services/FranklinZoningshp/FeatureServer/6',
  futureLandUse: 'https://services2.arcgis.com/BxXA8zJZUU4360ND/arcgis/rest/services/FranklinCountyZoning_WFL1/FeatureServer/5',
  countyFlood: 'https://services2.arcgis.com/BxXA8zJZUU4360ND/arcgis/rest/services/FranklinCountyZoning_WFL1/FeatureServer/3',
  femaFlood: 'https://hazards.fema.gov/arcgis/rest/services/public/NFHL/MapServer/28',
  uasfm: 'https://services6.arcgis.com/ssFJjBXIUyZDrSYZ/ArcGIS/rest/services/FAA_UAS_FacilityMap_Data/FeatureServer/0',
  classAirspace: 'https://services6.arcgis.com/ssFJjBXIUyZDrSYZ/ArcGIS/rest/services/Class_Airspace/FeatureServer/0',
  fullNationalSecurity: 'https://services6.arcgis.com/ssFJjBXIUyZDrSYZ/ArcGIS/rest/services/DoD_Mar_13/FeatureServer/0',
  partNationalSecurity: 'https://services6.arcgis.com/ssFJjBXIUyZDrSYZ/ArcGIS/rest/services/Part_Time_National_Security_UAS_Flight_Restrictions/FeatureServer/0',
  specialUse: 'https://services6.arcgis.com/ssFJjBXIUyZDrSYZ/ArcGIS/rest/services/Special_Use_Airspace/FeatureServer/0',
  airports: 'https://services6.arcgis.com/ssFJjBXIUyZDrSYZ/ArcGIS/rest/services/US_Airport/FeatureServer/0',
  stadiums: 'https://services6.arcgis.com/ssFJjBXIUyZDrSYZ/ArcGIS/rest/services/Stadiums/FeatureServer/0',
  boundaryAirspace: 'https://services6.arcgis.com/ssFJjBXIUyZDrSYZ/ArcGIS/rest/services/Boundary_Airspace/FeatureServer/0',
  tfrList: 'https://tfr.faa.gov/tfrapi/getTfrList',
  tfrNoShape: 'https://tfr.faa.gov/tfrapi/noShapeTfrList',
  tfrWfs: 'https://tfr.faa.gov/geoserver/TFR/ows',
}

type Json = Record<string, any>
type Anchor = {
  property_id?: string
  lat?: number
  lon?: number
  state_code?: string | null
  county_fips?: string | null
  selected_parcel_id?: string | null
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
function num(value: unknown): number | null {
  const parsed = Number(value)
  return Number.isFinite(parsed) ? parsed : null
}
async function fetchJson(url: string, timeoutMs = SOURCE_TIMEOUT_MS) {
  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), timeoutMs)
  try {
    const response = await fetch(url, {
      signal: controller.signal,
      headers: { accept: 'application/json, application/geo+json, */*', 'user-agent': 'Cadastory-Farm-Watch/0.4 (https://pmicka.com)' },
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
async function arcgisIntersect(base: string, polygon: Json, outFields: string) {
  const url = new URL(`${base.replace(/\/$/, '')}/query`)
  url.searchParams.set('f', 'json')
  url.searchParams.set('where', '1=1')
  url.searchParams.set('geometry', JSON.stringify(polygon))
  url.searchParams.set('geometryType', 'esriGeometryPolygon')
  url.searchParams.set('inSR', '4326')
  url.searchParams.set('spatialRel', 'esriSpatialRelIntersects')
  url.searchParams.set('outFields', outFields)
  url.searchParams.set('returnGeometry', 'false')
  const payload = await fetchJson(url.toString())
  if (payload?.error) throw new Error(payload.error.message || 'ArcGIS query failed')
  if (!Array.isArray(payload?.features)) throw new Error('ArcGIS response did not contain features')
  return payload.features.map((feature: Json) => feature?.attributes || {})
}
async function arcgisPoint(base: string, lat: number, lon: number, outFields = '*') {
  const url = new URL(`${base.replace(/\/$/, '')}/query`)
  url.searchParams.set('f', 'geojson')
  url.searchParams.set('where', '1=1')
  url.searchParams.set('geometry', `${lon},${lat}`)
  url.searchParams.set('geometryType', 'esriGeometryPoint')
  url.searchParams.set('inSR', '4326')
  url.searchParams.set('spatialRel', 'esriSpatialRelIntersects')
  url.searchParams.set('outFields', outFields)
  url.searchParams.set('returnGeometry', 'true')
  url.searchParams.set('outSR', '4326')
  const payload = await fetchJson(url.toString())
  if (payload?.error) throw new Error(payload.error.message || 'FAA ArcGIS query failed')
  if (!Array.isArray(payload?.features)) throw new Error('FAA response did not contain features')
  return payload.features
}
function haversineMiles(lat1: number, lon1: number, lat2: number, lon2: number) {
  const r = 3958.7613
  const dLat = (lat2 - lat1) * Math.PI / 180
  const dLon = (lon2 - lon1) * Math.PI / 180
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * Math.sin(dLon / 2) ** 2
  return 2 * r * Math.asin(Math.min(1, Math.sqrt(a)))
}
async function arcgisNearbyPoints(base: string, lat: number, lon: number, radiusMiles: number) {
  const dy = radiusMiles / 69
  const dx = radiusMiles / (69 * Math.max(.2, Math.cos(lat * Math.PI / 180)))
  const url = new URL(`${base.replace(/\/$/, '')}/query`)
  url.searchParams.set('f', 'geojson')
  url.searchParams.set('where', '1=1')
  url.searchParams.set('geometry', `${lon - dx},${lat - dy},${lon + dx},${lat + dy}`)
  url.searchParams.set('geometryType', 'esriGeometryEnvelope')
  url.searchParams.set('inSR', '4326')
  url.searchParams.set('spatialRel', 'esriSpatialRelIntersects')
  url.searchParams.set('outFields', '*')
  url.searchParams.set('returnGeometry', 'true')
  url.searchParams.set('outSR', '4326')
  const payload = await fetchJson(url.toString())
  if (payload?.error) throw new Error(payload.error.message || 'FAA nearby query failed')
  const features = Array.isArray(payload?.features) ? payload.features : []
  return features.filter((feature: Json) => {
    const coordinates = feature?.geometry?.coordinates
    return feature?.geometry?.type !== 'Point' || (Array.isArray(coordinates) && haversineMiles(lat, lon, Number(coordinates[1]), Number(coordinates[0])) <= radiusMiles)
  })
}
function compactDateRange(text: unknown) {
  const matches = [...String(text || '').matchAll(/(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{1,2}),\s+(\d{4})/gi)]
  const toIso = (match: RegExpMatchArray | undefined, end = false) => {
    if (!match) return null
    const date = new Date(`${match[1]} ${match[2]}, ${match[3]} 00:00:00 UTC`)
    if (end) date.setUTCHours(23, 59, 59, 999)
    return Number.isFinite(date.getTime()) ? date.toISOString() : null
  }
  return { from: toIso(matches[0]), to: toIso(matches[1], true) || toIso(matches[0], true) }
}
function overlapsNow(from: string | null, to: string | null, now: Date) {
  return !(from && new Date(from) > now) && !(to && new Date(to) < now)
}
function segmentContains(x: number, y: number, a: number, b: number, c: number, d: number) {
  const cross = (x - a) * (d - b) - (y - b) * (c - a)
  if (Math.abs(cross) > 1e-9) return false
  const dot = (x - a) * (c - a) + (y - b) * (d - b)
  const length = (c - a) ** 2 + (d - b) ** 2
  return dot >= 0 && dot <= length
}
function inRing(x: number, y: number, ring: any[]) {
  let inside = false
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const a = ring[i], b = ring[j]
    if (segmentContains(x, y, +a[0], +a[1], +b[0], +b[1])) return true
    if (((+a[1] > y) !== (+b[1] > y)) && (x < (+b[0] - +a[0]) * (y - +a[1]) / ((+b[1] - +a[1]) || 1e-30) + +a[0])) inside = !inside
  }
  return inside
}
function pointInGeometry(x: number, y: number, geometry: Json): boolean {
  if (geometry?.type === 'Polygon') {
    const rings = geometry.coordinates || []
    if (!rings.length || !inRing(x, y, rings[0])) return false
    for (let i = 1; i < rings.length; i += 1) if (inRing(x, y, rings[i])) return false
    return true
  }
  if (geometry?.type === 'MultiPolygon') return (geometry.coordinates || []).some((polygon: any) => pointInGeometry(x, y, { type: 'Polygon', coordinates: polygon }))
  return false
}

async function refreshStatic(slug: string, anchor: Anchor) {
  const polygon = geojsonToEsriPolygon(anchor.boundary_geojson)
  if (!polygon) throw new Error('selected parcel boundary is unavailable')
  const localPromise = admin.rpc('farm_watch_get_regulatory_local_v1_internal', { p_slug: slug })
  const results = await Promise.allSettled([
    arcgisIntersect(SOURCES.zoning, polygon, 'Zoning,PARCEL_ID'),
    arcgisIntersect(SOURCES.futureLandUse, polygon, 'Fut_LU,PARCEL_ID'),
    arcgisIntersect(SOURCES.femaFlood, polygon, 'DFIRM_ID,FLD_ZONE,ZONE_SUBTY,SFHA_TF,STATIC_BFE,V_DATUM,SOURCE_CIT'),
    arcgisIntersect(SOURCES.countyFlood, polygon, 'DFIRM_ID,FLD_ZONE,ZONE_SUBTY,SFHA_TF,STATIC_BFE,V_DATUM,SOURCE_CIT'),
    localPromise,
  ])
  const errors: Record<string, string> = {}
  const get = (index: number, key: string) => {
    const result = results[index]
    if (result.status === 'fulfilled') return result.value
    errors[key] = result.reason instanceof Error ? result.reason.message : String(result.reason)
    return null
  }
  const zoningRows: any[] | null = get(0, 'franklin_county_zoning')
  const futureRows: any[] | null = get(1, 'franklin_county_future_land_use')
  const femaRows: any[] | null = get(2, 'fema_nfhl')
  const countyFloodRows: any[] | null = get(3, 'franklin_county_flood')
  const localResult: any = get(4, 'scout_local_regulatory')
  const local = localResult?.data || null
  if (localResult?.error) errors.scout_local_regulatory = localResult.error.message || 'local regulatory RPC failed'

  const unique = (rows: any[] | null, key: string) => [...new Set((rows || []).map((row) => String(row?.[key] || '').trim()).filter(Boolean))]
  const futureLabels = unique(futureRows, 'Fut_LU')
  const context = {
    retrieved_at: new Date().toISOString(),
    land_use: {
      zoning: {
        source: 'Franklin County Planning & Zoning GIS',
        codes: unique(zoningRows, 'Zoning'),
        intersecting_features: zoningRows?.length ?? null,
        selected_parcel_geometry_used_for_intersection: true,
      },
      future_land_use: {
        source: 'Franklin County Planning & Zoning GIS',
        labels: futureLabels,
        source_field_width: 24,
        source_value_may_be_truncated: futureLabels.some((label) => label.length >= 24),
        intersecting_features: futureRows?.length ?? null,
      },
    },
    flood: {
      fema_nfhl: femaRows === null ? { status: 'unavailable' } : {
        status: 'available',
        intersecting_zone_count: femaRows.length,
        zones: (femaRows || []).map((row) => ({
          flood_zone: row.FLD_ZONE ?? null,
          subtype: row.ZONE_SUBTY ?? null,
          special_flood_hazard_area: row.SFHA_TF ?? null,
          static_bfe: row.STATIC_BFE ?? null,
          vertical_datum: row.V_DATUM ?? null,
          dfirm_id: row.DFIRM_ID ?? null,
          source_citation: row.SOURCE_CIT ?? null,
        })),
        absence_semantics: femaRows.length === 0 ? 'No mapped NFHL Flood Hazard Zone polygon intersects the selected parcel; this is not a guarantee of no flood risk.' : null,
      },
      county_corroboration: countyFloodRows === null ? { status: 'unavailable' } : {
        status: 'available',
        intersecting_zone_count: countyFloodRows.length,
        zones: (countyFloodRows || []).map((row) => ({ flood_zone: row.FLD_ZONE ?? null, subtype: row.ZONE_SUBTY ?? null, special_flood_hazard_area: row.SFHA_TF ?? null })),
      },
    },
    hunting: local?.hunting || null,
    protected_lands: local?.protected_lands || null,
    source_errors: errors,
    provenance: {
      financial_context_included: false,
      ownership_context_included: false,
      imagery_pixels_analyzed: false,
      source_attributes_allowlisted: true,
    },
  }
  const successCount = 5 - Object.keys(errors).length
  const status = successCount === 5 ? 'available' : successCount > 0 ? 'partial' : 'unavailable'
  await admin.rpc('farm_watch_upsert_regulatory_static_v1_internal', {
    p_slug: slug, p_status: status, p_context: context, p_retrieved_at: context.retrieved_at,
  })
  return { status, context, retrieved_at: context.retrieved_at, cache: 'miss' }
}

function surfaceClass(feature: Json) {
  const props = feature?.properties || {}
  const airspaceClass = String(props.CLASS || '').trim().toUpperCase()
  const lowerValue = num(props.LOWER_VAL ?? props.LOWER_VALUE ?? props.LOWER_ALT ?? props.LOWER_ALTITUDE)
  const lowerCode = String(props.LOWER_CODE ?? props.LOWER_DESC ?? props.LOWER ?? '').trim().toUpperCase()
  if (!['B', 'C', 'D', 'E'].includes(airspaceClass)) return { airspaceClass, surfaceControlled: false, uncertain: false, lowerValue, lowerCode }
  const surfaceControlled = lowerValue !== null ? lowerValue <= 0 : /\bSFC\b|SURFACE/.test(lowerCode)
  const uncertain = lowerValue === null && !lowerCode
  return { airspaceClass, surfaceControlled, uncertain, lowerValue, lowerCode }
}
async function refreshFaa(slug: string, anchor: Anchor) {
  const lat = Number(anchor.lat), lon = Number(anchor.lon)
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) throw new Error('property regulatory reference point is unavailable')
  const awarenessNames = ['uasfm', 'class_airspace', 'full_national_security', 'part_national_security', 'special_use', 'airports', 'stadiums', 'boundary_airspace']
  const awareness = await Promise.allSettled([
    arcgisPoint(SOURCES.uasfm, lat, lon),
    arcgisPoint(SOURCES.classAirspace, lat, lon),
    arcgisPoint(SOURCES.fullNationalSecurity, lat, lon),
    arcgisPoint(SOURCES.partNationalSecurity, lat, lon),
    arcgisPoint(SOURCES.specialUse, lat, lon),
    arcgisNearbyPoints(SOURCES.airports, lat, lon, 2),
    arcgisNearbyPoints(SOURCES.stadiums, lat, lon, 3),
    arcgisPoint(SOURCES.boundaryAirspace, lat, lon),
  ])
  const awarenessErrors: Record<string, string> = {}
  const features: Record<string, Json[]> = {}
  awareness.forEach((result, index) => {
    const key = awarenessNames[index]
    if (result.status === 'fulfilled') features[key] = result.value as Json[]
    else { features[key] = []; awarenessErrors[key] = result.reason instanceof Error ? result.reason.message : String(result.reason) }
  })

  const classSummary = (features.class_airspace || []).map(surfaceClass)
  const surfaceControlled = classSummary.filter((item) => item.surfaceControlled)
  const uncertainSurface = classSummary.filter((item) => item.uncertain)
  const uasfmProps = (features.uasfm || []).map((feature) => feature?.properties || {})
  const ceilings = uasfmProps.map((props) => num(props.CEILING)).filter((value): value is number => value !== null)
  const uasfmCeiling = ceilings.length ? Math.min(...ceilings) : null
  let laancAvailable = false
  for (const props of uasfmProps) {
    for (let i = 1; i <= 5; i += 1) {
      const value = `${props[`APT${i}_LAANC`] ?? ''} ${props[`APT${i}_Enabled`] ?? props[`APT${i}_ENABLED`] ?? ''}`.toLowerCase()
      if (/\b(1|y|yes|true|enabled|active|laanc|107)\b/.test(value)) laancAvailable = true
    }
  }

  const now = new Date()
  const tfrErrors: Record<string, string> = {}
  const tfrResults = await Promise.allSettled([
    fetchJson(SOURCES.tfrList),
    (async () => {
      const wfs = new URL(SOURCES.tfrWfs)
      const eps = .02
      for (const [key, value] of Object.entries({ service: 'WFS', version: '1.1.0', request: 'GetFeature', typeName: 'TFR:V_TFR_LOC', outputFormat: 'application/json', srsname: 'EPSG:4326', bbox: `${lon - eps},${lat - eps},${lon + eps},${lat + eps},EPSG:4326` })) wfs.searchParams.set(key, value)
      return fetchJson(wfs.toString())
    })(),
    fetchJson(SOURCES.tfrNoShape),
  ])
  const tfrList = tfrResults[0].status === 'fulfilled' && Array.isArray(tfrResults[0].value) ? tfrResults[0].value : (tfrErrors.list = tfrResults[0].status === 'rejected' ? String(tfrResults[0].reason) : 'invalid FAA TFR list', [])
  const tfrGeometry = tfrResults[1].status === 'fulfilled' && Array.isArray(tfrResults[1].value?.features) ? tfrResults[1].value.features : (tfrErrors.geometry = tfrResults[1].status === 'rejected' ? String(tfrResults[1].reason) : 'invalid FAA TFR geometry', [])
  const tfrNoShape = tfrResults[2].status === 'fulfilled' && Array.isArray(tfrResults[2].value) ? tfrResults[2].value : (tfrErrors.no_shape = tfrResults[2].status === 'rejected' ? String(tfrResults[2].reason) : 'invalid FAA no-shape TFR list', [])
  const tfrById = new Map<string, any>()
  for (const row of tfrList) {
    const id = String(row.notam_id ?? row.gid ?? '').trim()
    if (id) tfrById.set(id, row)
  }
  const currentMappedTfrs: any[] = []
  for (const feature of tfrGeometry) {
    if (!pointInGeometry(lon, lat, feature?.geometry)) continue
    const props = feature?.properties || {}
    const key = String(props.NOTAM_KEY || '')
    const id = key.match(/^\d+\/\d+/)?.[0] || null
    const row = id ? tfrById.get(id) : null
    const dates = compactDateRange(row?.description)
    if (!overlapsNow(dates.from, dates.to, now)) continue
    currentMappedTfrs.push({ identifier: id || key || null, title: row?.description || props.TITLE || 'FAA Temporary Flight Restriction', effective_from: dates.from, effective_to: dates.to })
  }
  const stateCode = String(anchor.state_code || '').toUpperCase()
  const currentNoShape = tfrNoShape.filter((row: any) => {
    if (stateCode && String(row?.state || '').toUpperCase() !== stateCode) return false
    const dates = compactDateRange(row?.description)
    return overlapsNow(dates.from, dates.to, now)
  }).slice(0, 20).map((row: any) => ({ identifier: row.notam_id ?? row.gid ?? null, title: row.description ?? 'FAA TFR without mapped shape' }))

  const complete = Object.keys(awarenessErrors).length === 0 && Object.keys(tfrErrors).length === 0
  let finding = 'no_current_surface_or_tfr_restriction_detected_at_reference_point'
  if (surfaceControlled.length) finding = 'surface_controlled_airspace_authorization_required'
  if ((features.full_national_security || []).length) finding = 'national_security_uas_restriction_detected'
  if (currentMappedTfrs.length) finding = 'current_mapped_tfr_detected'
  if (!complete) finding = 'unknown_due_to_incomplete_source_coverage'
  else if (currentNoShape.length && !currentMappedTfrs.length) finding = 'review_current_no_shape_tfr_notices'

  const cleanNearby = (list: Json[]) => list.slice(0, 10).map((feature) => {
    const props = feature?.properties || {}
    const coords = feature?.geometry?.coordinates
    const distance = Array.isArray(coords) ? haversineMiles(lat, lon, Number(coords[1]), Number(coords[0])) : null
    return {
      identifier: props.ARPT_ID ?? props.FAA_ID ?? props.ICAO_ID ?? props.IDENT ?? props.OBJECTID ?? null,
      name: props.ARPT_NAME ?? props.STADIUM ?? props.NAME ?? props.FACILITY ?? null,
      distance_miles: distance === null ? null : Number(distance.toFixed(2)),
    }
  })
  const context = {
    checked_at: now.toISOString(),
    reference_scope: 'property reference point; not a flight authorization',
    finding,
    source_coverage_complete: complete,
    part107_airspace_authorization: surfaceControlled.length ? 'required_for_surface_controlled_airspace' : complete ? 'not_indicated_by_surface_class_at_reference_point' : 'unknown',
    surface_airspace: {
      classes: [...new Set(classSummary.map((item) => item.airspaceClass).filter(Boolean))],
      surface_controlled_classes: [...new Set(surfaceControlled.map((item) => item.airspaceClass))],
      uncertain_feature_count: uncertainSurface.length,
      features: classSummary.map((item) => ({ class: item.airspaceClass, lower_value: item.lowerValue, lower_code: item.lowerCode, surface_controlled: item.surfaceControlled })),
    },
    uas_facility_map: { cell_count: uasfmProps.length, minimum_grid_ceiling_ft: uasfmCeiling, laanc_available: laancAvailable, informational_not_authorization: true },
    national_security: { full_time_count: (features.full_national_security || []).length, part_time_count: (features.part_national_security || []).length },
    special_use_airspace: { feature_count: (features.special_use || []).length },
    nearby_airports_within_2_miles: cleanNearby(features.airports || []),
    nearby_stadiums_within_3_miles: cleanNearby(features.stadiums || []),
    temporary_flight_restrictions: { mapped_current: currentMappedTfrs, no_shape_state_notices_requiring_review: currentNoShape },
    source_errors: { awareness: awarenessErrors, tfr: tfrErrors },
    provenance: { authority: 'Federal Aviation Administration', uasfm_is_authorization: false, imagery_pixels_analyzed: false },
  }
  const status = complete ? 'available' : Object.keys(awarenessErrors).length < awarenessNames.length ? 'partial' : 'unavailable'
  await admin.rpc('farm_watch_upsert_regulatory_faa_v1_internal', { p_slug: slug, p_status: status, p_context: context, p_checked_at: context.checked_at })
  return { status, context, checked_at: context.checked_at, cache: 'miss' }
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
  const { data: anchor, error: anchorError } = await admin.rpc('farm_watch_get_regulatory_anchor_v1_internal', { p_slug: slug })
  if (anchorError || !anchor?.property_id) return json({ error: 'regulatory context unavailable' }, 503, origin)

  const { data: cached } = await admin.rpc('farm_watch_get_regulatory_context_v1_internal', { p_slug: slug })
  let staticPart: any = null
  const staticAt = Date.parse(cached?.static_retrieved_at || '')
  if (cached?.static_context && Number.isFinite(staticAt) && Date.now() - staticAt < STATIC_TTL_MS) {
    staticPart = { status: cached.static_status || 'unknown', context: cached.static_context, retrieved_at: cached.static_retrieved_at, cache: 'hit' }
  } else {
    try { staticPart = await refreshStatic(slug, anchor as Anchor) }
    catch (error) { staticPart = { status: 'unavailable', context: cached?.static_context || {}, retrieved_at: cached?.static_retrieved_at || null, cache: 'stale', error: error instanceof Error ? error.message : String(error) } }
  }

  let faaPart: any = null
  const faaAt = Date.parse(cached?.faa_checked_at || '')
  if (cached?.faa_context && Number.isFinite(faaAt) && Date.now() - faaAt < FAA_TTL_MS) {
    faaPart = { status: cached.faa_status || 'unknown', context: cached.faa_context, checked_at: cached.faa_checked_at, cache: 'hit' }
  } else {
    try { faaPart = await refreshFaa(slug, anchor as Anchor) }
    catch (error) { faaPart = { status: 'unavailable', context: cached?.faa_context || { finding: 'unknown_due_to_refresh_failure' }, checked_at: cached?.faa_checked_at || null, cache: 'stale', error: error instanceof Error ? error.message : String(error) } }
  }

  return json({
    property: { slug, selected_parcel_id: anchor.selected_parcel_id || null },
    static: staticPart,
    faa: faaPart,
    product_boundaries: {
      financial_context_included: false,
      ownership_context_included: false,
      imagery_analysis_performed: false,
    },
  }, 200, origin)
})
