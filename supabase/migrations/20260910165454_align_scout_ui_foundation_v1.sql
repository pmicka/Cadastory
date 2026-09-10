-- Align the owner-only sandbox contract with the minimal MCP Apps foundation.

update agent_contract.output_schema_families
set description = 'Owner-only minimal Scout MCP Apps View foundation state',
    json_schema = '{"type":"object","properties":{"surface":{"const":"scout_component_sandbox"},"version":{"const":"v1"},"business_data":{"const":false},"interaction_scope":{"const":"ephemeral_only"},"foundation":{"const":"ready"}},"required":["surface","version","business_data","interaction_scope","foundation"],"additionalProperties":false}'::jsonb,
    updated_at = now()
where slug = 'ui_component_sandbox';

update agent_contract.tool_contracts
set notes = 'Owner-only minimal MCP Apps View foundation. Authorization remains server-side at the public gateway and sandbox function; no arguments, business data, or canonical state mutation.',
    updated_at = now()
where tool_name = 'scout_preview_component_sandbox';

update agent_contract.tool_routing
set summary = 'Render the owner-only minimal Scout MCP Apps View to verify the live UI foundation.',
    when_cues = array['the Scout owner explicitly asks to preview, render, or test the Scout sandbox UI foundation'],
    result_rules = '{"boundary":"Minimal developer UI projection only. No business data, opportunity data, external account data, or canonical Scout state is read or mutated. Authorization is server-side and owner-only."}'::jsonb,
    updated_at = now()
where tool_name = 'scout_preview_component_sandbox';

update agent_presentation.tool_contracts
set max_initial_items = 1,
    section_order = array['ui_foundation']::text[],
    primary_action_policy = 'none',
    agent_instruction = 'Render the MCP Apps View once. This foundation surface contains no product data or actions.',
    updated_at = now()
where tool_name = 'scout_preview_component_sandbox';

update agent_ui.surface_catalog
set title = 'Scout UI Foundation',
    purpose = 'Owner-only minimal MCP Apps surface for verifying the current View lifecycle and host rendering.',
    max_primary_actions = 0,
    supports_map = false,
    supports_horizontal_gesture = false,
    fallback_required = true,
    notes = 'Step 1 foundation only. No maps, contacts, files, imagery, carousel behavior, or canonical state mutation.',
    updated_at = now()
where slug = 'component_sandbox';

update agent_ui.resource_registry
set edge_function_slug = 'scout-component-sandbox-mcp',
    business_data = false,
    protocol_smoke_status = 'not_tested',
    smoke_tested_at = null,
    active = true,
    updated_at = now()
where resource_uri = 'ui://scout/component-sandbox/v1';

select agent_contract.assert_tool_registry_integrity_v1();
select agent_contract.assert_architecture_doctrine_v1();
