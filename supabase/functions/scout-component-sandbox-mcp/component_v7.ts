import {
  buildComponentSandboxHtml as buildComponentSandboxHtmlV6,
  type SandboxMapTarget as SandboxMapTargetV6,
} from './component_v6.ts'

export type SandboxMapMemberType =
  | 'multifamily'
  | 'senior_living'
  | 'hotel'
  | 'office'
  | 'retail'
  | 'industrial'
  | 'residential'
  | 'dealership'
  | 'water_tank_elevated'
  | 'water_tank_standpipe'
  | 'water_tank_ground_storage'
  | 'water_tank_other'
  | 'other'

export type SandboxMapMember = {
  key: string
  label: string
  property_type: SandboxMapMemberType
  property_type_label: string
  city?: string | null
  state?: string | null
  lon: number
  lat: number
}

export type SandboxMapTarget = Omit<SandboxMapTargetV6,'members'> & {
  members?: SandboxMapMember[]
}

function replaceRequired(source:string, needle:string, replacement:string, label:string){
  if(!source.includes(needle))throw new Error('Scout component sandbox v7 transform failed: '+label)
  return source.replace(needle,replacement)
}

const oldNodeTypeColors=`.map-node.multifamily{--node-rgb:36,111,121}.map-node.residential{--node-rgb:70,118,76}.map-node.senior_living{--node-rgb:171,116,39}.map-node.hotel{--node-rgb:55,92,145}.map-node.office{--node-rgb:102,80,139}.map-node.retail{--node-rgb:154,73,94}.map-node.industrial{--node-rgb:82,92,99}`
const newNodeTypeColors=`.map-node.multifamily{--node-rgb:36,111,121}.map-node.residential{--node-rgb:70,118,76}.map-node.senior_living{--node-rgb:171,116,39}.map-node.hotel{--node-rgb:55,92,145}.map-node.office{--node-rgb:102,80,139}.map-node.retail{--node-rgb:154,73,94}.map-node.industrial{--node-rgb:82,92,99}.map-node.dealership{--node-rgb:151,87,48}.map-node.water_tank_elevated{--node-rgb:35,126,151}.map-node.water_tank_standpipe{--node-rgb:59,98,170}.map-node.water_tank_ground_storage{--node-rgb:91,119,70}.map-node.water_tank_other{--node-rgb:100,109,120}.map-node.other{--node-rgb:112,112,112}`

const oldLegendTypeColors=`.legend-swatch.multifamily{--node-rgb:36,111,121}.legend-swatch.residential{--node-rgb:70,118,76}.legend-swatch.senior_living{--node-rgb:171,116,39}.legend-swatch.hotel{--node-rgb:55,92,145}.legend-swatch.office{--node-rgb:102,80,139}.legend-swatch.retail{--node-rgb:154,73,94}.legend-swatch.industrial{--node-rgb:82,92,99}`
const newLegendTypeColors=`.legend-swatch.multifamily{--node-rgb:36,111,121}.legend-swatch.residential{--node-rgb:70,118,76}.legend-swatch.senior_living{--node-rgb:171,116,39}.legend-swatch.hotel{--node-rgb:55,92,145}.legend-swatch.office{--node-rgb:102,80,139}.legend-swatch.retail{--node-rgb:154,73,94}.legend-swatch.industrial{--node-rgb:82,92,99}.legend-swatch.dealership{--node-rgb:151,87,48}.legend-swatch.water_tank_elevated{--node-rgb:35,126,151}.legend-swatch.water_tank_standpipe{--node-rgb:59,98,170}.legend-swatch.water_tank_ground_storage{--node-rgb:91,119,70}.legend-swatch.water_tank_other{--node-rgb:100,109,120}.legend-swatch.other{--node-rgb:112,112,112}`

