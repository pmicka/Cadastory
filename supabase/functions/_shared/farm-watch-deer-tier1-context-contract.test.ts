import {
  FARM_WATCH_DEER_TIER1_CONTEXT_PRODUCT,
  validateFarmWatchExtremeWeatherEventContext,
  validateFarmWatchHumanFootprintContext,
  validateFarmWatchMultiscaleCoverContext,
} from './farm-watch-deer-tier1-context-contract.ts'

function assert(condition: unknown, message = 'assertion failed'): asserts condition {
  if (!condition) throw new Error(message)
}

const sha = 'a'.repeat(64)

Deno.test('human-footprint context preserves Delisle building area and Stephens road radii', () => {
  const value = {
    schema: FARM_WATCH_DEER_TIER1_CONTEXT_PRODUCT.humanFootprint.outputSchemaVersion,
    method: FARM_WATCH_DEER_TIER1_CONTEXT_PRODUCT.humanFootprint.algorithmVersion,
    evidence_class: 'deterministic_derived',
    building_development: {
      study_area_km2: 10.36,
      building_count: 12,
      building_density_per_km2: 12 / 10.36,
    },
    road_context: {
      study_sampling_radii_m: [30, 90, 270],
      scopes: {
        local_500m: { road_length_m: 100 },
        landscape_1500m: { road_length_m: 500 },
      },
    },
    source_fingerprint_sha256: sha,
    deer_inference_performed: false,
  }
  assert(validateFarmWatchHumanFootprintContext(value))
})

Deno.test('multiscale context requires exact 1 and 9 km2 windows', () => {
  const value = {
    schema: FARM_WATCH_DEER_TIER1_CONTEXT_PRODUCT.multiscaleCover.outputSchemaVersion,
    method: FARM_WATCH_DEER_TIER1_CONTEXT_PRODUCT.multiscaleCover.algorithmVersion,
    evidence_class: 'deterministic_derived',
    windows: [
      { area_km2: 1, geometry_basis: 'property_centered_square' },
      { area_km2: 9, geometry_basis: 'property_centered_square' },
    ],
    deer_inference_performed: false,
  }
  assert(validateFarmWatchMultiscaleCoverContext(value))
})

Deno.test('extreme-weather gate rejects ordinary weather and accepts explicit tropical alert types', () => {
  const base = {
    schema: FARM_WATCH_DEER_TIER1_CONTEXT_PRODUCT.extremeWeather.outputSchemaVersion,
    method: FARM_WATCH_DEER_TIER1_CONTEXT_PRODUCT.extremeWeather.algorithmVersion,
    evidence_class: 'authoritative_event_context',
    ordinary_weather_activation_allowed: false,
    deer_inference_performed: false,
  }

  assert(validateFarmWatchExtremeWeatherEventContext({
    ...base,
    event_active: false,
    events: [],
  }))

  assert(validateFarmWatchExtremeWeatherEventContext({
    ...base,
    event_active: true,
    events: [{ event_type: 'Hurricane Warning' }],
  }))

  assert(!validateFarmWatchExtremeWeatherEventContext({
    ...base,
    event_active: true,
    events: [{ event_type: 'Severe Thunderstorm Warning' }],
  }))
})
