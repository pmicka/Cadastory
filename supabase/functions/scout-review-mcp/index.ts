import 'jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts'

// Improve Scout is intentionally parked by product decision.
//
// Keep the public function slug reserved so existing gateway topology and old
// clients fail closed instead of accidentally resolving to another surface.
// The previous implementation remains recoverable from Git history. Bringing
// it back requires an explicit code/deployment change; catalog visibility or
// routing metadata alone cannot reactivate it.

const headers = {
  'access-control-allow-origin': '*',
  'access-control-allow-headers': 'authorization,content-type,accept,mcp-protocol-version,mcp-session-id,x-request-id,last-event-id',
  'access-control-allow-methods': 'GET,POST,DELETE,OPTIONS',
  'cache-control': 'no-store, max-age=0',
  'pragma': 'no-cache',
  'referrer-policy': 'no-referrer',
  'x-content-type-options': 'nosniff',
  'content-type': 'application/json; charset=utf-8',
}

Deno.serve((req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers })
  return new Response(JSON.stringify({
    error: 'feature_inactive',
    feature: 'Improve Scout',
    status: 'paused',
  }), { status: 404, headers })
})
