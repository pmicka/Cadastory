import 'jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.115.0'
import {
  FARM_WATCH_HLS_FIELD_PRODUCT,
  validateFarmWatchHlsCompletion,
} from '../_shared/farm-watch-hls-field-observation-contract.ts'
import {
  FARM_WATCH_GITHUB_OIDC_AUDIENCE,
  verifyFarmWatchGitHubActionsOidc,
} from '../_shared/github-actions-oidc.ts'

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

function bearer(req: Request) {
  const match = /^Bearer\s+(.+)$/i.exec(req.headers.get('authorization') || '')
  return match?.[1]?.trim() || null
}

function boundedSlug(value: unknown) {
  const slug = String(value || '').trim().toLowerCase()
  return /^[a-z0-9][a-z0-9-]{0,79}$/.test(slug) ? slug : null
}

function boundedDate(value: unknown) {
  const text = String(value || '')
  if (!/^\d{4}-\d{2}-\d{2}$/.test(text)) return null
  const date = new Date(text + 'T00:00:00Z')
  return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === text
    ? text
    : null
}

function validUuid(value: unknown) {
  const text = String(value || '')
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(text)
    ? text
    : null
}

function boundedDetails(value: unknown) {
  const details = value && typeof value === 'object' ? value : {}
  const encoded = JSON.stringify(details)
  if (encoded.length > 500_000) throw new Error('collection details payload is too large')
  return details
}

