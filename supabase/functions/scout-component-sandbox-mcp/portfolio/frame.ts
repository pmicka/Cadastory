import { normalizePortfolio, portfolioCounts } from './model.ts'
const x = (lon:number) => (lon+180)/360
const y = (lat:number) => (1-Math.log(Math.tan(lat*Math.PI/180)+1/Math.cos(lat*Math.PI/180))/Math.PI)/2
export function buildPortfolioFrame(value:unknown,width:number,height:number,tileUrlTemplate:string) {
  const p=normalizePortfolio(value)
  if (!p) throw new Error('Invalid portfolio contract')
  if (!Number.isFinite(width)||!Number.isFinite(height)||width<280||width>456||height!==210) throw new Error('Unsupported portfolio viewport')
  width=Math.round(width)
  const located=p.members.flatMap(m=>m.point.type==='Point'?[{member:m,px:x(m.point.coordinates[0]),py:y(m.point.coordinates[1])}]:[])
  if (!located.length) return {status:'no_located_members' as const,counts:portfolioCounts(p),tiles:[],markers:[],overlapPairs:[]}
  const west=Math.min(...located.map(m=>m.px)),east=Math.max(...located.map(m=>m.px))
  const north=Math.min(...located.map(m=>m.py)),south=Math.max(...located.map(m=>m.py))
  // Regional portfolio only. Do not silently misframe antimeridian or worldwide rosters.
  if (east-west>10/360||south-north>0.05) throw new Error('Portfolio exceeds regional framing scope')
  const cx=(west+east)/2,cy=(north+south)/2,padding=24
  let zoom=18
  while(zoom>5&&((east-west)*256*2**zoom>width-2*padding||(south-north)*256*2**zoom>height-2*padding))zoom--
  const world=256*2**zoom,left=cx*world-width/2,top=cy*world-height/2
  if ((east-west)*world>width-2*padding||(south-north)*world>height-2*padding)throw new Error('Portfolio does not fit')
  const tiles=[]
  for(let tx=Math.floor(left/256);tx<=Math.floor((left+width-1)/256);tx++)for(let ty=Math.floor(top/256);ty<=Math.floor((top+height-1)/256);ty++) {
    if(ty<0||ty>=2**zoom)continue
    const wrapped=((tx%2**zoom)+2**zoom)%2**zoom
    tiles.push({z:zoom,x:wrapped,y:ty,left:tx*256-left,top:ty*256-top,url:tileUrlTemplate.replace('{z}',String(zoom)).replace('{x}',String(wrapped)).replace('{y}',String(ty))})
  }
  if(tiles.length>12)throw new Error('Portfolio tile budget exceeded')
  const markers=located.map(m=>({id:m.member.id,left:m.px*world-left,top:m.py*world-top,serviceState:m.member.service_state,hasHistoricalSignal:m.member.signals.length>0}))
  // Report overlap; never jitter, merge identities, or imply an unapproved cluster.
  const overlapPairs:string[][]=[]
  for(let i=0;i<markers.length;i++)for(let j=i+1;j<markers.length;j++)if(Math.hypot(markers[i].left-markers[j].left,markers[i].top-markers[j].top)<24)overlapPairs.push([markers[i].id,markers[j].id])
  return {status:'ready' as const,counts:portfolioCounts(p),zoom,width,height,tiles,markers,overlapPairs}
}
