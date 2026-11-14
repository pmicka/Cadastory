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
Deno.test('hex colors normalize; omitted color stays compatible; malformed colors never reach SQL', async () => {
  const { request, calls } = fixture()
  assert((await request('POST', { ...pin, color: '#A1B2C3' })).status === 201)
  assert(calls[0].args.p_color === '#a1b2c3')
  assert((await request('PATCH', { ...pin, id, revision: 1 })).status === 200)
  assert(!Object.hasOwn(calls[1].args, 'p_color'), 'old clients must preserve stored color')
  for (const color of [null, 1, {}, '#fff', '#11223344', '#2463eb\n', 'red', 'var(--color)', '#000000;fill:red'])
    assert((await request('POST', { ...pin, color })).status === 400)
  assert(calls.length === 2)
})

Deno.test('only named icon values are forwarded; old clients omit icon without losing it', async () => {
  const { request, calls } = fixture()
  for (const icon of ['pin','deerstand','water_pump','container','trail_camera','gate','bonfire','crop','corn_feeder','salt_mineral_block','tree','pop_up_blind','ladder_stand']) {
    assert((await request('POST', { ...pin, icon })).status === 201)
    assert(calls.at(-1).args.p_icon === icon)
  }
  for (const icon of [null, 1, {}, 'Deerstand', 'feeder', '__proto__', '<svg onload=alert(1)>'])
    assert((await request('POST', { ...pin, icon })).status === 400)
  assert((await request('PATCH', { ...pin, id, revision: 1 })).status === 200)
  assert(!Object.hasOwn(calls.at(-1).args, 'p_icon'))
  assert(calls.length === 14)
})
Deno.test('account grant denials come from the authoritative database boundary', async () => {
  const { request, calls } = fixture('42501')
  assert((await request('POST', { ...pin, icon:'gate' })).status === 404)
  assert(calls[0].args.p_icon === 'gate')
  assert((await request('POST', { ...pin, icon:'gate', can_use_pin_icons:true })).status === 400)
  assert(calls.length === 1)
})
