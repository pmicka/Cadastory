import {
  buildComponentSandboxHtml as buildComponentSandboxHtmlV10,
  type SandboxMapMember,
  type SandboxMapTarget as SandboxMapTargetV10,
  type SandboxMapTerritory,
  type SandboxContactCard,
  type SandboxContactRoute,
} from './component_v10.ts'

export type { SandboxMapMember, SandboxMapTerritory, SandboxContactCard, SandboxContactRoute }
export type SandboxMapTarget = SandboxMapTargetV10

function replaceRequired(source:string, needle:string, replacement:string, label:string){
  if(!source.includes(needle))throw new Error('Scout component sandbox v11 transform failed: '+label)
  return source.replace(needle,replacement)
}

const routePersonCss=`.contact-route-value-button{appearance:none;border:0;padding:0;margin:0;background:transparent;color:var(--text);font:inherit;font-size:10px;line-height:1.15;font-weight:680;text-align:left;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:100%}.contact-route-value-button[data-downloadable="true"]{cursor:pointer;text-decoration:underline;text-decoration-color:color-mix(in srgb,var(--accent) 48%,transparent);text-underline-offset:2px}.contact-route-value-button[data-downloadable="true"]::after{content:' ↓';color:var(--accent);font-size:8px;text-decoration:none}.contact-route-value-button:disabled{opacity:1;color:var(--text);cursor:default}`

const helperMarker='function renderContactCard(){'
const routePersonHelpers=`function namedRouteIdentity(route){const label=String(route?.label||'').trim(),value=String(route?.value||'').trim();let match=value.match(/^(?:ask for|call[^.]*?and ask for)\\s+([^,]+),\\s+(.+?)(?:\\s+via\\b|\\.|$)/i);if(match){const rawName=match[1].trim();if(!/\\bor\\b/i.test(rawName))return{name:rawName,title:match[2].trim()}}const parts=label.split(/\\s+[—–]\\s+/);if(parts.length===2){const left=parts[0].trim(),right=parts[1].trim();if(right.split(/\\s+/).length>=2&&!/routing|request|vendor|facilit|operations route|procurement route/i.test(right))return{name:right,title:left}}return null}
function personCardFromRoute(card,route){const identity=namedRouteIdentity(route);if(!identity)return null;return{lead_key:String(card?.lead_key||'lead')+':'+String(route?.key||identity.name),subject_name:identity.name,organization_name:card?.organization_name||card?.subject_name||null,organization_type:card?.organization_type||null,site_name:card?.site_name||null,address:card?.address||null,website_url:card?.website_url||null,role_label:identity.title||null,resolution_status:'named_routing_contact',enrichment_status:'partial',routes:[route],route_count:1,research_note:null}}
function namedRouteVcardEligibility(card,route){const candidate=personCardFromRoute(card,route);if(!candidate)return false;const name=String(candidate.subject_name||'').trim(),org=String(candidate.organization_name||'').trim(),title=String(candidate.role_label||'').trim(),routeValue=String(route?.value||'').trim();return!!name&&!!routeValue&&(!!org||!!title)}
function renderContactCard(){`

const oldRouteValue="const value=document.createElement('div');value.className='contact-route-value';value.textContent=route.label||route.value;value.title=route.value;"
const newRouteValue="const personCandidate=personCardFromRoute(card,route),personDownloadable=namedRouteVcardEligibility(card,route),value=document.createElement(personDownloadable?'button':'div');value.className=personDownloadable?'contact-route-value-button':'contact-route-value';if(personDownloadable){value.type='button';value.dataset.downloadable='true';value.setAttribute('aria-label','Save '+personCandidate.subject_name+' contact file');value.title='Save '+personCandidate.subject_name+' (.vcf)';value.onclick=(event)=>{event.stopPropagation();showVcardPrompt(personCandidate)}}else value.title=route.value;value.textContent=route.label||route.value;"

const oldPromptCopy="copy.textContent='Download '+String(card.subject_name||card.organization_name||'this contact')+' as a standard .vcf contact file?';"
const newPromptCopy="copy.textContent='Download '+String(card.subject_name||card.organization_name||'this contact')+' as a standard .vcf contact file?';"

export function buildComponentSandboxHtml(targets: SandboxMapTarget[] = []) {
  let html=buildComponentSandboxHtmlV10(targets as unknown as SandboxMapTargetV10[])
  html=replaceRequired(html,'</style>',routePersonCss+'</style>','named route contact CSS')
  html=replaceRequired(html,helperMarker,routePersonHelpers,'named route identity helpers')
  html=replaceRequired(html,oldRouteValue,newRouteValue,'named route person vCard affordance')
  html=replaceRequired(html,oldPromptCopy,newPromptCopy,'person-aware vCard prompt copy')
  return html
}
