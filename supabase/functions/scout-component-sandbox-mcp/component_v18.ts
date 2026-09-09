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

function replaceRequired(source:string, needle:string, replacement:string, label:string){
  if(!source.includes(needle))throw new Error('Scout component sandbox v18 transform failed: '+label)
  return source.replace(needle,replacement)
}

const oldDownload="async function downloadCurrentVcard(){const card=currentContactCard;if(!card||!vcardEligibility(card))return;const content=buildVcard(card),filename=vcardFilename(card),download=document.getElementById('contactVcardDownload'),copy=document.getElementById('contactVcardCopy'),live=document.getElementById('live'),originalLabel=download?.textContent||'Download .vcf';if(download){download.disabled=true;download.textContent='Saving…'}if(copy)copy.textContent='Preparing '+filename+' for ChatGPT…';try{const app=await scoutMcpDownloadApp();const result=await app.downloadFile({contents:[{type:'resource',resource:{uri:'file:///'+filename,mimeType:'text/vcard',text:content}}]});if(result?.isError)throw new Error('host_download_file_rejected');hideVcardPrompt();if(live)live.textContent='Contact file handed to ChatGPT.'}catch(error){console.error('Scout in-app vCard download failed',error);if(copy){const message=String(error?.message||'');copy.textContent=/method not found|unsupported|not implemented|ui\\/download-file/i.test(message)?'This ChatGPT client rejected the native in-app file download request.':'ChatGPT could not save the contact file in-app. Please try again.'}if(live)live.textContent='In-app contact download failed.'}finally{if(download){download.disabled=false;download.textContent=originalLabel}}}"

const deviceShareHelpers=`async function tryDeviceVcardShare(content,filename){
  if(typeof navigator==='undefined'||typeof navigator.share!=='function'||typeof File==='undefined')return{status:'unavailable'};
  const candidates=[
    new File([content],filename,{type:'text/x-vcard'}),
    new File([content],filename,{type:'text/vcard'}),
    new File([content],filename,{type:'text/plain'})
  ];
  let file=null;
  if(typeof navigator.canShare==='function'){
    for(const candidate of candidates){
      try{if(navigator.canShare({files:[candidate]})){file=candidate;break}}catch{}
    }
    if(!file)return{status:'unavailable'};
  }else file=candidates[0];
  try{
    await navigator.share({files:[file],title:String(filename||'Scout contact').replace(/\\.vcf$/i,'')});
    return{status:'shared'};
  }catch(error){
    if(error?.name==='AbortError')return{status:'cancelled'};
    return{status:'failed',error};
  }
}
`

const newDownload="async function downloadCurrentVcard(){const card=currentContactCard;if(!card||!vcardEligibility(card))return;const content=buildVcard(card),filename=vcardFilename(card),download=document.getElementById('contactVcardDownload'),copy=document.getElementById('contactVcardCopy'),live=document.getElementById('live'),originalLabel=download?.textContent||'Download .vcf';if(download){download.disabled=true;download.textContent='Saving…'}if(copy)copy.textContent='Preparing '+filename+'…';try{const share=await tryDeviceVcardShare(content,filename);if(share.status==='shared'){hideVcardPrompt();if(live)live.textContent='Contact file handed to your device.';return}if(share.status==='cancelled'){if(copy)copy.textContent='Save cancelled.';if(live)live.textContent='Contact save cancelled.';return}if(share.status==='failed')console.warn('Scout device vCard share unavailable',share.error);if(copy)copy.textContent='Trying ChatGPT\'s in-app file handoff…';const app=await scoutMcpDownloadApp();const result=await app.downloadFile({contents:[{type:'resource',resource:{uri:'file:///'+filename,mimeType:'text/vcard',text:content}}]});if(result?.isError)throw new Error('host_download_file_rejected');hideVcardPrompt();if(live)live.textContent='Contact file handed to ChatGPT.'}catch(error){console.error('Scout no-browser vCard save failed',error);if(copy)copy.textContent='This ChatGPT client blocked both device sharing and in-app contact download.';if(live)live.textContent='No-browser contact save is unavailable on this client.'}finally{if(download){download.disabled=false;download.textContent=originalLabel}}}"

export function buildComponentSandboxHtml(targets: SandboxMapTarget[] = []) {
  let html=buildComponentSandboxHtmlV17(targets as unknown as SandboxMapTargetV17[])
  html=replaceRequired(html,oldDownload,deviceShareHelpers+newDownload,'device share first vCard save')
  return html
}
