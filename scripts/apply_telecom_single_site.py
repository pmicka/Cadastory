from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
SHARED=ROOT/'supabase/functions/_shared'
COMP=ROOT/'supabase/functions/scout-component-sandbox-mcp'
MIG=ROOT/'supabase/migrations'

def write(path,text):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(text.rstrip()+"\n")

def replace_once(path,old,new):
    text=path.read_text()
    if old not in text:
        raise RuntimeError(f'anchor missing in {path}: {old[:120]!r}')
    path.write_text(text.replace(old,new,1))

# Shared schema for the bounded telecom change exemplar.
write(SHARED/'scout_sandbox_telecom_change_schema.ts',r'''
export function sandboxTelecomChangeMapSchema(){return {type:'object',properties:{contract_version:{type:'string',enum:['telecom_change_single_site_map_v1']},opportunity_type:{type:'string',enum:['telecom_change']},candidate_key:{type:'string',minLength:1,maxLength:120},event_id:{type:'string',pattern:'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'},registration_number:{type:'string',enum:['1333510']},event_type:{type:'string',enum:['new_registration']},signal_strength:{type:'string',enum:['high']},confidence:{type:'number',minimum:0,maximum:1},observed_at:{type:'string',minLength:1,maxLength:80},site_point:{type:'object',properties:{lon:{type:'number',minimum:-180,maximum:180},lat:{type:'number',minimum:-90,maximum:90},source:{type:'string',enum:['fcc_asr_registration']},source_authority:{type:'string',enum:['Federal Communications Commission']},canonical_source:{type:'string',enum:['fcc_asr']}},required:['lon','lat','source','source_authority','canonical_source'],additionalProperties:false},asset:{type:'object',properties:{owner_name:{type:'string',enum:['The Towers, LLC']},owner_frn:{type:'string',enum:['0033815929']},status_code:{type:'string',enum:['C']},structure_type_code:{type:'string',enum:['LTOWER']},application_purpose_code:{type:'string',enum:['NT']},structure_height_m:{type:'number',minimum:0,maximum:10000},overall_height_agl_m:{type:'number',minimum:0,maximum:10000},date_constructed:{type:'string',enum:['09/04/2026']},date_entered:{type:'string',enum:['09/09/2026']},last_action_date:{type:'string',enum:['09/09/2026']},structure_address:{type:'string',enum:['S. Becker Road / IN-5286']},city:{type:'string',enum:['Leavenworth']},state_code:{type:'string',enum:['IN']},zip:{type:'string',enum:['47137']},faa_study_number:{type:'string',enum:['2026-AGL-2286-OE']}},required:['owner_name','owner_frn','status_code','structure_type_code','application_purpose_code','structure_height_m','overall_height_agl_m','date_constructed','date_entered','last_action_date','structure_address','city','state_code','zip','faa_study_number'],additionalProperties:false},buyer:{type:'object',properties:{organization_id:{type:'string',pattern:'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'},canonical_name:{type:'string',enum:['The Towers, LLC']},organization_type:{type:'string',enum:['tower_owner']},resolution_state:{type:'string',enum:['resolved_scout_organization']},resolution_basis:{type:'string',enum:['opportunity_buyer_identity']},contact_route_available:{type:'boolean'},procurement_route_available:{type:'boolean'}},required:['organization_id','canonical_name','organization_type','resolution_state','resolution_basis','contact_route_available','procurement_route_available'],additionalProperties:false},guardrail:{type:'string',minLength:1,maxLength:2400}},required:['contract_version','opportunity_type','candidate_key','event_id','registration_number','event_type','signal_strength','confidence','observed_at','site_point','asset','buyer','guardrail'],additionalProperties:false}}
export function sandboxTelecomChangeOpportunitySchema(){return {type:'object',properties:{opportunity_type:{type:'string',enum:['telecom_change']},name:{type:'string',enum:['The Towers, LLC']},registration_number:{type:'string',enum:['1333510']},signal_kind:{type:'string',enum:['new_registration']},signal_strength:{type:'string',enum:['high']},signal_confidence:{type:'number',minimum:0,maximum:1},observed_at:{type:'string',minLength:1,maxLength:80},location_label:{type:'string',enum:['S. Becker Road / IN-5286 · Leavenworth, IN']},structure_type_code:{type:'string',enum:['LTOWER']},overall_height_agl_m:{type:'number',minimum:0,maximum:10000},date_constructed:{type:'string',enum:['09/04/2026']},buyer_resolution_state:{type:'string',enum:['resolved_scout_organization']},contact_route_available:{type:'boolean'},procurement_route_available:{type:'boolean'},why_investigate:{type:'string',minLength:1,maxLength:1200},guardrail:{type:'string',minLength:1,maxLength:2400}},required:['opportunity_type','name','registration_number','signal_kind','signal_strength','signal_confidence','observed_at','location_label','structure_type_code','overall_height_agl_m','date_constructed','buyer_resolution_state','contact_route_available','procurement_route_available','why_investigate','guardrail'],additionalProperties:false}}
''')

