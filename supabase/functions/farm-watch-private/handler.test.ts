import { createPrivateHandler, hydroSourceQuery, HYDRO_SOURCES } from './handler.ts'
import { resolveFarmWatchExternalSourceIdentities } from '../_shared/farm-watch-external-source-identity.ts'
function assert(value: unknown, message = 'assertion failed'): asserts value {
  if (!value) throw new Error(message)
}
const boundary = { type: 'Polygon', coordinates: [[[0,0], [.001,0], [.001,.001], [0,.001], [0,0]]] }
function fixture(options: { allowed?: boolean; role?: string; property?: any; fail?: string; old?: boolean; oldDeep?: boolean; partialDeep?: boolean; hunting?: boolean; staleHunting?: boolean } = {}) {
  const calls: { name: string; args: any }[] = []
  const now = new Date().toISOString()
  const at = options.old ? '2000-01-01T00:00:00Z' : now
  let observations = 0
  const property = { id: 'private-property-id', slug: 'validation-property-01', display_name: 'Private fixture',
    center_geojson: { coordinates: [0,0] }, boundary_geojson: boundary, state_code: 'KY',
    metadata: { selected_parcel_id: 'private-parcel', other: 'x'.repeat(50000) } }
  const values: Record<string, any> = {
    farm_watch_authorize_user_v1_internal: options.allowed !== false,
    farm_watch_get_account_role_v1_internal: options.role || 'viewer',
    farm_watch_get_property_v1_internal: options.property === null ? null : property,
    farm_watch_get_access_features_v1_internal: { type: 'FeatureCollection', features: [] },
    farm_watch_get_operator_observations_v1_internal: [],
    farm_watch_get_soils_v1_internal: { status: 'available', feature_collection: { type: 'FeatureCollection', features: [{ type: 'Feature', geometry: boundary,
        properties: { musym: 'synthetic', deep_attribute_status: 'available', horizon_profile: [{ top_cm: 0 }], runoff_class: 'synthetic' } }] },
      summary: { identity_status: 'current', map_unit_count: 1, deep_profile_count: 1, retrieved_at: at, deep_retrieved_at: options.oldDeep ? '2000-01-01T00:00:00Z' : at } },
    farm_watch_get_hydrology_v1_internal: { status: 'available', feature_collection: { type: 'FeatureCollection', features: [] },
      summary: { identity_status: 'current', buffer_m: 3000, retrieved_at: at } },
    farm_watch_get_landscape_domain_v1_internal: { status: 'available', identity: 'canonical' },
    farm_watch_get_landscape_context_v1_internal: { status: 'available' },
    farm_watch_get_deer_evidence_stack_at_v1_internal: { status: 'stale', products: {} },
    farm_watch_resolve_deer_context_v1_internal: { status: 'available', diel_photoperiod: { status: 'available' } },
    farm_watch_resolve_deer_biological_state_v1_internal: { status: 'unavailable', context: null },
    farm_watch_get_diel_photoperiod_v1_internal: { status: 'available' },
  }
  if (options.hunting) {
    const today = { status: 'available', context: { events: { sunrise: '2026-11-13T12:23:00Z', sunset: '2026-11-13T22:24:00Z' } } }
    values.farm_watch_resolve_deer_context_v1_internal = { status: 'partial', as_of_date: '2026-11-13',
      diel_photoperiod: today, seasonal_state: { status: 'stale', context: 'x'.repeat(100000) },
      field_phenology: { status: 'stale', context: 'x'.repeat(100000) } }
    values.farm_watch_resolve_deer_biological_state_v1_internal = { status: 'available', context: {
      season: 'fall', diel: { solar_phase: 'day' }, regional_reproductive_context: { phase: 'regional', peak_timing_label: 'mid-November' },
      individual_reproductive_state: 'unknown', unused_diagnostics: 'x'.repeat(100000) } }
    values.farm_watch_get_diel_photoperiod_v1_internal = today
    values.farm_watch_get_regulatory_local_v1_internal = { as_of_date: '2026-11-13', hunting: {
      jurisdiction: 'KY', deer_management: { deer_zone: '1' },
      active_seasons: [{ season_name: 'Archery', legal_hours: '30 minutes before sunrise to 30 minutes after sunset' }],
      upcoming_seasons: [], drone_wildlife_rules: [],
    }, protected_lands: 'x'.repeat(100000) }
  }
  if (options.staleHunting) {
    values.farm_watch_resolve_deer_context_v1_internal.diel_photoperiod.status = 'stale'
    values.farm_watch_resolve_deer_biological_state_v1_internal.status = 'stale'
  }
  if (options.partialDeep) {
    const soils = values.farm_watch_get_soils_v1_internal
    soils.summary.map_unit_count = 2
    soils.feature_collection.features.push({ type: 'Feature', geometry: boundary,
      properties: { musym: 'missing-profile', deep_attribute_status: 'unavailable' } })
  }
  const handler = createPrivateHandler({
    auth: { getUser: async (token: string) => token === 'valid-token'
      ? { data: { user: { id: 'private-user-id' } }, error: null } : { data: {}, error: true } },
    rpc: async (name: string, args: any) => {
      calls.push({ name, args })
      return { data: Object.hasOwn(values, name) ? values[name] : { status: 'unavailable' }, error: name === options.fail ? { message: 'Unavailable' } : null }
    },
  }, { readWeather: async (center: any) => {
    calls.push({ name: 'weather_reader', args: center })
    return { status: 'available', kind: 'forecast', current: { temperature: 54 } }
  }, resolveExternal: async () => {
    ++observations
    return { overrides: { 'external:test': { status: 'unavailable', authoritative: false } },
      observations: [{ key: 'external:test', status: 'unavailable', authoritative: false }] } as any
  } })
  const request = (context: string, token: string | null = 'valid-token') => handler(new Request(
    `https://example.test/?context=${context}`, { headers: token ? { authorization: `Bearer ${token}` } : {} }))
  return { request, calls, observed: () => observations }
}
Deno.test('bootstrap requires valid session, allowlist, role and active property', async () => {
  for (const options of [{ allowed: false }, { role: 'unknown' }, { property: null }]) {
    const f = fixture(options)
    const response = await f.request('bootstrap')
    assert(response.status === 404)
    assert(!JSON.stringify(await response.json()).includes('Private fixture'))
    assert(f.observed() === 0)
  }
  const f = fixture()
  assert((await f.request('bootstrap', null)).status === 404)
  assert((await f.request('bootstrap', 'invalid-token')).status === 404)
  assert(f.calls.length === 0)
})
Deno.test('bootstrap exposes server role/capabilities and minimal property only for every supported role', async () => {
  for (const role of ['owner', 'admin', 'viewer']) {
    const f = fixture({ role })
    const response = await f.request('bootstrap')
    assert(response.status === 200)
    const text = await response.text(), body = JSON.parse(text)
    assert(body.access.account_role === role)
    assert(body.access.capabilities.presentation_profile === (role === 'viewer' ? 'guided' : 'technical'))
    assert(body.access.capabilities.qa_controls === (role !== 'viewer'))
    assert(body.property.id === 'private-property-id' && body.property.metadata.other === undefined)
    assert(!body.analysis && !body.deer_evidence_stack && !body.deer_science_context)
    assert(text.length < 2000 && f.calls.length === 3 && f.observed() === 0)
    assert(response.headers.get('cache-control')?.includes('no-store'))
    assert(response.headers.get('server-timing')?.includes('session_validation'))
    assert(!response.headers.get('server-timing')?.includes('private-'))
  }
})
Deno.test('map references never read analytical resources or refresh', async () => {
  const f = fixture()
  const response = await f.request('map')
  assert(response.status === 200)
  const body = await response.json()
  assert(body.analysis.access_features_status === 'available')
  assert(f.calls.length === 5 && f.observed() === 0)
  assert(!f.calls.some(c => /refresh|soils|hydrology|landscape|evidence/.test(c.name)))
})
Deno.test('expired physical context remains stale, with no map features or synchronous maintenance', async () => {
  const f = fixture({ old: true })
  const body = await (await f.request('physical')).json()
  assert(body.analysis.soils_status === 'stale')
  assert(body.analysis.hydrology_status === 'stale')
  assert(body.analysis.landscape_context_status === 'stale')
  assert(body.analysis.soils_geojson.features.length === 0 && body.analysis.hydrology_geojson.features.length === 0)
  assert(!f.calls.some(c => /refresh|replace/.test(c.name)))
  assert(f.observed() === 0)
})
Deno.test('one unavailable physical resource does not suppress independent resources', async () => {
  const f = fixture({ fail: 'farm_watch_get_soils_v1_internal' })
  const body = await (await f.request('physical')).json()
  assert(body.analysis.soils_status === 'unavailable')
  assert(body.analysis.hydrology_status === 'available')
  assert(body.analysis.landscape_context_status === 'available')
})
Deno.test('deer reader observes providers once and passes unavailable identities to canonical reader', async () => {
  const f = fixture()
  const body = await (await f.request('deer')).json()
  assert(f.observed() === 1)
  const read = f.calls.find(c => c.name === 'farm_watch_get_deer_evidence_stack_at_v1_internal')
  assert(read?.args.p_dependency_overrides['external:test'].status === 'unavailable')
  assert(body.deer_evidence_stack.status === 'stale')
  assert(body.deer_evidence_stack.external_source_observations[0].authoritative === false)
  assert(body.deer_science_context && !body.analysis)
  assert(!f.calls.some(c => /soils|access_features|operator_observations/.test(c.name)))
})
Deno.test('scoped and legacy science assembly retain identical results at the same scenario time', async () => {
  const scoped = fixture(), full = fixture()
  const a = await (await scoped.request('deer&at=2026-11-13T12:00:00Z')).json()
  const b = await (await full.request('full&at=2026-11-13T12:00:00Z')).json()
  for (const key of ['deer_context', 'hunting_daylight_planning', 'deer_evidence_stack', 'deer_science_context']) {
    assert(JSON.stringify(a[key]) === JSON.stringify(b[key]), key + ' changed')
  }
})
Deno.test('authoritative resolver fails closed when an upstream provider is unavailable', async () => {
  const observed: string[] = []
  const rows = await resolveFarmWatchExternalSourceIdentities({ boundary,
    dependencyKeys: ['external:fia-bigmap-2018-species-biomass'], requireAll: false,
    fetchImpl: (() => Promise.resolve(new Response('', { status: 503 }))) as typeof fetch,
    onTiming: key => observed.push(key),
  })
  assert(rows.length === 1 && rows[0].status !== 'available' && !rows[0].authoritative)
  assert(observed.length === 1)
})

