import {
  buildComponentSandboxHtml as buildComponentSandboxHtmlV11,
  type SandboxMapMember,
  type SandboxMapTarget as SandboxMapTargetV11,
  type SandboxMapTerritory,
  type SandboxContactCard,
  type SandboxContactRoute,
} from './component_v11.ts'

export type { SandboxMapMember, SandboxMapTerritory, SandboxContactCard, SandboxContactRoute }
export type SandboxMapTarget = SandboxMapTargetV11

function replaceRequired(source:string, needle:string, replacement:string, label:string){
  if(!source.includes(needle))throw new Error('Scout component sandbox v12 transform failed: '+label)
  return source.replace(needle,replacement)
}

const oldEligibility="function vcardEligibility(card){const name=String(card?.subject_name||card?.organization_name||'').trim(),fields=vcardDirectFields(card);return!!name&&(fields.phones.length>0||fields.emails.length>0||fields.urls.length>0||!!fields.address)}"
const newEligibility="function vcardEligibility(card){const name=String(card?.subject_name||card?.organization_name||'').trim(),fields=vcardDirectFields(card);if(!name)return false;if(fields.phones.length>0||fields.emails.length>0||fields.urls.length>0||!!fields.address)return true;if(card?.resolution_status==='named_routing_contact'){const org=String(card?.organization_name||'').trim(),title=String(card?.role_label||'').trim(),routing=Array.isArray(card?.routes)?card.routes.find(route=>String(route?.channel_type||'').toLowerCase()==='routing_instruction'&&String(route?.value||'').trim()):null;return!!routing&&!!(org||title)}return false}"

const oldDownload="function downloadCurrentVcard(){const card=currentContactCard;if(!card||!vcardEligibility(card))return;const content=buildVcard(card),blob=new Blob([content],{type:'text/vcard;charset=utf-8'}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=vcardFilename(card);a.rel='noopener';a.style.display='none';document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),1500);hideVcardPrompt();const live=document.getElementById('live');if(live)live.textContent='Contact file prepared for download.'}"
const newDownload="async function downloadCurrentVcard(){const card=currentContactCard;if(!card||!vcardEligibility(card))return;const content=buildVcard(card),filename=vcardFilename(card),download=document.getElementById('contactVcardDownload'),copy=document.getElementById('contactVcardCopy'),live=document.getElementById('live'),host=window.openai;const originalLabel=download?.textContent||'Download .vcf';if(download){download.disabled=true;download.textContent='Preparing…'}if(copy)copy.textContent='Preparing '+filename+'…';try{if(!host?.uploadFile||!host?.getFileDownloadUrl)throw new Error('host_file_api_unavailable');let uploaded;try{uploaded=await host.uploadFile(new File([content],filename,{type:'text/vcard;charset=utf-8'}),{library:false})}catch(firstError){uploaded=await host.uploadFile(new File([content],filename,{type:'text/plain;charset=utf-8'}),{library:false})}const fileId=uploaded?.fileId;if(!fileId)throw new Error('host_upload_missing_file_id');const resolved=await host.getFileDownloadUrl({fileId}),href=resolved?.downloadUrl;if(!href)throw new Error('host_download_url_unavailable');if(host.openExternal)await host.openExternal({href});else{const a=document.createElement('a');a.href=href;a.target='_blank';a.rel='noopener noreferrer';a.style.display='none';document.body.appendChild(a);a.click();a.remove()}hideVcardPrompt();if(live)live.textContent='Contact file opened for download.'}catch(error){console.error('Scout vCard host download failed',error);if(copy)copy.textContent='ChatGPT could not prepare the contact file. Please try again.';if(live)live.textContent='Contact download failed before leaving the widget.'}finally{if(download){download.disabled=false;download.textContent=originalLabel}}}"

const interactionCss=`.contact-route-value-button[data-downloadable="true"]{touch-action:manipulation;user-select:none;-webkit-user-select:none}`

export function buildComponentSandboxHtml(targets: SandboxMapTarget[] = []) {
  let html=buildComponentSandboxHtmlV11(targets as unknown as SandboxMapTargetV11[])
  html=replaceRequired(html,oldEligibility,newEligibility,'unified named-route vCard eligibility')
  html=replaceRequired(html,oldDownload,newDownload,'host-mediated vCard download flow')
  html=replaceRequired(html,'</style>',interactionCss+'</style>','named-route touch behavior')
  return html
}
