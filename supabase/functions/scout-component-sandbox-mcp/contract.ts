export const SCOUT_SANDBOX_MAX_NAMES = 2

export type ScoutSandboxOpportunity = {
  name: string
  address: string
  opportunity_tier: string
  opportunity_score: number
  confidence: number
  story_count: number
  height_m: number
  footprint_sqft: number
  glazing_status: string
  observed_at: string
  target_class: string
  target_subclass: string
  buyer_resolvability: string
  guardrail: string
}

export type ScoutSandboxPolygonGeometry = {
  type: 'Polygon'
  coordinates: number[][][]
}

export type ScoutSandboxSingleSiteMap = {
  contract_version: 'single_site_map_v1'
  opportunity_type: 'premium_exterior'
  opportunity_id: string
  name: string
  address: string
  site_point: {
    lon: number
    lat: number
    source: 'premium_exterior_target_geocode'
    method: string
  }
  footprint: {
    geometry: ScoutSandboxPolygonGeometry
    bounds: {
      west: number
      south: number
      east: number
      north: number
    }
    footprint_sqft: number
    source: {
      slug: string
      name: string
      native_id: string
      image_date: string
      validation_method: string
    }
  }
  linkage: {
    status: 'reconciled_existing_evidence'
    basis: string
    guardrail: string
    target_to_footprint_m: number
    stored_match_distance_m: number
  }
}

export type ScoutSandboxWaterTankMap = {
  contract_version: 'water_tank_single_site_map_v1'
  opportunity_type: 'water_tank'
  tank_id: string
  candidate_key: string
  name: string
  system_name: string
  site_point: {
    lon: number
    lat: number
    source: 'kentucky_wris_water_tank'
    source_slug: 'ky-kia-water-tanks'
    source_name: string
    source_authority: string
    source_native_id: string
    wris_fid: string
    pwsid: string
    retrieved_at: string
  }
  asset: {
    tank_type: 'ELEVATED'
    capacity_gallons: number
    construction_date: string | null
    last_cleaning_date: string | null
    last_inspection_date: string | null
    out_of_service: false
  }
  geometry: {
    morphology_class: string
    support_geometry: 'single_pedestal'
    cross_bracing_status: 'none'
    support_leg_count: number | null
    operator_assessment: 'favorable'
    operator_assessment_basis: string
    evidence_kind: 'engineering_document'
    confidence: number
    source_authority: string
    source_url: string
    observed_on: string
    media_retained: false
    guardrail: string
  }
  project_linkage: {
    project_id: string
    pnum: string
    status: 'REHAB'
    purpose: string | null
    other_purpose: string | null
    match_method: string
    match_distance_m: number
    source_modified_at: string
    guardrail: string
  }
}

export type ScoutSandboxResult = {
  surface: 'scout_component_sandbox'
  names: string[]
  opportunity: ScoutSandboxOpportunity
  map: ScoutSandboxSingleSiteMap
}

function boundedString(value: unknown, maxLength: number) {
  if (typeof value !== 'string') return null
  const text = value.trim()
  return text.length > 0 && text.length <= maxLength ? text : null
}

function boundedNullableString(value: unknown, maxLength: number) {
  return value === null ? null : boundedString(value, maxLength)
}

function boundedNumber(value: unknown, minimum: number, maximum: number) {
  return typeof value === 'number' && Number.isFinite(value) && value >= minimum && value <= maximum
    ? value
    : null
}

function boundedInteger(value: unknown, minimum: number, maximum: number) {
  const number = boundedNumber(value, minimum, maximum)
  return number !== null && Number.isInteger(number) ? number : null
}

function boundedNullableInteger(value: unknown, minimum: number, maximum: number) {
  return value === null ? null : boundedInteger(value, minimum, maximum)
}

function boundedName(value: unknown) {
  return boundedString(value, 160)
}

function boundedUuid(value: unknown) {
  const text = boundedString(value, 36)
  return text && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(text)
    ? text
    : null
}

function boundedLongitude(value: unknown) {
  return boundedNumber(value, -180, 180)
}

function boundedLatitude(value: unknown) {
  return boundedNumber(value, -90, 90)
}

