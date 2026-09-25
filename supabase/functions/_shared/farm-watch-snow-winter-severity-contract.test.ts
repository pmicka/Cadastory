import {
  FARM_WATCH_SNOW_WINTER_SEVERITY_PRODUCT,
  minnesotaWsiDailyPoints,
  validateFarmWatchSnowWinterSeverityContext,
} from './farm-watch-snow-winter-severity-contract.ts'

function assert(condition: unknown, message = 'assertion failed'): asserts condition {
  if (!condition) throw new Error(message)
}

function baseContext(): any {
  return {
    schema: FARM_WATCH_SNOW_WINTER_SEVERITY_PRODUCT.outputSchemaVersion,
    method: FARM_WATCH_SNOW_WINTER_SEVERITY_PRODUCT.algorithmVersion,
    evidence_state: 'proxy',
    latest_complete_daily_context: null,
    minnesota_wsi_context: {
      status: 'not_applicable',
      thresholds: {
        snow_depth_cm: 38,
        minimum_temperature_c: -17.7,
      },
    },
    deer_inference_performed: false,
    coefficient_transfer_performed: false,
    severity_category_assigned: false,
  }
}

Deno.test('Minnesota WSI arithmetic preserves the source thresholds exactly', () => {
  assert(minnesotaWsiDailyPoints(37.9, -17.6) === 0)
  assert(minnesotaWsiDailyPoints(38, -17.6) === 1)
  assert(minnesotaWsiDailyPoints(37.9, -17.7) === 1)
  assert(minnesotaWsiDailyPoints(38, -17.7) === 2)
})

Deno.test('M08 contract rejects biological/scoring promotion', () => {
  const value = baseContext()
  assert(validateFarmWatchSnowWinterSeverityContext(value))
  assert(!validateFarmWatchSnowWinterSeverityContext({ ...value, deer_inference_performed: true }))
  assert(!validateFarmWatchSnowWinterSeverityContext({ ...value, coefficient_transfer_performed: true }))
  assert(!validateFarmWatchSnowWinterSeverityContext({ ...value, severity_category_assigned: true }))
  assert(!validateFarmWatchSnowWinterSeverityContext({ ...value, evidence_state: 'available' }))
})

Deno.test('complete daily context requires at least 75 percent HRRR hourly coverage', () => {
  const value = baseContext()
  value.latest_complete_daily_context = {
    snow_depth_cm: 38,
    minimum_daily_temperature_c: -17.7,
    temperature_hour_count: 18,
    temperature_expected_hours: 24,
    temperature_coverage_ratio: 0.75,
    minnesota_wsi_daily_points: 2,
  }
  assert(validateFarmWatchSnowWinterSeverityContext(value))
  value.latest_complete_daily_context.temperature_coverage_ratio = 0.7499
  assert(!validateFarmWatchSnowWinterSeverityContext(value))
})
