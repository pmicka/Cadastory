from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BRANCH = 'scout/school-district-portfolio'


def write(path: str, content: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding='utf-8')


def replace_once(path: str, old: str, new: str) -> None:
    target = ROOT / path
    text = target.read_text(encoding='utf-8')
    if old not in text:
        raise SystemExit(f'anchor not found in {path}: {old[:120]!r}')
    target.write_text(text.replace(old, new, 1), encoding='utf-8')


MODEL = r'''export type ScoutSchoolDistrictPortfolioPoint = { type: 'Point'; coordinates: [number, number] }

export type ScoutSchoolDistrictPortfolioMember = {
  id: string
  name: string
  address: string
  city: string
  state_code: 'IN'
  zip: string
  point: ScoutSchoolDistrictPortfolioPoint
  school_year: '2024-2025'
  observed_at: string
}

export type ScoutSchoolDistrictCapitalSignal = {
  id: string
  kind: 'district_roof_capital_project'
  project_title: 'Roof Project'
  estimated_cost: number
  start_date_text: string
  end_date_text: string
  plan_year: 2027
  plan_id: '10695'
  plan_submitted_at: string
  extraction_confidence: 'high'
  site_attribution: 'district_only_unresolved'
  observed_at: string
}

export type ScoutSandboxSchoolDistrictPortfolioMap = {
  contract_version: 'school_district_portfolio_map_v1'
  opportunity_type: 'school_district_portfolio'
  group_kind: 'portfolio'
  account_name: 'Scott County School District 2'
  district_key: 'IN-7255'
  nces_district_id: '1810020'
  dlgf_unit_id: '1288'
  dlgf_unit_code: '7255'
  scope: 'documented_public_school_roster'
  facility_source_slug: 'nces-edge-public-schools-2425'
  signal_source_slug: 'indiana-dlgf-school-capital-projects'
  relationship: 'district_membership'
  target_kind: 'school_facility_member'
  map_semantics: 'documented_public_school_facility_portfolio'
  evidence_boundary: 'NCES school facility locations plus district-level DLGF capital-plan signals; capital projects are not attributed to individual schools unless explicitly documented'
  generated_at: string
  observed_at: string
  facility_observed_at: string
  capital_plan_observed_at: string
  member_count: number
  resolved_member_count: number
  bounds: { west: number; south: number; east: number; north: number }
  members: ScoutSchoolDistrictPortfolioMember[]
  capital_signals: ScoutSchoolDistrictCapitalSignal[]
  guardrail: string
}

export type ScoutSandboxSchoolDistrictPortfolioOpportunity = {
  opportunity_type: 'school_district_portfolio'
  name: 'Scott County School District 2'
  district_key: 'IN-7255'
  member_count: number
  observed_at: string
  school_year: '2024-2025'
  roof_project_estimated_cost: number
  roof_project_start_text: string
  roof_project_end_text: string
  roof_project_plan_year: 2027
  project_site_attribution: 'district_only_unresolved'
  map_semantics: 'documented_public_school_facility_portfolio'
  evidence_boundary: 'NCES school facility locations plus district-level DLGF capital-plan signals; capital projects are not attributed to individual schools unless explicitly documented'
  why_investigate: string
  guardrail: string
}

const EVIDENCE_BOUNDARY = 'NCES school facility locations plus district-level DLGF capital-plan signals; capital projects are not attributed to individual schools unless explicitly documented' as const
const GUARDRAIL = 'This map is a documented NCES public-school facility roster for Scott County School District 2. The DLGF capital plan separately documents a district-level Roof Project with a $500,000 estimate and Summer 2027–Summer 2029 timing, but the source does not identify which campus or building is associated with that project. Do not treat any mapped school as the roof-project site, and do not treat the plan as a solicitation, award, current cleaning need, approved vendor route, or proof that work is available.'

function cleanString(value: unknown, maxLength = 1000) { if (typeof value !== 'string') return null; const text = value.trim(); return text.length > 0 && text.length <= maxLength ? text : null }
function cleanNumber(value: unknown, minimum: number, maximum: number) { return typeof value === 'number' && Number.isFinite(value) && value >= minimum && value <= maximum ? value : null }
function normalizeTimestamp(value: unknown) { const text = cleanString(value, 80); if (!text) return null; const date = new Date(text); return Number.isNaN(date.valueOf()) ? null : date.toISOString() }
function latestTimestamp(values: string[]) { let latest: { value: string; time: number } | null = null; for (const value of values) { const time = new Date(value).valueOf(); if (Number.isFinite(time) && (!latest || time > latest.time)) latest = { value, time } } return latest?.value ?? null }

function normalizeMember(value: unknown): ScoutSchoolDistrictPortfolioMember | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null
  const source = value as Record<string, unknown>
  const id = cleanString(source.id, 40), name = cleanString(source.name, 200), address = cleanString(source.address, 240), city = cleanString(source.city, 120), zip = cleanString(source.zip, 16)
  const state = cleanString(source.state_code, 8), schoolYear = cleanString(source.school_year, 20), observedAt = normalizeTimestamp(source.observed_at)
  if (!source.point || typeof source.point !== 'object' || Array.isArray(source.point)) return null
  const point = source.point as Record<string, unknown>
  if (point.type !== 'Point' || !Array.isArray(point.coordinates) || point.coordinates.length !== 2) return null
  const lon = cleanNumber(point.coordinates[0], -180, 180), lat = cleanNumber(point.coordinates[1], -90, 90)
  if (!id || !name || !address || !city || !zip || state?.toUpperCase() !== 'IN' || schoolYear !== '2024-2025' || !observedAt || lon === null || lat === null) return null
  return { id, name, address, city, state_code: 'IN', zip, point: { type: 'Point', coordinates: [lon, lat] }, school_year: '2024-2025', observed_at: observedAt }
}

function normalizeSignal(value: unknown): ScoutSchoolDistrictCapitalSignal | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null
  const source = value as Record<string, unknown>
  const id = cleanString(source.id, 120), title = cleanString(source.project_title, 200), start = cleanString(source.start_date_text, 120), end = cleanString(source.end_date_text, 120)
  const planSubmitted = normalizeTimestamp(source.plan_submitted_at), observedAt = normalizeTimestamp(source.observed_at), cost = cleanNumber(source.estimated_cost, 1, 1_000_000_000)
  if (!id || source.kind !== 'district_roof_capital_project' || title !== 'Roof Project' || cost === null || !start || !end || source.plan_year !== 2027 || source.plan_id !== '10695' || !planSubmitted || source.extraction_confidence !== 'high' || source.site_attribution !== 'district_only_unresolved' || !observedAt) return null
  return { id, kind: 'district_roof_capital_project', project_title: 'Roof Project', estimated_cost: cost, start_date_text: start, end_date_text: end, plan_year: 2027, plan_id: '10695', plan_submitted_at: planSubmitted, extraction_confidence: 'high', site_attribution: 'district_only_unresolved', observed_at: observedAt }
}

export function normalizeScoutSandboxSchoolDistrictPortfolioMap(value: unknown): ScoutSandboxSchoolDistrictPortfolioMap | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null
  const source = value as Record<string, unknown>
  if (source.contract_version !== 'school_district_portfolio_map_v1' || source.account_name !== 'Scott County School District 2' || source.district_key !== 'IN-7255' || source.nces_district_id !== '1810020' || source.dlgf_unit_id !== '1288' || source.dlgf_unit_code !== '7255') return null
  if (source.scope !== 'documented_public_school_roster' || source.facility_source_slug !== 'nces-edge-public-schools-2425' || source.signal_source_slug !== 'indiana-dlgf-school-capital-projects' || source.relationship !== 'district_membership') return null
  const generatedAt = normalizeTimestamp(source.generated_at), facilityObservedAt = normalizeTimestamp(source.facility_observed_at), capitalPlanObservedAt = normalizeTimestamp(source.capital_plan_observed_at)
  if (!generatedAt || !facilityObservedAt || !capitalPlanObservedAt || !Array.isArray(source.members) || source.members.length < 1 || source.members.length > 100 || !Array.isArray(source.capital_signals) || source.capital_signals.length < 1 || source.capital_signals.length > 20) return null
  const members: ScoutSchoolDistrictPortfolioMember[] = []
  const ids = new Set<string>()
  for (const item of source.members) { const member = normalizeMember(item); if (!member || ids.has(member.id)) return null; ids.add(member.id); members.push(member) }
  const signals: ScoutSchoolDistrictCapitalSignal[] = []
  for (const item of source.capital_signals) { const signal = normalizeSignal(item); if (!signal) return null; signals.push(signal) }
  const roofSignals = signals.filter((signal) => signal.kind === 'district_roof_capital_project')
  if (roofSignals.length !== 1) return null
  const lons = members.map((member) => member.point.coordinates[0]), lats = members.map((member) => member.point.coordinates[1])
  const observedAt = latestTimestamp([facilityObservedAt, capitalPlanObservedAt, ...members.map((member) => member.observed_at), ...signals.map((signal) => signal.observed_at)])
  if (!observedAt) return null
  return {
    contract_version: 'school_district_portfolio_map_v1', opportunity_type: 'school_district_portfolio', group_kind: 'portfolio', account_name: 'Scott County School District 2', district_key: 'IN-7255', nces_district_id: '1810020', dlgf_unit_id: '1288', dlgf_unit_code: '7255', scope: 'documented_public_school_roster', facility_source_slug: 'nces-edge-public-schools-2425', signal_source_slug: 'indiana-dlgf-school-capital-projects', relationship: 'district_membership', target_kind: 'school_facility_member', map_semantics: 'documented_public_school_facility_portfolio', evidence_boundary: EVIDENCE_BOUNDARY, generated_at: generatedAt, observed_at: observedAt, facility_observed_at: facilityObservedAt, capital_plan_observed_at: capitalPlanObservedAt, member_count: members.length, resolved_member_count: members.length, bounds: { west: Math.min(...lons), south: Math.min(...lats), east: Math.max(...lons), north: Math.max(...lats) }, members, capital_signals: signals, guardrail: GUARDRAIL,
  }
}

export function buildScoutSandboxSchoolDistrictPortfolioOpportunity(map: ScoutSandboxSchoolDistrictPortfolioMap): ScoutSandboxSchoolDistrictPortfolioOpportunity {
  const roof = map.capital_signals.find((signal) => signal.kind === 'district_roof_capital_project')!
  return { opportunity_type: 'school_district_portfolio', name: 'Scott County School District 2', district_key: 'IN-7255', member_count: map.member_count, observed_at: map.observed_at, school_year: '2024-2025', roof_project_estimated_cost: roof.estimated_cost, roof_project_start_text: roof.start_date_text, roof_project_end_text: roof.end_date_text, roof_project_plan_year: 2027, project_site_attribution: 'district_only_unresolved', map_semantics: 'documented_public_school_facility_portfolio', evidence_boundary: EVIDENCE_BOUNDARY, why_investigate: 'Scout has a defensible district-level portfolio context: six documented NCES school facilities and a high-confidence DLGF capital-plan Roof Project estimated at $500,000 for Summer 2027 through Summer 2029. Use the capital signal to qualify the district account and investigate facilities, procurement, and current exterior needs; do not assign the roof project to a mapped campus without new evidence.', guardrail: map.guardrail }
}

export function normalizeScoutSandboxSchoolDistrictPortfolioOpportunity(value: unknown): ScoutSandboxSchoolDistrictPortfolioOpportunity | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null
  const source = value as Record<string, unknown>
  const observedAt = normalizeTimestamp(source.observed_at), count = cleanNumber(source.member_count, 1, 100), cost = cleanNumber(source.roof_project_estimated_cost, 1, 1_000_000_000), start = cleanString(source.roof_project_start_text, 120), end = cleanString(source.roof_project_end_text, 120), why = cleanString(source.why_investigate, 1400), guardrail = cleanString(source.guardrail, 2000)
  if (source.opportunity_type !== 'school_district_portfolio' || source.name !== 'Scott County School District 2' || source.district_key !== 'IN-7255' || count === null || !Number.isInteger(count) || !observedAt || source.school_year !== '2024-2025' || cost === null || !start || !end || source.roof_project_plan_year !== 2027 || source.project_site_attribution !== 'district_only_unresolved' || source.map_semantics !== 'documented_public_school_facility_portfolio' || source.evidence_boundary !== EVIDENCE_BOUNDARY || !why || !guardrail) return null
  return { opportunity_type: 'school_district_portfolio', name: 'Scott County School District 2', district_key: 'IN-7255', member_count: count, observed_at: observedAt, school_year: '2024-2025', roof_project_estimated_cost: cost, roof_project_start_text: start, roof_project_end_text: end, roof_project_plan_year: 2027, project_site_attribution: 'district_only_unresolved', map_semantics: 'documented_public_school_facility_portfolio', evidence_boundary: EVIDENCE_BOUNDARY, why_investigate: why, guardrail }
}
'''