function normalizePolygonGeometry(value: unknown): ScoutSandboxPolygonGeometry | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null
  const source = value as Record<string, unknown>
  if (source.type !== 'Polygon' || !Array.isArray(source.coordinates) || source.coordinates.length < 1 || source.coordinates.length > 8) return null

  const rings: number[][][] = []
  for (const ringValue of source.coordinates) {
    if (!Array.isArray(ringValue) || ringValue.length < 4 || ringValue.length > 2048) return null
    const ring: number[][] = []
    for (const positionValue of ringValue) {
      if (!Array.isArray(positionValue) || positionValue.length < 2) return null
      const lon = boundedLongitude(positionValue[0])
      const lat = boundedLatitude(positionValue[1])
      if (lon === null || lat === null) return null
      ring.push([lon, lat])
    }
    const first = ring[0]
    const last = ring[ring.length - 1]
    if (first[0] !== last[0] || first[1] !== last[1]) return null
    rings.push(ring)
  }

  return { type: 'Polygon', coordinates: rings }
}

export function normalizeScoutSandboxNames(value: unknown): string[] {
  if (!Array.isArray(value)) return []
  return value.map(boundedName).filter((name): name is string => name !== null).slice(0, SCOUT_SANDBOX_MAX_NAMES)
}

export function normalizeScoutSandboxOpportunity(value: unknown): ScoutSandboxOpportunity | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null
  const source = value as Record<string, unknown>
  const opportunity: ScoutSandboxOpportunity = {
    name: boundedString(source.name, 160) ?? '',
    address: boundedString(source.address, 240) ?? '',
    opportunity_tier: boundedString(source.opportunity_tier, 64) ?? '',
    opportunity_score: boundedInteger(source.opportunity_score, 0, 100) ?? -1,
    confidence: boundedNumber(source.confidence, 0, 1) ?? -1,
    story_count: boundedInteger(source.story_count, 0, 1000) ?? -1,
    height_m: boundedNumber(source.height_m, 0, 10000) ?? -1,
    footprint_sqft: boundedNumber(source.footprint_sqft, 0, 1_000_000_000) ?? -1,
    glazing_status: boundedString(source.glazing_status, 80) ?? '',
    observed_at: boundedString(source.observed_at, 80) ?? '',
    target_class: boundedString(source.target_class, 80) ?? '',
    target_subclass: boundedString(source.target_subclass, 80) ?? '',
    buyer_resolvability: boundedString(source.buyer_resolvability, 120) ?? '',
    guardrail: boundedString(source.guardrail, 1000) ?? '',
  }

  return opportunity.name &&
      opportunity.address &&
      opportunity.opportunity_tier &&
      opportunity.opportunity_score >= 0 &&
      opportunity.confidence >= 0 &&
      opportunity.story_count >= 0 &&
      opportunity.height_m >= 0 &&
      opportunity.footprint_sqft >= 0 &&
      opportunity.glazing_status &&
      opportunity.observed_at &&
      opportunity.target_class &&
      opportunity.target_subclass &&
      opportunity.buyer_resolvability &&
      opportunity.guardrail
    ? opportunity
    : null
}

