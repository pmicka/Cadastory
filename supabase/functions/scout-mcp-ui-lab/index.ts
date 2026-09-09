import 'jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.57.4'
import { McpServer } from 'npm:@modelcontextprotocol/sdk@1.29.0/server/mcp.js'
import { WebStandardStreamableHTTPServerTransport } from 'npm:@modelcontextprotocol/sdk@1.29.0/server/webStandardStreamableHttp.js'
import { registerAppResource, registerAppTool, RESOURCE_MIME_TYPE } from 'npm:@modelcontextprotocol/ext-apps@1.7.5/server'
import * as z from 'npm:zod@4.2.0/v4'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
let SECRET_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
try {
  const keys = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') || '{}')
  SECRET_KEY = keys.default || SECRET_KEY
} catch {}
if (!SECRET_KEY) throw new Error('Scout UI lab database secret is unavailable')
const db = createClient(SUPABASE_URL, SECRET_KEY, { auth: { persistSession: false, autoRefreshToken: false } })

const PRIVACY_CONTRACT = 'privacy-contract-v2'
const EXPOSURE_CONTRACT = 'scout-exposure-v1'
const ENUMERATION_CONTRACT = 'scout-enumeration-v1'
const RESOURCE_URI = 'ui://scout/component-sandbox/v1'
const TOOL_NAME = 'scout_preview_component_sandbox'

type Connection = { connection_id:string; scopes?:string[]; expires_at?:string|null }

