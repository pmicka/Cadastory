import 'jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.115.0'
import {
  FARM_WATCH_TERRAIN_LIMITATIONS,
  FARM_WATCH_TERRAIN_PRODUCT,
  FARM_WATCH_TERRAIN_SOURCE_SIGNATURE,
  terrainArtifactPath,
} from '../_shared/farm-watch-terrain-contract.ts'
import {
  buildTerrainArtifact,
  sha256Hex,
} from '../_shared/farm-watch-terrain.ts'
import {
  FARM_WATCH_LIDAR_SOURCE_LIMITATIONS,
  FARM_WATCH_LIDAR_SOURCE_PRODUCT,
  FARM_WATCH_LIDAR_SOURCE_SIGNATURE,
  buildLidarSourceArtifact,
  lidarSourceArtifactPath,
} from '../_shared/farm-watch-lidar-source.ts'
import {
  FARM_WATCH_LIDAR_PHYSICAL_PRODUCT,
  lidarPhysicalSourceSignature,
  validateLidarPhysicalArtifact,
} from '../_shared/farm-watch-lidar-physical-contract.ts'
import {
  FARM_WATCH_LEAF_OFF_PRODUCT,
  FARM_WATCH_LEAF_OFF_SOURCE_SIGNATURE,
  validateLeafOffArtifact,
} from '../_shared/farm-watch-leaf-off-contract.ts'
import {
  FARM_WATCH_STRUCTURE_SYNTHESIS_PRODUCT,
  structureSynthesisSourceSignature,
  validateStructureSynthesisArtifact,
} from '../_shared/farm-watch-structure-synthesis-contract.ts'
import {
  FARM_WATCH_LANDSCAPE_STRUCTURE_PRODUCT,
  landscapeStructureSourceSignature,
  validateLandscapeStructureArtifact,
} from '../_shared/farm-watch-landscape-structure-contract.ts'
import {
  FARM_WATCH_SPATIAL_PATTERN_LIMITATIONS,
  FARM_WATCH_SPATIAL_PATTERN_PRODUCT,
  FARM_WATCH_TERRAIN_FORM_LIMITATIONS,
  FARM_WATCH_TERRAIN_FORM_PRODUCT,
  spatialPatternArtifactPath,
  spatialPatternSourceSignature,
  terrainFormArtifactPath,
  terrainFormSourceSignature,
  validateSpatialPatternArtifact,
  validateTerrainFormArtifact,
} from '../_shared/farm-watch-neutral-primitives-contract.ts'
import {
  buildSpatialPatternArtifact,
  buildTerrainFormArtifact,
} from '../_shared/farm-watch-neutral-primitives.ts'
import {
  FARM_WATCH_SOLAR_EXPOSURE_LIMITATIONS,
  FARM_WATCH_SOLAR_EXPOSURE_PRODUCT,
  FARM_WATCH_SOLAR_TERRAIN_LIMITATIONS,
  FARM_WATCH_SOLAR_TERRAIN_PRODUCT,
  requireSolarDate,
  solarExposureArtifactPath,
  solarExposureSourceSignature,
  solarTerrainArtifactPath,
  solarTerrainSourceSignature,
  validateSolarExposureArtifact,
  validateSolarTerrainArtifact,
} from '../_shared/farm-watch-solar-exposure-contract.ts'
import {
  buildSolarExposureArtifact,
  buildSolarTerrainArtifact,
} from '../_shared/farm-watch-solar-exposure.ts'
import {
  FARM_WATCH_THERMAL_EXPOSURE_LIMITATIONS,
  FARM_WATCH_THERMAL_EXPOSURE_PRODUCT,
  requireThermalValidAt,
  thermalExposureArtifactPath,
  thermalExposureSourceSignature,
  validateThermalExposureArtifact,
} from '../_shared/farm-watch-thermal-exposure-contract.ts'
import {
  buildThermalExposureArtifact,
} from '../_shared/farm-watch-thermal-exposure.ts'
import {
  FARM_WATCH_HORIZONTAL_VISIBILITY_LIMITATIONS,
  FARM_WATCH_HORIZONTAL_VISIBILITY_PRODUCT,
  horizontalVisibilityArtifactPath,
  horizontalVisibilitySourceSignature,
  validateHorizontalVisibilityArtifact,
} from '../_shared/farm-watch-horizontal-visibility-contract.ts'
import {
  buildHorizontalVisibilityArtifact,
} from '../_shared/farm-watch-horizontal-visibility.ts'
import {
  FARM_WATCH_GITHUB_OIDC_AUDIENCE,
  verifyFarmWatchGitHubActionsOidc,
} from '../_shared/github-actions-oidc.ts'
import {
  materializationPresentationMode,
  normalizeFarmWatchAccountRole,
} from '../_shared/farm-watch-presentation-policy.ts'

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

const ALLOWED_ORIGINS = new Set([
  'https://pmicka.com',
  'https://www.pmicka.com',
  'http://127.0.0.1:8000',
  'http://localhost:8000',
])
const DEFAULT_PROPERTY_SLUG = 'validation-property-01'
const ALLOWED_MATERIALIZATION_WORKFLOW_REFS = new Set([
  'pmicka/Cadastory/.github/workflows/farm-watch-neutral-primitives.yml@refs/heads/main',
  'pmicka/Cadastory/.github/workflows/farm-watch-horizontal-visibility.yml@refs/heads/main',
])

type ProductKey = 'terrain' | 'lidar-source-coverage' | 'lidar-physical-structure' | 'leaf-off-structure' | 'structure-complementarity' | 'landscape-structure-context' | 'terrain-form-permeability' | 'spatial-edge-patch-context' | 'solar-terrain-context' | 'solar-exposure-context' | 'thermal-exposure-context' | 'horizontal-visibility-context'

function headers(origin = ''): Record<string, string> {
  const out: Record<string, string> = {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store, max-age=0',
    pragma: 'no-cache',
    'referrer-policy': 'no-referrer',
    'x-content-type-options': 'nosniff',
  }
  if (ALLOWED_ORIGINS.has(origin)) {
    out['access-control-allow-origin'] = origin
    out.vary = 'Origin'
    out['access-control-allow-headers'] = 'authorization, content-type, apikey'
    out['access-control-allow-methods'] = 'GET, POST, OPTIONS'
  }
  return out
}

function json(body: unknown, status = 200, origin = '') {
  return new Response(JSON.stringify(body), { status, headers: headers(origin) })
}

async function gzipBytes(bytes: Uint8Array) {
  const stream = new Response(bytes).body!.pipeThrough(new CompressionStream('gzip'))
  return new Uint8Array(await new Response(stream).arrayBuffer())
}

async function gunzipBytes(bytes: Uint8Array) {
  const stream = new Response(bytes).body!.pipeThrough(new DecompressionStream('gzip'))
  return new Uint8Array(await new Response(stream).arrayBuffer())
}

function bearer(req: Request) {
  const match = /^Bearer\s+(.+)$/i.exec(req.headers.get('authorization') || '')
  return match?.[1]?.trim() || null
}

function boundedSlug(value: string | null) {
  if (!value) return DEFAULT_PROPERTY_SLUG
  const normalized = value.trim().toLowerCase()
  return /^[a-z0-9][a-z0-9-]{0,79}$/.test(normalized) ? normalized : null
}

function validSha256(value: string | null) {
  return value && /^[0-9a-f]{64}$/.test(value) ? value : null
}

function validUuid(value: unknown) {
  const text = String(value || '')
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(text)
    ? text
    : null
}

function boundedSolarDate(value: unknown) {
  if (value == null || value === '') return null
  try {
    return requireSolarDate(String(value))
  } catch {
    return null
  }
}

function boundedThermalAt(value: unknown) {
  if (value == null || value === '') return null
  try {
    return requireThermalValidAt(String(value))
  } catch {
    return null
  }
}

function productKey(value: unknown): ProductKey | null {
  const key = String(value || '')
  return key === FARM_WATCH_TERRAIN_PRODUCT.key ||
      key === FARM_WATCH_LIDAR_SOURCE_PRODUCT.key ||
      key === FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.key ||
      key === FARM_WATCH_LEAF_OFF_PRODUCT.key ||
      key === FARM_WATCH_STRUCTURE_SYNTHESIS_PRODUCT.key ||
      key === FARM_WATCH_LANDSCAPE_STRUCTURE_PRODUCT.key ||
      key === FARM_WATCH_TERRAIN_FORM_PRODUCT.key ||
      key === FARM_WATCH_SPATIAL_PATTERN_PRODUCT.key ||
      key === FARM_WATCH_SOLAR_TERRAIN_PRODUCT.key ||
      key === FARM_WATCH_SOLAR_EXPOSURE_PRODUCT.key ||
      key === FARM_WATCH_THERMAL_EXPOSURE_PRODUCT.key
      || key === FARM_WATCH_HORIZONTAL_VISIBILITY_PRODUCT.key
    ? key as ProductKey
    : null
}

