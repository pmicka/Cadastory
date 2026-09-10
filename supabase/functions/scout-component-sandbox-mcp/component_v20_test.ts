import { buildComponentSandboxHtml } from './component_v20.ts'

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
  const html=buildComponentSandboxHtml([])

  if(!html.includes("window.__scoutMcpAppReady=(async()=>")){
    throw new Error('missing root MCP Apps readiness promise')
  }
  if(count(html,'new mod.App(')!==1){
    throw new Error('Scout sandbox must construct exactly one MCP Apps App instance')
  }
  if(count(html,'await app.connect()')!==1){
    throw new Error('Scout sandbox must connect exactly one MCP Apps App instance')
  }
  if(html.includes('scoutMcpDownloadAppPromise')){
    throw new Error('vCard download must not create a second MCP Apps connection')
  }
  if(!html.includes("capabilities?.downloadFile")){
    throw new Error('vCard download must feature-gate ui/download-file')
  }
  if(!html.includes("autoResize:true,strict:true")){
    throw new Error('root MCP Apps connection must report host sizing and enforce handshake ordering')
  }
})