const oldTypeLabel=`function typeLabel(type){return({multifamily:'Multifamily',senior_living:'Senior living',hotel:'Hotel',office:'Office',retail:'Retail',industrial:'Industrial',residential:'Residential'})[type]||'Property'}`
const newTypeLabel=`function typeLabel(type){return({multifamily:'Multifamily',senior_living:'Senior living',hotel:'Hotel',office:'Office',retail:'Retail',industrial:'Industrial',residential:'Residential',dealership:'Dealership',water_tank_elevated:'Elevated tank',water_tank_standpipe:'Standpipe',water_tank_ground_storage:'Ground storage',water_tank_other:'Water tank',other:'Other asset'})[type]||'Portfolio asset'}`

const oldTypeOrder=`const PROPERTY_TYPE_ORDER=['multifamily','senior_living','hotel','office','retail','industrial','residential']`
const newTypeOrder=`const PROPERTY_TYPE_ORDER=['multifamily','senior_living','hotel','dealership','office','retail','industrial','residential','water_tank_elevated','water_tank_standpipe','water_tank_ground_storage','water_tank_other','other']`

const oldLegendJs=`function renderLegend(){const el=document.getElementById('mapLegend');if(!el)return;if(mapTarget?.kind!=='group'||!focusMembers.length){el.hidden=true;el.innerHTML='';return}const types=[...new Set(focusMembers.map(m=>m.property_type||'residential'))];el.innerHTML='';for(const type of types){const item=document.createElement('span');item.className='legend-item';const swatch=document.createElement('span');swatch.className='legend-swatch '+type;swatch.setAttribute('aria-hidden','true');const label=document.createElement('span');label.textContent=typeLabel(type);item.append(swatch,label);el.appendChild(item)}el.hidden=false}`
const newLegendJs=`function renderLegend(){const el=document.getElementById('mapLegend');if(!el)return;if(mapTarget?.kind!=='group'||!focusMembers.length){el.hidden=true;el.innerHTML='';return}const types=[...new Set(focusMembers.map(m=>m.property_type||'other'))].sort((a,b)=>propertyTypeRank(a)-propertyTypeRank(b)||a.localeCompare(b));el.innerHTML='';for(const type of types){const item=document.createElement('span');item.className='legend-item';const swatch=document.createElement('span');swatch.className='legend-swatch '+type;swatch.setAttribute('aria-hidden','true');const label=document.createElement('span');label.textContent=typeLabel(type);item.append(swatch,label);el.appendChild(item)}el.hidden=false}`

const placeholderCircleCss=`.circle{width:44px;height:44px;border-radius:50%;background:color-mix(in srgb,var(--card) 76%,transparent);margin:0 auto 16px}`

export function buildComponentSandboxHtml(targets: SandboxMapTarget[] = []) {
  let html=buildComponentSandboxHtmlV6(targets as unknown as SandboxMapTargetV6[])
  html=replaceRequired(html,oldNodeTypeColors,newNodeTypeColors,'portfolio member node colors')
  html=replaceRequired(html,oldLegendTypeColors,newLegendTypeColors,'portfolio member legend colors')
  html=replaceRequired(html,oldTypeLabel,newTypeLabel,'portfolio member labels')
  html=replaceRequired(html,oldTypeOrder,newTypeOrder,'portfolio member stable order')
  html=replaceRequired(html,oldLegendJs,newLegendJs,'stable portfolio legend order')
  html=replaceRequired(html,placeholderCircleCss,'','remove placeholder circle CSS')
  html=replaceRequired(html,'<div><div class="circle"></div><b>Placeholder image 1</b>','<div><b>Placeholder image 1</b>','remove placeholder slide 1 circle')
  html=replaceRequired(html,'<div><div class="circle"></div><b>Placeholder image 3</b>','<div><b>Placeholder image 3</b>','remove placeholder slide 3 circle')
  html=html.replace('Owner-only preview · count-scaled same-type circles merge only at 0.85 screen-space collision; count labels move only within their own circles; widget state survives host remounts.','Owner-only preview · resolved physical portfolio assets use count-scaled same-type circles; labels move only within their own circles; widget state survives host remounts.')
  return html
}