function productSpec(key: ProductKey) {
  if (key === FARM_WATCH_TERRAIN_PRODUCT.key) {
    return {
      key,
      productKind: FARM_WATCH_TERRAIN_PRODUCT.productKind,
      algorithmVersion: FARM_WATCH_TERRAIN_PRODUCT.algorithmVersion,
      outputSchemaVersion: FARM_WATCH_TERRAIN_PRODUCT.outputSchemaVersion,
      sourceSignature: FARM_WATCH_TERRAIN_SOURCE_SIGNATURE,
    }
  }
  if (key === FARM_WATCH_LIDAR_SOURCE_PRODUCT.key) {
    return {
      key,
      productKind: FARM_WATCH_LIDAR_SOURCE_PRODUCT.productKind,
      algorithmVersion: FARM_WATCH_LIDAR_SOURCE_PRODUCT.algorithmVersion,
      outputSchemaVersion: FARM_WATCH_LIDAR_SOURCE_PRODUCT.outputSchemaVersion,
      sourceSignature: FARM_WATCH_LIDAR_SOURCE_SIGNATURE,
    }
  }
  if (key === FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.key) {
    return {
      key,
      productKind: FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.productKind,
      algorithmVersion: FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.algorithmVersion,
      outputSchemaVersion: FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.outputSchemaVersion,
      sourceSignature: null,
    }
  }
  if (key === FARM_WATCH_LEAF_OFF_PRODUCT.key) {
    return {
      key,
      productKind: FARM_WATCH_LEAF_OFF_PRODUCT.productKind,
      algorithmVersion: FARM_WATCH_LEAF_OFF_PRODUCT.algorithmVersion,
      outputSchemaVersion: FARM_WATCH_LEAF_OFF_PRODUCT.outputSchemaVersion,
      sourceSignature: FARM_WATCH_LEAF_OFF_SOURCE_SIGNATURE,
    }
  }
  if (key === FARM_WATCH_LANDSCAPE_STRUCTURE_PRODUCT.key) {
    return {
      key,
      productKind: FARM_WATCH_LANDSCAPE_STRUCTURE_PRODUCT.productKind,
      algorithmVersion: FARM_WATCH_LANDSCAPE_STRUCTURE_PRODUCT.algorithmVersion,
      outputSchemaVersion: FARM_WATCH_LANDSCAPE_STRUCTURE_PRODUCT.outputSchemaVersion,
      sourceSignature: null,
    }
  }
  if (key === FARM_WATCH_TERRAIN_FORM_PRODUCT.key) {
    return {
      key,
      productKind: FARM_WATCH_TERRAIN_FORM_PRODUCT.productKind,
      algorithmVersion: FARM_WATCH_TERRAIN_FORM_PRODUCT.algorithmVersion,
      outputSchemaVersion: FARM_WATCH_TERRAIN_FORM_PRODUCT.outputSchemaVersion,
      sourceSignature: null,
    }
  }
  if (key === FARM_WATCH_SPATIAL_PATTERN_PRODUCT.key) {
    return {
      key,
      productKind: FARM_WATCH_SPATIAL_PATTERN_PRODUCT.productKind,
      algorithmVersion: FARM_WATCH_SPATIAL_PATTERN_PRODUCT.algorithmVersion,
      outputSchemaVersion: FARM_WATCH_SPATIAL_PATTERN_PRODUCT.outputSchemaVersion,
      sourceSignature: null,
    }
  }
  if (key === FARM_WATCH_SOLAR_TERRAIN_PRODUCT.key) {
    return {
      key,
      productKind: FARM_WATCH_SOLAR_TERRAIN_PRODUCT.productKind,
      algorithmVersion: FARM_WATCH_SOLAR_TERRAIN_PRODUCT.algorithmVersion,
      outputSchemaVersion: FARM_WATCH_SOLAR_TERRAIN_PRODUCT.outputSchemaVersion,
      sourceSignature: null,
    }
  }
  if (key === FARM_WATCH_SOLAR_EXPOSURE_PRODUCT.key) {
    return {
      key,
      productKind: FARM_WATCH_SOLAR_EXPOSURE_PRODUCT.productKind,
      algorithmVersion: FARM_WATCH_SOLAR_EXPOSURE_PRODUCT.algorithmVersion,
      outputSchemaVersion: FARM_WATCH_SOLAR_EXPOSURE_PRODUCT.outputSchemaVersion,
      sourceSignature: null,
    }
  }
  if (key === FARM_WATCH_THERMAL_EXPOSURE_PRODUCT.key) {
    return {
      key,
      productKind: FARM_WATCH_THERMAL_EXPOSURE_PRODUCT.productKind,
      algorithmVersion: FARM_WATCH_THERMAL_EXPOSURE_PRODUCT.algorithmVersion,
      outputSchemaVersion: FARM_WATCH_THERMAL_EXPOSURE_PRODUCT.outputSchemaVersion,
      sourceSignature: null,
    }
  }
  if (key === FARM_WATCH_HORIZONTAL_VISIBILITY_PRODUCT.key) {
    return {
      key,
      productKind: FARM_WATCH_HORIZONTAL_VISIBILITY_PRODUCT.productKind,
      algorithmVersion: FARM_WATCH_HORIZONTAL_VISIBILITY_PRODUCT.algorithmVersion,
      outputSchemaVersion: FARM_WATCH_HORIZONTAL_VISIBILITY_PRODUCT.outputSchemaVersion,
      sourceSignature: null,
    }
  }
  return {
    key,
    productKind: FARM_WATCH_STRUCTURE_SYNTHESIS_PRODUCT.productKind,
    algorithmVersion: FARM_WATCH_STRUCTURE_SYNTHESIS_PRODUCT.algorithmVersion,
    outputSchemaVersion: FARM_WATCH_STRUCTURE_SYNTHESIS_PRODUCT.outputSchemaVersion,
    sourceSignature: null,
  }
}

function validateTerrainArtifact(value: any) {
  const grid = value?.grid
  const contours = value?.contours
  return Boolean(
    value?.schema === FARM_WATCH_TERRAIN_PRODUCT.outputSchemaVersion &&
    value?.method === FARM_WATCH_TERRAIN_PRODUCT.algorithmVersion &&
    grid &&
    Number(grid.size) === FARM_WATCH_TERRAIN_PRODUCT.gridSize &&
    Array.isArray(grid.points) &&
    Array.isArray(grid.values) &&
    grid.points.length === FARM_WATCH_TERRAIN_PRODUCT.gridSize ** 2 &&
    grid.values.length === FARM_WATCH_TERRAIN_PRODUCT.gridSize ** 2 &&
    contours?.summary &&
    Array.isArray(contours?.levels) &&
    Array.isArray(value?.flow_paths) &&
    value?.flow_summary &&
    value?.flow_summary?.routing_scope === 'priority_flood_conditioned_metric_d8'
  )
}

function validateLidarSourceArtifact(value: any) {
  if (
    value?.schema !== FARM_WATCH_LIDAR_SOURCE_PRODUCT.outputSchemaVersion ||
    value?.method !== FARM_WATCH_LIDAR_SOURCE_PRODUCT.algorithmVersion ||
    !Array.isArray(value?.collections)
  ) return false

  const expected = new Set(FARM_WATCH_LIDAR_SOURCE_PRODUCT.collections.map((row) => row.id))
  for (const collection of value.collections) {
    if (!expected.has(String(collection?.id || ''))) return false
    if (!Array.isArray(collection?.items) || !Array.isArray(collection?.processing_items)) return false
    if (!collection?.coverage || !Array.isArray(collection.coverage.processing_item_ids)) return false
  }
  return true
}

function validateArtifact(key: ProductKey, value: any) {
  if (key === FARM_WATCH_TERRAIN_PRODUCT.key) return validateTerrainArtifact(value)
  if (key === FARM_WATCH_LIDAR_SOURCE_PRODUCT.key) return validateLidarSourceArtifact(value)
  if (key === FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.key) return validateLidarPhysicalArtifact(value)
  if (key === FARM_WATCH_LEAF_OFF_PRODUCT.key) return validateLeafOffArtifact(value)
  if (key === FARM_WATCH_LANDSCAPE_STRUCTURE_PRODUCT.key) return validateLandscapeStructureArtifact(value)
  if (key === FARM_WATCH_TERRAIN_FORM_PRODUCT.key) return validateTerrainFormArtifact(value)
  if (key === FARM_WATCH_SPATIAL_PATTERN_PRODUCT.key) return validateSpatialPatternArtifact(value)
  if (key === FARM_WATCH_SOLAR_TERRAIN_PRODUCT.key) return validateSolarTerrainArtifact(value)
  if (key === FARM_WATCH_SOLAR_EXPOSURE_PRODUCT.key) return validateSolarExposureArtifact(value)
  if (key === FARM_WATCH_THERMAL_EXPOSURE_PRODUCT.key) return validateThermalExposureArtifact(value)
  if (key === FARM_WATCH_HORIZONTAL_VISIBILITY_PRODUCT.key) {
    return validateHorizontalVisibilityArtifact(value)
  }
  return validateStructureSynthesisArtifact(value)
}

async function readStaticState(
  slug: string,
  key: ProductKey,
) {
  const spec = productSpec(key)
  const { data, error } = await admin.rpc('farm_watch_get_materialization_v1_internal', {
    p_slug: slug,
    p_product_kind: spec.productKind,
    p_algorithm_version: spec.algorithmVersion,
    p_output_schema_version: spec.outputSchemaVersion,
    p_source_signature: spec.sourceSignature,
  })
  if (error) throw new Error(`materialization state read failed: ${error.message}`)
  return data
}

async function readLidarPhysicalState(slug: string) {
  const sourceState = await readStaticState(slug, FARM_WATCH_LIDAR_SOURCE_PRODUCT.key)
  const sourceStatus = String(sourceState?.status || 'missing')
  if (sourceStatus !== 'available') {
    return {
      status: sourceStatus,
      identity: null,
      build: sourceState?.build || null,
      materialization: null,
    }
  }

  const sourcePayload = await readPayload(
    slug,
    FARM_WATCH_LIDAR_SOURCE_PRODUCT.key,
    sourceState,
  )
  const sourceArtifact = sourcePayload?.artifact
  const sourceArtifactSha256 = validSha256(
    String(sourcePayload?.materialization?.artifact_sha256 || ''),
  )
  if (!sourceArtifact || !sourceArtifactSha256) {
    throw new Error('LiDAR physical source plan is unavailable')
  }

  const sourceSignature = lidarPhysicalSourceSignature(sourceArtifact, sourceArtifactSha256)
  const spec = productSpec(FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.key)
  const { data, error } = await admin.rpc('farm_watch_get_materialization_v1_internal', {
    p_slug: slug,
    p_product_kind: spec.productKind,
    p_algorithm_version: spec.algorithmVersion,
    p_output_schema_version: spec.outputSchemaVersion,
    p_source_signature: sourceSignature,
  })
  if (error) throw new Error(`physical materialization state read failed: ${error.message}`)
  return data
}

