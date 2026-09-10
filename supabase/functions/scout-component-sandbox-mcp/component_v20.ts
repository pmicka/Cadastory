import {
  buildComponentSandboxHtml as buildComponentSandboxHtmlV17,
  type SandboxMapMember,
  type SandboxMapTarget as SandboxMapTargetV17,
  type SandboxMapTerritory,
  type SandboxContactCard,
  type SandboxContactRoute,
} from './component_v17.ts'

export type { SandboxMapMember, SandboxMapTerritory, SandboxContactCard, SandboxContactRoute }
export type SandboxMapTarget = SandboxMapTargetV17

const legacyPerDownloadAppHelper=`let scoutMcpDownloadAppPromise=null;
async function scoutMcpDownloadApp(){
  if(!scoutMcpDownloadAppPromise){
    scoutMcpDownloadAppPromise=import('https://unpkg.com/@modelcontextprotocol/ext-apps@2.0.0/app-with-deps').then(async mod=>{
      const app=new mod.App({name:'Scout Component Sandbox',version:'3.7.0'},{},{autoResize:false,strict:true});
      await app.connect();
      return app;
    }).catch(error=>{scoutMcpDownloadAppPromise=null;throw error});
  }
  return scoutMcpDownloadAppPromise;
}
`

const sharedAppHelper=`async function scoutMcpDownloadApp(){
  const ready=window.__scoutMcpAppReady;
  if(!ready||typeof ready.then!=='function')throw new Error('mcp_app_root_not_initialized');
  const app=await ready;
  if(!app)throw new Error('mcp_app_root_connection_failed');
  return app;
}
`

const legacyDownload="async function downloadCurrentVcard(){const card=currentContactCard;if(!card||!vcardEligibility(card))return;const content=buildVcard(card),filename=vcardFilename(card),download=document.getElementById('contactVcardDownload'),copy=document.getElementById('contactVcardCopy'),live=document.getElementById('live'),originalLabel=download?.textContent||'Download .vcf';if(download){download.disabled=true;download.textContent='Saving…'}if(copy)copy.textContent='Preparing '+filename+' for ChatGPT…';try{const app=await scoutMcpDownloadApp();const result=await app.downloadFile({contents:[{type:'resource',resource:{uri:'file:///'+filename,mimeType:'text/vcard',text:content}}]});if(result?.isError)throw new Error('host_download_file_rejected');hideVcardPrompt();if(live)live.textContent='Contact file handed to ChatGPT.'}catch(error){console.error('Scout in-app vCard download failed',error);if(copy){const message=String(error?.message||'');copy.textContent=/method not found|unsupported|not implemented|ui\\/download-file/i.test(message)?'This ChatGPT client rejected the native in-app file download request.':'ChatGPT could not save the contact file in-app. Please try again.'}if(live)live.textContent='In-app contact download failed.'}finally{if(download){download.disabled=false;download.textContent=originalLabel}}}"

const sharedDownload="async function downloadCurrentVcard(){const card=currentContactCard;if(!card||!vcardEligibility(card))return;const content=buildVcard(card),filename=vcardFilename(card),download=document.getElementById('contactVcardDownload'),copy=document.getElementById('contactVcardCopy'),live=document.getElementById('live'),originalLabel=download?.textContent||'Download .vcf';if(download){download.disabled=true;download.textContent='Saving…'}if(copy)copy.textContent='Preparing '+filename+' for ChatGPT…';try{const app=await scoutMcpDownloadApp(),capabilities=typeof app.getHostCapabilities==='function'?app.getHostCapabilities():null;if(!capabilities?.downloadFile)throw new Error('host_download_file_unsupported');const result=await app.downloadFile({contents:[{type:'resource',resource:{uri:'file:///'+filename,mimeType:'text/vcard',text:content}}]});if(result?.isError)throw new Error('host_download_file_rejected');hideVcardPrompt();if(live)live.textContent='Contact file handed to ChatGPT.'}catch(error){console.error('Scout in-app vCard download failed',error);if(copy){const message=String(error?.message||'');copy.textContent=/host_download_file_unsupported|method not found|unsupported|not implemented|ui\\/download-file/i.test(message)?'This ChatGPT client does not advertise native in-app file downloads.':'ChatGPT could not save the contact file in-app. Please try again.'}if(live)live.textContent='In-app contact download failed.'}finally{if(download){download.disabled=false;download.textContent=originalLabel}}}"

const rootMcpAppBridge=`<script type="module">
window.__scoutMcpAppReady=(async()=>{
  document.documentElement.dataset.scoutMcpApp='connecting';
  try{
    const mod=await import('https://unpkg.com/@modelcontextprotocol/ext-apps@2.0.0/app-with-deps');
    const app=new mod.App({name:'Scout Component Sandbox',version:'4.0.0'},{},{autoResize:false,strict:true});
    app.ontoolinput=(input)=>window.dispatchEvent(new CustomEvent('scout:mcp-tool-input',{detail:input}));
    app.ontoolresult=(result)=>window.dispatchEvent(new CustomEvent('scout:mcp-tool-result',{detail:result}));
    app.onhostcontextchanged=(context)=>window.dispatchEvent(new CustomEvent('scout:mcp-host-context',{detail:context}));
    app.onteardown=async()=>{window.dispatchEvent(new CustomEvent('scout:mcp-teardown'));return{}};
    app.onerror=(error)=>console.error('Scout MCP App protocol error',error);
    await app.connect();
    window.__scoutMcpApp=app;
    window.__scoutMcpHostCapabilities=typeof app.getHostCapabilities==='function'?(app.getHostCapabilities()||{}):{};
    document.documentElement.dataset.scoutMcpApp='connected';
    window.dispatchEvent(new CustomEvent('scout:mcp-ready',{detail:{capabilities:window.__scoutMcpHostCapabilities}}));
    return app;
  }catch(error){
    document.documentElement.dataset.scoutMcpApp='failed';
    window.__scoutMcpAppError=String(error?.message||error||'Unknown MCP Apps initialization failure');
    console.error('Scout MCP App root initialization failed',error);
    window.dispatchEvent(new CustomEvent('scout:mcp-failed',{detail:{message:window.__scoutMcpAppError}}));
    return null;
  }
})();
</script>`

export function buildComponentSandboxHtml(targets: SandboxMapTarget[] = []) {
  let html=buildComponentSandboxHtmlV17(targets as unknown as SandboxMapTargetV17[])

  // v17 opened a second MCP App connection only when a vCard was clicked.
  // v20 preserves the v17 UI but makes every host-mediated action consume the
  // single root App connection established for the View lifecycle.
  if(html.includes(legacyPerDownloadAppHelper))html=html.replace(legacyPerDownloadAppHelper,sharedAppHelper)
  if(html.includes(legacyDownload))html=html.replace(legacyDownload,sharedDownload)

  // MCP Apps Views must initialize themselves with the Host. Keep this as a
  // progressive enhancement over the known-good v17 HTML so a future markup
  // change cannot erase the base Scout card.
  if(html.includes('</body>'))html=html.replace('</body>',rootMcpAppBridge+'</body>')

  return html
}
