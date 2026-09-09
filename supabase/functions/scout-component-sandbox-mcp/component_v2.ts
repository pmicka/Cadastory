export type SandboxMapTarget = {
  kind: 'property' | 'group'
  key: string
  label: string
  scope_count: number
  min_lon: number
  min_lat: number
  max_lon: number
  max_lat: number
}

function safeJson(value: unknown) {
  return JSON.stringify(value)
    .replace(/</g, '\\u003c')
    .replace(/>/g, '\\u003e')
    .replace(/&/g, '\\u0026')
}

export function buildComponentSandboxHtml(targets: SandboxMapTarget[] = []) {
  const targetJson = safeJson(targets)
  return String.raw`<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover" />
<meta name="color-scheme" content="light dark" />
<title>Scout component sandbox</title>
<style>
:root{color-scheme:light dark;--card:light-dark(#fff,#1c1f1c);--subtle:light-dark(#f6f8f5,#252925);--media-a:light-dark(#dfe7dc,#2f3930);--media-b:light-dark(#e7e1d5,#39352e);--media-c:light-dark(#dce5e8,#2d383c);--text:light-dark(#171b17,#f2f5f1);--muted:light-dark(#747d73,#aeb6ad);--line:light-dark(#dde2da,#3a4039);--accent:light-dark(#4d6b52,#7fa586);--accent-soft:light-dark(#eef3ed,#273228);--button:light-dark(#263128,#dfe9df);--button-text:light-dark(#fff,#182019);font-family:ui-sans-serif,system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
*{box-sizing:border-box}html,body{margin:0;padding:0;background:transparent;color:var(--text)}body{padding:10px 6px 12px}.shell{max-width:520px;margin:0 auto}.card{background:var(--card);border:1px solid var(--line);border-radius:22px;overflow:hidden;box-shadow:0 10px 28px rgba(20,28,20,.08)}.inner{padding:18px 18px 16px}.top{display:flex;align-items:center;gap:9px}.dot{width:10px;height:10px;border-radius:50%;background:var(--accent);flex:none}.brand{font-size:14px;font-weight:700}.preview{font-size:12px;color:var(--muted);margin-top:1px}.more{margin-left:auto;width:36px;height:36px;border:1px solid var(--line);border-radius:50%;background:var(--subtle);color:var(--text);font-size:19px;line-height:1;display:grid;place-items:center}.rule{height:1px;background:var(--line);margin:16px 0 18px}.title{font-size:22px;line-height:1.15;letter-spacing:-.02em;font-weight:750;margin:0 0 11px}.meta{display:flex;align-items:center;gap:8px;flex-wrap:wrap;font-size:12px;color:var(--muted)}.pill{background:var(--accent-soft);color:var(--accent);border-radius:999px;padding:6px 10px;font-weight:700}.label{font-size:12px;font-weight:700;margin:20px 0 8px}.carousel{display:flex;gap:10px;overflow-x:auto;scroll-snap-type:x mandatory;scrollbar-width:none;border-radius:16px;touch-action:pan-x}.carousel::-webkit-scrollbar{display:none}.slide{position:relative;min-width:86%;height:200px;border-radius:16px;scroll-snap-align:start;display:grid;place-items:center;text-align:center;color:var(--muted);overflow:hidden}.slide:nth-child(1){background:var(--media-a)}.slide:nth-child(2){background:var(--media-b)}.slide:nth-child(3){background:var(--media-c)}.diamond{width:18px;height:18px;border:2px solid currentColor;transform:rotate(45deg);position:absolute;left:18px;top:18px}.circle{width:44px;height:44px;border-radius:50%;background:color-mix(in srgb,var(--card) 76%,transparent);margin:0 auto 16px}.slide b{display:block;font-size:13px;color:var(--text);font-weight:600}.slide small{display:block;font-size:11px;margin-top:6px}.counter{position:absolute;right:12px;bottom:12px;background:color-mix(in srgb,var(--text) 88%,transparent);color:var(--card);border-radius:999px;padding:5px 9px;font-size:11px;font-weight:700;z-index:4}.map-slide{display:block}.basemap{position:absolute;inset:0;overflow:hidden;background:var(--media-b);pointer-events:none}.basemap img{position:absolute;width:256px;height:256px;max-width:none;user-select:none;pointer-events:none}.map-attribution{position:absolute;left:7px;bottom:7px;z-index:4;background:rgba(255,255,255,.86);color:#303530;border-radius:5px;padding:2px 5px;font-size:8px;line-height:1.25}.map-attribution a{color:inherit}.pager{display:flex;justify-content:center;gap:7px;margin-top:10px}.page-dot{width:7px;height:7px;border-radius:50%;background:var(--line)}.page-dot.on{background:var(--accent)}.map-frame-note{min-height:17px;text-align:center;font-size:10px;color:var(--muted);margin-top:7px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.copy{font-size:13px;line-height:1.55;color:color-mix(in srgb,var(--text) 78%,var(--muted));margin:18px 0 20px}.select{width:100%;min-height:46px;border:1px solid var(--line);border-radius:12px;background:var(--subtle);color:var(--text);padding:0 13px;font:inherit;font-size:13px}.row{display:flex;align-items:center;gap:14px;margin-top:18px}.grow{flex:1;min-width:0}.row-title{font-size:13px;font-weight:600}.row-sub{font-size:11px;color:var(--muted);margin-top:4px}.switch{width:50px;height:30px;border:0;border-radius:999px;background:var(--accent);padding:3px;cursor:pointer;flex:none}.knob{width:24px;height:24px;border-radius:50%;background:#fff;transform:translateX(20px);transition:transform .16s ease}.switch[aria-checked="false"]{background:var(--line)}.switch[aria-checked="false"] .knob{transform:translateX(0)}.timeline-head{display:flex;justify-content:space-between;gap:12px;align-items:center;margin-top:22px}.timeline-value{font-size:12px;color:var(--accent)}input[type=range]{width:100%;accent-color:var(--accent);margin:14px 0 3px}.ticks{display:grid;grid-template-columns:repeat(6,1fr);font-size:10px;color:var(--muted)}.ticks span{text-align:center}.ticks span:first-child{text-align:left}.ticks span:last-child{text-align:right}.ticks .active{color:var(--accent);font-weight:700}.chips{display:flex;gap:8px;flex-wrap:wrap}.chip{border:1px solid var(--line);background:var(--subtle);border-radius:999px;padding:7px 11px;font-size:11px;color:var(--muted)}.footer{border-top:1px solid var(--line);padding:16px 18px;display:grid;grid-template-columns:1fr 1.25fr;gap:10px}.action{min-height:44px;border-radius:12px;border:1px solid var(--line);background:var(--subtle);color:var(--text);font:inherit;font-size:12px;font-weight:700;cursor:pointer}.action.primary{background:var(--button);border-color:var(--button);color:var(--button-text)}.live{padding:0 18px 14px;min-height:20px;color:var(--muted);font-size:11px}button:focus-visible,select:focus-visible,input:focus-visible{outline:3px solid var(--accent);outline-offset:2px}@media(max-width:360px){.inner{padding-left:14px;padding-right:14px}.footer{padding-left:14px;padding-right:14px}.slide{min-width:92%;height:190px}.title{font-size:20px}}@media(prefers-reduced-motion:reduce){*{scroll-behavior:auto!important;transition:none!important}}
</style>
</head>
<body>
<main class="shell" aria-label="Scout owner component sandbox"><section class="card"><div class="inner"><div class="top"><span class="dot" aria-hidden="true"></span><div><div class="brand">Scout</div><div class="preview">Component preview</div></div><button class="more" aria-label="More preview options">•••</button></div><div class="rule"></div><h1 class="title">Example opportunity card</h1><div class="meta"><span class="pill">Worth investigating</span><span>Updated 2h ago</span><span aria-hidden="true">•</span><span>4 evidence items</span></div><div class="label">Media</div><div class="carousel" id="carousel" aria-label="Placeholder image carousel"><div class="slide"><span class="diamond" aria-hidden="true"></span><div><div class="circle"></div><b>Placeholder image 1</b><small>Swipe horizontally</small></div><span class="counter">1 / 3</span></div><div class="slide map-slide"><div class="basemap" id="basemap" role="img" aria-label="Static exemplar basemap framing test"></div><div class="map-attribution">© <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noreferrer">OpenStreetMap</a> contributors</div><span class="counter">2 / 3</span></div><div class="slide"><span class="diamond" aria-hidden="true"></span><div><div class="circle"></div><b>Placeholder image 3</b><small>Swipe horizontally</small></div><span class="counter">3 / 3</span></div></div><div class="pager" aria-hidden="true"><i class="page-dot on"></i><i class="page-dot"></i><i class="page-dot"></i></div><div class="map-frame-note" id="mapFrameNote">Map frame: loading exemplar…</div><p class="copy">Lorem ipsum dolor sit amet, consectetur adipiscing elit. Integer posuere erat a ante venenatis dapibus posuere velit aliquet.</p><div class="label">View</div><select class="select" id="viewSelect" aria-label="Preview view"><option>Evidence summary</option><option>Access summary</option><option>Timing summary</option></select><div class="row"><div class="grow"><div class="row-title">Include lower-confidence signals</div><div class="row-sub">Useful for testing progressive disclosure.</div></div><button class="switch" id="signalSwitch" role="switch" aria-checked="true" aria-label="Include lower-confidence signals"><span class="knob"></span></button></div><div class="timeline-head"><span class="label" style="margin:0">Evidence timeline</span><span class="timeline-value" id="timelineValue">Past 90 days</span></div><input id="timeline" type="range" min="0" max="5" step="1" value="2" aria-label="Evidence timeline range" /><div class="ticks" id="ticks"><span>1y</span><span>6m</span><span class="active">90d</span><span>30d</span><span>7d</span><span>Now</span></div><div class="label">Standard controls</div><div class="chips"><span class="chip">Evidence</span><span class="chip">Access</span><span class="chip">Timing</span></div></div><div class="footer"><button class="action" id="save">Save for later</button><button class="action primary" id="investigate">Investigate</button></div><div class="live" id="live" aria-live="polite">Owner-only preview · widget state restores after host remounts.</div></section></main>
<script id="map-targets" type="application/json">${targetJson}</script>
<script>
const carousel=document.getElementById('carousel');
const slides=[...carousel.children];
const dots=[...document.querySelectorAll('.page-dot')];
const sw=document.getElementById('signalSwitch');
const timeline=document.getElementById('timeline');
const timelineValue=document.getElementById('timelineValue');
const viewSelect=document.getElementById('viewSelect');
const values=['Past year','Past 6 months','Past 90 days','Past 30 days','Past 7 days','Current'];
let mapTargets=[];try{mapTargets=JSON.parse(document.getElementById('map-targets').textContent||'[]')}catch{}
const fallbackTarget={kind:'property',key:'fallback:louisville',label:'Louisville fallback frame',scope_count:1,min_lon:-85.7600,max_lon:-85.7570,min_lat:38.2510,max_lat:38.2540};
const propertyTargets=mapTargets.filter(t=>t&&t.kind==='property');
const groupTargets=mapTargets.filter(t=>t&&t.kind==='group');
let mapTarget=null;
let hostGlobalsSeen=false;
let restoring=false;
let state={__v:1,mapTargetKey:null,slideIndex:0,includeLowConfidence:true,timelineIndex:2,viewIndex:0};

function mergeState(raw){
  if(!raw||typeof raw!=='object'||Array.isArray(raw))return;
  if(typeof raw.mapTargetKey==='string')state.mapTargetKey=raw.mapTargetKey;
  if(Number.isInteger(raw.slideIndex)&&raw.slideIndex>=0&&raw.slideIndex<slides.length)state.slideIndex=raw.slideIndex;
  if(typeof raw.includeLowConfidence==='boolean')state.includeLowConfidence=raw.includeLowConfidence;
  if(Number.isInteger(raw.timelineIndex)&&raw.timelineIndex>=0&&raw.timelineIndex<values.length)state.timelineIndex=raw.timelineIndex;
  if(Number.isInteger(raw.viewIndex)&&raw.viewIndex>=0&&raw.viewIndex<viewSelect.options.length)state.viewIndex=raw.viewIndex;
}
function persist(patch){
  state={...state,...patch,__v:1};
  if(!hostGlobalsSeen)return;
  try{window.openai?.setWidgetState?.(state)}catch{}
}
function randomTarget(){
  const buckets=[propertyTargets,groupTargets].filter(b=>b.length);
  if(!buckets.length)return fallbackTarget;
  const bucket=buckets[Math.floor(Math.random()*buckets.length)];
  return bucket[Math.floor(Math.random()*bucket.length)]||fallbackTarget;
}
function resolveTarget(){
  const restored=mapTargets.find(t=>t&&t.key===state.mapTargetKey);
  if(restored){mapTarget=restored;return}
  mapTarget=randomTarget();
  state.mapTargetKey=mapTarget.key;
  persist({mapTargetKey:mapTarget.key});
}
function restoreControls(){
  restoring=true;
  sw.setAttribute('aria-checked',String(state.includeLowConfidence));
  timeline.value=String(state.timelineIndex);
  timelineValue.textContent=values[state.timelineIndex];
  [...document.querySelectorAll('#ticks span')].forEach((n,j)=>n.classList.toggle('active',j===state.timelineIndex));
  viewSelect.selectedIndex=state.viewIndex;
  requestAnimationFrame(()=>{
    const targetSlide=slides[state.slideIndex]||slides[0];
    carousel.scrollLeft=targetSlide?targetSlide.offsetLeft:0;
    updatePager(false);
    restoring=false;
  });
}
function applyHostState(raw){
  const beforeKey=state.mapTargetKey;
  mergeState(raw);
  resolveTarget();
  restoreControls();
  if(beforeKey!==state.mapTargetKey)requestAnimationFrame(renderStaticMap);
}
function initialize(){
  const initial=window.openai?.widgetState;
  if(initial&&typeof initial==='object')mergeState(initial);
  resolveTarget();
  restoreControls();
  requestAnimationFrame(renderStaticMap);
}
window.addEventListener('openai:set_globals',(event)=>{
  const globals=event?.detail?.globals;
  if(!globals)return;
  hostGlobalsSeen=true;
  if(globals.widgetState&&typeof globals.widgetState==='object')applyHostState(globals.widgetState);
  else{
    if(!mapTarget)resolveTarget();
    persist({mapTargetKey:mapTarget?.key||state.mapTargetKey});
  }
},{passive:true});

function updatePager(save=true){
  let best=0,bestD=Infinity;
  for(let i=0;i<slides.length;i++){
    const d=Math.abs(slides[i].offsetLeft-carousel.scrollLeft);
    if(d<bestD){bestD=d;best=i}
  }
  dots.forEach((d,i)=>d.classList.toggle('on',i===best));
  if(save&&!restoring&&best!==state.slideIndex)persist({slideIndex:best});
}
let scrollFrame=0;
carousel.addEventListener('scroll',()=>{
  cancelAnimationFrame(scrollFrame);
  scrollFrame=requestAnimationFrame(()=>updatePager(true));
},{passive:true});

function clampLat(lat){return Math.max(-85.05112878,Math.min(85.05112878,lat))}
function worldX(lon){return(lon+180)/360}
function worldY(lat){const r=clampLat(lat)*Math.PI/180;return(1-Math.log(Math.tan(r)+1/Math.cos(r))/Math.PI)/2}
function expandedBounds(t){
  let minLon=Number(t.min_lon),maxLon=Number(t.max_lon),minLat=Number(t.min_lat),maxLat=Number(t.max_lat);
  if(![minLon,maxLon,minLat,maxLat].every(Number.isFinite))return expandedBounds(fallbackTarget);
  if(maxLon<minLon){const q=minLon;minLon=maxLon;maxLon=q}
  if(maxLat<minLat){const q=minLat;minLat=maxLat;maxLat=q}
  const centerLat=(minLat+maxLat)/2;
  const metersPerDegLat=111320;
  const metersPerDegLon=Math.max(15000,111320*Math.cos(centerLat*Math.PI/180));
  const minWidthM=t.kind==='group'?1800:180;
  const minHeightM=t.kind==='group'?1400:150;
  const widthM=(maxLon-minLon)*metersPerDegLon;
  const heightM=(maxLat-minLat)*metersPerDegLat;
  if(widthM<minWidthM){const add=(minWidthM-widthM)/metersPerDegLon/2;minLon-=add;maxLon+=add}
  if(heightM<minHeightM){const add=(minHeightM-heightM)/metersPerDegLat/2;minLat-=add;maxLat+=add}
  const pad=t.kind==='group'?.12:.05;
  const lonPad=(maxLon-minLon)*pad;
  const latPad=(maxLat-minLat)*pad;
  return{minLon:minLon-lonPad,maxLon:maxLon+lonPad,minLat:minLat-latPad,maxLat:maxLat+latPad}
}
function fitZoom(b,w,h,kind){
  const maxZoom=kind==='group'?13:18,minZoom=5;
  const xSpan=Math.abs(worldX(b.maxLon)-worldX(b.minLon));
  const ySpan=Math.abs(worldY(b.maxLat)-worldY(b.minLat));
  const xFit=kind==='group'?.9:.94,yFit=kind==='group'?.82:.90;
  for(let z=maxZoom;z>=minZoom;z--){const world=256*Math.pow(2,z);if(xSpan*world<=w*xFit&&ySpan*world<=h*yFit)return z}
  return minZoom
}
function renderStaticMap(){
  if(!mapTarget)return;
  const map=document.getElementById('basemap');const note=document.getElementById('mapFrameNote');if(!map)return;
  map.innerHTML='';
  const w=Math.max(280,map.clientWidth||0),h=Math.max(180,map.clientHeight||0);
  const b=expandedBounds(mapTarget);const z=fitZoom(b,w,h,mapTarget.kind);
  const centerLon=(b.minLon+b.maxLon)/2,centerLat=(b.minLat+b.maxLat)/2;
  const world=256*Math.pow(2,z),centerPxX=worldX(centerLon)*world,centerPxY=worldY(centerLat)*world;
  const left=centerPxX-w/2,top=centerPxY-h/2;
  const startX=Math.floor(left/256)-1,endX=Math.floor((left+w)/256)+1,startY=Math.floor(top/256)-1,endY=Math.floor((top+h)/256)+1;
  const n=Math.pow(2,z);
  for(let tx=startX;tx<=endX;tx++)for(let ty=startY;ty<=endY;ty++){
    if(ty<0||ty>=n)continue;
    const wrappedX=((tx%n)+n)%n;
    const img=document.createElement('img');img.alt='';img.draggable=false;img.decoding='async';img.src='https://tile.openstreetmap.org/'+z+'/'+wrappedX+'/'+ty+'.png';img.style.left=(tx*256-left)+'px';img.style.top=(ty*256-top)+'px';map.appendChild(img)
  }
  const scope=mapTarget.kind==='group'?String(mapTarget.scope_count)+' regional properties':'single property';
  note.textContent='Map frame: '+mapTarget.label+' · '+scope+' · z'+z;
  map.setAttribute('aria-label','Static basemap framed to '+mapTarget.label+' at zoom '+z)
}

sw.addEventListener('click',()=>{
  const next=sw.getAttribute('aria-checked')!=='true';sw.setAttribute('aria-checked',String(next));persist({includeLowConfidence:next});document.getElementById('live').textContent=next?'Lower-confidence signals included in this preview.':'Lower-confidence signals hidden in this preview.'
});
timeline.addEventListener('input',()=>{
  const i=Number(timeline.value);timelineValue.textContent=values[i];[...document.querySelectorAll('#ticks span')].forEach((n,j)=>n.classList.toggle('active',j===i));persist({timelineIndex:i})
});
viewSelect.addEventListener('change',()=>persist({viewIndex:viewSelect.selectedIndex}));
document.getElementById('save').addEventListener('click',()=>{document.getElementById('live').textContent='Preview-only save state selected; nothing was persisted to Scout.'});
document.getElementById('investigate').addEventListener('click',()=>{document.getElementById('live').textContent='Preview-only investigate state selected; no Scout workflow was started.'});

initialize();
let resizeTimer=null;window.addEventListener('resize',()=>{clearTimeout(resizeTimer);resizeTimer=setTimeout(renderStaticMap,120)});
</script>
</body></html>`
}