async function readStructureSynthesisState(slug: string) {
  const [physicalState, leafState] = await Promise.all([
    readLidarPhysicalState(slug),
    readStaticState(slug, FARM_WATCH_LEAF_OFF_PRODUCT.key),
  ])
  const physicalStatus = String(physicalState?.status || 'missing')
  const leafStatus = String(leafState?.status || 'missing')
  if (physicalStatus !== 'available' || leafStatus !== 'available') {
    return {
      status: physicalStatus !== 'available' ? physicalStatus : leafStatus,
      identity: null,
      build: null,
      materialization: null,
    }
  }

  const physicalSha = validSha256(String(physicalState?.materialization?.artifact_sha256 || ''))
  const leafSha = validSha256(String(leafState?.materialization?.artifact_sha256 || ''))
  if (!physicalSha || !leafSha) throw new Error('structure synthesis dependency checksum is unavailable')

  const sourceSignature = structureSynthesisSourceSignature(physicalSha, leafSha)
  const spec = productSpec(FARM_WATCH_STRUCTURE_SYNTHESIS_PRODUCT.key)
  const { data, error } = await admin.rpc('farm_watch_get_materialization_v1_internal', {
    p_slug: slug,
    p_product_kind: spec.productKind,
    p_algorithm_version: spec.algorithmVersion,
    p_output_schema_version: spec.outputSchemaVersion,
    p_source_signature: sourceSignature,
  })
  if (error) throw new Error(`structure synthesis materialization state read failed: ${error.message}`)
  return data
}

async function readLandscapeStructureState(slug: string) {
  const { data: domain, error: domainError } = await admin.rpc(
    'farm_watch_get_landscape_domain_v1_internal',
    { p_slug: slug },
  )
  if (domainError) {
    throw new Error(`landscape domain state read failed: ${domainError.message}`)
  }
  const domainIdentity = String(domain?.identity?.identity_sha256 || '').toLowerCase()
  if (
    domain?.status !== 'available' ||
    !domain?.zones?.local_500m ||
    !/^[0-9a-f]{64}$/.test(domainIdentity)
  ) {
    return {
      status: String(domain?.status || 'missing'),
      identity: null,
      build: null,
      materialization: null,
    }
  }
  const sourceSignature = landscapeStructureSourceSignature({
    landscapeDomainIdentitySha256: domainIdentity,
    landscapeDomainAlgorithmVersion: String(domain?.identity?.algorithm_version || ''),
    lidarSourceContractSignature: FARM_WATCH_LIDAR_SOURCE_SIGNATURE,
  })
  const spec = productSpec(FARM_WATCH_LANDSCAPE_STRUCTURE_PRODUCT.key)
  const { data, error } = await admin.rpc('farm_watch_get_materialization_v1_internal', {
    p_slug: slug,
    p_product_kind: spec.productKind,
    p_algorithm_version: spec.algorithmVersion,
    p_output_schema_version: spec.outputSchemaVersion,
    p_source_signature: sourceSignature,
  })
  if (error) throw new Error(`landscape structure materialization state read failed: ${error.message}`)
  return data
}

async function neutralPrimitiveBaseDependencies(slug: string) {
  const [{ data: domain, error: domainError }, { data: physical, error: physicalError }] =
    await Promise.all([
      admin.rpc('farm_watch_get_landscape_domain_v1_internal', { p_slug: slug }),
      admin.rpc('farm_watch_get_landscape_physical_context_v1_internal', { p_slug: slug }),
    ])
  if (domainError) throw new Error('landscape domain dependency failed: ' + domainError.message)
  if (physicalError) throw new Error('landscape physical dependency failed: ' + physicalError.message)

  const domainIdentity = validSha256(String(domain?.identity?.identity_sha256 || ''))
  const physicalIdentity = validSha256(String(physical?.identity?.identity_sha256 || ''))
  if (
    domain?.status !== 'available' ||
    !domain?.zones?.local_500m ||
    !domain?.zones?.landscape_1500m ||
    !domainIdentity
  ) throw new Error('current barrier-aware landscape domain is unavailable')
  if (physical?.status !== 'available' || !physicalIdentity) {
    throw new Error('current landscape physical context is unavailable')
  }
  return { domain, physical, domainIdentity, physicalIdentity }
}

async function resourceEdgeDependency(slug: string, includeGeometry = false) {
  const { data, error } = await admin.rpc(
    'farm_watch_get_resource_edge_context_v1_internal',
    { p_slug: slug, p_include_geometry: includeGeometry },
  )
  if (error) throw new Error('resource edge dependency failed: ' + error.message)
  const identity = validSha256(String(data?.identity?.identity_sha256 || ''))
  if (data?.status !== 'available' || !identity) {
    throw new Error('current resource edge context is unavailable')
  }
  return { data, identity }
}

async function readDynamicState(slug: string, key: ProductKey, sourceSignature: string) {
  const spec = productSpec(key)
  const { data, error } = await admin.rpc('farm_watch_get_materialization_v1_internal', {
    p_slug: slug,
    p_product_kind: spec.productKind,
    p_algorithm_version: spec.algorithmVersion,
    p_output_schema_version: spec.outputSchemaVersion,
    p_source_signature: sourceSignature,
  })
  if (error) throw new Error('dynamic materialization state read failed: ' + error.message)
  return data
}

async function readTerrainFormState(slug: string) {
  const deps = await neutralPrimitiveBaseDependencies(slug)
  const sourceSignature = terrainFormSourceSignature({
    landscapeDomainIdentitySha256: deps.domainIdentity!,
    landscapePhysicalIdentitySha256: deps.physicalIdentity!,
  })
  return readDynamicState(slug, FARM_WATCH_TERRAIN_FORM_PRODUCT.key, sourceSignature)
}

async function spatialPatternDependencies(slug: string, includeResourceGeometry = false) {
  const [base, resource, structureState] = await Promise.all([
    neutralPrimitiveBaseDependencies(slug),
    resourceEdgeDependency(slug, includeResourceGeometry),
    readLandscapeStructureState(slug),
  ])
  const structureIdentity = validSha256(
    String(structureState?.materialization?.identity_sha256 || ''),
  )
  const structureArtifactSha256 = validSha256(
    String(structureState?.materialization?.artifact_sha256 || ''),
  )
  if (
    String(structureState?.status || '') !== 'available' ||
    !structureIdentity ||
    !structureArtifactSha256
  ) throw new Error('current local landscape structure materialization is unavailable')

  const sourceSignature = spatialPatternSourceSignature({
    landscapeDomainIdentitySha256: base.domainIdentity!,
    landscapePhysicalIdentitySha256: base.physicalIdentity!,
    resourceEdgeIdentitySha256: resource.identity!,
    landscapeStructureIdentitySha256: structureIdentity,
    landscapeStructureArtifactSha256: structureArtifactSha256,
  })
  return {
    ...base,
    resource,
    structureState,
    structureIdentity,
    structureArtifactSha256,
    sourceSignature,
  }
}

async function readSpatialPatternState(slug: string) {
  const deps = await spatialPatternDependencies(slug, false)
  return readDynamicState(slug, FARM_WATCH_SPATIAL_PATTERN_PRODUCT.key, deps.sourceSignature)
}

async function horizontalVisibilityDependencies(slug: string, includeArtifacts = false) {
  const [{ data: domain, error: domainError }, structureState, terrainState] = await Promise.all([
    admin.rpc('farm_watch_get_landscape_domain_v1_internal', { p_slug: slug }),
    readLandscapeStructureState(slug),
    readTerrainFormState(slug),
  ])
  if (domainError) throw new Error('horizontal visibility landscape domain failed: ' + domainError.message)
  const domainIdentity = validSha256(String(domain?.identity?.identity_sha256 || ''))
  const structureIdentity = validSha256(String(structureState?.materialization?.identity_sha256 || ''))
  const structureArtifactSha256 = validSha256(String(structureState?.materialization?.artifact_sha256 || ''))
  const terrainIdentity = validSha256(String(terrainState?.materialization?.identity_sha256 || ''))
  const terrainArtifactSha256 = validSha256(String(terrainState?.materialization?.artifact_sha256 || ''))
  if (
    domain?.status !== 'available' ||
    structureState?.status !== 'available' ||
    terrainState?.status !== 'available' ||
    !domain?.zones?.local_500m ||
    !domainIdentity || !structureIdentity || !structureArtifactSha256 ||
    !terrainIdentity || !terrainArtifactSha256
  ) throw new Error('current horizontal visibility dependencies are unavailable')

  const sourceSignature = horizontalVisibilitySourceSignature({
    landscapeDomainIdentitySha256: domainIdentity,
    landscapeStructureIdentitySha256: structureIdentity,
    landscapeStructureArtifactSha256: structureArtifactSha256,
    terrainFormIdentitySha256: terrainIdentity,
    terrainFormArtifactSha256: terrainArtifactSha256,
  })

  let landscapeStructureArtifact: any = null
  let terrainFormArtifact: any = null
  if (includeArtifacts) {
    const [structurePayload, terrainPayload] = await Promise.all([
      readPayload(slug, FARM_WATCH_LANDSCAPE_STRUCTURE_PRODUCT.key, structureState),
      readPayload(slug, FARM_WATCH_TERRAIN_FORM_PRODUCT.key, terrainState),
    ])
    landscapeStructureArtifact = structurePayload?.artifact
    terrainFormArtifact = terrainPayload?.artifact
    if (!landscapeStructureArtifact || !terrainFormArtifact) {
      throw new Error('horizontal visibility dependency artifacts are unavailable')
    }
  }
  return {
    domainIdentity,
    domain,
    structureState,
    terrainState,
    structureIdentity,
    structureArtifactSha256,
    terrainIdentity,
    terrainArtifactSha256,
    landscapeStructureArtifact,
    terrainFormArtifact,
    sourceSignature,
  }
}

async function readHorizontalVisibilityState(slug: string) {
  const deps = await horizontalVisibilityDependencies(slug, false)
  return readDynamicState(slug, FARM_WATCH_HORIZONTAL_VISIBILITY_PRODUCT.key, deps.sourceSignature)
}