RENDERER = r'''import type { ScoutSandboxSchoolDistrictPortfolioMap } from './school_district_portfolio_map_model.ts'

const TILE_SIZE = 256
const MAX_MERCATOR_LAT = 85.05112878
const DEFAULT_MIN_ZOOM = 5
const DEFAULT_MAX_ZOOM = 18
const DEFAULT_PADDING_PX = 24
export type ScoutSchoolDistrictPortfolioRasterTile = { z: number; x: number; y: number; left: number; top: number; url: string }
export type ScoutSchoolDistrictPortfolioMarker = { left: number; top: number; name: string; city: string }
export type ScoutSchoolDistrictPortfolioRasterFrame = { zoom: number; width: number; height: number; tiles: ScoutSchoolDistrictPortfolioRasterTile[]; markers: ScoutSchoolDistrictPortfolioMarker[] }
export type ScoutSchoolDistrictPortfolioRasterFrameOptions = { tileUrlTemplate: string; minZoom?: number; maxZoom?: number; paddingPx?: number }
function clampLat(lat:number){return Math.max(-MAX_MERCATOR_LAT,Math.min(MAX_MERCATOR_LAT,lat))}
function worldX(lon:number){return(lon+180)/360}
function worldY(lat:number){const radians=clampLat(lat)*Math.PI/180;return(1-Math.log(Math.tan(radians)+1/Math.cos(radians))/Math.PI)/2}
function tileUrl(template:string,z:number,x:number,y:number){return template.replace('{z}',String(z)).replace('{x}',String(x)).replace('{y}',String(y))}
function fitZoom(data:ScoutSandboxSchoolDistrictPortfolioMap,width:number,height:number,minZoom:number,maxZoom:number,paddingPx:number){const usableWidth=Math.max(1,width-paddingPx*2),usableHeight=Math.max(1,height-paddingPx*2),west=worldX(data.bounds.west),east=worldX(data.bounds.east),north=worldY(data.bounds.north),south=worldY(data.bounds.south),spanX=Math.max(1e-12,Math.abs(east-west)),spanY=Math.max(1e-12,Math.abs(south-north));for(let zoom=maxZoom;zoom>=minZoom;zoom--){const world=TILE_SIZE*Math.pow(2,zoom);if(spanX*world<=usableWidth&&spanY*world<=usableHeight)return zoom}return minZoom}
export function buildScoutSchoolDistrictPortfolioRasterFrame(data:ScoutSandboxSchoolDistrictPortfolioMap,width:number,height:number,options:ScoutSchoolDistrictPortfolioRasterFrameOptions):ScoutSchoolDistrictPortfolioRasterFrame{const frameWidth=Math.max(280,Math.round(width||0)),frameHeight=Math.max(180,Math.round(height||0)),minZoom=options.minZoom??DEFAULT_MIN_ZOOM,maxZoom=options.maxZoom??DEFAULT_MAX_ZOOM,paddingPx=options.paddingPx??DEFAULT_PADDING_PX,zoom=fitZoom(data,frameWidth,frameHeight,minZoom,maxZoom,paddingPx),world=TILE_SIZE*Math.pow(2,zoom),westX=worldX(data.bounds.west),eastX=worldX(data.bounds.east),northY=worldY(data.bounds.north),southY=worldY(data.bounds.south),centerPxX=((westX+eastX)/2)*world,centerPxY=((northY+southY)/2)*world,left=centerPxX-frameWidth/2,top=centerPxY-frameHeight/2,startX=Math.floor(left/TILE_SIZE),endX=Math.floor((left+frameWidth-1)/TILE_SIZE),startY=Math.floor(top/TILE_SIZE),endY=Math.floor((top+frameHeight-1)/TILE_SIZE),tileCount=Math.pow(2,zoom),tiles:ScoutSchoolDistrictPortfolioRasterTile[]=[];for(let tx=startX;tx<=endX;tx++){for(let ty=startY;ty<=endY;ty++){if(ty<0||ty>=tileCount)continue;const wrappedX=((tx%tileCount)+tileCount)%tileCount;tiles.push({z:zoom,x:wrappedX,y:ty,left:tx*TILE_SIZE-left,top:ty*TILE_SIZE-top,url:tileUrl(options.tileUrlTemplate,zoom,wrappedX,ty)})}}const markers:ScoutSchoolDistrictPortfolioMarker[]=data.members.map(member=>({left:worldX(member.point.coordinates[0])*world-left,top:worldY(member.point.coordinates[1])*world-top,name:member.name,city:member.city}));return{zoom,width:frameWidth,height:frameHeight,tiles,markers}}
'''