Deno.test('explicit refresh reuses maintenance and is server restricted to owner/admin', async () => {
  assert((await fixture().request('refresh')).status === 404)
  for (const role of ['owner', 'admin']) {
    const f = fixture({ role })
    const response = await f.request('refresh')
    assert(response.status === 200)
    const body = await response.json()
    assert(body.analysis && !body.deer_context && f.observed() === 0)
  }
})

Deno.test('expired deep soil profiles do not relabel current map units or expose stale deep measurements', async () => {
  const f = fixture({ oldDeep: true })
  const body = await (await f.request('physical')).json()
  assert(body.analysis.soils_status === 'available')
  assert(body.analysis.soils_summary.deep_status === 'stale')
  assert(body.analysis.soils_summary.deep_profile_count === 0)
  const properties = body.analysis.soils_geojson.features[0].properties
  assert(properties.musym === 'synthetic' && properties.deep_attribute_status === 'stale')
  assert(!properties.horizon_profile && !properties.runoff_class)
})

Deno.test('fresh partial deep-profile coverage preserves current profiles and individual unavailable states', async () => {
  const body = await (await fixture({ partialDeep: true }).request('physical')).json()
  const analysis = body.analysis
  assert(analysis.soils_status === 'available')
  assert(analysis.soils_summary.deep_profile_count === 1 && analysis.soils_summary.deep_status === 'partial')
  const [current, missing] = analysis.soils_geojson.features.map((f: any) => f.properties)
  assert(current.deep_attribute_status === 'available' && current.horizon_profile.length === 1)
  assert(current.runoff_class === 'synthetic' && missing.deep_attribute_status === 'unavailable')
})
Deno.test('expired partial coverage withholds expired measurements without rewriting unavailable profiles', async () => {
  const body = await (await fixture({ partialDeep: true, oldDeep: true }).request('physical')).json()
  const [expired, missing] = body.analysis.soils_geojson.features.map((f: any) => f.properties)
  assert(body.analysis.soils_summary.deep_status === 'stale')
  assert(expired.deep_attribute_status === 'stale' && !expired.horizon_profile)
  assert(missing.deep_attribute_status === 'unavailable')
})

