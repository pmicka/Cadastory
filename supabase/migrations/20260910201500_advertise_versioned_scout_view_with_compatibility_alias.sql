-- Advertise the versioned Step 2 View while retaining the v1 runtime compatibility alias.

update agent_ui.resource_registry
set active = false,
    updated_at = now()
where resource_uri = 'ui://scout/component-sandbox/v1';

update agent_ui.resource_registry
set business_data = true,
    protocol_smoke_status = 'passed',
    smoke_tested_at = now(),
    active = true,
    updated_at = now()
where resource_uri = 'ui://scout/component-sandbox/v2';

update agent_contract.tool_evolution
set notes = 'Step 2 advertises the versioned v2 View/result path and serves the v1 View URI as a runtime compatibility alias for hosts with cached Step 1 metadata. Remains owner-only, read-only, ephemeral, and reversible.',
    updated_at = now()
where tool_name = 'scout_preview_component_sandbox';

select agent_contract.assert_tool_registry_integrity_v1();
select agent_contract.assert_architecture_doctrine_v1();