MOUNT = r'''import type { ScoutSandboxSchoolDistrictPortfolioMap } from './school_district_portfolio_map_model.ts'
import { buildScoutSchoolDistrictPortfolioRasterFrame, type ScoutSchoolDistrictPortfolioRasterFrameOptions } from './school_district_portfolio_map_renderer.ts'
const DEFAULT_TIMEOUT_MS=7000
const PNG_DATA_URL_PREFIX='data:image/png;base64,'
async function decodeEmbeddedRasterTile(dataUrl:string){if(!dataUrl.startsWith(PNG_DATA_URL_PREFIX))throw new Error('Scout embedded raster tile is invalid');const binary=atob(dataUrl.slice(PNG_DATA_URL_PREFIX.length)),bytes=new Uint8Array(binary.length);for(let i=0;i<binary.length;i++)bytes[i]=binary.charCodeAt(i);return await createImageBitmap(new Blob([bytes],{type:'image/png'}))}
export type ScoutSchoolDistrictPortfolioMapMountOptions=ScoutSchoolDistrictPortfolioRasterFrameOptions&{attributionLabel:string;attributionUrl:string;timeoutMs?:number;embeddedTiles?:Record<string,string>;onError?:(error:Error)=>void;onReady?:()=>void}
export function mountScoutSchoolDistrictPortfolioMap(container:HTMLElement,data:ScoutSandboxSchoolDistrictPortfolioMap,options:ScoutSchoolDistrictPortfolioMapMountOptions){let destroyed=false,generation=0,timeout:ReturnType<typeof setTimeout>|null=null,lastW=-1,lastH=-1;const clear=()=>{if(timeout!==null){clearTimeout(timeout);timeout=null}};const render=(force=false)=>{if(destroyed)return;const frame=buildScoutSchoolDistrictPortfolioRasterFrame(data,container.clientWidth,container.clientHeight,options);if(!force&&frame.width===lastW&&frame.height===lastH)return;lastW=frame.width;lastH=frame.height;clear();generation++;const g=generation;container.replaceChildren();let loaded=0,settled=0,ready=false;const ok=()=>{if(destroyed||g!==generation||ready)return;ready=true;clear();options.onReady?.()};const bad=()=>{if(destroyed||g!==generation||ready)return;clear();options.onError?.(new Error('Scout raster tiles did not load'))};const embedded=frame.tiles.length>0&&frame.tiles.every(t=>options.embeddedTiles?.[t.url]);if(embedded){const canvas=document.createElement('canvas');canvas.width=frame.width;canvas.height=frame.height;canvas.style.position='absolute';canvas.style.inset='0';canvas.style.width=`${frame.width}px`;canvas.style.height=`${frame.height}px`;container.appendChild(canvas);const ctx=canvas.getContext('2d');if(!ctx){bad();return}void Promise.allSettled(frame.tiles.map(async t=>{const bitmap=await decodeEmbeddedRasterTile(options.embeddedTiles![t.url]);if(!destroyed&&g===generation){ctx.drawImage(bitmap,t.left,t.top,256,256);loaded++}bitmap.close()})).then(()=>{settled=frame.tiles.length;loaded>0?ok():bad()})}else{for(const t of frame.tiles){const image=document.createElement('img');image.alt='';image.draggable=false;image.decoding='async';image.loading='eager';image.referrerPolicy='origin';image.src=t.url;image.style.left=`${t.left}px`;image.style.top=`${t.top}px`;image.addEventListener('load',()=>{if(destroyed||g!==generation)return;loaded++;settled++;if(loaded===1)ok()},{once:true});image.addEventListener('error',()=>{if(destroyed||g!==generation)return;settled++;if(settled===frame.tiles.length&&loaded===0)bad()},{once:true});container.appendChild(image)}}for(const m of frame.markers){const marker=document.createElement('span');marker.className='scout-portfolio-marker';marker.style.left=`${m.left}px`;marker.style.top=`${m.top}px`;marker.style.setProperty('--scout-portfolio-marker-color','#376b8a');marker.style.backgroundColor='#376b8a';marker.title=`${m.name} · ${m.city}, IN · documented NCES school facility`;marker.setAttribute('aria-hidden','true');container.appendChild(marker)}const legend=document.createElement('span');legend.className='scout-portfolio-legend';legend.setAttribute('aria-hidden','true');const item=document.createElement('span');item.className='scout-portfolio-legend-item';const swatch=document.createElement('span');swatch.className='scout-portfolio-legend-swatch';swatch.style.backgroundColor='#376b8a';const text=document.createElement('span');text.textContent='Documented NCES school facility';item.append(swatch,text);legend.appendChild(item);const status=document.createElement('span');status.className='scout-portfolio-legend-status';status.textContent='DLGF roof signal is district-level · no campus attribution';legend.appendChild(status);container.appendChild(legend);const attr=document.createElement('span');attr.className='scout-map-attribution';const link=document.createElement('a');link.href=options.attributionUrl;link.target='_blank';link.rel='noreferrer';link.textContent=options.attributionLabel;attr.appendChild(link);container.appendChild(attr);if(frame.tiles.length===0){bad();return}timeout=setTimeout(()=>loaded>0?ok():bad(),options.timeoutMs??DEFAULT_TIMEOUT_MS)};render(true);return{resize(){render(false)},destroy(){if(destroyed)return;destroyed=true;generation++;clear();container.replaceChildren()}}}
'''

