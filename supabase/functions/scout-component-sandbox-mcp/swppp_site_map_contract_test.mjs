import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const directory = new URL('./', import.meta.url)
const [migration, locationCorrection, mapContract, serverSource, viewSource] = await Promise.all([
  readFile(new URL('../../migrations/20260912145117_add_component_sandbox_swppp_site_map_v1.sql', directory), 'utf8'),
  readFile(new URL('../../migrations/20260912145346_correct_component_sandbox_swppp_site_location_label.sql', directory), 'utf8'),
  readFile(new URL('MAP_CONTRACT.md', directory), 'utf8'),
  readFile(new URL('index.ts', directory), 'utf8'),
  readFile(new URL('view.ts', directory), 'utf8'),
])

assert.ok(migration.includes('scout_get_component_sandbox_swppp_site_map_v1_internal'))
assert.ok(migration.includes("'contract_version', 'swppp_site_map_v1'"))
assert.ok(migration.includes("'opportunity_type', 'swppp_site'"))
assert.ok(migration.includes("e.source_native_id = 'ohio-epa:1GC10896*AG'"))
assert.ok(migration.includes("e.registry_id = 'OHGC18548'"))
assert.ok(migration.includes("e.permit_status_desc = 'ACTIVE'"))
assert.ok(migration.includes("e.storm_water_area_acres = 135"))
assert.ok(migration.includes("extensions.st_geometrytype(e.location::extensions.geometry) = 'ST_Point'"))
assert.ok(migration.includes("'semantics', 'authoritative_permit_location_point'"))
assert.ok(migration.includes("'classification', 'unresolved'"))
assert.ok(migration.includes('not proof of an active procurement opportunity'))
assert.ok(migration.includes('not a project boundary'))
assert.ok(migration.includes('revoke all on function public.scout_get_component_sandbox_swppp_site_map_v1_internal() from public'))
assert.ok(migration.includes('grant execute on function public.scout_get_component_sandbox_swppp_site_map_v1_internal() to service_role'))
assert.ok(locationCorrection.includes("pg_catalog.concat(t.attributes ->> 'county', ' County, Ohio')"))
assert.ok(locationCorrection.includes('scout_get_component_sandbox_swppp_site_map_v1_internal'))

assert.ok(mapContract.includes('SWPPP-site bounded data contract'))
assert.ok(mapContract.includes('HAM-Brent Spence Project (PID 116649)'))
assert.ok(mapContract.includes('isolated database groundwork only'))
assert.ok(mapContract.includes('must not fabricate a project polygon'))

// Batch C must not change the live sandbox tool or View.
assert.equal(serverSource.includes('scout_get_component_sandbox_swppp_site_map_v1_internal'), false)
assert.equal(viewSource.includes("opportunityType === 'swppp_site'"), false)

console.log('Scout SWPPP-site isolated database contract checks passed.')
