import 'jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.115.0'
import {
  farmWatchPresentationCapabilities,
  normalizeFarmWatchAccountRole,
} from '../_shared/farm-watch-presentation-policy.ts'

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
const EMPTY_FEATURE_COLLECTION = { type: 'FeatureCollection', features: [] }
const HYDRO_BUFFER_M = 3000
const HYDRO_DISPLAY_BUFFER_M = 1000
const HYDRO_AVAILABLE_TTL_MS = 30 * 24 * 60 * 60 * 1000
const HYDRO_PARTIAL_TTL_MS = 60 * 60 * 1000
const SOIL_MAP_TTL_MS = 30 * 24 * 60 * 60 * 1000
const SOIL_DEEP_TTL_MS = 30 * 24 * 60 * 60 * 1000

const HYDRO_SOURCES = [
  {
    key: 'flowline',
    sourceSlug: 'usgs-3dhp',
    featureKind: 'flowline',
    url: 'https://3dhp.nationalmap.gov/arcgis/rest/services/usgs_3dhp_all/MapServer/50',
    outFields: 'OBJECTID,id3dhp,gnisidlabel,featuretypelabel,lengthkm,flowdirectionlabel,streamorder,onsurfacelabel',
    bufferM: 1000,
    timeoutMs: 15000,
  },
  {
    key: 'waterbody',
    sourceSlug: 'usgs-3dhp',
    featureKind: 'waterbody',
    url: 'https://3dhp.nationalmap.gov/arcgis/rest/services/usgs_3dhp_all/MapServer/60',
    outFields: 'OBJECTID,id3dhp,gnisidlabel,featuretypelabel,areasqkm',
    bufferM: 3000,
    timeoutMs: 15000,
  },
  {
    key: 'wetland',
    sourceSlug: 'usfws-nwi',
    featureKind: 'wetland',
    url: 'https://fwspublicservices.wim.usgs.gov/wetlandsmapservice/rest/services/Wetlands/MapServer/0',
    outFields: '*',
    bufferM: 3000,
    timeoutMs: 15000,
  },
] as const

function headers(origin = ''): Record<string, string> {
  const out: Record<string, string> = {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store, max-age=0',
    'pragma': 'no-cache',
    'referrer-policy': 'no-referrer',
    'x-content-type-options': 'nosniff',
  }
  if (ALLOWED_ORIGINS.has(origin)) {
    out['access-control-allow-origin'] = origin
    out['vary'] = 'Origin'
    out['access-control-allow-headers'] = 'authorization, content-type, apikey'
    out['access-control-allow-methods'] = 'GET, OPTIONS'
  }
  return out
}

function json(body: unknown, status = 200, origin = '') {
  return new Response(JSON.stringify(body), { status, headers: headers(origin) })
}

function bearer(req: Request): string | null {
  const value = req.headers.get('authorization') || ''
  const match = /^Bearer\s+(.+)$/i.exec(value)
  return match?.[1]?.trim() || null
}

function boundedSlug(value: string | null): string | null {
  if (!value) return DEFAULT_PROPERTY_SLUG
  const normalized = value.trim().toLowerCase()
  return /^[a-z0-9][a-z0-9-]{0,79}$/.test(normalized) ? normalized : null
}

type Center = { lat: number; lon: number; basis: string; matched_address?: string }
type Envelope = { west: number; south: number; east: number; north: number }

type HydroSource = typeof HYDRO_SOURCES[number]

async function censusCenter(address: string): Promise<Center | null> {
  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), 6000)
  try {
    const url = new URL('https://geocoding.geo.census.gov/geocoder/locations/onelineaddress')
    url.searchParams.set('address', address)
    url.searchParams.set('benchmark', 'Public_AR_Current')
    url.searchParams.set('format', 'json')
    const response = await fetch(url, {
      signal: controller.signal,
      headers: {
        'accept': 'application/json',
        'user-agent': 'Cadastory-Property-History/0.1 (https://pmicka.com)',
      },
    })
    if (!response.ok) return null
    const payload = await response.json()
    const match = payload?.result?.addressMatches?.[0]
    const x = Number(match?.coordinates?.x)
    const y = Number(match?.coordinates?.y)
    if (!Number.isFinite(x) || !Number.isFinite(y)) return null
    return {
      lat: y,
      lon: x,
      basis: 'US Census Geocoder address match',
      ...(typeof match?.matchedAddress === 'string' ? { matched_address: match.matchedAddress } : {}),
    }
  } catch {
    return null
  } finally {
    clearTimeout(timeout)
  }
}

