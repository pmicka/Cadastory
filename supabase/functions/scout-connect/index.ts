import 'jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.115.0'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
let SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
try {
  const keys = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') || '{}')
  SERVICE_KEY = keys.default || SERVICE_KEY
} catch { /* legacy fallback */ }
if (!SERVICE_KEY) throw new Error('Scout connection service credential is unavailable')

const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false, autoRefreshToken: false } })
const RESOURCE_URL = `${SUPABASE_URL}/functions/v1/scout-connect`
const METADATA_URL = `${RESOURCE_URL}/oauth-protected-resource`
const AUTH_SERVER = `${SUPABASE_URL}/auth/v1`
const CORE_URL = `${SUPABASE_URL}/functions/v1/scout-mcp-contract`
const OPS_URL = `${SUPABASE_URL}/functions/v1/scout-ops-contract`
const SANDBOX_URL = `${SUPABASE_URL}/functions/v1/scout-component-sandbox-mcp`
const SANDBOX_TOOL = 'scout_preview_component_sandbox'
const SANDBOX_RESOURCE_URI = 'ui://scout/component-sandbox/v2'
const OPS_TOOLS = new Set(['scout_submit_business_signal','scout_get_action_intents','scout_update_action_intent','scout_reject_public_equipment_candidates'])

const publicHeaders = {
  'access-control-allow-origin': '*',
  'access-control-allow-headers': 'authorization, content-type, accept, mcp-protocol-version, mcp-session-id, last-event-id',
  'access-control-expose-headers': 'www-authenticate, mcp-session-id, content-type',
  'access-control-allow-methods': 'GET, POST, DELETE, OPTIONS',
  'cache-control': 'no-store, max-age=0',
  'pragma': 'no-cache',
  'referrer-policy': 'no-referrer',
  'x-content-type-options': 'nosniff',
  'x-scout-agent-contract': 'v1',
}

