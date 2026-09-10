-- Record the successful production host invocation of the Step 1 MCP Apps View.

update agent_ui.resource_registry
set protocol_smoke_status = 'passed',
    smoke_tested_at = now(),
    updated_at = now()
where resource_uri = 'ui://scout/component-sandbox/v1'
  and edge_function_slug = 'scout-component-sandbox-mcp'
  and business_data = false
  and active = true;

select agent_contract.assert_tool_registry_integrity_v1();
select agent_contract.assert_architecture_doctrine_v1();
