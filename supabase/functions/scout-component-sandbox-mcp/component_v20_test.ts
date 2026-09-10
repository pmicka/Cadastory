import { buildComponentSandboxHtml as buildV17 } from './component_v17.ts'
import { buildComponentSandboxHtml as buildV20 } from './component_v20.ts'

function count(haystack:string,needle:string){
  let n=0,start=0
  while(true){
    const i=haystack.indexOf(needle,start)
    if(i<0)return n
    n++
    start=i+needle.length
  }
}

Deno.test('Scout sandbox emits exactly one root MCP Apps lifecycle',()=>{
  const html=buildV20([])

  if(!html.includes("window.__scoutMcpAppReady=(async()=>")){
    throw new Error('missing root MCP Apps readiness promise')
  }
  if(!html.includes("window.__scoutGetMcpApp=async()=>")){
    throw new Error('missing shared root App accessor for host-mediated features')
  }
  if(count(html,'new mod.App(')!==1){
    throw new Error('Scout sandbox must construct exactly one MCP Apps App instance')
  }
  if(count(html,'await app.connect()')!==1){
    throw new Error('Scout sandbox must connect exactly one MCP Apps App instance')
  }
  if(html.includes('scoutMcpDownloadAppPromise')){
    throw new Error('host-mediated features must not create a second MCP Apps connection')
  }

  const handlerPositions=[
    html.indexOf('app.ontoolinput='),
    html.indexOf('app.ontoolresult='),
    html.indexOf('app.onhostcontextchanged='),
    html.indexOf('app.onteardown='),
  ]
  const connectPosition=html.indexOf('await app.connect()')
  if(handlerPositions.some(position=>position<0||position>connectPosition)){
    throw new Error('all MCP Apps lifecycle handlers must be registered before connect()')
  }
  if(!html.includes("autoResize:true,strict:true")){
    throw new Error('root MCP Apps connection must report sizing and enforce handshake ordering')
  }
})

Deno.test('lifecycle repair leaves contact and image presentation behavior unchanged',()=>{
  const baseline=buildV17([])
  const repaired=buildV20([])

  const downloadFunctionStart="async function downloadCurrentVcard(){const card=currentContactCard;"
  const downloadFunctionEnd="finally{if(download){download.disabled=false;download.textContent=originalLabel}}}"
  const baselineStart=baseline.indexOf(downloadFunctionStart)
  const baselineEnd=baseline.indexOf(downloadFunctionEnd,baselineStart)
  const repairedStart=repaired.indexOf(downloadFunctionStart)
  const repairedEnd=repaired.indexOf(downloadFunctionEnd,repairedStart)
  if([baselineStart,baselineEnd,repairedStart,repairedEnd].some(position=>position<0)){
    throw new Error('expected unchanged v17 vCard function was not found')
  }
  const baselineDownload=baseline.slice(baselineStart,baselineEnd+downloadFunctionEnd.length)
  const repairedDownload=repaired.slice(repairedStart,repairedEnd+downloadFunctionEnd.length)
  if(baselineDownload!==repairedDownload){
    throw new Error('lifecycle repair must not modify the contact-card download function')
  }

  if(repaired.includes('property-image-slide')||repaired.includes('USGSNAIPImagery')){
    throw new Error('lifecycle repair must not add image-display enrichment')
  }
})