const COMPONENT_SANDBOX_HTML = String.raw`<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover" />
<meta name="color-scheme" content="light dark" />
<title>Scout component sandbox</title>
<style>
:root{
  color-scheme:light dark;
  --bg:light-dark(#f4f6f2,#101210);
  --card:light-dark(#ffffff,#1c1f1c);
  --subtle:light-dark(#f6f8f5,#252925);
  --media-a:light-dark(#dfe7dc,#2f3930);
  --media-b:light-dark(#e7e1d5,#39352e);
  --media-c:light-dark(#dce5e8,#2d383c);
  --text:light-dark(#171b17,#f2f5f1);
  --muted:light-dark(#747d73,#aeb6ad);
  --line:light-dark(#dde2da,#3a4039);
  --accent:light-dark(#4d6b52,#7fa586);
  --accent-soft:light-dark(#eef3ed,#273228);
  --button:light-dark(#263128,#dfe9df);
  --button-text:light-dark(#ffffff,#182019);
  font-family:ui-sans-serif,system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;
}
*{box-sizing:border-box}html,body{margin:0;padding:0;background:transparent;color:var(--text)}
body{padding:10px 6px 12px}.shell{max-width:520px;margin:0 auto}.card{background:var(--card);border:1px solid var(--line);border-radius:22px;overflow:hidden;box-shadow:0 10px 28px rgba(20,28,20,.08)}
.inner{padding:18px 18px 16px}.top{display:flex;align-items:center;gap:9px}.dot{width:10px;height:10px;border-radius:50%;background:var(--accent);flex:none}.brand{font-size:14px;font-weight:700}.preview{font-size:12px;color:var(--muted);margin-top:1px}.more{margin-left:auto;width:36px;height:36px;border:1px solid var(--line);border-radius:50%;background:var(--subtle);color:var(--text);font-size:19px;line-height:1;display:grid;place-items:center}
.rule{height:1px;background:var(--line);margin:16px 0 18px}.title{font-size:22px;line-height:1.15;letter-spacing:-.02em;font-weight:750;margin:0 0 11px}.meta{display:flex;align-items:center;gap:8px;flex-wrap:wrap;font-size:12px;color:var(--muted)}.pill{background:var(--accent-soft);color:var(--accent);border-radius:999px;padding:6px 10px;font-weight:700}.label{font-size:12px;font-weight:700;margin:20px 0 8px}
.carousel{display:flex;gap:10px;overflow-x:auto;scroll-snap-type:x mandatory;scrollbar-width:none;border-radius:16px}.carousel::-webkit-scrollbar{display:none}.slide{position:relative;min-width:86%;height:200px;border-radius:16px;scroll-snap-align:start;display:grid;place-items:center;text-align:center;color:var(--muted);overflow:hidden}.slide:nth-child(1){background:var(--media-a)}.slide:nth-child(2){background:var(--media-b)}.slide:nth-child(3){background:var(--media-c)}.diamond{width:18px;height:18px;border:2px solid currentColor;transform:rotate(45deg);position:absolute;left:18px;top:18px}.circle{width:44px;height:44px;border-radius:50%;background:color-mix(in srgb,var(--card) 76%,transparent);margin:0 auto 16px}.slide b{display:block;font-size:13px;color:var(--text);font-weight:600}.slide small{display:block;font-size:11px;margin-top:6px}.counter{position:absolute;right:12px;bottom:12px;background:color-mix(in srgb,var(--text) 88%,transparent);color:var(--card);border-radius:999px;padding:5px 9px;font-size:11px;font-weight:700}.pager{display:flex;justify-content:center;gap:7px;margin-top:10px}.page-dot{width:7px;height:7px;border-radius:50%;background:var(--line)}.page-dot.on{background:var(--accent)}
.copy{font-size:13px;line-height:1.55;color:color-mix(in srgb,var(--text) 78%,var(--muted));margin:20px 0}.select{width:100%;min-height:46px;border:1px solid var(--line);border-radius:12px;background:var(--subtle);color:var(--text);padding:0 13px;font:inherit;font-size:13px}.row{display:flex;align-items:center;gap:14px;margin-top:18px}.grow{flex:1;min-width:0}.row-title{font-size:13px;font-weight:600}.row-sub{font-size:11px;color:var(--muted);margin-top:4px}.switch{width:50px;height:30px;border:0;border-radius:999px;background:var(--accent);padding:3px;cursor:pointer;flex:none}.knob{width:24px;height:24px;border-radius:50%;background:#fff;transform:translateX(20px);transition:transform .16s ease}.switch[aria-checked="false"]{background:var(--line)}.switch[aria-checked="false"] .knob{transform:translateX(0)}
.timeline-head{display:flex;justify-content:space-between;gap:12px;align-items:center;margin-top:22px}.timeline-value{font-size:12px;color:var(--accent)}input[type=range]{width:100%;accent-color:var(--accent);margin:14px 0 3px}.ticks{display:grid;grid-template-columns:repeat(6,1fr);font-size:10px;color:var(--muted)}.ticks span{text-align:center}.ticks span:first-child{text-align:left}.ticks span:last-child{text-align:right}.ticks .active{color:var(--accent);font-weight:700}
.chips{display:flex;gap:8px;flex-wrap:wrap}.chip{border:1px solid var(--line);background:var(--subtle);border-radius:999px;padding:7px 11px;font-size:11px;color:var(--muted)}.footer{border-top:1px solid var(--line);padding:16px 18px;display:grid;grid-template-columns:1fr 1.25fr;gap:10px}.action{min-height:44px;border-radius:12px;border:1px solid var(--line);background:var(--subtle);color:var(--text);font:inherit;font-size:12px;font-weight:700;cursor:pointer}.action.primary{background:var(--button);border-color:var(--button);color:var(--button-text)}.live{padding:0 18px 14px;min-height:20px;color:var(--muted);font-size:11px}
button:focus-visible,select:focus-visible,input:focus-visible{outline:3px solid var(--accent);outline-offset:2px}@media(max-width:360px){.inner{padding-left:14px;padding-right:14px}.footer{padding-left:14px;padding-right:14px}.slide{min-width:92%;height:190px}.title{font-size:20px}}@media(prefers-reduced-motion:reduce){*{scroll-behavior:auto!important;transition:none!important}}
</style>
</head>
<body>
<main class="shell" aria-label="Scout owner component sandbox">
<section class="card">
  <div class="inner">
    <div class="top"><span class="dot" aria-hidden="true"></span><div><div class="brand">Scout</div><div class="preview">Component preview</div></div><button class="more" aria-label="More preview options">•••</button></div>
    <div class="rule"></div>
    <h1 class="title">Example opportunity card</h1>
    <div class="meta"><span class="pill">Worth investigating</span><span>Updated 2h ago</span><span aria-hidden="true">•</span><span>4 evidence items</span></div>
    <div class="label">Media</div>
    <div class="carousel" id="carousel" aria-label="Placeholder image carousel">
      <div class="slide"><span class="diamond" aria-hidden="true"></span><div><div class="circle"></div><b>Placeholder image 1</b><small>Swipe horizontally</small></div><span class="counter">1 / 3</span></div>
      <div class="slide"><span class="diamond" aria-hidden="true"></span><div><div class="circle"></div><b>Placeholder image 2</b><small>Swipe horizontally</small></div><span class="counter">2 / 3</span></div>
      <div class="slide"><span class="diamond" aria-hidden="true"></span><div><div class="circle"></div><b>Placeholder image 3</b><small>Swipe horizontally</small></div><span class="counter">3 / 3</span></div>
    </div>
    <div class="pager" aria-hidden="true"><i class="page-dot on"></i><i class="page-dot"></i><i class="page-dot"></i></div>
    <p class="copy">Lorem ipsum dolor sit amet, consectetur adipiscing elit. Integer posuere erat a ante venenatis dapibus posuere velit aliquet.</p>
    <div class="label">View</div>
    <select class="select" aria-label="Preview view"><option>Evidence summary</option><option>Access summary</option><option>Timing summary</option></select>
    <div class="row"><div class="grow"><div class="row-title">Include lower-confidence signals</div><div class="row-sub">Useful for testing progressive disclosure.</div></div><button class="switch" id="signalSwitch" role="switch" aria-checked="true" aria-label="Include lower-confidence signals"><span class="knob"></span></button></div>
    <div class="timeline-head"><span class="label" style="margin:0">Evidence timeline</span><span class="timeline-value" id="timelineValue">Past 90 days</span></div>
    <input id="timeline" type="range" min="0" max="5" step="1" value="2" aria-label="Evidence timeline range" />
    <div class="ticks" id="ticks"><span>1y</span><span>6m</span><span class="active">90d</span><span>30d</span><span>7d</span><span>Now</span></div>
    <div class="label">Standard controls</div><div class="chips"><span class="chip">Evidence</span><span class="chip">Access</span><span class="chip">Timing</span></div>
  </div>
  <div class="footer"><button class="action" id="save">Save for later</button><button class="action primary" id="investigate">Investigate</button></div>
  <div class="live" id="live" aria-live="polite">Static owner-only preview · controls are local to this card.</div>
</section>
</main>
<script>
const carousel=document.getElementById('carousel');const dots=[...document.querySelectorAll('.page-dot')];
function updatePager(){const slides=[...carousel.children];let best=0,bestD=Infinity;for(let i=0;i<slides.length;i++){const d=Math.abs(slides[i].offsetLeft-carousel.scrollLeft);if(d<bestD){bestD=d;best=i}}dots.forEach((d,i)=>d.classList.toggle('on',i===best))}
carousel.addEventListener('scroll',()=>requestAnimationFrame(updatePager),{passive:true});
const sw=document.getElementById('signalSwitch');sw.addEventListener('click',()=>{const next=sw.getAttribute('aria-checked')!=='true';sw.setAttribute('aria-checked',String(next));document.getElementById('live').textContent=next?'Lower-confidence signals included in this preview.':'Lower-confidence signals hidden in this preview.'});
const values=['Past year','Past 6 months','Past 90 days','Past 30 days','Past 7 days','Current'];const timeline=document.getElementById('timeline');
timeline.addEventListener('input',()=>{const i=Number(timeline.value);document.getElementById('timelineValue').textContent=values[i];[...document.querySelectorAll('#ticks span')].forEach((n,j)=>n.classList.toggle('active',j===i))});
document.getElementById('save').addEventListener('click',()=>{document.getElementById('live').textContent='Preview-only save state selected; nothing was persisted.'});
document.getElementById('investigate').addEventListener('click',()=>{document.getElementById('live').textContent='Preview-only investigate state selected; no Scout workflow was started.'});
</script>
</body>
</html>`

