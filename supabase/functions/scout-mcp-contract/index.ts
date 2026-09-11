import 'jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.115.0'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
let SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
try { const keys = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') || '{}'); SERVICE_KEY = keys.default || SERVICE_KEY } catch {}
if (!SERVICE_KEY) throw new Error('Scout contract gateway database secret is unavailable')
const db = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession:false, autoRefreshToken:false } })

const CORE_URL = `${SUPABASE_URL}/functions/v1/scout-mcp`
const IMPROVE_URL = `${SUPABASE_URL}/functions/v1/scout-review-mcp`
const EXPLORE_URL = `${SUPABASE_URL}/functions/v1/scout-explore-mcp`
const UI_LAB_URL = `${SUPABASE_URL}/functions/v1/scout-component-sandbox-mcp`
const IMPROVE_RESOURCE_URI = 'ui://scout/improve/v1'
const LEGACY_REVIEW_RESOURCE_URI = 'ui://scout/rapid-review/v1'
const LENS_RESOURCE_URI = 'ui://scout/lens/v1'
const TIME_RESOURCE_URI = 'ui://scout/evidence-time-machine/v1'
const CONSTELLATION_RESOURCE_URI = 'ui://scout/constellations/v1'
const SANDBOX_RESOURCE_URI = 'ui://scout/component-sandbox/v3'
const SANDBOX_COMPATIBILITY_RESOURCE_URIS = ['ui://scout/component-sandbox/v2','ui://scout/component-sandbox/v1']
const SANDBOX_TOOL = 'scout_preview_component_sandbox'
const IMPROVE_TOOLS = new Set(['scout_start_improve_scout','scout_get_improve_scout_state','scout_submit_improvement_answer','scout_review_lead','scout_start_rapid_review','scout_get_rapid_review_state'])
const EXPLORE_TOOLS = new Set(['scout_get_opportunity_lens_catalog','scout_apply_opportunity_lens','scout_get_opportunity_timeline','scout_get_opportunity_constellation'])
const IMPROVE_RESOURCES = new Set([IMPROVE_RESOURCE_URI,LEGACY_REVIEW_RESOURCE_URI])
const EXPLORE_RESOURCES = new Set([LENS_RESOURCE_URI,TIME_RESOURCE_URI,CONSTELLATION_RESOURCE_URI])
const EXPLORE_TOOL_RESOURCE = new Map<string,string>([
  ['scout_get_opportunity_lens_catalog',LENS_RESOURCE_URI],
  ['scout_apply_opportunity_lens',LENS_RESOURCE_URI],
  ['scout_get_opportunity_timeline',TIME_RESOURCE_URI],
  ['scout_get_opportunity_constellation',CONSTELLATION_RESOURCE_URI],
])
const EXPLORE_RESOURCE_DESCRIPTION = new Map<string,string>([
  [LENS_RESOURCE_URI,'Scout Lens interactively narrows an already surfaced candidate set using safe semantic dimensions; it never expands discovery.'],
  [TIME_RESOURCE_URI,'Evidence Time Machine renders the chronology for one already surfaced Scout opportunity while preserving fact, inference, counter-evidence, decision, and future-milestone distinctions.'],
  [CONSTELLATION_RESOURCE_URI,'Opportunity Constellations renders explainable relationships among only the supplied already surfaced Scout opportunities; it never adds hidden nodes.'],
])
const PRIVACY_CONTRACT = 'privacy-contract-v2'
const EXPOSURE_CONTRACT = 'scout-exposure-v1'
const ENUMERATION_CONTRACT = 'scout-enumeration-v1'
const MAX_BODY_BYTES = 131072

const corsHeaders = {
  'access-control-allow-origin':'*',
  'access-control-allow-headers':'authorization,content-type,accept,mcp-protocol-version,mcp-session-id,x-request-id,last-event-id',
  'access-control-expose-headers':'mcp-session-id,content-type',
  'access-control-allow-methods':'GET,POST,DELETE,OPTIONS',
  'cache-control':'no-store, max-age=0','pragma':'no-cache','referrer-policy':'no-referrer','x-content-type-options':'nosniff','x-scout-agent-contract':'v2',
}
type Connection={connection_id:string;scopes:string[];expires_at?:string|null}
type RpcEnvelope={jsonrpc?:string;id?:unknown;method?:string;params?:any;result?:any;error?:any}
type ContractRow={tool_name:string;response_type_slug?:string;output_schema:any;annotations:any;model_visible?:boolean;app_visible?:boolean;contract_version?:number;routing?:any;routing_description?:string|null}

