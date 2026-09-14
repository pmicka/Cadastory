export const SANDBOX_PORTFOLIO_TOOL = 'scout_preview_component_sandbox_portfolio'
export const SANDBOX_PORTFOLIO_RESOURCE_URI = 'ui://scout/component-sandbox/warren-water-portfolio/v1'

const pointSchema = {
  oneOf: [
    {
      type: 'object',
      properties: {
        type: { type: 'string', enum: ['Point'] },
        coordinates: {
          type: 'array', minItems: 2, maxItems: 2,
          items: { type: 'number' },
        },
      },
      required: ['type', 'coordinates'],
      additionalProperties: false,
    },
    {
      type: 'object',
      properties: { type: { type: 'string', enum: ['unresolved'] } },
      required: ['type'],
      additionalProperties: false,
    },
  ],
}

const signalSchema = {
  type: 'object',
  properties: {
    id: { type: 'string', minLength: 1, maxLength: 160 },
    kind: { type: 'string', enum: ['historical_rehab_record'] },
    observed_at: { type: 'string', minLength: 1, maxLength: 80 },
  },
  required: ['id', 'kind', 'observed_at'],
  additionalProperties: false,
}

const memberSchema = {
  type: 'object',
  properties: {
    id: { type: 'string', minLength: 1, maxLength: 80 },
    pwsid: { type: 'string', enum: ['KY1140487'] },
    name: { type: 'string', minLength: 1, maxLength: 200 },
    point: pointSchema,
    service_state: { type: 'string', enum: ['documented_not_in_service', 'unverified'] },
    within_pilot_radius: { type: 'boolean' },
    source_modified_at: { type: 'string', minLength: 1, maxLength: 80 },
    signals: { type: 'array', maxItems: 10, items: signalSchema },
  },
  required: ['id', 'pwsid', 'name', 'point', 'service_state', 'within_pilot_radius', 'source_modified_at', 'signals'],
  additionalProperties: false,
}

const mapSchema = {
  type: 'object',
  properties: {
    contract_version: { type: 'string', enum: ['water_utility_portfolio_map_v1'] },
    scope: { type: 'string', enum: ['documented_roster'] },
    source_slug: { type: 'string', enum: ['ky-kia-water-tanks'] },
    relationship: { type: 'string', enum: ['system_membership'] },
    organization_id: { type: 'string', minLength: 1, maxLength: 80 },
    account_name: { type: 'string', enum: ['Warren County Water District'] },
    pwsid: { type: 'string', enum: ['KY1140487'] },
    observed_on: { type: 'string', minLength: 1, maxLength: 80 },
    members: { type: 'array', minItems: 1, maxItems: 100, items: memberSchema },
  },
  required: ['contract_version', 'scope', 'source_slug', 'relationship', 'organization_id', 'account_name', 'pwsid', 'observed_on', 'members'],
  additionalProperties: false,
}

export function sandboxPortfolioResultSchema() {
  return {
    type: 'object',
    properties: {
      surface: { type: 'string', enum: ['scout_component_sandbox'] },
      opportunity_type: { type: 'string', enum: ['water_tank'] },
      view_scope: { type: 'string', enum: ['portfolio'] },
      opportunity: {
        type: 'object',
        properties: {
          organization_id: { type: 'string', minLength: 1, maxLength: 80 },
          name: { type: 'string', enum: ['Warren County Water District'] },
          pwsid: { type: 'string', enum: ['KY1140487'] },
        },
        required: ['organization_id', 'name', 'pwsid'],
        additionalProperties: false,
      },
      map: mapSchema,
    },
    required: ['surface', 'opportunity_type', 'view_scope', 'opportunity', 'map'],
    additionalProperties: false,
  }
}

export function sandboxPortfolioTool() {
  return {
    name: SANDBOX_PORTFOLIO_TOOL,
    title: 'Preview Scout water-tank portfolio card',
    description: 'Owner-only read-only developer tool that renders the bounded Warren County Water District water-tank portfolio map. It accepts no organization selector or arbitrary geography.',
    inputSchema: { type: 'object', properties: {}, additionalProperties: false },
    outputSchema: sandboxPortfolioResultSchema(),
    annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
    _meta: { ui: { resourceUri: SANDBOX_PORTFOLIO_RESOURCE_URI } },
  }
}

export function sandboxPortfolioResource() {
  return {
    uri: SANDBOX_PORTFOLIO_RESOURCE_URI,
    name: 'scout-water-portfolio-sandbox',
    title: 'Scout Warren Water Portfolio Sandbox',
    description: 'Owner-only bounded Scout MCP Apps portfolio View for the documented Warren County water-tank roster.',
    mimeType: 'text/html;profile=mcp-app',
  }
}