function json(body: unknown, status = 200, extra: Record<string,string> = {}) {
  return new Response(JSON.stringify(body), { status, headers: { ...publicHeaders, 'content-type': 'application/json; charset=utf-8', ...extra } })
}
function challenge(description = 'Scout authentication required') {
  return json({ error: 'unauthorized', error_description: description }, 401, { 'www-authenticate': `Bearer resource_metadata="${METADATA_URL}"` })
}
function decodePayload(token: string): Record<string, unknown> | null {
  try { const part=token.split('.')[1]; if(!part)return null; const normalized=part.replace(/-/g,'+').replace(/_/g,'/')+'='.repeat((4-part.length%4)%4); return JSON.parse(atob(normalized)) } catch { return null }
}
function uuid(value: unknown): string | null { if(typeof value!=='string')return null; return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)?value:null }
function obj(v:unknown):Record<string,any>{return v&&typeof v==='object'&&!Array.isArray(v)?v as Record<string,any>:{} }
function machine(v:unknown,max=120):string|undefined { if(typeof v!=='string')return; const x=v.trim(); return /^[A-Za-z0-9_.-]+$/.test(x)&&x.length<=max?x:undefined }
function bounded(v:unknown,max=300):string|undefined { if(typeof v!=='string')return; const x=v.trim(); return x&&x.length<=max?x:undefined }
function bool(v:unknown):boolean|undefined{return typeof v==='boolean'?v:undefined}
function num(v:unknown,min:number,max:number):number|undefined{return typeof v==='number'&&Number.isFinite(v)&&v>=min&&v<=max?v:undefined}
function listMachine(v:unknown,maxItems=50):string[]{return Array.isArray(v)?v.map(x=>machine(x)).filter((x):x is string=>!!x).slice(0,maxItems):[]}
function radiusBucket(v:unknown){const n=num(v,0,10000);if(n===undefined)return undefined;if(n<=5)return '0-5';if(n<=15)return '6-15';if(n<=30)return '16-30';if(n<=50)return '31-50';if(n<=100)return '51-100';if(n<=250)return '101-250';return '250+'}
function budgetBand(v:unknown){const n=num(v,0,100000000);if(n===undefined)return undefined;if(n<1000)return '<1k';if(n<5000)return '1k-5k';if(n<10000)return '5k-10k';if(n<25000)return '10k-25k';if(n<50000)return '25k-50k';if(n<100000)return '50k-100k';return '100k+'}
function leadBucket(v:unknown){if(typeof v!=='string')return undefined;const t=Date.parse(v);if(!Number.isFinite(t))return undefined;const d=(t-Date.now())/86400000;if(d<0)return 'past';if(d<1)return '<1d';if(d<3)return '1-3d';if(d<7)return '3-7d';if(d<30)return '1-4w';if(d<90)return '1-3mo';return '3mo+'}
function geoDims(a:Record<string,any>){const out:Record<string,unknown>={};const state=machine(a.state_code,8);const county=bounded(a.county_name,120);if(state)out.state_code=state.toUpperCase();if(county)out.county_name=county;const rb=radiusBucket(a.radius_miles);if(rb)out.radius_miles_band=rb;out.geography_mode=county&&state?'county':(typeof a.center_lat==='number'&&typeof a.center_lon==='number'?'center_radius':'unspecified');return out}
function safeDimensions(tool:string,args:Record<string,any>):Record<string,unknown>{
  const out:Record<string,unknown>={}
  const limit=num(args.limit,1,100);if(limit!==undefined)out.limit=limit
  switch(tool){
    case 'scout_find_opportunities': {
      const service=machine(args.service_slug);if(service)out.service_slug=service
      Object.assign(out,geoDims(args));const j=machine(args.jurisdiction_code,16);if(j)out.jurisdiction_code=j.toUpperCase()
      if(bool(args.time_sensitive)!==undefined)out.time_sensitive=args.time_sensitive
      if(bool(args.require_contact)!==undefined)out.require_contact=args.require_contact
      const fit=machine(args.fit_filter,40);if(fit)out.fit_filter=fit
      break
    }
    case 'scout_find_growth_options': {
      Object.assign(out,geoDims(args));const b=budgetBand(args.budget);if(b)out.budget_band=b
      if(bool(args.include_existing)!==undefined)out.include_existing=args.include_existing
      const j=machine(args.jurisdiction_code,16);if(j)out.jurisdiction_code=j.toUpperCase()
      break
    }
    case 'scout_plan_job': {
      const service=machine(args.service_slug);if(service)out.service_slug=service
      const dm=machine(args.delivery_method_slug);if(dm)out.delivery_method=dm
      const target=obj(args.target);const st=machine(target.state_code,8);const county=bounded(target.county_name,120);if(st)out.state_code=st.toUpperCase();if(county)out.county_name=county
      out.has_address=typeof target.address==='string'&&target.address.trim().length>0
      out.has_coordinates=typeof target.latitude==='number'&&typeof target.longitude==='number'
      out.has_site_name=typeof target.site_name==='string'&&target.site_name.trim().length>0
      const lead=leadBucket(args.scheduled_start);if(lead)out.scheduled_lead_time=lead
      out.has_scheduled_end=typeof args.scheduled_end==='string'
      out.equipment_count=Array.isArray(args.equipment)?Math.min(args.equipment.length,40):0
      const op=obj(args.operating_plan);out.operating_plan_fields=Object.keys(op).filter(k=>/^[a-z0-9_]{1,64}$/i.test(k)).slice(0,20).sort()
      out.candidate_context=typeof args.candidate_key==='string'&&args.candidate_key.length>0
      if(bool(args.queue_live_checks)!==undefined)out.queue_live_checks=args.queue_live_checks
      break
    }
    case 'scout_get_document_suite': {
      out.service_slugs=listMachine(args.service_slugs,20);const j=machine(args.jurisdiction,16);if(j)out.jurisdiction=j.toUpperCase()
      const c=obj(args.context);for(const k of ['human_entry','respirator_required','fall_exposure','hazardous_energy'])if(typeof c[k]==='boolean')out[k]=c[k]
      if(machine(c.contract_framework,40))out.contract_framework=c.contract_framework
      const flags=obj(c.condition_flags);out.condition_flags=Object.keys(flags).filter(k=>flags[k]===true&&/^[a-z0-9_]{1,80}$/i.test(k)).slice(0,30).sort()
      break
    }
    case 'scout_check_opportunity_access': {
      out.service_slugs=listMachine(args.service_slugs,50);const st=machine(args.state_code,8);if(st)out.state_code=st.toUpperCase()
      if(bool(args.controlled_airspace_requires_authorization)!==undefined)out.controlled_airspace_requires_authorization=args.controlled_airspace_requires_authorization
      const flags=obj(args.condition_flags);out.condition_flags=Object.keys(flags).filter(k=>flags[k]===true&&/^[a-z0-9_]{1,80}$/i.test(k)).slice(0,30).sort();break
    }
    case 'scout_match_media_asset': {
      out.has_coordinates=typeof args.latitude==='number'&&typeof args.longitude==='number';out.has_business_hint=typeof args.business_hint==='string';out.has_address_hint=typeof args.address_hint==='string';out.has_visible_text=typeof args.visible_text==='string'
      const bt=machine(args.observed_building_type,40);if(bt)out.observed_building_type=bt;const r=num(args.search_radius_m,0,100000);if(r!==undefined)out.search_radius_m_band=r<=100?'0-100':r<=500?'101-500':r<=1000?'501-1000':r<=5000?'1-5k':'5k+';break
    }
    case 'scout_get_lead_work_package': case 'scout_prepare_outreach': {
      const ck=bounded(args.candidate_key,300);if(ck)out.candidate_key=ck;const ch=machine(args.channel,40);if(ch)out.channel=ch;const j=machine(args.jurisdiction_code,16);if(j)out.jurisdiction_code=j.toUpperCase();break
    }
    case 'scout_search_document_standards': {
      out.query_present=typeof args.query==='string'&&args.query.length>0;out.query_length=typeof args.query==='string'?Math.min(args.query.length,300):0
      for(const k of ['domain','jurisdiction','criticality']){const x=bounded(args[k],100);if(x)out[k]=x}break
    }
    case 'scout_search_equipment_models': {
      out.query_present=typeof args.query==='string'&&args.query.length>0;out.query_length=typeof args.query==='string'?Math.min(args.query.length,160):0;break
    }
    case 'scout_search_knowledge': {
      out.query_present=typeof args.query==='string'&&args.query.length>0;out.query_length=typeof args.query==='string'?Math.min(args.query.length,300):0;const service=machine(args.service_slug);if(service)out.service_slug=service;const j=bounded(args.jurisdiction,40);if(j)out.jurisdiction=j;break
    }
    case 'scout_get_capabilities': {
      out.query_present=typeof args.query==='string'&&args.query.length>0;out.query_length=typeof args.query==='string'?Math.min(args.query.length,200):0;const cat=machine(args.category,40);if(cat)out.category=cat;if(bool(args.include_services)!==undefined)out.include_services=args.include_services;if(bool(args.include_external)!==undefined)out.include_external=args.include_external;break
    }
    case 'scout_update_profile': {
      const p=obj(args.patch);out.patch_fields=Object.keys(p).filter(k=>/^[a-z0-9_]{1,64}$/i.test(k)).slice(0,40).sort();const sec=machine(p.sector);if(sec)out.sector=sec;const states=Array.isArray(p.operating_states)?p.operating_states.filter((x:any)=>typeof x==='string'&&/^[A-Za-z]{2}$/.test(x)).map((x:string)=>x.toUpperCase()).slice(0,20):[];if(states.length)out.operating_states=states
      const services=listMachine(p.services,200);if(services.length){out.service_count=services.length;out.service_slugs=services}
      out.rig_count=Array.isArray(p.rigs)?Math.min(p.rigs.length,25):0;out.equipment_count=Array.isArray(p.equipment)?Math.min(p.equipment.length,100):0;out.credential_count=Array.isArray(p.credentials)?Math.min(p.credentials.length,100):0
      for(const k of ['services_confirmed','equipment_confirmed','credentials_confirmed','rigs_confirmed'])if(typeof p[k]==='boolean')out[k]=p[k];break
    }
    case 'scout_list_onboarding_options': {
      const services=listMachine(args.service_slugs,100);if(services.length)out.service_slugs=services;const states=Array.isArray(args.operating_states)?args.operating_states.filter((x:any)=>typeof x==='string'&&/^[A-Za-z]{2}$/.test(x)).map((x:string)=>x.toUpperCase()).slice(0,20):[];if(states.length)out.operating_states=states;break
    }
    case 'scout_store_equipment_serial': {
      const pe=uuid(args.provider_equipment_id);if(pe)out.provider_equipment_id=pe;out.has_unit_id=!!uuid(args.unit_id);out.has_nickname=typeof args.nickname==='string'&&args.nickname.length>0;if(bool(args.recall_watch_enabled)!==undefined)out.recall_watch_enabled=args.recall_watch_enabled;break
    }
    case 'scout_submit_compatibility_research': {
      const rid=uuid(args.research_request_id);if(rid)out.research_request_id=rid;const b=obj(args.bundle);out.source_count=Array.isArray(b.sources)?Math.min(b.sources.length,100):0;out.capability_count=Array.isArray(b.capabilities)?Math.min(b.capabilities.length,200):0;out.wetted_material_count=Array.isArray(b.wetted_materials)?Math.min(b.wetted_materials.length,200):0;out.chemistry_rule_count=Array.isArray(b.chemistry_rules)?Math.min(b.chemistry_rules.length,200):0;out.field_claim_count=Array.isArray(b.field_claims)?Math.min(b.field_claims.length,300):0;out.unresolved_domains=listMachine(b.unresolved_domains,100);break
    }
    case 'scout_submit_recall_check': {
      const rid=uuid(args.record_id);if(rid)out.record_id=rid;out.checked_source_count=Array.isArray(args.checked_sources)?Math.min(args.checked_sources.length,30):0;out.notice_count=Array.isArray(args.notices)?Math.min(args.notices.length,50):0;break
    }
    case 'scout_update_entry_item': {
      const action=machine(args.action,40);if(action)out.action=action;const sd=num(args.snooze_days,1,730);if(sd!==undefined)out.snooze_days=sd;const ik=bounded(args.item_key,300);if(ik)out.item_key=ik;break
    }
    case 'scout_report_external_capabilities': {
      const caps=Array.isArray(args.capabilities)?args.capabilities.slice(0,100):[];out.capability_count=caps.length;out.capability_slugs=caps.map((c:any)=>machine(obj(c).slug)).filter(Boolean).slice(0,100);if(bool(args.replace)!==undefined)out.replace=args.replace;const ttl=num(args.ttl_hours,1,720);if(ttl!==undefined)out.ttl_hours=ttl;break
    }
    case 'scout_prepare_external_context_request': {
      const cap=machine(args.capability_slug);if(cap)out.capability_slug=cap;const purpose=machine(args.purpose_code);if(purpose)out.purpose_code=purpose;out.requested_fields=listMachine(args.requested_fields,25);const sc=obj(args.scope);const st=machine(sc.state_code,8);if(st)out.state_code=st.toUpperCase();const rb=radiusBucket(sc.radius_miles);if(rb)out.radius_miles_band=rb;const rl=num(sc.record_limit,1,100);if(rl!==undefined)out.record_limit=rl;out.has_target_name=typeof sc.target_name==='string';out.has_target_location=typeof sc.target_location==='string';out.has_project_reference=typeof sc.project_reference==='string';out.has_job_reference=typeof sc.job_reference==='string';break
    }
    default: {
      for(const k of ['action','category','domain','state_code','jurisdiction_code','channel','reason_code','purpose_code','capability_slug','source_key']){const x=machine(args[k],120);if(x)out[k]=k==='state_code'||k==='jurisdiction_code'?x.toUpperCase():x}
      for(const k of ['enabled','replace','include_unavailable','queue_live_checks'])if(typeof args[k]==='boolean')out[k]=args[k]
    }
  }
  return out
}
async function recordToolDimensions(userId:string,clientId:string,connectionId:string,rpcBody:any){
  const items=Array.isArray(rpcBody)?rpcBody:[rpcBody]
  let seen=0
  for(const item of items){
    if(seen>=8)break
    if(!item||item.method!=='tools/call')continue
    const tool=typeof item.params?.name==='string'?item.params.name:''
    if(!/^scout_[a-z0-9_]{1,100}$/.test(tool))continue
    const args=obj(item.params?.arguments)
    const requestId=item.id===undefined?null:String(item.id).slice(0,160)
    seen++
    try{await admin.rpc('scout_record_tool_dimensions_internal',{p_user_id:userId,p_oauth_client_id:clientId,p_connection_id:connectionId,p_tool_name:tool,p_request_id:requestId,p_dimensions:safeDimensions(tool,args)})}catch(e){console.error('tool dimension telemetry failed',tool,e)}
  }
}