async function finishRun(args: {
  runId: string
  status: string
  targetFields: number
  discoveredItems: number
  completeAssetItems: number
  sampledItems: number
  storedObservations: number
  currentQualityFields: number
  details: unknown
}) {
  const { data, error } = await admin.rpc(
    'farm_watch_finish_field_vegetation_collection_v1_internal',
    {
      p_run_id: args.runId,
      p_status: args.status,
      p_target_fields: args.targetFields,
      p_discovered_items: args.discoveredItems,
      p_complete_asset_items: args.completeAssetItems,
      p_sampled_items: args.sampledItems,
      p_stored_observations: args.storedObservations,
      p_current_quality_fields: args.currentQualityFields,
      p_details: boundedDetails(args.details),
    },
  )
  if (error) throw new Error('HLS collection run completion failed: ' + error.message)
  return data
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return json({ error: 'not found' }, 404)

  const token = bearer(req)
  if (!token) return json({ error: 'not found' }, 404)

  let identity: any
  try {
    identity = await verifyFarmWatchGitHubActionsOidc(token)
  } catch (error) {
    console.error('Farm Watch HLS worker OIDC rejected', error)
    return json({ error: 'not found' }, 404)
  }

  let body: any
  try {
    body = await req.json()
  } catch {
    return json({ error: 'invalid request' }, 400)
  }

  const operation = String(body?.operation || '')
  const property = boundedSlug(body?.property)
  const asOfDate = boundedDate(body?.as_of_date)
  if (!property || !asOfDate) return json({ error: 'invalid request' }, 400)

  let runId: string | null = validUuid(body?.run_id)
  try {
    if (operation === 'claim') {
      const { data: run, error: runError } = await admin.rpc(
        'farm_watch_start_field_vegetation_collection_v1_internal',
        {
          p_slug: property,
          p_as_of_date: asOfDate,
          p_workflow: identity,
        },
      )
      if (runError || !run?.run_id) {
        throw new Error('HLS collection run start failed' + (runError?.message ? ': ' + runError.message : ''))
      }
      runId = String(run.run_id)

      const { data: targets, error: targetsError } = await admin.rpc(
        'farm_watch_get_field_phenology_targets_v1_internal',
        {
          p_slug: property,
          p_as_of_date: asOfDate,
          p_limit: 1000,
        },
      )
      if (targetsError) throw new Error('HLS field targets unavailable: ' + targetsError.message)

      const targetRows = Array.isArray(targets) ? targets : []
      return json({
        status: 'processing',
        run_id: runId,
        property,
        as_of_date: asOfDate,
        targets: targetRows,
        contract: {
          algorithm_version: FARM_WATCH_HLS_FIELD_PRODUCT.algorithmVersion,
          output_schema_version: FARM_WATCH_HLS_FIELD_PRODUCT.outputSchemaVersion,
          evidence_class: FARM_WATCH_HLS_FIELD_PRODUCT.evidenceClass,
          distribution_provider: FARM_WATCH_HLS_FIELD_PRODUCT.distributionProvider,
          distribution_endpoint: FARM_WATCH_HLS_FIELD_PRODUCT.distributionEndpoint,
          source_authority: FARM_WATCH_HLS_FIELD_PRODUCT.sourceAuthority,
          lookback_days: FARM_WATCH_HLS_FIELD_PRODUCT.lookbackDays,
          freshness_days: FARM_WATCH_HLS_FIELD_PRODUCT.freshnessDays,
          minimum_valid_fraction: FARM_WATCH_HLS_FIELD_PRODUCT.minimumValidFraction,
          collections: FARM_WATCH_HLS_FIELD_PRODUCT.collections,
        },
        oidc_audience: FARM_WATCH_GITHUB_OIDC_AUDIENCE,
      })
    }

    if (!runId) return json({ error: 'invalid run identity' }, 400)

    if (operation === 'complete') {
      if (!validateFarmWatchHlsCompletion(body)) {
        return json({ error: 'invalid HLS completion payload' }, 400)
      }
      if (body.observations.length > 5000) {
        return json({ error: 'too many HLS observations in one completion' }, 400)
      }

      let stored = 0
      if (body.observations.length) {
        const { data, error } = await admin.rpc(
          'farm_watch_store_field_vegetation_observations_v1_internal',
          { p_rows: body.observations },
        )
        if (error) throw new Error('HLS field observation storage failed: ' + error.message)
        stored = Number(data ?? 0)
      }

      const { data: refreshed, error: refreshError } = await admin.rpc(
        'farm_watch_refresh_field_phenology_v1_internal',
        { p_slug: property, p_as_of_date: asOfDate },
      )
      if (refreshError) throw new Error('field phenology refresh failed: ' + refreshError.message)

      const completed = await finishRun({
        runId,
        status: String(body.status),
        targetFields: Number(body.target_fields),
        discoveredItems: Number(body.discovered_items),
        completeAssetItems: Number(body.complete_asset_items),
        sampledItems: Number(body.sampled_items),
        storedObservations: stored,
        currentQualityFields: Number(body.current_quality_fields),
        details: {
          ...(body.details || {}),
          worker_contract: {
            algorithm_version: FARM_WATCH_HLS_FIELD_PRODUCT.algorithmVersion,
            output_schema_version: FARM_WATCH_HLS_FIELD_PRODUCT.outputSchemaVersion,
            distribution_provider: FARM_WATCH_HLS_FIELD_PRODUCT.distributionProvider,
            source_authority: FARM_WATCH_HLS_FIELD_PRODUCT.sourceAuthority,
          },
          workflow: identity,
        },
      })

      return json({
        ok: true,
        collection: completed,
        stored_observations: stored,
        field_phenology: refreshed,
      })
    }

    if (operation === 'fail') {
      const status = String(body?.status || 'processing_error')
      if (!['catalog_incomplete','download_error','processing_error'].includes(status)) {
        return json({ error: 'invalid failure status' }, 400)
      }
      const completed = await finishRun({
        runId,
        status,
        targetFields: Math.max(0, Number(body?.target_fields || 0)),
        discoveredItems: Math.max(0, Number(body?.discovered_items || 0)),
        completeAssetItems: Math.max(0, Number(body?.complete_asset_items || 0)),
        sampledItems: Math.max(0, Number(body?.sampled_items || 0)),
        storedObservations: 0,
        currentQualityFields: 0,
        details: {
          ...(body?.details || {}),
          error: String(body?.error || 'HLS field materialization failed').slice(0, 4000),
          workflow: identity,
        },
      })
      return json({ ok: true, collection: completed })
    }

    return json({ error: 'invalid request' }, 400)
  } catch (error) {
    console.error('Farm Watch HLS field worker failed', operation, error)
    if (runId && operation === 'claim') {
      try {
        await finishRun({
          runId,
          status: 'processing_error',
          targetFields: 0,
          discoveredItems: 0,
          completeAssetItems: 0,
          sampledItems: 0,
          storedObservations: 0,
          currentQualityFields: 0,
          details: {
            error: error instanceof Error ? error.message : String(error),
            failure_stage: 'claim',
            workflow: identity,
          },
        })
      } catch (finishError) {
        console.error('Farm Watch HLS failed to close claim run', finishError)
      }
    }
    return json({
      error: 'worker operation failed',
      detail: error instanceof Error ? error.message : String(error),
    }, 503)
  }
})