write(COMP/'telecom_change_map_model.ts',r'''
export type ScoutSandboxTelecomChangeMap={contract_version:'telecom_change_single_site_map_v1';opportunity_type:'telecom_change';candidate_key:string;event_id:string;registration_number:'1333510';event_type:'new_registration';signal_strength:'high';confidence:number;observed_at:string;site_point:{lon:number;lat:number;source:'fcc_asr_registration';source_authority:'Federal Communications Commission';canonical_source:'fcc_asr'};asset:{owner_name:'The Towers, LLC';owner_frn:'0033815929';status_code:'C';structure_type_code:'LTOWER';application_purpose_code:'NT';structure_height_m:number;overall_height_agl_m:number;date_constructed:'09/04/2026';date_entered:'09/09/2026';last_action_date:'09/09/2026';structure_address:'S. Becker Road / IN-5286';city:'Leavenworth';state_code:'IN';zip:'47137';faa_study_number:'2026-AGL-2286-OE'};buyer:{organization_id:string;canonical_name:'The Towers, LLC';organization_type:'tower_owner';resolution_state:'resolved_scout_organization';resolution_basis:'opportunity_buyer_identity';contact_route_available:boolean;procurement_route_available:boolean};guardrail:string}
export type ScoutSandboxTelecomChangeOpportunity={opportunity_type:'telecom_change';name:'The Towers, LLC';registration_number:'1333510';signal_kind:'new_registration';signal_strength:'high';signal_confidence:number;observed_at:string;location_label:'S. Becker Road / IN-5286 · Leavenworth, IN';structure_type_code:'LTOWER';overall_height_agl_m:number;date_constructed:'09/04/2026';buyer_resolution_state:'resolved_scout_organization';contact_route_available:boolean;procurement_route_available:boolean;why_investigate:string;guardrail:string}
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
const GUARDRAIL='This is a bounded FCC Antenna Structure Registration change signal. FCC ASR registration 1333510 and its coordinates and structure attributes identify a registered antenna-structure record; Scout does not infer inspection need, maintenance due, commissioning scope, procurement, buyer intent, vendor eligibility, site access, climb authorization, or work availability. The Towers, LLC buyer resolution is separate Scout organization linkage; a durable contact route is not a documented procurement route.'
const WHY='FCC ASR 1333510 was observed as a new registration on September 10, 2026, and the current FCC structure record reports a September 4, 2026 construction date. That makes the asset timely to qualify for owner-side inspection or documentation needs without asserting that any such need exists.'
function text(v:unknown,n=1000){if(typeof v!=='string')return null;const s=v.trim();return s&&s.length<=n?s:null}
function num(v:unknown,min:number,max:number){return typeof v==='number'&&Number.isFinite(v)&&v>=min&&v<=max?v:null}
function timestamp(v:unknown){const s=text(v,80);if(!s)return null;const d=new Date(s);return Number.isNaN(d.valueOf())?null:d.toISOString()}
export function normalizeScoutSandboxTelecomChangeMap(value:unknown):ScoutSandboxTelecomChangeMap|null{if(!value||typeof value!=='object'||Array.isArray(value))return null;const s=value as Record<string,unknown>;if(s.contract_version!=='telecom_change_single_site_map_v1'||s.opportunity_type!=='telecom_change'||s.registration_number!=='1333510'||s.event_type!=='new_registration'||s.signal_strength!=='high')return null;const candidate=text(s.candidate_key,120),eventId=text(s.event_id,36),confidence=num(s.confidence,0,1),observed=timestamp(s.observed_at);if(!candidate||!eventId||!UUID.test(eventId)||confidence===null||!observed)return null;if(!s.site_point||typeof s.site_point!=='object'||Array.isArray(s.site_point)||!s.asset||typeof s.asset!=='object'||Array.isArray(s.asset)||!s.buyer||typeof s.buyer!=='object'||Array.isArray(s.buyer))return null;const p=s.site_point as Record<string,unknown>,a=s.asset as Record<string,unknown>,b=s.buyer as Record<string,unknown>;const lon=num(p.lon,-180,180),lat=num(p.lat,-90,90),structureHeight=num(a.structure_height_m,0,10000),overallHeight=num(a.overall_height_agl_m,0,10000),orgId=text(b.organization_id,36);if(lon===null||lat===null||p.source!=='fcc_asr_registration'||p.source_authority!=='Federal Communications Commission'||p.canonical_source!=='fcc_asr'||structureHeight===null||overallHeight===null||!orgId||!UUID.test(orgId))return null;if(a.owner_name!=='The Towers, LLC'||a.owner_frn!=='0033815929'||a.status_code!=='C'||a.structure_type_code!=='LTOWER'||a.application_purpose_code!=='NT'||a.date_constructed!=='09/04/2026'||a.date_entered!=='09/09/2026'||a.last_action_date!=='09/09/2026'||a.structure_address!=='S. Becker Road / IN-5286'||a.city!=='Leavenworth'||a.state_code!=='IN'||a.zip!=='47137'||a.faa_study_number!=='2026-AGL-2286-OE')return null;if(b.canonical_name!=='The Towers, LLC'||b.organization_type!=='tower_owner'||b.resolution_state!=='resolved_scout_organization'||b.resolution_basis!=='opportunity_buyer_identity'||b.contact_route_available!==true||b.procurement_route_available!==false||s.guardrail!==GUARDRAIL)return null;return{contract_version:'telecom_change_single_site_map_v1',opportunity_type:'telecom_change',candidate_key:candidate,event_id:eventId,registration_number:'1333510',event_type:'new_registration',signal_strength:'high',confidence,observed_at:observed,site_point:{lon,lat,source:'fcc_asr_registration',source_authority:'Federal Communications Commission',canonical_source:'fcc_asr'},asset:{owner_name:'The Towers, LLC',owner_frn:'0033815929',status_code:'C',structure_type_code:'LTOWER',application_purpose_code:'NT',structure_height_m:structureHeight,overall_height_agl_m:overallHeight,date_constructed:'09/04/2026',date_entered:'09/09/2026',last_action_date:'09/09/2026',structure_address:'S. Becker Road / IN-5286',city:'Leavenworth',state_code:'IN',zip:'47137',faa_study_number:'2026-AGL-2286-OE'},buyer:{organization_id:orgId,canonical_name:'The Towers, LLC',organization_type:'tower_owner',resolution_state:'resolved_scout_organization',resolution_basis:'opportunity_buyer_identity',contact_route_available:true,procurement_route_available:false},guardrail:GUARDRAIL}}
export function buildScoutSandboxTelecomChangeOpportunity(map:ScoutSandboxTelecomChangeMap):ScoutSandboxTelecomChangeOpportunity{return{opportunity_type:'telecom_change',name:'The Towers, LLC',registration_number:'1333510',signal_kind:'new_registration',signal_strength:'high',signal_confidence:map.confidence,observed_at:map.observed_at,location_label:'S. Becker Road / IN-5286 · Leavenworth, IN',structure_type_code:'LTOWER',overall_height_agl_m:map.asset.overall_height_agl_m,date_constructed:'09/04/2026',buyer_resolution_state:'resolved_scout_organization',contact_route_available:map.buyer.contact_route_available,procurement_route_available:map.buyer.procurement_route_available,why_investigate:WHY,guardrail:map.guardrail}}
export function normalizeScoutSandboxTelecomChangeOpportunity(value:unknown):ScoutSandboxTelecomChangeOpportunity|null{if(!value||typeof value!=='object'||Array.isArray(value))return null;const s=value as Record<string,unknown>;const confidence=num(s.signal_confidence,0,1),observed=timestamp(s.observed_at),height=num(s.overall_height_agl_m,0,10000);if(s.opportunity_type!=='telecom_change'||s.name!=='The Towers, LLC'||s.registration_number!=='1333510'||s.signal_kind!=='new_registration'||s.signal_strength!=='high'||confidence===null||!observed||s.location_label!=='S. Becker Road / IN-5286 · Leavenworth, IN'||s.structure_type_code!=='LTOWER'||height===null||s.date_constructed!=='09/04/2026'||s.buyer_resolution_state!=='resolved_scout_organization'||s.contact_route_available!==true||s.procurement_route_available!==false||s.why_investigate!==WHY||s.guardrail!==GUARDRAIL)return null;return{opportunity_type:'telecom_change',name:'The Towers, LLC',registration_number:'1333510',signal_kind:'new_registration',signal_strength:'high',signal_confidence:confidence,observed_at:observed,location_label:'S. Becker Road / IN-5286 · Leavenworth, IN',structure_type_code:'LTOWER',overall_height_agl_m:height,date_constructed:'09/04/2026',buyer_resolution_state:'resolved_scout_organization',contact_route_available:true,procurement_route_available:false,why_investigate:WHY,guardrail:GUARDRAIL}}
''')

