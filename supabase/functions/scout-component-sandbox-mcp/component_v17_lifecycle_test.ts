import { buildComponentSandboxHtml } from './component_v17.ts'

function count(haystack:string,needle:string){
  let total=0,start=0
  while(true){
    const index=haystack.indexOf(needle,start)
    if(index<0)return total
    total++
    start=index+needle.length
  }
}

Deno.test('Scout sandbox uses one root MCP Apps connection with handlers registered first',()=>{
  const html=buildComponentSandboxHtml([])
  const connect='await app.connect()'
  const connectAt=html.indexOf(connect)

  if(!html.includes("window.__scoutMcpAppReady=(async()=>"))throw new Error('missing root MCP Apps readiness promise')
  if(!html.includes("window.__scoutGetMcpApp=async()=>"))throw new Error('missing shared root App accessor')
  if(count(html,'new mod.App(')!==1)throw new Error('Scout sandbox must create exactly one MCP Apps App')
  if(count(html,connect)!==1)throw new Error('Scout sandbox must connect exactly one MCP Apps App')

  for(const handler of ['app.ontoolinput=','app.ontoolresult=','app.onhostcontextchanged=','app.onteardown=']){
    const handlerAt=html.indexOf(handler)
    if(handlerAt<0||handlerAt>connectAt)throw new Error(`${handler} must be registered before connect()`)
  }

  if(html.includes('scoutMcpDownloadAppPromise'))throw new Error('host-mediated actions must not create a second App connection')
  if(!html.includes("const getApp=window.__scoutGetMcpApp;"))throw new Error('existing host-mediated download path must reuse the root App')
})

Deno.test('MCP lifecycle work does not add image enrichment or rewrite contact-card presentation',()=>{
  const html=buildComponentSandboxHtml([])

  if(html.includes('USGSNAIPImagery')||html.includes('property-image-slide')){
    throw new Error('lifecycle-only component must not add image enrichment')
  }

  const existingDownload="async function downloadCurrentVcard(){const card=currentContactCard;if(!card||!vcardEligibility(card))return;const content=buildVcard(card),filename=vcardFilename(card)"
  if(!html.includes(existingDownload)){
    throw new Error('existing v17 contact-card download implementation must remain present')
  }
}