async function solarTerrainDependencies(slug: string, includeArtifacts = false) {
  const [terrainState, spatialState] = await Promise.all([
    readTerrainFormState(slug),
    readSpatialPatternState(slug),
  ])
  const terrainIdentity = validSha256(String(terrainState?.materialization?.identity_sha256 || ''))
  const terrainArtifactSha256 = validSha256(
    String(terrainState?.materialization?.artifact_sha256 || ''),
  )
  const spatialIdentity = validSha256(String(spatialState?.materialization?.identity_sha256 || ''))
  const spatialArtifactSha256 = validSha256(
    String(spatialState?.materialization?.artifact_sha256 || ''),
  )
  if (
    terrainState?.status !== 'available' ||
    spatialState?.status !== 'available' ||
    !terrainIdentity ||
    !terrainArtifactSha256 ||
    !spatialIdentity ||
    !spatialArtifactSha256
  ) throw new Error('current solar terrain dependencies are unavailable')

  const sourceSignature = solarTerrainSourceSignature({
    terrainMaterializationIdentitySha256: terrainIdentity,
    terrainArtifactSha256,
    spatialPatternMaterializationIdentitySha256: spatialIdentity,
    spatialPatternArtifactSha256: spatialArtifactSha256,
  })

  let terrainArtifact: any = null
  let spatialArtifact: any = null
  if (includeArtifacts) {
    const [terrainPayload, spatialPayload] = await Promise.all([
      readPayload(slug, FARM_WATCH_TERRAIN_FORM_PRODUCT.key, terrainState),
      readPayload(slug, FARM_WATCH_SPATIAL_PATTERN_PRODUCT.key, spatialState),
    ])
    terrainArtifact = terrainPayload?.artifact
    spatialArtifact = spatialPayload?.artifact
    if (!terrainArtifact || !spatialArtifact) {
      throw new Error('solar terrain dependency artifact payload is unavailable')
    }
  }

  return {
    terrainState,
    spatialState,
    terrainIdentity,
    terrainArtifactSha256,
    spatialIdentity,
    spatialArtifactSha256,
    terrainArtifact,
    spatialArtifact,
    sourceSignature,
  }
}

async function readSolarTerrainState(slug: string) {
  const deps = await solarTerrainDependencies(slug, false)
  return readDynamicState(slug, FARM_WATCH_SOLAR_TERRAIN_PRODUCT.key, deps.sourceSignature)
}

async function solarExposureDependencies(
  slug: string,
  solarDate: string,
  includeArtifact = false,
) {
  const date = requireSolarDate(solarDate)
  const solarTerrainState = await readSolarTerrainState(slug)
  const solarTerrainIdentity = validSha256(
    String(solarTerrainState?.materialization?.identity_sha256 || ''),
  )
  const solarTerrainArtifactSha256 = validSha256(
    String(solarTerrainState?.materialization?.artifact_sha256 || ''),
  )
  if (
    solarTerrainState?.status !== 'available' ||
    !solarTerrainIdentity ||
    !solarTerrainArtifactSha256
  ) throw new Error('current solar terrain materialization is unavailable')

  const sourceSignature = solarExposureSourceSignature({
    solarTerrainMaterializationIdentitySha256: solarTerrainIdentity,
    solarTerrainArtifactSha256,
    solarDate: date,
  })

  let solarTerrainArtifact: any = null
  if (includeArtifact) {
    const payload = await readPayload(
      slug,
      FARM_WATCH_SOLAR_TERRAIN_PRODUCT.key,
      solarTerrainState,
    )
    solarTerrainArtifact = payload?.artifact
    if (!solarTerrainArtifact) throw new Error('solar terrain artifact payload is unavailable')
  }

  return {
    solarDate: date,
    solarTerrainState,
    solarTerrainIdentity,
    solarTerrainArtifactSha256,
    solarTerrainArtifact,
    sourceSignature,
  }
}

async function readSolarExposureState(slug: string, solarDate: string) {
  const deps = await solarExposureDependencies(slug, solarDate, false)
  return readDynamicState(slug, FARM_WATCH_SOLAR_EXPOSURE_PRODUCT.key, deps.sourceSignature)
}

async function thermalExposureDependencies(
  slug: string,
  requestedAt: string,
  includeArtifact = false,
) {
  const targetAt = requireThermalValidAt(requestedAt)
  const solarTerrainState = await readSolarTerrainState(slug)
  const solarTerrainIdentity = validSha256(
    String(solarTerrainState?.materialization?.identity_sha256 || ''),
  )
  const solarTerrainArtifactSha256 = validSha256(
    String(solarTerrainState?.materialization?.artifact_sha256 || ''),
  )
  if (
    solarTerrainState?.status !== 'available' ||
    !solarTerrainIdentity ||
    !solarTerrainArtifactSha256
  ) throw new Error('current solar terrain materialization is unavailable')

  const { data: forcingResponse, error: forcingError } = await admin.rpc(
    'farm_watch_get_meteorological_forcing_v1_internal',
    {
      p_slug: slug,
      p_valid_at: targetAt,
      p_max_age_minutes: FARM_WATCH_THERMAL_EXPOSURE_PRODUCT.forcingMaxAgeMinutes,
      p_source_state: FARM_WATCH_THERMAL_EXPOSURE_PRODUCT.forcingSourceState,
    },
  )
  if (forcingError) {
    throw new Error('meteorological forcing dependency failed: ' + forcingError.message)
  }
  if (forcingResponse?.status !== 'available' || !forcingResponse?.context) {
    throw new Error(
      'meteorological forcing dependency is ' + String(forcingResponse?.status || 'missing'),
    )
  }

  const forcingIdentity = validSha256(
    String(forcingResponse?.identity?.identity_sha256 || ''),
  )
  const sourceIndexSha256 = validSha256(
    String(forcingResponse?.identity?.source_index_sha256 || ''),
  )
  const sourceRecordsSha256 = validSha256(
    String(forcingResponse?.identity?.source_records_sha256 || ''),
  )
  const forcingValidAt = requireThermalValidAt(
    String(forcingResponse?.valid_at || forcingResponse?.context?.valid_at || ''),
  )
  if (!forcingIdentity || !sourceIndexSha256 || !sourceRecordsSha256) {
    throw new Error('meteorological forcing identity is unavailable')
  }

  const sourceSignature = thermalExposureSourceSignature({
    solarTerrainMaterializationIdentitySha256: solarTerrainIdentity,
    solarTerrainArtifactSha256,
    meteorologicalForcingIdentitySha256: forcingIdentity,
    meteorologicalForcingValidAt: forcingValidAt,
    sourceIndexSha256,
    sourceRecordsSha256,
  })

  let solarTerrainArtifact: any = null
  if (includeArtifact) {
    const payload = await readPayload(
      slug,
      FARM_WATCH_SOLAR_TERRAIN_PRODUCT.key,
      solarTerrainState,
    )
    solarTerrainArtifact = payload?.artifact
    if (!solarTerrainArtifact) throw new Error('solar terrain artifact payload is unavailable')
  }

  return {
    requestedAt: targetAt,
    solarTerrainState,
    solarTerrainIdentity,
    solarTerrainArtifactSha256,
    solarTerrainArtifact,
    forcingResponse,
    forcingIdentity,
    forcingValidAt,
    sourceIndexSha256,
    sourceRecordsSha256,
    sourceSignature,
  }
}

async function readThermalExposureState(slug: string, requestedAt: string) {
  const deps = await thermalExposureDependencies(slug, requestedAt, false)
  return readDynamicState(
    slug,
    FARM_WATCH_THERMAL_EXPOSURE_PRODUCT.key,
    deps.sourceSignature,
  )
}

async function readState(
  slug: string,
  key: ProductKey,
  solarDate: string | null = null,
  thermalAt: string | null = null,
) {
  if (key === FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.key) return readLidarPhysicalState(slug)
  if (key === FARM_WATCH_STRUCTURE_SYNTHESIS_PRODUCT.key) return readStructureSynthesisState(slug)
  if (key === FARM_WATCH_LANDSCAPE_STRUCTURE_PRODUCT.key) return readLandscapeStructureState(slug)
  if (key === FARM_WATCH_TERRAIN_FORM_PRODUCT.key) return readTerrainFormState(slug)
  if (key === FARM_WATCH_SPATIAL_PATTERN_PRODUCT.key) return readSpatialPatternState(slug)
  if (key === FARM_WATCH_SOLAR_TERRAIN_PRODUCT.key) return readSolarTerrainState(slug)
  if (key === FARM_WATCH_SOLAR_EXPOSURE_PRODUCT.key) {
    if (!solarDate) throw new Error('solar exposure date is required')
    return readSolarExposureState(slug, solarDate)
  }
  if (key === FARM_WATCH_THERMAL_EXPOSURE_PRODUCT.key) {
    if (!thermalAt) throw new Error('thermal exposure timestamp is required')
    return readThermalExposureState(slug, thermalAt)
  }
  if (key === FARM_WATCH_HORIZONTAL_VISIBILITY_PRODUCT.key) return readHorizontalVisibilityState(slug)
  return readStaticState(slug, key)
}

async function claimBuild(
  slug: string,
  key: Exclude<ProductKey, 'lidar-physical-structure' | 'structure-complementarity' | 'landscape-structure-context'>,
  workerId: string,
) {
  const spec = productSpec(key)
  const { data, error } = await admin.rpc('farm_watch_claim_materialization_build_v1_internal', {
    p_slug: slug,
    p_product_kind: spec.productKind,
    p_algorithm_version: spec.algorithmVersion,
    p_output_schema_version: spec.outputSchemaVersion,
    p_source_signature: spec.sourceSignature,
    p_worker_id: workerId,
    p_lease_seconds: 900,
  })
  if (error) throw new Error(`materialization claim failed: ${error.message}`)
  return data
}

async function claimDynamicBuild(
  slug: string,
  key: ProductKey,
  sourceSignature: string,
  workerId: string,
) {
  const spec = productSpec(key)
  const { data, error } = await admin.rpc('farm_watch_claim_materialization_build_v1_internal', {
    p_slug: slug,
    p_product_kind: spec.productKind,
    p_algorithm_version: spec.algorithmVersion,
    p_output_schema_version: spec.outputSchemaVersion,
    p_source_signature: sourceSignature,
    p_worker_id: workerId,
    p_lease_seconds: 1800,
  })
  if (error) throw new Error('dynamic materialization claim failed: ' + error.message)
  return data
}

async function failBuild(buildId: string, leaseToken: string, error: unknown) {
  const { error: failError } = await admin.rpc('farm_watch_fail_materialization_build_v1_internal', {
    p_build_id: buildId,
    p_lease_token: leaseToken,
    p_error: error instanceof Error ? error.message : String(error),
    p_retry_delay_seconds: 300,
  })
  if (failError) console.error('Failed to persist materialization failure', failError.message)
}

