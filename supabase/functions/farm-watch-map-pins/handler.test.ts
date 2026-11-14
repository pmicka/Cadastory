import { createMapPinsHandler } from './handler.ts'
function assert(value: unknown, message = 'assertion failed'): asserts value { if (!value) throw new Error(message) }
const id = '00000000-0000-0000-0000-000000000001'
function fixture(errorCode?: string) {
  const calls: any[] = []
  const handler = createMapPinsHandler(token => {
    assert(token === 'verified' || token === 'invalid')
    return { auth: { getUser: async value => value === 'verified'
      ? { data: { user: { id } } } : { error: true } },
      rpc: async (name, args) => {
        calls.push({ name, args })
        return { data: { pins: [] }, error: errorCode ? { code: errorCode, message: 'private database detail' } : null }
      } }
  })
  const request = (method = 'GET', body?: any, token = 'verified', origin = 'https://pmicka.com') => handler(new Request(
    'https://test.invalid/functions/v1/farm-watch-map-pins?property=selected', {
      method, headers: { authorization: `Bearer ${token}`, origin, 'content-type': 'application/json' },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    }))
  return { calls, request, handler }
}
const pin = { title: 'My pin', notes: 'Plain text', longitude: -84.9, latitude: 38.2 }
Deno.test('verified user token and explicit property only; no supplied creator identity', async () => {
  const { calls, request } = fixture()
  assert((await request('POST', pin)).status === 201)
  assert(calls[0].name === 'farm_watch_map_pins_v1')
  assert(calls[0].args.p_property_slug === 'selected')
  assert(!Object.hasOwn(calls[0].args, 'p_user_id'))
  for (const key of ['created_by', 'property_id', 'geometry', 'created_at', 'updated_at'])
    assert((await request('POST', { ...pin, [key]: id })).status === 400)
  assert(calls.length === 1)
  assert((await request('GET', undefined, 'invalid')).status === 404)
  assert((await request('GET', undefined, 'verified', 'https://hostile.invalid')).status === 404)
  assert(calls.length === 1)
})
Deno.test('strict input bounds and finite numeric coordinates', async () => {
  const { calls, request } = fixture()
  for (const body of [null, [], { ...pin, title: '' }, { ...pin, title: 'x'.repeat(101) },
    { ...pin, notes: 'x'.repeat(2001) }, { ...pin, longitude: '1' }, { ...pin, longitude: 181 },
    { ...pin, latitude: 91 }, { ...pin, latitude: null }, { ...pin, geometry: {type:'LineString'} }])
    assert((await request('POST', body)).status === 400)
  assert((await request('POST', { ...pin, notes: 'x'.repeat(20000) })).status === 413)
  assert((await request('PATCH', pin)).status === 400)
  assert((await request('DELETE', { id, revision: 0 })).status === 400)
  assert(calls.length === 0)
})
Deno.test('bounded non-sensitive database error mapping and optimistic revision forwarding', async () => {
  for (const [code, status] of [['42501',404],['PT409',409],['22023',400],['XX000',503]] as const) {
    const { request, calls } = fixture(code)
    const response = await request('PATCH', { ...pin, id, revision: 2 })
    assert(response.status === status)
    assert(!(await response.text()).includes('private database detail'))
    assert(calls[0].args.p_expected_revision === 2)
  }
})
Deno.test('unauthenticated denial, CORS preflight, malformed JSON and method restriction', async () => {
  const { handler, calls } = fixture()
  const url = 'https://test.invalid/?property=selected'
  assert((await handler(new Request(url))).status === 404)
  assert((await handler(new Request(url,{method:'OPTIONS',headers:{origin:'https://pmicka.com'}}))).status === 204)
  assert((await handler(new Request(url,{method:'PUT'}))).status === 404)
  assert((await handler(new Request(url,{method:'POST',headers:{authorization:'Bearer verified'},body:'bad'}))).status === 400)
  assert(calls.length === 0)
})
