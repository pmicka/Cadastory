import 'jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.115.0'
import { createMcpHandler, McpServer } from 'npm:@modelcontextprotocol/server@2.0.0'
import { registerAppResource, registerAppTool, RESOURCE_MIME_TYPE } from 'npm:@modelcontextprotocol/ext-apps@2.0.0/server'
import * as z from 'npm:zod@4.2.0/v4'
import { COMPONENT_SANDBOX_HTML } from './component.ts'

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

function makeServer(){
  const server=new McpServer({name:'Scout Component Sandbox',version:'2.0.1'})
  registerAppTool(server,TOOL_NAME,{
    title:'Preview Scout Component Sandbox',
    description:'Owner-only read-only developer preview of the Scout MCP App component sandbox. Call only when the Scout owner explicitly asks to preview, surface, inspect, or test the sandbox UI. It uses placeholder content and no business data.',
    inputSchema:z.object({}),
    outputSchema:z.object({surface:z.literal('scout_component_sandbox'),version:z.literal('v1'),business_data:z.literal(false),interaction_scope:z.literal('ephemeral_only')}),
    annotations:{readOnlyHint:true,destructiveHint:false,idempotentHint:true,openWorldHint:false},
    _meta:{ui:{resourceUri:RESOURCE_URI},'ui/resourceUri':RESOURCE_URI,'openai/outputTemplate':RESOURCE_URI,'openai/widgetAccessible':true,'openai/toolInvocation/invoking':'Opening Scout preview…','openai/toolInvocation/invoked':'Scout preview opened.'}
  },async()=>({
    content:[{type:'text',text:'Scout component sandbox v1. This is an owner-only static developer preview; its controls are ephemeral and contain no business data.'}],
    structuredContent:{surface:'scout_component_sandbox',version:'v1',business_data:false,interaction_scope:'ephemeral_only'}
  }))
  registerAppResource(server,'scout-component-sandbox',RESOURCE_URI,{mimeType:RESOURCE_MIME_TYPE},async()=>({
    contents:[{uri:RESOURCE_URI,mimeType:RESOURCE_MIME_TYPE,text:COMPONENT_SANDBOX_HTML,_meta:{ui:{prefersBorder:false,csp:{connectDomains:[],resourceDomains:[BASEMAP_ORIGIN]}},'openai/widgetDescription':'Owner-only Scout component sandbox for testing inline card controls and interaction density. Slide 2 is a non-interactive basemap-only rendering test with no Scout data overlays.','openai/widgetPrefersBorder':false,'openai/widgetCSP':{connect_domains:[],resource_domains:[BASEMAP_ORIGIN]}}}]
  }))
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
