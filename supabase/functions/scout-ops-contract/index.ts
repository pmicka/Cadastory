import 'jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.115.0'

const SUPABASE_URL=Deno.env.get('SUPABASE_URL')!
let SERVICE_KEY=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')||''
try{SERVICE_KEY=JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS')||'{}').default||SERVICE_KEY}catch{}
if(!SERVICE_KEY)throw new Error('Scout operations contract gateway database secret unavailable')
const db=createClient(SUPABASE_URL,SERVICE_KEY,{auth:{persistSession:false,autoRefreshToken:false}})
const OPS_URL=`${SUPABASE_URL}/functions/v1/scout-ops-mcp`
const MAX_BODY_BYTES=65536
const headersBase={
 'access-control-allow-origin':'*','access-control-allow-headers':'authorization,content-type,accept,mcp-protocol-version,mcp-session-id,x-request-id,last-event-id',
 'access-control-expose-headers':'mcp-session-id,content-type','access-control-allow-methods':'GET,POST,DELETE,OPTIONS','cache-control':'no-store, max-age=0','pragma':'no-cache','referrer-policy':'no-referrer','x-content-type-options':'nosniff','x-scout-agent-contract':'v1'
}
type Rpc={jsonrpc?:string;id?:unknown;method?:string;result?:any;error?:any}
type C={tool_name:string;response_type_slug?:string;output_schema:any;annotations:any;model_visible?:boolean;contract_version?:number;routing?:any;routing_description?:string|null}
function json(body:unknown,status=200,extra?:HeadersInit){const h=new Headers(headersBase);if(extra)for(const[k,v]of new Headers(extra))h.set(k,v);h.set('content-type','application/json; charset=utf-8');return new Response(JSON.stringify(body),{status,headers:h})}
function sse(body:unknown,status=200,extra?:HeadersInit){const h=new Headers(headersBase);if(extra)for(const[k,v]of new Headers(extra))h.set(k,v);h.set('content-type','text/event-stream');return new Response(`event: message\ndata: ${JSON.stringify(body)}\n\n`,{status,headers:h})}
function wantsSse(req:Request){return(req.headers.get('accept')||'').includes('text/event-stream')}
async function manifest(){const{data,error}=await db.rpc('scout_get_agent_tool_contract_manifest_internal');if(error)throw error;const m=new Map<string,C>();for(const x of Array.isArray(data)?data:[])if(x?.tool_name)m.set(String(x.tool_name),x as C);return m}
async function parse(r:Response):Promise<Rpc|null>{const t=await r.clone().text(),ct=r.headers.get('content-type')||'';try{if(ct.includes('application/json'))return JSON.parse(t);if(ct.includes('text/event-stream')){const d=t.split(/\r?\n/).filter(x=>x.startsWith('data:')).map(x=>x.slice(5).trim()).join('');return d?JSON.parse(d):null}return JSON.parse(t)}catch{return null}}
function enriched(env:Rpc,contracts:Map<string,C>){if(!Array.isArray(env?.result?.tools))return env;const tools=[] as any[];for(const t of env.result.tools){const c=contracts.get(String(t?.name||''));if(c?.model_visible===false)continue;const routing=typeof c?.routing_description==='string'?c.routing_description.trim():'';const description=routing?[typeof t?.description==='string'?t.description.trim():'',routing].filter(Boolean).join('\n\n'):t?.description;tools.push(c?{...t,description,annotations:{...(t.annotations||{}),...(c.annotations||{})},outputSchema:c.output_schema||t.outputSchema,_meta:{...(t._meta||{}),'scout/contractVersion':c.contract_version??1,'scout/responseType':c.response_type_slug??null,'scout/routingVersion':c.routing?.version??null,'scout/routingGroup':c.routing?.instruction_group??null,'scout/confirmation':c.routing?.confirmation??null}}:t)}return{...env,result:{...env.result,tools}}}
async function forward(req:Request,raw?:string){const h=new Headers(req.headers);h.delete('host');h.delete('content-length');h.delete('cf-connecting-ip');const init:RequestInit={method:req.method,headers:h,redirect:'manual'};if(!['GET','HEAD'].includes(req.method))init.body=raw!==undefined?raw:req.body;return await fetch(OPS_URL,init)}
function passthrough(r:Response){const h=new Headers(r.headers);for(const[k,v]of Object.entries(headersBase))h.set(k,v);return new Response(r.body,{status:r.status,statusText:r.statusText,headers:h})}
Deno.serve(async(req:Request)=>{
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers:headersBase})
 if(!(req.headers.get('authorization')||'').match(/^Bearer\s+.+/i))return json({error:'missing Scout bearer token'},401)
 if(req.method!=='POST'){try{return passthrough(await forward(req))}catch{return json({error:'Scout operations contract gateway failed'},500)}}
 const declared=Number(req.headers.get('content-length')||0);if(declared>MAX_BODY_BYTES)return json({error:'request_too_large'},413)
 const raw=await req.clone().text();if(new TextEncoder().encode(raw).byteLength>MAX_BODY_BYTES)return json({error:'request_too_large'},413)
 let env:Rpc|null=null;try{const x=JSON.parse(raw);if(!Array.isArray(x)&&x&&typeof x==='object')env=x}catch{}
 try{const up=await forward(req,raw);if(env?.method==='tools/list'&&up.ok){const p=await parse(up);if(p){const e=enriched(p,await manifest());return wantsSse(req)?sse(e,up.status,up.headers):json(e,up.status,up.headers)}}return passthrough(up)}catch(e){console.error('Scout ops contract gateway',e);return json({error:'Scout operations contract gateway failed'},500)}
})