function storedCenter(property: any): Center | null {
  const coords = property?.center_geojson?.coordinates
  if (!Array.isArray(coords) || coords.length < 2) return null
  const lon = Number(coords[0])
  const lat = Number(coords[1])
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) return null
  return { lat, lon, basis: 'stored property center' }
}

function collectCoordinatePairs(value: unknown, out: number[][]) {
  if (!Array.isArray(value)) return
  if (value.length >= 2 && Number.isFinite(Number(value[0])) && Number.isFinite(Number(value[1]))) {
    out.push([Number(value[0]), Number(value[1])])
    return
  }
  for (const child of value) collectCoordinatePairs(child, out)
}

function expandedEnvelope(boundary: any, bufferM: number): Envelope | null {
  const pairs: number[][] = []
  collectCoordinatePairs(boundary?.coordinates, pairs)
  if (!pairs.length) return null
  const lons = pairs.map((pair) => pair[0])
  const lats = pairs.map((pair) => pair[1])
  const west = Math.min(...lons)
  const east = Math.max(...lons)
  const south = Math.min(...lats)
  const north = Math.max(...lats)
  const centerLat = (south + north) / 2
  const latPad = bufferM / 111320
  const lonMetersPerDegree = 111320 * Math.max(0.2, Math.cos(centerLat * Math.PI / 180))
  const lonPad = bufferM / lonMetersPerDegree
  return { west: west - lonPad, east: east + lonPad, south: south - latPad, north: north + latPad }
}

function pickProperty(properties: Record<string, unknown>, ...keys: string[]) {
  for (const key of keys) {
    const value = properties?.[key]
    if (value !== undefined && value !== null && value !== '') return value
  }
  return null
}

function normalizeHydroProperties(source: HydroSource, properties: Record<string, unknown>) {
  if (source.featureKind === 'flowline') {
    return {
      name: pickProperty(properties, 'gnisidlabel'),
      feature_type: pickProperty(properties, 'featuretypelabel'),
      length_km: pickProperty(properties, 'lengthkm'),
      stream_order: pickProperty(properties, 'streamorder'),
      flow_direction: pickProperty(properties, 'flowdirectionlabel'),
      on_surface: pickProperty(properties, 'onsurfacelabel'),
    }
  }
  if (source.featureKind === 'waterbody') {
    return {
      name: pickProperty(properties, 'gnisidlabel'),
      feature_type: pickProperty(properties, 'featuretypelabel'),
      area_sq_km: pickProperty(properties, 'areasqkm'),
    }
  }
  return {
    attribute_code: pickProperty(properties, 'ATTRIBUTE', 'Wetlands.ATTRIBUTE'),
    wetland_type: pickProperty(properties, 'WETLAND_TYPE', 'Wetlands.WETLAND_TYPE'),
    source_acres: pickProperty(properties, 'ACRES', 'Wetlands.ACRES'),
    system_name: pickProperty(properties, 'SYSTEM_NAME', 'NWI_Wetland_Codes.SYSTEM_NAME'),
    class_name: pickProperty(properties, 'CLASS_NAME', 'NWI_Wetland_Codes.CLASS_NAME'),
    water_regime_name: pickProperty(properties, 'WATER_REGIME_NAME', 'NWI_Wetland_Codes.WATER_REGIME_NAME'),
  }
}

function sourceFeatureId(source: HydroSource, feature: any, index: number) {
  const properties = feature?.properties || {}
  const candidate = source.featureKind === 'wetland'
    ? pickProperty(properties, 'GLOBALID', 'Wetlands.GLOBALID', 'OBJECTID', 'Wetlands.OBJECTID')
    : pickProperty(properties, 'id3dhp', 'OBJECTID')
  return String(candidate ?? feature?.id ?? `${source.featureKind}-${index}`)
}