async function isOwnerUser(userId:string){const {data,error}=await admin.rpc('scout_is_owner_user_internal',{p_user_id:userId});return !error&&data===true}
function sandboxTool(){return {name:SANDBOX_TOOL,title:'Preview Scout UI Foundation',description:'Owner-only read-only developer tool that renders the minimal Scout MCP Apps View with a bounded set of real Scout exemplars. Call only when the Scout owner explicitly asks to test or preview the Scout sandbox UI foundation.',inputSchema:{type:'object',properties:{},additionalProperties:false},outputSchema:{type:'object',properties:{surface:{type:'string',enum:['scout_component_sandbox']},version:{type:'string',enum:['v2']},business_data:{type:'boolean',enum:[true]},interaction_scope:{type:'string',enum:['ephemeral_only']},foundation:{type:'string',enum:['ready']},exemplars:{type:'array',maxItems:4,items:{type:'object',properties:{name:{type:'string',minLength:1,maxLength:160},kind:{type:'string',enum:['property','group']},archetype:{type:['string','null'],minLength:1,maxLength:100},resolution_status:{type:['string','null'],minLength:1,maxLength:100}},required:['name','kind','archetype','resolution_status'],additionalProperties:false}}},required:['surface','version','business_data','interaction_scope','foundation','exemplars'],additionalProperties:false},annotations:{readOnlyHint:true,destructiveHint:false,idempotentHint:true,openWorldHint:false},_meta:{ui:{resourceUri:SANDBOX_RESOURCE_URI}}}}
function sandboxResource(){return {uri:SANDBOX_RESOURCE_URI,name:'scout-ui-foundation',title:'Scout UI Foundation',description:'Owner-only minimal Scout MCP Apps View used to verify rendering and host-bridge delivery.',mimeType:'text/html;profile=mcp-app'}}
function methodNotFound(rpcBody:any){return json({jsonrpc:'2.0',id:rpcBody?.id??null,error:{code:-32601,message:'Method not found'}})}

