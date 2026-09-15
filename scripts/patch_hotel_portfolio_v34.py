from pathlib import Path
import json

ROOT=Path('.')
COMP=ROOT/'supabase/functions/scout-component-sandbox-mcp'
SHARED=ROOT/'supabase/functions/_shared'
MIG=ROOT/'supabase/migrations'

schema = r'''export function sandboxHotelPortfolioMapSchema(){
  const point={oneOf:[{type:'object',properties:{type:{type:'string',enum:['Point']},coordinates:{type:'array',minItems:2,maxItems:2,items:{type:'number'}}},required:['type','coordinates'],additionalProperties:false},{type:'object',properties:{type:{type:'string',enum:['unresolved']}},required:['type'],additionalProperties:false}]}
  const member={type:'object',properties:{id:{type:'string',minLength:1,maxLength:80},name:{type:'string',minLength:1,maxLength:200},address:{type:'string',minLength:1,maxLength:240},city:{type:'string',minLength:1,maxLength:120},state_code:{type:'string',minLength:1,maxLength:8},brands:{type:'array',maxItems:16,items:{type:'string',minLength:1,maxLength:80}},point,resolution_state:{type:'string',enum:['single_building_resolved','multi_building_resolved','unresolved']},resolved_building_count:{type:'integer',minimum:0,maximum:20},link_confidence:{type:['number','null'],minimum:0,maximum:1},within_pilot_radius:{type:'boolean'},observed_at:{type:'string',minLength:1,maxLength:80}},required:['id','name','address','city','state_code','brands','point','resolution_state','resolved_building_count','link_confidence','within_pilot_radius','observed_at'],additionalProperties:false}
  return {type:'object',properties:{contract_version:{type:'string',enum:['hotel_management_portfolio_map_v1']},opportunity_type:{type:'string',enum:['hotel_management_portfolio']},group_kind:{type:'string',enum:['portfolio']},account_name:{type:'string',minLength:1,maxLength:200},organization_id:{type:'string',pattern:'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'},scope:{type:'string',enum:['documented_operating_roster']},source_slug:{type:'string',enum:['commonwealth-hotels-managed-portfolio']},relationship:{type:'string',enum:['manages']},target_kind:{type:'string',enum:['site_member']},map_semantics:{type:'string',enum:['documented_operating_hotel_portfolio']},evidence_boundary:{type:'string',enum:['first-party hotel-management roster plus resolved building crosswalks']},generated_at:{type:'string',minLength:1,maxLength:80},observed_at:{type:'string',minLength:1,maxLength:80},member_count:{type:'integer',minimum:1,maximum:100},resolved_member_count:{type:'integer',minimum:1,maximum:100},resolved_building_count:{type:'integer',minimum:1,maximum:200},contact_route_available:{type:'boolean'},operations_route_available:{type:'boolean'},procurement_route_available:{type:'boolean'},vendor_route_proven:{type:'boolean'},current_need_scan_complete:{type:'boolean'},bounds:{type:'object',properties:{west:{type:'number',minimum:-180,maximum:180},south:{type:'number',minimum:-90,maximum:90},east:{type:'number',minimum:-180,maximum:180},north:{type:'number',minimum:-90,maximum:90}},required:['west','south','east','north'],additionalProperties:false},members:{type:'array',minItems:1,maxItems:100,items:member},guardrail:{type:'string',minLength:1,maxLength:1600}},required:['contract_version','opportunity_type','group_kind','account_name','organization_id','scope','source_slug','relationship','target_kind','map_semantics','evidence_boundary','generated_at','observed_at','member_count','resolved_member_count','resolved_building_count','contact_route_available','operations_route_available','procurement_route_available','vendor_route_proven','current_need_scan_complete','bounds','members','guardrail'],additionalProperties:false}
}

export function sandboxHotelPortfolioOpportunitySchema(){return {type:'object',properties:{opportunity_type:{type:'string',enum:['hotel_management_portfolio']},name:{type:'string',minLength:1,maxLength:200},member_count:{type:'integer',minimum:1,maximum:100},resolved_member_count:{type:'integer',minimum:1,maximum:100},resolved_building_count:{type:'integer',minimum:1,maximum:200},unresolved_member_count:{type:'integer',minimum:0,maximum:100},observed_at:{type:'string',minLength:1,maxLength:80},contact_route_available:{type:'boolean'},operations_route_available:{type:'boolean'},procurement_route_available:{type:'boolean'},vendor_route_proven:{type:'boolean'},current_need_scan_complete:{type:'boolean'},map_semantics:{type:'string',enum:['documented_operating_hotel_portfolio']},evidence_boundary:{type:'string',enum:['first-party hotel-management roster plus resolved building crosswalks']},why_investigate:{type:'string',minLength:1,maxLength:1000},guardrail:{type:'string',minLength:1,maxLength:1600}},required:['opportunity_type','name','member_count','resolved_member_count','resolved_building_count','unresolved_member_count','observed_at','contact_route_available','operations_route_available','procurement_route_available','vendor_route_proven','current_need_scan_complete','map_semantics','evidence_boundary','why_investigate','guardrail'],additionalProperties:false}}
'''
(SHARED/'scout_sandbox_hotel_portfolio_schema.ts').write_text(schema)