SCHEMA = r'''export function sandboxSchoolDistrictPortfolioMapSchema(){
  const point={type:'object',properties:{type:{type:'string',enum:['Point']},coordinates:{type:'array',minItems:2,maxItems:2,items:{type:'number'}}},required:['type','coordinates'],additionalProperties:false}
  const member={type:'object',properties:{id:{type:'string',minLength:1,maxLength:40},name:{type:'string',minLength:1,maxLength:200},address:{type:'string',minLength:1,maxLength:240},city:{type:'string',minLength:1,maxLength:120},state_code:{type:'string',enum:['IN']},zip:{type:'string',minLength:1,maxLength:16},point,school_year:{type:'string',enum:['2024-2025']},observed_at:{type:'string',minLength:1,maxLength:80}},required:['id','name','address','city','state_code','zip','point','school_year','observed_at'],additionalProperties:false}
  const signal={type:'object',properties:{id:{type:'string',minLength:1,maxLength:120},kind:{type:'string',enum:['district_roof_capital_project']},project_title:{type:'string',enum:['Roof Project']},estimated_cost:{type:'number',minimum:1,maximum:1000000000},start_date_text:{type:'string',minLength:1,maxLength:120},end_date_text:{type:'string',minLength:1,maxLength:120},plan_year:{type:'integer',enum:[2027]},plan_id:{type:'string',enum:['10695']},plan_submitted_at:{type:'string',minLength:1,maxLength:80},extraction_confidence:{type:'string',enum:['high']},site_attribution:{type:'string',enum:['district_only_unresolved']},observed_at:{type:'string',minLength:1,maxLength:80}},required:['id','kind','project_title','estimated_cost','start_date_text','end_date_text','plan_year','plan_id','plan_submitted_at','extraction_confidence','site_attribution','observed_at'],additionalProperties:false}
  return {type:'object',properties:{contract_version:{type:'string',enum:['school_district_portfolio_map_v1']},opportunity_type:{type:'string',enum:['school_district_portfolio']},group_kind:{type:'string',enum:['portfolio']},account_name:{type:'string',enum:['Scott County School District 2']},district_key:{type:'string',enum:['IN-7255']},nces_district_id:{type:'string',enum:['1810020']},dlgf_unit_id:{type:'string',enum:['1288']},dlgf_unit_code:{type:'string',enum:['7255']},scope:{type:'string',enum:['documented_public_school_roster']},facility_source_slug:{type:'string',enum:['nces-edge-public-schools-2425']},signal_source_slug:{type:'string',enum:['indiana-dlgf-school-capital-projects']},relationship:{type:'string',enum:['district_membership']},target_kind:{type:'string',enum:['school_facility_member']},map_semantics:{type:'string',enum:['documented_public_school_facility_portfolio']},evidence_boundary:{type:'string',minLength:1,maxLength:1000},generated_at:{type:'string',minLength:1,maxLength:80},observed_at:{type:'string',minLength:1,maxLength:80},facility_observed_at:{type:'string',minLength:1,maxLength:80},capital_plan_observed_at:{type:'string',minLength:1,maxLength:80},member_count:{type:'integer',minimum:1,maximum:100},resolved_member_count:{type:'integer',minimum:1,maximum:100},bounds:{type:'object',properties:{west:{type:'number',minimum:-180,maximum:180},south:{type:'number',minimum:-90,maximum:90},east:{type:'number',minimum:-180,maximum:180},north:{type:'number',minimum:-90,maximum:90}},required:['west','south','east','north'],additionalProperties:false},members:{type:'array',minItems:1,maxItems:100,items:member},capital_signals:{type:'array',minItems:1,maxItems:20,items:signal},guardrail:{type:'string',minLength:1,maxLength:2000}},required:['contract_version','opportunity_type','group_kind','account_name','district_key','nces_district_id','dlgf_unit_id','dlgf_unit_code','scope','facility_source_slug','signal_source_slug','relationship','target_kind','map_semantics','evidence_boundary','generated_at','observed_at','facility_observed_at','capital_plan_observed_at','member_count','resolved_member_count','bounds','members','capital_signals','guardrail'],additionalProperties:false}
}
export function sandboxSchoolDistrictPortfolioOpportunitySchema(){return {type:'object',properties:{opportunity_type:{type:'string',enum:['school_district_portfolio']},name:{type:'string',enum:['Scott County School District 2']},district_key:{type:'string',enum:['IN-7255']},member_count:{type:'integer',minimum:1,maximum:100},observed_at:{type:'string',minLength:1,maxLength:80},school_year:{type:'string',enum:['2024-2025']},roof_project_estimated_cost:{type:'number',minimum:1,maximum:1000000000},roof_project_start_text:{type:'string',minLength:1,maxLength:120},roof_project_end_text:{type:'string',minLength:1,maxLength:120},roof_project_plan_year:{type:'integer',enum:[2027]},project_site_attribution:{type:'string',enum:['district_only_unresolved']},map_semantics:{type:'string',enum:['documented_public_school_facility_portfolio']},evidence_boundary:{type:'string',minLength:1,maxLength:1000},why_investigate:{type:'string',minLength:1,maxLength:1400},guardrail:{type:'string',minLength:1,maxLength:2000}},required:['opportunity_type','name','district_key','member_count','observed_at','school_year','roof_project_estimated_cost','roof_project_start_text','roof_project_end_text','roof_project_plan_year','project_site_attribution','map_semantics','evidence_boundary','why_investigate','guardrail'],additionalProperties:false}}
'''