async function issueProxy(connectionId:string){
  const {data,error}=await admin.rpc('scout_issue_connection_proxy_token_internal',{p_connection_id:connectionId,p_ttl_seconds:120})
  if(error||!data?.token)throw new Error('Scout could not prepare authenticated MCP request')
  return String(data.token)
}
function upstreamHeaders(req:Request,bearer:string){
  const headers=new Headers(req.headers); headers.set('authorization',`Bearer ${bearer}`); headers.delete('host'); headers.delete('content-length'); headers.delete('cf-connecting-ip'); return headers
}
async function forwardTo(url:string,req:Request,bearer:string,rawBody?:string){
  const headers=upstreamHeaders(req,bearer)
  const init:RequestInit={method:req.method,headers,redirect:'manual'}
  if(!['GET','HEAD'].includes(req.method)) init.body=rawBody!==undefined?rawBody:req.body
  const upstream=await fetch(url,init)
  const outHeaders=new Headers(upstream.headers); for(const [k,v] of Object.entries(publicHeaders))if(!outHeaders.has(k))outHeaders.set(k,v)
  return new Response(upstream.body,{status:upstream.status,headers:outHeaders})
}
async function fetchRpcJson(url:string,req:Request,bearer:string,raw:string){
  const headers=upstreamHeaders(req,bearer); headers.set('accept','application/json, text/event-stream')
  const r=await fetch(url,{method:'POST',headers,body:raw,redirect:'manual'})
  if(!r.ok)return null
  const ct=r.headers.get('content-type')||''
  const text=await r.text()
  try{
    if(ct.includes('application/json'))return JSON.parse(text)
    if(ct.includes('text/event-stream')){
      const lines=text.split(/\r?\n/).filter(l=>l.startsWith('data:'))
      if(!lines.length)return null
      return JSON.parse(lines.map(l=>l.slice(5).trim()).join(''))
    }
    return JSON.parse(text)
  }catch{return null}
}
async function mergedToolsList(req:Request,connectionId:string,raw:string,owner:boolean){
  const [coreToken,opsToken]=await Promise.all([issueProxy(connectionId),issueProxy(connectionId)])
  const [core,ops]=await Promise.all([fetchRpcJson(CORE_URL,req,coreToken,raw),fetchRpcJson(OPS_URL,req,opsToken,raw)])
  if(!core?.result?.tools)return null
  const seen=new Set<string>(); const tools:any[]=[]
  for(const t of [...(core.result.tools||[]),...(ops?.result?.tools||[])]){if(!t?.name||seen.has(t.name))continue;seen.add(t.name);tools.push(t)}
  if(owner&&!seen.has(SANDBOX_TOOL))tools.push(sandboxTool())
  return {...core,result:{...core.result,tools}}
}
async function mergedResourcesList(req:Request,connectionId:string,raw:string,owner:boolean){
  const core=await fetchRpcJson(CORE_URL,req,await issueProxy(connectionId),raw)
  if(!core?.result?.resources)return core
  const resources=[...(core.result.resources||[])]
  if(owner&&!resources.some((r:any)=>String(r?.uri||'')===SANDBOX_RESOURCE_URI))resources.push(sandboxResource())
  return {...core,result:{...core.result,resources}}
}