async function fetchHydroSourceAttempt(source: HydroSource, envelope: Envelope) {
  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), source.timeoutMs)
  try {
    const url = new URL(`${source.url}/query`)
    url.searchParams.set('where', '1=1')
    url.searchParams.set('geometry', `${envelope.west},${envelope.south},${envelope.east},${envelope.north}`)
    url.searchParams.set('geometryType', 'esriGeometryEnvelope')
    url.searchParams.set('inSR', '4326')
    url.searchParams.set('outSR', '4326')
    url.searchParams.set('spatialRel', 'esriSpatialRelIntersects')
    url.searchParams.set('outFields', source.outFields)
    url.searchParams.set('returnGeometry', 'true')
    url.searchParams.set('geometryPrecision', '6')
    url.searchParams.set('f', 'geojson')

    const response = await fetch(url, {
      signal: controller.signal,
      headers: {
        accept: 'application/geo+json, application/json',
        'user-agent': 'Cadastory-Farm-Watch/0.2 (https://pmicka.com)',
      },
    })
    if (!response.ok) throw new Error(`${source.key} returned HTTP ${response.status}`)
    const payload = await response.json()
    if (payload?.type !== 'FeatureCollection' || !Array.isArray(payload?.features)) {
      const serviceMessage = payload?.error?.message
      throw new Error(
        serviceMessage
          ? `${source.key} returned ArcGIS error: ${serviceMessage}`
          : `${source.key} returned an invalid feature collection`
      )
    }

    return payload.features
      .filter((feature: any) => feature?.geometry)
      .map((feature: any, index: number) => ({
        source_slug: source.sourceSlug,
        feature_kind: source.featureKind,
        source_feature_id: sourceFeatureId(source, feature, index),
        geometry: feature.geometry,
        properties: normalizeHydroProperties(source, feature.properties || {}),
      }))
  } catch (error) {
    if (error instanceof DOMException && error.name === 'AbortError') {
      throw new Error(`${source.key} timed out after ${source.timeoutMs} ms`)
    }
    throw error
  } finally {
    clearTimeout(timeout)
  }
}

async function fetchHydroSource(source: HydroSource, envelope: Envelope) {
  let firstError: unknown = null
  for (let attempt = 1; attempt <= 2; attempt += 1) {
    try {
      return await fetchHydroSourceAttempt(source, envelope)
    } catch (error) {
      if (attempt === 1) {
        firstError = error
        await new Promise((resolve) => setTimeout(resolve, 400))
        continue
      }
      const firstMessage = firstError instanceof Error ? firstError.message : String(firstError)
      const finalMessage = error instanceof Error ? error.message : String(error)
      throw new Error(`${source.key} failed after 2 attempts; first=${firstMessage}; final=${finalMessage}`)
    }
  }
  throw new Error(`${source.key} failed without an attempt result`)
}

function soilMapUnitsNeedRefresh(soils: any) {
  const mapUnitCount = Number(soils?.summary?.map_unit_count) || 0
  const identityStatus = String(soils?.summary?.identity_status || '')
  const retrievedAt = Date.parse(soils?.summary?.retrieved_at || '')
  if (soils?.status !== 'available' || identityStatus !== 'current' || !mapUnitCount) return true
  if (!Number.isFinite(retrievedAt)) return true
  return Date.now() - retrievedAt > SOIL_MAP_TTL_MS
}

function soilDeepProfilesNeedRefresh(soils: any) {
  const mapUnitCount = Number(soils?.summary?.map_unit_count) || 0
  const deepProfileCount = Number(soils?.summary?.deep_profile_count) || 0
  const retrievedAt = Date.parse(soils?.summary?.deep_retrieved_at || '')
  if (!mapUnitCount || deepProfileCount < mapUnitCount) return true
  if (!Number.isFinite(retrievedAt)) return true
  return Date.now() - retrievedAt > SOIL_DEEP_TTL_MS
}

function hydrologyNeedsRefresh(hydrology: any) {
  const identityStatus = String(hydrology?.summary?.identity_status || '')
  const bufferM = Number(hydrology?.summary?.buffer_m)
  const retrievedAt = Date.parse(hydrology?.summary?.retrieved_at || '')
  if (identityStatus !== 'current') return true
  if (!Number.isFinite(bufferM) || bufferM < HYDRO_BUFFER_M) return true
  if (!Number.isFinite(retrievedAt)) return true
  const ttl = hydrology?.status === 'available' ? HYDRO_AVAILABLE_TTL_MS : HYDRO_PARTIAL_TTL_MS
  return Date.now() - retrievedAt > ttl
}

function filterFeatureCollectionByDistance(collection: any, maxDistanceM: number) {
  const features = Array.isArray(collection?.features) ? collection.features : []
  return {
    type: 'FeatureCollection',
    features: features.filter((feature: any) => {
      const properties = feature?.properties || {}
      if (properties.intersects_property === true) return true
      const distanceM = Number(properties.distance_m)
      return Number.isFinite(distanceM) && distanceM <= maxDistanceM
    }),
  }
}

