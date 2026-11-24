// User annotations only. No scientific/materialization dependencies.
const ORIGINS = new Set(['https://pmicka.com', 'https://www.pmicka.com',
  'http://127.0.0.1:8000', 'http://localhost:8000'])
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const PIN_ICONS = new Set(['pin', 'dot', 'deerstand', 'water_pump', 'container', 'trail_camera', 'gate', 'bonfire', 'crop', 'corn_feeder', 'salt_mineral_block', 'tree', 'pop_up_blind', 'ladder_stand', 'sprout', 'sapling', 'ear_of_corn', 'wheat', 'blackberry', 'acorn'])
const PIN_CATEGORIES = new Set(['auto', 'general', 'hunting', 'farming-orchard'])
type Client = {
  auth: { getUser(token: string): Promise<{ data?: { user: { id: string; is_anonymous?: boolean } | null }; error?: unknown }> }
  rpc(name: string, args: Record<string, unknown>): PromiseLike<{ data?: unknown; error?: { code: string } | null }>
}
const PIN_WRITE_FIELDS = [
  'title', 'notes', 'longitude', 'latitude', 'color', 'icon', 'category', 'is_private',
  'camera_bearing_deg', 'camera_range_m', 'camera_fov_deg', 'specialized_views', 'agriculture', 'planting_group_id',
]
function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value)
}

