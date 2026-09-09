import 'jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.115.0'
import { createMcpHandler, McpServer } from 'npm:@modelcontextprotocol/server@2.0.0'
import { registerAppResource, registerAppTool, RESOURCE_MIME_TYPE } from 'npm:@modelcontextprotocol/ext-apps@2.0.0/server'
import * as z from 'npm:zod@4.2.0/v4'
import { buildComponentSandboxHtml, type SandboxMapTarget } from './component.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
let SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
try { const keys = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') || '{}'); SERVICE_KEY = keys.default || SERVICE_KEY } catch {}
if (!SERVICE_KEY) throw new Error('Scout component sandbox service credential is unavailable')
const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession:false, autoRefreshToken:false } })

const RESOURCE_URI = 'ui://scout/component-sandbox/v1'
const TOOL_NAME = 'scout_preview_component_sandbox'
const BASEMAP_ORIGIN = 'https://tile.openstreetmap.org'

async function authenticateOwner(req:Request){
  const match=(req.headers.get('authorization')||'').match(/^Bearer\s+(.+)$/i)
  if(!match)return null
  const token=match[1].trim()
  const {data:userResult,error:userError}=await admin.auth.getUser(token)
  const user=userResult.user
  if(userError||!user?.id)return null
  const {data:owner,error:ownerError}=await admin.rpc('scout_is_owner_user_internal',{p_user_id:user.id})
  if(ownerError||owner!==true)return null
  return user
}

function normalizeTarget(value:any):SandboxMapTarget|null{
  if(!value||!['property','group'].includes(value.kind)||typeof value.key!=='string'||typeof value.label!=='string')return null
  const scopeCount=Number(value.scope_count)
  const minLon=Number(value.min_lon),minLat=Number(value.min_lat),maxLon=Number(value.max_lon),maxLat=Number(value.max_lat)
  if(!Number.isInteger(scopeCount)||scopeCount<1||![minLon,minLat,maxLon,maxLat].every(Number.isFinite))return null
  if(minLon < -180 || maxLon > 180 || minLat < -90 || maxLat > 90)return null
  return {kind:value.kind,key:value.key,label:value.label.slice(0,160),scope_count:scopeCount,min_lon:minLon,min_lat:minLat,max_lon:maxLon,max_lat:maxLat}
}

async function loadMapTargets():Promise<SandboxMapTarget[]>{
  const {data,error}=await admin.rpc('scout_get_component_sandbox_map_targets_internal',{p_property_limit:12,p_group_limit:8})
  if(error){console.error('Scout component sandbox exemplar target query failed',error);return []}
  if(!Array.isArray(data))return []
  return data.map(normalizeTarget).filter((x):x is SandboxMapTarget=>!!x)
}

function makeServer(){
  const server=new McpServer({name:'Scout Component Sandbox',version:'2.1.0'})
  registerAppTool(server,TOOL_NAME,{
    title:'Preview Scout Component Sandbox',
    description:'Owner-only read-only developer preview of the Scout MCP App component sandbox. Call only when the Scout owner explicitly asks to preview, surface, inspect, or test the sandbox UI. Slide 2 may frame a bounded real Scout exemplar property or regional property group; it does not render opportunity overlays.',
    inputSchema:z.object({}),
    outputSchema:z.object({surface:z.literal('scout_component_sandbox'),version:z.literal('v1'),business_data:z.literal(true),interaction_scope:z.literal('ephemeral_only')}),
    annotations:{readOnlyHint:true,destructiveHint:false,idempotentHint:true,openWorldHint:false},
    _meta:{ui:{resourceUri:RESOURCE_URI},'ui/resourceUri':RESOURCE_URI,'openai/outputTemplate':RESOURCE_URI,'openai/widgetAccessible':true,'openai/toolInvocation/invoking':'Opening Scout preview…','openai/toolInvocation/invoked':'Scout preview opened.'}
  },async()=>({
    content:[{type:'text',text:'Scout component sandbox v1. Owner-only developer preview; slide 2 frames a bounded real exemplar property or regional group and renders no opportunity overlays.'}],
    structuredContent:{surface:'scout_component_sandbox',version:'v1',business_data:true,interaction_scope:'ephemeral_only'}
  }))
  registerAppResource(server,'scout-component-sandbox',RESOURCE_URI,{mimeType:RESOURCE_MIME_TYPE},async()=>{
    const targets=await loadMapTargets()
    return {contents:[{uri:RESOURCE_URI,mimeType:RESOURCE_MIME_TYPE,text:buildComponentSandboxHtml(targets),_meta:{ui:{prefersBorder:false,csp:{connectDomains:[],resourceDomains:[BASEMAP_ORIGIN]}},'openai/widgetDescription':'Owner-only Scout component sandbox. Slide 2 chooses a bounded real exemplar property or regional property-management group and auto-fits a static basemap; no opportunity overlays are rendered.','openai/widgetPrefersBorder':false,'openai/widgetCSP':{connect_domains:[],resource_domains:[BASEMAP_ORIGIN]}}}]}
  })
  return server
}

const mcpHandler=createMcpHandler(()=>makeServer())

function headers(base?:HeadersInit){
  const h=new Headers(base)
  h.set('access-control-allow-origin','*')
  h.set('access-control-allow-headers','authorization,content-type,accept,mcp-protocol-version,mcp-session-id,x-request-id,last-event-id')
  h.set('access-control-expose-headers','mcp-session-id,content-type')
  h.set('access-control-allow-methods','GET,POST,DELETE,OPTIONS')
  h.set('cache-control','no-store, max-age=0')
  h.set('x-content-type-options','nosniff')
  h.set('referrer-policy','no-referrer')
  return h
}

Deno.serve(async(req:Request)=>{
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers:headers()})
  if(!(await authenticateOwner(req)))return Response.json({error:'not found'},{status:404,headers:headers()})
  try{
    const response=await mcpHandler.fetch(req)
    return new Response(response.body,{status:response.status,statusText:response.statusText,headers:headers(response.headers)})
  }catch(e){
    console.error('Scout component sandbox MCP error',e)
    return Response.json({error:'Scout component sandbox request failed'},{status:500,headers:headers()})
  }
})