function landscapeDomainNeedsRefresh(domain: any) {
  return domain?.status === 'missing' || domain?.status === 'stale'
}

function louisvilleCalendarDate(value = new Date()): string {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: 'America/Kentucky/Louisville',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(value)
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]))
  return `${values.year}-${values.month}-${values.day}`
}

async function readDeerContext(slug: string) {
  const now = new Date()
  const asOfDate = louisvilleCalendarDate(now)
  const at = now.toISOString()

  const { data, error } = await admin.rpc('farm_watch_resolve_deer_context_v1_internal', {
    p_slug: slug,
    p_as_of_date: asOfDate,
    p_at: at,
  })

  if (error) {
    console.error('farm_watch_resolve_deer_context_v1_internal failed', error.message)
    return {
      status: 'unavailable',
      as_of_date: asOfDate,
      at,
      component_status: {
        seasonal_state: 'unavailable',
        diel_photoperiod: 'unavailable',
        deer_biological_state: 'unavailable',
        field_phenology: 'unavailable',
      },
      seasonal_state: null,
      diel_photoperiod: null,
      deer_biological_state: null,
      field_phenology: null,
      interpretation_boundary: 'Review-only deer context is temporarily unavailable. No scoring or behavioral inference is performed.',
    }
  }

  return data
}

async function readDeerEvidenceStack(slug: string) {
  const asOfDate = louisvilleCalendarDate(new Date())
  const { data, error } = await admin.rpc('farm_watch_get_deer_evidence_stack_v1_internal', {
    p_slug: slug,
    p_as_of_date: asOfDate,
  })

  if (error) {
    console.error('farm_watch_get_deer_evidence_stack_v1_internal failed', error.message)
    return {
      status: 'unavailable',
      schema: 'deer-evidence-stack-v1',
      as_of_date: asOfDate,
      products: {},
      surface_water_state: { status: 'unavailable' },
      interpretation_boundary:
        'Neutral evidence inventory is temporarily unavailable. No scoring or behavioral inference is performed.',
    }
  }
  return data
}

