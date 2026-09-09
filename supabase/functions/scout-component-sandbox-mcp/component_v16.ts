import {
  buildComponentSandboxHtml as buildComponentSandboxHtmlV13,
  type SandboxMapMember,
  type SandboxMapTarget as SandboxMapTargetV13,
  type SandboxMapTerritory,
  type SandboxContactCard,
  type SandboxContactRoute,
} from './component_v13.ts'

export type { SandboxMapMember, SandboxMapTerritory, SandboxContactCard, SandboxContactRoute }
export type SandboxMapTarget = SandboxMapTargetV13

function replaceRequired(source:string, needle:string, replacement:string, label:string){
  if(!source.includes(needle))throw new Error('Scout component sandbox v16 transform failed: '+label)
  return source.replace(needle,replacement)
}

const oldDownload="async function downloadCurrentVcard(){const card=currentContactCard;if(!card||!vcardEligibility(card))return;const download=document.getElementById('contactVcardDownload'),copy=document.getElementById('contactVcardCopy'),live=document.getElementById('live'),host=window.openai,originalLabel=download?.textContent||'Download .vcf';if(download){download.disabled=true;download.textContent='Preparing…'}if(copy)copy.textContent='Preparing contact file…';try{if(!host?.callTool)throw new Error('host_tool_api_unavailable');const targetKey=String(mapTarget?.key||'').trim();if(!targetKey)throw new Error('target_key_unavailable');const routeKey=card?.resolution_status==='named_routing_contact'?String(card?.routes?.[0]?.key||'').trim()||null:null;const result=await host.callTool('scout_prepare_contact_vcard_download',{target_key:targetKey,route_key:routeKey});let data=result?.structuredContent||null;if(!data&&typeof result?.result==='string'){try{data=JSON.parse(result.result)}catch{}}if(!data&&Array.isArray(result?.content)){const textPart=result.content.find(part=>part?.type==='text'&&typeof part?.text==='string');if(textPart){try{data=JSON.parse(textPart.text)}catch{}}}const href=String(data?.download_url||'').trim();if(!/^https:\\/\\//i.test(href))throw new Error('download_url_unavailable');if(host.openExternal)await host.openExternal({href,redirectUrl:false});else window.open(href,'_blank','noopener,noreferrer');hideVcardPrompt();if(live)live.textContent='Contact download opened.'}catch(error){console.error('Scout vCard download handoff failed',error);if(copy)copy.textContent='Scout could not open the contact download. Please try again.';if(live)live.textContent='Contact download handoff failed.'}finally{if(download){download.disabled=false;download.textContent=originalLabel}}}"

const newDownload="async function downloadCurrentVcard(){const card=currentContactCard;if(!card||!vcardEligibility(card))return;const download=document.getElementById('contactVcardDownload'),copy=document.getElementById('contactVcardCopy'),live=document.getElementById('live'),host=window.openai,originalLabel=download?.textContent||'Download .vcf';if(download){download.disabled=true;download.textContent='Opening…'}try{const routeUrl=card?.resolution_status==='named_routing_contact'?String(card?.routes?.[0]?.prepared_download_url||'').trim():'';const href=String(routeUrl||card?.prepared_download_url||'').trim();if(!/^https:\\/\\//i.test(href))throw new Error('prepared_download_url_unavailable');if(copy)copy.textContent='Opening the prepared contact file…';if(host?.openExternal)await host.openExternal({href,redirectUrl:false});else{const a=document.createElement('a');a.href=href;a.target='_blank';a.rel='noopener noreferrer';document.body.appendChild(a);a.click();a.remove()}hideVcardPrompt();if(live)live.textContent='Contact download opened.'}catch(error){console.error('Scout prepared vCard open failed',error);if(copy)copy.textContent='ChatGPT could not open the prepared contact file. Please refresh the Scout card and try again.';if(live)live.textContent='Prepared contact download failed to open.'}finally{if(download){download.disabled=false;download.textContent=originalLabel}}}"

export function buildComponentSandboxHtml(targets: SandboxMapTarget[] = []) {
  let html=buildComponentSandboxHtmlV13(targets as unknown as SandboxMapTargetV13[])
  html=replaceRequired(html,oldDownload,newDownload,'preprepared vCard URL handoff')
  return html
}
