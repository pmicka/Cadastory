update agent_ui.resource_registry
set active = false,
    updated_at = now()
where resource_uri in (
  'ui://scout/component-sandbox/v1',
  'ui://scout/component-sandbox/v2'
);

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
  'ui://scout/component-sandbox/v3',
  'component_sandbox',
  'scout-component-sandbox-mcp',
  'text/html;profile=mcp-app',
  'v3',
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

update agent_contract.tool_evolution
set notes = 'Step 2 advertises cache-busting View resource v3 while serving v1 and v2 as runtime compatibility aliases. The data contract remains v2 and the tool remains owner-only, read-only, ephemeral, and reversible.',
    updated_at = now()
where tool_name = 'scout_preview_component_sandbox';

select agent_contract.assert_tool_registry_integrity_v1();
select agent_contract.assert_architecture_doctrine_v1();
