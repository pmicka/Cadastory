import 'jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.115.0'
import { createMcpHandler, McpServer } from 'npm:@modelcontextprotocol/server@2.0.0'
import { registerAppResource, registerAppTool, RESOURCE_MIME_TYPE } from 'npm:@modelcontextprotocol/ext-apps@2.0.0/server'
import * as z from 'npm:zod@4.2.0/v4'
import {
  buildComponentSandboxHtml,
  type SandboxMapMember,
  type SandboxMapTarget,
  type SandboxMapTerritory,
} from './component_v8.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
let SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
try { const keys = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') || '{}'); SERVICE_KEY = keys.default || SERVICE_KEY } catch {}
if (!SERVICE_KEY) throw new Error('Scout component sandbox service credential is unavailable')
const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession:false, autoRefreshToken:false } })

const RESOURCE_URI = 'ui://scout/component-sandbox/v1'
const TOOL_NAME = 'scout_preview_component_sandbox'
const BASEMAP_ORIGIN = 'https://tile.openstreetmap.org'
const PROPERTY_TYPES = new Set([
  'multifamily','senior_living','hotel','office','retail','industrial','residential',
  'dealership','water_tank_elevated','water_tank_standpipe','water_tank_ground_storage','water_tank_other','other'
])
const GEOGRAPHY_STATUSES = new Set(['resolved_assets','documented_territory','mixed','reported_scale_only'])
const TERRITORY_KINDS = new Set(['administrative_area','named_market'])
const BOUNDARY_STATUSES = new Set(['resolved','unresolved'])

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

function normalizeMember(value:any):SandboxMapMember|null{
  if(!value||typeof value.key!=='string'||typeof value.label!=='string')return null
  const lat=Number(value.lat),lon=Number(value.lon)
  if(!Number.isFinite(lat)||!Number.isFinite(lon)||lat < -90||lat > 90||lon < -180||lon > 180)return null
  const propertyType=PROPERTY_TYPES.has(String(value.property_type))?String(value.property_type):'other'
  return {
    key:value.key.slice(0,180),
    label:value.label.slice(0,180),
    property_type:propertyType as SandboxMapMember['property_type'],
    property_type_label:typeof value.property_type_label==='string'?value.property_type_label.slice(0,160):'Portfolio asset',
    city:typeof value.city==='string'?value.city.slice(0,100):null,
    state:typeof value.state==='string'?value.state.slice(0,20):null,
    lon,lat
  }
}

function normalizeCoordinateTree(value:any,state:{points:number,depth:number}):any|null{
  if(!Array.isArray(value)||value.length===0||state.depth>8)return null
  if(value.length>=2&&!Array.isArray(value[0])&&!Array.isArray(value[1])){
    const lon=Number(value[0]),lat=Number(value[1])
    if(!Number.isFinite(lon)||!Number.isFinite(lat)||lon < -180||lon > 180||lat < -90||lat > 90)return null
    state.points++
    if(state.points>6000)return null
    return [lon,lat]
  }
  const out:any[]=[]
  for(const child of value){
    const childState={points:state.points,depth:state.depth+1}
    const normalized=normalizeCoordinateTree(child,childState)
    if(normalized===null)return null
    state.points=childState.points
    out.push(normalized)
  }
  return out
}

function normalizeGeometry(value:any):SandboxMapTerritory['geometry']{
  if(!value||!['Polygon','MultiPolygon'].includes(String(value.type))||!Array.isArray(value.coordinates))return null
  const state={points:0,depth:0}
  const coordinates=normalizeCoordinateTree(value.coordinates,state)
  if(coordinates===null||state.points<3)return null
  return {type:String(value.type) as 'Polygon'|'MultiPolygon',coordinates}
}

function normalizeTerritory(value:any):SandboxMapTerritory|null{
  if(!value||typeof value.key!=='string'||typeof value.label!=='string')return null
  const territoryKind=TERRITORY_KINDS.has(String(value.territory_kind))?String(value.territory_kind):'named_market'
  const boundaryStatus=BOUNDARY_STATUSES.has(String(value.boundary_status))?String(value.boundary_status):'unresolved'
  const confidence=Number(value.confidence)
  const geometry=boundaryStatus==='resolved'?normalizeGeometry(value.geometry):null
  return {
    key:value.key.slice(0,180),
    label:value.label.slice(0,180),
    territory_kind:territoryKind as SandboxMapTerritory['territory_kind'],
    boundary_status:(geometry?'resolved':'unresolved') as SandboxMapTerritory['boundary_status'],
    coverage_basis:typeof value.coverage_basis==='string'?value.coverage_basis.slice(0,120):'documented_scope',
    state:typeof value.state==='string'?value.state.slice(0,20):null,
    confidence:Number.isFinite(confidence)&&confidence>=0&&confidence<=1?confidence:null,
    source_url:typeof value.source_url==='string'?value.source_url.slice(0,600):null,
    source_authority:typeof value.source_authority==='string'?value.source_authority.slice(0,180):null,
    geometry
  }
}