write(COMP/'telecom_change_map_renderer.ts',r'''
import type{ScoutSandboxTelecomChangeMap}from'./telecom_change_map_model.ts'
const TILE_SIZE=256,MAX_MERCATOR_LAT=85.05112878,DEFAULT_MIN_ZOOM=5,DEFAULT_MAX_ZOOM=18,DEFAULT_ZOOM=16
export type ScoutTelecomChangeRasterTile={z:number;x:number;y:number;left:number;top:number;url:string}
export type ScoutTelecomChangeRasterFrame={zoom:number;width:number;height:number;tiles:ScoutTelecomChangeRasterTile[];marker:{left:number;top:number}}
export type ScoutTelecomChangeRasterFrameOptions={tileUrlTemplate:string;minZoom?:number;maxZoom?:number}
function clampLat(lat:number){return Math.max(-MAX_MERCATOR_LAT,Math.min(MAX_MERCATOR_LAT,lat))}function worldX(lon:number){return(lon+180)/360}function worldY(lat:number){const r=clampLat(lat)*Math.PI/180;return(1-Math.log(Math.tan(r)+1/Math.cos(r))/Math.PI)/2}function tileUrl(t:string,z:number,x:number,y:number){return t.replace('{z}',String(z)).replace('{x}',String(x)).replace('{y}',String(y))}
export function buildScoutTelecomChangeRasterFrame(data:ScoutSandboxTelecomChangeMap,width:number,height:number,options:ScoutTelecomChangeRasterFrameOptions):ScoutTelecomChangeRasterFrame{const frameWidth=Math.max(280,Math.round(width||0)),frameHeight=Math.max(180,Math.round(height||0)),zoom=Math.max(options.minZoom??DEFAULT_MIN_ZOOM,Math.min(options.maxZoom??DEFAULT_MAX_ZOOM,DEFAULT_ZOOM)),world=TILE_SIZE*Math.pow(2,zoom),cx=worldX(data.site_point.lon)*world,cy=worldY(data.site_point.lat)*world,left=cx-frameWidth/2,top=cy-frameHeight/2,startX=Math.floor(left/TILE_SIZE),endX=Math.floor((left+frameWidth-1)/TILE_SIZE),startY=Math.floor(top/TILE_SIZE),endY=Math.floor((top+frameHeight-1)/TILE_SIZE),count=Math.pow(2,zoom),tiles:ScoutTelecomChangeRasterTile[]=[];for(let tx=startX;tx<=endX;tx++){for(let ty=startY;ty<=endY;ty++){if(ty<0||ty>=count)continue;const x=((tx%count)+count)%count;tiles.push({z:zoom,x,y:ty,left:tx*TILE_SIZE-left,top:ty*TILE_SIZE-top,url:tileUrl(options.tileUrlTemplate,zoom,x,ty)})}}return{zoom,width:frameWidth,height:frameHeight,tiles,marker:{left:frameWidth/2,top:frameHeight/2}}}
''')

write(COMP/'telecom_change_map_mount.ts',r'''
import type{ScoutSandboxTelecomChangeMap}from'./telecom_change_map_model.ts'
import{buildScoutTelecomChangeRasterFrame,type ScoutTelecomChangeRasterFrameOptions}from'./telecom_change_map_renderer.ts'
const DEFAULT_TIMEOUT_MS=7000,PNG='data:image/png;base64,'
async function decode(dataUrl:string){if(!dataUrl.startsWith(PNG))throw new Error('Scout embedded raster tile is invalid');const binary=atob(dataUrl.slice(PNG.length)),bytes=new Uint8Array(binary.length);for(let i=0;i<binary.length;i++)bytes[i]=binary.charCodeAt(i);return await createImageBitmap(new Blob([bytes],{type:'image/png'}))}
export type ScoutTelecomChangeMapMountOptions=ScoutTelecomChangeRasterFrameOptions&{attributionLabel:string;attributionUrl:string;timeoutMs?:number;embeddedTiles?:Record<string,string>;onError?:(error:Error)=>void;onReady?:()=>void}
export function mountScoutTelecomChangeMap(container:HTMLElement,data:ScoutSandboxTelecomChangeMap,options:ScoutTelecomChangeMapMountOptions){let destroyed=false,generation=0,timeout:ReturnType<typeof setTimeout>|null=null,lastW=-1,lastH=-1;const clear=()=>{if(timeout!==null){clearTimeout(timeout);timeout=null}};const render=(force=false)=>{if(destroyed)return;const frame=buildScoutTelecomChangeRasterFrame(data,container.clientWidth,container.clientHeight,options);if(!force&&frame.width===lastW&&frame.height===lastH)return;lastW=frame.width;lastH=frame.height;clear();generation++;const g=generation;container.replaceChildren();let loaded=0,settled=0,ready=false;const ok=()=>{if(destroyed||g!==generation||ready)return;ready=true;clear();options.onReady?.()};const bad=()=>{if(destroyed||g!==generation||ready)return;clear();options.onError?.(new Error('Scout raster tiles did not load'))};const embedded=frame.tiles.length>0&&frame.tiles.every(t=>options.embeddedTiles?.[t.url]);if(embedded){const canvas=document.createElement('canvas');canvas.width=frame.width;canvas.height=frame.height;canvas.style.position='absolute';canvas.style.inset='0';canvas.style.width=`${frame.width}px`;canvas.style.height=`${frame.height}px`;container.appendChild(canvas);const ctx=canvas.getContext('2d');if(!ctx){bad();return}void Promise.allSettled(frame.tiles.map(async t=>{const bitmap=await decode(options.embeddedTiles![t.url]);if(!destroyed&&g===generation){ctx.drawImage(bitmap,t.left,t.top,256,256);loaded++}bitmap.close()})).then(()=>{settled=frame.tiles.length;loaded>0?ok():bad()})}else{for(const t of frame.tiles){const img=document.createElement('img');img.alt='';img.draggable=false;img.decoding='async';img.loading='eager';img.referrerPolicy='origin';img.src=t.url;img.style.left=`${t.left}px`;img.style.top=`${t.top}px`;img.addEventListener('load',()=>{if(destroyed||g!==generation)return;loaded++;settled++;if(loaded===1)ok()},{once:true});img.addEventListener('error',()=>{if(destroyed||g!==generation)return;settled++;if(settled===frame.tiles.length&&loaded===0)bad()},{once:true});container.appendChild(img)}}const marker=document.createElement('span');marker.className='scout-site-marker';marker.style.left=`${frame.marker.left}px`;marker.style.top=`${frame.marker.top}px`;marker.title=`FCC ASR ${data.registration_number} · ${data.asset.owner_name}`;marker.setAttribute('aria-hidden','true');const dot=document.createElement('span');dot.className='scout-site-marker-dot';marker.appendChild(dot);container.appendChild(marker);const attr=document.createElement('span');attr.className='scout-map-attribution';const link=document.createElement('a');link.href=options.attributionUrl;link.target='_blank';link.rel='noreferrer';link.textContent=options.attributionLabel;attr.appendChild(link);container.appendChild(attr);if(frame.tiles.length===0){bad();return}timeout=setTimeout(()=>loaded>0?ok():bad(),options.timeoutMs??DEFAULT_TIMEOUT_MS)};render(true);return{resize(){render(false)},destroy(){if(destroyed)return;destroyed=true;generation++;clear();container.replaceChildren()}}}
''')

