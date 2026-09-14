import { registerAppResource, registerAppTool, RESOURCE_MIME_TYPE } from 'npm:@modelcontextprotocol/ext-apps@2.0.0/server'
import * as z from 'npm:zod@4.2.0/v4'
import {
  SANDBOX_PORTFOLIO_RESOURCE_URI,
  SANDBOX_PORTFOLIO_TOOL,
} from '../../_shared/scout_sandbox_portfolio_contract.ts'
import { loadWarrenPortfolio } from './backend.ts'
import { prepareWarrenResource } from './resource.ts'
import { buildPortfolioResult } from './result.ts'

const pointSchema = z.union([
  z.object({
    type: z.literal('Point'),
    coordinates: z.tuple([
      z.number().min(-180).max(180),
      z.number().min(-85.05112878).max(85.05112878),
    ]),
  }),
  z.object({ type: z.literal('unresolved') }),
])

const signalSchema = z.object({
  id: z.string().min(1).max(160),
  kind: z.literal('historical_rehab_record'),
  observed_at: z.string().min(1).max(80),
})

const memberSchema = z.object({
  id: z.string().min(1).max(80),
  pwsid: z.literal('KY1140487'),
  name: z.string().min(1).max(200),
  point: pointSchema,
  service_state: z.enum(['documented_not_in_service', 'unverified']),
  within_pilot_radius: z.boolean(),
  source_modified_at: z.string().min(1).max(80),
  signals: z.array(signalSchema).max(10),
})

const portfolioMapSchema = z.object({
  contract_version: z.literal('water_utility_portfolio_map_v1'),
  scope: z.literal('documented_roster'),
  source_slug: z.literal('ky-kia-water-tanks'),
  relationship: z.literal('system_membership'),
  organization_id: z.string().min(1).max(80),
  account_name: z.literal('Warren County Water District'),
  pwsid: z.literal('KY1140487'),
  observed_on: z.string().min(1).max(80),
  members: z.array(memberSchema).min(1).max(100),
})

const portfolioResultSchema = z.object({
  surface: z.literal('scout_component_sandbox'),
  opportunity_type: z.literal('water_tank'),
  view_scope: z.literal('portfolio'),
  opportunity: z.object({
    organization_id: z.string().min(1).max(80),
    name: z.literal('Warren County Water District'),
    pwsid: z.literal('KY1140487'),
  }),
  map: portfolioMapSchema,
})

type PortfolioDb = Parameters<typeof loadWarrenPortfolio>[0]
let portfolioHtmlPromise: Promise<string> | null = null

function loadPortfolioHtml(db: PortfolioDb, html: string) {
  if (!portfolioHtmlPromise) {
    portfolioHtmlPromise = prepareWarrenResource(db, html)
      .then(({ html: prepared }) => prepared)
      .catch((error) => {
        portfolioHtmlPromise = null
        throw error
      })
  }
  return portfolioHtmlPromise
}

export function registerPortfolioMcp(server: any, db: PortfolioDb, html: string) {
  registerAppResource(
    server,
    'scout-water-portfolio-sandbox',
    SANDBOX_PORTFOLIO_RESOURCE_URI,
    { mimeType: RESOURCE_MIME_TYPE },
    async () => ({
      contents: [{
        uri: SANDBOX_PORTFOLIO_RESOURCE_URI,
        mimeType: RESOURCE_MIME_TYPE,
        text: (await loadPortfolioHtml(db, html))
          .replace('__SCOUT_DIAGNOSTIC_RESOURCE_URI__', SANDBOX_PORTFOLIO_RESOURCE_URI),
        _meta: {
          ui: {
            prefersBorder: false,
            csp: { resourceDomains: [] },
          },
        },
      }],
    }),
  )

  registerAppTool(
    server,
    SANDBOX_PORTFOLIO_TOOL,
    {
      title: 'Preview Scout water-tank portfolio card',
      description: 'Owner-only read-only developer tool that renders the bounded Warren County Water District water-tank portfolio map. It accepts no organization selector or arbitrary geography.',
      inputSchema: z.object({}),
      outputSchema: portfolioResultSchema,
      annotations: {
        readOnlyHint: true,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false,
      },
      _meta: { ui: { resourceUri: SANDBOX_PORTFOLIO_RESOURCE_URI } },
    },
    async () => {
      const portfolio = await loadWarrenPortfolio(db)
      const structuredContent = {
        surface: 'scout_component_sandbox' as const,
        ...buildPortfolioResult(portfolio),
      }
      return {
        content: [{
          type: 'text',
          text: `Scout returned the bounded ${portfolio.account_name} water-tank portfolio card with ${portfolio.members.length} documented roster members.`,
        }],
        structuredContent,
      }
    },
  )
}