model = r'''export type ScoutHotelPortfolioPoint =
  | { type: 'Point'; coordinates: [number, number] }
  | { type: 'unresolved' }

export type ScoutHotelPortfolioResolutionState = 'single_building_resolved' | 'multi_building_resolved' | 'unresolved'

export type ScoutHotelPortfolioMember = {
  id: string
  name: string
  address: string
  city: string
  state_code: string
  brands: string[]
  point: ScoutHotelPortfolioPoint
  resolution_state: ScoutHotelPortfolioResolutionState
  resolved_building_count: number
  link_confidence: number | null
  within_pilot_radius: boolean
  observed_at: string
}

export type ScoutSandboxHotelPortfolioMap = {
  contract_version: 'hotel_management_portfolio_map_v1'
  opportunity_type: 'hotel_management_portfolio'
  group_kind: 'portfolio'
  account_name: string
  organization_id: string
  scope: 'documented_operating_roster'
  source_slug: 'commonwealth-hotels-managed-portfolio'
  relationship: 'manages'
  target_kind: 'site_member'
  map_semantics: 'documented_operating_hotel_portfolio'
  evidence_boundary: 'first-party hotel-management roster plus resolved building crosswalks'
  generated_at: string
  observed_at: string
  member_count: number
  resolved_member_count: number
  resolved_building_count: number
  contact_route_available: boolean
  operations_route_available: boolean
  procurement_route_available: boolean
  vendor_route_proven: boolean
  current_need_scan_complete: boolean
  bounds: { west: number; south: number; east: number; north: number }
  members: ScoutHotelPortfolioMember[]
  guardrail: string
}

export type ScoutSandboxHotelPortfolioOpportunity = {
  opportunity_type: 'hotel_management_portfolio'
  name: string
  member_count: number
  resolved_member_count: number
  resolved_building_count: number
  unresolved_member_count: number
  observed_at: string
  contact_route_available: boolean
  operations_route_available: boolean
  procurement_route_available: boolean
  vendor_route_proven: boolean
  current_need_scan_complete: boolean
  map_semantics: 'documented_operating_hotel_portfolio'
  evidence_boundary: 'first-party hotel-management roster plus resolved building crosswalks'
  why_investigate: string
  guardrail: string
}

const HOTEL_PORTFOLIO_GUARDRAIL = 'This is a documented operating hotel-management roster and building-resolution context, not proof of current exterior-cleaning need, legal ownership, or approved vendor status. Resolved site points are derived from matched building records; unresolved roster members are not mapped. Confirm current exterior condition, site access, vendor onboarding, and purchasing authority before outreach.'

function cleanString(value: unknown, maxLength = 1000) { if (typeof value !== 'string') return null; const text=value.trim(); return text.length>0&&text.length<=maxLength?text:null }
function cleanBoolean(value: unknown) { return typeof value === 'boolean' ? value : null }
function cleanInteger(value: unknown, minimum: number, maximum: number) { return typeof value==='number'&&Number.isInteger(value)&&value>=minimum&&value<=maximum?value:null }
function cleanNumber(value: unknown, minimum: number, maximum: number) { return typeof value==='number'&&Number.isFinite(value)&&value>=minimum&&value<=maximum?value:null }
function normalizeTimestamp(value: unknown) { const text=cleanString(value,80); if(!text)return null; const date=new Date(text); return Number.isNaN(date.valueOf())?null:date.toISOString() }
function normalizePoint(value: unknown): ScoutHotelPortfolioPoint | null { if(!value||typeof value!=='object'||Array.isArray(value))return null; const p=value as Record<string,unknown>; if(p.type==='unresolved')return {type:'unresolved'}; if(p.type!=='Point'||!Array.isArray(p.coordinates)||p.coordinates.length!==2)return null; const lon=cleanNumber(p.coordinates[0],-180,180),lat=cleanNumber(p.coordinates[1],-90,90); return lon===null||lat===null?null:{type:'Point',coordinates:[lon,lat]} }
function normalizeBrands(value: unknown) { if(!Array.isArray(value)||value.length>16)return null; const out:string[]=[]; for(const item of value){const x=cleanString(item,80); if(!x)return null; out.push(x)} return out }
function normalizeResolutionState(value: unknown): ScoutHotelPortfolioResolutionState | null { return value==='single_building_resolved'||value==='multi_building_resolved'||value==='unresolved'?value:null }

function normalizeMember(value: unknown): ScoutHotelPortfolioMember | null {
  if(!value||typeof value!=='object'||Array.isArray(value))return null
  const s=value as Record<string,unknown>
  const id=cleanString(s.id,80),name=cleanString(s.name,200),address=cleanString(s.address,240),city=cleanString(s.city,120),stateCode=cleanString(s.state_code,8)
  const brands=normalizeBrands(s.brands),point=normalizePoint(s.point),resolutionState=normalizeResolutionState(s.resolution_state),count=cleanInteger(s.resolved_building_count,0,20)
  const confidenceValue=s.link_confidence
  const confidence=confidenceValue==null?null:cleanNumber(confidenceValue,0,1)
  const inPilot=cleanBoolean(s.within_pilot_radius),observedAt=normalizeTimestamp(s.observed_at)
  if(!id||!name||!address||!city||!stateCode||!brands||!point||!resolutionState||count===null||inPilot===null||!observedAt)return null
  if(confidenceValue!=null&&confidence===null)return null
  if(resolutionState==='unresolved'&&(point.type!=='unresolved'||count!==0||confidence!==null))return null
  if(resolutionState==='single_building_resolved'&&(point.type!=='Point'||count!==1||confidence===null))return null
  if(resolutionState==='multi_building_resolved'&&(point.type!=='Point'||count<2||confidence===null))return null
  return {id,name,address,city,state_code:stateCode.toUpperCase(),brands,point,resolution_state:resolutionState,resolved_building_count:count,link_confidence:confidence,within_pilot_radius:inPilot,observed_at:observedAt}
}
function latestTimestamp(values:string[]){let latest:{value:string,time:number}|null=null;for(const value of values){const time=new Date(value).valueOf();if(Number.isFinite(time)&&(!latest||time>latest.time))latest={value,time}}return latest?.value??null}

export function normalizeScoutSandboxHotelPortfolioMap(value: unknown): ScoutSandboxHotelPortfolioMap | null {
  if(!value||typeof value!=='object'||Array.isArray(value))return null
  const s=value as Record<string,unknown>
  if(s.contract_version!=='hotel_management_portfolio_map_v1')return null
  const accountName=cleanString(s.account_name,200),organizationId=cleanString(s.organization_id,80),generatedAt=normalizeTimestamp(s.generated_at)
  if(!accountName||!organizationId||!generatedAt)return null
  if(s.scope!=='documented_operating_roster'||s.source_slug!=='commonwealth-hotels-managed-portfolio'||s.relationship!=='manages')return null
  if(s.target_kind!=='site_member'||s.map_semantics!=='documented_operating_hotel_portfolio'||s.evidence_boundary!=='first-party hotel-management roster plus resolved building crosswalks')return null
  const contact=cleanBoolean(s.contact_route_available),operations=cleanBoolean(s.operations_route_available),procurement=cleanBoolean(s.procurement_route_available),vendor=cleanBoolean(s.vendor_route_proven),need=cleanBoolean(s.current_need_scan_complete)
  if(contact===null||operations===null||procurement===null||vendor===null||need===null||!Array.isArray(s.members)||s.members.length<1||s.members.length>100)return null
  const members:ScoutHotelPortfolioMember[]=[]; for(const item of s.members){const m=normalizeMember(item); if(!m)return null; members.push(m)}
  const resolved=members.filter((m):m is ScoutHotelPortfolioMember & {point:{type:'Point';coordinates:[number,number]}}=>m.point.type==='Point')
  if(resolved.length<1)return null
  const observedAt=latestTimestamp(members.map(m=>m.observed_at)); if(!observedAt)return null
  const lons=resolved.map(m=>m.point.coordinates[0]),lats=resolved.map(m=>m.point.coordinates[1])
  return {contract_version:'hotel_management_portfolio_map_v1',opportunity_type:'hotel_management_portfolio',group_kind:'portfolio',account_name:accountName,organization_id:organizationId,scope:'documented_operating_roster',source_slug:'commonwealth-hotels-managed-portfolio',relationship:'manages',target_kind:'site_member',map_semantics:'documented_operating_hotel_portfolio',evidence_boundary:'first-party hotel-management roster plus resolved building crosswalks',generated_at:generatedAt,observed_at:observedAt,member_count:members.length,resolved_member_count:resolved.length,resolved_building_count:resolved.reduce((n,m)=>n+m.resolved_building_count,0),contact_route_available:contact,operations_route_available:operations,procurement_route_available:procurement,vendor_route_proven:vendor,current_need_scan_complete:need,bounds:{west:Math.min(...lons),south:Math.min(...lats),east:Math.max(...lons),north:Math.max(...lats)},members,guardrail:HOTEL_PORTFOLIO_GUARDRAIL}
}

export function buildScoutSandboxHotelPortfolioOpportunity(map:ScoutSandboxHotelPortfolioMap):ScoutSandboxHotelPortfolioOpportunity{return {opportunity_type:'hotel_management_portfolio',name:map.account_name,member_count:map.member_count,resolved_member_count:map.resolved_member_count,resolved_building_count:map.resolved_building_count,unresolved_member_count:map.member_count-map.resolved_member_count,observed_at:map.observed_at,contact_route_available:map.contact_route_available,operations_route_available:map.operations_route_available,procurement_route_available:map.procurement_route_available,vendor_route_proven:map.vendor_route_proven,current_need_scan_complete:map.current_need_scan_complete,map_semantics:'documented_operating_hotel_portfolio',evidence_boundary:'first-party hotel-management roster plus resolved building crosswalks',why_investigate:'Treat the account as a portfolio-level exterior-services verification target. Documented operations, procurement, and contact routes support account-level qualification; verify vendor onboarding and current exterior need before prioritizing resolved hotels.',guardrail:map.guardrail}}

export function normalizeScoutSandboxHotelPortfolioOpportunity(value:unknown):ScoutSandboxHotelPortfolioOpportunity|null{
  if(!value||typeof value!=='object'||Array.isArray(value))return null; const s=value as Record<string,unknown>
  const name=cleanString(s.name,200),members=cleanInteger(s.member_count,1,100),resolved=cleanInteger(s.resolved_member_count,1,100),buildings=cleanInteger(s.resolved_building_count,1,200),unresolved=cleanInteger(s.unresolved_member_count,0,100),observed=normalizeTimestamp(s.observed_at)
  const contact=cleanBoolean(s.contact_route_available),operations=cleanBoolean(s.operations_route_available),procurement=cleanBoolean(s.procurement_route_available),vendor=cleanBoolean(s.vendor_route_proven),need=cleanBoolean(s.current_need_scan_complete),why=cleanString(s.why_investigate,1000),guardrail=cleanString(s.guardrail,1600)
  if(s.opportunity_type!=='hotel_management_portfolio'||!name||members===null||resolved===null||buildings===null||unresolved===null||!observed||contact===null||operations===null||procurement===null||vendor===null||need===null||!why||!guardrail)return null
  if(resolved>members||unresolved!==members-resolved||buildings<resolved||s.map_semantics!=='documented_operating_hotel_portfolio'||s.evidence_boundary!=='first-party hotel-management roster plus resolved building crosswalks')return null
  return {opportunity_type:'hotel_management_portfolio',name,member_count:members,resolved_member_count:resolved,resolved_building_count:buildings,unresolved_member_count:unresolved,observed_at:observed,contact_route_available:contact,operations_route_available:operations,procurement_route_available:procurement,vendor_route_proven:vendor,current_need_scan_complete:need,map_semantics:'documented_operating_hotel_portfolio',evidence_boundary:'first-party hotel-management roster plus resolved building crosswalks',why_investigate:why,guardrail}
}
'''
(COMP/'hotel_portfolio_map_model.ts').write_text(model)