VIEW_REGISTRY = r'''import type { ScoutSandboxPortfolioType } from '../_shared/scout_sandbox_manifest.ts'
import { mountScoutWaterUtilityPortfolioMap } from './water_portfolio_map_mount.ts'
import { mountScoutDealershipPortfolioMap } from './dealership_portfolio_map_mount.ts'
import { mountScoutHotelPortfolioMap } from './hotel_portfolio_map_mount.ts'
import { mountScoutSchoolDistrictPortfolioMap } from './school_district_portfolio_map_mount.ts'

type Presentation = { title:string; tier:string; meta:string; address:string; summary:string; guardrail:string; state:string }
function observed(value:string){const date=new Date(value);if(Number.isNaN(date.valueOf()))return value;return new Intl.DateTimeFormat('en-US',{year:'numeric',month:'short',day:'numeric',timeZone:'UTC'}).format(date)}
function number(value:number){return new Intl.NumberFormat('en-US',{maximumFractionDigits:0}).format(value)}
function money(value:number){return new Intl.NumberFormat('en-US',{style:'currency',currency:'USD',maximumFractionDigits:0}).format(value)}
export const SCOUT_SANDBOX_PORTFOLIO_VIEW_IMPLEMENTATIONS={
  water_utility_portfolio:{mount:mountScoutWaterUtilityPortfolioMap,presentation:(opportunity:any):Presentation=>({title:opportunity.name,tier:'Portfolio evidence',meta:`${number(opportunity.member_count)} documented tank records  •  Kentucky WRIS source modified ${observed(opportunity.source_modified_at)}`,address:`PWSID ${opportunity.pwsid}`,summary:`${number(opportunity.not_in_service_count)} documented not in service  •  ${number(opportunity.historical_project_signal_count)} historical rehab-linked records  •  ${opportunity.why_investigate}`,guardrail:`Scout guardrail: ${opportunity.guardrail}`,state:`Scout portfolio ready: ${opportunity.name}`})},
  dealership_group_portfolio:{mount:mountScoutDealershipPortfolioMap,presentation:(opportunity:any):Presentation=>{const route=opportunity.operations_route_available||opportunity.procurement_route_available?'Operations / procurement route available':opportunity.contact_route_available?'Contact route available; operations / procurement route unresolved':'Account route unresolved';return{title:opportunity.name,tier:'Portfolio evidence',meta:`${number(opportunity.member_count)} documented operating dealership sites  •  First-party roster observed ${observed(opportunity.observed_at)}`,address:'Kentucky pilot portfolio',summary:`${number(opportunity.resolved_member_count)} sites physically crosswalked  •  ${number(opportunity.resolved_building_count)} resolved buildings  •  ${number(opportunity.unresolved_member_count)} roster sites not mapped  •  ${route}  •  ${opportunity.why_investigate}`,guardrail:`Scout guardrail: ${opportunity.guardrail}`,state:`Scout portfolio ready: ${opportunity.name}`}}},
  hotel_management_portfolio:{mount:mountScoutHotelPortfolioMap,presentation:(opportunity:any):Presentation=>{const route=opportunity.operations_route_available&&opportunity.procurement_route_available?'Operations + procurement routes available':opportunity.contact_route_available?'Contact route available; account purchasing route incomplete':'Account route unresolved',vendor=opportunity.vendor_route_proven?'vendor route documented':'vendor route not yet proven';return{title:opportunity.name,tier:'Portfolio evidence',meta:`${number(opportunity.member_count)} documented operating hotels  •  First-party management roster observed ${observed(opportunity.observed_at)}`,address:'Kentucky pilot hotel portfolio',summary:`${number(opportunity.resolved_member_count)} hotels physically crosswalked  •  ${number(opportunity.resolved_building_count)} resolved buildings  •  ${number(opportunity.unresolved_member_count)} roster sites not mapped  •  ${route}; ${vendor}  •  ${opportunity.why_investigate}`,guardrail:`Scout guardrail: ${opportunity.guardrail}`,state:`Scout portfolio ready: ${opportunity.name}`}}},
  school_district_portfolio:{mount:mountScoutSchoolDistrictPortfolioMap,presentation:(opportunity:any):Presentation=>({title:opportunity.name,tier:'Portfolio evidence',meta:`${number(opportunity.member_count)} documented public schools  •  NCES ${opportunity.school_year} roster / DLGF capital-plan evidence`,address:'Scott County, Indiana  •  DLGF unit 7255',summary:`${money(opportunity.roof_project_estimated_cost)} district-level Roof Project  •  ${opportunity.roof_project_start_text}–${opportunity.roof_project_end_text}  •  No campus identified in source  •  ${opportunity.why_investigate}`,guardrail:`Scout guardrail: ${opportunity.guardrail}`,state:`Scout portfolio ready: ${opportunity.name}`})},
} as const satisfies Record<ScoutSandboxPortfolioType,{mount:any;presentation:(opportunity:any)=>Presentation}>
export function scoutSandboxPortfolioViewImplementation(type:ScoutSandboxPortfolioType){return SCOUT_SANDBOX_PORTFOLIO_VIEW_IMPLEMENTATIONS[type] as any}
export function assertScoutSandboxPortfolioViewImplementationCoverage(){return Object.keys(SCOUT_SANDBOX_PORTFOLIO_VIEW_IMPLEMENTATIONS).sort().join('|')}
'''

RENDERER_TEST = r'''import assert from 'node:assert/strict'
import { build } from 'esbuild'
import { makePortfolioPayload } from './sandbox_portfolio_test_fixtures.mjs'
const directory=new URL('./',import.meta.url)
async function bundle(path){const result=await build({entryPoints:[new URL(path,directory).pathname],bundle:true,format:'esm',platform:'node',target:'node22',write:false});return await import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`)}
const model=await bundle('school_district_portfolio_map_model.ts'),renderer=await bundle('school_district_portfolio_map_renderer.ts')
const map=model.normalizeScoutSandboxSchoolDistrictPortfolioMap(makePortfolioPayload('school_district_portfolio'))
assert.ok(map)
assert.equal(map.member_count,6)
assert.deepEqual(map.bounds,{west:-85.781081,south:38.6503,east:-85.6264,north:38.7373})
const frame=renderer.buildScoutSchoolDistrictPortfolioRasterFrame(map,456,210,{tileUrlTemplate:'https://sandbox.invalid/map-tile/{z}/{x}/{y}.png'})
assert.equal(frame.zoom,10)
assert.equal(frame.markers.length,6)
assert.deepEqual(frame.tiles.map((tile)=>`${tile.z}/${tile.x}/${tile.y}`),['10/267/392','10/268/392','10/269/392'])
assert.equal(map.capital_signals[0].site_attribution,'district_only_unresolved')
const opportunity=model.buildScoutSandboxSchoolDistrictPortfolioOpportunity(map)
assert.equal(opportunity.roof_project_estimated_cost,500000)
assert.equal(opportunity.project_site_attribution,'district_only_unresolved')
console.log('Scout school-district portfolio renderer checks passed.')
'''

