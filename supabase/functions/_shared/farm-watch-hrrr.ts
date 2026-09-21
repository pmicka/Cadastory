import {
  ECCODES_MISSING_VALUE,
  decodeFieldValues,
  lambertConeConstant,
  lambertEarthWind,
  nearestGridpoint,
  parseFields,
  parseGrid,
  parseIdx,
  type IdxRecord,
} from 'npm:@azohra/meteo.grib@0.1.4'

export const HRRR_MODEL_SLUG = 'noaa-hrrr-conus-3km'
export const HRRR_ALGORITHM_VERSION = 'noaa-hrrr-nearest-grid-analysis-v1'
export const HRRR_OUTPUT_SCHEMA_VERSION = 'farm-watch-meteorological-forcing-v1'
export const HRRR_EVIDENCE_CLASS = 'modeled_environmental_proxy'
export const HRRR_MAX_GRID_DISTANCE_KM = 5
export const HRRR_BASE_URL = 'https://noaa-hrrr-bdp-pds.s3.amazonaws.com'
export const HRRR_LAMBERT_ORIENTATION_DEG = 262.5
export const HRRR_LAMBERT_CONE = lambertConeConstant(38.5, 38.5)

export type FarmWatchMeteorologyTarget = {
  property_id?: string
  slug: string
  latitude: number
  longitude: number
  boundary_sha256: string
}

export type HrrrFieldKey =
  | 'air_temperature_2m_c'
  | 'dew_point_2m_c'
  | 'relative_humidity_2m_pct'
  | 'wind_grid_u_10m_mps'
  | 'wind_grid_v_10m_mps'
  | 'downward_shortwave_wm2'
  | 'downward_longwave_wm2'
  | 'total_cloud_cover_pct'
  | 'precipitation_rate_mm_hr'

type FieldSpec = {
  key: HrrrFieldKey
  variable: string
  level: string
  convert: (value: number) => number
}

export const HRRR_REQUIRED_FIELDS: readonly FieldSpec[] = Object.freeze([
  { key: 'air_temperature_2m_c', variable: 'TMP', level: '2 m above ground', convert: (v) => v - 273.15 },
  { key: 'dew_point_2m_c', variable: 'DPT', level: '2 m above ground', convert: (v) => v - 273.15 },
  { key: 'relative_humidity_2m_pct', variable: 'RH', level: '2 m above ground', convert: (v) => v },
  { key: 'wind_grid_u_10m_mps', variable: 'UGRD', level: '10 m above ground', convert: (v) => v },
  { key: 'wind_grid_v_10m_mps', variable: 'VGRD', level: '10 m above ground', convert: (v) => v },
  { key: 'downward_shortwave_wm2', variable: 'DSWRF', level: 'surface', convert: (v) => v },
  { key: 'downward_longwave_wm2', variable: 'DLWRF', level: 'surface', convert: (v) => v },
  { key: 'total_cloud_cover_pct', variable: 'TCDC', level: 'entire atmosphere', convert: (v) => v },
  { key: 'precipitation_rate_mm_hr', variable: 'PRATE', level: 'surface', convert: (v) => v * 3600 },
] as const)

export function floorUtcHour(value: Date): Date {
  const out = new Date(value.getTime())
  out.setUTCMinutes(0, 0, 0)
  return out
}

export function candidateReferenceTimes(now: Date, lookbackHours = 8): Date[] {
  const bounded = Math.max(0, Math.min(24, Math.floor(lookbackHours)))
  const start = floorUtcHour(now)
  return Array.from({ length: bounded + 1 }, (_, i) => new Date(start.getTime() - i * 3_600_000))
}

function stamp(referenceTime: Date) {
  return {
    date: referenceTime.toISOString().slice(0, 10).replaceAll('-', ''),
    hour: referenceTime.toISOString().slice(11, 13),
  }
}

export function hrrrAnalysisFileUrl(referenceTime: Date): string {
  const { date, hour } = stamp(referenceTime)
  return `${HRRR_BASE_URL}/hrrr.${date}/conus/hrrr.t${hour}z.wrfsfcf00.grib2`
}

export function hrrrAnalysisIndexUrl(referenceTime: Date): string {
  return hrrrAnalysisFileUrl(referenceTime) + '.idx'
}

function isAnalysisForecast(value: string) {
  const normalized = value.trim().toLowerCase()
  return normalized === 'anl' || normalized === 'analysis' || normalized === '0 hour fcst'
}

export function findAnalysisRecord(records: IdxRecord[], variable: string, level: string): IdxRecord {
  const match = records.find((record) =>
    record.variable === variable &&
    record.level === level &&
    isAnalysisForecast(record.forecast)
  )
  if (!match) throw new Error(`HRRR analysis record is unavailable: ${variable}:${level}`)
  return match
}

export function selectRequiredAnalysisRecords(indexText: string): Record<HrrrFieldKey, IdxRecord> {
  const records = parseIdx(indexText)
  if (!records.length) throw new Error('HRRR index contained no records')
  return Object.fromEntries(
    HRRR_REQUIRED_FIELDS.map((field) => [
      field.key,
      findAnalysisRecord(records, field.variable, field.level),
    ]),
  ) as Record<HrrrFieldKey, IdxRecord>
}

export function byteRange(record: IdxRecord): string {
  return record.length === undefined
    ? `bytes=${record.offset}-`
    : `bytes=${record.offset}-${record.offset + record.length - 1}`
}

async function sha256Hex(value: string | Uint8Array): Promise<string> {
  const bytes = typeof value === 'string' ? new TextEncoder().encode(value) : value
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))
  return [...digest].map((byte) => byte.toString(16).padStart(2, '0')).join('')
}