renderer = (COMP/'dealership_portfolio_map_renderer.ts').read_text()
renderer = renderer.replace("import type { ScoutDealershipPortfolioResolutionState, ScoutSandboxDealershipPortfolioMap } from './dealership_portfolio_map_model.ts'", "import type { ScoutHotelPortfolioResolutionState, ScoutSandboxHotelPortfolioMap } from './hotel_portfolio_map_model.ts'")
renderer = renderer.replace('ScoutDealershipPortfolio', 'ScoutHotelPortfolio').replace('ScoutSandboxDealershipPortfolioMap','ScoutSandboxHotelPortfolioMap')
(COMP/'hotel_portfolio_map_renderer.ts').write_text(renderer)

mount = r'''import type { ScoutSandboxHotelPortfolioMap } from './hotel_portfolio_map_model.ts'
import { buildScoutHotelPortfolioRasterFrame, type ScoutHotelPortfolioRasterFrameOptions } from './hotel_portfolio_map_renderer.ts'
const DEFAULT_TIMEOUT_MS=7000
const PNG_DATA_URL_PREFIX='data:image/png;base64,'
const FAMILY={marriott:{label:'Marriott family',color:'#3769b2'},hilton:{label:'Hilton family',color:'#3f7f78'},ihg:{label:'IHG family',color:'#b96a2d'},other:{label:'Other',color:'#7656a8'}} as const
type Family=keyof typeof FAMILY
function brandFamily(brands:string[]):Family{const text=brands.join(' ').toLowerCase();if(/marriott|courtyard|residence inn|springhill|fairfield|westin|sheraton/.test(text))return'marriott';if(/hilton|hampton|tru|homewood|embassy/.test(text))return'hilton';if(/holiday inn|ihg|crowne plaza/.test(text))return'ihg';return'other'}
async function decodeEmbeddedRasterTile(dataUrl:string){if(!dataUrl.startsWith(PNG_DATA_URL_PREFIX))throw new Error('Scout embedded raster tile is invalid');const binary=atob(dataUrl.slice(PNG_DATA_URL_PREFIX.length)),bytes=new Uint8Array(binary.length);for(let i=0;i<binary.length;i++)bytes[i]=binary.charCodeAt(i);return await createImageBitmap(new Blob([bytes],{type:'image/png'}))}
export type ScoutHotelPortfolioMapMountOptions=ScoutHotelPortfolioRasterFrameOptions&{attributionLabel:string;attributionUrl:string;timeoutMs?:number;embeddedTiles?:Record<string,string>;onError?:(error:Error)=>void;onReady?:()=>void}
export function mountScoutHotelPortfolioMap(container:HTMLElement,data:ScoutSandboxHotelPortfolioMap,options:ScoutHotelPortfolioMapMountOptions){let destroyed=false,generation=0,timeout:ReturnType<typeof setTimeout>|null=null,lastW=-1,lastH=-1;const clear=()=>{if(timeout!==null){clearTimeout(timeout);timeout=null}};const render=(force=false)=>{if(destroyed)return;const frame=buildScoutHotelPortfolioRasterFrame(data,container.clientWidth,container.clientHeight,options);if(!force&&frame.width===lastW&&frame.height===lastH)return;lastW=frame.width;lastH=frame.height;clear();generation++;const g=generation;container.replaceChildren();let loaded=0,settled=0,ready=false;const ok=()=>{if(destroyed||g!==generation||ready)return;ready=true;clear();options.onReady?.()};const bad=()=>{if(destroyed||g!==generation||ready)return;clear();options.onError?.(new Error('Scout raster tiles did not load'))};const embedded=frame.tiles.length>0&&frame.tiles.every(t=>options.embeddedTiles?.[t.url]);if(embedded){const canvas=document.createElement('canvas');canvas.width=frame.width;canvas.height=frame.height;canvas.style.position='absolute';canvas.style.inset='0';canvas.style.width=`${frame.width}px`;canvas.style.height=`${frame.height}px`;container.appendChild(canvas);const ctx=canvas.getContext('2d');if(!ctx){bad();return}void Promise.allSettled(frame.tiles.map(async t=>{const bitmap=await decodeEmbeddedRasterTile(options.embeddedTiles![t.url]);if(!destroyed&&g===generation){ctx.drawImage(bitmap,t.left,t.top,256,256);loaded++}bitmap.close()})).then(()=>{settled=frame.tiles.length;loaded>0?ok():bad()})}else{for(const t of frame.tiles){const image=document.createElement('img');image.alt='';image.draggable=false;image.decoding='async';image.loading='eager';image.referrerPolicy='origin';image.src=t.url;image.style.left=`${t.left}px`;image.style.top=`${t.top}px`;image.addEventListener('load',()=>{if(destroyed||g!==generation)return;loaded++;settled++;if(loaded===1)ok()},{once:true});image.addEventListener('error',()=>{if(destroyed||g!==generation)return;settled++;if(settled===frame.tiles.length&&loaded===0)bad()},{once:true});container.appendChild(image)}}
const families=new Set<Family>();for(const m of frame.markers){const family=brandFamily(m.brands);families.add(family);const info=FAMILY[family],marker=document.createElement('span');marker.className='scout-portfolio-marker';marker.style.left=`${m.left}px`;marker.style.top=`${m.top}px`;marker.style.setProperty('--scout-portfolio-marker-color',info.color);marker.style.backgroundColor=info.color;marker.title=`${m.name} · ${m.brands.join(' / ')} · resolved building`;marker.setAttribute('aria-hidden','true');container.appendChild(marker)}
const legend=document.createElement('span');legend.className='scout-portfolio-legend';legend.setAttribute('aria-hidden','true');for(const key of ['marriott','hilton','ihg','other'] as Family[]){if(!families.has(key))continue;const info=FAMILY[key],item=document.createElement('span');item.className='scout-portfolio-legend-item';const swatch=document.createElement('span');swatch.className='scout-portfolio-legend-swatch';swatch.style.backgroundColor=info.color;const text=document.createElement('span');text.textContent=info.label;item.append(swatch,text);legend.appendChild(item)}const unresolved=data.member_count-data.resolved_member_count;if(unresolved>0){const status=document.createElement('span');status.className='scout-portfolio-legend-status';status.textContent=`${unresolved} roster site${unresolved===1?'':'s'} unresolved · not mapped`;legend.appendChild(status)}container.appendChild(legend)
const attr=document.createElement('span');attr.className='scout-map-attribution';const link=document.createElement('a');link.href=options.attributionUrl;link.target='_blank';link.rel='noreferrer';link.textContent=options.attributionLabel;attr.appendChild(link);container.appendChild(attr);if(frame.tiles.length===0){bad();return}timeout=setTimeout(()=>loaded>0?ok():bad(),options.timeoutMs??DEFAULT_TIMEOUT_MS)};render(true);return{resize(){render(false)},destroy(){if(destroyed)return;destroyed=true;generation++;clear();container.replaceChildren()}}}
'''
(COMP/'hotel_portfolio_map_mount.ts').write_text(mount)

