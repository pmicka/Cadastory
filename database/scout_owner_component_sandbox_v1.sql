-- Scout owner-only MCP App component sandbox v1
-- Applied to production 2026-09-09. Idempotent contract/surface registration.

insert into agent_contract.output_schema_families (slug,version,description,json_schema,updated_at)
values (
  'ui_component_sandbox',1,
  'Owner-only static Scout MCP App component-sandbox preview state',
  '{"type":"object","properties":{"surface":{"const":"scout_component_sandbox"},"version":{"const":"v1"},"business_data":{"const":false},"interaction_scope":{"const":"ephemeral_only"}},"required":["surface","version","business_data","interaction_scope"],"additionalProperties":false}'::jsonb,
  now()
)
on conflict (slug) do update set version=excluded.version,description=excluded.description,json_schema=excluded.json_schema,updated_at=now();

insert into agent_contract.tool_contracts (tool_name,response_type_slug,output_schema_slug,read_only,destructive,idempotent,open_world,model_visible,app_visible,contract_version,active,notes,updated_at)
values ('scout_preview_component_sandbox','status','ui_component_sandbox',true,false,true,false,true,true,1,true,'Owner-only developer preview. Authorization is enforced server-side at both the contract gateway and UI lab; no business data or canonical state mutation.',now())
on conflict (tool_name) do update set response_type_slug=excluded.response_type_slug,output_schema_slug=excluded.output_schema_slug,read_only=excluded.read_only,destructive=excluded.destructive,idempotent=excluded.idempotent,open_world=excluded.open_world,model_visible=excluded.model_visible,app_visible=excluded.app_visible,contract_version=excluded.contract_version,active=excluded.active,notes=excluded.notes,updated_at=now();

insert into agent_contract.tool_routing (tool_name,summary,when_cues,not_when_cues,prefer_over,prerequisites,usually_preceded_by,usually_followed_by,confirmation,failure_policy,result_rules,instruction_group,instruction_priority,active,routing_version,updated_at)
values (
  'scout_preview_component_sandbox',
  'Render the owner-only Scout MCP App component sandbox for deliberate UI development and review.',
  array['the Scout owner explicitly asks to preview, render, surface, inspect, or test the component sandbox card','the Scout owner explicitly asks to test basic MCP App UI controls'],
  array['the operator is asking for live opportunities, job planning, evidence, outreach, profile state, or another normal Scout workflow','the request does not explicitly concern the Scout UI/component sandbox'],
  array[]::text[],'[]'::jsonb,array[]::text[],array[]::text[],'none',
  '{"on_forbidden":"Treat the tool as unavailable; do not infer or reveal owner-access details."}'::jsonb,
  '{"boundary":"Static developer UI projection only. No business data, opportunity data, external account data, or canonical Scout state is read or mutated. Authorization is server-side and owner-only."}'::jsonb,
  'other',95,true,1,now()
)
on conflict (tool_name) do update set summary=excluded.summary,when_cues=excluded.when_cues,not_when_cues=excluded.not_when_cues,prefer_over=excluded.prefer_over,prerequisites=excluded.prerequisites,usually_preceded_by=excluded.usually_preceded_by,usually_followed_by=excluded.usually_followed_by,confirmation=excluded.confirmation,failure_policy=excluded.failure_policy,result_rules=excluded.result_rules,instruction_group=excluded.instruction_group,instruction_priority=excluded.instruction_priority,active=excluded.active,routing_version=excluded.routing_version,updated_at=now();

insert into agent_privacy.tool_policies (tool_name,required_scope,purpose,allowed_root_keys,raw_payload_persisted,persistence_class,sensitive_exception_keys,max_argument_bytes,enabled,privacy_notes,contract_version,agent_free_text_allowed,nested_contract,updated_at)
values ('scout_preview_component_sandbox','profile:read','Render an owner-only static developer UI preview',array[]::text[],false,'never',array[]::text[],2048,true,'No arguments, chat text, business data, customer data, or external-account data are accepted or persisted. Owner authorization is checked server-side.','privacy-contract-v2',false,'{}'::jsonb,now())
on conflict (tool_name) do update set required_scope=excluded.required_scope,purpose=excluded.purpose,allowed_root_keys=excluded.allowed_root_keys,raw_payload_persisted=excluded.raw_payload_persisted,persistence_class=excluded.persistence_class,sensitive_exception_keys=excluded.sensitive_exception_keys,max_argument_bytes=excluded.max_argument_bytes,enabled=excluded.enabled,privacy_notes=excluded.privacy_notes,contract_version=excluded.contract_version,agent_free_text_allowed=excluded.agent_free_text_allowed,nested_contract=excluded.nested_contract,updated_at=now();

insert into agent_presentation.tool_contracts (tool_name,response_type_slug,max_initial_items,section_order,evidence_visibility,primary_action_policy,map_priority,status_hint,agent_instruction,active,updated_at)
values ('scout_preview_component_sandbox','status',1,array['component_sandbox']::text[],'hidden','one_plus_secondary','none',null,'Render the MCP App UI surface once. Treat all controls as ephemeral UI state; do not imply that placeholder content is live Scout business data.',true,now())
on conflict (tool_name) do update set response_type_slug=excluded.response_type_slug,max_initial_items=excluded.max_initial_items,section_order=excluded.section_order,evidence_visibility=excluded.evidence_visibility,primary_action_policy=excluded.primary_action_policy,map_priority=excluded.map_priority,status_hint=excluded.status_hint,agent_instruction=excluded.agent_instruction,active=excluded.active,updated_at=now();

