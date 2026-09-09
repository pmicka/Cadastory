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
  type SandboxContactCard,
  type SandboxContactRoute,
} from './component_v10.ts'

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
const ENRICHMENT_STATUSES = new Set(['none','partial','enriched'])

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

function text(value:any,max=180){return typeof value==='string'&&value.trim()?value.trim().slice(0,max):null}

function normalizeMember(value:any):SandboxMapMember|null{
  if(!value||typeof value.key!=='string'||typeof value.label!=='string')return null
  const lat=Number(value.lat),lon=Number(value.lon)
  if(!Number.isFinite(lat)||!Number.isFinite(lon)||lat < -90||lat > 90||lon < -180||lon > 180)return null
  const propertyType=PROPERTY_TYPES.has(String(value.property_type))?String(value.property_type):'other'
  return {
    key:value.key.slice(0,180),label:value.label.slice(0,180),
    property_type:propertyType as SandboxMapMember['property_type'],
    property_type_label:text(value.property_type_label,160)||'Portfolio asset',
    city:text(value.city,100),state:text(value.state,20),lon,lat
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
    key:value.key.slice(0,180),label:value.label.slice(0,180),
    territory_kind:territoryKind as SandboxMapTerritory['territory_kind'],
    boundary_status:(geometry?'resolved':'unresolved') as SandboxMapTerritory['boundary_status'],
    coverage_basis:text(value.coverage_basis,120)||'documented_scope',state:text(value.state,20),
    confidence:Number.isFinite(confidence)&&confidence>=0&&confidence<=1?confidence:null,
    source_url:text(value.source_url,600),source_authority:text(value.source_authority,180),geometry
  }
}

function normalizeContactRoute(value:any):SandboxContactRoute|null{
  if(!value)return null
  const channel=text(value.channel_type,60),routeValue=text(value.value,800)
  if(!channel||!routeValue)return null
  const confidence=Number(value.confidence)
  return {
    key:text(value.key,180)||`${channel}:${routeValue}`.slice(0,180),channel_type:channel,value:routeValue,
    label:text(value.label,220),scope:text(value.scope,100),department:text(value.department,140),
    stability_class:text(value.stability_class,80),
    confidence:Number.isFinite(confidence)&&confidence>=0&&confidence<=1?confidence:null,
    verify_after:text(value.verify_after,40),is_primary:typeof value.is_primary==='boolean'?value.is_primary:null,
    inherited:typeof value.inherited==='boolean'?value.inherited:null,routing_note:text(value.routing_note,600),
    source_authority:text(value.source_authority,180),source_url:text(value.source_url,600)
  }
}