migration = r'''-- Add the bounded Commonwealth Hotels management-portfolio sandbox projection.
-- The roster is first-party management evidence; map points come only from resolved building crosswalks.
create or replace function public.scout_get_component_sandbox_hotel_portfolio_v1_internal()
returns jsonb language sql stable security definer set search_path='pg_catalog'
as $function$
with org as (
  select s.organization_id,s.account_name
  from scout.v_portfolio_account_summary s
  where s.account_name='Commonwealth Hotels' and s.organization_type='hotel_management_company' and s.portfolio_archetype='hotel_management'
  limit 1
), facilities as (
  select f.organization_facility_id,f.organization_id,f.account_name,f.source_record_id,f.site_name,f.site_address_text,f.city,f.state_code,f.brands,f.within_pilot_radius,f.last_observed_at
  from scout.v_portfolio_account_facilities f join org o on o.organization_id=f.organization_id
  where f.source_slug='commonwealth-hotels-managed-portfolio' and f.relationship_type='manages' and f.relationship_status='current' and f.portfolio_asset_status='operating' and f.portfolio_unit_type='hotel' and f.within_pilot_radius=true
), resolved as (
  select f.source_record_id,count(distinct p.building_source_record_id)::integer resolved_building_count,min(p.confidence)::numeric link_confidence,extensions.st_centroid(extensions.st_collect(br.location::extensions.geometry)) site_point
  from facilities f join scout.property_building_links p on p.property_source_record_id=f.source_record_id and p.match_status='resolved'
  join ingest.raw_records br on br.id=p.building_source_record_id and br.location is not null
  group by f.source_record_id
), account_research as (
  select q.any_contact_route_available,q.operations_route_available,q.procurement_route_available,q.operating_asset_vendor_route_proven,q.current_need_scan_complete
  from scout.v_portfolio_account_research_queue q join org o on o.organization_id=q.organization_id limit 1
)
select jsonb_build_object('contract_version','hotel_management_portfolio_map_v1','account_name',min(f.account_name),'organization_id',min(f.organization_id::text),'scope','documented_operating_roster','source_slug','commonwealth-hotels-managed-portfolio','relationship','manages','target_kind','site_member','map_semantics','documented_operating_hotel_portfolio','evidence_boundary','first-party hotel-management roster plus resolved building crosswalks','generated_at',statement_timestamp(),'observed_at',max(f.last_observed_at),'contact_route_available',max(ar.any_contact_route_available::int)::boolean,'operations_route_available',max(ar.operations_route_available::int)::boolean,'procurement_route_available',max(ar.procurement_route_available::int)::boolean,'vendor_route_proven',max(ar.operating_asset_vendor_route_proven::int)::boolean,'current_need_scan_complete',max(ar.current_need_scan_complete::int)::boolean,'members',jsonb_agg(jsonb_build_object('id',f.organization_facility_id::text,'name',f.site_name,'address',f.site_address_text,'city',f.city,'state_code',f.state_code,'brands',coalesce(f.brands,'[]'::jsonb),'point',case when r.site_point is null then jsonb_build_object('type','unresolved') else extensions.st_asgeojson(r.site_point)::jsonb end,'resolution_state',case when coalesce(r.resolved_building_count,0)=0 then 'unresolved' when r.resolved_building_count=1 then 'single_building_resolved' else 'multi_building_resolved' end,'resolved_building_count',coalesce(r.resolved_building_count,0),'link_confidence',r.link_confidence,'within_pilot_radius',f.within_pilot_radius,'observed_at',f.last_observed_at) order by f.site_name,f.organization_facility_id))
from facilities f left join resolved r on r.source_record_id=f.source_record_id cross join account_research ar having count(*) between 1 and 100;
$function$;
comment on function public.scout_get_component_sandbox_hotel_portfolio_v1_internal() is 'Owner sandbox-only Commonwealth Hotels operating management roster. Map points are derived only from resolved property-to-building crosswalks; unresolved roster members remain unmapped.';
revoke all on function public.scout_get_component_sandbox_hotel_portfolio_v1_internal() from public;
revoke all on function public.scout_get_component_sandbox_hotel_portfolio_v1_internal() from anon;
revoke all on function public.scout_get_component_sandbox_hotel_portfolio_v1_internal() from authenticated;
grant execute on function public.scout_get_component_sandbox_hotel_portfolio_v1_internal() to service_role;
'''
(MIG/'20260915011500_add_hotel_portfolio_sandbox_v1.sql').write_text(migration)