async function completeBuild(args: {
  buildId: string
  leaseToken: string
  sampledSourceSha256: string
  evidenceClass: string
  summary: any
  sourceProvenance: any
  limitations: readonly string[]
  bucket: string
  path: string
  format: string
  mimeType: string
  bytes: Uint8Array
  artifactSha256: string
  expiresAt: string
}) {
  const { error } = await admin.rpc('farm_watch_complete_materialization_build_v1_internal', {
    p_build_id: args.buildId,
    p_lease_token: args.leaseToken,
    p_sampled_source_sha256: args.sampledSourceSha256,
    p_evidence_class: args.evidenceClass,
    p_summary: args.summary,
    p_source_provenance: args.sourceProvenance,
    p_limitations: args.limitations,
    p_artifact_bucket: args.bucket,
    p_artifact_path: args.path,
    p_artifact_format: args.format,
    p_artifact_mime_type: args.mimeType,
    p_artifact_size_bytes: args.bytes.byteLength,
    p_artifact_sha256: args.artifactSha256,
    p_expires_at: args.expiresAt,
  })
  if (error) throw new Error(`materialization completion failed: ${error.message}`)
}

async function readMaterializationBuild(buildId: string) {
  const { data, error } = await admin.rpc(
    'farm_watch_get_materialization_build_v1_internal',
    { p_build_id: buildId },
  )
  if (error || !data) {
    throw new Error('materialization build unavailable' + (error?.message ? ': ' + error.message : ''))
  }
  return data
}

async function buildTerrainMaterialization(slug: string, workerId: string) {
  const claim = await claimBuild(slug, FARM_WATCH_TERRAIN_PRODUCT.key, workerId)
  if (claim?.action === 'reuse') return await readState(slug, FARM_WATCH_TERRAIN_PRODUCT.key)
  if (claim?.action !== 'build') {
    return { status: claim?.action || 'not_claimed', build: claim || null, materialization: null }
  }

  const buildId = String(claim.build_id)
  const leaseToken = String(claim.lease_token)
  try {
    const startedAt = performance.now()
    const { artifact, sampledSourceSha256 } = await buildTerrainArtifact(
      claim.boundary_geojson,
      claim.stated_acres == null ? null : Number(claim.stated_acres),
    )
    const bytes = new TextEncoder().encode(JSON.stringify(artifact))
    const artifactSha256 = await sha256Hex(bytes)
    const path = terrainArtifactPath(
      String(claim.property_id),
      String(claim.input_signature_sha256),
      artifactSha256,
    )
    const { error: uploadError } = await admin.storage
      .from(FARM_WATCH_TERRAIN_PRODUCT.artifactBucket)
      .upload(path, bytes, {
        contentType: FARM_WATCH_TERRAIN_PRODUCT.artifactMimeType,
        cacheControl: '31536000',
        upsert: true,
      })
    if (uploadError) throw new Error(`terrain artifact upload failed: ${uploadError.message}`)

    const completedAt = new Date()
    const expiresAt = new Date(
      completedAt.getTime() + FARM_WATCH_TERRAIN_PRODUCT.refreshDays * 24 * 60 * 60 * 1000,
    )
    await completeBuild({
      buildId,
      leaseToken,
      sampledSourceSha256,
      evidenceClass: FARM_WATCH_TERRAIN_PRODUCT.evidenceClass,
      summary: {
        grid_size: artifact.grid.size,
        raster_observation_count: artifact.grid.values.filter(Number.isFinite).length,
        grid_extent_min_ft: artifact.grid.min,
        grid_extent_max_ft: artifact.grid.max,
        contour_interval_ft: artifact.contours.summary.interval,
        contour_path_count: artifact.contours.summary.pathCount,
        flow_trace_count: artifact.flow_paths.length,
        flow_routing_scope: artifact.flow_summary?.routing_scope || null,
        flow_min_contributing_area_acres: artifact.flow_summary?.min_contributing_area_acres ?? null,
        flow_threshold_cells: artifact.flow_summary?.threshold_cells ?? null,
        flow_channel_cell_count: artifact.flow_summary?.channel_cell_count ?? null,
        flow_conditioned_cell_count: artifact.flow_summary?.conditioning?.filled_cell_count ?? null,
        flow_max_fill_depth_ft: artifact.flow_summary?.conditioning?.max_fill_depth_ft ?? null,
        terrain_anatomy_available: Boolean(artifact.anatomy),
        artifact_size_bytes: bytes.byteLength,
        worker_elapsed_ms: Math.round(performance.now() - startedAt),
      },
      sourceProvenance: {
        source_slug: FARM_WATCH_TERRAIN_PRODUCT.sourceSlug,
        source_url: FARM_WATCH_TERRAIN_PRODUCT.sourceUrl,
        source_signature: FARM_WATCH_TERRAIN_SOURCE_SIGNATURE,
        source_signature_sha256: claim.source_signature_sha256,
        source_revision_status: FARM_WATCH_TERRAIN_PRODUCT.sourceRevisionStatus,
        sampled_source_sha256: sampledSourceSha256,
        operation: 'ImageServer/getSamples',
        grid_size: FARM_WATCH_TERRAIN_PRODUCT.gridSize,
        bounds_padding_fraction: FARM_WATCH_TERRAIN_PRODUCT.boundsPaddingFraction,
        input_srid: 4326,
        requested_at: completedAt.toISOString(),
      },
      limitations: FARM_WATCH_TERRAIN_LIMITATIONS,
      bucket: FARM_WATCH_TERRAIN_PRODUCT.artifactBucket,
      path,
      format: FARM_WATCH_TERRAIN_PRODUCT.artifactFormat,
      mimeType: FARM_WATCH_TERRAIN_PRODUCT.artifactMimeType,
      bytes,
      artifactSha256,
      expiresAt: expiresAt.toISOString(),
    })
    return await readState(slug, FARM_WATCH_TERRAIN_PRODUCT.key)
  } catch (error) {
    await failBuild(buildId, leaseToken, error)
    throw error
  }
}

async function buildLidarSourceMaterialization(slug: string, workerId: string) {
  const claim = await claimBuild(slug, FARM_WATCH_LIDAR_SOURCE_PRODUCT.key, workerId)
  if (claim?.action === 'reuse') return await readState(slug, FARM_WATCH_LIDAR_SOURCE_PRODUCT.key)
  if (claim?.action !== 'build') {
    return { status: claim?.action || 'not_claimed', build: claim || null, materialization: null }
  }

  const buildId = String(claim.build_id)
  const leaseToken = String(claim.lease_token)
  try {
    const startedAt = performance.now()
    const { artifact, sampledSourceSha256 } = await buildLidarSourceArtifact(claim.boundary_geojson)
    const bytes = new TextEncoder().encode(JSON.stringify(artifact))
    const artifactSha256 = await sha256Hex(bytes)
    const path = lidarSourceArtifactPath(
      String(claim.property_id),
      String(claim.input_signature_sha256),
      artifactSha256,
    )
    const { error: uploadError } = await admin.storage
      .from(FARM_WATCH_LIDAR_SOURCE_PRODUCT.artifactBucket)
      .upload(path, bytes, {
        contentType: FARM_WATCH_LIDAR_SOURCE_PRODUCT.artifactMimeType,
        cacheControl: '31536000',
        upsert: true,
      })
    if (uploadError) throw new Error(`LiDAR source artifact upload failed: ${uploadError.message}`)

    const completedAt = new Date()
    const expiresAt = new Date(
      completedAt.getTime() + FARM_WATCH_LIDAR_SOURCE_PRODUCT.refreshDays * 24 * 60 * 60 * 1000,
    )
    const collectionSummary = Object.fromEntries(artifact.collections.map((collection: any) => [
      collection.id,
      {
        matched_item_count: collection.matched_item_count,
        selected_item_count: collection.coverage?.intersecting_usable_item_count ?? 0,
        processing_mode: collection.coverage?.processing_mode || 'unavailable',
        sampled_parcel_coverage_percent:
          collection.coverage?.sampled_parcel_coverage_percent ?? null,
        processing_item_ids: collection.coverage?.processing_item_ids || [],
      },
    ]))

    await completeBuild({
      buildId,
      leaseToken,
      sampledSourceSha256,
      evidenceClass: FARM_WATCH_LIDAR_SOURCE_PRODUCT.evidenceClass,
      summary: {
        collections: collectionSummary,
        artifact_size_bytes: bytes.byteLength,
        worker_elapsed_ms: Math.round(performance.now() - startedAt),
      },
      sourceProvenance: {
        source_slug: 'kyfromabove-lidar-stac',
        source_url: FARM_WATCH_LIDAR_SOURCE_PRODUCT.stacRoot,
        source_signature: FARM_WATCH_LIDAR_SOURCE_SIGNATURE,
        source_signature_sha256: claim.source_signature_sha256,
        source_revision_status: 'provider_catalog_revision_unresolved',
        sampled_source_sha256: sampledSourceSha256,
        operation: 'STAC POST /search',
        requested_at: completedAt.toISOString(),
      },
      limitations: FARM_WATCH_LIDAR_SOURCE_LIMITATIONS,
      bucket: FARM_WATCH_LIDAR_SOURCE_PRODUCT.artifactBucket,
      path,
      format: FARM_WATCH_LIDAR_SOURCE_PRODUCT.artifactFormat,
      mimeType: FARM_WATCH_LIDAR_SOURCE_PRODUCT.artifactMimeType,
      bytes,
      artifactSha256,
      expiresAt: expiresAt.toISOString(),
    })
    return await readState(slug, FARM_WATCH_LIDAR_SOURCE_PRODUCT.key)
  } catch (error) {
    await failBuild(buildId, leaseToken, error)
    throw error
  }
}

