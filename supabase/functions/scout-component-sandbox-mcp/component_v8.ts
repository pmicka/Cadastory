import {
  buildComponentSandboxHtml as buildComponentSandboxHtmlV7,
  type SandboxMapMember,
  type SandboxMapTarget as SandboxMapTargetV7,
} from './component_v7.ts'

export type { SandboxMapMember }

export type SandboxMapTerritory = {
  key: string
  label: string
  territory_kind: 'administrative_area' | 'named_market'
  boundary_status: 'resolved' | 'unresolved'
  coverage_basis: string
  state?: string | null
  confidence?: number | null
  source_url?: string | null
  source_authority?: string | null
  geometry?: {
    type: 'Polygon' | 'MultiPolygon'
    coordinates: unknown
  } | null
}

export type SandboxMapTarget = Omit<SandboxMapTargetV7,'members'> & {
  members?: SandboxMapMember[]
  portfolio_archetype?: string | null
  portfolio_geography_status?: 'resolved_assets' | 'documented_territory' | 'mixed' | 'reported_scale_only' | null
  resolved_member_count?: number | null
  reported_member_count_minimum?: number | null
  roster_status?: string | null
  territories?: SandboxMapTerritory[]
}

function replaceRequired(source:string, needle:string, replacement:string, label:string){
  if(!source.includes(needle))throw new Error('Scout component sandbox v8 transform failed: '+label)
  return source.replace(needle,replacement)
}

const territoryCss=`.territory-overlay{position:absolute;inset:0;width:100%;height:100%;z-index:4;pointer-events:none;overflow:hidden}.territory-area{fill:rgba(82,98,112,.16);stroke:rgba(67,83,97,.78);stroke-width:1.5;vector-effect:non-scaling-stroke}.legend-territory-swatch{width:14px;height:10px;border:1.5px solid rgba(67,83,97,.78);border-radius:2px;background:rgba(82,98,112,.16);flex:none}.legend-scope-text{flex-basis:100%;font-size:8px;line-height:1.25;color:var(--muted);white-space:normal;text-align:left}`

const oldFocusVars=`let focusMembers=[];\nlet focusLabel='';`
const newFocusVars=`let focusMembers=[];\nlet focusTerritories=[];\nlet focusLabel='';`

const oldValidMembers=`function validMembers(){return Array.isArray(mapTarget?.members)?mapTarget.members.filter(m=>m&&Number.isFinite(Number(m.lat))&&Number.isFinite(Number(m.lon))):[]}`
const newValidMembers=`function validMembers(){return Array.isArray(mapTarget?.members)?mapTarget.members.filter(m=>m&&Number.isFinite(Number(m.lat))&&Number.isFinite(Number(m.lon))):[]}\nfunction validTerritories(){return Array.isArray(mapTarget?.territories)?mapTarget.territories.filter(t=>t&&typeof t.key==='string'&&typeof t.label==='string'):[]}\nfunction resolvedTerritories(){return focusTerritories.filter(t=>t.boundary_status==='resolved'&&t.geometry&&(t.geometry.type==='Polygon'||t.geometry.type==='MultiPolygon'))}\nfunction unresolvedTerritories(){return focusTerritories.filter(t=>t.boundary_status!=='resolved'||!t.geometry)}`