function normalizeContactCard(value:any,targetKey:string,targetLabel:string):SandboxContactCard{
  const routes=Array.isArray(value?.routes)?value.routes.map(normalizeContactRoute).filter((x):x is SandboxContactRoute=>!!x).slice(0,3):[]
  const routeCount=Number(value?.route_count)
  const enrichment=ENRICHMENT_STATUSES.has(String(value?.enrichment_status))?String(value.enrichment_status):routes.length?'partial':'none'
  return {
    lead_key:text(value?.lead_key,180)||targetKey,subject_name:text(value?.subject_name,180)||targetLabel,
    organization_name:text(value?.organization_name,180),organization_type:text(value?.organization_type,120),
    site_name:text(value?.site_name,180),address:text(value?.address,300),website_url:text(value?.website_url,600),
    role_label:text(value?.role_label,180),resolution_status:text(value?.resolution_status,100)||'lead_identified',
    enrichment_status:enrichment as SandboxContactCard['enrichment_status'],routes,
    route_count:Number.isInteger(routeCount)&&routeCount>=0?routeCount:routes.length,research_note:text(value?.research_note,500)
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
  const resolvedMemberCount=Number(value.resolved_member_count),reportedMinimum=Number(value.reported_member_count_minimum)
  return {
    kind:value.kind,key:value.key.slice(0,180),label:value.label.slice(0,160),scope_count:scopeCount,
    min_lon:minLon,min_lat:minLat,max_lon:maxLon,max_lat:maxLat,members,
    portfolio_archetype:text(value.portfolio_archetype,100),
    portfolio_geography_status:geographyStatus as SandboxMapTarget['portfolio_geography_status'],
    resolved_member_count:Number.isInteger(resolvedMemberCount)&&resolvedMemberCount>=0?resolvedMemberCount:members.length,
    reported_member_count_minimum:Number.isInteger(reportedMinimum)&&reportedMinimum>=0?reportedMinimum:null,
    roster_status:text(value.roster_status,160),territories,
    contact_card:normalizeContactCard(value.contact_card,value.key,value.label)
  }
}

async function loadMapTargets():Promise<SandboxMapTarget[]>{
  const {data,error}=await admin.rpc('scout_get_component_sandbox_map_targets_v3_internal',{p_property_limit:12,p_group_limit:14})
  if(error){console.error('Scout component sandbox exemplar target query failed',error);return []}
  if(!Array.isArray(data))return []
  return data.map(normalizeTarget).filter((x):x is SandboxMapTarget=>!!x)
}

function makeServer(){
  const server=new McpServer({name:'Scout Component Sandbox',version:'2.9.0'})
  registerAppTool(server,TOOL_NAME,{
    title:'Preview Scout Component Sandbox',
    description:'Owner-only read-only developer preview of the Scout MCP App component sandbox. Call only when the Scout owner explicitly asks to preview, surface, inspect, or test the sandbox UI. Slide 2 shows bounded property/portfolio geography. Slide 3 is a progressive lead contact card. When a lead has a stable identity plus at least one importable phone, email, URL, website, supplier route, or address, the contact name becomes a .vcf download affordance with an in-card confirmation prompt. Routing instructions alone do not qualify. Missing enrichment remains explicit rather than fabricated. No opportunity overlays are rendered.',
    inputSchema:z.object({}),
    outputSchema:z.object({surface:z.literal('scout_component_sandbox'),version:z.literal('v1'),business_data:z.literal(true),interaction_scope:z.literal('ephemeral_only')}),
    annotations:{readOnlyHint:true,destructiveHint:false,idempotentHint:true,openWorldHint:false},
    _meta:{ui:{resourceUri:RESOURCE_URI},'ui/resourceUri':RESOURCE_URI,'openai/outputTemplate':RESOURCE_URI,'openai/widgetAccessible':true,'openai/toolInvocation/invoking':'Opening Scout preview…','openai/toolInvocation/invoked':'Scout preview opened.'}
  },async()=>{
    const widgetSessionId=crypto.randomUUID()
    return {content:[{type:'text',text:'Scout component sandbox v1. Slide 3 previews a progressive contact card and can prepare a standard .vcf contact file when the lead contains enough importable contact data.'}],structuredContent:{surface:'scout_component_sandbox',version:'v1',business_data:true,interaction_scope:'ephemeral_only'},_meta:{'openai/widgetSessionId':widgetSessionId,viewUUID:widgetSessionId}}
  })
  registerAppResource(server,'scout-component-sandbox',RESOURCE_URI,{mimeType:RESOURCE_MIME_TYPE},async()=>{
    const targets=await loadMapTargets()
    return {contents:[{uri:RESOURCE_URI,mimeType:RESOURCE_MIME_TYPE,text:buildComponentSandboxHtml(targets),_meta:{ui:{prefersBorder:false,csp:{connectDomains:[],resourceDomains:[BASEMAP_ORIGIN]}},'openai/widgetDescription':'Owner-only Scout component sandbox. Slide 2 distinguishes resolved assets from documented portfolio territory. Slide 3 is a normalized contact card. A sufficiently resolved contact name is tappable and opens an in-card confirmation before generating a standard .vcf file locally from the already-authorized widget payload; thin leads and routing-instruction-only records remain non-downloadable. Widget state survives host remounts.','openai/widgetPrefersBorder':false,'openai/widgetCSP':{connect_domains:[],resource_domains:[BASEMAP_ORIGIN]}}}]}
  })
  return server
}

const mcpHandler=createMcpHandler(()=>makeServer())
function headers(base?:HeadersInit){const h=new Headers(base);h.set('access-control-allow-origin','*');h.set('access-control-allow-headers','authorization,content-type,accept,mcp-protocol-version,mcp-session-id,x-request-id,last-event-id');h.set('access-control-expose-headers','mcp-session-id,content-type');h.set('access-control-allow-methods','GET,POST,DELETE,OPTIONS');h.set('cache-control','no-store, max-age=0');h.set('x-content-type-options','nosniff');h.set('referrer-policy','no-referrer');return h}
Deno.serve(async(req:Request)=>{if(req.method==='OPTIONS')return new Response(null,{status:204,headers:headers()});if(!(await authenticateOwner(req)))return Response.json({error:'not found'},{status:404,headers:headers()});try{const response=await mcpHandler.fetch(req);return new Response(response.body,{status:response.status,statusText:response.statusText,headers:headers(response.headers)})}catch(e){console.error('Scout component sandbox MCP error',e);return Response.json({error:'Scout component sandbox request failed'},{status:500,headers:headers()})}})
