export const FARM_WATCH_SNOW_WINTER_SEVERITY_PRODUCT = Object.freeze({
  key: 'snow-winter-severity-context',
  algorithmVersion: 'delgiudice-daily-snow-temperature-context-v1',
  outputSchemaVersion: 'snow-winter-severity-context-v1',
  evidenceState: 'proxy',
  snowSourceSlug: 'noaa-nohrsc-national-snow-analysis',
  temperatureSourceSlug: 'noaa-hrrr-conus-3km',
  snowThresholdCm: 38,
  minimumTemperatureThresholdC: -17.7,
  minimumTemperatureCoverageRatio: 0.75,
  studyWinterStart: '11-01',
  studyWinterEnd: '05-14',
  sourceWsiMonths: Object.freeze([11,12,1,2,3,4,5] as const),
})

export function minnesotaWsiDailyPoints(snowDepthCm: number, minimumTemperatureC: number) {
  if (!Number.isFinite(snowDepthCm) || snowDepthCm < 0 || !Number.isFinite(minimumTemperatureC)) {
    throw new Error('invalid physical winter inputs')
  }
  return (snowDepthCm >= FARM_WATCH_SNOW_WINTER_SEVERITY_PRODUCT.snowThresholdCm ? 1 : 0) +
    (minimumTemperatureC <= FARM_WATCH_SNOW_WINTER_SEVERITY_PRODUCT.minimumTemperatureThresholdC ? 1 : 0)
}

export function validateFarmWatchSnowWinterSeverityContext(value: any) {
  const p = FARM_WATCH_SNOW_WINTER_SEVERITY_PRODUCT
  if (
    value?.schema !== p.outputSchemaVersion ||
    value?.method !== p.algorithmVersion ||
    value?.evidence_state !== p.evidenceState ||
    value?.deer_inference_performed !== false ||
    value?.coefficient_transfer_performed !== false ||
    value?.severity_category_assigned !== false
  ) return false

  const wsi = value?.minnesota_wsi_context
  if (!wsi || !['not_applicable','pending','complete','partial','unavailable'].includes(String(wsi.status || ''))) {
    return false
  }
  if (
    Number(wsi?.thresholds?.snow_depth_cm) !== p.snowThresholdCm ||
    Number(wsi?.thresholds?.minimum_temperature_c) !== p.minimumTemperatureThresholdC
  ) return false

  const daily = value?.latest_complete_daily_context
  if (daily != null) {
    if (
      !Number.isFinite(Number(daily.snow_depth_cm)) ||
      Number(daily.snow_depth_cm) < 0 ||
      !Number.isFinite(Number(daily.minimum_daily_temperature_c)) ||
      !Number.isInteger(Number(daily.temperature_hour_count)) ||
      !Number.isInteger(Number(daily.temperature_expected_hours)) ||
      Number(daily.temperature_expected_hours) < 23 ||
      Number(daily.temperature_expected_hours) > 25 ||
      !Number.isFinite(Number(daily.temperature_coverage_ratio)) ||
      Number(daily.temperature_coverage_ratio) < p.minimumTemperatureCoverageRatio ||
      Number(daily.minnesota_wsi_daily_points) !== minnesotaWsiDailyPoints(
        Number(daily.snow_depth_cm),
        Number(daily.minimum_daily_temperature_c),
      )
    ) return false
  }

  return true
}