# Renderer generated from dealership template needs symbol cleanup after replacement above.
p=COMP/'hotel_portfolio_map_renderer.ts'; txt=p.read_text(); txt=txt.replace('ScoutHotelPortfolioResolutionState','ScoutHotelPortfolioResolutionState').replace("./dealership_portfolio_map_model.ts","./hotel_portfolio_map_model.ts"); p.write_text(txt)

# Shared schema imports into gateway mirrors and version/tool additions.
for gp in [ROOT/'supabase/functions/scout-connect/index.ts',ROOT/'supabase/functions/scout-mcp-contract/index.ts']:
  t=gp.read_text()
  anchor="import { sandboxDealershipPortfolioMapSchema, sandboxDealershipPortfolioOpportunitySchema } from '../_shared/scout_sandbox_dealership_portfolio_schema.ts'"
  t=t.replace(anchor,anchor+"\nimport { sandboxHotelPortfolioMapSchema, sandboxHotelPortfolioOpportunitySchema } from '../_shared/scout_sandbox_hotel_portfolio_schema.ts'")
  t=t.replace("const SANDBOX_RESOURCE_URI = 'ui://scout/component-sandbox/v33'","const SANDBOX_RESOURCE_URI = 'ui://scout/component-sandbox/v34'")
  t=t.replace("const SANDBOX_COMPATIBILITY_RESOURCE_URIS = ['ui://scout/component-sandbox/v32'","const SANDBOX_COMPATIBILITY_RESOURCE_URIS = ['ui://scout/component-sandbox/v33','ui://scout/component-sandbox/v32'")
  old="{type:'object',properties:{surface:{type:'string',enum:['scout_component_sandbox']},opportunity_type:{type:'string',enum:['dealership_group_portfolio']},opportunity:sandboxDealershipPortfolioOpportunitySchema(),map:sandboxDealershipPortfolioMapSchema()},required:['surface','opportunity_type','opportunity','map'],additionalProperties:false}]}}"
  new="{type:'object',properties:{surface:{type:'string',enum:['scout_component_sandbox']},opportunity_type:{type:'string',enum:['dealership_group_portfolio']},opportunity:sandboxDealershipPortfolioOpportunitySchema(),map:sandboxDealershipPortfolioMapSchema()},required:['surface','opportunity_type','opportunity','map'],additionalProperties:false},{type:'object',properties:{surface:{type:'string',enum:['scout_component_sandbox']},opportunity_type:{type:'string',enum:['hotel_management_portfolio']},opportunity:sandboxHotelPortfolioOpportunitySchema(),map:sandboxHotelPortfolioMapSchema()},required:['surface','opportunity_type','opportunity','map'],additionalProperties:false}]}}"
  if old not in t: raise SystemExit(f'gateway result anchor missing {gp}')
  t=t.replace(old,new)
  t=t.replace("or the Don Franklin Auto dealership_group_portfolio exemplar;", "the Don Franklin Auto dealership_group_portfolio exemplar, or the Commonwealth Hotels hotel_management_portfolio exemplar;")
  t=t.replace("'water_utility_portfolio','dealership_group_portfolio']", "'water_utility_portfolio','dealership_group_portfolio','hotel_management_portfolio']")
  gp.write_text(t)

