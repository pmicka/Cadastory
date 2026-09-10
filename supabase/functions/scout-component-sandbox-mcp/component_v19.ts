import {
  buildComponentSandboxHtml as buildComponentSandboxHtmlV17,
  type SandboxMapMember,
  type SandboxMapTarget as SandboxMapTargetV17,
  type SandboxMapTerritory,
  type SandboxContactCard,
  type SandboxContactRoute,
} from './component_v17.ts'

export type { SandboxMapMember, SandboxMapTerritory, SandboxContactCard, SandboxContactRoute }
export type SandboxMapTarget = SandboxMapTargetV17

function replaceRequired(source:string, needle:string, replacement:string, label:string){
  if(!source.includes(needle))throw new Error('Scout component sandbox v19 transform failed: '+label)
  return source.replace(needle,replacement)
}

const oldFirstSlide='<div class="slide"><span class="diamond" aria-hidden="true"></span><div><b>Placeholder image 1</b><small>Swipe horizontally</small></div><span class="counter">1 / 3</span></div>'
const newFirstSlide='<div class="slide property-image-slide" id="propertyImageSlide"><div class="property-image-canvas" id="propertyImageCanvas" role="img" aria-label="Aerial property imagery"><div class="property-image-empty" id="propertyImageEmpty"><b>Aerial property view</b><span>Loading exemplar imagery…</span></div></div><div class="property-image-label" id="propertyImageLabel">Aerial property view</div><div class="property-image-attribution" id="propertyImageAttribution">USGS · USDA · The National Map</div><span class="counter">1 / 3</span></div>'

const imageryCss=`.property-image-slide{display:block!important;background:var(--media-a)!important;text-align:left!important}.property-image-canvas{position:absolute;inset:0;overflow:hidden;background:var(--media-a)}.property-image-canvas>img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;max-width:none;user-select:none;pointer-events:none}.property-image-canvas::after{content:'';position:absolute;inset:0;pointer-events:none;background:linear-gradient(to bottom,rgba(0,0,0,.24),transparent 30%,transparent 62%,rgba(0,0,0,.34))}.property-image-empty{position:absolute;inset:0;z-index:2;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;padding:24px;background:var(--media-a);color:var(--muted)}.property-image-empty[hidden]{display:none!important}.property-image-empty b{font-size:12px!important;color:var(--text)!important;font-weight:700!important}.property-image-empty span{font-size:9px;line-height:1.35;margin-top:5px;max-width:270px}.property-image-label{position:absolute;left:10px;top:10px;z-index:4;max-width:72%;padding:5px 7px;border-radius:7px;background:rgba(15,18,15,.72);color:#fff;font-size:9px;line-height:1.2;font-weight:750;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.property-image-attribution{position:absolute;left:8px;bottom:8px;z-index:4;max-width:70%;padding:3px 5px;border-radius:5px;background:rgba(255,255,255,.88);color:#303530;font-size:7px;line-height:1.2;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}`