insert into agent_ip.tool_exposure_policies (tool_name,permitted_output_classes,explanation_mode,bulk_method_export_allowed,internal_diagnostics_allowed,active,updated_at)
values ('scout_preview_component_sandbox',array['public_fact']::text[],'evidence_explanation_only',false,false,true,now())
on conflict (tool_name) do update set permitted_output_classes=excluded.permitted_output_classes,explanation_mode=excluded.explanation_mode,bulk_method_export_allowed=excluded.bulk_method_export_allowed,internal_diagnostics_allowed=excluded.internal_diagnostics_allowed,active=excluded.active,updated_at=now();

insert into agent_exposure.tool_rules (tool_name,track_entities,deep_sensitive,discovery_batch,updated_at)
values ('scout_preview_component_sandbox',false,false,false,now())
on conflict (tool_name) do update set track_entities=excluded.track_entities,deep_sensitive=excluded.deep_sensitive,discovery_batch=excluded.discovery_batch,updated_at=now();

insert into agent_contract.tool_evolution (tool_name,lifecycle_state,compatibility_policy,side_effect_scope,reversibility,compensation_tool,result_envelope_version,provenance_policy,notes,legacy_doctrine_v1_debt,updated_at)
values ('scout_preview_component_sandbox','stable','additive_only','none','not_applicable',null,1,'preserve_if_present','Owner-only developer preview; smallest reversible MCP Apps experiment. No canonical state mutation.',false,now())
on conflict (tool_name) do update set lifecycle_state=excluded.lifecycle_state,compatibility_policy=excluded.compatibility_policy,side_effect_scope=excluded.side_effect_scope,reversibility=excluded.reversibility,compensation_tool=excluded.compensation_tool,result_envelope_version=excluded.result_envelope_version,provenance_policy=excluded.provenance_policy,notes=excluded.notes,legacy_doctrine_v1_debt=excluded.legacy_doctrine_v1_debt,updated_at=now();

insert into agent_contract.routing_eval_fixtures (fixture_key,fixture_source,prompt,expected_first_tool,forbidden_first_tools,expected_sequence,assertions,active,updated_at)
values
('component_sandbox_explicit_preview','catalog_task_cue','Show me the Scout component sandbox card in the AI client.','scout_preview_component_sandbox',array[]::text[],array['scout_preview_component_sandbox']::text[],'{"requires_explicit_ui_preview_intent":true}'::jsonb,true,now()),
('component_sandbox_not_for_live_leads','collision','Find exterior cleaning opportunities in Jefferson County, Kentucky.','scout_find_opportunities',array['scout_preview_component_sandbox']::text[],array['scout_find_opportunities']::text[],'{"sandbox_must_not_replace_business_workflow":true}'::jsonb,true,now())
on conflict (fixture_key) do update set fixture_source=excluded.fixture_source,prompt=excluded.prompt,expected_first_tool=excluded.expected_first_tool,forbidden_first_tools=excluded.forbidden_first_tools,expected_sequence=excluded.expected_sequence,assertions=excluded.assertions,active=excluded.active,updated_at=now();

insert into agent_ui.surface_catalog (slug,title,purpose,priority,status,default_display_mode,max_primary_actions,supports_map,supports_horizontal_gesture,fallback_required,primary_tools,resource_uri,notes,updated_at)
values ('component_sandbox','Scout Component Sandbox','Owner-only zero-business-data MCP App surface for developing and testing reusable inline Scout card controls.',1,'foundation','inline',2,false,true,true,array['scout_preview_component_sandbox']::text[],'ui://scout/component-sandbox/v1','Developer-only surface. All controls are ephemeral; owner authorization is enforced server-side and the surface is hidden from non-owner tool/resource discovery.',now())
on conflict (slug) do update set title=excluded.title,purpose=excluded.purpose,priority=excluded.priority,status=excluded.status,default_display_mode=excluded.default_display_mode,max_primary_actions=excluded.max_primary_actions,supports_map=excluded.supports_map,supports_horizontal_gesture=excluded.supports_horizontal_gesture,fallback_required=excluded.fallback_required,primary_tools=excluded.primary_tools,resource_uri=excluded.resource_uri,notes=excluded.notes,updated_at=now();

update agent_ui.resource_registry set active=false,updated_at=now() where resource_uri='ui://scout/foundation/v1';
insert into agent_ui.resource_registry (resource_uri,surface_slug,version,mime_type,edge_function_slug,business_data,protocol_smoke_status,smoke_tested_at,active,updated_at)
values ('ui://scout/component-sandbox/v1','component_sandbox','v1','text/html;profile=mcp-app','scout-mcp-ui-lab',false,'not_tested',null,true,now())
on conflict (resource_uri) do update set surface_slug=excluded.surface_slug,version=excluded.version,mime_type=excluded.mime_type,edge_function_slug=excluded.edge_function_slug,business_data=excluded.business_data,protocol_smoke_status=excluded.protocol_smoke_status,smoke_tested_at=excluded.smoke_tested_at,active=excluded.active,updated_at=now();

select agent_contract.assert_tool_registry_integrity_v1();
select agent_contract.assert_architecture_doctrine_v1();