# Component index patches.
ip=COMP/'index.ts'; t=ip.read_text()
t=t.replace("} from './dealership_portfolio_map_model.ts'", "} from './dealership_portfolio_map_model.ts'\nimport {\n  buildScoutSandboxHotelPortfolioOpportunity,\n  normalizeScoutSandboxHotelPortfolioMap,\n} from './hotel_portfolio_map_model.ts'")
t=t.replace("import { buildScoutDealershipPortfolioRasterFrame } from './dealership_portfolio_map_renderer.ts'", "import { buildScoutDealershipPortfolioRasterFrame } from './dealership_portfolio_map_renderer.ts'\nimport { buildScoutHotelPortfolioRasterFrame } from './hotel_portfolio_map_renderer.ts'")
t=t.replace("const RESOURCE_URI = 'ui://scout/component-sandbox/v33'", "const RESOURCE_URI = 'ui://scout/component-sandbox/v34'")
t=t.replace("const COMPATIBILITY_RESOURCE_URIS = [\n  'ui://scout/component-sandbox/v32',", "const COMPATIBILITY_RESOURCE_URIS = [\n  'ui://scout/component-sandbox/v33',\n  'ui://scout/component-sandbox/v32',")
t=t.replace("const DEALERSHIP_PORTFOLIO_NARROW_TILE_BOUNDS = { z: 7, minX: 33, maxX: 34, minY: 49, maxY: 49 } as const", "const DEALERSHIP_PORTFOLIO_NARROW_TILE_BOUNDS = { z: 7, minX: 33, maxX: 34, minY: 49, maxY: 49 } as const\nconst HOTEL_PORTFOLIO_TILE_BOUNDS = { z: 7, minX: 32, maxX: 34, minY: 48, maxY: 49 } as const")
anchor="async function loadScoutSandboxDealershipPortfolioMap() {\n  const { data, error } = await admin.rpc('scout_get_component_sandbox_dealership_portfolio_v1_internal')\n  if (error) throw new Error('Scout sandbox dealership portfolio map is unavailable')\n  const map = normalizeScoutSandboxDealershipPortfolioMap(data)\n  if (!map) throw new Error('Scout sandbox dealership portfolio map did not satisfy the bounded contract')\n  return map\n}\n"
addition=anchor+"\nasync function loadScoutSandboxHotelPortfolioMap() {\n  const { data, error } = await admin.rpc('scout_get_component_sandbox_hotel_portfolio_v1_internal')\n  if (error) throw new Error('Scout sandbox hotel portfolio map is unavailable')\n  const map = normalizeScoutSandboxHotelPortfolioMap(data)\n  if (!map) throw new Error('Scout sandbox hotel portfolio map did not satisfy the bounded contract')\n  return map\n}\n"
if anchor not in t: raise SystemExit('component load anchor missing')
t=t.replace(anchor,addition)
t=t.replace('const MAX_EMBEDDED_RASTER_TILES = 32','const MAX_EMBEDDED_RASTER_TILES = 40')
t=t.replace('const [premiumMap, waterTankMap, swpppMap, portfolioMap, dealershipMap] = await Promise.all([','const [premiumMap, waterTankMap, swpppMap, portfolioMap, dealershipMap, hotelMap] = await Promise.all([')
t=t.replace('    loadScoutSandboxDealershipPortfolioMap(),\n  ])','    loadScoutSandboxDealershipPortfolioMap(),\n    loadScoutSandboxHotelPortfolioMap(),\n  ])')
t=t.replace('    buildScoutDealershipPortfolioRasterFrame(dealershipMap, 280, 210, { tileUrlTemplate }),\n  ]','    buildScoutDealershipPortfolioRasterFrame(dealershipMap, 280, 210, { tileUrlTemplate }),\n    buildScoutHotelPortfolioRasterFrame(hotelMap, 456, 210, { tileUrlTemplate }),\n    buildScoutHotelPortfolioRasterFrame(hotelMap, 280, 210, { tileUrlTemplate }),\n  ]')
# Clone dealership zod schema block into hotel-specific schema via explicit insertion after result schema.
marker="const dealershipPortfolioResultSchema = z.object({\n  surface: z.literal('scout_component_sandbox'),\n  opportunity_type: z.literal('dealership_group_portfolio'),\n  opportunity: dealershipPortfolioOpportunitySchema,\n  map: dealershipPortfolioMapSchema,\n})\n"
hotelz=r'''

const hotelPortfolioMemberSchema = z.object({
  id:z.string().min(1).max(80),name:z.string().min(1).max(200),address:z.string().min(1).max(240),city:z.string().min(1).max(120),state_code:z.string().min(1).max(8),brands:z.array(z.string().min(1).max(80)).max(16),
  point:z.union([z.object({type:z.literal('Point'),coordinates:z.tuple([z.number().min(-180).max(180),z.number().min(-90).max(90)])}),z.object({type:z.literal('unresolved')})]),
  resolution_state:z.enum(['single_building_resolved','multi_building_resolved','unresolved']),resolved_building_count:z.number().int().min(0).max(20),link_confidence:z.number().min(0).max(1).nullable(),within_pilot_radius:z.boolean(),observed_at:z.string().min(1).max(80),
})
const hotelPortfolioMapSchema=z.object({contract_version:z.literal('hotel_management_portfolio_map_v1'),opportunity_type:z.literal('hotel_management_portfolio'),group_kind:z.literal('portfolio'),account_name:z.string().min(1).max(200),organization_id:z.string().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i),scope:z.literal('documented_operating_roster'),source_slug:z.literal('commonwealth-hotels-managed-portfolio'),relationship:z.literal('manages'),target_kind:z.literal('site_member'),map_semantics:z.literal('documented_operating_hotel_portfolio'),evidence_boundary:z.literal('first-party hotel-management roster plus resolved building crosswalks'),generated_at:z.string().min(1).max(80),observed_at:z.string().min(1).max(80),member_count:z.number().int().min(1).max(100),resolved_member_count:z.number().int().min(1).max(100),resolved_building_count:z.number().int().min(1).max(200),contact_route_available:z.boolean(),operations_route_available:z.boolean(),procurement_route_available:z.boolean(),vendor_route_proven:z.boolean(),current_need_scan_complete:z.boolean(),bounds:z.object({west:z.number().min(-180).max(180),south:z.number().min(-90).max(90),east:z.number().min(-180).max(180),north:z.number().min(-90).max(90)}),members:z.array(hotelPortfolioMemberSchema).min(1).max(100),guardrail:z.string().min(1).max(1600)})
const hotelPortfolioOpportunitySchema=z.object({opportunity_type:z.literal('hotel_management_portfolio'),name:z.string().min(1).max(200),member_count:z.number().int().min(1).max(100),resolved_member_count:z.number().int().min(1).max(100),resolved_building_count:z.number().int().min(1).max(200),unresolved_member_count:z.number().int().min(0).max(100),observed_at:z.string().min(1).max(80),contact_route_available:z.boolean(),operations_route_available:z.boolean(),procurement_route_available:z.boolean(),vendor_route_proven:z.boolean(),current_need_scan_complete:z.boolean(),map_semantics:z.literal('documented_operating_hotel_portfolio'),evidence_boundary:z.literal('first-party hotel-management roster plus resolved building crosswalks'),why_investigate:z.string().min(1).max(1000),guardrail:z.string().min(1).max(1600)})
const hotelPortfolioResultSchema=z.object({surface:z.literal('scout_component_sandbox'),opportunity_type:z.literal('hotel_management_portfolio'),opportunity:hotelPortfolioOpportunitySchema,map:hotelPortfolioMapSchema})
'''
if marker not in t: raise SystemExit('component schema anchor missing')
t=t.replace(marker,marker+hotelz)
t=t.replace("new McpServer({ name: 'Scout UI Foundation', version: '2.3.3' })","new McpServer({ name: 'Scout UI Foundation', version: '2.3.4' })")
t=t.replace("the Warren County water_utility_portfolio exemplar, or the Don Franklin Auto dealership_group_portfolio exemplar;", "the Warren County water_utility_portfolio exemplar, the Don Franklin Auto dealership_group_portfolio exemplar, or the Commonwealth Hotels hotel_management_portfolio exemplar;")
t=t.replace("z.enum(['premium_exterior', 'water_tank', 'swppp_site', 'water_utility_portfolio', 'dealership_group_portfolio'])", "z.enum(['premium_exterior', 'water_tank', 'swppp_site', 'water_utility_portfolio', 'dealership_group_portfolio', 'hotel_management_portfolio'])")
t=t.replace('waterUtilityPortfolioResultSchema, dealershipPortfolioResultSchema])','waterUtilityPortfolioResultSchema, dealershipPortfolioResultSchema, hotelPortfolioResultSchema])')
handler="""      if (selectedType === 'dealership_group_portfolio') {"""
hotel_handler="""      if (selectedType === 'hotel_management_portfolio') {
        const map = await loadScoutSandboxHotelPortfolioMap()
        const opportunity = buildScoutSandboxHotelPortfolioOpportunity(map)
        if (map.account_name !== opportunity.name || map.member_count !== opportunity.member_count || map.resolved_member_count !== opportunity.resolved_member_count) throw new Error('Scout sandbox hotel portfolio opportunity and map identity do not match')
        return { content: [{ type: 'text', text: `Scout returned the bounded ${opportunity.name} hotel-management portfolio card with ${opportunity.resolved_member_count} mapped sites from ${opportunity.member_count} documented operating hotels.` }], structuredContent: { surface: 'scout_component_sandbox', opportunity_type: 'hotel_management_portfolio', opportunity, map } }
      }

"""+handler
if handler not in t: raise SystemExit('handler anchor missing')
t=t.replace(handler,hotel_handler,1)
allow="""  if (z === DEALERSHIP_PORTFOLIO_NARROW_TILE_BOUNDS.z
    && x >= DEALERSHIP_PORTFOLIO_NARROW_TILE_BOUNDS.minX && x <= DEALERSHIP_PORTFOLIO_NARROW_TILE_BOUNDS.maxX
    && y >= DEALERSHIP_PORTFOLIO_NARROW_TILE_BOUNDS.minY && y <= DEALERSHIP_PORTFOLIO_NARROW_TILE_BOUNDS.maxY) return { z, x, y }
"""
if allow not in t: raise SystemExit('tile anchor missing')
t=t.replace(allow,allow+"  if (z === HOTEL_PORTFOLIO_TILE_BOUNDS.z\n    && x >= HOTEL_PORTFOLIO_TILE_BOUNDS.minX && x <= HOTEL_PORTFOLIO_TILE_BOUNDS.maxX\n    && y >= HOTEL_PORTFOLIO_TILE_BOUNDS.minY && y <= HOTEL_PORTFOLIO_TILE_BOUNDS.maxY) return { z, x, y }\n")
ip.write_text(t)