function jsonResponse(body:unknown,status=200,extra?:HeadersInit){const h=new Headers(corsHeaders);if(extra)for(const [k,v] of new Headers(extra))h.set(k,v);h.set('content-type','application/json; charset=utf-8');return new Response(JSON.stringify(body),{status,headers:h})}
function sseResponse(body:unknown,status=200,extra?:HeadersInit){const h=new Headers(corsHeaders);if(extra)for(const [k,v] of new Headers(extra))h.set(k,v);h.set('content-type','text/event-stream');return new Response(`event: message\ndata: ${JSON.stringify(body)}\n\n`,{status,headers:h})}
function wantsSse(req:Request){return (req.headers.get('accept')||'').includes('text/event-stream')}
function rpcResponse(req:Request,body:unknown,status=200,extra?:HeadersInit){return wantsSse(req)?sseResponse(body,status,extra):jsonResponse(body,status,extra)}
function safeError(req:Request,id:unknown,code:number,message:string,status=200){return rpcResponse(req,{jsonrpc:'2.0',id:id??null,error:{code,message}},status)}
function looksLikeSecret(s:string){return /-----BEGIN [A-Z ]*PRIVATE KEY-----/.test(s)||/\bsb_secret_[A-Za-z0-9_-]{12,}\b/.test(s)||/\bsk-(?:proj-)?[A-Za-z0-9_-]{20,}\b/.test(s)||/\bgh[pousr]_[A-Za-z0-9]{20,}\b/.test(s)||/\bxox[baprs]-[A-Za-z0-9-]{10,}\b/.test(s)||/\bBearer\s+[A-Za-z0-9._~-]{20,}\b/i.test(s)||/\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b/.test(s)}
function validMachine(s:unknown,max=120){return typeof s==='string'&&s.length<=max&&/^[a-z][a-z0-9_.-]*$/.test(s)}
async function readBody(req:Request){const declared=Number(req.headers.get('content-length')||0);if(declared>MAX_BODY_BYTES)throw new Error('request_too_large');const text=await req.text();if(new TextEncoder().encode(text).byteLength>MAX_BODY_BYTES)throw new Error('request_too_large');return text}
async function resolveConnection(token:string):Promise<Connection|null>{const {data,error}=await db.rpc('scout_resolve_agent_connection_v4',{p_token:token,p_privacy_contract:PRIVACY_CONTRACT,p_exposure_contract:EXPOSURE_CONTRACT,p_enumeration_contract:ENUMERATION_CONTRACT});if(error||!data?.connection_id)return null;return data as Connection}
async function isOwnerConnection(connectionId:string):Promise<boolean>{
  const {data,error}=await db.rpc('scout_is_owner_connection_internal',{p_connection_id:connectionId})
  return !error&&data===true
}
async function issueProxy(connectionId:string){const {data,error}=await db.rpc('scout_issue_connection_proxy_token_internal',{p_connection_id:connectionId,p_ttl_seconds:120});if(error||!data?.token)throw new Error('Scout contract gateway could not prepare upstream authentication');return String(data.token)}
async function prepareFanout(token:string,count:number):Promise<{connection:Connection;tokens:string[]}|null>{const connection=await resolveConnection(token);if(!connection)return null;const tokens=await Promise.all(Array.from({length:count},()=>issueProxy(connection.connection_id)));return {connection,tokens}}
async function manifest():Promise<Map<string,ContractRow>>{const {data,error}=await db.rpc('scout_get_agent_tool_contract_manifest_internal');if(error)throw error;const map=new Map<string,ContractRow>();for(const row of Array.isArray(data)?data:[])if(row?.tool_name)map.set(String(row.tool_name),row as ContractRow);return map}
function knowledgeTool(){return {name:'scout_search_knowledge',title:'Search Scout Field Knowledge',description:'Search Scout curated technical, manufacturer, regulatory, standards, research, industry and reviewed field evidence for one bounded business/technical question. Use for general evidence questions; use scout_get_cleaning_compatibility instead when the question is specifically about the connected operator selected rig/product combination. Search text is transient and must not contain chat history, credentials, secrets, or unrelated personal context.',inputSchema:{type:'object',properties:{query:{type:'string',minLength:1,maxLength:300},service_slug:{type:'string',pattern:'^[a-z][a-z0-9_.-]{0,119}$'},jurisdiction:{type:'string',maxLength:40},limit:{type:'integer',minimum:1,maximum:20}},required:['query'],additionalProperties:false}}}
function sandboxTool(){return {name:SANDBOX_TOOL,title:'Preview Scout UI Foundation',description:'Owner-only read-only developer tool that renders the minimal Scout MCP Apps View with a bounded set of real Scout exemplars. Call only when the Scout owner explicitly asks to test or preview the Scout sandbox UI foundation.',inputSchema:{type:'object',properties:{},additionalProperties:false},outputSchema:{type:'object',properties:{surface:{type:'string',enum:['scout_component_sandbox']},version:{type:'string',enum:['v2']},business_data:{type:'boolean',enum:[true]},interaction_scope:{type:'string',enum:['ephemeral_only']},foundation:{type:'string',enum:['ready']},exemplars:{type:'array',maxItems:4,items:{type:'object',properties:{name:{type:'string',minLength:1,maxLength:160},kind:{type:'string',enum:['property','group']},archetype:{type:['string','null'],minLength:1,maxLength:100},resolution_status:{type:['string','null'],minLength:1,maxLength:100}},required:['name','kind','archetype','resolution_status'],additionalProperties:false}}},required:['surface','version','business_data','interaction_scope','foundation','exemplars'],additionalProperties:false},annotations:{readOnlyHint:true,destructiveHint:false,idempotentHint:true,openWorldHint:false},_meta:{ui:{resourceUri:SANDBOX_RESOURCE_URI}}}}
function sandboxResource(){return {uri:SANDBOX_RESOURCE_URI,name:'scout-ui-foundation',title:'Scout UI Foundation',description:'Owner-only minimal Scout MCP Apps View used to verify rendering and host-bridge delivery.',mimeType:'text/html;profile=mcp-app'}}
function exploreToolMeta(name:string,base:any){const uri=EXPLORE_TOOL_RESOURCE.get(name);if(!uri)return base||{};return {...(base||{}),ui:{...((base||{}).ui||{}),resourceUri:uri},'ui/resourceUri':uri,'openai/outputTemplate':uri,'openai/widgetAccessible':true}}
function enrichTool(tool:any,contracts:Map<string,ContractRow>){const name=String(tool?.name||'');const c=contracts.get(name);const baseMeta=exploreToolMeta(name,tool?._meta);if(!c)return {...tool,_meta:baseMeta};const routing=typeof c.routing_description==='string'?c.routing_description.trim():'';const description=routing?[typeof tool?.description==='string'?tool.description.trim():'',routing].filter(Boolean).join('\n\n'):tool?.description;return {...tool,description,annotations:{...(tool.annotations||{}),...(c.annotations||{})},outputSchema:c.output_schema||tool.outputSchema,_meta:{...baseMeta,'scout/contractVersion':c.contract_version??1,'scout/responseType':c.response_type_slug??null,'scout/routingVersion':c.routing?.version??null,'scout/routingGroup':c.routing?.instruction_group??null,'scout/confirmation':c.routing?.confirmation??null}}}
function enrichToolList(env:RpcEnvelope,contracts:Map<string,ContractRow>){if(!Array.isArray(env?.result?.tools))return env;const seen=new Set<string>();const tools:any[]=[];for(const raw of env.result.tools){const name=String(raw?.name||'');if(!name||seen.has(name))continue;seen.add(name);const c=contracts.get(name);if(c?.model_visible===false)continue;tools.push(enrichTool(raw,contracts))}if(!seen.has('scout_search_knowledge'))tools.push(enrichTool(knowledgeTool(),contracts));return {...env,result:{...env.result,tools}}}
async function parseUpstream(upstream:Response):Promise<RpcEnvelope|null>{const text=await upstream.clone().text();const ct=upstream.headers.get('content-type')||'';try{if(ct.includes('application/json'))return JSON.parse(text);if(ct.includes('text/event-stream')){const lines=text.split(/\r?\n/).filter(l=>l.startsWith('data:'));if(!lines.length)return null;return JSON.parse(lines.map(l=>l.slice(5).trim()).join(''))}return JSON.parse(text)}catch{return null}}
function responseFromUpstream(req:Request,upstream:Response,body?:unknown){const h=new Headers(upstream.headers);for(const [k,v] of Object.entries(corsHeaders))h.set(k,v);if(body!==undefined)return rpcResponse(req,body,upstream.status,h);return new Response(upstream.body,{status:upstream.status,statusText:upstream.statusText,headers:h})}
async function forwardTo(url:string,req:Request,raw?:string,bearer?:string){const h=new Headers(req.headers);if(bearer)h.set('authorization',`Bearer ${bearer}`);h.delete('host');h.delete('content-length');h.delete('cf-connecting-ip');const init:RequestInit={method:req.method,headers:h,redirect:'manual'};if(!['GET','HEAD'].includes(req.method))init.body=raw!==undefined?raw:req.body;return await fetch(url,init)}
async function fetchRpc(url:string,req:Request,raw:string,bearer?:string){const upstream=await forwardTo(url,req,raw,bearer);if(!upstream.ok)return {upstream,parsed:null};return {upstream,parsed:await parseUpstream(upstream)}}
function mergeToolEnvelopes(core:RpcEnvelope,...extras:(RpcEnvelope|null)[]){const seen=new Set<string>();const tools:any[]=[];for(const env of [core,...extras])for(const t of env?.result?.tools||[]){if(!t?.name||seen.has(t.name))continue;seen.add(t.name);tools.push(t)}return {...core,result:{...core.result,tools}}}
function mergeResourceEnvelopes(core:RpcEnvelope|null,id:unknown,...extras:(RpcEnvelope|null)[]){const seen=new Set<string>();const resources:any[]=[];for(const env of [core,...extras])for(const r of env?.result?.resources||[]){if(!r?.uri||seen.has(r.uri))continue;seen.add(r.uri);resources.push(r)}return {jsonrpc:'2.0',id:id??null,result:{resources}}}
function enrichInitialize(env:RpcEnvelope|null){if(!env?.result)return env;const capabilities=(env.result.capabilities&&typeof env.result.capabilities==='object')?env.result.capabilities:{};return {...env,result:{...env.result,capabilities:{...capabilities,resources:{...((capabilities as any).resources||{})}}}}}
function enrichExploreResource(env:RpcEnvelope|null,uri:string){if(!env?.result?.contents||!Array.isArray(env.result.contents))return env;const description=EXPLORE_RESOURCE_DESCRIPTION.get(uri)||'Interactive Scout known-candidate exploration surface.';return {...env,result:{...env.result,contents:env.result.contents.map((content:any)=>{if(String(content?.uri||'')!==uri)return content;const meta=content?._meta&&typeof content._meta==='object'?content._meta:{};const ui=meta.ui&&typeof meta.ui==='object'?meta.ui:{};const modernCsp=ui.csp&&typeof ui.csp==='object'?ui.csp:{};const resourceDomains=Array.isArray(modernCsp.resourceDomains)?modernCsp.resourceDomains:['https://esm.sh'];const connectDomains=Array.isArray(modernCsp.connectDomains)?modernCsp.connectDomains:[];return {...content,_meta:{...meta,ui:{...ui,prefersBorder:false,csp:{...modernCsp,connectDomains,resourceDomains}},'openai/widgetDescription':description,'openai/widgetPrefersBorder':false,'openai/widgetCSP':{connect_domains:connectDomains,resource_domains:resourceDomains}}}})}}}
async function audit(connection:Connection,toolName:string,outcome:string,requestBytes:number,httpStatus:number,requestId:string|null,flags:string[]=[]){try{await db.rpc('scout_record_agent_request_event',{p_connection_id:connection.connection_id,p_tool_name:toolName,p_protocol_method:'tools/call',p_outcome:outcome,p_request_bytes:requestBytes,p_argument_keys:['query','service_slug','jurisdiction','limit'],p_privacy_flags:flags,p_duration_ms:0,p_http_status:httpStatus,p_request_id:requestId})}catch{}}
async function callKnowledge(req:Request,env:RpcEnvelope,raw:string,token:string){const connection=await resolveConnection(token);if(!connection)return jsonResponse({error:'invalid or expired Scout connection'},401);if(!connection.scopes?.includes('knowledge:read')){await audit(connection,'scout_search_knowledge','rejected_scope',raw.length,403,String(env.id??''));return safeError(req,env.id,-32003,'connection does not grant knowledge:read',200)}const args=env?.params?.arguments;if(!args||typeof args!=='object'||Array.isArray(args)){await audit(connection,'scout_search_knowledge','rejected_privacy',raw.length,422,String(env.id??''),['invalid_arguments']);return safeError(req,env.id,-32602,'invalid Scout knowledge arguments',200)}const keys=Object.keys(args),allowed=new Set(['query','service_slug','jurisdiction','limit']);if(keys.some(k=>!allowed.has(k))){await audit(connection,'scout_search_knowledge','rejected_privacy',raw.length,422,String(env.id??''),['unknown_argument']);return safeError(req,env.id,-32602,'Scout rejected fields outside the knowledge-search contract',200)}const query=typeof args.query==='string'?args.query.trim():'';const service=args.service_slug,jurisdiction=args.jurisdiction,limit=args.limit===undefined?10:args.limit;if(!query||query.length>300||looksLikeSecret(query)||!Number.isInteger(limit)||limit<1||limit>20||(service!==undefined&&!validMachine(service))||(jurisdiction!==undefined&&(typeof jurisdiction!=='string'||jurisdiction.length>40))){await audit(connection,'scout_search_knowledge','rejected_privacy',raw.length,422,String(env.id??''),['invalid_or_sensitive_argument']);return safeError(req,env.id,-32602,'invalid or out-of-scope Scout knowledge arguments',200)}const {data,error}=await db.rpc('scout_search_knowledge_internal',{p_query:query,p_service_slug:service??null,p_jurisdiction:jurisdiction??null,p_limit:limit});if(error){await audit(connection,'scout_search_knowledge','error',raw.length,500,String(env.id??''));return safeError(req,env.id,-32603,'Scout knowledge search failed',200)}let payload:any=data;try{const decorated=await db.rpc('scout_decorate_agent_response_v2',{p_connection_id:connection.connection_id,p_tool_name:'scout_search_knowledge',p_payload:data??null});if(!decorated.error)payload=decorated.data}catch{}await audit(connection,'scout_search_knowledge','allowed',raw.length,200,String(env.id??''));return rpcResponse(req,{jsonrpc:'2.0',id:env.id??null,result:{content:[{type:'text',text:JSON.stringify(payload,null,2)}],structuredContent:payload&&typeof payload==='object'&&!Array.isArray(payload)?payload:{result:payload}}})}
async function forwardOwnerSandbox(req:Request,env:RpcEnvelope,raw:string,inboundToken:string){
  const connection=await resolveConnection(inboundToken)
  if(!connection||!(await isOwnerConnection(connection.connection_id)))return safeError(req,env.id,-32601,'Method not found')
  try{return responseFromUpstream(req,await forwardTo(UI_LAB_URL,req,raw,await issueProxy(connection.connection_id)))}catch{return safeError(req,env.id,-32603,'Scout UI request failed')}
}