write(COMP/'single_site_registry.ts',r'''
import{SCOUT_SANDBOX_SINGLE_SITE_TYPES,type ScoutSandboxSingleSiteType}from'../_shared/scout_sandbox_manifest.ts'
import{buildScoutSandboxWaterTankOpportunity,normalizeScoutSandboxOpportunity,normalizeScoutSandboxSingleSiteMap,normalizeScoutSandboxWaterTankMap}from'./contract.ts'
import{buildScoutSandboxSwpppSiteOpportunity,normalizeScoutSandboxSwpppSiteMap}from'./swppp_site_map_model.ts'
import{buildScoutSwpppSiteTransport}from'./swppp_site_transport.ts'
import{buildScoutSandboxTelecomChangeOpportunity,normalizeScoutSandboxTelecomChangeMap}from'./telecom_change_map_model.ts'
import{buildScoutSingleSiteRasterFrame}from'./single_site_map_renderer.ts'
import{buildScoutWaterTankRasterFrame}from'./water_tank_map_renderer.ts'
import{buildScoutSwpppSiteRasterFrame}from'./swppp_site_map_renderer.ts'
import{buildScoutTelecomChangeRasterFrame}from'./telecom_change_map_renderer.ts'
export const SCOUT_SANDBOX_SINGLE_SITE_IMPLEMENTATIONS={
 premium_exterior:{mapRpc:'scout_get_component_sandbox_premium_exterior_map_v1_internal',opportunityRpc:'scout_get_component_sandbox_opportunity_v1_internal',normalizeMap:normalizeScoutSandboxSingleSiteMap,normalizeOpportunity:normalizeScoutSandboxOpportunity,buildOpportunity:null,toResultMap:(map:any)=>map,buildRasterFrame:buildScoutSingleSiteRasterFrame,identityMatches:(map:any,opp:any)=>map.name===opp.name&&map.address===opp.address,responseText:(opp:any)=>`Scout returned the bounded ${opp.name} premium-exterior opportunity card with its single-site map.`,ariaLabel:(map:any)=>`Site map for ${map.name}`},
 water_tank:{mapRpc:'scout_get_component_sandbox_water_tank_map_v1_internal',opportunityRpc:null,normalizeMap:normalizeScoutSandboxWaterTankMap,normalizeOpportunity:null,buildOpportunity:buildScoutSandboxWaterTankOpportunity,toResultMap:(map:any)=>map,buildRasterFrame:buildScoutWaterTankRasterFrame,identityMatches:(map:any,opp:any)=>map.name===opp.name&&map.system_name===opp.system_name,responseText:(opp:any)=>`Scout returned the bounded ${opp.name} water-tank opportunity card with its single-site map.`,ariaLabel:(map:any)=>`Site map for ${map.name}`},
 swppp_site:{mapRpc:'scout_get_component_sandbox_swppp_site_map_v1_internal',opportunityRpc:null,normalizeMap:normalizeScoutSandboxSwpppSiteMap,normalizeOpportunity:null,buildOpportunity:buildScoutSandboxSwpppSiteOpportunity,toResultMap:buildScoutSwpppSiteTransport,buildRasterFrame:buildScoutSwpppSiteRasterFrame,identityMatches:(map:any,opp:any)=>map.site_name===opp.name&&map.location_label===opp.location_label,responseText:(opp:any)=>`Scout returned the bounded ${opp.name} SWPPP-site evidence card with its authoritative permit-location point map.`,ariaLabel:(map:any)=>`Permit location map for ${map.site_name}`},
 telecom_change:{mapRpc:'scout_get_component_sandbox_telecom_change_v1_internal',opportunityRpc:null,normalizeMap:normalizeScoutSandboxTelecomChangeMap,normalizeOpportunity:null,buildOpportunity:buildScoutSandboxTelecomChangeOpportunity,toResultMap:(map:any)=>map,buildRasterFrame:buildScoutTelecomChangeRasterFrame,identityMatches:(map:any,opp:any)=>map.asset.owner_name===opp.name&&map.registration_number===opp.registration_number,responseText:(opp:any)=>`Scout returned the bounded FCC ASR ${opp.registration_number} telecom-change card for ${opp.name} with its exact registration-point map.`,ariaLabel:(map:any)=>`FCC ASR registration point map for ${map.registration_number}`},
}as const
export function scoutSandboxSingleSiteImplementation(type:ScoutSandboxSingleSiteType){return SCOUT_SANDBOX_SINGLE_SITE_IMPLEMENTATIONS[type] as any}
export function assertScoutSandboxSingleSiteImplementationCoverage(){const a=Object.keys(SCOUT_SANDBOX_SINGLE_SITE_IMPLEMENTATIONS).sort(),b=[...SCOUT_SANDBOX_SINGLE_SITE_TYPES].sort();if(a.length!==b.length||a.some((v,i)=>v!==b[i]))throw new Error('Scout sandbox single-site runtime registry does not match the shared opportunity manifest')}
''')

write(COMP/'single_site_view_registry.ts',r'''
import type{ScoutSandboxSingleSiteType}from'../_shared/scout_sandbox_manifest.ts'
import{normalizeScoutSandboxSingleSiteMap,normalizeScoutSandboxWaterTankMap}from'./contract.ts'
import{mountScoutSingleSiteMap}from'./single_site_map_renderer.ts'
import{mountScoutWaterTankMap}from'./water_tank_map_mount.ts'
import{normalizeScoutSwpppSiteTransport}from'./swppp_site_transport.ts'
import{mountScoutSwpppSiteMap}from'./swppp_site_map_mount.ts'
import{normalizeScoutSandboxTelecomChangeMap}from'./telecom_change_map_model.ts'
import{mountScoutTelecomChangeMap}from'./telecom_change_map_mount.ts'
export const SCOUT_SANDBOX_SINGLE_SITE_VIEW_IMPLEMENTATIONS={
 premium_exterior:{normalizeMap:(value:unknown)=>normalizeScoutSandboxSingleSiteMap(value),mount:mountScoutSingleSiteMap,ariaLabel:(map:any)=>`Site map for ${map.name}`},
 water_tank:{normalizeMap:(value:unknown)=>normalizeScoutSandboxWaterTankMap(value),mount:mountScoutWaterTankMap,ariaLabel:(map:any)=>`Site map for ${map.name}`},
 swppp_site:{normalizeMap:(value:unknown,onReject?:any)=>normalizeScoutSwpppSiteTransport(value,onReject),mount:mountScoutSwpppSiteMap,ariaLabel:(map:any)=>`Permit location map for ${map.site_name}`},
 telecom_change:{normalizeMap:(value:unknown)=>normalizeScoutSandboxTelecomChangeMap(value),mount:mountScoutTelecomChangeMap,ariaLabel:(map:any)=>`FCC ASR registration point map for ${map.registration_number}`},
}as const satisfies Record<ScoutSandboxSingleSiteType,{normalizeMap:any;mount:any;ariaLabel:(map:any)=>string}>
export function scoutSandboxSingleSiteViewImplementation(type:ScoutSandboxSingleSiteType){return SCOUT_SANDBOX_SINGLE_SITE_VIEW_IMPLEMENTATIONS[type] as any}
''')