const renderStaticMarker='function renderStaticMap(){if(!mapTarget)return;renderContactCard();const map='
const imageryHelpers=`const SCOUT_EXEMPLAR_IMAGERY_URL='https://imagery.nationalmap.gov/arcgis/rest/services/USGSNAIPImagery/ImageServer/exportImage';
function exemplarPropertyImageBounds(target,aspect){
  let minLon=Number(target?.min_lon),maxLon=Number(target?.max_lon),minLat=Number(target?.min_lat),maxLat=Number(target?.max_lat);
  if(![minLon,maxLon,minLat,maxLat].every(Number.isFinite))return null;
  if(maxLon<minLon){const v=minLon;minLon=maxLon;maxLon=v}if(maxLat<minLat){const v=minLat;minLat=maxLat;maxLat=v}
  const centerLon=(minLon+maxLon)/2,centerLat=(minLat+maxLat)/2,metersPerDegLat=111320,metersPerDegLon=Math.max(15000,111320*Math.cos(centerLat*Math.PI/180));
  let widthM=Math.max((maxLon-minLon)*metersPerDegLon,150),heightM=Math.max((maxLat-minLat)*metersPerDegLat,105);
  widthM*=1.28;heightM*=1.28;
  const targetAspect=Math.max(1,Number(aspect)||2.4),currentAspect=widthM/heightM;
  if(currentAspect<targetAspect)widthM=heightM*targetAspect;else heightM=widthM/targetAspect;
  const halfLon=widthM/metersPerDegLon/2,halfLat=heightM/metersPerDegLat/2;
  return{minLon:centerLon-halfLon,maxLon:centerLon+halfLon,minLat:centerLat-halfLat,maxLat:centerLat+halfLat};
}
function renderPropertyImage(){
  const canvas=document.getElementById('propertyImageCanvas'),empty=document.getElementById('propertyImageEmpty'),label=document.getElementById('propertyImageLabel'),attribution=document.getElementById('propertyImageAttribution');
  if(!canvas||!empty||!label||!attribution)return;
  canvas.querySelectorAll('img').forEach(node=>node.remove());
  const key=String(mapTarget?.key||''),isExemplarProperty=mapTarget?.kind==='property'&&!key.startsWith('fallback:');
  label.textContent=isExemplarProperty?(mapTarget?.label||'Aerial property view'):'Property imagery';
  if(!isExemplarProperty){empty.hidden=false;empty.innerHTML='<b>No single property image</b><span>Portfolio and fallback frames do not fabricate a representative property. Imagery enrichment is limited to single-property exemplars.</span>';attribution.hidden=true;canvas.setAttribute('aria-label','Property imagery unavailable for this non-property exemplar');return}
  const w=Math.max(320,canvas.clientWidth||484),h=Math.max(180,canvas.clientHeight||200),bounds=exemplarPropertyImageBounds(mapTarget,w/h);
  if(!bounds){empty.hidden=false;empty.innerHTML='<b>Imagery unavailable</b><span>This exemplar does not have a defensible geographic frame for imagery retrieval.</span>';attribution.hidden=true;return}
  empty.hidden=false;empty.innerHTML='<b>Aerial property view</b><span>Loading current exemplar imagery…</span>';attribution.hidden=false;
  const dpr=Math.min(2,Math.max(1,Number(window.devicePixelRatio)||1)),sizeW=Math.min(1200,Math.round(w*dpr)),sizeH=Math.min(600,Math.round(h*dpr));
  const params=new URLSearchParams({f:'image',bbox:[bounds.minLon,bounds.minLat,bounds.maxLon,bounds.maxLat].map(v=>v.toFixed(8)).join(','),bboxSR:'4326',imageSR:'4326',size:sizeW+','+sizeH,format:'jpg',compressionQuality:'82',interpolation:'RSP_BilinearInterpolation',renderingRule:JSON.stringify({rasterFunction:'NaturalColor'})});
  const img=document.createElement('img');img.alt='';img.decoding='async';img.loading='eager';img.referrerPolicy='no-referrer';
  img.onload=()=>{empty.hidden=true;canvas.setAttribute('aria-label','Aerial orthoimagery for '+String(mapTarget?.label||'property exemplar')+'. Source: USGS and USDA, The National Map.')};
  img.onerror=()=>{img.remove();empty.hidden=false;empty.innerHTML='<b>Imagery unavailable</b><span>The external orthoimagery service did not return an image for this exemplar.</span>';attribution.hidden=true;canvas.setAttribute('aria-label','Aerial imagery unavailable for '+String(mapTarget?.label||'property exemplar'))};
  img.src=SCOUT_EXEMPLAR_IMAGERY_URL+'?'+params.toString();canvas.prepend(img);
}
function renderStaticMap(){if(!mapTarget)return;renderPropertyImage();renderContactCard();const map=`

export function buildComponentSandboxHtml(targets: SandboxMapTarget[] = []) {
  let html=buildComponentSandboxHtmlV17(targets as unknown as SandboxMapTargetV17[])
  html=replaceRequired(html,oldFirstSlide,newFirstSlide,'first carousel tile exemplar imagery')
  html=replaceRequired(html,'</style>',imageryCss+'</style>','exemplar imagery CSS')
  html=replaceRequired(html,renderStaticMarker,imageryHelpers,'exemplar imagery render lifecycle')
  html=html.replace('Owner-only preview · resolved assets use numbered circles; documented service territory uses bounded area fill; unresolved scope is labeled without synthetic sites; widget state survives host remounts.','Owner-only preview · single-property exemplars load aerial imagery on demand without Scout image storage; resolved assets and documented territory remain bounded; widget state survives host remounts.')
  return html
}