async function uploadNeutralPrimitive(args: {
  claim: any
  artifact: any
  sampledSourceSha256: string
  key: ProductKey
  sourceSignature: string
  limitations: readonly string[]
  refreshDays: number
  artifactPath: (propertyId: string, inputSignature: string, artifactSha256: string) => string
  maxArtifactBytes?: number
  storageEncoding?: 'identity' | 'gzip'
}) {
  const spec = productSpec(args.key)
  const jsonBytes = new TextEncoder().encode(JSON.stringify(args.artifact))
  const bytes = args.storageEncoding === 'gzip' ? await gzipBytes(jsonBytes) : jsonBytes
  const maxArtifactBytes = args.maxArtifactBytes ?? 10 * 1024 * 1024
  if (bytes.byteLength <= 0 || bytes.byteLength > maxArtifactBytes) {
    throw new Error('neutral primitive artifact size is invalid')
  }
  const artifactSha256 = await sha256Hex(bytes)
  const path = args.artifactPath(
    String(args.claim.property_id),
    String(args.claim.input_signature_sha256),
    artifactSha256,
  )
  const { error: uploadError } = await admin.storage
    .from('farm-watch-derived')
    .upload(path, bytes, {
      contentType: args.storageEncoding === 'gzip'
        ? FARM_WATCH_HORIZONTAL_VISIBILITY_PRODUCT.artifactMimeType
        : 'application/json',
      cacheControl: '31536000',
      upsert: true,
    })
  if (uploadError) throw new Error('neutral primitive artifact upload failed: ' + uploadError.message)

  const completedAt = new Date()
  const expiresAt = new Date(
    completedAt.getTime() + args.refreshDays * 24 * 60 * 60 * 1000,
  )
  await completeBuild({
    buildId: String(args.claim.build_id),
    leaseToken: String(args.claim.lease_token),
    sampledSourceSha256: args.sampledSourceSha256,
    evidenceClass: 'deterministic_derived',
    summary: {
      ...(args.artifact.summary || {}),
      artifact_size_bytes: bytes.byteLength,
    },
    sourceProvenance: {
      ...(args.artifact.source_provenance || {}),
      source_signature: args.sourceSignature,
      source_signature_sha256: args.claim.source_signature_sha256,
      storage_encoding: args.storageEncoding || 'identity',
      completed_at: completedAt.toISOString(),
    },
    limitations: args.limitations,
    bucket: 'farm-watch-derived',
    path,
    format: args.storageEncoding === 'gzip'
      ? FARM_WATCH_HORIZONTAL_VISIBILITY_PRODUCT.artifactFormat
      : spec.outputSchemaVersion,
    mimeType: args.storageEncoding === 'gzip'
      ? FARM_WATCH_HORIZONTAL_VISIBILITY_PRODUCT.artifactMimeType
      : 'application/json',
    bytes,
    artifactSha256,
    expiresAt: expiresAt.toISOString(),
  })
}

async function buildTerrainFormMaterialization(slug: string, workerId: string) {
  const deps = await neutralPrimitiveBaseDependencies(slug)
  const sourceSignature = terrainFormSourceSignature({
    landscapeDomainIdentitySha256: deps.domainIdentity!,
    landscapePhysicalIdentitySha256: deps.physicalIdentity!,
  })
  const claim = await claimDynamicBuild(
    slug,
    FARM_WATCH_TERRAIN_FORM_PRODUCT.key,
    sourceSignature,
    workerId,
  )
  if (claim?.action === 'reuse') return readTerrainFormState(slug)
  if (claim?.action !== 'build') {
    return { status: claim?.action || 'not_claimed', build: claim || null, materialization: null }
  }

  const buildId = String(claim.build_id)
  const leaseToken = String(claim.lease_token)
  try {
    const { artifact, sampledSourceSha256 } = await buildTerrainFormArtifact({
      localGeometry: deps.domain.zones.local_500m,
      landscapeGeometry: deps.domain.zones.landscape_1500m,
      domainIdentitySha256: deps.domainIdentity!,
      domainAlgorithmVersion: String(deps.domain.identity.algorithm_version || ''),
      landscapePhysicalIdentitySha256: deps.physicalIdentity!,
    })
    await uploadNeutralPrimitive({
      claim,
      artifact,
      sampledSourceSha256,
      key: FARM_WATCH_TERRAIN_FORM_PRODUCT.key,
      sourceSignature,
      limitations: FARM_WATCH_TERRAIN_FORM_LIMITATIONS,
      refreshDays: FARM_WATCH_TERRAIN_FORM_PRODUCT.refreshDays,
      artifactPath: terrainFormArtifactPath,
    })
    return readTerrainFormState(slug)
  } catch (error) {
    await failBuild(buildId, leaseToken, error)
    throw error
  }
}

async function buildSpatialPatternMaterialization(slug: string, workerId: string) {
  const deps = await spatialPatternDependencies(slug, true)
  const claim = await claimDynamicBuild(
    slug,
    FARM_WATCH_SPATIAL_PATTERN_PRODUCT.key,
    deps.sourceSignature,
    workerId,
  )
  if (claim?.action === 'reuse') return readSpatialPatternState(slug)
  if (claim?.action !== 'build') {
    return { status: claim?.action || 'not_claimed', build: claim || null, materialization: null }
  }

  const buildId = String(claim.build_id)
  const leaseToken = String(claim.lease_token)
  try {
    const structurePayload = await readPayload(
      slug,
      FARM_WATCH_LANDSCAPE_STRUCTURE_PRODUCT.key,
      deps.structureState,
    )
    if (!structurePayload?.artifact) {
      throw new Error('landscape structure artifact payload is unavailable')
    }
    const { artifact, sampledSourceSha256 } = await buildSpatialPatternArtifact({
      localGeometry: deps.domain.zones.local_500m,
      domainIdentitySha256: deps.domainIdentity!,
      domainAlgorithmVersion: String(deps.domain.identity.algorithm_version || ''),
      landscapePhysicalIdentitySha256: deps.physicalIdentity!,
      resourceEdgeIdentitySha256: deps.resource.identity!,
      resourceEdgeContext: deps.resource.data,
      landscapeStructureIdentitySha256: deps.structureIdentity!,
      landscapeStructureArtifactSha256: deps.structureArtifactSha256!,
      landscapeStructureArtifact: structurePayload.artifact,
    })
    await uploadNeutralPrimitive({
      claim,
      artifact,
      sampledSourceSha256,
      key: FARM_WATCH_SPATIAL_PATTERN_PRODUCT.key,
      sourceSignature: deps.sourceSignature,
      limitations: FARM_WATCH_SPATIAL_PATTERN_LIMITATIONS,
      refreshDays: FARM_WATCH_SPATIAL_PATTERN_PRODUCT.refreshDays,
      artifactPath: spatialPatternArtifactPath,
    })
    return readSpatialPatternState(slug)
  } catch (error) {
    await failBuild(buildId, leaseToken, error)
    throw error
  }
}

async function buildSolarTerrainMaterialization(slug: string, workerId: string) {
  const deps = await solarTerrainDependencies(slug, true)
  const claim = await claimDynamicBuild(
    slug,
    FARM_WATCH_SOLAR_TERRAIN_PRODUCT.key,
    deps.sourceSignature,
    workerId,
  )
  if (claim?.action === 'reuse') return readSolarTerrainState(slug)
  if (claim?.action !== 'build') {
    return { status: claim?.action || 'not_claimed', build: claim || null, materialization: null }
  }

  const buildId = String(claim.build_id)
  const leaseToken = String(claim.lease_token)
  try {
    const built = await buildSolarTerrainArtifact({
      terrainArtifact: deps.terrainArtifact,
      terrainMaterializationIdentitySha256: deps.terrainIdentity!,
      terrainArtifactSha256: deps.terrainArtifactSha256!,
      spatialPatternArtifact: deps.spatialArtifact,
      spatialPatternMaterializationIdentitySha256: deps.spatialIdentity!,
      spatialPatternArtifactSha256: deps.spatialArtifactSha256!,
    })
    await uploadNeutralPrimitive({
      claim,
      artifact: built.artifact,
      sampledSourceSha256: built.sampledSourceSha256,
      key: FARM_WATCH_SOLAR_TERRAIN_PRODUCT.key,
      sourceSignature: deps.sourceSignature,
      limitations: FARM_WATCH_SOLAR_TERRAIN_LIMITATIONS,
      refreshDays: FARM_WATCH_SOLAR_TERRAIN_PRODUCT.refreshDays,
      artifactPath: solarTerrainArtifactPath,
    })
    return readSolarTerrainState(slug)
  } catch (error) {
    await failBuild(buildId, leaseToken, error)
    throw error
  }
}

async function buildSolarExposureMaterialization(
  slug: string,
  solarDate: string,
  workerId: string,
) {
  const deps = await solarExposureDependencies(slug, solarDate, true)
  const claim = await claimDynamicBuild(
    slug,
    FARM_WATCH_SOLAR_EXPOSURE_PRODUCT.key,
    deps.sourceSignature,
    workerId,
  )
  if (claim?.action === 'reuse') return readSolarExposureState(slug, deps.solarDate)
  if (claim?.action !== 'build') {
    return { status: claim?.action || 'not_claimed', build: claim || null, materialization: null }
  }

  const buildId = String(claim.build_id)
  const leaseToken = String(claim.lease_token)
  try {
    const built = await buildSolarExposureArtifact({
      solarDate: deps.solarDate,
      solarTerrainArtifact: deps.solarTerrainArtifact,
      solarTerrainMaterializationIdentitySha256: deps.solarTerrainIdentity!,
      solarTerrainArtifactSha256: deps.solarTerrainArtifactSha256!,
    })
    await uploadNeutralPrimitive({
      claim,
      artifact: built.artifact,
      sampledSourceSha256: built.sampledSourceSha256,
      key: FARM_WATCH_SOLAR_EXPOSURE_PRODUCT.key,
      sourceSignature: deps.sourceSignature,
      limitations: FARM_WATCH_SOLAR_EXPOSURE_LIMITATIONS,
      refreshDays: FARM_WATCH_SOLAR_EXPOSURE_PRODUCT.refreshDays,
      artifactPath: solarExposureArtifactPath,
    })
    return readSolarExposureState(slug, deps.solarDate)
  } catch (error) {
    await failBuild(buildId, leaseToken, error)
    throw error
  }
}