write(COMP/'telecom_change_map_renderer_test.mjs',r'''
import assert from'node:assert/strict';import{build}from'esbuild';const directory=new URL('./',import.meta.url);async function bundle(path){const result=await build({entryPoints:[new URL(path,directory).pathname],bundle:true,format:'esm',platform:'node',target:'node22',write:false});return await import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`)}const model=await bundle('telecom_change_map_model.ts'),renderer=await bundle('telecom_change_map_renderer.ts'),manifest=await bundle('../_shared/scout_sandbox_manifest.ts');const payload={contract_version:'telecom_change_single_site_map_v1',opportunity_type:'telecom_change',candidate_key:'telecom_change:89a0e8a7-d84a-453a-a18f-2d8bfc834c0e',event_id:'89a0e8a7-d84a-453a-a18f-2d8bfc834c0e',registration_number:'1333510',event_type:'new_registration',signal_strength:'high',confidence:0.95,observed_at:'2026-09-10T05:00:33Z',site_point:{lon:-86.35352777777777,lat:38.20866666666667,source:'fcc_asr_registration',source_authority:'Federal Communications Commission',canonical_source:'fcc_asr'},asset:{owner_name:'The Towers, LLC',owner_frn:'0033815929',status_code:'C',structure_type_code:'LTOWER',application_purpose_code:'NT',structure_height_m:91.4,overall_height_agl_m:94.5,date_constructed:'09/04/2026',date_entered:'09/09/2026',last_action_date:'09/09/2026',structure_address:'S. Becker Road / IN-5286',city:'Leavenworth',state_code:'IN',zip:'47137',faa_study_number:'2026-AGL-2286-OE'},buyer:{organization_id:'8e59cab5-c220-414a-99d7-f1c6a2cb93a9',canonical_name:'The Towers, LLC',organization_type:'tower_owner',resolution_state:'resolved_scout_organization',resolution_basis:'opportunity_buyer_identity',contact_route_available:true,procurement_route_available:false},guardrail:'This is a bounded FCC Antenna Structure Registration change signal. FCC ASR registration 1333510 and its coordinates and structure attributes identify a registered antenna-structure record; Scout does not infer inspection need, maintenance due, commissioning scope, procurement, buyer intent, vendor eligibility, site access, climb authorization, or work availability. The Towers, LLC buyer resolution is separate Scout organization linkage; a durable contact route is not a documented procurement route.'};const map=model.normalizeScoutSandboxTelecomChangeMap(payload);assert.ok(map);const opp=model.buildScoutSandboxTelecomChangeOpportunity(map);assert.equal(opp.registration_number,'1333510');assert.equal(opp.contact_route_available,true);assert.equal(opp.procurement_route_available,false);const frame=renderer.buildScoutTelecomChangeRasterFrame(map,456,210,{tileUrlTemplate:'https://sandbox.invalid/map-tile/{z}/{x}/{y}.png'});assert.equal(frame.zoom,16);assert.ok(frame.tiles.length>0&&frame.tiles.length<=manifest.SCOUT_SANDBOX_MAX_EMBEDDED_RASTER_TILES);for(const tile of frame.tiles)assert.equal(manifest.isScoutSandboxRasterTileAllowed(tile.z,tile.x,tile.y),true,`telecom tile ${tile.z}/${tile.x}/${tile.y} outside allowlist`);assert.equal(frame.marker.left,228);assert.equal(frame.marker.top,105);console.log(`Scout telecom-change single-site checks passed with ${frame.tiles.length} bounded tiles.`)
''')

write(COMP/'TELECOM_CHANGE_MAP_CONTRACT.md',r'''
# Scout telecom-change single-site map contract

Status: owner-approved next opportunity family, September 16, 2026.

The first `telecom_change` exemplar is FCC ASR registration **1333510**, owned in the FCC record by **The Towers, LLC**, near Leavenworth, Indiana.

## Evidence boundary

The bounded map uses only the exact FCC ASR registration coordinate. It must not infer a parcel, compound boundary, guy-wire footprint, service radius, access envelope, ownership polygon, inspection perimeter, or climb area.

The FCC record supports the registration number, owner name/FRN, raw ASR status and structure-type codes, structure and overall AGL heights, construction/entry/action dates, structure address, FAA study number, and coordinate. Scout's opportunity spine separately supports a high-confidence `new_registration` change signal. Scout's buyer-identity layer separately resolves The Towers, LLC to a Scout tower-owner organization with a durable contact route; that is not the same claim as an FCC owner-organization foreign key and it is not a documented procurement route.

A new registration and recent construction date are reasons to qualify the asset and owner. They are **not** proof of inspection need, maintenance due, commissioning scope, active solicitation, contract availability, buyer intent, vendor eligibility, site access, climb authorization, or work available.

Raw FCC codes remain raw unless a separately authoritative decoder is wired into the bounded contract.

## Presentation

The existing card geometry and three-slide carousel remain unchanged. Exactly one media slide is the non-interactive map. The point marker denotes the FCC ASR coordinate only. The card may display registration number, raw structure-type code, overall AGL height, reported construction date, signal observation date/confidence, buyer-resolution state, and contact/procurement-route distinction.
''')

write(MIG/'20260916033000_add_telecom_change_sandbox.sql',r'''
create or replace function public.scout_get_component_sandbox_telecom_change_v1_internal()
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog'
as $function$
with event as(
  select e.id,e.registration_number,e.observed_at,e.event_type,e.importance
  from telecom.asr_change_events e
  where e.registration_number='1333510' and e.event_type='new_registration'
  order by e.observed_at desc,e.id
  limit 1
), structure as(
  select s.*
  from telecom.asr_structures s join event e on e.registration_number=s.registration_number
  where s.canonical_source='fcc_asr' and s.within_pilot=true
  order by s.last_seen_at desc nulls last,s.first_seen_at desc nulls last
  limit 1
), signal as(
  select o.*
  from scout.opportunity_search_spine o join event e on o.source_id=e.id
  where o.source_kind='telecom_change' and o.signal_kind='new_registration' and o.signal_strength='high'
  order by o.refreshed_at desc nulls last,o.observed_at desc
  limit 1
), buyer as(
  select org.id,org.canonical_name,org.organization_type
  from core.organizations org join signal sig on sig.buyer_organization_id=org.id
  where org.status='active' and org.organization_type='tower_owner'
  limit 1
)
select jsonb_build_object(
 'contract_version','telecom_change_single_site_map_v1','opportunity_type','telecom_change','candidate_key',sig.candidate_key,'event_id',e.id,'registration_number',e.registration_number,'event_type',e.event_type,'signal_strength',sig.signal_strength,'confidence',sig.confidence,'observed_at',e.observed_at,
 'site_point',jsonb_build_object('lon',st_x(s.location::geometry),'lat',st_y(s.location::geometry),'source','fcc_asr_registration','source_authority','Federal Communications Commission','canonical_source',s.canonical_source),
 'asset',jsonb_build_object('owner_name',s.owner_name,'owner_frn',s.owner_frn,'status_code',s.status_code,'structure_type_code',s.structure_type,'application_purpose_code',s.application_purpose,'structure_height_m',s.structure_height_m,'overall_height_agl_m',s.overall_height_agl_m,'date_constructed',s.date_constructed,'date_entered',s.date_entered,'last_action_date',s.last_action_date,'structure_address',s.structure_address,'city',s.structure_city,'state_code',s.structure_state,'zip',s.structure_zip,'faa_study_number',s.faa_study_number),
 'buyer',jsonb_build_object('organization_id',b.id,'canonical_name',b.canonical_name,'organization_type',b.organization_type,'resolution_state','resolved_scout_organization','resolution_basis','opportunity_buyer_identity','contact_route_available',sig.buyer_contact_status='durable_route_available','procurement_route_available',sig.procurement_status='procurement_route_available'),
 'guardrail','This is a bounded FCC Antenna Structure Registration change signal. FCC ASR registration 1333510 and its coordinates and structure attributes identify a registered antenna-structure record; Scout does not infer inspection need, maintenance due, commissioning scope, procurement, buyer intent, vendor eligibility, site access, climb authorization, or work availability. The Towers, LLC buyer resolution is separate Scout organization linkage; a durable contact route is not a documented procurement route.'
)
from event e cross join structure s cross join signal sig cross join buyer b
where s.owner_name='The Towers, LLC' and s.owner_frn='0033815929' and s.status_code='C' and s.structure_type='LTOWER' and s.application_purpose='NT' and s.date_constructed='09/04/2026' and s.date_entered='09/09/2026' and s.last_action_date='09/09/2026' and s.structure_address='S. Becker Road / IN-5286' and s.structure_city='Leavenworth' and s.structure_state='IN' and s.structure_zip='47137' and s.faa_study_number='2026-AGL-2286-OE' and sig.buyer_contact_status='durable_route_available' and sig.procurement_status='durable_contact_available';
$function$;
revoke all on function public.scout_get_component_sandbox_telecom_change_v1_internal() from public,anon,authenticated;
grant execute on function public.scout_get_component_sandbox_telecom_change_v1_internal() to service_role;
''')

