import { withCollectorRun } from './collector-runtime.ts'
import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.57.4'

const legacy = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
const modern = (() => { try { return JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') || '{}').default } catch { return null } })()
const sb = createClient(Deno.env.get('SUPABASE_URL')!, modern || legacy!, { auth: { persistSession: false } })

const ECHO = 'https://services.arcgis.com/cJ9YHowT8TU7DUyn/ArcGIS/rest/services/ECHO_CWA_Facilities/FeatureServer/0/query'
const OH = 'https://geo.epa.ohio.gov/arcgis/rest/services/SurfaceWater/NPDES/FeatureServer/3/query'
const BBOX = '-87.62,36.80,-83.90,39.71'
const WRITE_CHUNK = 1000

async function authorized(req: Request) {
  const k = req.headers.get('x-scout-key') || ''
  const { data, error } = await sb.rpc('internal_validate_collector_key', { p_key: k })
  return !error && data === true
}

async function getJson(url: string) {
  const r = await fetch(url, { headers: { accept: 'application/json', 'user-agent': 'Scout-by-Cadastory/1.0' } })
  const t = await r.text()
  if (!r.ok) throw new Error(`${r.status}: ${t.slice(0, 500)}`)
  const j = JSON.parse(t)
  if (j?.error) throw new Error(JSON.stringify(j.error))
  return j
}

function date(v: any) {
  if (v == null || v === '') return null
  const d = typeof v === 'number' ? new Date(v) : new Date(String(v))
  return isNaN(d.getTime()) ? null : d.toISOString().slice(0, 10)
}

function num(v: any) {
  if (v == null || v === '') return null
  const n = Number(String(v).replace(/,/g, ''))
  return Number.isFinite(n) ? n : null
}

function chunks<T>(rows: T[], size = WRITE_CHUNK): T[][] {
  const out: T[][] = []
  for (let i = 0; i < rows.length; i += size) out.push(rows.slice(i, i + size))
  return out
}

async function echoRows() {
  const where = "master_external_permit_nmbr IN ('KYR100000','INRA00000')"
  const rows: any[] = []
  let offset = 0
  for (let page = 0; page < 50; page++) {
    const u = new URL(ECHO)
    u.searchParams.set('where', where)
    u.searchParams.set('geometry', BBOX)
    u.searchParams.set('geometryType', 'esriGeometryEnvelope')
    u.searchParams.set('inSR', '4326')
    u.searchParams.set('spatialRel', 'esriSpatialRelIntersects')
    u.searchParams.set('outFields', 'source_id,registry_id,cwp_name,cwp_state,cwp_county,master_external_permit_nmbr,cwp_permit_status_code,cwp_permit_status_desc,cwp_permit_type_code,cwp_permit_type_desc,cwp_issue_date,cwp_effective_date,cwp_expiration_date,cwp_termination_date,storm_water_area,swppp_url,permit_components,permitting_agency,fac_lat,fac_long')
    u.searchParams.set('returnGeometry', 'false')
    u.searchParams.set('resultOffset', String(offset))
    u.searchParams.set('resultRecordCount', '2000')
    u.searchParams.set('f', 'json')
    const j = await getJson(u.toString())
    const fs = j.features ?? []
    for (const f of fs) {
      const p = f.attributes ?? {}
      const sid = String(p.source_id ?? '').trim()
      const st = String(p.cwp_state ?? '').trim()
      if (!sid || !['KY', 'IN'].includes(st)) continue
      rows.push({
        source_native_id: sid,
        state_code: st,
        master_permit_number: p.master_external_permit_nmbr,
        facility_name: p.cwp_name,
        registry_id: p.registry_id,
        permit_status_code: p.cwp_permit_status_code,
        permit_status_desc: p.cwp_permit_status_desc,
        permit_type_code: p.cwp_permit_type_code,
        permit_type_desc: p.cwp_permit_type_desc,
        issue_date: date(p.cwp_issue_date),
        effective_date: date(p.cwp_effective_date),
        expiration_date: date(p.cwp_expiration_date),
        termination_date: date(p.cwp_termination_date),
        storm_water_area_acres: num(p.storm_water_area),
        storm_water_area_raw: p.storm_water_area == null ? null : String(p.storm_water_area),
        swppp_url: p.swppp_url,
        permit_components: p.permit_components,
        permitting_agency: p.permitting_agency,
        latitude: num(p.fac_lat),
        longitude: num(p.fac_long),
        attributes: {
          source: 'EPA ECHO CWA Facilities',
          county: p.cwp_county,
          master_general_permit: p.master_external_permit_nmbr,
          storm_water_area_semantics: 'EPA ECHO field is estimated area exposed to stormwater in acres when populated; documentary permit data only.'
        }
      })
    }
    if (fs.length < 2000) break
    offset += fs.length
  }
  return rows.filter(r => Number.isFinite(r.latitude) && Number.isFinite(r.longitude))
}

async function ohioRows() {
  const rows: any[] = []
  let offset = 0
  for (let page = 0; page < 20; page++) {
    const u = new URL(OH)
    u.searchParams.set('where', "facility_state='OH'")
    u.searchParams.set('geometry', BBOX)
    u.searchParams.set('geometryType', 'esriGeometryEnvelope')
    u.searchParams.set('inSR', '4326')
    u.searchParams.set('spatialRel', 'esriSpatialRelIntersects')
    u.searchParams.set('outFields', 'ohio_epa_no,permitdetail,facility_name,facility_state,facility_county,effective_date,issue_date,total_acres,facility_latitude,facility_longitude,permit_status,expiration_date,us_epa_no,permit_category,permit_type')
    u.searchParams.set('returnGeometry', 'false')
    u.searchParams.set('resultOffset', String(offset))
    u.searchParams.set('resultRecordCount', '4000')
    u.searchParams.set('f', 'json')
    const j = await getJson(u.toString())
    const fs = j.features ?? []
    for (const f of fs) {
      const p = f.attributes ?? {}
      if (!p.ohio_epa_no) continue
      rows.push({
        ohio_epa_no: String(p.ohio_epa_no),
        facility_name: p.facility_name,
        us_epa_no: p.us_epa_no,
        permit_status: p.permit_status,
        permit_type: p.permit_type,
        permit_category: p.permit_category,
        permitdetail: p.permitdetail,
        issue_date: date(p.issue_date),
        effective_date: date(p.effective_date),
        expiration_date: date(p.expiration_date),
        total_acres: num(p.total_acres),
        county_name: p.facility_county,
        latitude: num(p.facility_latitude),
        longitude: num(p.facility_longitude)
      })
    }
    if (fs.length < 4000) break
    offset += fs.length
  }
  return rows.filter(r => Number.isFinite(r.latitude) && Number.isFinite(r.longitude))
}

async function ingestChunks(rpc: string, rows: any[], seenAt: string) {
  let stored = 0
  let writtenChunks = 0
  for (const part of chunks(rows)) {
    const result = await sb.rpc(rpc, { p_rows: part, p_seen_at: seenAt })
    if (result.error) throw new Error(`${rpc} chunk ${writtenChunks + 1}: ${result.error.message}`)
    stored += Number(result.data ?? 0)
    writtenChunks++
  }
  return { stored, writtenChunks }
}

async function finalize(sourceSlug: string, seenAt: string) {
  const result = await sb.rpc('internal_finalize_construction_stormwater_snapshot', {
    p_source_slug: sourceSlug,
    p_seen_at: seenAt
  })
  if (result.error) throw new Error(`finalize ${sourceSlug}: ${result.error.message}`)
  return Number(result.data ?? 0)
}

Deno.serve(withCollectorRun('collect-construction-stormwater', async req => {
  try {
    if (req.method !== 'POST') return Response.json({ error: 'POST required' }, { status: 405 })
    if (!await authorized(req)) return Response.json({ error: 'unauthorized' }, { status: 401 })

    const [echo, oh] = await Promise.all([echoRows(), ohioRows()])
    const seenAt = new Date().toISOString()

    const echoWrite = await ingestChunks('internal_ingest_construction_stormwater_evidence_chunk', echo, seenAt)
    const echoAbsent = await finalize('epa-echo-cwa-facilities', seenAt)

    const ohioWrite = await ingestChunks('internal_ingest_ohio_construction_stormwater_chunk', oh, seenAt)
    const ohioAbsent = await finalize('ohio-epa-npdes-construction', seenAt)

    return Response.json({
      ok: true,
      targets: echo.length + oh.length,
      stored: echoWrite.stored + ohioWrite.stored,
      echo_rows: echo.length,
      ohio_rows: oh.length,
      stored_echo: echoWrite.stored,
      stored_ohio: ohioWrite.stored,
      echo_chunks: echoWrite.writtenChunks,
      ohio_chunks: ohioWrite.writtenChunks,
      echo_marked_absent: echoAbsent,
      ohio_marked_absent: ohioAbsent,
      snapshot_seen_at: seenAt,
      by_state: {
        KY: echo.filter(x => x.state_code === 'KY').length,
        IN: echo.filter(x => x.state_code === 'IN').length,
        OH: oh.length
      },
      ohio_with_acres: oh.filter(x => x.total_acres != null).length
    })
  } catch (e) {
    console.error(e)
    return Response.json({ ok: false, error: e instanceof Error ? e.message : String(e) }, { status: 500 })
  }
}))