function normalizeTarget(value:any):SandboxMapTarget|null{
  if(!value||!['property','group'].includes(value.kind)||typeof value.key!=='string'||typeof value.label!=='string')return null
  const scopeCount=Number(value.scope_count)
  const minLon=Number(value.min_lon),minLat=Number(value.min_lat),maxLon=Number(value.max_lon),maxLat=Number(value.max_lat)
  const validScope=Number.isInteger(scopeCount)&&(value.kind==='group'?scopeCount>=0:scopeCount>=1)
  if(!validScope||![minLon,minLat,maxLon,maxLat].every(Number.isFinite))return null
  if(minLon < -180 || maxLon > 180 || minLat < -90 || maxLat > 90)return null
  const members=Array.isArray(value.members)?value.members.map(normalizeMember).filter((x):x is SandboxMapMember=>!!x).slice(0,80):[]
  const territories=Array.isArray(value.territories)?value.territories.map(normalizeTerritory).filter((x):x is SandboxMapTerritory=>!!x).slice(0,12):[]
  const geographyStatus=GEOGRAPHY_STATUSES.has(String(value.portfolio_geography_status))?String(value.portfolio_geography_status):null
  const resolvedMemberCount=Number(value.resolved_member_count)
  const reportedMinimum=Number(value.reported_member_count_minimum)
  return {
    kind:value.kind,
    key:value.key.slice(0,180),
    label:value.label.slice(0,160),
    scope_count:scopeCount,
    min_lon:minLon,
    min_lat:minLat,
    max_lon:maxLon,
    max_lat:maxLat,
    members,
    portfolio_archetype:typeof value.portfolio_archetype==='string'?value.portfolio_archetype.slice(0,100):null,
    portfolio_geography_status:geographyStatus as SandboxMapTarget['portfolio_geography_status'],
    resolved_member_count:Number.isInteger(resolvedMemberCount)&&resolvedMemberCount>=0?resolvedMemberCount:members.length,
    reported_member_count_minimum:Number.isInteger(reportedMinimum)&&reportedMinimum>=0?reportedMinimum:null,
    roster_status:typeof value.roster_status==='string'?value.roster_status.slice(0,160):null,
    territories
  }
}

async function loadMapTargets():Promise<SandboxMapTarget[]>{
  const {data,error}=await admin.rpc('scout_get_component_sandbox_map_targets_v2_internal',{p_property_limit:12,p_group_limit:10})
  if(error){console.error('Scout component sandbox exemplar target query failed',error);return []}
  if(!Array.isArray(data))return []
  return data.map(normalizeTarget).filter((x):x is SandboxMapTarget=>!!x)
}

function makeServer(){
  const server=new McpServer({name:'Scout Component Sandbox',version:'2.7.0'})
  registerAppTool(server,TOOL_NAME,{
    title:'Preview Scout Component Sandbox',
    description:'Owner-only read-only developer preview of the Scout MCP App component sandbox. Call only when the Scout owner explicitly asks to preview, surface, inspect, or test the sandbox UI. Slide 2 frames a bounded real Scout exemplar property or portfolio account. Resolved physical assets use count-scaled color-coded numbered circles. Documented service territory can render as a separate bounded geographic fill when Scout has defensible administrative geometry. Broader named markets with unresolved boundaries are labeled without synthetic polygons or client-site points. Same-type resolved assets cluster only when their rendered circles materially collide. No opportunity overlays are rendered.',
    inputSchema:z.object({}),
    outputSchema:z.object({surface:z.literal('scout_component_sandbox'),version:z.literal('v1'),business_data:z.literal(true),interaction_scope:z.literal('ephemeral_only')}),
    annotations:{readOnlyHint:true,destructiveHint:false,idempotentHint:true,openWorldHint:false},
    _meta:{ui:{resourceUri:RESOURCE_URI},'ui/resourceUri':RESOURCE_URI,'openai/outputTemplate':RESOURCE_URI,'openai/widgetAccessible':true,'openai/toolInvocation/invoking':'Opening Scout preview…','openai/toolInvocation/invoked':'Scout preview opened.'}
  },async()=>{
    const widgetSessionId=crypto.randomUUID()
    return {
      content:[{type:'text',text:'Scout component sandbox v1. Owner-only developer preview; portfolio geography distinguishes resolved physical assets from documented operating territory and unresolved broader scope without fabricating locations.'}],
      structuredContent:{surface:'scout_component_sandbox',version:'v1',business_data:true,interaction_scope:'ephemeral_only'},
      _meta:{'openai/widgetSessionId':widgetSessionId,viewUUID:widgetSessionId}
    }
  })
  registerAppResource(server,'scout-component-sandbox',RESOURCE_URI,{mimeType:RESOURCE_MIME_TYPE},async()=>{
    const targets=await loadMapTargets()
    return {contents:[{uri:RESOURCE_URI,mimeType:RESOURCE_MIME_TYPE,text:buildComponentSandboxHtml(targets),_meta:{ui:{prefersBorder:false,csp:{connectDomains:[],resourceDomains:[BASEMAP_ORIGIN]}},'openai/widgetDescription':'Owner-only Scout component sandbox. Single properties auto-fit tightly. Portfolio maps distinguish exact resolved assets from documented service territory: numbered circles mean resolved physical locations; bounded translucent areas mean evidence-backed administrative service territory; broader named markets with unresolved extent are labeled but never drawn as invented boundaries. Facilities-management accounts can therefore be visualized even when client rosters are private or incomplete. Widget state survives host remounts. No opportunity overlays are rendered.','openai/widgetPrefersBorder':false,'openai/widgetCSP':{connect_domains:[],resource_domains:[BASEMAP_ORIGIN]}}}]}
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
