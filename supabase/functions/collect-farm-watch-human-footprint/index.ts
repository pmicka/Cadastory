import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.57.4'
import { withCollectorRun } from '../_shared/collector-runtime.ts'

const LAYER_URL =
  'https://kygisserver.ky.gov/arcgis/rest/services/WGS84WM_Services/Ky_ORNL_Building_Footprints_WGS84WM/MapServer/0'

function serviceKey(): string {
  try {
    const keys = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') || '{}')
    if (typeof keys.default === 'string' && keys.default) return keys.default
  } catch { /* legacy fallback */ }
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!key) throw new Error('Farm Watch human-footprint service credential is unavailable')
  return key
}

const admin: any = createClient(Deno.env.get('SUPABASE_URL')!, serviceKey(), {
  auth: { persistSession: false, autoRefreshToken: false },
})

async function sha256Hex(value: string) {
  const bytes = new TextEncoder().encode(value)
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))
  return [...digest].map((byte) => byte.toString(16).padStart(2, '0')).join('')
}

function propertySlug(value: unknown) {
  const slug = String(value || 'validation-property-01')
  if (!/^[a-z0-9][a-z0-9-]{0,79}$/.test(slug)) {
    throw new Error('invalid Farm Watch property slug')
  }
  return slug
}

Deno.serve(withCollectorRun('collect-farm-watch-human-footprint', async (req) => {
  try {
    const body = await req.json().catch(() => ({}))
    const property = propertySlug(body?.property)

    const queryResult = await admin.rpc(
      'farm_watch_get_human_footprint_query_v1_internal',
      { p_slug: property },
    )
    if (queryResult.error) throw new Error(queryResult.error.message)
    if (queryResult.data?.status !== 'available') {
      return Response.json({
        ok: true,
        outcome: 'no_work',
        targets: 0,
        stored: 0,
        property,
        status: queryResult.data?.status || 'unavailable',
      })
    }

    const query = queryResult.data.building_query
    const envelope = query?.envelope
    if (!Array.isArray(envelope) || envelope.length !== 4) {
      throw new Error('building query envelope is unavailable')
    }

    const metadataResponse = await fetch(LAYER_URL + '?f=json', {
      headers: {
        accept: 'application/json',
        'user-agent': 'Scout-by-Cadastory/1.0',
      },
      signal: AbortSignal.timeout(20_000),
    })
    if (!metadataResponse.ok) {
      throw new Error('Kentucky building metadata returned ' + metadataResponse.status)
    }
    const metadataText = await metadataResponse.text()
    const metadata = JSON.parse(metadataText)
    if (metadata?.type !== 'Feature Layer' || metadata?.geometryType !== 'esriGeometryPolygon') {
      throw new Error('Kentucky building source metadata is not the expected polygon feature layer')
    }
    const metadataSha256 = await sha256Hex(metadataText)

    const params = new URLSearchParams({
      where: '1=1',
      geometry: envelope.map((value: unknown) => Number(value)).join(','),
      geometryType: 'esriGeometryEnvelope',
      inSR: String(query.in_sr || 32616),
      spatialRel: 'esriSpatialRelIntersects',
      returnCountOnly: 'true',
      f: 'json',
    })

    const countResponse = await fetch(LAYER_URL + '/query?' + params.toString(), {
      headers: {
        accept: 'application/json',
        'user-agent': 'Scout-by-Cadastory/1.0',
      },
      signal: AbortSignal.timeout(30_000),
    })
    if (!countResponse.ok) {
      throw new Error('Kentucky building count query returned ' + countResponse.status)
    }
    const countPayload = await countResponse.json()
    const buildingCount = Number(countPayload?.count)
    if (!Number.isInteger(buildingCount) || buildingCount < 0) {
      throw new Error(
        'Kentucky building count query did not return a valid count: ' +
          JSON.stringify(countPayload).slice(0, 300),
      )
    }

    const checkedAt = new Date().toISOString()
    const stored = await admin.rpc(
      'farm_watch_record_human_footprint_context_v1_internal',
      {
        p_slug: property,
        p_building_count: buildingCount,
        p_building_metadata_sha256: metadataSha256,
        p_building_checked_at: checkedAt,
      },
    )
    if (stored.error) throw new Error(stored.error.message)

    return Response.json({
      ok: true,
      targets: 1,
      stored: 1,
      property,
      building_count: buildingCount,
      study_area_km2: Number(query.area_km2),
      context_status: stored.data?.status || 'unknown',
      checked_at: checkedAt,
      valid_at: checkedAt,
      building_metadata_sha256: metadataSha256,
    })
  } catch (error) {
    console.error(
      'Farm Watch human-footprint collection failed',
      error instanceof Error ? error.message : error,
    )
    return Response.json(
      { ok: false, error: error instanceof Error ? error.message : String(error) },
      { status: 500 },
    )
  }
}))