async function isOwnerConnection(connectionId:string):Promise<boolean>{
  const { data: binding, error: bindingError } = await db.schema('commerce').from('oauth_agent_connection_bindings').select('user_id').eq('connection_id',connectionId).limit(1).maybeSingle()
  if (bindingError || !binding?.user_id) return false
  const { data: owner, error: ownerError } = await db.schema('commerce').from('scout_account_allowlist').select('user_id').eq('user_id',binding.user_id).eq('account_role','owner').eq('status','active').limit(1).maybeSingle()
  return !ownerError && !!owner?.user_id
}

async function authenticate(req:Request):Promise<Connection|null>{
  const auth=req.headers.get('authorization')||''
  const match=auth.match(/^Bearer\s+(.+)$/i)
  if(!match)return null
  const token=match[1].trim()
  const {data,error}=await db.rpc('scout_resolve_agent_connection_v4',{p_token:token,p_privacy_contract:PRIVACY_CONTRACT,p_exposure_contract:EXPOSURE_CONTRACT,p_enumeration_contract:ENUMERATION_CONTRACT})
  if(error||!data?.connection_id)return null
  const connection=data as Connection
  if(!connection.scopes?.includes('profile:read'))return null
  if(!(await isOwnerConnection(connection.connection_id)))return null
  return connection
}

