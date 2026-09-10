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

const sharedDownloadHelpers=`async function scoutMcpDownloadApp(){
  const getApp=window.__scoutGetMcpApp;
  if(typeof getApp!=='function')throw new Error('mcp_app_root_not_initialized');
  return await getApp();
}
`

const newDownload="async function downloadCurrentVcard(){const card=currentContactCard;if(!card||!vcardEligibility(card))return;const content=buildVcard(card),filename=vcardFilename(card),download=document.getElementById('contactVcardDownload'),copy=document.getElementById('contactVcardCopy'),live=document.getElementById('live'),originalLabel=download?.textContent||'Download .vcf';if(download){download.disabled=true;download.textContent='Saving…'}if(copy)copy.textContent='Preparing '+filename+' for ChatGPT…';try{const app=await scoutMcpDownloadApp();const result=await app.downloadFile({contents:[{type:'resource',resource:{uri:'file:///'+filename,mimeType:'text/vcard',text:content}}]});if(result?.isError)throw new Error('host_download_file_rejected');hideVcardPrompt();if(live)live.textContent='Contact file handed to ChatGPT.'}catch(error){console.error('Scout in-app vCard download failed',error);if(copy){const message=String(error?.message||'');copy.textContent=/method not found|unsupported|not implemented|ui\\/download-file/i.test(message)?'This ChatGPT client rejected the native in-app file download request.':'ChatGPT could not save the contact file in-app. Please try again.'}if(live)live.textContent='In-app contact download failed.'}finally{if(download){download.disabled=false;download.textContent=originalLabel}}}"

const legacyStateFlag='let hostGlobalsSeen=false;\nlet restoring=false;'
const portableStateFlag="const stateStorageKey='scout:component-sandbox:v1';\nlet restoring=false;"
const legacyPersist="function persist(patch){state={...state,...patch,__v:2};if(!hostGlobalsSeen)return;try{window.openai?.setWidgetState?.(state)}catch{}}"
const portablePersist="function persist(patch){state={...state,...patch,__v:2};try{localStorage.setItem(stateStorageKey,JSON.stringify(state))}catch{}}"
const legacyInitialize=`function initialize(){const initial=window.openai?.widgetState;if(initial&&typeof initial==='object')mergeState(initial);resolveTarget();restoreControls();requestAnimationFrame(renderStaticMap)}
window.addEventListener('openai:set_globals',(event)=>{const globals=event?.detail?.globals;if(!globals)return;hostGlobalsSeen=true;if(globals.widgetState&&typeof globals.widgetState==='object')applyHostState(globals.widgetState);else{if(!mapTarget)resolveTarget();persist({mapTargetKey:mapTarget?.key||state.mapTargetKey})}},{passive:true});`
const portableInitialize=`function initialize(){let initial=null;try{const raw=localStorage.getItem(stateStorageKey);initial=raw?JSON.parse(raw):null}catch{}if(initial&&typeof initial==='object')mergeState(initial);resolveTarget();restoreControls();requestAnimationFrame(renderStaticMap)}`

const rootMcpAppBridge=`<script type="module">
(async()=>{
  document.documentElement.dataset.scoutMcpApp='connecting';
  try{
    const mod=await import('https://unpkg.com/@modelcontextprotocol/ext-apps@2.0.0/app-with-deps');
    const app=new mod.App(
      {name:'Scout Component Sandbox',title:'Scout Component Sandbox',version:'4.0.0'},
      {},
      {autoResize:true}
    );

    // Register every notification/request handler before the initialization handshake.
    app.addEventListener('toolinput',(params)=>window.dispatchEvent(new CustomEvent('scout:mcp-tool-input',{detail:params})));
    app.addEventListener('toolresult',(params)=>window.dispatchEvent(new CustomEvent('scout:mcp-tool-result',{detail:params})));
    app.addEventListener('toolcancelled',(params)=>window.dispatchEvent(new CustomEvent('scout:mcp-tool-cancelled',{detail:params})));
    app.addEventListener('hostcontextchanged',(params)=>window.dispatchEvent(new CustomEvent('scout:mcp-host-context',{detail:params})));
    app.onteardown=async()=>{window.dispatchEvent(new CustomEvent('scout:mcp-teardown'));return{}};
    app.onerror=(error)=>console.error('Scout MCP App protocol error',error);

    window.__scoutMcpApp=app;
    const ready=(async()=>{
      await app.connect();
      window.__scoutMcpHostCapabilities=app.getHostCapabilities?.()||{};
      document.documentElement.dataset.scoutMcpApp='connected';
      window.dispatchEvent(new CustomEvent('scout:mcp-ready',{detail:{host:app.getHostVersion?.(),capabilities:window.__scoutMcpHostCapabilities,context:app.getHostContext?.()}}));
      return app;
    })();
    window.__scoutMcpAppReady=ready;
    window.__scoutGetMcpApp=async()=>{
      const connected=await ready;
      if(!connected)throw new Error('mcp_app_root_connection_failed');
      return connected;
    };
    await ready;
  }catch(error){
    document.documentElement.dataset.scoutMcpApp='failed';
    window.__scoutMcpAppError=String(error?.message||error||'Unknown MCP Apps initialization failure');
    console.error('Scout MCP App root initialization failed',error);
    window.dispatchEvent(new CustomEvent('scout:mcp-failed',{detail:{message:window.__scoutMcpAppError}}));
  }
})();
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

  // Preserve current presentation behavior while replacing host-specific plumbing.
  html=replaceRequired(html,oldDownload,sharedDownloadHelpers+newDownload,'shared MCP Apps host connection')
  html=replaceRequired(html,legacyStateFlag,portableStateFlag,'portable local view-state key')
  html=replaceRequired(html,legacyPersist,portablePersist,'portable local view-state persistence')
  html=replaceRequired(html,legacyInitialize,portableInitialize,'portable local view-state restore')

  html=replaceRequired(html,oldCarousel,newCarousel,'contained carousel overscroll')
  html=replaceRequired(html,oldSlide,newSlide,'full-width carousel tile')
  html=replaceRequired(html,oldNarrowSlide,newNarrowSlide,'full-width narrow carousel tile')
  html=replaceRequired(html,oldScrollHandler,settledScrollHandler,'settled carousel state persistence')

  if(html.includes('window.openai'))throw new Error('Scout component sandbox v17 still contains host-specific window.openai usage')
  if(!html.includes('</body>'))throw new Error('Scout component sandbox v17 missing body terminator for MCP Apps lifecycle')
  return html.replace('</body>',rootMcpAppBridge+'</body>')
}
