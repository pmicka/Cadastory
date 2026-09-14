import { readFile, writeFile } from 'node:fs/promises'

const gatewayPaths = [
  new URL('../scout-connect/index.ts', import.meta.url),
  new URL('../scout-mcp-contract/index.ts', import.meta.url),
]

const portfolioImport = "import { sandboxWaterUtilityPortfolioMapSchema, sandboxWaterUtilityPortfolioOpportunitySchema } from '../_shared/scout_sandbox_water_portfolio_schema.ts'"
const compatibilityUris = Array.from({ length: 26 }, (_, index) => `ui://scout/component-sandbox/v${26 - index}`)

function replaceFunction(source, functionName, nextFunctionName, replacement) {
  const start = source.indexOf(`function ${functionName}(){`)
  const end = source.indexOf(`function ${nextFunctionName}(){`, start)
  if (start < 0 || end < 0) throw new Error(`Could not locate ${functionName} gateway function`)
  return `${source.slice(0, start)}${replacement}\n${source.slice(end)}`
}

for (const path of gatewayPaths) {
  let source = await readFile(path, 'utf8')

  if (!source.includes(portfolioImport)) {
    const swpppImport = "import { sandboxSwpppSiteMapSchema, sandboxSwpppSiteOpportunitySchema } from '../_shared/scout_sandbox_swppp_schema.ts'"
    if (!source.includes(swpppImport)) throw new Error(`Could not locate SWPPP schema import in ${path.pathname}`)
    source = source.replace(swpppImport, `${swpppImport}\n${portfolioImport}`)
  }

  source = source.replace(
    /const SANDBOX_RESOURCE_URI = 'ui:\/\/scout\/component-sandbox\/v\d+'/,
    "const SANDBOX_RESOURCE_URI = 'ui://scout/component-sandbox/v27'",
  )
  source = source.replace(
    /const SANDBOX_COMPATIBILITY_RESOURCE_URIS = \[[^\n]+\]/,
    `const SANDBOX_COMPATIBILITY_RESOURCE_URIS = [${compatibilityUris.map((uri) => `'${uri}'`).join(',')}]`,
  )

  source = replaceFunction(
    source,
    'sandboxResultSchema',
    'sandboxTool',
    "function sandboxResultSchema(){return {oneOf:[{type:'object',properties:{surface:{type:'string',enum:['scout_component_sandbox']},opportunity_type:{type:'string',enum:['premium_exterior']},opportunity:sandboxPremiumOpportunitySchema(),map:sandboxPremiumMapSchema()},required:['surface','opportunity_type','opportunity','map'],additionalProperties:false},{type:'object',properties:{surface:{type:'string',enum:['scout_component_sandbox']},opportunity_type:{type:'string',enum:['water_tank']},opportunity:sandboxWaterTankOpportunitySchema(),map:sandboxWaterTankMapSchema()},required:['surface','opportunity_type','opportunity','map'],additionalProperties:false},{type:'object',properties:{surface:{type:'string',enum:['scout_component_sandbox']},opportunity_type:{type:'string',enum:['swppp_site']},opportunity:sandboxSwpppSiteOpportunitySchema(),map:sandboxSwpppSiteMapSchema()},required:['surface','opportunity_type','opportunity','map'],additionalProperties:false},{type:'object',properties:{surface:{type:'string',enum:['scout_component_sandbox']},opportunity_type:{type:'string',enum:['water_utility_portfolio']},opportunity:sandboxWaterUtilityPortfolioOpportunitySchema(),map:sandboxWaterUtilityPortfolioMapSchema()},required:['surface','opportunity_type','opportunity','map'],additionalProperties:false}]}}",
  )

  source = replaceFunction(
    source,
    'sandboxTool',
    'sandboxResource',
    "function sandboxTool(){return {name:SANDBOX_TOOL,title:'Preview Scout opportunity card',description:'Owner-only read-only developer tool that renders one bounded Scout MCP Apps opportunity card and matching map. Select premium_exterior, water_tank, swppp_site, or the Warren County water_utility_portfolio exemplar; omission preserves the PNC Tower compatibility default.',inputSchema:{type:'object',properties:{opportunity_type:{type:'string',enum:['premium_exterior','water_tank','swppp_site','water_utility_portfolio']}},additionalProperties:false},outputSchema:sandboxResultSchema(),annotations:{readOnlyHint:true,destructiveHint:false,idempotentHint:true,openWorldHint:false},_meta:{ui:{resourceUri:SANDBOX_RESOURCE_URI}}}",
  )

  await writeFile(path, source)
}

console.log('Scout Warren portfolio gateway contracts aligned to v27.')
