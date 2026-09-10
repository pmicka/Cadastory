-- Step 2: version the sandbox result envelope and register its bounded real-data View.

update agent_contract.output_schema_families
set version = 2,
    description = 'Owner-only minimal Scout MCP Apps View with bounded real exemplar data',
    json_schema = '{"type":"object","properties":{"surface":{"const":"scout_component_sandbox"},"version":{"const":"v2"},"business_data":{"const":true},"interaction_scope":{"const":"ephemeral_only"},"foundation":{"const":"ready"},"exemplars":{"type":"array","maxItems":4,"items":{"type":"object","properties":{"name":{"type":"string","minLength":1,"maxLength":160},"kind":{"enum":["property","group"]},"archetype":{"type":["string","null"],"minLength":1,"maxLength":100},"resolution_status":{"type":["string","null"],"minLength":1,"maxLength":100}},"required":["name","kind","archetype","resolution_status"],"additionalProperties":false}}},"required":["surface","version","business_data","interaction_scope","foundation","exemplars"],"additionalProperties":false}'::jsonb,
    updated_at = now()
where slug = 'ui_component_sandbox';

update agent_contract.tool_contracts
set contract_version = 3,
    notes = 'Owner-only minimal MCP Apps View with at most four server-normalized Scout exemplars. Authorization remains server-side at the public gateway and sandbox function; no arguments or canonical state mutation.',
    updated_at = now()
where tool_name = 'scout_preview_component_sandbox';

update agent_contract.tool_evolution
set result_envelope_version = 2,
    notes = 'Step 2 uses an explicit v2 result/resource path because the Step 1 envelope promised business_data=false. Remains owner-only, read-only, ephemeral, and reversible.',
    updated_at = now()
where tool_name = 'scout_preview_component_sandbox';

update agent_contract.tool_routing
set routing_version = 3,
    summary = 'Render the owner-only minimal Scout MCP Apps View with a bounded set of real Scout exemplars.',
    result_rules = '{"boundary":"Minimal developer UI projection with at most four server-normalized Scout exemplars. No map, contact details, imagery, actions, external account data, or canonical Scout state mutation. Authorization is server-side and owner-only."}'::jsonb,
    updated_at = now()
where tool_name = 'scout_preview_component_sandbox';

update agent_presentation.tool_contracts
set max_initial_items = 4,
    section_order = array['ui_foundation', 'bounded_exemplars']::text[],
    agent_instruction = 'Render the MCP Apps View once. Display only the bounded exemplar fields returned by the tool; missing fields remain explicit and no actions are offered.',
    updated_at = now()
where tool_name = 'scout_preview_component_sandbox';

update agent_ui.surface_catalog
set purpose = 'Owner-only minimal MCP Apps surface for verifying the current View lifecycle and bounded real-data path.',
    notes = 'Step 2 data-path proof only. At most four text exemplars; no maps, detailed contacts, files, imagery, carousel behavior, actions, or canonical state mutation.',
    updated_at = now()
where slug = 'component_sandbox';

update agent_ui.resource_registry
set active = false,
    updated_at = now()
where resource_uri = 'ui://scout/component-sandbox/v1';

insert into agent_ui.resource_registry (
  resource_uri,
  surface_slug,
  edge_function_slug,
  mime_type,
  version,
  business_data,
  protocol_smoke_status,
  smoke_tested_at,
  active
)
values (
  'ui://scout/component-sandbox/v2',
  'component_sandbox',
  'scout-component-sandbox-mcp',
  'text/html;profile=mcp-app',
  'v2',
  true,
  'not_tested',
  null,
  true
)
on conflict (resource_uri) do update
set surface_slug = excluded.surface_slug,
    edge_function_slug = excluded.edge_function_slug,
    mime_type = excluded.mime_type,
    version = excluded.version,
    business_data = excluded.business_data,
    protocol_smoke_status = excluded.protocol_smoke_status,
    smoke_tested_at = excluded.smoke_tested_at,
    active = excluded.active,
    updated_at = now();

select agent_contract.assert_tool_registry_integrity_v1();
select agent_contract.assert_architecture_doctrine_v1();
