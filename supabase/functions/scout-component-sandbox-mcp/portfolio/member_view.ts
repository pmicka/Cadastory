import { buildPortfolioFrame } from './frame.ts'
import { mountPortfolioSelector } from './selector.ts'
// Caller supplies a separate transparent marker layer above its raster canvas.
export function mountPortfolioMembers(controls:HTMLElement,markerLayer:HTMLElement,value:unknown,width:number) {
  let frame=buildPortfolioFrame(value,width,210,'/{z}/{x}/{y}.png'),selectedId='',destroyed=false
  const paint=()=>{
    if(destroyed)return
    markerLayer.replaceChildren();markerLayer.style.pointerEvents='none'
    for(const marker of [...frame.markers].sort((a,b)=>Number(a.id===selectedId)-Number(b.id===selectedId))) {
      const dot=document.createElement('span'),selected=marker.id===selectedId
      dot.dataset.memberId=marker.id;dot.setAttribute('aria-hidden','true')
      dot.style.cssText=`position:absolute;left:${marker.left}px;top:${marker.top}px;transform:translate(-50%,-50%);width:16px;height:16px;box-sizing:border-box;border-radius:50%;border:${selected?4:2}px solid ${selected?'#111':'#263128'};background:${marker.serviceState==='documented_not_in_service'?'#999':marker.hasHistoricalSignal?'#b58b37':'#4d6b52'};opacity:${selectedId&&!selected?0.35:1};z-index:${selected?5:3}`
      markerLayer.appendChild(dot)
    }
  }
  const selector=mountPortfolioSelector(controls,value,id=>{selectedId=id;paint()})
  return {resize(nextWidth:number){frame=buildPortfolioFrame(value,nextWidth,210,'/{z}/{x}/{y}.png');paint()},destroy(){destroyed=true;selector.destroy();markerLayer.replaceChildren()},snapshot:()=>({selection:selector.snapshot(),frame})}
}
