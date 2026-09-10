-- Keep the existing View resource identity stable for hosts with cached tool metadata.
-- The structured result remains explicitly versioned as v2.

update agent_ui.resource_registry
set business_data = true,
    protocol_smoke_status = 'not_tested',
    smoke_tested_at = null,
    active = true,
    updated_at = now()
where resource_uri = 'ui://scout/component-sandbox/v1';

update agent_ui.resource_registry
set active = false,
    updated_at = now()
where resource_uri = 'ui://scout/component-sandbox/v2';

update agent_contract.tool_evolution
set notes = 'Step 2 uses an explicit v2 result envelope while retaining the stable v1 View resource identity for host metadata-cache compatibility. Remains owner-only, read-only, ephemeral, and reversible.',
    updated_at = now()
where tool_name = 'scout_preview_component_sandbox';

select agent_contract.assert_tool_registry_integrity_v1();
select agent_contract.assert_architecture_doctrine_v1();
