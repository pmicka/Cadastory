import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.57.4'
import { withCollectorRun } from '../_shared/collector-runtime.ts'
import {
  HRRR_ALGORITHM_VERSION,
  HRRR_EVIDENCE_CLASS,
  HRRR_MODEL_SLUG,
  HRRR_OUTPUT_SCHEMA_VERSION,
  candidateReferenceTimes,
  hashHrrrIndex,
  hrrrAnalysisFileUrl,
  hrrrAnalysisIndexUrl,
  sampleHrrrAnalysisTargets,
  selectRequiredAnalysisRecords,
  type FarmWatchMeteorologyTarget,
} from '../_shared/farm-watch-hrrr.ts'

function serviceKey(): string {
  try {
    const keys = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') || '{}')
    if (typeof keys.default === 'string' && keys.default) return keys.default
  } catch { /* legacy fallback */ }
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!key) throw new Error('Farm Watch meteorology service credential is unavailable')
  return key
}

const admin: any = createClient(Deno.env.get('SUPABASE_URL')!, serviceKey(), {
  auth: { persistSession: false, autoRefreshToken: false },
})

function boundedSlug(value: unknown): string | null {
  if (value == null || value === '') return null
  const slug = String(value).trim().toLowerCase()
  return /^[a-z0-9][a-z0-9-]{0,79}$/.test(slug) ? slug : null
}

function boundedInteger(value: unknown, fallback: number, min: number, max: number) {
  const number = Number(value)
  if (!Number.isFinite(number)) return fallback
  return Math.max(min, Math.min(max, Math.floor(number)))
}

async function fetchIndexText(referenceTime: Date) {
  const indexUrl = hrrrAnalysisIndexUrl(referenceTime)
  const response = await fetch(indexUrl, {
    headers: {
      accept: 'text/plain,*/*',
      'user-agent': 'Scout-by-Cadastory/1.0',
    },
    signal: AbortSignal.timeout(12_000),
  })
  if (response.status === 404) return null
  if (!response.ok) throw new Error(`HRRR index returned ${response.status}`)
  const indexText = await response.text()
  const records = selectRequiredAnalysisRecords(indexText)
  return {
    referenceTime,
    fileUrl: hrrrAnalysisFileUrl(referenceTime),
    indexUrl,
    indexText,
    records,
  }
}

async function resolveLatestAnalysis(lookbackHours: number) {
  const failures: string[] = []
  for (const referenceTime of candidateReferenceTimes(new Date(), lookbackHours)) {
    try {
      const candidate = await fetchIndexText(referenceTime)
      if (candidate) return candidate
    } catch (error) {
      failures.push(
        `${referenceTime.toISOString()}: ${error instanceof Error ? error.message : String(error)}`,
      )
    }
  }
  const detail = failures.slice(0, 3).join('; ')
  throw new Error(`No complete HRRR f00 analysis found within ${lookbackHours} hours${detail ? `: ${detail}` : ''}`)
}