MIGRATION = r'''create or replace function public.scout_get_component_sandbox_school_district_portfolio_v1_internal()
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog'
as $function$
with facilities as (
  select distinct on (r.raw_payload->>'nces_school_id')
    r.raw_payload->>'nces_school_id' as nces_school_id,
    r.raw_payload->>'school_name' as school_name,
    r.raw_payload->>'address_1' as address_1,
    r.raw_payload->>'city' as city,
    trim(r.raw_payload->>'state') as state_code,
    r.raw_payload->>'zip' as zip,
    (r.raw_payload->>'longitude')::double precision as lon,
    (r.raw_payload->>'latitude')::double precision as lat,
    r.raw_payload->>'school_year' as school_year,
    r.retrieved_at
  from ingest.raw_records r
  join ingest.sources s on s.id=r.source_id
  where s.slug='nces-edge-public-schools-2425'
    and r.provisional_entity_type='public_school_facility'
    and r.raw_payload->>'state_district_id'='IN-7255'
    and nullif(r.raw_payload->>'nces_school_id','') is not null
    and nullif(r.raw_payload->>'longitude','') is not null
    and nullif(r.raw_payload->>'latitude','') is not null
  order by r.raw_payload->>'nces_school_id',r.retrieved_at desc,r.id
), roof as (
  select
    r.raw_payload->>'project_title' as project_title,
    (r.raw_payload->>'estimated_cost')::numeric as estimated_cost,
    r.raw_payload->>'start_date_text' as start_date_text,
    r.raw_payload->>'end_date_text' as end_date_text,
    (r.raw_payload->>'plan_year')::integer as plan_year,
    r.raw_payload->>'plan_id' as plan_id,
    r.raw_payload->>'extraction_confidence' as extraction_confidence,
    to_char(to_timestamp(r.raw_payload->>'date_submitted','MM/DD/YYYY HH12:MI:SS AM') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"') as plan_submitted_at,
    r.retrieved_at
  from ingest.raw_records r
  join ingest.sources s on s.id=r.source_id
  where s.slug='indiana-dlgf-school-capital-projects'
    and r.provisional_entity_type='indiana_school_capital_project_candidate'
    and r.raw_payload->>'unit_code'='7255'
    and r.raw_payload->>'candidate_kind'='capital_project'
    and lower(trim(r.raw_payload->>'project_title'))='roof project'
  order by r.retrieved_at desc,r.id
  limit 1
)
select jsonb_build_object(
  'contract_version','school_district_portfolio_map_v1',
  'account_name','Scott County School District 2',
  'district_key','IN-7255',
  'nces_district_id','1810020',
  'dlgf_unit_id','1288',
  'dlgf_unit_code','7255',
  'scope','documented_public_school_roster',
  'facility_source_slug','nces-edge-public-schools-2425',
  'signal_source_slug','indiana-dlgf-school-capital-projects',
  'relationship','district_membership',
  'generated_at',statement_timestamp(),
  'facility_observed_at',max(f.retrieved_at),
  'capital_plan_observed_at',(select retrieved_at from roof),
  'members',jsonb_agg(jsonb_build_object('id',f.nces_school_id,'name',f.school_name,'address',f.address_1,'city',f.city,'state_code',f.state_code,'zip',f.zip,'point',jsonb_build_object('type','Point','coordinates',jsonb_build_array(f.lon,f.lat)),'school_year',f.school_year,'observed_at',f.retrieved_at) order by f.school_name,f.nces_school_id),
  'capital_signals',(select jsonb_build_array(jsonb_build_object('id','dlgf:10695:roof-project','kind','district_roof_capital_project','project_title',roof.project_title,'estimated_cost',roof.estimated_cost,'start_date_text',roof.start_date_text,'end_date_text',roof.end_date_text,'plan_year',roof.plan_year,'plan_id',roof.plan_id,'plan_submitted_at',roof.plan_submitted_at,'extraction_confidence',roof.extraction_confidence,'site_attribution','district_only_unresolved','observed_at',roof.retrieved_at)) from roof)
)
from facilities f
having count(*) between 1 and 100 and (select count(*) from roof)=1;
$function$;
revoke all on function public.scout_get_component_sandbox_school_district_portfolio_v1_internal() from public,anon,authenticated;
grant execute on function public.scout_get_component_sandbox_school_district_portfolio_v1_internal() to service_role;
'''

write('supabase/functions/scout-component-sandbox-mcp/school_district_portfolio_map_model.ts', MODEL)
write('supabase/functions/scout-component-sandbox-mcp/school_district_portfolio_map_renderer.ts', RENDERER)
write('supabase/functions/scout-component-sandbox-mcp/school_district_portfolio_map_mount.ts', MOUNT)
write('supabase/functions/scout-component-sandbox-mcp/school_district_portfolio_map_renderer_test.mjs', RENDERER_TEST)
write('supabase/functions/scout-component-sandbox-mcp/portfolio_view_registry.ts', VIEW_REGISTRY)
write('supabase/functions/_shared/scout_sandbox_school_district_portfolio_schema.ts', SCHEMA)
write('supabase/migrations/20260915190000_add_school_district_portfolio_sandbox.sql', MIGRATION)

manifest='supabase/functions/_shared/scout_sandbox_manifest.ts'
replace_once(manifest, 'export const SCOUT_SANDBOX_RESOURCE_VERSION = 35 as const', 'export const SCOUT_SANDBOX_RESOURCE_VERSION = 36 as const')
replace_once(manifest, "  'hotel_management_portfolio',\n] as const", "  'hotel_management_portfolio',\n  'school_district_portfolio',\n] as const")
replace_once(manifest, "  hotel_management_portfolio: {\n    slug: 'hotel_management_portfolio',", "  hotel_management_portfolio: {\n    slug: 'hotel_management_portfolio',")
anchor="  hotel_management_portfolio: {\n    slug: 'hotel_management_portfolio',\n    label: 'Commonwealth Hotels management portfolio',\n    mapKind: 'portfolio',\n    markerSemantics: 'resolved operating hotels with brand-family context; unresolved roster members are not mapped',\n    hostNormalization: 'unresolved_link_confidence_null_elision',\n    rasterFrames: [{ width: 456, height: 210 }, { width: 280, height: 210 }],\n    tileRanges: [{ z: 7, minX: 32, maxX: 34, minY: 48, maxY: 49 }],\n    tileCenters: [],\n    rpc: 'scout_get_component_sandbox_hotel_portfolio_v1_internal',\n    contractVersion: 'hotel_management_portfolio_map_v1',\n  },\n"
addition=anchor+"  school_district_portfolio: {\n    slug: 'school_district_portfolio',\n    label: 'Scott County School District 2 facilities portfolio',\n    mapKind: 'portfolio',\n    markerSemantics: 'documented NCES school facility points; district-level DLGF capital signals are not attributed to individual campuses',\n    hostNormalization: 'strict',\n    rasterFrames: [{ width: 456, height: 210 }, { width: 280, height: 210 }],\n    tileRanges: [{ z: 10, minX: 267, maxX: 269, minY: 392, maxY: 392 }],\n    tileCenters: [],\n    rpc: 'scout_get_component_sandbox_school_district_portfolio_v1_internal',\n    contractVersion: 'school_district_portfolio_map_v1',\n  },\n"
replace_once(manifest, anchor, addition)

registry='supabase/functions/scout-component-sandbox-mcp/portfolio_registry.ts'
replace_once(registry, "import { buildScoutHotelPortfolioRasterFrame } from './hotel_portfolio_map_renderer.ts'\n", "import { buildScoutHotelPortfolioRasterFrame } from './hotel_portfolio_map_renderer.ts'\nimport {\n  buildScoutSandboxSchoolDistrictPortfolioOpportunity,\n  normalizeScoutSandboxSchoolDistrictPortfolioMap,\n  normalizeScoutSandboxSchoolDistrictPortfolioOpportunity,\n} from './school_district_portfolio_map_model.ts'\nimport { buildScoutSchoolDistrictPortfolioRasterFrame } from './school_district_portfolio_map_renderer.ts'\n")
replace_once(registry, "  hotel_management_portfolio: {\n    normalizeMap: normalizeScoutSandboxHotelPortfolioMap,\n    normalizeOpportunity: normalizeScoutSandboxHotelPortfolioOpportunity,\n    buildOpportunity: buildScoutSandboxHotelPortfolioOpportunity,\n    buildRasterFrame: buildScoutHotelPortfolioRasterFrame,\n    identityMatches: (map: any, opportunity: any) => map.account_name === opportunity.name && map.member_count === opportunity.member_count && map.resolved_member_count === opportunity.resolved_member_count,\n    responseText: (opportunity: any) => `Scout returned the bounded ${opportunity.name} hotel-management portfolio card with ${opportunity.resolved_member_count} mapped sites from ${opportunity.member_count} documented operating hotels.`,\n    ariaLabel: (map: any) => `Documented hotel portfolio map for ${map.account_name}`,\n  },\n", "  hotel_management_portfolio: {\n    normalizeMap: normalizeScoutSandboxHotelPortfolioMap,\n    normalizeOpportunity: normalizeScoutSandboxHotelPortfolioOpportunity,\n    buildOpportunity: buildScoutSandboxHotelPortfolioOpportunity,\n    buildRasterFrame: buildScoutHotelPortfolioRasterFrame,\n    identityMatches: (map: any, opportunity: any) => map.account_name === opportunity.name && map.member_count === opportunity.member_count && map.resolved_member_count === opportunity.resolved_member_count,\n    responseText: (opportunity: any) => `Scout returned the bounded ${opportunity.name} hotel-management portfolio card with ${opportunity.resolved_member_count} mapped sites from ${opportunity.member_count} documented operating hotels.`,\n    ariaLabel: (map: any) => `Documented hotel portfolio map for ${map.account_name}`,\n  },\n  school_district_portfolio: {\n    normalizeMap: normalizeScoutSandboxSchoolDistrictPortfolioMap,\n    normalizeOpportunity: normalizeScoutSandboxSchoolDistrictPortfolioOpportunity,\n    buildOpportunity: buildScoutSandboxSchoolDistrictPortfolioOpportunity,\n    buildRasterFrame: buildScoutSchoolDistrictPortfolioRasterFrame,\n    identityMatches: (map: any, opportunity: any) => map.account_name === opportunity.name && map.district_key === opportunity.district_key && map.member_count === opportunity.member_count,\n    responseText: (opportunity: any) => `Scout returned the bounded ${opportunity.name} school-district portfolio card with ${opportunity.member_count} documented NCES school facilities and a district-level DLGF roof capital-plan signal.`,\n    ariaLabel: (map: any) => `Documented public-school facility portfolio map for ${map.account_name}`,\n  },\n")