# Manifest: resource v39 + single-site registry type.
manifest=SHARED/'scout_sandbox_manifest.ts'
replace_once(manifest,'export const SCOUT_SANDBOX_RESOURCE_VERSION = 38 as const','export const SCOUT_SANDBOX_RESOURCE_VERSION = 39 as const')
replace_once(manifest,"  'swppp_site',\n] as const","  'swppp_site',\n  'telecom_change',\n] as const")
replace_once(manifest,"export type ScoutSandboxOpportunityType = typeof SCOUT_SANDBOX_OPPORTUNITY_TYPES[number]","export const SCOUT_SANDBOX_SINGLE_SITE_TYPES = SCOUT_SANDBOX_BASE_OPPORTUNITY_TYPES\n\nexport type ScoutSandboxOpportunityType = typeof SCOUT_SANDBOX_OPPORTUNITY_TYPES[number]\nexport type ScoutSandboxSingleSiteType = typeof SCOUT_SANDBOX_SINGLE_SITE_TYPES[number]")
replace_once(manifest,"  swppp_site: {\n    slug: 'swppp_site',\n    label: 'SWPPP site',\n    mapKind: 'single_site',\n    markerSemantics: 'authoritative permit-location point only',\n    hostNormalization: 'strict',\n    rasterFrames: [{ width: 456, height: 210 }],\n    tileRanges: [],\n    tileCenters: singleSiteCenter(-84.521, 39.097),\n  },","  swppp_site: {\n    slug: 'swppp_site',\n    label: 'SWPPP site',\n    mapKind: 'single_site',\n    markerSemantics: 'authoritative permit-location point only',\n    hostNormalization: 'strict',\n    rasterFrames: [{ width: 456, height: 210 }],\n    tileRanges: [],\n    tileCenters: singleSiteCenter(-84.521, 39.097),\n  },\n  telecom_change: {\n    slug: 'telecom_change',\n    label: 'FCC ASR telecom change',\n    mapKind: 'single_site',\n    markerSemantics: 'exact FCC ASR registration coordinate; no service radius, access envelope, or ownership boundary implied',\n    hostNormalization: 'strict',\n    rasterFrames: [{ width: 456, height: 210 }],\n    tileRanges: [],\n    tileCenters: singleSiteCenter(-86.35352777777777, 38.20866666666667),\n  },")
replace_once(manifest,"export function isScoutSandboxPortfolioType(value: unknown): value is ScoutSandboxPortfolioType {","export function isScoutSandboxSingleSiteType(value: unknown): value is ScoutSandboxSingleSiteType {\n  return typeof value === 'string' && (SCOUT_SANDBOX_SINGLE_SITE_TYPES as readonly string[]).includes(value)\n}\n\nexport function isScoutSandboxPortfolioType(value: unknown): value is ScoutSandboxPortfolioType {")

# Shared result schema.
schema=SHARED/'scout_sandbox_contract_schema.ts'
replace_once(schema,"import { SCOUT_SANDBOX_OPPORTUNITY_TYPES } from './scout_sandbox_manifest.ts'","import { sandboxTelecomChangeMapSchema, sandboxTelecomChangeOpportunitySchema } from './scout_sandbox_telecom_change_schema.ts'\nimport { SCOUT_SANDBOX_OPPORTUNITY_TYPES } from './scout_sandbox_manifest.ts'")
replace_once(schema,"{type:'object',properties:{surface:{type:'string',enum:['scout_component_sandbox']},opportunity_type:{type:'string',enum:['swppp_site']},opportunity:sandboxSwpppSiteOpportunitySchema(),map:sandboxSwpppSiteMapSchema()},required:['surface','opportunity_type','opportunity','map'],additionalProperties:false},{type:'object',properties:{surface:{type:'string',enum:['scout_component_sandbox']},opportunity_type:{type:'string',enum:['water_utility_portfolio']}","{type:'object',properties:{surface:{type:'string',enum:['scout_component_sandbox']},opportunity_type:{type:'string',enum:['swppp_site']},opportunity:sandboxSwpppSiteOpportunitySchema(),map:sandboxSwpppSiteMapSchema()},required:['surface','opportunity_type','opportunity','map'],additionalProperties:false},{type:'object',properties:{surface:{type:'string',enum:['scout_component_sandbox']},opportunity_type:{type:'string',enum:['telecom_change']},opportunity:sandboxTelecomChangeOpportunitySchema(),map:sandboxTelecomChangeMapSchema()},required:['surface','opportunity_type','opportunity','map'],additionalProperties:false},{type:'object',properties:{surface:{type:'string',enum:['scout_component_sandbox']},opportunity_type:{type:'string',enum:['water_utility_portfolio']}")

# Contract union includes telecom for static parity.
contract=COMP/'contract.ts'
replace_once(contract,"import type { ScoutSandboxSwpppSiteOpportunity } from './swppp_site_map_model.ts'","import type { ScoutSandboxSwpppSiteOpportunity } from './swppp_site_map_model.ts'\nimport type { ScoutSandboxTelecomChangeMap, ScoutSandboxTelecomChangeOpportunity } from './telecom_change_map_model.ts'")
replace_once(contract,"export type ScoutSandboxOpportunityType = 'premium_exterior' | 'water_tank' | 'swppp_site'","export type ScoutSandboxOpportunityType = 'premium_exterior' | 'water_tank' | 'swppp_site' | 'telecom_change'")
replace_once(contract,"export type ScoutSandboxResult = ScoutSandboxPremiumExteriorResult | ScoutSandboxWaterTankResult | ScoutSandboxSwpppSiteResult","export type ScoutSandboxTelecomChangeResult = {\n  surface: 'scout_component_sandbox'\n  opportunity_type: 'telecom_change'\n  opportunity: ScoutSandboxTelecomChangeOpportunity\n  map: ScoutSandboxTelecomChangeMap\n}\n\nexport type ScoutSandboxResult = ScoutSandboxPremiumExteriorResult | ScoutSandboxWaterTankResult | ScoutSandboxSwpppSiteResult | ScoutSandboxTelecomChangeResult")