Deno.serve(async(req:Request)=>{
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers:corsHeaders})
  const auth=req.headers.get('authorization')||'',m=auth.match(/^Bearer\s+(.+)$/i);if(!m)return jsonResponse({error:'missing Scout bearer token'},401)
  const inboundToken=m[1].trim()
  if(req.method!=='POST'){try{return responseFromUpstream(req,await forwardTo(CORE_URL,req))}catch{return jsonResponse({error:'Scout MCP contract gateway failed'},500)}}
  let raw='';try{raw=await readBody(req.clone())}catch{return jsonResponse({error:'Scout MCP request exceeds the privacy gateway size limit'},413)}
  let env:RpcEnvelope|null=null;try{const x=JSON.parse(raw);if(!Array.isArray(x)&&x&&typeof x==='object')env=x}catch{}
  if(env?.method==='initialize'){
    try{const upstream=await forwardTo(CORE_URL,req,raw);const parsed=await parseUpstream(upstream);return responseFromUpstream(req,upstream,enrichInitialize(parsed)??undefined)}catch(e){console.error('Scout initialize enrichment error',e);return jsonResponse({error:'Scout MCP contract gateway failed'},500)}
  }
  if(env?.method==='tools/call'&&env?.params?.name===SANDBOX_TOOL)return await forwardOwnerSandbox(req,env,raw,inboundToken)
  if(env?.method==='resources/read'&&[SANDBOX_RESOURCE_URI,...SANDBOX_COMPATIBILITY_RESOURCE_URIS].includes(String(env?.params?.uri||'')))return await forwardOwnerSandbox(req,env,raw,inboundToken)
  if(env?.method==='tools/call'&&env?.params?.name==='scout_search_knowledge')return await callKnowledge(req,env,raw,inboundToken)
  if(env?.method==='tools/call'&&IMPROVE_TOOLS.has(String(env?.params?.name||''))){try{return responseFromUpstream(req,await forwardTo(IMPROVE_URL,req,raw))}catch{return safeError(req,env.id,-32603,'Improve Scout request failed')}}
  if(env?.method==='tools/call'&&EXPLORE_TOOLS.has(String(env?.params?.name||''))){try{return responseFromUpstream(req,await forwardTo(EXPLORE_URL,req,raw))}catch{return safeError(req,env.id,-32603,'Scout exploration request failed')}}
  if(env?.method==='resources/read'&&IMPROVE_RESOURCES.has(String(env?.params?.uri||''))){try{return responseFromUpstream(req,await forwardTo(IMPROVE_URL,req,raw))}catch{return safeError(req,env.id,-32603,'Improve Scout resource failed')}}
  if(env?.method==='resources/read'&&EXPLORE_RESOURCES.has(String(env?.params?.uri||''))){try{const uri=String(env?.params?.uri||'');const upstream=await forwardTo(EXPLORE_URL,req,raw);const parsed=await parseUpstream(upstream);return responseFromUpstream(req,upstream,enrichExploreResource(parsed,uri)??undefined)}catch{return safeError(req,env.id,-32603,'Scout exploration resource failed')}}
  if(env?.method==='tools/list'){
    try{
      const fanout=await prepareFanout(inboundToken,3)
      if(!fanout)return jsonResponse({error:'invalid or expired Scout connection'},401)
      const [coreToken,improveToken,exploreToken]=fanout.tokens
      const [coreR,improveR,exploreR]=await Promise.all([fetchRpc(CORE_URL,req,raw,coreToken),fetchRpc(IMPROVE_URL,req,raw,improveToken),fetchRpc(EXPLORE_URL,req,raw,exploreToken)])
      if(coreR.parsed){
        const merged=mergeToolEnvelopes(coreR.parsed,improveR.parsed,exploreR.parsed)
        if(await isOwnerConnection(fanout.connection.connection_id))merged.result.tools.push(sandboxTool())
        const contracts=await manifest()
        return responseFromUpstream(req,coreR.upstream,enrichToolList(merged,contracts))
      }
      return responseFromUpstream(req,coreR.upstream)
    }catch(e){console.error('Scout tool-list merge error',e);return jsonResponse({error:'Scout MCP contract gateway failed'},500)}
  }
  if(env?.method==='resources/list'){
    try{
      const fanout=await prepareFanout(inboundToken,3)
      if(!fanout)return jsonResponse({error:'invalid or expired Scout connection'},401)
      const [coreToken,improveToken,exploreToken]=fanout.tokens
      const [coreR,improveR,exploreR]=await Promise.all([fetchRpc(CORE_URL,req,raw,coreToken),fetchRpc(IMPROVE_URL,req,raw,improveToken),fetchRpc(EXPLORE_URL,req,raw,exploreToken)])
      if(coreR.parsed||improveR.parsed||exploreR.parsed){
        const merged=mergeResourceEnvelopes(coreR.parsed,env.id,improveR.parsed,exploreR.parsed)
        if(await isOwnerConnection(fanout.connection.connection_id))merged.result.resources.push(sandboxResource())
        return rpcResponse(req,merged)
      }
      return responseFromUpstream(req,coreR.upstream)
    }catch(e){console.error('Scout resource-list merge error',e);return jsonResponse({error:'Scout MCP contract gateway failed'},500)}
  }
  try{const upstream=await forwardTo(CORE_URL,req,raw);return responseFromUpstream(req,upstream)}catch(e){console.error('Scout contract gateway error',e);return jsonResponse({error:'Scout MCP contract gateway failed'},500)}
})
