import { normalizePortfolio, portfolioCounts, type Portfolio } from './model.ts'
export function createPortfolioSelection(value: unknown) {
  const portfolio=normalizePortfolio(value)
  if(!portfolio)throw new Error('Invalid portfolio contract')
  let selectedId=''
  return {
    portfolio,
    select(id:string) { if(id!==''&&!portfolio.members.some(m=>m.id===id))throw new Error('Unknown portfolio member'); selectedId=id },
    snapshot() {
      const member=portfolio.members.find(m=>m.id===selectedId)
      return {selectedId, member, counts:portfolioCounts(portfolio),
        description:member ? `${member.name}. ${member.point.type==='Point'?'Recorded location.':'Location unresolved.'} ${member.service_state==='documented_not_in_service'?'Documented not in service.':'Operating state unverified.'} ${member.signals.length?member.signals.map(s=>`Historical rehabilitation evidence: ${s.observed_at.slice(0,10)}.`).join(' '):'No linked rehabilitation signal in this roster.'}` : 'All documented tanks. Portfolio membership is not proof of current service need.'}
    },
  }
}