async function buildThermalExposureMaterialization(
  slug: string,
  requestedAt: string,
  workerId: string,
) {
  const deps = await thermalExposureDependencies(slug, requestedAt, true)
  const claim = await claimDynamicBuild(
    slug,
    FARM_WATCH_THERMAL_EXPOSURE_PRODUCT.key,
    deps.sourceSignature,
    workerId,
  )
  if (claim?.action === 'reuse') {
    return readDynamicState(
      slug,
      FARM_WATCH_THERMAL_EXPOSURE_PRODUCT.key,
      deps.sourceSignature,
    )
  }
  if (claim?.action !== 'build') {
    return { status: claim?.action || 'not_claimed', build: claim || null, materialization: null }
  }

  const buildId = String(claim.build_id)
  const leaseToken = String(claim.lease_token)
  try {
    const built = await buildThermalExposureArtifact({
      solarTerrainArtifact: deps.solarTerrainArtifact,
      solarTerrainMaterializationIdentitySha256: deps.solarTerrainIdentity!,
      solarTerrainArtifactSha256: deps.solarTerrainArtifactSha256!,
      meteorologicalForcingResponse: deps.forcingResponse,
    })
    await uploadNeutralPrimitive({
      claim,
      artifact: built.artifact,
      sampledSourceSha256: built.sampledSourceSha256,
      key: FARM_WATCH_THERMAL_EXPOSURE_PRODUCT.key,
      sourceSignature: deps.sourceSignature,
      limitations: FARM_WATCH_THERMAL_EXPOSURE_LIMITATIONS,
      refreshDays: FARM_WATCH_THERMAL_EXPOSURE_PRODUCT.refreshDays,
      artifactPath: thermalExposureArtifactPath,
    })
    return readDynamicState(
      slug,
      FARM_WATCH_THERMAL_EXPOSURE_PRODUCT.key,
      deps.sourceSignature,
    )
  } catch (error) {
    await failBuild(buildId, leaseToken, error)
    throw error
  }
}

async function buildHorizontalVisibilityMaterialization(slug: string, workerId: string) {
  const deps = await horizontalVisibilityDependencies(slug, true)
  const claim = await claimDynamicBuild(
    slug,
    FARM_WATCH_HORIZONTAL_VISIBILITY_PRODUCT.key,
    deps.sourceSignature,
    workerId,
  )
  if (claim?.action === 'reuse') return readHorizontalVisibilityState(slug)
  if (claim?.action !== 'build') {
    return { status: claim?.action || 'not_claimed', build: claim || null, materialization: null }
  }

  const buildId = String(claim.build_id)
  const leaseToken = String(claim.lease_token)
  try {
    const built = await buildHorizontalVisibilityArtifact({
      landscapeStructureArtifact: deps.landscapeStructureArtifact,
      terrainFormArtifact: deps.terrainFormArtifact,
      landscapeDomainIdentitySha256: deps.domainIdentity,
      landscapeStructureIdentitySha256: deps.structureIdentity,
      landscapeStructureArtifactSha256: deps.structureArtifactSha256,
      terrainFormIdentitySha256: deps.terrainIdentity,
      terrainFormArtifactSha256: deps.terrainArtifactSha256,
      sourceSignature: deps.sourceSignature,
    })
    await uploadNeutralPrimitive({
      claim,
      artifact: built.artifact,
      sampledSourceSha256: built.sampledSourceSha256,
      key: FARM_WATCH_HORIZONTAL_VISIBILITY_PRODUCT.key,
      sourceSignature: deps.sourceSignature,
      limitations: FARM_WATCH_HORIZONTAL_VISIBILITY_LIMITATIONS,
      refreshDays: FARM_WATCH_HORIZONTAL_VISIBILITY_PRODUCT.refreshDays,
      artifactPath: horizontalVisibilityArtifactPath,
    })
    return readHorizontalVisibilityState(slug)
  } catch (error) {
    await failBuild(buildId, leaseToken, error)
    throw error
  }
}

async function prepareHorizontalVisibilityMaterialization(slug: string, workerId: string) {
  const deps = await horizontalVisibilityDependencies(slug, true)
  const claim = await claimDynamicBuild(
    slug,
    FARM_WATCH_HORIZONTAL_VISIBILITY_PRODUCT.key,
    deps.sourceSignature,
    workerId,
  )
  if (claim?.action === 'reuse') {
    return { action: 'reuse', materialization: await readHorizontalVisibilityState(slug) }
  }
  if (claim?.action !== 'build') return claim || { action: 'not_claimed' }
  return {
    action: 'build',
    build_id: claim.build_id,
    lease_token: claim.lease_token,
    input_signature_sha256: claim.input_signature_sha256,
    source_signature_sha256: claim.source_signature_sha256,
    source_signature: deps.sourceSignature,
    dependencies: {
      landscape_structure_artifact: deps.landscapeStructureArtifact,
      terrain_form_artifact: deps.terrainFormArtifact,
      landscape_domain_identity_sha256: deps.domainIdentity,
      landscape_structure_identity_sha256: deps.structureIdentity,
      landscape_structure_artifact_sha256: deps.structureArtifactSha256,
      terrain_form_identity_sha256: deps.terrainIdentity,
      terrain_form_artifact_sha256: deps.terrainArtifactSha256,
    },
  }
}

async function completeHorizontalVisibilityMaterialization(slug: string, body: any) {
  const buildId = validUuid(body?.build_id)
  const leaseToken = validUuid(body?.lease_token)
  const sampledSourceSha256 = validSha256(body?.sampled_source_sha256 || null)
  if (!buildId || !leaseToken || !sampledSourceSha256) throw new Error('invalid visibility completion identity')

  const build = await readMaterializationBuild(buildId)
  const deps = await horizontalVisibilityDependencies(slug, false)
  if (
    build.product_kind !== FARM_WATCH_HORIZONTAL_VISIBILITY_PRODUCT.productKind ||
    build.algorithm_version !== FARM_WATCH_HORIZONTAL_VISIBILITY_PRODUCT.algorithmVersion ||
    build.output_schema_version !== FARM_WATCH_HORIZONTAL_VISIBILITY_PRODUCT.outputSchemaVersion ||
    build.source_signature !== deps.sourceSignature ||
    build.status !== 'processing' ||
    String(build.lease_token) !== leaseToken
  ) throw new Error('horizontal visibility build lease is incompatible')

  const artifact = body?.artifact
  if (!validateHorizontalVisibilityArtifact(artifact)) {
    throw new Error('horizontal visibility artifact failed contract validation')
  }
  if (
    artifact?.domain?.identity_sha256 !== deps.domainIdentity ||
    artifact?.dependencies?.landscape_structure_identity_sha256 !== deps.structureIdentity ||
    artifact?.dependencies?.landscape_structure_artifact_sha256 !== deps.structureArtifactSha256 ||
    artifact?.dependencies?.terrain_form_identity_sha256 !== deps.terrainIdentity ||
    artifact?.dependencies?.terrain_form_artifact_sha256 !== deps.terrainArtifactSha256 ||
    artifact?.source_provenance?.source_signature !== deps.sourceSignature
  ) throw new Error('horizontal visibility artifact dependency identity is stale')

  await uploadNeutralPrimitive({
    claim: build,
    artifact,
    sampledSourceSha256,
    key: FARM_WATCH_HORIZONTAL_VISIBILITY_PRODUCT.key,
    sourceSignature: deps.sourceSignature,
    limitations: FARM_WATCH_HORIZONTAL_VISIBILITY_LIMITATIONS,
    refreshDays: FARM_WATCH_HORIZONTAL_VISIBILITY_PRODUCT.refreshDays,
    artifactPath: horizontalVisibilityArtifactPath,
    maxArtifactBytes: 25 * 1024 * 1024,
    storageEncoding: 'gzip',
  })
  return readHorizontalVisibilityState(slug)
}

async function failHorizontalVisibilityMaterialization(body: any) {
  const buildId = validUuid(body?.build_id)
  const leaseToken = validUuid(body?.lease_token)
  if (!buildId || !leaseToken) throw new Error('invalid visibility failure identity')
  const build = await readMaterializationBuild(buildId)
  if (
    build.product_kind !== FARM_WATCH_HORIZONTAL_VISIBILITY_PRODUCT.productKind ||
    String(build.lease_token) !== leaseToken ||
    build.status !== 'processing'
  ) throw new Error('horizontal visibility failure lease is incompatible')
  await failBuild(buildId, leaseToken, String(body?.error || 'horizontal visibility worker failed'))
  return { status: 'failed', build_id: buildId }
}

async function buildMaterialization(
  slug: string,
  key: ProductKey,
  workerId: string,
  solarDate: string | null = null,
  thermalAt: string | null = null,
) {
  if (key === FARM_WATCH_LIDAR_PHYSICAL_PRODUCT.key) {
    throw new Error('LiDAR physical materialization uses the dedicated GitHub OIDC worker')
  }
  if (key === FARM_WATCH_LEAF_OFF_PRODUCT.key) {
    throw new Error('Leaf-off materialization uses the dedicated GitHub OIDC worker')
  }
  if (key === FARM_WATCH_STRUCTURE_SYNTHESIS_PRODUCT.key) {
    throw new Error('Structure synthesis materialization uses the dedicated GitHub OIDC worker')
  }
  if (key === FARM_WATCH_LANDSCAPE_STRUCTURE_PRODUCT.key) {
    throw new Error('Landscape structure materialization uses the dedicated GitHub OIDC worker')
  }
  if (key === FARM_WATCH_TERRAIN_FORM_PRODUCT.key) {
    return buildTerrainFormMaterialization(slug, workerId)
  }
  if (key === FARM_WATCH_SPATIAL_PATTERN_PRODUCT.key) {
    return buildSpatialPatternMaterialization(slug, workerId)
  }
  if (key === FARM_WATCH_SOLAR_TERRAIN_PRODUCT.key) {
    return buildSolarTerrainMaterialization(slug, workerId)
  }
  if (key === FARM_WATCH_SOLAR_EXPOSURE_PRODUCT.key) {
    if (!solarDate) throw new Error('solar exposure date is required')
    return buildSolarExposureMaterialization(slug, solarDate, workerId)
  }
  if (key === FARM_WATCH_THERMAL_EXPOSURE_PRODUCT.key) {
    if (!thermalAt) throw new Error('thermal exposure timestamp is required')
    return buildThermalExposureMaterialization(slug, thermalAt, workerId)
  }
  if (key === FARM_WATCH_HORIZONTAL_VISIBILITY_PRODUCT.key) {
    throw new Error('horizontal visibility materialization uses the protected GitHub worker')
  }
  return key === FARM_WATCH_TERRAIN_PRODUCT.key
    ? buildTerrainMaterialization(slug, workerId)
    : buildLidarSourceMaterialization(slug, workerId)
}