const oldPrepareFocus=`function prepareGroupFocus(){focusMembers=[];focusLabel='';if(mapTarget?.kind!=='group')return;const members=validMembers();if(!members.length)return;const louisville={lat:38.2527,lon:-85.7585};const components=connectedComponents(members);components.sort((a,b)=>b.length-a.length||kmBetween(centroid(a),louisville)-kmBetween(centroid(b),louisville));focusMembers=components[0]||members;const c=centroid(focusMembers);focusLabel=kmBetween(c,louisville)<=45?'Louisville-area cluster':((focusMembers[0]?.city||focusMembers[0]?.state||'Regional')+' cluster')}`
const newPrepareFocus=`function prepareGroupFocus(){focusMembers=[];focusTerritories=[];focusLabel='';if(mapTarget?.kind!=='group')return;focusTerritories=validTerritories();const members=validMembers();if(!members.length){const resolved=resolvedTerritories();focusLabel=resolved[0]?.label||focusTerritories[0]?.label||'Documented portfolio geography';return}const louisville={lat:38.2527,lon:-85.7585};const components=connectedComponents(members);components.sort((a,b)=>b.length-a.length||kmBetween(centroid(a),louisville)-kmBetween(centroid(b),louisville));focusMembers=components[0]||members;const c=centroid(focusMembers);focusLabel=kmBetween(c,louisville)<=45?'Louisville-area cluster':((focusMembers[0]?.city||focusMembers[0]?.state||'Regional')+' cluster')}`

const oldBoundsFromMembers=`function boundsFromMembers(members){if(!members.length)return null;return{minLon:Math.min(...members.map(m=>Number(m.lon))),maxLon:Math.max(...members.map(m=>Number(m.lon))),minLat:Math.min(...members.map(m=>Number(m.lat))),maxLat:Math.max(...members.map(m=>Number(m.lat)))}}`
const newBoundsHelpers=`${oldBoundsFromMembers}\nfunction scanCoordinateBounds(value,b){if(!Array.isArray(value))return;if(value.length>=2&&Number.isFinite(Number(value[0]))&&Number.isFinite(Number(value[1]))&&!Array.isArray(value[0])){const lon=Number(value[0]),lat=Number(value[1]);b.minLon=Math.min(b.minLon,lon);b.maxLon=Math.max(b.maxLon,lon);b.minLat=Math.min(b.minLat,lat);b.maxLat=Math.max(b.maxLat,lat);return}for(const child of value)scanCoordinateBounds(child,b)}\nfunction boundsFromTerritories(territories){const b={minLon:Infinity,maxLon:-Infinity,minLat:Infinity,maxLat:-Infinity};for(const t of territories){if(t?.boundary_status!=='resolved'||!t.geometry)continue;scanCoordinateBounds(t.geometry.coordinates,b)}return[b.minLon,b.maxLon,b.minLat,b.maxLat].every(Number.isFinite)?b:null}\nfunction mergeBounds(a,b){if(!a)return b;if(!b)return a;return{minLon:Math.min(a.minLon,b.minLon),maxLon:Math.max(a.maxLon,b.maxLon),minLat:Math.min(a.minLat,b.minLat),maxLat:Math.max(a.maxLat,b.maxLat)}}\nfunction expandedBoundsForPortfolio(members,territories){let b=mergeBounds(boundsFromMembers(members),boundsFromTerritories(territories));if(!b&&mapTarget){const candidate={minLon:Number(mapTarget.min_lon),maxLon:Number(mapTarget.max_lon),minLat:Number(mapTarget.min_lat),maxLat:Number(mapTarget.max_lat)};if(Object.values(candidate).every(Number.isFinite))b=candidate}if(!b)return{minLon:-85.90,maxLon:-85.55,minLat:38.10,maxLat:38.45};let{minLon,maxLon,minLat,maxLat}=b;const centerLat=(minLat+maxLat)/2,metersPerDegLat=111320,metersPerDegLon=Math.max(15000,111320*Math.cos(centerLat*Math.PI/180));const widthM=(maxLon-minLon)*metersPerDegLon,heightM=(maxLat-minLat)*metersPerDegLat;if(widthM<5000){const add=(5000-widthM)/metersPerDegLon/2;minLon-=add;maxLon+=add}if(heightM<4000){const add=(4000-heightM)/metersPerDegLat/2;minLat-=add;maxLat+=add}const lonPad=(maxLon-minLon)*.08,latPad=(maxLat-minLat)*.08;return{minLon:minLon-lonPad,maxLon:maxLon+lonPad,minLat:minLat-latPad,maxLat:maxLat+latPad}}`

