import {
  buildComponentSandboxHtml as buildBaselineHtml,
  type SandboxMapMember,
  type SandboxMapTarget,
  type SandboxMapTerritory,
  type SandboxContactCard,
  type SandboxContactRoute,
} from 'https://raw.githubusercontent.com/pmicka/Cadastory/19374bc7b2bb389dea2191c8be2a82c1b1fbc923/supabase/functions/scout-component-sandbox-mcp/component_v17.ts'

export type { SandboxMapMember, SandboxMapTerritory, SandboxContactCard, SandboxContactRoute }

const OLD_FIRST_SLIDE='<div class="slide"><span class="diamond" aria-hidden="true"></span><div><b>Placeholder image 1</b><small>Swipe horizontally</small></div><span class="counter">1 / 3</span></div>'
const IMAGE_ORIGIN='https://imagery.nationalmap.gov'
const EXPORT_URL=IMAGE_ORIGIN+'/arcgis/rest/services/USGSNAIPImagery/ImageServer/exportImage'

function escapeHtml(value:string){
  return value.replace(/[&<>"']/g,ch=>({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[ch]||ch))
}

function staticImageUrl(target:SandboxMapTarget){
  let minLon=Number(target.min_lon),minLat=Number(target.min_lat),maxLon=Number(target.max_lon),maxLat=Number(target.max_lat)
  if(![minLon,minLat,maxLon,maxLat].every(Number.isFinite))return null
  if(maxLon<minLon)[minLon,maxLon]=[maxLon,minLon]
  if(maxLat<minLat)[minLat,maxLat]=[maxLat,minLat]
  const lonPad=Math.max((maxLon-minLon)*0.35,0.0006)
  const latPad=Math.max((maxLat-minLat)*0.35,0.00045)
  const params=new URLSearchParams({
    f:'image',
    bbox:[minLon-lonPad,minLat-latPad,maxLon+lonPad,maxLat+latPad].map(v=>v.toFixed(8)).join(','),
    bboxSR:'4326',
    imageSR:'4326',
    size:'1200,600',
    format:'jpg',
    compressionQuality:'82',
    interpolation:'RSP_BilinearInterpolation',
    renderingRule:JSON.stringify({rasterFunction:'NaturalColor'})
  })
  return EXPORT_URL+'?'+params.toString()
}

export function buildComponentSandboxHtml(targets:SandboxMapTarget[]=[]){
  let html=buildBaselineHtml(targets)
  const exemplar=targets.find(target=>target.kind==='property'&&!String(target.key||'').startsWith('fallback:'))
  if(!exemplar)return html
  const src=staticImageUrl(exemplar)
  if(!src||!html.includes(OLD_FIRST_SLIDE))return html
  const label=escapeHtml(String(exemplar.label||'Property exemplar'))
  const slide='<div class="slide scout-static-exemplar-image"><img src="'+escapeHtml(src)+'" alt="Aerial orthoimagery for '+label+'" referrerpolicy="no-referrer"><div class="scout-static-exemplar-label">'+label+'</div><div class="scout-static-exemplar-attribution">USGS · USDA · The National Map</div><span class="counter">1 / 3</span></div>'
  html=html.replace(OLD_FIRST_SLIDE,slide)
  const css='.scout-static-exemplar-image{display:block!important;overflow:hidden!important;background:var(--media-a)!important;text-align:left!important}.scout-static-exemplar-image>img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;max-width:none;pointer-events:none;user-select:none}.scout-static-exemplar-label{position:absolute;left:10px;top:10px;z-index:3;max-width:72%;padding:5px 7px;border-radius:7px;background:rgba(15,18,15,.72);color:#fff;font-size:9px;font-weight:750;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.scout-static-exemplar-attribution{position:absolute;left:8px;bottom:8px;z-index:3;padding:3px 5px;border-radius:5px;background:rgba(255,255,255,.88);color:#303530;font-size:7px;line-height:1.2}'
  if(html.includes('</style>'))html=html.replace('</style>',css+'</style>')
  return html
}