type RoutingManifest={version?:string;policies?:Array<{title?:unknown;body?:unknown;priority?:unknown}>;tools?:Array<Record<string,unknown>>}
let routingCache:{until:number;manifest:RoutingManifest}|null=null
function routingText(value:unknown,max=1200){return typeof value==='string'?value.trim().slice(0,max):''}
function routingList(value:unknown,max=6){return Array.isArray(value)?value.map(v=>routingText(v,280)).filter(Boolean).slice(0,max):[]}
function routingGroupLabel(value:unknown){const key=routingText(value,80);return ({
  startup:'Startup and setup',opportunities:'Opportunities and readiness',leads:'Lead pursuit and outreach',
  knowledge_documents:'Knowledge and documents',jobs:'Job planning',briefing:'Briefing and alerts',
  integrations:'External context and action intents',equipment:'Equipment and research',other:'Focused operations'
} as Record<string,string>)[key]||'Focused operations'}
async function getRoutingManifest():Promise<RoutingManifest|null>{
  if(routingCache&&routingCache.until>Date.now())return routingCache.manifest
  const {data,error}=await admin.rpc('scout_get_mcp_routing_manifest_internal')
  if(error)throw error
  if(!data||typeof data!=='object'||Array.isArray(data))return null
  const manifest=data as RoutingManifest
  routingCache={until:Date.now()+30000,manifest}
  return manifest
}
function compilePublicInstructions(base:unknown,manifest:RoutingManifest,owner:boolean){
  const root=routingText(base,18000)
  const lines=['PUBLIC ROUTING (generated from Scout routing and capability contracts):']
  const policies=Array.isArray(manifest.policies)?[...manifest.policies]:[]
  policies.sort((a,b)=>Number(a?.priority||999)-Number(b?.priority||999))
  for(const policy of policies){
    const title=routingText(policy?.title,180),body=routingText(policy?.body,1600)
    if(title&&body)lines.push(`- ${title}: ${body}`)
  }
  const groups=new Map<string,Array<Record<string,unknown>>>()
  for(const row of Array.isArray(manifest.tools)?manifest.tools:[]){
    if(!row||typeof row!=='object')continue
    if(!owner&&routingText(row.tool_name,160)===SANDBOX_TOOL)continue
    const group=routingText(row.instruction_group,80)||'other'
    const rows=groups.get(group)||[];rows.push(row);groups.set(group,rows)
  }
  for(const [group,rows] of [...groups.entries()].sort((a,b)=>{
    const pa=Math.min(...a[1].map(r=>Number(r.instruction_priority||999)))
    const pb=Math.min(...b[1].map(r=>Number(r.instruction_priority||999)))
    return pa-pb||a[0].localeCompare(b[0])
  })){
    lines.push('',routingGroupLabel(group)+':')
    rows.sort((a,b)=>Number(a.instruction_priority||999)-Number(b.instruction_priority||999)||routingText(a.tool_name,120).localeCompare(routingText(b.tool_name,120)))
    for(const row of rows){
      const tool=routingText(row.tool_name,160),summary=routingText(row.summary,600)
      if(!tool||!summary)continue
      const when=routingList(row.when,3),notWhen=routingList(row.not_when,2),prefer=routingList(row.prefer_over,2),prereq=routingList(row.prerequisites,3),follow=routingList(row.usually_followed_by,3)
      const parts=[`Use ${tool} for ${summary}`]
      if(when.length)parts.push(`when ${when.join('; ')}`)
      if(notWhen.length)parts.push(`not when ${notWhen.join('; ')}`)
      if(prefer.length)parts.push(`prefer it over ${prefer.join(' or ')}`)
      if(prereq.length)parts.push(`requires ${prereq.join('; ')}`)
      if(follow.length)parts.push(`typical next: ${follow.join(' → ')}`)
      if(row.confirmation==='explicit')parts.push('requires explicit operator approval')
      const failure=row.failure_policy&&typeof row.failure_policy==='object'?(row.failure_policy as Record<string,unknown>):{}
      const retry=routingText(failure.retry||failure.on_blocked||failure.on_opt_in,500)
      if(retry)parts.push(`failure/retry: ${retry}`)
      const boundary=routingText((row.result_rules as any)?.boundary,600)
      if(boundary)parts.push(boundary)
      lines.push(`- ${parts.join('; ')}.`)
    }
  }
  const compiled=lines.join('\n')
  return root?root+'\n\n'+compiled:compiled
}
async function composedInitialize(req:Request,connectionId:string,raw:string,owner:boolean){
  const [core,manifest]=await Promise.all([
    fetchRpcJson(CORE_URL,req,await issueProxy(connectionId),raw),
    getRoutingManifest()
  ])
  if(!core?.result||!manifest)return core
  return {...core,result:{...core.result,instructions:compilePublicInstructions(core.result.instructions,manifest,owner)}}
}