const oldLegend=`function renderLegend(){const el=document.getElementById('mapLegend');if(!el)return;if(mapTarget?.kind!=='group'||!focusMembers.length){el.hidden=true;el.innerHTML='';return}const types=[...new Set(focusMembers.map(m=>m.property_type||'other'))].sort((a,b)=>propertyTypeRank(a)-propertyTypeRank(b)||a.localeCompare(b));el.innerHTML='';for(const type of types){const item=document.createElement('span');item.className='legend-item';const swatch=document.createElement('span');swatch.className='legend-swatch '+type;swatch.setAttribute('aria-hidden','true');const label=document.createElement('span');label.textContent=typeLabel(type);item.append(swatch,label);el.appendChild(item)}el.hidden=false}`
const newLegend=`function territoryGeometryPath(geometry,world,left,top){if(!geometry||!Array.isArray(geometry.coordinates))return'';const polygons=geometry.type==='Polygon'?[geometry.coordinates]:geometry.type==='MultiPolygon'?geometry.coordinates:[];let d='';for(const polygon of polygons){if(!Array.isArray(polygon))continue;for(const ring of polygon){if(!Array.isArray(ring)||ring.length<3)continue;let started=false;for(const pair of ring){if(!Array.isArray(pair)||pair.length<2)continue;const lon=Number(pair[0]),lat=Number(pair[1]);if(!Number.isFinite(lon)||!Number.isFinite(lat))continue;const x=worldX(lon)*world-left,y=worldY(lat)*world-top;d+=(started?'L':'M')+x.toFixed(2)+' '+y.toFixed(2);started=true}if(started)d+='Z'}}return d}\nfunction renderTerritories(map,world,left,top,w,h){const territories=resolvedTerritories();if(!territories.length)return;const ns='http://www.w3.org/2000/svg',svg=document.createElementNS(ns,'svg');svg.classList.add('territory-overlay');svg.setAttribute('viewBox','0 0 '+w+' '+h);svg.setAttribute('aria-hidden','true');for(const territory of territories){const d=territoryGeometryPath(territory.geometry,world,left,top);if(!d)continue;const path=document.createElementNS(ns,'path');path.setAttribute('d',d);path.setAttribute('class','territory-area');path.setAttribute('fill-rule','evenodd');const title=document.createElementNS(ns,'title');title.textContent=territory.label+' · documented service territory';path.appendChild(title);svg.appendChild(path)}map.appendChild(svg)}\nfunction renderLegend(){const el=document.getElementById('mapLegend');if(!el)return;if(mapTarget?.kind!=='group'){el.hidden=true;el.innerHTML='';return}const types=[...new Set(focusMembers.map(m=>m.property_type||'other'))].sort((a,b)=>propertyTypeRank(a)-propertyTypeRank(b)||a.localeCompare(b)),resolved=resolvedTerritories(),unresolved=unresolvedTerritories();el.innerHTML='';for(const type of types){const item=document.createElement('span');item.className='legend-item';const swatch=document.createElement('span');swatch.className='legend-swatch '+type;swatch.setAttribute('aria-hidden','true');const label=document.createElement('span');label.textContent=typeLabel(type);item.append(swatch,label);el.appendChild(item)}if(resolved.length){const item=document.createElement('span');item.className='legend-item';const swatch=document.createElement('span');swatch.className='legend-territory-swatch';swatch.setAttribute('aria-hidden','true');const label=document.createElement('span');label.textContent='Documented service territory';item.append(swatch,label);el.appendChild(item)}if(unresolved.length){const scope=document.createElement('span');scope.className='legend-scope-text';const labels=[...new Set(unresolved.map(t=>t.label))].slice(0,3);scope.textContent='Broader documented scope: '+labels.join(' · ')+' · exact boundary unresolved';el.appendChild(scope)}el.hidden=!types.length&&!resolved.length&&!unresolved.length}`