shared='supabase/functions/_shared/scout_sandbox_contract_schema.ts'
replace_once(shared, "import { sandboxHotelPortfolioMapSchema, sandboxHotelPortfolioOpportunitySchema } from './scout_sandbox_hotel_portfolio_schema.ts'\n", "import { sandboxHotelPortfolioMapSchema, sandboxHotelPortfolioOpportunitySchema } from './scout_sandbox_hotel_portfolio_schema.ts'\nimport { sandboxSchoolDistrictPortfolioMapSchema, sandboxSchoolDistrictPortfolioOpportunitySchema } from './scout_sandbox_school_district_portfolio_schema.ts'\n")
replace_once(shared, "{type:'object',properties:{surface:{type:'string',enum:['scout_component_sandbox']},opportunity_type:{type:'string',enum:['hotel_management_portfolio']},opportunity:sandboxHotelPortfolioOpportunitySchema(),map:sandboxHotelPortfolioMapSchema()},required:['surface','opportunity_type','opportunity','map'],additionalProperties:false}]}}", "{type:'object',properties:{surface:{type:'string',enum:['scout_component_sandbox']},opportunity_type:{type:'string',enum:['hotel_management_portfolio']},opportunity:sandboxHotelPortfolioOpportunitySchema(),map:sandboxHotelPortfolioMapSchema()},required:['surface','opportunity_type','opportunity','map'],additionalProperties:false},{type:'object',properties:{surface:{type:'string',enum:['scout_component_sandbox']},opportunity_type:{type:'string',enum:['school_district_portfolio']},opportunity:sandboxSchoolDistrictPortfolioOpportunitySchema(),map:sandboxSchoolDistrictPortfolioMapSchema()},required:['surface','opportunity_type','opportunity','map'],additionalProperties:false}]}}")

fixture='supabase/functions/scout-component-sandbox-mcp/sandbox_portfolio_test_fixtures.mjs'
replace_once(fixture, "  const hotel = type === 'hotel_management_portfolio'\n", "  if (type === 'school_district_portfolio') {\n    return {\n      contract_version: 'school_district_portfolio_map_v1', account_name: 'Scott County School District 2', district_key: 'IN-7255', nces_district_id: '1810020', dlgf_unit_id: '1288', dlgf_unit_code: '7255', scope: 'documented_public_school_roster', facility_source_slug: 'nces-edge-public-schools-2425', signal_source_slug: 'indiana-dlgf-school-capital-projects', relationship: 'district_membership', generated_at: '2026-09-15T12:00:00Z', facility_observed_at: '2026-09-06T05:21:27.854428Z', capital_plan_observed_at: '2026-09-06T05:06:41.657508Z',\n      members: [\n        ['181002001609','Johnson Elementary School','4235 E SR 256','Scottsburg','47170',-85.6989,38.7373],\n        ['181002001610','Lexington Elementary School','7980 E Walnut St','Lexington','47138',-85.6264,38.6524],\n        ['181002001608','Scottsburg Elem School','49 N Hyland St','Scottsburg','47170',-85.7757,38.6866],\n        ['181002001611','Scottsburg Middle School','425 S 3rd St','Scottsburg','47170',-85.763562,38.680269],\n        ['181002001612','Scottsburg Senior High School','500 S Gardner','Scottsburg','47170',-85.781081,38.680638],\n        ['181002001614','Vienna-Finley Elementary School','445 Ivan Rogers Dr','Scottsburg','47170',-85.7661,38.6503],\n      ].map(([id,name,address,city,zip,lon,lat]) => ({ id,name,address,city,state_code:'IN',zip,point:{type:'Point',coordinates:[lon,lat]},school_year:'2024-2025',observed_at:'2026-09-06T05:21:27.854428Z' })),\n      capital_signals: [{ id:'dlgf:10695:roof-project',kind:'district_roof_capital_project',project_title:'Roof Project',estimated_cost:500000,start_date_text:'Summer of 2027',end_date_text:'Summer of 2029',plan_year:2027,plan_id:'10695',plan_submitted_at:'2026-08-12T08:28:01Z',extraction_confidence:'high',site_attribution:'district_only_unresolved',observed_at:'2026-09-06T05:06:41.657508Z' }],\n    }\n  }\n\n  const hotel = type === 'hotel_management_portfolio'\n")

package='supabase/functions/scout-component-sandbox-mcp/package.json'
replace_once(package, 'node hotel_portfolio_map_renderer_test.mjs && node sandbox_portfolio_contract_test.mjs', 'node hotel_portfolio_map_renderer_test.mjs && node school_district_portfolio_map_renderer_test.mjs && node sandbox_portfolio_contract_test.mjs')

smoke='supabase/functions/scout-component-sandbox-mcp/sandbox_predeploy_smoke_test.mjs'
replace_once(smoke, "  hotel_management_portfolio: 'hotel_portfolio_map_renderer_test.mjs',\n", "  hotel_management_portfolio: 'hotel_portfolio_map_renderer_test.mjs',\n  school_district_portfolio: 'school_district_portfolio_map_renderer_test.mjs',\n")

registry_test='supabase/functions/scout-component-sandbox-mcp/sandbox_registry_contract_test.mjs'
replace_once(registry_test, "const [component, contractGateway, connectGateway, view] = await Promise.all([", "const [component, contractGateway, connectGateway, view, viewRegistry] = await Promise.all([")
replace_once(registry_test, "  readFile(new URL('view.ts', directory), 'utf8'),\n])", "  readFile(new URL('view.ts', directory), 'utf8'),\n  readFile(new URL('portfolio_view_registry.ts', directory), 'utf8'),\n])")
replace_once(registry_test, "assert.ok(view.includes('isScoutSandboxPortfolioType'))\n", "assert.ok(view.includes('isScoutSandboxPortfolioType'))\nassert.ok(view.includes('scoutSandboxPortfolioViewImplementation'))\nfor (const type of manifest.SCOUT_SANDBOX_PORTFOLIO_TYPES) assert.ok(viewRegistry.includes(`${type}:`), `view registry missing ${type}`)\n")