export function createMapPinsHandler(clientForToken: (token: string) => Client, cleanup: () => Promise<void> = async () => {}) {
  return async (req: Request): Promise<Response> => {
    const origin = req.headers.get('origin') || ''
    const headers: Record<string, string> = { 'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store, max-age=0', 'x-content-type-options': 'nosniff', 'referrer-policy': 'no-referrer',
      vary: 'Origin' }
    if (ORIGINS.has(origin)) Object.assign(headers, { 'access-control-allow-origin': origin,
      'access-control-allow-methods': 'GET, POST, PATCH, DELETE, OPTIONS',
      'access-control-allow-headers': 'authorization, apikey, content-type' })
    const respond = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers })
    if (origin && !ORIGINS.has(origin)) return respond({ error: 'not found' }, 404)
    if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers })
    if (!['GET', 'POST', 'PATCH', 'DELETE'].includes(req.method)) return respond({ error: 'not found' }, 404)
    const token = req.headers.get('authorization')?.match(/^Bearer (\S+)$/i)?.[1]
    if (!token) return respond({ error: 'not found' }, 404)
    try {
      // The RPC is invoked with this SAME user JWT, never a service credential.
      // Its auth.uid() and allowlist checks remain authoritative even for direct RPC callers.
      const client = clientForToken(token)
      const { data: auth, error: authError } = await client.auth.getUser(token)
      if (authError || !auth?.user || auth.user.is_anonymous) return respond({ error: 'not found' }, 404)
      const url = new URL(req.url)
      const property = url.searchParams.get('property') || ''
      if (!/^[a-z0-9][a-z0-9-]{0,79}$/.test(property)) return respond({ error: 'invalid property' }, 400)
      const args: Record<string, unknown> = { p_property_slug: property,
        p_action: ({ GET: 'list', POST: 'create', PATCH: 'update', DELETE: 'delete' } as Record<string,string>)[req.method] }
      if (req.method !== 'GET') {
        // Bound bodies before JSON parsing, including requests without Content-Length.
        const reader = req.body?.getReader()
        if (!reader) return respond({ error: 'invalid input' }, 400)
        const chunks: Uint8Array[] = []
        let size = 0
        while (true) {
          const { done, value } = await reader.read()
          if (done) break
          size += value.byteLength
          if (size > 32768) { await reader.cancel(); return respond({ error: 'input too large' }, 413) }
          chunks.push(value)
        }
        const bytes = new Uint8Array(size)
        let offset = 0
        for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length }
        let body: unknown
        try { body = JSON.parse(new TextDecoder().decode(bytes)) } catch { return respond({ error: 'invalid input' }, 400) }
        const fields = req.method === 'DELETE' ? ['id', 'revision']
          : req.method === 'POST' ? PIN_WRITE_FIELDS : ['id', 'revision', ...PIN_WRITE_FIELDS]
        if (!isRecord(body) || Object.keys(body).some(key => !fields.includes(key))) {
          return respond({ error: 'invalid input' }, 400)
        }
        if (req.method !== 'POST') {
          if (typeof body.id !== 'string' || !UUID.test(body.id) || typeof body.revision !== 'number' || !Number.isSafeInteger(body.revision) || body.revision < 1)
            return respond({ error: 'invalid input' }, 400)
          args.p_pin_id = body.id; args.p_expected_revision = body.revision
        }
        if (req.method !== 'DELETE') {
          if (typeof body.title !== 'string' || !body.title.trim() || [...body.title.trim()].length > 100 ||
            (body.notes != null && (typeof body.notes !== 'string' || [...body.notes].length > 2000)) ||
            typeof body.longitude !== 'number' || !Number.isFinite(body.longitude) || Math.abs(body.longitude) > 180 ||
            typeof body.latitude !== 'number' || !Number.isFinite(body.latitude) || Math.abs(body.latitude) > 90) return respond({ error: 'invalid input' }, 400)
          Object.assign(args, { p_title: body.title.trim(), p_notes: body.notes || null,
            p_longitude: body.longitude, p_latitude: body.latitude })
          if (Object.hasOwn(body, 'is_private')) {
            if (typeof body.is_private !== 'boolean') return respond({ error: 'invalid pin visibility' }, 400)
            args.p_is_private = body.is_private
          }
          if (Object.hasOwn(body, 'color')) {
            if (typeof body.color !== 'string' || body.color.length !== 7 || !/^#[0-9a-f]{6}$/i.test(body.color)) return respond({ error: 'invalid pin color' }, 400)
            args.p_color = body.color.toLowerCase()
          }
          for (const [field,minimum,maximum,integer] of [
            ['camera_bearing_deg',0,359,true],['camera_range_m',1.524,91.44,false],['camera_fov_deg',10,120,true],
          ] as const) {
            if (!Object.hasOwn(body,field)) continue
            const value = body[field]
            if (typeof value !== 'number' || !Number.isFinite(value) || value < minimum || value > maximum || (integer && !Number.isInteger(value)))
              return respond({ error: 'invalid camera view' },400)
            args['p_'+field] = value
          }
          if (Object.hasOwn(body, 'category')) {
            if (typeof body.category !== 'string' || !PIN_CATEGORIES.has(body.category)) return respond({ error: 'invalid pin category' }, 400)
            args.p_category = body.category
          }
          if (Object.hasOwn(body, 'specialized_views')) {
            if (!Array.isArray(body.specialized_views) || body.specialized_views.length > 2 ||
              body.specialized_views.some((view: unknown) => view !== 'hunting' && view !== 'farming-orchard') ||
              new Set(body.specialized_views).size !== body.specialized_views.length) {
              return respond({ error: 'Invalid map visibility.' }, 400)
            }
            args.p_specialized_views = body.specialized_views
          }
          if (Object.hasOwn(body, 'agriculture')) {
            if (!isRecord(body.agriculture)) {
              return respond({ error: 'Invalid planting details.' }, 400)
            }
            args.p_agriculture = body.agriculture
          }
          if (Object.hasOwn(body, 'planting_group_id')) {
            if (body.planting_group_id !== null &&
              (typeof body.planting_group_id !== 'string' || !UUID.test(body.planting_group_id))) {
              return respond({ error: 'Invalid growing area.' }, 400)
            }
            args.p_group_id = body.planting_group_id
            args.p_set_group = true
          }
          if (Object.hasOwn(body, 'icon')) {
            if (typeof body.icon !== 'string' || !PIN_ICONS.has(body.icon)) return respond({ error: 'invalid pin icon' }, 400)
            args.p_icon = body.icon // The RPC enforces the account-specific grant.
          }
        }
      }
      const { data, error } = await client.rpc('farm_watch_map_pins_v2', args)
      if (error) {
        const status = error.code === '42501' ? 404 : error.code === 'PT409' ? 409
          : ['22023', '23514', '22P02'].includes(error.code) ? 400 : error.code === '54000' ? 409 : 503
        const message = status === 404 ? 'not found' : status === 409 ? 'Pin changed or property pin limit reached. Reload pins.'
          : status === 400 && ['p_agriculture','p_specialized_views','p_set_group'].some(key => Object.hasOwn(args,key))
          ? 'Check planting details, map visibility, and location, then try again.'
          : status === 400 ? 'Use a title up to 100 characters, notes up to 2,000 characters, and a location on the property or within 100 ft of its boundary.'
          : 'Pins unavailable. Try again.'
        return respond({ error: message }, status)
      }
      if (req.method === 'DELETE') { try { await cleanup() } catch { /* Private outbox retains retries. */ } }
      return respond(data, req.method === 'POST' ? 201 : 200)
    } catch { return respond({ error: 'Pins unavailable. Try again.' }, 503) }
  }
}
