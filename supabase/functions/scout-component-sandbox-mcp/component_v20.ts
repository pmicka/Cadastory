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
  const getApp=window.__scoutGetMcpApp;
  if(typeof getApp!=='function')throw new Error('mcp_app_root_not_initialized');
  return await getApp();
}
`

const rootMcpAppBridge=`<script type="module">
window.__scoutMcpAppReady=(async()=>{
  document.documentElement.dataset.scoutMcpApp='connecting';
  try{
    const mod=await import('https://unpkg.com/@modelcontextprotocol/ext-apps@2.0.0/app-with-deps');
    const app=new mod.App({name:'Scout Component Sandbox',version:'4.0.0'},{},{autoResize:true,strict:true});

    // One-shot and lifecycle handlers must be registered before connect().
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

// All host-mediated features reuse the same root App connection.
window.__scoutGetMcpApp=async()=>{
  const ready=window.__scoutMcpAppReady;
  if(!ready||typeof ready.then!=='function')throw new Error('mcp_app_root_not_initialized');
  const app=await ready;
  if(!app)throw new Error('mcp_app_root_connection_failed');
  return app;
};
</script>`

export function buildComponentSandboxHtml(targets: SandboxMapTarget[] = []) {
  let html=buildComponentSandboxHtmlV17(targets as unknown as SandboxMapTargetV17[])

  // Lifecycle-only repair: v17 created a second App connection on demand for
  // a host-mediated action. Preserve that feature's implementation unchanged,
  // but make its App accessor return the single root View connection instead.
  if(html.includes(legacyPerDownloadAppHelper))html=html.replace(legacyPerDownloadAppHelper,sharedAppHelper)

  // Establish one MCP Apps View lifecycle at the root. Presentation markup,
  // contact-card rendering, and image behavior are intentionally untouched.
  if(html.includes('</body>'))html=html.replace('</body>',rootMcpAppBridge+'</body>')

  return html
}
