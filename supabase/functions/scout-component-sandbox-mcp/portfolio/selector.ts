import { createPortfolioSelection } from './selection.ts'
// Native selector is outside the swipeable media viewport; the map remains non-interactive.
export function mountPortfolioSelector(container:HTMLElement,value:unknown,onSelect:(id:string)=>void) {
  const state=createPortfolioSelection(value)
  const label=document.createElement('label')
  label.textContent='Portfolio member '
  const select=document.createElement('select')
  select.style.cssText='width:100%;max-width:100%;font:inherit;color:inherit;background:#fff;border:1px solid #dde2da;border-radius:8px;padding:8px'
  const overview=document.createElement('option');overview.value='';overview.textContent=`All ${state.portfolio.members.length} tanks`;select.appendChild(overview)
  for(const member of state.portfolio.members) {
    const option=document.createElement('option');option.value=member.id
    option.textContent=member.name+(member.service_state==='documented_not_in_service'?' — not in service':member.signals.length?' — historical evidence':'')
    select.appendChild(option)
  }
  const description=document.createElement('p');description.setAttribute('role','status');description.setAttribute('aria-live','polite')
  description.style.cssText='font-size:11px;line-height:1.5;color:#657065;margin:6px 0'
  const update=()=>{state.select(select.value);description.textContent=state.snapshot().description;onSelect(select.value)}
  const legend=document.createElement('p');legend.textContent='Green: operating state unverified · Gray: not in service · Amber: historical evidence';legend.style.cssText='font-size:10px;color:#657065;margin:4px 0'
  label.appendChild(select);container.replaceChildren(label,description,legend)
  select.addEventListener('change',update);update()
  return {destroy(){select.removeEventListener('change',update);container.replaceChildren()},snapshot:()=>state.snapshot()}
}
