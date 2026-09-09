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

const interactionCss=`.contact-route-value-button[data-downloadable="true"]{touch-action:manipulation;user-select:none;-webkit-user-select:none}`

export function buildComponentSandboxHtml(targets: SandboxMapTarget[] = []) {
  let html=buildComponentSandboxHtmlV11(targets as unknown as SandboxMapTargetV11[])
  html=replaceRequired(html,oldEligibility,newEligibility,'unified named-route vCard eligibility')
  html=replaceRequired(html,'</style>',interactionCss+'</style>','named-route touch behavior')
  return html
}