view='supabase/functions/scout-component-sandbox-mcp/view.ts'
replace_once(view, "import { scoutSandboxPortfolioImplementation } from './portfolio_registry.ts'\n", "import { scoutSandboxPortfolioImplementation } from './portfolio_registry.ts'\nimport { scoutSandboxPortfolioViewImplementation } from './portfolio_view_registry.ts'\n")
for line in ["import { mountScoutWaterUtilityPortfolioMap } from './water_portfolio_map_mount.ts'\n","import { mountScoutDealershipPortfolioMap } from './dealership_portfolio_map_mount.ts'\n","import { mountScoutHotelPortfolioMap } from './hotel_portfolio_map_mount.ts'\n"]:
    replace_once(view,line,'')
replace_once(view, "const SCOUT_SANDBOX_PORTFOLIO_MOUNTS = {\n  water_utility_portfolio: mountScoutWaterUtilityPortfolioMap,\n  dealership_group_portfolio: mountScoutDealershipPortfolioMap,\n  hotel_management_portfolio: mountScoutHotelPortfolioMap,\n} as const\n\n", '')
vp=ROOT/view
text=vp.read_text(encoding='utf-8')
start=text.index('function renderOpportunity(opportunityType: ScoutViewOpportunityType, value: unknown) {')
portfolio_end=text.index("  if (opportunityType === 'swppp_site') {",start)
prefix=text[:start]
suffix=text[portfolio_end:]
generic="""function renderOpportunity(opportunityType: ScoutViewOpportunityType, value: unknown) {\n  if (isScoutSandboxPortfolioType(opportunityType)) {\n    const implementation = scoutSandboxPortfolioImplementation(opportunityType)\n    const opportunity = implementation.normalizeOpportunity(value)\n    if (!opportunity) { renderUnavailableOpportunity(); return }\n    const presentation = scoutSandboxPortfolioViewImplementation(opportunityType).presentation(opportunity)\n    if (title) title.textContent = presentation.title\n    if (tier) tier.textContent = presentation.tier\n    if (meta) meta.textContent = presentation.meta\n    if (address) address.textContent = presentation.address\n    if (summary) summary.textContent = presentation.summary\n    if (guardrail) guardrail.textContent = presentation.guardrail\n    setState(presentation.state)\n    return\n  }\n\n"""
vp.write_text(prefix+generic+suffix,encoding='utf-8')
replace_once(view, "      const mount = SCOUT_SANDBOX_PORTFOLIO_MOUNTS[opportunityType] as any\n", "      const mount = scoutSandboxPortfolioViewImplementation(opportunityType).mount as any\n")
replace_once(view, "const app = new App({ name: 'scout-ui-foundation', version: '2.15.0' })", "const app = new App({ name: 'scout-ui-foundation', version: '2.16.0' })")

index='supabase/functions/scout-component-sandbox-mcp/index.ts'
school_zod=r'''const schoolDistrictPortfolioMemberSchema=z.object({id:z.string().min(1).max(40),name:z.string().min(1).max(200),address:z.string().min(1).max(240),city:z.string().min(1).max(120),state_code:z.literal('IN'),zip:z.string().min(1).max(16),point:z.object({type:z.literal('Point'),coordinates:z.tuple([z.number().min(-180).max(180),z.number().min(-90).max(90)])}),school_year:z.literal('2024-2025'),observed_at:z.string().min(1).max(80)})
const schoolDistrictCapitalSignalSchema=z.object({id:z.string().min(1).max(120),kind:z.literal('district_roof_capital_project'),project_title:z.literal('Roof Project'),estimated_cost:z.number().min(1).max(1_000_000_000),start_date_text:z.string().min(1).max(120),end_date_text:z.string().min(1).max(120),plan_year:z.literal(2027),plan_id:z.literal('10695'),plan_submitted_at:z.string().min(1).max(80),extraction_confidence:z.literal('high'),site_attribution:z.literal('district_only_unresolved'),observed_at:z.string().min(1).max(80)})
const schoolDistrictPortfolioMapSchema=z.object({contract_version:z.literal('school_district_portfolio_map_v1'),opportunity_type:z.literal('school_district_portfolio'),group_kind:z.literal('portfolio'),account_name:z.literal('Scott County School District 2'),district_key:z.literal('IN-7255'),nces_district_id:z.literal('1810020'),dlgf_unit_id:z.literal('1288'),dlgf_unit_code:z.literal('7255'),scope:z.literal('documented_public_school_roster'),facility_source_slug:z.literal('nces-edge-public-schools-2425'),signal_source_slug:z.literal('indiana-dlgf-school-capital-projects'),relationship:z.literal('district_membership'),target_kind:z.literal('school_facility_member'),map_semantics:z.literal('documented_public_school_facility_portfolio'),evidence_boundary:z.string().min(1).max(1000),generated_at:z.string().min(1).max(80),observed_at:z.string().min(1).max(80),facility_observed_at:z.string().min(1).max(80),capital_plan_observed_at:z.string().min(1).max(80),member_count:z.number().int().min(1).max(100),resolved_member_count:z.number().int().min(1).max(100),bounds:z.object({west:z.number().min(-180).max(180),south:z.number().min(-90).max(90),east:z.number().min(-180).max(180),north:z.number().min(-90).max(90)}),members:z.array(schoolDistrictPortfolioMemberSchema).min(1).max(100),capital_signals:z.array(schoolDistrictCapitalSignalSchema).min(1).max(20),guardrail:z.string().min(1).max(2000)})
const schoolDistrictPortfolioOpportunitySchema=z.object({opportunity_type:z.literal('school_district_portfolio'),name:z.literal('Scott County School District 2'),district_key:z.literal('IN-7255'),member_count:z.number().int().min(1).max(100),observed_at:z.string().min(1).max(80),school_year:z.literal('2024-2025'),roof_project_estimated_cost:z.number().min(1).max(1_000_000_000),roof_project_start_text:z.string().min(1).max(120),roof_project_end_text:z.string().min(1).max(120),roof_project_plan_year:z.literal(2027),project_site_attribution:z.literal('district_only_unresolved'),map_semantics:z.literal('documented_public_school_facility_portfolio'),evidence_boundary:z.string().min(1).max(1000),why_investigate:z.string().min(1).max(1400),guardrail:z.string().min(1).max(2000)})
const schoolDistrictPortfolioResultSchema=z.object({surface:z.literal('scout_component_sandbox'),opportunity_type:z.literal('school_district_portfolio'),opportunity:schoolDistrictPortfolioOpportunitySchema,map:schoolDistrictPortfolioMapSchema})

'''
replace_once(index, 'const componentResultSchemaByType = {\n', school_zod+'const componentResultSchemaByType = {\n')
replace_once(index, "  hotel_management_portfolio: hotelPortfolioResultSchema,\n", "  hotel_management_portfolio: hotelPortfolioResultSchema,\n  school_district_portfolio: schoolDistrictPortfolioResultSchema,\n")
replace_once(index, "const server = new McpServer({ name: 'Scout UI Foundation', version: '2.3.5' })", "const server = new McpServer({ name: 'Scout UI Foundation', version: '2.3.6' })")

print('school district portfolio bootstrap complete')