async function readPayload(
  slug: string,
  key: ProductKey,
  state: any,
  knownSha256: string | null = null,
  presentationMode: 'full_artifact' | 'summary_only' = 'full_artifact',
) {
  const status = String(state?.status || 'missing')
  const materialization = state?.materialization || null
  const safeState = {
    status,
    identity: state?.identity || null,
    build: state?.build || null,
    materialization: materialization ? {
      id: materialization.id,
      identity_sha256: materialization.identity_sha256,
      evidence_class: materialization.evidence_class,
      summary: materialization.summary || {},
      source_provenance: materialization.source_provenance || {},
      limitations: materialization.limitations || [],
      artifact_format: materialization.artifact_format,
      artifact_size_bytes: materialization.artifact_size_bytes,
      artifact_sha256: materialization.artifact_sha256,
      completed_at: materialization.completed_at,
      expires_at: materialization.expires_at,
    } : null,
  }

  if (status !== 'available' || !materialization) {
    return {
      property: { slug },
      product: key,
      ...safeState,
      artifact: null,
      not_modified: false,
    }
  }

  if (presentationMode === 'summary_only') {
    return {
      property: { slug },
      product: key,
      ...safeState,
      artifact: null,
      not_modified: false,
      presentation: {
        mode: 'summary_only',
        artifact_withheld: true,
        map_rendering_allowed: false,
      },
    }
  }

  const artifactSha256 = validSha256(String(materialization.artifact_sha256 || ''))
  if (!artifactSha256) throw new Error('materialization artifact checksum is invalid')
  if (knownSha256 === artifactSha256) {
    return {
      property: { slug },
      product: key,
      ...safeState,
      artifact: null,
      not_modified: true,
    }
  }

  const { data: blob, error: downloadError } = await admin.storage
    .from(String(materialization.artifact_bucket))
    .download(String(materialization.artifact_path))
  if (downloadError || !blob) {
    throw new Error(`materialization artifact download failed: ${downloadError?.message || 'empty artifact'}`)
  }

  const storedBytes = new Uint8Array(await blob.arrayBuffer())
  const downloadedSha256 = await sha256Hex(storedBytes)
  if (downloadedSha256 !== artifactSha256) throw new Error('materialization artifact checksum mismatch')
  const bytes = materialization.artifact_format === FARM_WATCH_HORIZONTAL_VISIBILITY_PRODUCT.artifactFormat
    ? await gunzipBytes(storedBytes)
    : storedBytes

  let artifact: any
  try {
    artifact = JSON.parse(new TextDecoder().decode(bytes))
  } catch {
    throw new Error('materialization artifact JSON is invalid')
  }
  if (!validateArtifact(key, artifact)) throw new Error('materialization artifact is incompatible')

  return {
    property: { slug },
    product: key,
    ...safeState,
    artifact,
    not_modified: false,
  }
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get('origin') || ''
  if (origin && !ALLOWED_ORIGINS.has(origin)) return json({ error: 'not found' }, 404)
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: headers(origin) })

  if (req.method === 'POST') {
    let body: any = null
    try { body = await req.json() } catch { return json({ error: 'invalid request' }, 400, origin) }

    const workerToken = typeof body?.worker_token === 'string' ? body.worker_token : null
    let workerAllowed = false
    if (workerToken) {
      const { data, error } = await admin.rpc(
        'farm_watch_validate_materialization_worker_v1_internal',
        { p_token: workerToken },
      )
      if (error) console.error('Farm Watch materialization worker-token validation failed', error.message)
      workerAllowed = data === true
    }

    let oidcIdentity: any = null
    if (!workerAllowed) {
      const token = bearer(req)
      if (token) {
        try {
          const identity = await verifyFarmWatchGitHubActionsOidc(token)
          if (ALLOWED_MATERIALIZATION_WORKFLOW_REFS.has(identity?.workflow_ref)) {
            oidcIdentity = identity
          }
        } catch (error) {
          console.error('Farm Watch neutral-primitives GitHub OIDC rejected', error)
        }
      }
    }
    if (!workerAllowed && !oidcIdentity) return json({ error: 'not found' }, 404, origin)

    const slug = boundedSlug(typeof body?.property === 'string' ? body.property : null)
    const key = productKey(body?.product)
    const solarDate = boundedSolarDate(body?.date)
    const thermalAt = key === FARM_WATCH_THERMAL_EXPOSURE_PRODUCT.key
      ? boundedThermalAt(body?.at || new Date().toISOString())
      : boundedThermalAt(body?.at)
    if (!slug || !key) return json({ error: 'invalid request' }, 400, origin)
    if (key === FARM_WATCH_SOLAR_EXPOSURE_PRODUCT.key && !solarDate) {
      return json({ error: 'solar exposure date is required' }, 400, origin)
    }
    if (key === FARM_WATCH_THERMAL_EXPOSURE_PRODUCT.key && !thermalAt) {
      return json({ error: 'thermal exposure timestamp is invalid' }, 400, origin)
    }
    if (body?.date != null && !solarDate) {
      return json({ error: 'invalid solar date' }, 400, origin)
    }
    if (body?.at != null && !thermalAt) {
      return json({ error: 'invalid thermal timestamp' }, 400, origin)
    }

    try {
      const workerId = oidcIdentity
        ? [
            'github-actions-neutral-primitives',
            oidcIdentity.run_id || 'run',
            oidcIdentity.run_attempt || 'attempt',
          ].join(':')
        : 'farm-watch-materialization-edge-v2'
      if (key === FARM_WATCH_HORIZONTAL_VISIBILITY_PRODUCT.key && body?.operation === 'prepare') {
        return json(await prepareHorizontalVisibilityMaterialization(slug, workerId), 200, origin)
      }
      if (key === FARM_WATCH_HORIZONTAL_VISIBILITY_PRODUCT.key && body?.operation === 'complete') {
        return json(await completeHorizontalVisibilityMaterialization(slug, body), 200, origin)
      }
      if (key === FARM_WATCH_HORIZONTAL_VISIBILITY_PRODUCT.key && body?.operation === 'fail') {
        return json(await failHorizontalVisibilityMaterialization(body), 200, origin)
      }
      const operation = body?.operation === 'read' ? 'read' : 'build'
      const state = operation === 'read'
        ? await readState(slug, key, solarDate, thermalAt)
        : await buildMaterialization(
          slug,
          key,
          workerId,
          solarDate,
          thermalAt,
        )
      const knownSha256 = validSha256(
        typeof body?.known_artifact_sha256 === 'string'
          ? body.known_artifact_sha256.trim().toLowerCase()
          : null,
      )
      return json(await readPayload(slug, key, state, knownSha256), 200, origin)
    } catch (error) {
      console.error('Farm Watch materialization worker failed', key, error)
      const detail = oidcIdentity && error instanceof Error
        ? error.message.slice(0, 300)
        : null
      return json({
        error: 'materialization build failed',
        ...(detail ? { detail } : {}),
      }, 503, origin)
    }
  }

  if (req.method !== 'GET') return json({ error: 'not found' }, 404, origin)

  const token = bearer(req)
  if (!token) return json({ error: 'not found' }, 404, origin)

  const { data: userData, error: userError } = await admin.auth.getUser(token)
  const user = userData?.user
  if (userError || !user) return json({ error: 'not found' }, 404, origin)

  const { data: allowed, error: accessError } = await admin.rpc('farm_watch_authorize_user_v1_internal', {
    p_user_id: user.id,
  })
  if (accessError || allowed !== true) return json({ error: 'not found' }, 404, origin)

  const { data: accountRoleValue, error: accountRoleError } = await admin.rpc(
    'farm_watch_get_account_role_v1_internal',
    { p_user_id: user.id },
  )
  const accountRole = normalizeFarmWatchAccountRole(accountRoleValue)
  if (accountRoleError || !accountRole) {
    console.error(
      'farm_watch_get_account_role_v1_internal failed',
      accountRoleError?.message || 'role unavailable',
    )
    return json({ error: 'not found' }, 404, origin)
  }

  const url = new URL(req.url)
  const slug = boundedSlug(url.searchParams.get('property'))
  const key = productKey(url.searchParams.get('product') || FARM_WATCH_TERRAIN_PRODUCT.key)
  const dateParam = url.searchParams.get('date')
  const solarDate = boundedSolarDate(dateParam)
  const atParam = url.searchParams.get('at')
  const thermalAt = key === FARM_WATCH_THERMAL_EXPOSURE_PRODUCT.key
    ? boundedThermalAt(atParam || new Date().toISOString())
    : boundedThermalAt(atParam)
  if (!slug || !key) return json({ error: 'invalid request' }, 400, origin)
  if (key === FARM_WATCH_SOLAR_EXPOSURE_PRODUCT.key && !solarDate) {
    return json({ error: 'solar exposure date is required' }, 400, origin)
  }
  if (key === FARM_WATCH_THERMAL_EXPOSURE_PRODUCT.key && !thermalAt) {
    return json({ error: 'thermal exposure timestamp is invalid' }, 400, origin)
  }
  if (dateParam && !solarDate) return json({ error: 'invalid solar date' }, 400, origin)
  if (atParam && !thermalAt) return json({ error: 'invalid thermal timestamp' }, 400, origin)

  try {
    const state = await readState(slug, key, solarDate, thermalAt)
    const knownSha256 = validSha256(url.searchParams.get('known_artifact_sha256'))
    const presentationMode = materializationPresentationMode(accountRole, key)
    return json(
      await readPayload(slug, key, state, knownSha256, presentationMode),
      200,
      origin,
    )
  } catch (error) {
    console.error('Farm Watch materialization read failed', key, error)
    return json({ error: 'materialization unavailable' }, 503, origin)
  }
})