Deno.serve(async(req:Request)=>{
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers:publicHeaders})
  const url=new URL(req.url)
  if(url.pathname.endsWith('/oauth-protected-resource')||url.searchParams.get('metadata')==='oauth-protected-resource'){
    return json({resource:RESOURCE_URL,resource_name:'Scout by Cadastory',authorization_servers:[AUTH_SERVER],bearer_methods_supported:['header']},200,{'cache-control':'public, max-age=300'})
  }
  const match=(req.headers.get('authorization')||'').match(/^Bearer\s+(.+)$/i)
  if(!match)return challenge()
  const token=match[1].trim()
  if(/^scout_[0-9a-f]{64}$/.test(token))return challenge('Scout OAuth access token required for this MCP endpoint')

  const {data:userResult,error:userError}=await admin.auth.getUser(token); const user=userResult.user
  if(userError||!user?.id||!user.email)return challenge('Valid Scout OAuth access token required')
  const payload=decodePayload(token); const clientId=uuid(payload?.client_id)
  if(!clientId)return challenge('OAuth client identity is missing from the access token')
  const {error:claimError}=await admin.rpc('scout_claim_google_account_internal',{p_user_id:user.id,p_email:user.email})
  if(claimError)return json({error:'forbidden',error_description:'This Google account is not approved for Scout.'},403)
  const {data:connection,error:bindError}=await admin.rpc('scout_resolve_oauth_agent_connection_internal',{p_user_id:user.id,p_oauth_client_id:clientId})
  if(bindError||!connection?.connection_id){const reason=connection?.reason==='oauth_consent_not_active'?'OAuth consent is not active for this Scout connection.':(bindError?.message||'Scout provider connection could not be resolved');return json({error:'forbidden',error_description:reason},403)}
  const owner=await isOwnerUser(user.id)

  let raw:string|undefined
  let rpcBody:any=null
  if(req.method==='POST'){
    raw=await req.clone().text()
    try{rpcBody=JSON.parse(raw)}catch{/* let core return protocol error */}
    if(rpcBody)await recordToolDimensions(user.id,clientId,connection.connection_id,rpcBody)
    if(!Array.isArray(rpcBody)&&rpcBody?.method==='initialize'){
      try{const initialized=await composedInitialize(req,connection.connection_id,raw,owner);if(initialized)return json(initialized)}catch(e){console.error('initialize routing composition failed',e)}
    }
    if(!Array.isArray(rpcBody)&&rpcBody?.method==='tools/list'){
      try{const merged=await mergedToolsList(req,connection.connection_id,raw,owner);if(merged)return json(merged)}catch(e){console.error('tools/list merge failed',e)}
    }
    if(!Array.isArray(rpcBody)&&rpcBody?.method==='resources/list'){
      try{const merged=await mergedResourcesList(req,connection.connection_id,raw,owner);if(merged)return json(merged)}catch(e){console.error('resources/list merge failed',e)}
    }
    if(!Array.isArray(rpcBody)&&rpcBody?.method==='tools/call'&&String(rpcBody?.params?.name||'')===SANDBOX_TOOL){
      if(!owner)return methodNotFound(rpcBody)
      try{return await forwardTo(SANDBOX_URL,req,token,raw)}catch{return json({error:'server_error',error_description:'Scout component sandbox request could not be prepared.'},500)}
    }
    if(!Array.isArray(rpcBody)&&rpcBody?.method==='resources/read'&&String(rpcBody?.params?.uri||'')===SANDBOX_RESOURCE_URI){
      if(!owner)return methodNotFound(rpcBody)
      try{return await forwardTo(SANDBOX_URL,req,token,raw)}catch{return json({error:'server_error',error_description:'Scout component sandbox resource could not be prepared.'},500)}
    }
    if(!Array.isArray(rpcBody)&&rpcBody?.method==='tools/call'&&OPS_TOOLS.has(String(rpcBody?.params?.name||''))){
      try{return await forwardTo(OPS_URL,req,await issueProxy(connection.connection_id),raw)}catch{return json({error:'server_error',error_description:'Scout operations MCP request could not be prepared.'},500)}
    }
  }
  try{return await forwardTo(CORE_URL,req,await issueProxy(connection.connection_id),raw)}catch{return json({error:'server_error',error_description:'Scout could not prepare the authenticated MCP request.'},500)}
})
