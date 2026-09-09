import {
  buildComponentSandboxHtml as buildComponentSandboxHtmlV8,
  type SandboxMapMember,
  type SandboxMapTarget as SandboxMapTargetV8,
  type SandboxMapTerritory,
} from './component_v8.ts'

export type { SandboxMapMember, SandboxMapTerritory }

export type SandboxContactRoute = {
  key: string
  channel_type: string
  value: string
  label?: string | null
  scope?: string | null
  department?: string | null
  stability_class?: string | null
  confidence?: number | null
  verify_after?: string | null
  is_primary?: boolean | null
  inherited?: boolean | null
  routing_note?: string | null
  source_authority?: string | null
  source_url?: string | null
}

export type SandboxContactCard = {
  lead_key: string
  subject_name: string
  organization_name?: string | null
  organization_type?: string | null
  site_name?: string | null
  address?: string | null
  website_url?: string | null
  role_label?: string | null
  resolution_status: string
  enrichment_status: 'none' | 'partial' | 'enriched'
  routes?: SandboxContactRoute[]
  route_count?: number | null
  research_note?: string | null
}

export type SandboxMapTarget = SandboxMapTargetV8 & {
  contact_card?: SandboxContactCard | null
}

function replaceRequired(source:string, needle:string, replacement:string, label:string){
  if(!source.includes(needle))throw new Error('Scout component sandbox v9 transform failed: '+label)
  return source.replace(needle,replacement)
}

const contactCss=`.contact-slide{display:block!important;background:var(--card)!important;text-align:left!important;color:var(--text)!important}.contact-card-shell{position:absolute;inset:0;padding:12px 13px 11px;display:flex;flex-direction:column;gap:7px;overflow:hidden}.contact-head{display:flex;align-items:center;gap:9px;padding-right:46px}.contact-avatar{width:34px;height:34px;border-radius:50%;display:grid;place-items:center;flex:none;background:var(--accent-soft);color:var(--accent);font-size:12px;font-weight:850;border:1px solid color-mix(in srgb,var(--accent) 24%,var(--line))}.contact-identity{min-width:0;flex:1}.contact-subject{font-size:13px;line-height:1.16;font-weight:780;color:var(--text);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.contact-context{font-size:9px;line-height:1.25;color:var(--muted);margin-top:2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.contact-status{flex:none;border-radius:999px;padding:4px 7px;font-size:8px;font-weight:800;line-height:1;background:var(--accent-soft);color:var(--accent);white-space:nowrap}.contact-routes{display:flex;flex-direction:column;gap:5px;min-height:0}.contact-route{display:grid;grid-template-columns:40px minmax(0,1fr);gap:7px;align-items:center;padding:6px 7px;border:1px solid var(--line);border-radius:9px;background:var(--subtle);min-height:40px}.contact-route-tag{font-size:7px;font-weight:850;letter-spacing:.04em;color:var(--accent);text-transform:uppercase}.contact-route-main{min-width:0}.contact-route-value{font-size:10px;line-height:1.15;font-weight:680;color:var(--text);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.contact-route-meta{font-size:8px;line-height:1.15;color:var(--muted);margin-top:2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.contact-empty{display:flex;flex-direction:column;justify-content:center;min-height:76px;padding:9px 10px;border:1px dashed var(--line);border-radius:10px;background:var(--subtle)}.contact-empty b{font-size:10px!important;color:var(--text)!important}.contact-empty span{font-size:9px;line-height:1.35;color:var(--muted);margin-top:4px}.contact-foot{margin-top:auto;padding-right:44px;font-size:8px;line-height:1.2;color:var(--muted);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}`

const oldThirdSlide=`<div class="slide"><span class="diamond" aria-hidden="true"></span><div><b>Placeholder image 3</b><small>Swipe horizontally</small></div><span class="counter">3 / 3</span></div>`
const newThirdSlide=`<div class="slide contact-slide" id="contactSlide"><div class="contact-card-shell"><div class="contact-head"><div class="contact-avatar" id="contactAvatar">?</div><div class="contact-identity"><div class="contact-subject" id="contactSubject">Lead contact</div><div class="contact-context" id="contactContext">Contact research pending</div></div><span class="contact-status" id="contactStatus">Pending</span></div><div class="contact-routes" id="contactRoutes"></div><div class="contact-foot" id="contactFoot">Contact card adapts to available enrichment.</div></div><span class="counter">3 / 3</span></div>`