# Server: generic single-site registry replaces hardcoded branches.
index=COMP/'index.ts'
text=index.read_text()
text=text.replace("  isScoutSandboxPortfolioType,\n", "  isScoutSandboxSingleSiteType,\n  isScoutSandboxPortfolioType,\n",1)
text=text.replace("  type ScoutSandboxOpportunityType,\n  type ScoutSandboxPortfolioType,\n", "  type ScoutSandboxOpportunityType,\n  type ScoutSandboxSingleSiteType,\n  type ScoutSandboxPortfolioType,\n",1)
text=text.replace("import { assertScoutSandboxPortfolioImplementationCoverage, scoutSandboxPortfolioImplementation } from './portfolio_registry.ts'\n", "import { assertScoutSandboxPortfolioImplementationCoverage, scoutSandboxPortfolioImplementation } from './portfolio_registry.ts'\nimport { assertScoutSandboxSingleSiteImplementationCoverage, scoutSandboxSingleSiteImplementation } from './single_site_registry.ts'\n")
start=text.index('async function loadScoutSandboxOpportunity()')
end=text.index('async function loadScoutSandboxPortfolioMap',start)
new_load=r'''async function loadScoutSandboxSingleSiteMap(type: ScoutSandboxSingleSiteType) {
  const implementation = scoutSandboxSingleSiteImplementation(type)
  const { data, error } = await admin.rpc(implementation.mapRpc)
  if (error) throw new Error(`Scout sandbox ${type} map is unavailable`)
  const map = implementation.normalizeMap(data)
  if (!map) throw new Error(`Scout sandbox ${type} map did not satisfy the bounded contract`)
  return map
}

async function loadScoutSandboxSingleSiteOpportunity(type: ScoutSandboxSingleSiteType, map: any) {
  const implementation = scoutSandboxSingleSiteImplementation(type)
  if (implementation.opportunityRpc) {
    const { data, error } = await admin.rpc(implementation.opportunityRpc)
    if (error) throw new Error(`Scout sandbox ${type} opportunity is unavailable`)
    const opportunity = implementation.normalizeOpportunity?.(data)
    if (!opportunity) throw new Error(`Scout sandbox ${type} opportunity did not satisfy the bounded contract`)
    return opportunity
  }
  const opportunity = implementation.buildOpportunity?.(map)
  if (!opportunity) throw new Error(`Scout sandbox ${type} opportunity could not be built from the bounded map contract`)
  return opportunity
}

'''
text=text[:start]+new_load+text[end:]
# imports no longer needed after hardcoded loaders/branches are removed
for block in [
"import {\n  buildScoutSandboxWaterTankOpportunity,\n  normalizeScoutSandboxOpportunity,\n  normalizeScoutSandboxSingleSiteMap,\n  normalizeScoutSandboxWaterTankMap,\n  type ScoutSandboxResult,\n} from './contract.ts'\n",
"import {\n  buildScoutSandboxSwpppSiteOpportunity,\n  normalizeScoutSandboxSwpppSiteMap,\n  type ScoutSandboxSwpppSiteMap,\n} from './swppp_site_map_model.ts'\n",
"import { buildScoutSwpppSiteRasterFrame } from './swppp_site_map_renderer.ts'\n",
"import { buildScoutSingleSiteRasterFrame } from './single_site_map_renderer.ts'\n",
"import { buildScoutWaterTankRasterFrame } from './water_tank_map_renderer.ts'\n",
"import { buildScoutSwpppSiteTransport } from './swppp_site_transport.ts'\n",
]: text=text.replace(block,'')
old_frames="""  return registration.rasterFrames.map((frameSize) => {\n    if (selectedType === 'swppp_site') return buildScoutSwpppSiteRasterFrame(map, frameSize.width, frameSize.height, { tileUrlTemplate: TILE_URL_TEMPLATE })\n    if (selectedType === 'water_tank') return buildScoutWaterTankRasterFrame(map, frameSize.width, frameSize.height, { tileUrlTemplate: TILE_URL_TEMPLATE })\n    return buildScoutSingleSiteRasterFrame(map, frameSize.width, frameSize.height, { tileUrlTemplate: TILE_URL_TEMPLATE })\n  })\n"""
new_frames="""  if (!isScoutSandboxSingleSiteType(selectedType)) throw new Error(`Scout sandbox ${selectedType} has no single-site raster implementation`)\n  const implementation = scoutSandboxSingleSiteImplementation(selectedType)\n  return registration.rasterFrames.map((frameSize) =>\n    implementation.buildRasterFrame(map, frameSize.width, frameSize.height, { tileUrlTemplate: TILE_URL_TEMPLATE })\n  )\n"""
if old_frames not in text: raise RuntimeError('selectedRasterFrames anchor missing')
text=text.replace(old_frames,new_frames,1)
text=text.replace("  if (isScoutSandboxPortfolioType(selectedType)) assertScoutSandboxPortfolioImplementationCoverage()\n", "  if (isScoutSandboxPortfolioType(selectedType)) assertScoutSandboxPortfolioImplementationCoverage()\n  if (isScoutSandboxSingleSiteType(selectedType)) assertScoutSandboxSingleSiteImplementationCoverage()\n",1)
branch_start=text.index("      if (selectedType === 'swppp_site') {")
branch_end=text.index("    },\n  )",branch_start)
generic=r'''      if (!isScoutSandboxSingleSiteType(selectedType)) throw new Error(`Scout sandbox opportunity type ${selectedType} is not registered`)
      const implementation = scoutSandboxSingleSiteImplementation(selectedType)
      const map = await loadScoutSandboxSingleSiteMap(selectedType)
      const opportunity = await loadScoutSandboxSingleSiteOpportunity(selectedType, map)
      if (!implementation.identityMatches(map, opportunity)) throw new Error(`Scout sandbox ${selectedType} opportunity and map identity do not match`)
      return {
        content: [{ type: 'text', text: implementation.responseText(opportunity) }],
        structuredContent: { surface: 'scout_component_sandbox', opportunity_type: selectedType, opportunity, map: implementation.toResultMap(map) },
        _meta: { 'scout/rasterTiles': await loadEmbeddedRasterTilesForSelection(selectedType, map) },
      }
'''
text=text[:branch_start]+generic+text[branch_end:]
text=text.replace("const server = new McpServer({ name: 'Scout UI Foundation', version: '2.3.8' })","const server = new McpServer({ name: 'Scout UI Foundation', version: '2.3.9' })",1)
index.write_text(text)

