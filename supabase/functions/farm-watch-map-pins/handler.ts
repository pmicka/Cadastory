// User annotations only. No scientific/materialization dependencies.
const ORIGINS = new Set(['https://pmicka.com', 'https://www.pmicka.com',
  'http://127.0.0.1:8000', 'http://localhost:8000'])
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const PIN_ICONS = new Set(['pin', 'deerstand', 'water_pump', 'container', 'trail_camera', 'gate', 'bonfire', 'crop'])
type Client = { auth: { getUser(token: string): Promise<any> }; rpc(name: string, args: any): PromiseLike<any> }

export function createMapPinsHandler(clientForToken: (token: string) => Client) {
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
          if (size > 16384) { await reader.cancel(); return respond({ error: 'input too large' }, 413) }
          chunks.push(value)
        }
        const bytes = new Uint8Array(size)
        let offset = 0
        for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length }
        let body: any
        try { body = JSON.parse(new TextDecoder().decode(bytes)) } catch { return respond({ error: 'invalid input' }, 400) }
        const fields = req.method === 'DELETE' ? ['id', 'revision']
          : req.method === 'POST' ? ['title', 'notes', 'longitude', 'latitude', 'color', 'icon']
          : ['id', 'revision', 'title', 'notes', 'longitude', 'latitude', 'color', 'icon']
        if (!body || Array.isArray(body) || typeof body !== 'object' ||
          Object.keys(body).some(key => !fields.includes(key))) return respond({ error: 'invalid input' }, 400)
        if (req.method !== 'POST') {
          if (!UUID.test(body.id) || !Number.isSafeInteger(body.revision) || body.revision < 1)
            return respond({ error: 'invalid input' }, 400)
          args.p_pin_id = body.id; args.p_expected_revision = body.revision
        }
        if (req.method !== 'DELETE') {
          if (typeof body.title !== 'string' || !body.title.trim() || [...body.title.trim()].length > 100 ||
            (body.notes != null && (typeof body.notes !== 'string' || [...body.notes].length > 2000)) ||
            !Number.isFinite(body.longitude) || Math.abs(body.longitude) > 180 ||
            !Number.isFinite(body.latitude) || Math.abs(body.latitude) > 90) return respond({ error: 'invalid input' }, 400)
          Object.assign(args, { p_title: body.title.trim(), p_notes: body.notes || null,
            p_longitude: body.longitude, p_latitude: body.latitude })
          if (Object.hasOwn(body, 'color')) {
            if (typeof body.color !== 'string' || body.color.length !== 7 || !/^#[0-9a-f]{6}$/i.test(body.color)) return respond({ error: 'invalid pin color' }, 400)
            args.p_color = body.color.toLowerCase()
          }
          if (Object.hasOwn(body, 'icon')) {
            if (typeof body.icon !== 'string' || !PIN_ICONS.has(body.icon)) return respond({ error: 'invalid pin icon' }, 400)
            args.p_icon = body.icon // The RPC enforces the account-specific grant.
          }
        }
      }
      const { data, error } = await client.rpc('farm_watch_map_pins_v1', args)
      if (error) {
        const status = error.code === '42501' ? 404 : error.code === 'PT409' ? 409
          : ['22023', '23514', '22P02'].includes(error.code) ? 400 : error.code === '54000' ? 409 : 503
        const message = status === 404 ? 'not found' : status === 409 ? 'Pin changed or property pin limit reached. Reload pins.'
          : status === 400 ? 'Use a title up to 100 characters, notes up to 2,000 characters, and a location inside or on the property boundary.'
          : 'Pins unavailable. Try again.'
        return respond({ error: message }, status)
      }
      return respond(data, req.method === 'POST' ? 201 : 200)
    } catch { return respond({ error: 'Pins unavailable. Try again.' }, 503) }
  }
}