async function refreshHydrology(slug: string, boundary: any) {
  const sourceRequests = HYDRO_SOURCES.map((source) => {
    const envelope = expandedEnvelope(boundary, source.bufferM)
    if (!envelope) throw new Error('Property boundary is unavailable for hydrology refresh')
    return fetchHydroSource(source, envelope)
  })

  const settled = await Promise.allSettled(sourceRequests)
  const features: any[] = []
  const sourceStatus: Record<string, any> = {
    coverage_m: Object.fromEntries(HYDRO_SOURCES.map((source) => [source.key, source.bufferM])),
  }
  const sourceErrors: Record<string, string> = {}

  settled.forEach((result, index) => {
    const source = HYDRO_SOURCES[index]
    if (result.status === 'fulfilled') {
      sourceStatus[source.key] = 'available'
      features.push(...result.value)
    } else {
      sourceStatus[source.key] = 'unavailable'
      sourceErrors[source.key] = result.reason instanceof Error ? result.reason.message : String(result.reason)
      console.error(`Farm Watch ${source.key} refresh failed`, sourceErrors[source.key])
    }
  })
  if (Object.keys(sourceErrors).length) sourceStatus.errors = sourceErrors

  const { error } = await admin.rpc('farm_watch_replace_hydrology_v1_internal', {
    p_slug: slug,
    p_features: features,
    p_buffer_m: HYDRO_BUFFER_M,
    p_source_status: sourceStatus,
    p_retrieved_at: new Date().toISOString(),
  })
  if (error) throw new Error(`farm_watch_replace_hydrology_v1_internal failed: ${error.message}`)
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get('origin') || ''
  if (origin && !ALLOWED_ORIGINS.has(origin)) return json({ error: 'not found' }, 404)
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: headers(origin) })
  if (req.method !== 'GET') return json({ error: 'not found' }, 404, origin)

  const token = bearer(req)
  if (!token) return json({ error: 'not found' }, 404, origin)

  const { data: userData, error: userError } = await admin.auth.getUser(token)
  const user = userData?.user
  if (userError || !user) return json({ error: 'not found' }, 404, origin)

  const { data: allowed, error: accessError } = await admin.rpc('farm_watch_authorize_user_v1_internal', {
    p_user_id: user.id,
  })
  if (accessError || allowed !== true) return json({ error: 'not found' }, 404, origin)

  const { data: accountRole, error: accountRoleError } = await admin.rpc('farm_watch_get_account_role_v1_internal', {
    p_user_id: user.id,
  })
  const normalizedAccountRole = normalizeFarmWatchAccountRole(accountRole)
  if (accountRoleError || !normalizedAccountRole) {
    console.error('farm_watch_get_account_role_v1_internal failed', accountRoleError?.message || 'role unavailable')
    return json({ error: 'not found' }, 404, origin)
  }

  const requestUrl = new URL(req.url)
  const slug = boundedSlug(requestUrl.searchParams.get('property'))
  if (!slug) return json({ error: 'invalid property selector' }, 400, origin)

  const { data: property, error: propertyError } = await admin.rpc('farm_watch_get_property_v1_internal', {
    p_slug: slug,
  })
  if (propertyError) {
    console.error('farm_watch_get_property_v1_internal failed', propertyError.message)
    return json({ error: 'property unavailable' }, 503, origin)
  }
  if (!property) return json({ error: 'not found' }, 404, origin)

  const { data: accessFeatures, error: accessFeaturesError } = await admin.rpc('farm_watch_get_access_features_v1_internal', {
    p_slug: slug,
    p_buffer_m: 1000,
  })
  if (accessFeaturesError) {
    console.error('farm_watch_get_access_features_v1_internal failed', accessFeaturesError.message)
  }

  const { data: operatorObservations, error: operatorObservationsError } = await admin.rpc(
    'farm_watch_get_operator_observations_v1_internal',
    { p_slug: slug, p_observation_kind: null },
  )
  if (operatorObservationsError) {
    console.error('farm_watch_get_operator_observations_v1_internal failed', operatorObservationsError.message)
  }

  let { data: soils, error: soilsError } = await admin.rpc('farm_watch_get_soils_v1_internal', {
    p_slug: slug,
  })
  if (soilsError) {
    console.error('farm_watch_get_soils_v1_internal failed', soilsError.message)
  } else {
    if (soilMapUnitsNeedRefresh(soils)) {
      try {
        const refresh = await admin.rpc('farm_watch_refresh_soils_v1_internal', { p_slug: slug })
        if (refresh.error) {
          console.error('farm_watch_refresh_soils_v1_internal failed', refresh.error.message)
        } else {
          const reread = await admin.rpc('farm_watch_get_soils_v1_internal', { p_slug: slug })
          if (reread.error) {
            console.error('farm_watch_get_soils_v1_internal map-unit reread failed', reread.error.message)
          } else {
            soils = reread.data
          }
        }
      } catch (error) {
        console.error('Farm Watch SSURGO map-unit refresh failed', error instanceof Error ? error.message : error)
      }
    }

    if (soils?.status === 'available' && soils?.summary?.identity_status === 'current' && soilDeepProfilesNeedRefresh(soils)) {
      try {
        const refresh = await admin.rpc('farm_watch_refresh_soil_profiles_v1_internal', { p_slug: slug })
        if (refresh.error) {
          console.error('farm_watch_refresh_soil_profiles_v1_internal failed', refresh.error.message)
        } else {
          const reread = await admin.rpc('farm_watch_get_soils_v1_internal', { p_slug: slug })
          if (reread.error) console.error('farm_watch_get_soils_v1_internal deep-profile reread failed', reread.error.message)
          else soils = reread.data
        }
      } catch (error) {
        console.error('Farm Watch deep SSURGO refresh failed', error instanceof Error ? error.message : error)
      }
    }
  }

  let { data: hydrology, error: hydrologyError } = await admin.rpc('farm_watch_get_hydrology_v1_internal', {
    p_slug: slug,
  })
  if (hydrologyError) {
    console.error('farm_watch_get_hydrology_v1_internal failed', hydrologyError.message)
  } else if (property.boundary_geojson && hydrologyNeedsRefresh(hydrology)) {
    try {
      await refreshHydrology(slug, property.boundary_geojson)
      const refreshed = await admin.rpc('farm_watch_get_hydrology_v1_internal', { p_slug: slug })
      if (refreshed.error) {
        console.error('farm_watch_get_hydrology_v1_internal refresh read failed', refreshed.error.message)
      } else {
        hydrology = refreshed.data
      }
    } catch (error) {
      console.error('Farm Watch hydrology refresh failed', error instanceof Error ? error.message : error)
    }
  }

  let landscapeDomain: any = null
  let landscapeDomainError: any = null
  let landscapeContext: any = null
  let landscapeContextError: any = null

  if (
    !hydrologyError &&
    hydrology?.summary?.identity_status === 'current' &&
    Number(hydrology?.summary?.buffer_m) >= HYDRO_BUFFER_M
  ) {
    const domainRead = await admin.rpc('farm_watch_get_landscape_domain_v1_internal', { p_slug: slug })
    landscapeDomain = domainRead.data
    landscapeDomainError = domainRead.error

    if (landscapeDomainError) {
      console.error('farm_watch_get_landscape_domain_v1_internal failed', landscapeDomainError.message)
    } else if (landscapeDomainNeedsRefresh(landscapeDomain)) {
      const refresh = await admin.rpc('farm_watch_refresh_landscape_domain_v1_internal', { p_slug: slug })
      if (refresh.error) {
        console.error('farm_watch_refresh_landscape_domain_v1_internal failed', refresh.error.message)
      } else {
        const reread = await admin.rpc('farm_watch_get_landscape_domain_v1_internal', { p_slug: slug })
        if (reread.error) {
          console.error('farm_watch_get_landscape_domain_v1_internal refresh read failed', reread.error.message)
          landscapeDomainError = reread.error
        } else {
          landscapeDomain = reread.data
        }
      }
    }

    if (!landscapeDomainError && landscapeDomain?.status === 'available') {
      const contextRead = await admin.rpc('farm_watch_get_landscape_context_v1_internal', { p_slug: slug })
      landscapeContext = contextRead.data
      landscapeContextError = contextRead.error
      if (landscapeContextError) {
        console.error('farm_watch_get_landscape_context_v1_internal failed', landscapeContextError.message)
      }
    }
  }

  const [deerContext, deerEvidenceStack] = await Promise.all([
    readDeerContext(slug),
    readDeerEvidenceStack(slug),
  ])

  let center = storedCenter(property)
  if (!center) {
    const address = [property.street_address, property.city, property.state_code, property.postal_code]
      .filter((part) => typeof part === 'string' && part.trim())
      .join(', ')
    if (address) center = await censusCenter(address)
  }

  return json({
    property: {
      id: property.id,
      slug: property.slug,
      display_name: property.display_name,
      address: [property.street_address, property.city, property.state_code, property.postal_code]
        .filter((part) => typeof part === 'string' && part.trim())
        .join(', '),
      stated_acres: property.stated_acres,
      center,
      boundary_geojson: property.boundary_geojson,
      metadata: property.metadata,
      updated_at: property.updated_at,
    },
    analysis: {
      access_features_geojson: accessFeaturesError || !accessFeatures ? EMPTY_FEATURE_COLLECTION : accessFeatures,
      access_features_status: accessFeaturesError ? 'unavailable' : 'available',
      access_buffer_m: 1000,
      operator_observations: operatorObservationsError || !Array.isArray(operatorObservations) ? [] : operatorObservations,
      operator_observations_status: operatorObservationsError ? 'unavailable' : 'available',
      soils_geojson: soilsError || !soils?.feature_collection ? EMPTY_FEATURE_COLLECTION : soils.feature_collection,
      soils_status: soilsError ? 'unavailable' : soils?.status || 'unavailable',
      soils_summary: soilsError ? null : soils?.summary || null,
      hydrology_geojson: hydrologyError || !hydrology?.feature_collection
        ? EMPTY_FEATURE_COLLECTION
        : filterFeatureCollectionByDistance(hydrology.feature_collection, HYDRO_DISPLAY_BUFFER_M),
      hydrology_status: hydrologyError ? 'unavailable' : hydrology?.status || 'unavailable',
      hydrology_summary: hydrologyError ? null : hydrology?.summary || null,
      hydrology_display_buffer_m: HYDRO_DISPLAY_BUFFER_M,
      hydrology_model_buffer_m: HYDRO_BUFFER_M,
      landscape_context: landscapeContextError ? null : landscapeContext,
      landscape_context_status: landscapeContextError
        ? 'unavailable'
        : landscapeContext?.status || landscapeDomain?.status || 'unavailable',
      landscape_domain_identity: landscapeDomainError || !landscapeDomain?.identity
        ? null
        : landscapeDomain.identity,
    },
    deer_context: deerContext,
    deer_evidence_stack: deerEvidenceStack,
    access: {
      scope: 'private',
      account_role: normalizedAccountRole,
      capabilities: farmWatchPresentationCapabilities(normalizedAccountRole),
    },
  }, 200, origin)
})
