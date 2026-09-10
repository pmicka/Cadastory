import {
  buildComponentSandboxHtml as buildComponentSandboxHtmlV16,
  type SandboxMapMember,
  type SandboxMapTarget as SandboxMapTargetV16,
  type SandboxMapTerritory,
  type SandboxContactCard,
  type SandboxContactRoute,
} from './component_v16.ts'

export type { SandboxMapMember, SandboxMapTerritory, SandboxContactCard, SandboxContactRoute }
export type SandboxMapTarget = SandboxMapTargetV16

function replaceRequired(source:string, needle:string, replacement:string, label:string){
  if(!source.includes(needle))throw new Error('Scout component sandbox v17 transform failed: '+label)
  return source.replace(needle,replacement)
}

const oldDownload="async function downloadCurrentVcard(){const card=currentContactCard;if(!card||!vcardEligibility(card))return;const download=document.getElementById('contactVcardDownload'),copy=document.getElementById('contactVcardCopy'),live=document.getElementById('live'),host=window.openai,originalLabel=download?.textContent||'Download .vcf';if(download){download.disabled=true;download.textContent='Opening…'}try{const routeUrl=card?.resolution_status==='named_routing_contact'?String(card?.routes?.[0]?.prepared_download_url||'').trim():'';const href=String(routeUrl||card?.prepared_download_url||'').trim();if(!/^https:\\/\\//i.test(href))throw new Error('prepared_download_url_unavailable');if(copy)copy.textContent='Opening the prepared contact file…';if(host?.openExternal)await host.openExternal({href,redirectUrl:false});else{const a=document.createElement('a');a.href=href;a.target='_blank';a.rel='noopener noreferrer';document.body.appendChild(a);a.click();a.remove()}hideVcardPrompt();if(live)live.textContent='Contact download opened.'}catch(error){console.error('Scout prepared vCard open failed',error);if(copy)copy.textContent='ChatGPT could not open the prepared contact file. Please refresh the Scout card and try again.';if(live)live.textContent='Prepared contact download failed to open.'}finally{if(download){download.disabled=false;download.textContent=originalLabel}}}"

const sharedDownloadAppHelper=`async function scoutMcpDownloadApp(){
  const getApp=window.__scoutGetMcpApp;
  if(typeof getApp!=='function')throw new Error('mcp_app_root_not_initialized');
  return await getApp();
}
`

const newDownload="async function downloadCurrentVcard(){const card=currentContactCard;if(!card||!vcardEligibility(card))return;const content=buildVcard(card),filename=vcardFilename(card),download=document.getElementById('contactVcardDownload'),copy=document.getElementById('contactVcardCopy'),live=document.getElementById('live'),originalLabel=download?.textContent||'Download .vcf';if(download){download.disabled=true;download.textContent='Saving…'}if(copy)copy.textContent='Preparing '+filename+' for ChatGPT…';try{const app=await scoutMcpDownloadApp();const result=await app.downloadFile({contents:[{type:'resource',resource:{uri:'file:///'+filename,mimeType:'text/vcard',text:content}}]});if(result?.isError)throw new Error('host_download_file_rejected');hideVcardPrompt();if(live)live.textContent='Contact file handed to ChatGPT.'}catch(error){console.error('Scout in-app vCard download failed',error);if(copy){const message=String(error?.message||'');copy.textContent=/method not found|unsupported|not implemented|ui\\/download-file/i.test(message)?'This ChatGPT client rejected the native in-app file download request.':'ChatGPT could not save the contact file in-app. Please try again.'}if(live)live.textContent='In-app contact download failed.'}finally{if(download){download.disabled=false;download.textContent=originalLabel}}}"

const rootMcpAppLifecycle=`<script type="module">
window.__scoutMcpAppReady=(async()=>{
  try{
    const mod=await import('https://unpkg.com/@modelcontextprotocol/ext-apps@2.0.0/app-with-deps');
    const app=new mod.App({name:'Scout Component Sandbox',version:'3.7.1'});

    // MCP Apps one-shot/lifecycle handlers are registered before connect().
    app.ontoolinput=(input)=>window.dispatchEvent(new CustomEvent('scout:mcp-tool-input',{detail:input}));
    app.ontoolresult=(result)=>window.dispatchEvent(new CustomEvent('scout:mcp-tool-result',{detail:result}));
    app.onhostcontextchanged=(context)=>window.dispatchEvent(new CustomEvent('scout:mcp-host-context',{detail:context}));
    app.onteardown=async()=>{window.dispatchEvent(new CustomEvent('scout:mcp-teardown'));return{}};
    app.onerror=(error)=>console.error('Scout MCP App protocol error',error);

    await app.connect();
    window.__scoutMcpApp=app;
    window.dispatchEvent(new CustomEvent('scout:mcp-ready'));
    return app;
  }catch(error){
    window.__scoutMcpAppError=String(error?.message||error||'Unknown MCP Apps initialization failure');
    console.error('Scout MCP App root initialization failed',error);
    window.dispatchEvent(new CustomEvent('scout:mcp-failed',{detail:{message:window.__scoutMcpAppError}}));
    return null;
  }
})();

// MCP host actions share the single root View connection.
window.__scoutGetMcpApp=async()=>{
  const ready=window.__scoutMcpAppReady;
  if(!ready||typeof ready.then!=='function')throw new Error('mcp_app_root_not_initialized');
  const app=await ready;
  if(!app)throw new Error('mcp_app_root_connection_failed');
  return app;
};
</script>`

const oldCarousel='.carousel{display:flex;gap:10px;overflow-x:auto;scroll-snap-type:x mandatory;scrollbar-width:none;border-radius:16px;touch-action:pan-x}'
const newCarousel='.carousel{display:flex;gap:10px;overflow-x:auto;scroll-snap-type:x mandatory;scrollbar-width:none;border-radius:16px;touch-action:pan-x;overscroll-behavior-x:contain}'
const oldSlide='.slide{position:relative;min-width:86%;height:200px;'
const newSlide='.slide{position:relative;min-width:100%;height:200px;'
const oldNarrowSlide='.slide{min-width:92%;height:190px}'
const newNarrowSlide='.slide{min-width:100%;height:190px}'
const oldScrollHandler=`let scrollFrame=0;carousel.addEventListener('scroll',()=>{cancelAnimationFrame(scrollFrame);scrollFrame=requestAnimationFrame(()=>updatePager(true))},{passive:true});`
const settledScrollHandler=`let scrollFrame=0,slidePersistTimer=0;
carousel.addEventListener('scroll',()=>{cancelAnimationFrame(scrollFrame);scrollFrame=requestAnimationFrame(()=>updatePager(false));clearTimeout(slidePersistTimer);slidePersistTimer=setTimeout(()=>updatePager(true),180)},{passive:true});`

export function buildComponentSandboxHtml(targets: SandboxMapTarget[] = []) {
  let html=buildComponentSandboxHtmlV16(targets as unknown as SandboxMapTargetV16[])
  html=replaceRequired(html,oldDownload,sharedDownloadAppHelper+newDownload,'shared MCP Apps host connection')
  html=replaceRequired(html,oldCarousel,newCarousel,'contained carousel overscroll')
  html=replaceRequired(html,oldSlide,newSlide,'full-width carousel tile')
  html=replaceRequired(html,oldNarrowSlide,newNarrowSlide,'full-width narrow carousel tile')
  html=replaceRequired(html,oldScrollHandler,settledScrollHandler,'settled carousel state persistence')
  html=replaceRequired(html,'</body>',rootMcpAppLifecycle+'</body>','root MCP Apps lifecycle')
  return html
}
