export const FARM_WATCH_DEER_TIER1_CONTEXT_PRODUCT = Object.freeze({
  humanFootprint: Object.freeze({
    key: 'human-footprint-context',
    algorithmVersion: 'fema-usastructures-osm-human-footprint-v1',
    outputSchemaVersion: 'human-footprint-context-v1',
    buildingStudyAreaKm2: 10.36,
    buildingSource:
      'FEMA USA Structures View',
    roadSource: 'OpenStreetMap Geofabrik Access Snapshot',
    roadStudyRadiiM: Object.freeze([30, 90, 270] as const),
  }),
  roadFocal: Object.freeze({
    key: 'road-focal-context',
    algorithmVersion: 'stephens-road-distance-focal-10m-v1',
    outputSchemaVersion: 'road-focal-context-v1',
    roadSource: 'OpenStreetMap Geofabrik Access Snapshot',
    rasterResolutionM: 10,
    focalRadiiM: Object.freeze([30, 90, 270] as const),
  }),
  multiscaleCover: Object.freeze({
    key: 'multiscale-cover-context',
    algorithmVersion: 'nagy-reis-property-centered-grid-scales-v1',
    outputSchemaVersion: 'multiscale-cover-context-v1',
    sourceStudyAreasKm2: Object.freeze([1, 9] as const),
    projectedCrs: 'EPSG:32616',
  }),
  extremeWeather: Object.freeze({
    key: 'extreme-weather-event-context',
    algorithmVersion: 'nws-tropical-extreme-event-gate-v1',
    outputSchemaVersion: 'extreme-weather-event-context-v1',
    source: 'NOAA National Weather Service Alerts API',
    qualifyingEventTypes: Object.freeze([
      'Hurricane Warning',
      'Hurricane Watch',
      'Tropical Storm Warning',
      'Tropical Storm Watch',
      'Storm Surge Warning',
      'Storm Surge Watch',
      'Extreme Wind Warning',
    ] as const),
  }),
})

function sha(value: unknown) {
  return /^[0-9a-f]{64}$/.test(String(value || ''))
}

export function validateFarmWatchHumanFootprintContext(value: any) {
  const p = FARM_WATCH_DEER_TIER1_CONTEXT_PRODUCT.humanFootprint
  if (
    value?.schema !== p.outputSchemaVersion ||
    value?.method !== p.algorithmVersion ||
    value?.evidence_class !== 'deterministic_derived' ||
    !value?.building_development ||
    !value?.road_context ||
    value?.deer_inference_performed !== false ||
    !sha(value?.source_fingerprint_sha256)
  ) return false

  const buildings = value.building_development
  if (
    Number(buildings.study_area_km2) !== p.buildingStudyAreaKm2 ||
    !Number.isInteger(Number(buildings.building_count)) ||
    Number(buildings.building_count) < 0 ||
    !Number.isFinite(Number(buildings.building_density_per_km2)) ||
    Number(buildings.building_density_per_km2) < 0
  ) return false

  const roads = value.road_context
  if (
    !Array.isArray(roads.study_sampling_radii_m) ||
    JSON.stringify(roads.study_sampling_radii_m) !==
      JSON.stringify([...p.roadStudyRadiiM]) ||
    !roads.scopes?.local_500m ||
    !roads.scopes?.landscape_1500m
  ) return false

  return true
}


export function validateFarmWatchRoadFocalContext(value: any) {
  const p = FARM_WATCH_DEER_TIER1_CONTEXT_PRODUCT.roadFocal
  if (
    value?.schema !== p.outputSchemaVersion ||
    value?.method !== p.algorithmVersion ||
    value?.evidence_class !== 'deterministic_derived' ||
    value?.source_method?.study_road_raster_resolution_m !== p.rasterResolutionM ||
    JSON.stringify(value?.source_method?.study_focal_radii_m) !== JSON.stringify([...p.focalRadiiM]) ||
    value?.deer_inference_performed !== false ||
    value?.coefficient_transfer_performed !== false ||
    !sha(value?.source_signature_sha256) ||
    !sha(value?.identity_sha256)
  ) return false

  const focal = value?.focal_mean_distance_to_road_m
  for (const radius of p.focalRadiiM) {
    const row = focal?.[`${radius}m`]
    if (!row || !Number.isFinite(Number(row.mean_m)) || Number(row.cell_count) < 1) {
      return false
    }
  }
  return true
}

export function validateFarmWatchMultiscaleCoverContext(value: any) {
  const p = FARM_WATCH_DEER_TIER1_CONTEXT_PRODUCT.multiscaleCover
  if (
    value?.schema !== p.outputSchemaVersion ||
    value?.method !== p.algorithmVersion ||
    value?.evidence_class !== 'deterministic_derived' ||
    !Array.isArray(value?.windows) ||
    value.windows.length !== 2 ||
    value?.deer_inference_performed !== false
  ) return false

  const areas = value.windows.map((row: any) => Number(row.area_km2)).sort((a: number, b: number) => a - b)
  return JSON.stringify(areas) === JSON.stringify([...p.sourceStudyAreasKm2])
}

export function validateFarmWatchExtremeWeatherEventContext(value: any) {
  const p = FARM_WATCH_DEER_TIER1_CONTEXT_PRODUCT.extremeWeather
  if (
    value?.schema !== p.outputSchemaVersion ||
    value?.method !== p.algorithmVersion ||
    value?.evidence_class !== 'authoritative_event_context' ||
    typeof value?.event_active !== 'boolean' ||
    value?.ordinary_weather_activation_allowed !== false ||
    value?.deer_inference_performed !== false
  ) return false

  if (value.event_active) {
    if (!Array.isArray(value.events) || value.events.length < 1) return false
    return value.events.every((row: any) =>
      p.qualifyingEventTypes.includes(String(row.event_type) as any)
    )
  }
  return Array.isArray(value.events) && value.events.length === 0
}