Deno.test('guided hunting reference is compact and independent of external/evidence/physical dependencies', async () => {
  for (const role of ['viewer', 'owner', 'admin']) {
    const f = fixture({ hunting: true, role })
    const response = await f.request('hunting&at=2026-11-13T12:00:00Z')
    const text = await response.text(), body = JSON.parse(text)
    assert(response.status === 200 && text.length < 5000)
    assert(body.hunting_reference.status === 'available')
    // The raw full-context status remains partial; stale hidden datasets do not redefine visible timing freshness.
    assert(body.hunting_reference.deer_context.status === 'partial')
    assert(body.hunting_reference.deer_context.deer_biological_state.context.season === 'fall')
    assert(body.hunting_reference.hunting_daylight_planning.days[0].diel_photoperiod.context.events.sunrise === '2026-11-13T12:23:00Z')
    assert(!text.includes('unused_diagnostics') && !text.includes('field_phenology') && !text.includes('deer_evidence_stack'))
    assert(f.observed() === 0)
    assert(!f.calls.some(c => /evidence|hydrology|landscape|soils/.test(c.name)))
  }
})
Deno.test('hunting route enforces authorization and keeps unavailable biological context partial', async () => {
  assert((await fixture({ allowed: false }).request('hunting')).status === 404)
  const body = await (await fixture().request('hunting')).json()
  assert(body.hunting_reference.status === 'partial')
  assert(body.hunting_reference.deer_context.deer_biological_state.status === 'unavailable')
})