export function normalizeScoutSandboxSingleSiteMap(value: unknown): ScoutSandboxSingleSiteMap | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null
  const source = value as Record<string, unknown>
  if (source.contract_version !== 'single_site_map_v1' || source.opportunity_type !== 'premium_exterior') return null

  const sitePointSource = source.site_point
  const footprintSource = source.footprint
  const linkageSource = source.linkage
  if (!sitePointSource || typeof sitePointSource !== 'object' || Array.isArray(sitePointSource)) return null
  if (!footprintSource || typeof footprintSource !== 'object' || Array.isArray(footprintSource)) return null
  if (!linkageSource || typeof linkageSource !== 'object' || Array.isArray(linkageSource)) return null

  const sitePoint = sitePointSource as Record<string, unknown>
  const footprint = footprintSource as Record<string, unknown>
  const linkage = linkageSource as Record<string, unknown>
  const boundsSource = footprint.bounds
  const sourceInfoSource = footprint.source
  if (!boundsSource || typeof boundsSource !== 'object' || Array.isArray(boundsSource)) return null
  if (!sourceInfoSource || typeof sourceInfoSource !== 'object' || Array.isArray(sourceInfoSource)) return null
  const bounds = boundsSource as Record<string, unknown>
  const sourceInfo = sourceInfoSource as Record<string, unknown>

  const opportunityId = boundedUuid(source.opportunity_id)
  const name = boundedString(source.name, 160)
  const address = boundedString(source.address, 240)
  const lon = boundedLongitude(sitePoint.lon)
  const lat = boundedLatitude(sitePoint.lat)
  const siteMethod = boundedString(sitePoint.method, 120)
  const geometry = normalizePolygonGeometry(footprint.geometry)
  const west = boundedLongitude(bounds.west)
  const south = boundedLatitude(bounds.south)
  const east = boundedLongitude(bounds.east)
  const north = boundedLatitude(bounds.north)
  const footprintSqft = boundedNumber(footprint.footprint_sqft, 0, 1_000_000_000)
  const sourceSlug = boundedString(sourceInfo.slug, 120)
  const sourceName = boundedString(sourceInfo.name, 240)
  const sourceNativeId = boundedString(sourceInfo.native_id, 240)
  const imageDate = boundedString(sourceInfo.image_date, 40)
  const validationMethod = boundedString(sourceInfo.validation_method, 120)
  const basis = boundedString(linkage.basis, 1000)
  const guardrail = boundedString(linkage.guardrail, 1000)
  const targetToFootprintM = boundedNumber(linkage.target_to_footprint_m, 0, 10000)
  const storedMatchDistanceM = boundedNumber(linkage.stored_match_distance_m, 0, 10000)

  if (!opportunityId || !name || !address || lon === null || lat === null || sitePoint.source !== 'premium_exterior_target_geocode' || !siteMethod) return null
  if (!geometry || west === null || south === null || east === null || north === null || west >= east || south >= north || footprintSqft === null) return null
  if (!sourceSlug || !sourceName || !sourceNativeId || !imageDate || !validationMethod) return null
  if (linkage.status !== 'reconciled_existing_evidence' || !basis || !guardrail || targetToFootprintM === null || storedMatchDistanceM === null) return null

  return {
    contract_version: 'single_site_map_v1',
    opportunity_type: 'premium_exterior',
    opportunity_id: opportunityId,
    name,
    address,
    site_point: {
      lon,
      lat,
      source: 'premium_exterior_target_geocode',
      method: siteMethod,
    },
    footprint: {
      geometry,
      bounds: { west, south, east, north },
      footprint_sqft: footprintSqft,
      source: {
        slug: sourceSlug,
        name: sourceName,
        native_id: sourceNativeId,
        image_date: imageDate,
        validation_method: validationMethod,
      },
    },
    linkage: {
      status: 'reconciled_existing_evidence',
      basis,
      guardrail,
      target_to_footprint_m: targetToFootprintM,
      stored_match_distance_m: storedMatchDistanceM,
    },
  }
}