# View: map routing registry + telecom presentation.
view=COMP/'view.ts'
text=view.read_text()
text=text.replace("  isScoutSandboxOpportunityType,\n  isScoutSandboxPortfolioType,\n", "  isScoutSandboxOpportunityType,\n  isScoutSandboxSingleSiteType,\n  isScoutSandboxPortfolioType,\n",1)
text=text.replace("import { scoutSandboxPortfolioViewImplementation } from './portfolio_view_registry.ts'\n", "import { scoutSandboxPortfolioViewImplementation } from './portfolio_view_registry.ts'\nimport { scoutSandboxSingleSiteViewImplementation } from './single_site_view_registry.ts'\n")
text=text.replace("import { mountScoutSingleSiteMap } from './single_site_map_renderer.ts'\n",'')
text=text.replace("import { mountScoutWaterTankMap } from './water_tank_map_mount.ts'\n",'')
text=text.replace("import { mountScoutSwpppSiteMap } from './swppp_site_map_mount.ts'\n",'')
text=text.replace("import { normalizeScoutSwpppSiteTransport } from './swppp_site_transport.ts'\n",'')
text=text.replace("import {\n  normalizeScoutSandboxOpportunity,\n  normalizeScoutSandboxSingleSiteMap,\n  normalizeScoutSandboxWaterTankMap,\n  type ScoutSandboxOpportunityType,\n  type ScoutSandboxWaterTankOpportunity,\n} from './contract.ts'", "import {\n  normalizeScoutSandboxOpportunity,\n  type ScoutSandboxOpportunityType,\n  type ScoutSandboxWaterTankOpportunity,\n} from './contract.ts'\nimport { normalizeScoutSandboxTelecomChangeOpportunity } from './telecom_change_map_model.ts'")
telecom_presentation=r'''  if (opportunityType === 'telecom_change') {
    const opportunity = normalizeScoutSandboxTelecomChangeOpportunity(value)
    if (!opportunity) { renderUnavailableOpportunity(); return }
    if (title) title.textContent = `${opportunity.name} · ASR ${opportunity.registration_number}`
    if (tier) tier.textContent = 'FCC change signal'
    if (meta) meta.textContent = `${Math.round(opportunity.signal_confidence * 100)}% Scout signal confidence  •  Observed ${formatObserved(opportunity.observed_at)}`
    if (address) address.textContent = opportunity.location_label
    if (summary) summary.textContent = `FCC structure type ${opportunity.structure_type_code}  •  ${formatNumber(opportunity.overall_height_agl_m, 1)} m overall AGL  •  FCC record reports constructed ${opportunity.date_constructed}  •  Durable contact route available; procurement route not established  •  ${opportunity.why_investigate}`
    if (guardrail) guardrail.textContent = `Scout guardrail: ${opportunity.guardrail}`
    setState(`Scout opportunity ready: FCC ASR ${opportunity.registration_number}`)
    return
  }

'''
anchor="  const opportunity = normalizeScoutSandboxOpportunity(value)\n"
if anchor not in text: raise RuntimeError('premium presentation anchor missing')
text=text.replace(anchor,telecom_presentation+anchor,1)
# Replace all single-site map branches with the view registry, preserving SWPPP diagnostics.
map_start=text.index("    } else if (opportunityType === 'swppp_site') {")
map_end=text.index("    scheduleLayoutRefresh()",map_start)
new_map=r'''    } else {
      if (!isScoutSandboxSingleSiteType(opportunityType)) {
        mapState.textContent = 'Site map unavailable'
        setState(`Scout ${opportunityType} has no registered single-site map implementation`)
        return
      }
      const implementation = scoutSandboxSingleSiteViewImplementation(opportunityType)
      const rejectObserver = opportunityType === 'swppp_site'
        ? (detail: any) => diagnostic({ rejectedField: detail.field, rejectedCheck: detail.check, receivedType: detail.actualType, receivedStringShape: detail.stringShape })
        : undefined
      const mapData = implementation.normalizeMap(value, rejectObserver)
      if (opportunityType === 'swppp_site') diagnostic({ mapNormalizer: mapData ? 'passed' : 'rejected', viewReady: false, viewError: false, initialization: 'entered' })
      if (!mapData) {
        mapState.textContent = 'Site map unavailable'
        if (opportunityType === 'swppp_site') diagnosticOverlay(mapState)
        setState(`Scout ${opportunityType} map result failed validation`)
        return
      }
      mapContainer.setAttribute('role', 'img')
      mapContainer.setAttribute('aria-label', implementation.ariaLabel(mapData))
      const mountOptions = opportunityType === 'swppp_site' ? { ...mapOptions, embeddedTiles, onDiagnostic: diagnostic } : { ...mapOptions, embeddedTiles }
      mapHandle = implementation.mount(mapContainer, mapData, mountOptions)
      if (opportunityType === 'swppp_site') diagnostic({ initialization: 'returned' })
    }
'''
text=text[:map_start]+new_map+text[map_end:]
text=text.replace("const app = new App({ name: 'scout-ui-foundation', version: '2.18.0' })","const app = new App({ name: 'scout-ui-foundation', version: '2.19.0' })",1)
view.write_text(text)

# Tests / package / design contracts.
pkg=COMP/'package.json'
replace_once(pkg,'node municipal_facilities_portfolio_map_renderer_test.mjs && node sandbox_portfolio_contract_test.mjs','node municipal_facilities_portfolio_map_renderer_test.mjs && node telecom_change_map_renderer_test.mjs && node sandbox_portfolio_contract_test.mjs')
reg=COMP/'sandbox_registry_contract_test.mjs'
text=reg.read_text()
text=text.replace("const [component, contractGateway, connectGateway, view, viewRegistry] = await Promise.all([","const [component, contractGateway, connectGateway, view, viewRegistry, singleSiteRegistry, singleSiteViewRegistry] = await Promise.all([",1)
text=text.replace("  readFile(new URL('portfolio_view_registry.ts', directory), 'utf8'),\n])","  readFile(new URL('portfolio_view_registry.ts', directory), 'utf8'),\n  readFile(new URL('single_site_registry.ts', directory), 'utf8'),\n  readFile(new URL('single_site_view_registry.ts', directory), 'utf8'),\n])",1)
text=text.replace("assert.ok(component.includes('scoutSandboxPortfolioImplementation'))","assert.ok(component.includes('scoutSandboxPortfolioImplementation'))\nassert.ok(component.includes('scoutSandboxSingleSiteImplementation'))\nassert.ok(view.includes('scoutSandboxSingleSiteViewImplementation'))\nfor (const type of manifest.SCOUT_SANDBOX_SINGLE_SITE_TYPES) {\n  assert.ok(singleSiteRegistry.includes(`${type}:`), `single-site runtime registry missing ${type}`)\n  assert.ok(singleSiteViewRegistry.includes(`${type}:`), `single-site view registry missing ${type}`)\n}",1)
reg.write_text(text)
pre=COMP/'sandbox_predeploy_smoke_test.mjs'
text=pre.read_text()
# Only add string invariants if not already present.
needle="assert.ok(component.includes('scoutSandboxPortfolioImplementation'))"
if needle in text:text=text.replace(needle,needle+"\nassert.ok(component.includes('scoutSandboxSingleSiteImplementation'))\nassert.ok(component.includes('assertScoutSandboxSingleSiteImplementationCoverage'))",1)
pre.write_text(text)
# Design/map doctrine additions.
for path,section in [
(COMP/'DESIGN_CONTRACT.md',"""\n## Telecom-change single-site extension (owner-approved 2026-09-16)\n\n`telecom_change` is approved as the next bounded single-site opportunity family. Its first exemplar is FCC ASR registration 1333510 / The Towers, LLC near Leavenworth, Indiana. The existing card geometry and three-slide carousel remain unchanged; exactly one slide is the non-interactive FCC registration-point map. Raw FCC codes may be displayed as codes but must not be silently decoded without authoritative support.\n"""),
(COMP/'MAP_CONTRACT.md',"""\n## Telecom-change single-site contract (owner-approved 2026-09-16)\n\nThe `telecom_change` implementation is governed by `TELECOM_CHANGE_MAP_CONTRACT.md`. The first exemplar uses the exact FCC ASR registration coordinate for registration 1333510. No parcel, compound, service radius, access envelope, guy-wire footprint, ownership boundary, inspection perimeter, or climb area may be inferred. New registration/recent construction are qualification signals only; they do not prove inspection need, procurement, buyer intent, access, or work availability.\n""")]:
    existing=path.read_text()
    if section.strip().split('\n')[0] not in existing:path.write_text(existing.rstrip()+"\n"+section)

print('Applied telecom single-site implementation.')
