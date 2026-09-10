import 'jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.115.0'
import { createMcpHandler, McpServer } from 'npm:@modelcontextprotocol/server@2.0.0'
import { registerAppResource, registerAppTool, RESOURCE_MIME_TYPE } from 'npm:@modelcontextprotocol/ext-apps@2.0.0/server'
import * as z from 'npm:zod@4.2.0/v4'

const SUPABASE_URL=Deno.env.get('SUPABASE_URL')!
let SERVICE_KEY=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')||''
try{const keys=JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS')||'{}');SERVICE_KEY=keys.default||SERVICE_KEY}catch{}
if(!SERVICE_KEY)throw new Error('Scout component sandbox service credential is unavailable')
const admin=createClient(SUPABASE_URL,SERVICE_KEY,{auth:{persistSession:false,autoRefreshToken:false}})

const RESOURCE_URI='ui://scout/component-sandbox/mcp-handshake-smoke-v1'
const TOOL_NAME='scout_preview_component_sandbox'
const MCP_APP_SDK_ORIGIN='https://unpkg.com'

async function authenticateOwner(req:Request){
  const match=(req.headers.get('authorization')||'').match(/^Bearer\s+(.+)$/i)
  if(!match)return null
  const {data:userResult,error:userError}=await admin.auth.getUser(match[1].trim())
  const user=userResult.user
  if(userError||!user?.id)return null
  const {data:owner,error:ownerError}=await admin.rpc('scout_is_owner_user_internal',{p_user_id:user.id})
  if(ownerError||owner!==true)return null
  return user
}

const VIEW_HTML=String.raw`<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Scout MCP handshake smoke test</title>
<style>
:root{font-family:ui-sans-serif,system-ui,sans-serif;color-scheme:light dark}html,body{margin:0;padding:0;background:transparent}body{padding:16px}.card{border:1px solid rgba(127,127,127,.35);border-radius:16px;padding:18px;background:light-dark(#fff,#1c1f1c);color:light-dark(#171b17,#f2f5f1)}h1{font-size:18px;margin:0 0 8px}.status{font-size:13px;line-height:1.45}.detail{font-size:11px;opacity:.7;margin-top:8px;word-break:break-word}
</style>
</head>
<body>
<main class="card">
<h1>Scout MCP App smoke test</h1>
<div class="status" id="status">HTML resource rendered. Connecting to host…</div>
<div class="detail" id="detail">If this text is visible, resource rendering works even before the MCP App handshake completes.</div>
</main>
<script type="module">
const status=document.getElementById('status'),detail=document.getElementById('detail');
try{
  const mod=await import('https://unpkg.com/@modelcontextprotocol/ext-apps@2.0.0/app-with-deps');
  status.textContent='MCP Apps SDK loaded. Connecting to host…';
  const app=new mod.App({name:'Scout MCP Handshake Smoke Test',version:'1.0.0'},{},{autoResize:false,strict:true});
  app.ontoolresult=(result)=>{detail.textContent='Tool result received through MCP Apps lifecycle.'};
  await app.connect();
  status.textContent='MCP App handshake connected.';
}catch(error){
  status.textContent='MCP App handshake failed.';
  detail.textContent=String(error?.message||error||'Unknown handshake error');
  console.error('Scout MCP App handshake smoke test failed',error);
}
</script>
</body>
</html>`

function makeServer(){
  const server=new McpServer({name:'Scout Component Sandbox Handshake Smoke Test',version:'1.0.0'})
  registerAppTool(server,TOOL_NAME,{
    title:'Preview Scout Component Sandbox',
    description:'Owner-only protocol smoke test for the Scout component sandbox. This intentionally renders no business data and tests only MCP Apps resource rendering and the View-to-Host initialization handshake.',
    inputSchema:z.object({}),
    annotations:{readOnlyHint:true,destructiveHint:false,idempotentHint:true,openWorldHint:false},
    _meta:{ui:{resourceUri:RESOURCE_URI},'ui/resourceUri':RESOURCE_URI,'openai/outputTemplate':RESOURCE_URI,'openai/widgetAccessible':true}
  },async()=>({content:[{type:'text',text:'Scout MCP Apps handshake smoke test invoked.'}],structuredContent:{surface:'scout_component_sandbox_handshake_smoke'}}))
  registerAppResource(server,'scout-component-sandbox-handshake-smoke',RESOURCE_URI,{mimeType:RESOURCE_MIME_TYPE},async()=>({
    contents:[{
      uri:RESOURCE_URI,
      mimeType:RESOURCE_MIME_TYPE,
      text:VIEW_HTML,
      _meta:{
        ui:{prefersBorder:false,csp:{connectDomains:[],resourceDomains:[MCP_APP_SDK_ORIGIN]}},
        'openai/widgetDescription':'Scout owner-only MCP Apps handshake smoke test. No business data is rendered.',
        'openai/widgetPrefersBorder':false,
        'openai/widgetCSP':{connect_domains:[],resource_domains:[MCP_APP_SDK_ORIGIN]}
      }
    }]
  }))
  return server
}

const mcpHandler=createMcpHandler(()=>makeServer())
function headers(base?:HeadersInit){const h=new Headers(base);h.set('access-control-allow-origin','*');h.set('access-control-allow-headers','authorization,content-type,accept,mcp-protocol-version,mcp-session-id,x-request-id,last-event-id');h.set('access-control-expose-headers','mcp-session-id,content-type');h.set('access-control-allow-methods','GET,POST,DELETE,OPTIONS');h.set('cache-control','no-store, max-age=0');h.set('x-content-type-options','nosniff');h.set('referrer-policy','no-referrer');return h}
Deno.serve(async(req:Request)=>{if(req.method==='OPTIONS')return new Response(null,{status:204,headers:headers()});if(!(await authenticateOwner(req)))return Response.json({error:'not found'},{status:404,headers:headers()});try{const response=await mcpHandler.fetch(req);return new Response(response.body,{status:response.status,statusText:response.statusText,headers:headers(response.headers)})}catch(error){console.error('Scout MCP Apps handshake smoke test error',error);return Response.json({error:'Scout handshake smoke test failed'},{status:500,headers:headers()})}})