async function fetchRecordBytes(fetchImpl: typeof fetch, fileUrl: string, record: IdxRecord) {
  const response = await fetchImpl(fileUrl, {
    headers: {
      range: byteRange(record),
      'user-agent': 'Scout-by-Cadastory/1.0',
    },
    signal: AbortSignal.timeout(20_000),
  })
  if (response.status !== 206) {
    throw new Error(`HRRR range request returned ${response.status}`)
  }
  return new Uint8Array(await response.arrayBuffer())
}

function finite(value: unknown, label: string): number {
  const number = Number(value)
  if (!Number.isFinite(number)) throw new Error(`HRRR ${label} is not finite`)
  return number
}

function windFromEarthUv(uEastMps: number, vNorthMps: number) {
  const speed = Math.hypot(uEastMps, vNorthMps)
  const directionFrom = (((Math.atan2(-uEastMps, -vNorthMps) * (180 / Math.PI)) % 360) + 360) % 360
  return { speed, directionFrom }
}

function rounded(value: number, digits = 6) {
  const scale = 10 ** digits
  return Math.round(value * scale) / scale
}

export type HrrrSample = {
  fields: Record<string, number>
  grid: {
    latitude: number
    longitude: number
    distance_m: number
  }
  records: Array<{
    key: HrrrFieldKey
    variable: string
    level: string
    forecast: string
    offset: number
    length: number | null
  }>
  source_records_sha256: string
}

export async function sampleHrrrAnalysisTargets(
  fetchImpl: typeof fetch,
  fileUrl: string,
  selectedRecords: Record<HrrrFieldKey, IdxRecord>,
  targets: readonly FarmWatchMeteorologyTarget[],
): Promise<Record<string, HrrrSample>> {
  if (!targets.length) return {}

  const states = new Map<string, {
    fields: Partial<Record<HrrrFieldKey, number>>
    grid: { latitude: number; longitude: number; distance_m: number } | null
  }>()
  for (const target of targets) {
    states.set(target.slug, { fields: {}, grid: null })
  }

  const recordDescriptors: HrrrSample['records'] = []

  for (const spec of HRRR_REQUIRED_FIELDS) {
    const record = selectedRecords[spec.key]
    const bytes = await fetchRecordBytes(fetchImpl, fileUrl, record)
    const field = parseFields(bytes)[0]
    if (!field) throw new Error(`HRRR record ${spec.variable} contained no decodable GRIB field`)

    const grid = parseGrid(field.section3)
    const points = new Map<string, ReturnType<typeof nearestGridpoint>>()
    for (const target of targets) {
      const point = nearestGridpoint(grid, target.latitude, target.longitude)
      if (point.distanceKm > HRRR_MAX_GRID_DISTANCE_KM) {
        throw new Error(
          `HRRR nearest grid point for ${target.slug} is ${point.distanceKm.toFixed(3)} km away; max is ${HRRR_MAX_GRID_DISTANCE_KM} km`,
        )
      }
      points.set(target.slug, point)
    }

    const decoded = decodeFieldValues(field, { missingValue: ECCODES_MISSING_VALUE })

    for (const target of targets) {
      const point = points.get(target.slug)!
      const missing = decoded.missingMask !== undefined && decoded.missingMask[point.index] === 1
      if (missing) throw new Error(`HRRR field ${spec.variable} is missing at target ${target.slug}`)
      const raw = finite(decoded.values[point.index], spec.variable)
      const state = states.get(target.slug)!
      state.fields[spec.key] = rounded(spec.convert(raw))

      const nextGrid = {
        latitude: rounded(point.latitude, 8),
        longitude: rounded(point.longitude, 8),
        distance_m: rounded(point.distanceKm * 1000, 1),
      }
      if (state.grid === null) {
        state.grid = nextGrid
      } else if (
        Math.abs(nextGrid.latitude - state.grid.latitude) > 1e-8 ||
        Math.abs(nextGrid.longitude - state.grid.longitude) > 1e-8
      ) {
        throw new Error(`HRRR required fields resolved to inconsistent grid points for ${target.slug}`)
      }
    }

    recordDescriptors.push({
      key: spec.key,
      variable: spec.variable,
      level: spec.level,
      forecast: record.forecast,
      offset: record.offset,
      length: record.length ?? null,
    })
  }

  const output: Record<string, HrrrSample> = {}
  for (const target of targets) {
    const state = states.get(target.slug)!
    const grid = state.grid
    if (!grid) throw new Error(`HRRR grid metadata is unavailable for ${target.slug}`)

    const gridU = finite(state.fields.wind_grid_u_10m_mps, '10 m grid U wind')
    const gridV = finite(state.fields.wind_grid_v_10m_mps, '10 m grid V wind')
    const [uEast, vNorth] = lambertEarthWind(
      gridU,
      gridV,
      grid.longitude,
      HRRR_LAMBERT_ORIENTATION_DEG,
      HRRR_LAMBERT_CONE,
    )
    const wind = windFromEarthUv(uEast, vNorth)
    const fields: Record<string, number> = {
      ...state.fields as Record<string, number>,
      wind_east_10m_mps: rounded(uEast),
      wind_north_10m_mps: rounded(vNorth),
      wind_speed_10m_mps: rounded(wind.speed),
      wind_direction_from_deg: rounded(wind.directionFrom, 3),
    }

    output[target.slug] = {
      fields,
      grid,
      records: recordDescriptors,
      source_records_sha256: await sha256Hex(JSON.stringify({
        records: recordDescriptors,
        grid,
        fields,
      })),
    }
  }
  return output
}

export async function hashHrrrIndex(indexText: string) {
  return await sha256Hex(indexText)
}