const contactJs=`function contactInitials(card){const text=String(card?.organization_name||card?.subject_name||'?').trim();const parts=text.split(/\\s+/).filter(Boolean);if(!parts.length)return'?';return(parts.length===1?parts[0].slice(0,2):parts[0][0]+parts[parts.length-1][0]).toUpperCase()}
function contactChannelLabel(type){return({phone:'Phone',email:'Email',url:'Web',website:'Web',routing_instruction:'Route',supplier_portal:'Portal',form:'Form',procurement:'Procure',switchboard:'Phone'})[String(type||'').toLowerCase()]||String(type||'Route').replace(/_/g,' ')}
function contactResolutionLabel(card){if(card?.enrichment_status==='enriched')return'Enriched';if(card?.enrichment_status==='partial')return'Partial';return'Pending'}
function contactContextText(card){const bits=[];if(card?.role_label)bits.push(card.role_label);if(card?.organization_name&&card.organization_name!==card.subject_name)bits.push(card.organization_name);if(card?.site_name&&card.site_name!==card.subject_name)bits.push(card.site_name);if(card?.organization_type)bits.push(String(card.organization_type).replace(/_/g,' '));return bits.length?bits.join(' · '):String(card?.resolution_status||'lead identified').replace(/_/g,' ')}
function contactRouteMeta(route){const bits=[];if(route?.department)bits.push(route.department);else if(route?.scope)bits.push(String(route.scope).replace(/_/g,' '));if(Number.isFinite(Number(route?.confidence)))bits.push(Math.round(Number(route.confidence)*100)+'% confidence');if(route?.inherited)bits.push('inherited route');return bits.join(' · ')}
function renderContactCard(){const root=document.getElementById('contactSlide');if(!root)return;const card=mapTarget?.contact_card||{lead_key:mapTarget?.key||'lead',subject_name:mapTarget?.label||'Lead',resolution_status:'lead_identified',enrichment_status:'none',routes:[],research_note:'Contact research has not been completed yet.'},avatar=document.getElementById('contactAvatar'),subject=document.getElementById('contactSubject'),context=document.getElementById('contactContext'),status=document.getElementById('contactStatus'),routesEl=document.getElementById('contactRoutes'),foot=document.getElementById('contactFoot');avatar.textContent=contactInitials(card);subject.textContent=card.subject_name||card.organization_name||'Lead';context.textContent=contactContextText(card);status.textContent=contactResolutionLabel(card);routesEl.innerHTML='';const routes=Array.isArray(card.routes)?card.routes.filter(r=>r&&r.value).slice(0,2):[];if(routes.length){for(const route of routes){const row=document.createElement('div');row.className='contact-route';const tag=document.createElement('div');tag.className='contact-route-tag';tag.textContent=contactChannelLabel(route.channel_type);const main=document.createElement('div');main.className='contact-route-main';const value=document.createElement('div');value.className='contact-route-value';value.textContent=route.label||route.value;value.title=route.value;const meta=document.createElement('div');meta.className='contact-route-meta';meta.textContent=contactRouteMeta(route)||route.value;main.append(value,meta);row.append(tag,main);routesEl.appendChild(row)}}else{const empty=document.createElement('div');empty.className='contact-empty';const title=document.createElement('b');title.textContent='Contact research pending';const note=document.createElement('span');note.textContent=card.research_note||'No verified contact channel is attached yet. Keep the lead and continue enrichment.';empty.append(title,note);routesEl.appendChild(empty)}const routeCount=Number(card.route_count)||routes.length,site=card.address||card.website_url||'';foot.textContent=(routeCount?routeCount+' verified route'+(routeCount===1?'':'s'):'No verified route yet')+(site?' · '+site:'')}`
`

const oldRenderStaticStart=`function renderStaticMap(){if(!mapTarget)return;const map=`
const newRenderStaticStart=`function renderStaticMap(){if(!mapTarget)return;renderContactCard();const map=`

export function buildComponentSandboxHtml(targets: SandboxMapTarget[] = []) {
  let html=buildComponentSandboxHtmlV8(targets as unknown as SandboxMapTargetV8[])
  html=replaceRequired(html,'</style>',contactCss+'</style>','contact card CSS')
  html=replaceRequired(html,oldThirdSlide,newThirdSlide,'third tile contact card')
  html=replaceRequired(html,'<div class="label">Media</div>','<div class="label">Opportunity details</div>','carousel section label')
  html=replaceRequired(html,'aria-label="Placeholder image carousel"','aria-label="Opportunity detail carousel"','carousel accessibility label')
  html=replaceRequired(html,'const values=[\'Past year\',\'Past 6 months\',\'Past 90 days\',\'Past 30 days\',\'Past 7 days\',\'Current\'];',`const values=['Past year','Past 6 months','Past 90 days','Past 30 days','Past 7 days','Current'];\n${contactJs}`,'contact rendering helpers')
  html=replaceRequired(html,oldRenderStaticStart,newRenderStaticStart,'contact rendering lifecycle')
  return html
}