# View patches.
vp=COMP/'view.ts'; v=vp.read_text()
v=v.replace("import { buildScoutDealershipPortfolioRasterFrame } from './dealership_portfolio_map_renderer.ts'", "import { buildScoutDealershipPortfolioRasterFrame } from './dealership_portfolio_map_renderer.ts'\nimport { normalizeScoutSandboxHotelPortfolioMap, normalizeScoutSandboxHotelPortfolioOpportunity } from './hotel_portfolio_map_model.ts'\nimport { mountScoutHotelPortfolioMap } from './hotel_portfolio_map_mount.ts'")
v=v.replace("type ScoutViewOpportunityType = ScoutSandboxOpportunityType | 'water_utility_portfolio' | 'dealership_group_portfolio'", "type ScoutViewOpportunityType = ScoutSandboxOpportunityType | 'water_utility_portfolio' | 'dealership_group_portfolio' | 'hotel_management_portfolio'")
v=v.replace('if (!Array.isArray(value) || value.length > 32) return undefined','if (!Array.isArray(value) || value.length > 40) return undefined')
render_anchor="  if (opportunityType === 'dealership_group_portfolio') {"
hotel_render="""  if (opportunityType === 'hotel_management_portfolio') {
    const opportunity = normalizeScoutSandboxHotelPortfolioOpportunity(value)
    if (!opportunity) { renderUnavailableOpportunity(); return }
    if (title) title.textContent = opportunity.name
    if (tier) tier.textContent = 'Portfolio evidence'
    if (meta) meta.textContent = `${formatNumber(opportunity.member_count)} documented operating hotels  •  First-party management roster observed ${formatObserved(opportunity.observed_at)}`
    if (address) address.textContent = 'Kentucky pilot hotel portfolio'
    if (summary) {
      const route = opportunity.operations_route_available && opportunity.procurement_route_available ? 'Operations + procurement routes available' : opportunity.contact_route_available ? 'Contact route available; account purchasing route incomplete' : 'Account route unresolved'
      const vendor = opportunity.vendor_route_proven ? 'vendor route documented' : 'vendor route not yet proven'
      summary.textContent = `${formatNumber(opportunity.resolved_member_count)} hotels physically crosswalked  •  ${formatNumber(opportunity.resolved_building_count)} resolved buildings  •  ${formatNumber(opportunity.unresolved_member_count)} roster sites not mapped  •  ${route}; ${vendor}  •  ${opportunity.why_investigate}`
    }
    if (guardrail) guardrail.textContent = `Scout guardrail: ${opportunity.guardrail}`
    setState(`Scout portfolio ready: ${opportunity.name}`)
    return
  }

"""+render_anchor
if render_anchor not in v: raise SystemExit('view render anchor missing')
v=v.replace(render_anchor,hotel_render,1)
v=v.replace("(opportunityType === 'water_utility_portfolio' || opportunityType === 'dealership_group_portfolio')", "(opportunityType === 'water_utility_portfolio' || opportunityType === 'dealership_group_portfolio' || opportunityType === 'hotel_management_portfolio')")
map_anchor="""    if (opportunityType === 'dealership_group_portfolio') {"""
hotel_map="""    if (opportunityType === 'hotel_management_portfolio') {
      const normalized = normalizeScoutSandboxHotelPortfolioMap(value)
      if (!normalized) { mapState.textContent = 'Portfolio map unavailable'; setState('Scout hotel portfolio map result failed validation'); return }
      mapContainer.setAttribute('role','img')
      mapContainer.setAttribute('aria-label', `Documented hotel portfolio map for ${normalized.account_name}`)
      mapHandle = mountScoutHotelPortfolioMap(mapContainer, normalized, { ...mapOptions, embeddedTiles })
    } else if (opportunityType === 'dealership_group_portfolio') {"""
if map_anchor not in v: raise SystemExit('view map anchor missing')
v=v.replace(map_anchor,hotel_map,1)
v=v.replace("r !== 'water_utility_portfolio' && r !== 'dealership_group_portfolio'", "r !== 'water_utility_portfolio' && r !== 'dealership_group_portfolio' && r !== 'hotel_management_portfolio'")
v=v.replace("version: '2.13.0'", "version: '2.14.0'")
vp.write_text(v)

