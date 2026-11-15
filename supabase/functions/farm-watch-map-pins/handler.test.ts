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

Deno.test('bounded categories persist independently of restricted icons and older clients omit category', async () => {
  const { request, calls } = fixture()
  for (const category of ['auto', 'general', 'hunting', 'farming-orchard']) {
    assert((await request('POST', { ...pin, category })).status === 201)
    assert(calls.at(-1).args.p_category === category)
    assert((await request('PATCH', { ...pin, id, revision: 1, category })).status === 200)
  }
  for (const category of [null, 1, {}, [], '', 'Hunting', 'water', '__proto__', '<svg/>'])
    assert((await request('POST', { ...pin, category })).status === 400)
  assert((await request('PATCH', { ...pin, id, revision: 1 })).status === 200)
  assert(!Object.hasOwn(calls.at(-1).args, 'p_category'))
  assert((await request('DELETE', { id, revision: 1, category:'hunting' })).status === 400)
  assert(calls.length === 9)
})

Deno.test('camera settings are bounded numbers, forwarded under the caller JWT; omissions preserve old clients', async () => {
  const { request, calls } = fixture()
  const camera = { camera_bearing_deg: 359, camera_range_m: 24.384, camera_fov_deg: 40 }
  assert((await request('POST', { ...pin, icon: 'trail_camera', ...camera })).status === 201)
  for (const [key, value] of Object.entries(camera)) assert(calls[0].args['p_'+key] === value)
  for (const [key, values] of Object.entries({ camera_bearing_deg: [-1,360,1.5],camera_range_m:[0,1.523,91.441],camera_fov_deg:[9,121,40.5] }))
    for (const value of [...values,null,'40',{},[]]) assert((await request('PATCH',{...pin,id,revision:1,...camera,[key]:value})).status === 400)
  assert((await request('DELETE', { id, revision:1, ...camera })).status === 400)
  assert((await request('PATCH', { ...pin, id, revision:1 })).status === 200)
  assert(!Object.hasOwn(calls.at(-1).args,'p_camera_bearing_deg'))
  assert(calls.length === 2)
})

Deno.test('successful pin deletion invokes photo cleanup; cleanup failure keeps the deletion successful',async()=>{
 let cleanups=0
 const handler=createMapPinsHandler(()=>({auth:{getUser:async()=>({data:{user:{id:'verified'}}})},rpc:async()=>({data:{deleted:true}})}),async()=>{cleanups++;throw Error('retry private cleanup')})
 const response=await handler(new Request('https://test.invalid?property=one',{method:'DELETE',headers:{authorization:'Bearer verified','content-type':'application/json'},body:JSON.stringify({id,revision:1})}))
 assert(response.status===200&&cleanups===1)
})

Deno.test('privacy is an optional strict boolean; same verified caller and RPC revision boundary', async () => {
  const { calls, request }=fixture()
  for (const method of ['POST','PATCH']) {
    const body={...pin,...(method==='PATCH'?{id,revision:3}:{})}
    for (const value of [true,false]) {
      assert((await request(method,{...body,is_private:value})).status===(method==='POST'?201:200))
      assert(calls.at(-1).args.p_is_private===value)
    }
    const before=calls.length
    for (const value of [null,'true',0,1,[],{}]) assert((await request(method,{...body,is_private:value})).status===400)
    assert(calls.length===before)
    assert((await request(method,body)).status===(method==='POST'?201:200))
    assert(!Object.hasOwn(calls.at(-1).args,'p_is_private'))
  }
  assert((await request('DELETE',{id,revision:3,is_private:true})).status===400)
})