export function normalizeScoutSandboxWaterTankMap(value: unknown): ScoutSandboxWaterTankMap | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null
  const source = value as Record<string, unknown>
  if (source.contract_version !== 'water_tank_single_site_map_v1' || source.opportunity_type !== 'water_tank') return null

  const sitePointSource = source.site_point
  const assetSource = source.asset
  const geometrySource = source.geometry
  const projectSource = source.project_linkage
  if (!sitePointSource || typeof sitePointSource !== 'object' || Array.isArray(sitePointSource)) return null
  if (!assetSource || typeof assetSource !== 'object' || Array.isArray(assetSource)) return null
  if (!geometrySource || typeof geometrySource !== 'object' || Array.isArray(geometrySource)) return null
  if (!projectSource || typeof projectSource !== 'object' || Array.isArray(projectSource)) return null

  const sitePoint = sitePointSource as Record<string, unknown>
  const asset = assetSource as Record<string, unknown>
  const geometry = geometrySource as Record<string, unknown>
  const project = projectSource as Record<string, unknown>

  const tankId = boundedUuid(source.tank_id)
  const candidateKey = boundedString(source.candidate_key, 100)
  const name = boundedString(source.name, 160)
  const systemName = boundedString(source.system_name, 200)
  const lon = boundedLongitude(sitePoint.lon)
  const lat = boundedLatitude(sitePoint.lat)
  const sourceName = boundedString(sitePoint.source_name, 240)
  const sourceAuthority = boundedString(sitePoint.source_authority, 240)
  const sourceNativeId = boundedString(sitePoint.source_native_id, 240)
  const wrisFid = boundedString(sitePoint.wris_fid, 80)
  const pwsid = boundedString(sitePoint.pwsid, 80)
  const retrievedAt = boundedString(sitePoint.retrieved_at, 80)

  const capacityGallons = boundedNumber(asset.capacity_gallons, 1, 100_000_000)
  const constructionDate = boundedNullableString(asset.construction_date, 40)
  const lastCleaningDate = boundedNullableString(asset.last_cleaning_date, 40)
  const lastInspectionDate = boundedNullableString(asset.last_inspection_date, 40)

  const morphologyClass = boundedString(geometry.morphology_class, 120)
  const supportLegCount = boundedNullableInteger(geometry.support_leg_count, 0, 64)
  const operatorAssessmentBasis = boundedString(geometry.operator_assessment_basis, 1000)
  const geometryConfidence = boundedNumber(geometry.confidence, 0, 1)
  const geometrySourceAuthority = boundedString(geometry.source_authority, 300)
  const geometrySourceUrl = boundedString(geometry.source_url, 1000)
  const geometryObservedOn = boundedString(geometry.observed_on, 40)
  const geometryGuardrail = boundedString(geometry.guardrail, 1000)

  const projectId = boundedUuid(project.project_id)
  const pnum = boundedString(project.pnum, 80)
  const projectPurpose = boundedNullableString(project.purpose, 120)
  const projectOtherPurpose = boundedNullableString(project.other_purpose, 300)
  const projectMatchMethod = boundedString(project.match_method, 120)
  const projectMatchDistanceM = boundedNumber(project.match_distance_m, 0, 10000)
  const projectSourceModifiedAt = boundedString(project.source_modified_at, 80)
  const projectGuardrail = boundedString(project.guardrail, 1000)

  if (!tankId || !candidateKey || candidateKey !== `water_tank:${tankId}` || !name || !systemName) return null
  if (lon === null || lat === null || sitePoint.source !== 'kentucky_wris_water_tank' || sitePoint.source_slug !== 'ky-kia-water-tanks') return null
  if (!sourceName || !sourceAuthority || !sourceNativeId || !wrisFid || !pwsid || !retrievedAt) return null
  if (asset.tank_type !== 'ELEVATED' || capacityGallons === null || asset.out_of_service !== false) return null
  if (!morphologyClass || geometry.support_geometry !== 'single_pedestal' || geometry.cross_bracing_status !== 'none') return null
  if (geometry.operator_assessment !== 'favorable' || !operatorAssessmentBasis || geometry.evidence_kind !== 'engineering_document') return null
  if (geometryConfidence === null || !geometrySourceAuthority || !geometrySourceUrl || !geometryObservedOn || geometry.media_retained !== false || !geometryGuardrail) return null
  if (!projectId || !pnum || project.status !== 'REHAB' || !projectMatchMethod || projectMatchDistanceM === null || !projectSourceModifiedAt || !projectGuardrail) return null

  return {
    contract_version: 'water_tank_single_site_map_v1',
    opportunity_type: 'water_tank',
    tank_id: tankId,
    candidate_key: candidateKey,
    name,
    system_name: systemName,
    site_point: {
      lon,
      lat,
      source: 'kentucky_wris_water_tank',
      source_slug: 'ky-kia-water-tanks',
      source_name: sourceName,
      source_authority: sourceAuthority,
      source_native_id: sourceNativeId,
      wris_fid: wrisFid,
      pwsid,
      retrieved_at: retrievedAt,
    },
    asset: {
      tank_type: 'ELEVATED',
      capacity_gallons: capacityGallons,
      construction_date: constructionDate,
      last_cleaning_date: lastCleaningDate,
      last_inspection_date: lastInspectionDate,
      out_of_service: false,
    },
    geometry: {
      morphology_class: morphologyClass,
      support_geometry: 'single_pedestal',
      cross_bracing_status: 'none',
      support_leg_count: supportLegCount,
      operator_assessment: 'favorable',
      operator_assessment_basis: operatorAssessmentBasis,
      evidence_kind: 'engineering_document',
      confidence: geometryConfidence,
      source_authority: geometrySourceAuthority,
      source_url: geometrySourceUrl,
      observed_on: geometryObservedOn,
      media_retained: false,
      guardrail: geometryGuardrail,
    },
    project_linkage: {
      project_id: projectId,
      pnum,
      status: 'REHAB',
      purpose: projectPurpose,
      other_purpose: projectOtherPurpose,
      match_method: projectMatchMethod,
      match_distance_m: projectMatchDistanceM,
      source_modified_at: projectSourceModifiedAt,
      guardrail: projectGuardrail,
    },
  }
}