Deno.serve(withCollectorRun('collect-farm-watch-meteorology', async (req) => {
  try {
    const body = await req.json().catch(() => ({}))
    const requestedProperty = body?.property == null ? null : boundedSlug(body.property)
    if (body?.property != null && !requestedProperty) {
      return Response.json({ ok: false, error: 'invalid property slug' }, { status: 400 })
    }

    const limit = boundedInteger(body?.limit, 25, 1, 100)
    const lookbackHours = boundedInteger(body?.lookback_hours, 8, 1, 24)

    const { data: targetsData, error: targetError } = await admin.rpc(
      'farm_watch_get_meteorological_targets_v1_internal',
      { p_slug: requestedProperty, p_limit: limit },
    )
    if (targetError) throw new Error(targetError.message)

    const targets = (Array.isArray(targetsData) ? targetsData : []) as FarmWatchMeteorologyTarget[]
    if (!targets.length) {
      return Response.json({
        ok: true,
        outcome: 'no_work',
        targets: 0,
        stored: 0,
        property: requestedProperty,
      })
    }

    for (const target of targets) {
      if (
        !target.slug ||
        !Number.isFinite(Number(target.latitude)) ||
        !Number.isFinite(Number(target.longitude)) ||
        !/^[0-9a-f]{64}$/.test(String(target.boundary_sha256 || ''))
      ) {
        throw new Error('Farm Watch meteorological target contract is invalid')
      }
      target.latitude = Number(target.latitude)
      target.longitude = Number(target.longitude)
    }

    const source = await resolveLatestAnalysis(lookbackHours)
    const sourceIndexSha = await hashHrrrIndex(source.indexText)
    const samples = await sampleHrrrAnalysisTargets(
      fetch,
      source.fileUrl,
      source.records,
      targets,
    )

    const referenceTime = source.referenceTime.toISOString()
    const retrievedAt = new Date().toISOString()
    const rows = targets.map((target) => {
      const sample = samples[target.slug]
      if (!sample) throw new Error(`HRRR sample missing for ${target.slug}`)
      const forcing = {
        schema: HRRR_OUTPUT_SCHEMA_VERSION,
        method: HRRR_ALGORITHM_VERSION,
        evidence_class: HRRR_EVIDENCE_CLASS,
        valid_at: referenceTime,
        source_state: 'analysis',
        source: {
          authority: 'NOAA / NCEP',
          model: 'HRRR CONUS 3 km',
          model_slug: HRRR_MODEL_SLUG,
          reference_time: referenceTime,
          forecast_lead_hours: 0,
          spatial_resolution_km: 3,
          file_url: source.fileUrl,
          index_url: source.indexUrl,
          index_sha256: sourceIndexSha,
          record_ranges: sample.records,
        },
        grid: {
          target_latitude: target.latitude,
          target_longitude: target.longitude,
          sampled_latitude: sample.grid.latitude,
          sampled_longitude: sample.grid.longitude,
          distance_m: sample.grid.distance_m,
        },
        fields: sample.fields,
        scoring_performed: false,
        behavioral_inference_performed: false,
        interpretation_boundary:
          'HRRR forcing is modeled environmental state at the nearest model grid point. It is not an on-property weather-station observation and performs no deer-use, movement, bedding, habitat-quality, or management inference.',
      }

      return {
        property_slug: target.slug,
        boundary_sha256: target.boundary_sha256,
        valid_at: referenceTime,
        source_model: HRRR_MODEL_SLUG,
        source_state: 'analysis',
        reference_time: referenceTime,
        forecast_lead_hours: 0,
        forcing,
        target_latitude: target.latitude,
        target_longitude: target.longitude,
        grid_latitude: sample.grid.latitude,
        grid_longitude: sample.grid.longitude,
        grid_distance_m: sample.grid.distance_m,
        source_file_url: source.fileUrl,
        source_index_sha256: sourceIndexSha,
        source_records_sha256: sample.source_records_sha256,
        retrieved_at: retrievedAt,
      }
    })

    const { data: stored, error: storeError } = await admin.rpc(
      'farm_watch_store_meteorological_forcing_v1_internal',
      { p_rows: rows },
    )
    if (storeError) throw new Error(storeError.message)

    return Response.json({
      ok: true,
      targets: targets.length,
      stored: Number(stored ?? 0),
      property: requestedProperty,
      source_model: HRRR_MODEL_SLUG,
      source_state: 'analysis',
      reference_time: referenceTime,
      valid_at: referenceTime,
      source_index_sha256: sourceIndexSha,
      grid_distance_m: Object.fromEntries(
        rows.map((row) => [row.property_slug, row.grid_distance_m]),
      ),
    })
  } catch (error) {
    console.error('Farm Watch meteorology collection failed', error instanceof Error ? error.message : error)
    return Response.json(
      { ok: false, error: error instanceof Error ? error.message : String(error) },
      { status: 500 },
    )
  }
}))