Deno.test('stale retained hunting clocks and biological context are withheld from guided reference', async () => {
  const body = await (await fixture({ hunting: true, staleHunting: true }).request('hunting')).json()
  const reference = body.hunting_reference
  assert(reference.status === 'stale')
  assert(reference.deer_context.deer_biological_state.status === 'stale')
  assert(reference.deer_context.deer_biological_state.context === null)
  assert(reference.hunting_daylight_planning.days[0].diel_photoperiod.status === 'stale')
  assert(reference.hunting_daylight_planning.days[0].diel_photoperiod.context === null)
})

Deno.test('hunting rules use canonical normalized local authority without FAA or scientific-source calls', async () => {
  const f = fixture({ hunting: true })
  const response = await f.request('rules')
  const text = await response.text(), body = JSON.parse(text)
  assert(response.status === 200 && text.length < 3000)
  assert(body.hunting_rules.static.status === 'available')
  assert(body.hunting_rules.static.context.hunting.active_seasons[0].season_name === 'Archery')
  assert(!text.includes('protected_lands') && f.observed() === 0)
  assert(f.calls.length === 4 && f.calls[3].name === 'farm_watch_get_regulatory_local_v1_internal')
  assert((await fixture({ allowed: false }).request('rules')).status === 404)
})
Deno.test('unavailable normalized hunting rules do not become a known empty season schedule', async () => {
  const f = fixture({ hunting: true, fail: 'farm_watch_get_regulatory_local_v1_internal' })
  const body = await (await f.request('rules')).json()
  assert(body.hunting_rules.static.status === 'unavailable')
  assert(!body.hunting_rules.static.context.hunting)
})

Deno.test('weather is independently authorized and never invokes analytical dependencies', async () => {
  for (const role of ['owner', 'admin', 'viewer']) {
    const f = fixture({ role })
    const response = await f.request('weather')
    const data = await response.json()
    assert(response.status === 200 && data.weather.kind === 'forecast')
    assert(f.calls.length === 4 && f.calls.at(-1)?.name === 'weather_reader')
    assert(f.observed() === 0)
  }
  for (const options of [{ allowed: false }, { role: 'unknown' }, { property: null }]) {
    const f = fixture(options)
    assert((await f.request('weather')).status === 404)
    assert(!f.calls.some(call => call.name === 'weather_reader'))
  }
  const f = fixture()
  assert((await f.request('weather', null)).status === 404)
  assert((await f.request('weather', 'invalid-token')).status === 404)
  assert(f.calls.length === 0)
})

Deno.test('USGS flowline query uses the published Flowline schema and preserves spatial selection', () => {
  // Recorded provider field names from the live 3DHP Flowline /50 metadata.
  const fields = new Set(['OBJECTID', 'id3dhp', 'gnisidlabel', 'featuretypelabel', 'lengthkm', 'flowdirectionlabel', 'streamorder'])
  const source = HYDRO_SOURCES.find(source => source.key === 'flowline')!
  const url = hydroSourceQuery(source, { west: -84.91, south: 38.19, east: -84.89, north: 38.21 })
  for (const field of url.searchParams.get('outFields')!.split(',')) assert(fields.has(field), 'unsupported USGS field: ' + field)
  assert(url.searchParams.get('f') === 'geojson')
  assert(url.searchParams.get('spatialRel') === 'esriSpatialRelIntersects')
  assert(url.searchParams.get('inSR') === '4326' && url.searchParams.get('outSR') === '4326')
  assert(url.searchParams.get('geometry') === '-84.91,38.19,-84.89,38.21')
})
