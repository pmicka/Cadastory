export type ScoutHotelPortfolioPoint =
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