const oldMapBounds=`const b=mapTarget.kind==='group'?expandedBoundsForGroup(focusMembers):expandedBoundsForProperty(mapTarget);`
const newMapBounds=`const b=mapTarget.kind==='group'?expandedBoundsForPortfolio(focusMembers,focusTerritories):expandedBoundsForProperty(mapTarget);`

const oldRenderSequence=`map.appendChild(img)}renderGroupNodes(map,z,world,left,top);renderLegend();`
const newRenderSequence=`map.appendChild(img)}renderTerritories(map,world,left,top,w,h);renderGroupNodes(map,z,world,left,top);renderLegend();`

const oldGroupSummary=`if(mapTarget.kind==='group'){note.textContent='Map frame: '+mapTarget.label+' · '+focusLabel+' '+focusMembers.length+'/'+mapTarget.scope_count+' · z'+z;map.setAttribute('aria-label','Static basemap showing '+focusMembers.length+' of '+mapTarget.scope_count+' portfolio properties for '+mapTarget.label)}else`
const newGroupSummary=`if(mapTarget.kind==='group'){const status=mapTarget.portfolio_geography_status||'resolved_assets',reported=Number(mapTarget.reported_member_count_minimum),scale=Number.isFinite(reported)&&reported>0?' · ≥'+reported.toLocaleString()+' reported locations':'',resolvedTerritoryCount=resolvedTerritories().length;if(status==='documented_territory'){note.textContent='Map frame: '+mapTarget.label+' · documented service territory · client sites unresolved'+scale+' · z'+z;map.setAttribute('aria-label','Static basemap showing '+resolvedTerritoryCount+' documented service territor'+(resolvedTerritoryCount===1?'y':'ies')+' for '+mapTarget.label+'; individual client sites are unresolved'+(scale?'; '+scale.slice(3):''))}else if(status==='mixed'){note.textContent='Map frame: '+mapTarget.label+' · '+focusMembers.length+' resolved assets + documented territory'+scale+' · z'+z;map.setAttribute('aria-label','Static basemap showing '+focusMembers.length+' resolved portfolio assets plus documented service territory for '+mapTarget.label)}else{note.textContent='Map frame: '+mapTarget.label+' · '+focusLabel+' '+focusMembers.length+'/'+mapTarget.scope_count+' resolved assets · z'+z;map.setAttribute('aria-label','Static basemap showing '+focusMembers.length+' of '+mapTarget.scope_count+' resolved portfolio assets for '+mapTarget.label)}}else`

export function buildComponentSandboxHtml(targets: SandboxMapTarget[] = []) {
  let html=buildComponentSandboxHtmlV7(targets as unknown as SandboxMapTargetV7[])
  html=replaceRequired(html,'</style>',territoryCss+'</style>','territory overlay CSS')
  html=replaceRequired(html,oldFocusVars,newFocusVars,'territory focus state')
  html=replaceRequired(html,oldValidMembers,newValidMembers,'territory validation helpers')
  html=replaceRequired(html,oldPrepareFocus,newPrepareFocus,'territory-aware group focus')
  html=replaceRequired(html,oldBoundsFromMembers,newBoundsHelpers,'territory-aware bounds')
  html=replaceRequired(html,oldLegend,newLegend,'territory rendering and legend')
  html=replaceRequired(html,oldMapBounds,newMapBounds,'territory-aware map framing')
  html=replaceRequired(html,oldRenderSequence,newRenderSequence,'territory render ordering')
  html=replaceRequired(html,oldGroupSummary,newGroupSummary,'portfolio geography map summary')
  html=html.replace('Owner-only preview · resolved physical portfolio assets use count-scaled same-type circles; labels move only within their own circles; widget state survives host remounts.','Owner-only preview · resolved assets use numbered circles; documented service territory uses bounded area fill; unresolved scope is labeled without synthetic sites; widget state survives host remounts.')
  return html
}
