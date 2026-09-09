import {
  buildComponentSandboxHtml as buildComponentSandboxHtmlV12,
  type SandboxMapMember,
  type SandboxMapTarget as SandboxMapTargetV12,
  type SandboxMapTerritory,
  type SandboxContactCard,
  type SandboxContactRoute,
} from './component_v12.ts'

export type { SandboxMapMember, SandboxMapTerritory, SandboxContactCard, SandboxContactRoute }
export type SandboxMapTarget = SandboxMapTargetV12

function replaceRequired(source:string, needle:string, replacement:string, label:string){
  if(!source.includes(needle))throw new Error('Scout component sandbox v13 transform failed: '+label)
  return source.replace(needle,replacement)
}

const oldDownload="function downloadCurrentVcard(){const card=currentContactCard;if(!card||!vcardEligibility(card))return;const content=buildVcard(card),blob=new Blob([content],{type:'text/vcard;charset=utf-8'}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=vcardFilename(card);a.rel='noopener';a.style.display='none';document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),1500);hideVcardPrompt();const live=document.getElementById('live');if(live)live.textContent='Contact file prepared for download.'}"

const newDownload="async function downloadCurrentVcard(){const card=currentContactCard;if(!card||!vcardEligibility(card))return;const content=buildVcard(card),filename=vcardFilename(card),download=document.getElementById('contactVcardDownload'),copy=document.getElementById('contactVcardCopy'),live=document.getElementById('live'),host=window.openai;const originalLabel=download?.textContent||'Download .vcf';if(download){download.disabled=true;download.textContent='Preparing…'}if(copy)copy.textContent='Preparing '+filename+'…';try{if(!host?.uploadFile||!host?.getFileDownloadUrl)throw new Error('host_file_api_unavailable');let uploaded;try{uploaded=await host.uploadFile(new File([content],filename,{type:'text/vcard;charset=utf-8'}),{library:false})}catch(firstError){uploaded=await host.uploadFile(new File([content],filename,{type:'text/plain;charset=utf-8'}),{library:false})}const fileId=uploaded?.fileId;if(!fileId)throw new Error('host_upload_missing_file_id');const resolved=await host.getFileDownloadUrl({fileId}),href=resolved?.downloadUrl;if(!href)throw new Error('host_download_url_unavailable');if(host.openExternal)await host.openExternal({href});else{const a=document.createElement('a');a.href=href;a.target='_blank';a.rel='noopener noreferrer';a.style.display='none';document.body.appendChild(a);a.click();a.remove()}hideVcardPrompt();if(live)live.textContent='Contact file opened for download.'}catch(error){console.error('Scout vCard host download failed',error);if(copy)copy.textContent='ChatGPT could not prepare the contact file. Please try again.';if(live)live.textContent='Contact download failed before leaving the widget.'}finally{if(download){download.disabled=false;download.textContent=originalLabel}}}"

export function buildComponentSandboxHtml(targets: SandboxMapTarget[] = []) {
  let html=buildComponentSandboxHtmlV12(targets as unknown as SandboxMapTargetV12[])
  html=replaceRequired(html,oldDownload,newDownload,'host-mediated vCard download flow')
  return html
}
