import {
  buildComponentSandboxHtml as buildComponentSandboxHtmlV9,
  type SandboxMapMember,
  type SandboxMapTarget as SandboxMapTargetV9,
  type SandboxMapTerritory,
  type SandboxContactCard,
  type SandboxContactRoute,
} from './component_v9.ts'

export type { SandboxMapMember, SandboxMapTerritory, SandboxContactCard, SandboxContactRoute }
export type SandboxMapTarget = SandboxMapTargetV9

function replaceRequired(source:string, needle:string, replacement:string, label:string){
  if(!source.includes(needle))throw new Error('Scout component sandbox v10 transform failed: '+label)
  return source.replace(needle,replacement)
}

const vcardCss=`.contact-subject{appearance:none;border:0;padding:0;margin:0;background:transparent;text-align:left;font:inherit;font-size:13px;line-height:1.16;font-weight:780;color:var(--text);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:100%}.contact-subject[data-downloadable="true"]{cursor:pointer;text-decoration:underline;text-decoration-color:color-mix(in srgb,var(--accent) 48%,transparent);text-underline-offset:2px}.contact-subject[data-downloadable="true"]::after{content:' ↓';color:var(--accent);font-size:9px;text-decoration:none}.contact-subject:disabled{opacity:1;color:var(--text);cursor:default}.contact-vcard-prompt[hidden]{display:none!important}.contact-vcard-prompt{position:absolute;inset:8px;z-index:12;border:1px solid var(--line);border-radius:13px;background:color-mix(in srgb,var(--card) 97%,transparent);box-shadow:0 8px 24px rgba(0,0,0,.22);padding:13px;display:flex;flex-direction:column;justify-content:center;gap:9px}.contact-vcard-title{font-size:13px;font-weight:800;color:var(--text)}.contact-vcard-copy{font-size:9px;line-height:1.4;color:var(--muted)}.contact-vcard-actions{display:grid;grid-template-columns:1fr 1.25fr;gap:7px;margin-top:2px}.contact-vcard-button{min-height:34px;border:1px solid var(--line);border-radius:9px;background:var(--subtle);color:var(--text);font:inherit;font-size:9px;font-weight:750}.contact-vcard-button.primary{background:var(--button);border-color:var(--button);color:var(--button-text)}`

const oldSubject='<div class="contact-subject" id="contactSubject">Lead contact</div>'
const newSubject='<button class="contact-subject" id="contactSubject" type="button" disabled>Lead contact</button>'

const oldContactFoot='<div class="contact-foot" id="contactFoot">Contact card adapts to available enrichment.</div></div><span class="counter">3 / 3</span></div>'
const newContactFoot='<div class="contact-foot" id="contactFoot">Contact card adapts to available enrichment.</div><div class="contact-vcard-prompt" id="contactVcardPrompt" role="dialog" aria-modal="true" aria-labelledby="contactVcardTitle" hidden><div class="contact-vcard-title" id="contactVcardTitle">Save contact?</div><div class="contact-vcard-copy" id="contactVcardCopy">Download this contact as a .vcf file?</div><div class="contact-vcard-actions"><button class="contact-vcard-button" id="contactVcardCancel" type="button">Cancel</button><button class="contact-vcard-button primary" id="contactVcardDownload" type="button">Download .vcf</button></div></div></div><span class="counter">3 / 3</span></div>'