function makeServer(){
  const server=new McpServer({name:'Scout MCP UI Lab',version:'0.2.0'})
  registerAppTool(server,TOOL_NAME,{
    title:'Preview Scout Component Sandbox',
    description:'Owner-only read-only developer preview of the Scout MCP App component sandbox. Call only when the Scout owner explicitly asks to preview, surface, inspect, or test the sandbox UI. It uses placeholder content and no business data.',
    inputSchema:{},
    outputSchema:z.object({surface:z.literal('scout_component_sandbox'),version:z.literal('v1'),business_data:z.literal(false),interaction_scope:z.literal('ephemeral_only')}),
    annotations:{readOnlyHint:true,destructiveHint:false,idempotentHint:true,openWorldHint:false},
    _meta:{ui:{resourceUri:RESOURCE_URI},'openai/outputTemplate':RESOURCE_URI,'openai/toolInvocation/invoking':'Opening Scout preview…','openai/toolInvocation/invoked':'Scout preview opened.'},
  },async()=>({content:[{type:'text',text:'Scout component sandbox v1. This is an owner-only static developer preview; its controls are ephemeral and contain no business data.'}],structuredContent:{surface:'scout_component_sandbox',version:'v1',business_data:false,interaction_scope:'ephemeral_only'}}))
  registerAppResource(server,'scout-component-sandbox',RESOURCE_URI,{mimeType:RESOURCE_MIME_TYPE},async()=>({contents:[{uri:RESOURCE_URI,mimeType:RESOURCE_MIME_TYPE,text:COMPONENT_SANDBOX_HTML,_meta:{ui:{prefersBorder:false,csp:{connectDomains:[],resourceDomains:[]}},'openai/widgetDescription':'Owner-only Scout component sandbox for testing inline card controls and interaction density.','openai/widgetPrefersBorder':false,'openai/widgetCSP':{connect_domains:[],resource_domains:[]}}}]}))
  return server
}

function headers(base?:HeadersInit){const h=new Headers(base);h.set('access-control-allow-origin','*');h.set('access-control-allow-headers','authorization,content-type,accept,mcp-protocol-version,mcp-session-id,x-request-id,last-event-id');h.set('access-control-expose-headers','mcp-session-id,content-type');h.set('access-control-allow-methods','GET,POST,DELETE,OPTIONS');h.set('cache-control','no-store, max-age=0');h.set('x-content-type-options','nosniff');h.set('referrer-policy','no-referrer');return h}
Deno.serve(async(req:Request)=>{if(req.method==='OPTIONS')return new Response(null,{status:204,headers:headers()});const connection=await authenticate(req);if(!connection)return Response.json({error:'invalid or missing Scout connection'},{status:401,headers:headers()});try{const server=makeServer();const transport=new WebStandardStreamableHTTPServerTransport();await server.connect(transport);const response=await transport.handleRequest(req);return new Response(response.body,{status:response.status,statusText:response.statusText,headers:headers(response.headers)})}catch(e){console.error('Scout UI lab MCP error',e);return Response.json({error:'Scout UI lab request failed'},{status:500,headers:headers()})}})