# Package test command.
pp=COMP/'package.json'; pkg=json.loads(pp.read_text()); pkg['scripts']['test']=pkg['scripts']['test'].replace('node dealership_portfolio_gateway_contract_test.mjs && node gateway_syntax_test.mjs','node dealership_portfolio_gateway_contract_test.mjs && node hotel_portfolio_map_renderer_test.mjs && node hotel_portfolio_gateway_contract_test.mjs && node gateway_syntax_test.mjs'); pp.write_text(json.dumps(pkg,indent=2)+'\n')

# Renderer test.
test=r'''import { readFile } from 'node:fs/promises'
import assert from 'node:assert/strict'
import { build } from 'esbuild'
const d=new URL('./',import.meta.url)
const modelSource=await readFile(new URL('hotel_portfolio_map_model.ts',d),'utf8'),mountSource=await readFile(new URL('hotel_portfolio_map_mount.ts',d),'utf8')
assert.ok(modelSource.includes('commonwealth-hotels-managed-portfolio'));assert.ok(modelSource.includes('linkConfidenceValue == null'));assert.ok(mountSource.includes('Marriott family'));assert.ok(mountSource.includes('Hilton family'))
const resolved=[['Courtyard Cincinnati Airport',['Courtyard by Marriott'],[-84.628490281,39.052913717]],['Hampton Inn Cincinnati Airport',['Hampton by Hilton'],[-84.635182438,39.015264895]],['Hampton Inn Louisville Airport',['Hampton by Hilton'],[-85.743168701,38.190898942]],['Residence Inn Louisville Airport',['Residence Inn by Marriott'],[-85.744392935,38.190277203]],['SpringHill Suites Louisville Airport',['SpringHill Suites by Marriott'],[-85.74172902,38.190708967]]]
const unresolved=[['Holiday Inn Express & Suites Cincinnati',['Holiday Inn Express & Suites']],['Residence Inn Cincinnati Airport',['Residence Inn by Marriott']],['Tru by Hilton Louisville Airport',['Tru by Hilton']]]
const members=[...resolved.map(([name,brands,coordinates],i)=>({id:`00000000-0000-4000-8000-${String(i+1).padStart(12,'0')}`,name,address:'address',city:'city',state_code:'KY',brands,point:{type:'Point',coordinates},resolution_state:'single_building_resolved',resolved_building_count:1,link_confidence:.99,within_pilot_radius:true,observed_at:'2026-09-07T20:24:19.916463+00:00'})),...unresolved.map(([name,brands],i)=>({id:`00000000-0000-4000-8000-${String(i+20).padStart(12,'0')}`,name,address:'address',city:'city',state_code:'KY',brands,point:{type:'unresolved'},resolution_state:'unresolved',resolved_building_count:0,within_pilot_radius:true,observed_at:'2026-09-07T20:24:19.916463+00:00'}))]
const raw={contract_version:'hotel_management_portfolio_map_v1',account_name:'Commonwealth Hotels',organization_id:'6513f69a-bb53-4706-854b-bf9f7ba3064b',scope:'documented_operating_roster',source_slug:'commonwealth-hotels-managed-portfolio',relationship:'manages',target_kind:'site_member',map_semantics:'documented_operating_hotel_portfolio',evidence_boundary:'first-party hotel-management roster plus resolved building crosswalks',generated_at:'2026-09-15T01:00:00Z',contact_route_available:true,operations_route_available:true,procurement_route_available:true,vendor_route_proven:false,current_need_scan_complete:true,members}
const mb=await build({entryPoints:[new URL('hotel_portfolio_map_model.ts',d).pathname],bundle:true,format:'esm',platform:'node',target:'node24',write:false});const mod=await import(`data:text/javascript;base64,${Buffer.from(mb.outputFiles[0].text).toString('base64')}`);const normalized=mod.normalizeScoutSandboxHotelPortfolioMap(raw);assert.ok(normalized);assert.equal(normalized.member_count,8);assert.equal(normalized.resolved_member_count,5);assert.equal(normalized.resolved_building_count,5);assert.equal(normalized.members.filter(x=>x.link_confidence===null).length,3)
const bad=structuredClone(raw);delete bad.members[0].link_confidence;assert.equal(mod.normalizeScoutSandboxHotelPortfolioMap(bad),null)
const rb=await build({entryPoints:[new URL('hotel_portfolio_map_renderer.ts',d).pathname],bundle:true,format:'esm',platform:'node',target:'node24',write:false});const ren=await import(`data:text/javascript;base64,${Buffer.from(rb.outputFiles[0].text).toString('base64')}`);const frame=ren.buildScoutHotelPortfolioRasterFrame(normalized,456,210,{tileUrlTemplate:'https://tile/{z}/{x}/{y}.png'});assert.equal(frame.zoom,7);assert.equal(frame.tiles.length,6);assert.equal(frame.markers.length,5);assert.deepEqual(frame.tiles.map(x=>`${x.z}/${x.x}/${x.y}`).sort(),['7/32/48','7/32/49','7/33/48','7/33/49','7/34/48','7/34/49']);const narrow=ren.buildScoutHotelPortfolioRasterFrame(normalized,280,210,{tileUrlTemplate:'https://tile/{z}/{x}/{y}.png'});assert.equal(narrow.zoom,7);assert.deepEqual(narrow.tiles.map(x=>`${x.z}/${x.x}/${x.y}`).sort(),['7/33/48','7/33/49','7/34/48','7/34/49']);console.log('Scout hotel portfolio checks passed: 8 roster, 5 mapped, zoom 7.')
'''
(COMP/'hotel_portfolio_map_renderer_test.mjs').write_text(test)

gateway_test=r'''import { readFile } from 'node:fs/promises';import assert from 'node:assert/strict';const d=new URL('./',import.meta.url);for(const rel of ['../scout-connect/index.ts','../scout-mcp-contract/index.ts']){const s=await readFile(new URL(rel,d),'utf8');assert.ok(s.includes("hotel_management_portfolio"));assert.ok(s.includes('sandboxHotelPortfolioMapSchema'));assert.ok(s.includes("ui://scout/component-sandbox/v34"))}const component=await readFile(new URL('index.ts',d),'utf8');assert.ok(component.includes("scout_get_component_sandbox_hotel_portfolio_v1_internal"));assert.ok(component.includes('HOTEL_PORTFOLIO_TILE_BOUNDS'));assert.ok(component.includes('MAX_EMBEDDED_RASTER_TILES = 40'));console.log('Scout hotel portfolio gateway contract checks passed.')
'''
(COMP/'hotel_portfolio_gateway_contract_test.mjs').write_text(gateway_test)

# Bump existing hardcoded current version expectations within sandbox tests only.
for p in COMP.glob('*test.mjs'):
  text=p.read_text().replace("ui://scout/component-sandbox/v33","ui://scout/component-sandbox/v34").replace("version: '2.13.0'","version: '2.14.0'").replace("version: '2.3.3'","version: '2.3.4'")
  p.write_text(text)

print('hotel portfolio v34 patch applied')
