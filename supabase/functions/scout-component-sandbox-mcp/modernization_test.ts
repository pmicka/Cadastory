import { buildComponentSandboxHtml } from './component_v17.ts'

function count(haystack:string,needle:string){
  let total=0
  let offset=0
  while(true){
    const index=haystack.indexOf(needle,offset)
    if(index<0)return total
    total++
    offset=index+needle.length
  }
}

Deno.test('Scout sandbox View uses one current MCP Apps lifecycle',()=>{
  const html=buildComponentSandboxHtml([])

  if(html.includes('window.openai')){
    throw new Error('runtime View must not depend on the OpenAI widget global')
  }
  if(count(html,'new mod.App(')!==1){
    throw new Error('runtime View must construct exactly one MCP Apps App')
  }
  if(count(html,'await app.connect()')!==1){
    throw new Error('runtime View must perform exactly one MCP Apps handshake')
  }
  if(html.includes('scoutMcpDownloadAppPromise')){
    throw new Error('host-mediated features must reuse the root App instead of opening another connection')
  }
  if(!html.includes('window.__scoutGetMcpApp=async()=>')){
    throw new Error('runtime View must expose the shared connected App accessor')
  }

  const connect=html.indexOf('await app.connect()')
  const handlers=[
    "app.addEventListener('toolinput'",
    "app.addEventListener('toolresult'",
    "app.addEventListener('toolcancelled'",
    "app.addEventListener('hostcontextchanged'",
    'app.onteardown=',
  ]
  for(const handler of handlers){
    const position=html.indexOf(handler)
    if(position<0||position>connect){
      throw new Error(`MCP Apps handler must be registered before connect(): ${handler}`)
    }
  }
  if(!html.includes('{autoResize:true}')){
    throw new Error('runtime View must use MCP Apps automatic size reporting')
  }
})

Deno.test('Scout sandbox uses portable recoverable view state',()=>{
  const html=buildComponentSandboxHtml([])
  if(!html.includes("const stateStorageKey='scout:component-sandbox:v1'")){
    throw new Error('missing stable portable view-state key')
  }
  if(!html.includes('localStorage.setItem(stateStorageKey,JSON.stringify(state))')){
    throw new Error('view state must persist through localStorage when available')
  }
  if(!html.includes('localStorage.getItem(stateStorageKey)')){
    throw new Error('view state must restore through localStorage when available')
  }
})

Deno.test('modernization does not add image enrichment',()=>{
  const html=buildComponentSandboxHtml([])
  if(html.includes('USGSNAIPImagery')||html.includes('property-image-slide')){
    throw new Error('MCP Apps modernization must not introduce image enrichment')
  }
})

Deno.test('server metadata is standard MCP Apps metadata',async()=>{
  const source=await Deno.readTextFile(new URL('./index.ts',import.meta.url))
  if(source.includes("'openai/")||source.includes('"openai/')){
    throw new Error('canonical server metadata must not depend on OpenAI-specific metadata keys')
  }
  if(!source.includes("_meta:{ui:{resourceUri:RESOURCE_URI}}")){
    throw new Error('tool must advertise the standard MCP Apps resourceUri')
  }
  if(!source.includes('csp:{connectDomains:[],resourceDomains:')){
    throw new Error('resource must advertise standard MCP Apps CSP metadata')
  }
  if(!source.includes("RESOURCE_URI = 'ui://scout/component-sandbox/v2'")){
    throw new Error('modernized View must use a fresh resource URI to avoid stale host caches')
  }
})