const helperMarker='function renderContactCard(){'
const vcardHelpers=`let currentContactCard=null;
function vcardEscape(value){return String(value??'').replace(/\\\\/g,'\\\\\\\\').replace(/\\n|\\r/g,'\\\\n').replace(/;/g,'\\\\;').replace(/,/g,'\\\\,')}
function vcardHttpUrl(value){const text=String(value||'').trim();return /^https?:\\/\\//i.test(text)?text:null}
function vcardDirectFields(card){const phones=[],emails=[],urls=[];for(const route of Array.isArray(card?.routes)?card.routes:[]){if(!route?.value)continue;const type=String(route.channel_type||'').toLowerCase(),value=String(route.value).trim();if((type==='phone'||type==='switchboard')&&value)phones.push(value);else if(type==='email'&&/^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$/.test(value))emails.push(value);else if(['url','website','supplier_portal','form'].includes(type)){const url=vcardHttpUrl(value);if(url)urls.push(url)}}const website=vcardHttpUrl(card?.website_url);if(website)urls.push(website);return{phones:[...new Set(phones)],emails:[...new Set(emails)],urls:[...new Set(urls)],address:String(card?.address||'').trim()}}
function vcardEligibility(card){const name=String(card?.subject_name||card?.organization_name||'').trim(),fields=vcardDirectFields(card);return!!name&&(fields.phones.length>0||fields.emails.length>0||fields.urls.length>0||!!fields.address)}
function vcardFilename(card){const base=String(card?.subject_name||card?.organization_name||'scout-contact').trim().toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-+|-+$/g,'').slice(0,70)||'scout-contact';return base+'.vcf'}
function buildVcard(card){const fields=vcardDirectFields(card),name=String(card?.subject_name||card?.organization_name||'Scout contact').trim(),org=String(card?.organization_name||'').trim(),lines=['BEGIN:VCARD','VERSION:3.0','FN:'+vcardEscape(name),'N:;;;;'];if(org)lines.push('ORG:'+vcardEscape(org));if(card?.role_label)lines.push('TITLE:'+vcardEscape(card.role_label));for(const phone of fields.phones)lines.push('TEL;TYPE=WORK:'+vcardEscape(phone));for(const email of fields.emails)lines.push('EMAIL;TYPE=INTERNET,WORK:'+vcardEscape(email));for(const url of fields.urls)lines.push('URL:'+vcardEscape(url));if(fields.address)lines.push('ADR;TYPE=WORK:;;'+vcardEscape(fields.address)+';;;;');const notes=[];if(card?.site_name&&card.site_name!==name)notes.push('Site: '+card.site_name);for(const route of Array.isArray(card?.routes)?card.routes:[]){if(String(route?.channel_type||'').toLowerCase()==='routing_instruction'&&route?.value)notes.push(String(route.value))}if(notes.length)lines.push('NOTE:'+vcardEscape(notes.slice(0,2).join(' | ')));lines.push('REV:'+new Date().toISOString().replace(/[-:]/g,'').replace(/\\.\\d{3}Z$/,'Z'),'END:VCARD');return lines.join('\\r\\n')+'\\r\\n'}
function hideVcardPrompt(){const prompt=document.getElementById('contactVcardPrompt');if(prompt)prompt.hidden=true}
function showVcardPrompt(card){if(!vcardEligibility(card))return;currentContactCard=card;const prompt=document.getElementById('contactVcardPrompt'),copy=document.getElementById('contactVcardCopy'),download=document.getElementById('contactVcardDownload');if(!prompt||!copy||!download)return;copy.textContent='Download '+String(card.subject_name||card.organization_name||'this contact')+' as a standard .vcf contact file?';prompt.hidden=false;requestAnimationFrame(()=>download.focus())}
function downloadCurrentVcard(){const card=currentContactCard;if(!card||!vcardEligibility(card))return;const content=buildVcard(card),blob=new Blob([content],{type:'text/vcard;charset=utf-8'}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=vcardFilename(card);a.rel='noopener';a.style.display='none';document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),1500);hideVcardPrompt();const live=document.getElementById('live');if(live)live.textContent='Contact file prepared for download.'}
function renderContactCard(){`

const oldRenderSetup="avatar.textContent=contactInitials(card);subject.textContent=card.subject_name||card.organization_name||'Lead';context.textContent=contactContextText(card);status.textContent=contactResolutionLabel(card);routesEl.innerHTML='';"
const newRenderSetup="avatar.textContent=contactInitials(card);subject.textContent=card.subject_name||card.organization_name||'Lead';context.textContent=contactContextText(card);status.textContent=contactResolutionLabel(card);const downloadable=vcardEligibility(card);subject.disabled=!downloadable;subject.dataset.downloadable=String(downloadable);subject.setAttribute('aria-label',downloadable?'Download '+(card.subject_name||card.organization_name||'contact')+' contact file':(card.subject_name||card.organization_name||'Lead'));subject.title=downloadable?'Save contact (.vcf)':'';subject.onclick=downloadable?(event)=>{event.stopPropagation();showVcardPrompt(card)}:null;const cancel=document.getElementById('contactVcardCancel'),download=document.getElementById('contactVcardDownload');if(cancel)cancel.onclick=(event)=>{event.stopPropagation();hideVcardPrompt()};if(download)download.onclick=(event)=>{event.stopPropagation();downloadCurrentVcard()};hideVcardPrompt();routesEl.innerHTML='';"

export function buildComponentSandboxHtml(targets: SandboxMapTarget[] = []) {
  let html=buildComponentSandboxHtmlV9(targets as unknown as SandboxMapTargetV9[])
  html=replaceRequired(html,'</style>',vcardCss+'</style>','vCard prompt CSS')
  html=replaceRequired(html,oldSubject,newSubject,'downloadable contact name')
  html=replaceRequired(html,oldContactFoot,newContactFoot,'vCard confirmation prompt')
  html=replaceRequired(html,helperMarker,vcardHelpers,'vCard helper functions')
  html=replaceRequired(html,oldRenderSetup,newRenderSetup,'vCard eligibility and interactions')
  return html
}
