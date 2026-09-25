import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.57.4'
import { withCollectorRun } from '../_shared/collector-runtime.ts'

const LAYER_URL =
  'https://services2.arcgis.com/FiaPA4ga0iQKduv3/arcgis/rest/services/USA_Structures_View/FeatureServer/0'

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

function epochIso(value: unknown): string | null {
  const numeric = Number(value)
  if (!Number.isFinite(numeric) || numeric <= 0) return null
  const date = new Date(numeric)
  return Number.isNaN(date.getTime()) ? null : date.toISOString()
}

function coverage(nonNull: unknown, total: number) {
  const count = Number(nonNull)
  if (!Number.isFinite(count) || count < 0) {
    throw new Error('invalid FEMA USA Structures completeness count')
  }
  return {
    non_null_count: count,
    coverage_fraction: total > 0 ? count / total : null,
  }
}

function sourceProfile(metadata: any, attributes: any, total: number, checkedAt: string) {
  return {
    source_slug: 'fema-usa-structures-current',
    source_name: 'FEMA USA Structures View',
    source_checked_at: checkedAt,
    service: {
      service_item_id: String(metadata?.serviceItemId || ''),
      is_view: metadata?.isView === true,
      has_static_data: metadata?.hasStaticData === true,
      max_record_count: Number(metadata?.maxRecordCount || 0),
      last_edit_at: epochIso(metadata?.editingInfo?.lastEditDate),
      schema_last_edit_at: epochIso(metadata?.editingInfo?.schemaLastEditDate),
      data_last_edit_at: epochIso(metadata?.editingInfo?.dataLastEditDate),
    },
    local_feature_vintage: {
      production_date: {
        min: epochIso(attributes?.prod_date_min),
        max: epochIso(attributes?.prod_date_max),
        ...coverage(attributes?.prod_date_count, total),
      },
      imagery_date: {
        min: epochIso(attributes?.image_date_min),
        max: epochIso(attributes?.image_date_max),
        ...coverage(attributes?.image_date_count, total),
      },
    },
    completeness: {
      queried_feature_count: total,
      inventory_design: 'structures greater than 450 square feet in the United States and its territories',
      known_minimum_structure_area_sqft: 450,
      spatial_completeness_status: 'not_quantified_by_source',
      query_method: 'ArcGIS aggregate statistics over exact 10.36 km2 analytical window',
      transfer_limit_risk: 'none_for_aggregate_statistics',
      attribute_coverage: {
        source_attribution: coverage(attributes?.source_count, total),
        validation_method: coverage(attributes?.val_method_count, total),
        uuid: coverage(attributes?.uuid_count, total),
      },
      interpretation: 'Field coverage and source vintage are measured for returned features; they do not establish that every real-world structure above the source threshold is present.',
    },
  }
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
      throw new Error('FEMA USA Structures metadata returned ' + metadataResponse.status)
    }
    const metadataText = await metadataResponse.text()
    const metadata = JSON.parse(metadataText)
    if (metadata?.type !== 'Feature Layer' || metadata?.geometryType !== 'esriGeometryPolygon') {
      throw new Error('FEMA USA Structures source metadata is not the expected polygon feature layer')
    }
    const metadataSha256 = await sha256Hex(metadataText)

    const outStatistics = [
      { statisticType: 'count', onStatisticField: 'OBJECTID', outStatisticFieldName: 'total_count' },
      { statisticType: 'count', onStatisticField: 'PROD_DATE', outStatisticFieldName: 'prod_date_count' },
      { statisticType: 'min', onStatisticField: 'PROD_DATE', outStatisticFieldName: 'prod_date_min' },
      { statisticType: 'max', onStatisticField: 'PROD_DATE', outStatisticFieldName: 'prod_date_max' },
      { statisticType: 'count', onStatisticField: 'IMAGE_DATE', outStatisticFieldName: 'image_date_count' },
      { statisticType: 'min', onStatisticField: 'IMAGE_DATE', outStatisticFieldName: 'image_date_min' },
      { statisticType: 'max', onStatisticField: 'IMAGE_DATE', outStatisticFieldName: 'image_date_max' },
      { statisticType: 'count', onStatisticField: 'SOURCE', outStatisticFieldName: 'source_count' },
      { statisticType: 'count', onStatisticField: 'VAL_METHOD', outStatisticFieldName: 'val_method_count' },
      { statisticType: 'count', onStatisticField: 'UUID', outStatisticFieldName: 'uuid_count' },
    ]
    const params = new URLSearchParams({
      where: '1=1',
      geometry: envelope.map((value: unknown) => Number(value)).join(','),
      geometryType: 'esriGeometryEnvelope',
      inSR: String(query.in_sr || 32616),
      spatialRel: 'esriSpatialRelIntersects',
      returnGeometry: 'false',
      outStatistics: JSON.stringify(outStatistics),
      f: 'json',
    })

    const statsResponse = await fetch(LAYER_URL + '/query?' + params.toString(), {
      headers: {
        accept: 'application/json',
        'user-agent': 'Scout-by-Cadastory/1.0',
      },
      signal: AbortSignal.timeout(30_000),
    })
    if (!statsResponse.ok) {
      throw new Error('FEMA USA Structures statistics query returned ' + statsResponse.status)
    }
    const statsPayload = await statsResponse.json()
    if (statsPayload?.error) {
      throw new Error(
        'FEMA USA Structures statistics query failed: ' +
          JSON.stringify(statsPayload.error).slice(0, 500),
      )
    }
    const attributes = statsPayload?.features?.[0]?.attributes
    const buildingCount = Number(attributes?.total_count)
    if (!Number.isInteger(buildingCount) || buildingCount < 0) {
      throw new Error(
        'FEMA USA Structures statistics query did not return a valid count: ' +
          JSON.stringify(statsPayload).slice(0, 500),
      )
    }

    const checkedAt = new Date().toISOString()
    const profile = sourceProfile(metadata, attributes, buildingCount, checkedAt)
    const stored = await admin.rpc(
      'farm_watch_record_human_footprint_context_v2_internal',
      {
        p_slug: property,
        p_building_count: buildingCount,
        p_building_metadata_sha256: metadataSha256,
        p_building_source_profile: profile,
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
      building_source_profile: profile,
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
