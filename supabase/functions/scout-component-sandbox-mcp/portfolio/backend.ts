import { normalizePortfolio } from './model.ts'
// Internal only. The future MCP route must complete existing owner/profile gates first.
// No organization selector or arbitrary query is accepted from the View.
export async function loadWarrenPortfolio(db:{rpc:(name:string)=>PromiseLike<{data:unknown;error:unknown}>}) {
  const {data,error}=await db.rpc('scout_get_component_sandbox_water_portfolio_v1_internal')
  if(error)throw new Error('Portfolio roster unavailable')
  const portfolio=normalizePortfolio(data)
  if(!portfolio || portfolio.account_name!=='Warren County Water District' || portfolio.pwsid!=='KY1140487')throw new Error('Portfolio roster failed validation')
  return portfolio
}
