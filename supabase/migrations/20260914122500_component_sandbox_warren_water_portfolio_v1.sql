-- Owner-only bounded Warren County water-tank portfolio sandbox route.
-- Deployment remains a separate explicit action. This migration is intentionally tracked before deployment.

begin;

create or replace function public.scout_get_component_sandbox_water_portfolio_v1_internal()
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog'
as $portfolio$
with org as (
  select o.id, o.canonical_name
  from core.organizations o
  where o.status = 'active'
    and o.organization_type = 'water_utility'
    and o.canonical_name = 'Warren County Water District'
    and o.attributes->>'source' = 'ky-kia-water-tanks'
    and o.attributes->>'asset_resolution' = 'wris_operating_system_v1'
    and o.attributes->'pwsids' = '["KY1140487"]'::jsonb
), roster as (
  select
    o.id as organization_id,
    o.canonical_name,
    r.source_native_id,
    r.location,
    r.within_pilot_radius,
    r.raw_payload#>>'{attributes,WRIS_FID}' as wris_fid,
    r.raw_payload#>>'{attributes,PWSID}' as pwsid,
    r.raw_payload#>>'{attributes,MODIFYDATE}' as modify_epoch_ms
  from org o
  join ingest.sources s on s.slug = 'ky-kia-water-tanks'
  join ingest.raw_records r on r.source_id = s.id
  where r.raw_payload#>>'{attributes,PWSID}' = 'KY1140487'
), bounded as (
  select *
  from roster
  order by source_native_id, wris_fid
  limit 100
)
select jsonb_build_object(
  'contract_version', 'water_utility_portfolio_map_v1',
  'account_name', min(b.canonical_name),
  'organization_id', min(b.organization_id::text),
  'pwsid', 'KY1140487',
  'scope', 'documented_roster',
  'source_slug', 'ky-kia-water-tanks',
  'relationship', 'system_membership',
  'observed_on', current_date,
  'members', jsonb_agg(
    jsonb_build_object(
      'id', b.wris_fid,
      'pwsid', b.pwsid,
      'name', b.source_native_id,
      'point', case
        when b.location is null then jsonb_build_object('type', 'unresolved')
        else extensions.st_asgeojson(b.location::extensions.geometry)::jsonb
      end,
      'service_state', case
        when b.source_native_id ilike '%NOT IN SERVICE%' then 'documented_not_in_service'
        else 'unverified'
      end,
      'within_pilot_radius', b.within_pilot_radius,
      'source_modified_at', to_timestamp(b.modify_epoch_ms::double precision / 1000),
      'signals', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'id', s.candidate_key,
            'kind', 'historical_rehab_record',
            'observed_at', s.observed_at
          ) order by s.observed_at desc, s.candidate_key
        )
        from (
          select v.candidate_key, v.observed_at
          from scout.v_water_tank_opportunity_candidates v
          where v.organization_id = b.organization_id
            and v.subject_key = b.wris_fid
            and v.details->>'latest_project_status' = 'REHAB'
          order by v.observed_at desc, v.candidate_key
          limit 10
        ) s
      ), '[]'::jsonb)
    ) order by b.source_native_id, b.wris_fid
  )
)
from bounded b
having count(*) between 1 and 100;
$portfolio$;

revoke all on function public.scout_get_component_sandbox_water_portfolio_v1_internal() from public, anon, authenticated;
grant execute on function public.scout_get_component_sandbox_water_portfolio_v1_internal() to service_role;

insert into agent_contract.output_schema_families (slug, version, description, json_schema, updated_at)
values (
  'ui_component_sandbox_portfolio',
  1,
  'Owner-only bounded Warren County water-tank portfolio sandbox result',
  '{"type":"object","properties":{"surface":{"const":"scout_component_sandbox"},"opportunity_type":{"const":"water_tank"},"view_scope":{"const":"portfolio"},"opportunity":{"type":"object","properties":{"organization_id":{"type":"string","minLength":1,"maxLength":80},"name":{"const":"Warren County Water District"},"pwsid":{"const":"KY1140487"}},"required":["organization_id","name","pwsid"],"additionalProperties":false},"map":{"type":"object","properties":{"contract_version":{"const":"water_utility_portfolio_map_v1"},"scope":{"const":"documented_roster"},"source_slug":{"const":"ky-kia-water-tanks"},"relationship":{"const":"system_membership"},"organization_id":{"type":"string","minLength":1,"maxLength":80},"account_name":{"const":"Warren County Water District"},"pwsid":{"const":"KY1140487"},"observed_on":{"type":"string","minLength":1,"maxLength":80},"members":{"type":"array","minItems":1,"maxItems":100,"items":{"type":"object","properties":{"id":{"type":"string","minLength":1,"maxLength":80},"pwsid":{"const":"KY1140487"},"name":{"type":"string","minLength":1,"maxLength":200},"point":{"oneOf":[{"type":"object","properties":{"type":{"const":"Point"},"coordinates":{"type":"array","minItems":2,"maxItems":2,"items":{"type":"number"}}},"required":["type","coordinates"],"additionalProperties":false},{"type":"object","properties":{"type":{"const":"unresolved"}},"required":["type"],"additionalProperties":false}]},"service_state":{"enum":["documented_not_in_service","unverified"]},"within_pilot_radius":{"type":"boolean"},"source_modified_at":{"type":"string","minLength":1,"maxLength":80},"signals":{"type":"array","maxItems":10,"items":{"type":"object","properties":{"id":{"type":"string","minLength":1,"maxLength":160},"kind":{"const":"historical_rehab_record"},"observed_at":{"type":"string","minLength":1,"maxLength":80}},"required":["id","kind","observed_at"],"additionalProperties":false}}},"required":["id","pwsid","name","point","service_state","within_pilot_radius","source_modified_at","signals"],"additionalProperties":false}}},"required":["contract_version","scope","source_slug","relationship","organization_id","account_name","pwsid","observed_on","members"],"additionalProperties":false}},"required":["surface","opportunity_type","view_scope","opportunity","map"],"additionalProperties":false}'::jsonb,
  now()
)
on conflict (slug) do update set
  version = excluded.version,
  description = excluded.description,
  json_schema = excluded.json_schema,
  updated_at = now();

insert into agent_contract.tool_contracts (
  tool_name, response_type_slug, output_schema_slug, read_only, destructive, idempotent, open_world,
  model_visible, app_visible, contract_version, active, notes, updated_at
)
values (
  'scout_preview_component_sandbox_portfolio', 'status', 'ui_component_sandbox_portfolio',
  true, false, true, false, true, true, 1, true,
  'Owner-only bounded Warren County water-tank portfolio preview. No organization selector, arbitrary geography, chat text, or canonical mutation is accepted. Public gateways and the sandbox function independently enforce owner authorization.',
  now()
)
on conflict (tool_name) do update set
  response_type_slug = excluded.response_type_slug,
  output_schema_slug = excluded.output_schema_slug,
  read_only = excluded.read_only,
  destructive = excluded.destructive,
  idempotent = excluded.idempotent,
  open_world = excluded.open_world,
  model_visible = excluded.model_visible,
  app_visible = excluded.app_visible,
  contract_version = excluded.contract_version,
  active = excluded.active,
  notes = excluded.notes,
  updated_at = now();

insert into agent_contract.tool_routing (
  tool_name, summary, when_cues, not_when_cues, prefer_over, prerequisites,
  usually_preceded_by, usually_followed_by, confirmation, failure_policy, result_rules,
  instruction_group, instruction_priority, active, routing_version, updated_at
)
values (
  'scout_preview_component_sandbox_portfolio',
  'Render the owner-only bounded Warren County water-tank portfolio sandbox map and member selector.',
  array[
    'the Scout owner explicitly asks to preview or test the larger portfolio opportunity map',
    'the Scout owner explicitly asks for the Warren County Water District water-tank portfolio sandbox card'
  ],
  array[
    'the operator is asking for normal live opportunity discovery, job planning, evidence, outreach, or profile state',
    'the request asks for an arbitrary organization, arbitrary geography, or a portfolio other than the bounded Warren sandbox exemplar'
  ],
  array['scout_preview_component_sandbox']::text[],
  '[]'::jsonb,
  array[]::text[],
  array[]::text[],
  'none',
  '{"on_forbidden":"Treat the tool as unavailable; do not infer or reveal owner-access details."}'::jsonb,
  '{"boundary":"One documented Warren County Water District roster only. Member points remain exact and individually selectable. Historical REHAB records remain historical evidence, not current jobs. System membership does not establish ownership, contracting authority, or site access."}'::jsonb,
  'other',
  96,
  true,
  1,
  now()
)
on conflict (tool_name) do update set
  summary = excluded.summary,
  when_cues = excluded.when_cues,
  not_when_cues = excluded.not_when_cues,
  prefer_over = excluded.prefer_over,
  prerequisites = excluded.prerequisites,
  usually_preceded_by = excluded.usually_preceded_by,
  usually_followed_by = excluded.usually_followed_by,
  confirmation = excluded.confirmation,
  failure_policy = excluded.failure_policy,
  result_rules = excluded.result_rules,
  instruction_group = excluded.instruction_group,
  instruction_priority = excluded.instruction_priority,
  active = excluded.active,
  routing_version = excluded.routing_version,
  updated_at = now();

insert into agent_privacy.tool_policies (
  tool_name, required_scope, purpose, allowed_root_keys, raw_payload_persisted, persistence_class,
  sensitive_exception_keys, max_argument_bytes, enabled, privacy_notes, contract_version,
  agent_free_text_allowed, nested_contract, updated_at
)
values (
  'scout_preview_component_sandbox_portfolio', 'profile:read',
  'Render the owner-only bounded Warren County water-tank portfolio developer preview',
  array[]::text[], false, 'never', array[]::text[], 512, true,
  'No arguments or chat text are accepted or persisted. The result is a fixed documented water-system roster. Owner authorization is checked at both public routing and the sandbox function.',
  'privacy-contract-v2', false, '{}'::jsonb, now()
)
on conflict (tool_name) do update set
  required_scope = excluded.required_scope,
  purpose = excluded.purpose,
  allowed_root_keys = excluded.allowed_root_keys,
  raw_payload_persisted = excluded.raw_payload_persisted,
  persistence_class = excluded.persistence_class,
  sensitive_exception_keys = excluded.sensitive_exception_keys,
  max_argument_bytes = excluded.max_argument_bytes,
  enabled = excluded.enabled,
  privacy_notes = excluded.privacy_notes,
  contract_version = excluded.contract_version,
  agent_free_text_allowed = excluded.agent_free_text_allowed,
  nested_contract = excluded.nested_contract,
  updated_at = now();

insert into agent_presentation.tool_contracts (
  tool_name, response_type_slug, max_initial_items, section_order, evidence_visibility,
  primary_action_policy, map_priority, status_hint, agent_instruction, active, updated_at
)
values (
  'scout_preview_component_sandbox_portfolio', 'status', 1,
  array['portfolio_map', 'member_selector', 'portfolio_context']::text[],
  'summary', 'one_plus_secondary', 'high', null,
  'Render one bounded portfolio card. Preserve exact member locations and explicit documented/unverified states; do not turn historical REHAB evidence into a current-job claim.',
  true, now()
)
on conflict (tool_name) do update set
  response_type_slug = excluded.response_type_slug,
  max_initial_items = excluded.max_initial_items,
  section_order = excluded.section_order,
  evidence_visibility = excluded.evidence_visibility,
  primary_action_policy = excluded.primary_action_policy,
  map_priority = excluded.map_priority,
  status_hint = excluded.status_hint,
  agent_instruction = excluded.agent_instruction,
  active = excluded.active,
  updated_at = now();

insert into agent_ip.tool_exposure_policies (
  tool_name, permitted_output_classes, explanation_mode, bulk_method_export_allowed,
  internal_diagnostics_allowed, active, updated_at
)
values (
  'scout_preview_component_sandbox_portfolio',
  array['public_fact']::text[], 'evidence_explanation_only', false, false, true, now()
)
on conflict (tool_name) do update set
  permitted_output_classes = excluded.permitted_output_classes,
  explanation_mode = excluded.explanation_mode,
  bulk_method_export_allowed = excluded.bulk_method_export_allowed,
  internal_diagnostics_allowed = excluded.internal_diagnostics_allowed,
  active = excluded.active,
  updated_at = now();

insert into agent_exposure.tool_rules (tool_name, track_entities, deep_sensitive, discovery_batch, updated_at)
values ('scout_preview_component_sandbox_portfolio', false, false, false, now())
on conflict (tool_name) do update set
  track_entities = excluded.track_entities,
  deep_sensitive = excluded.deep_sensitive,
  discovery_batch = excluded.discovery_batch,
  updated_at = now();

insert into agent_contract.tool_evolution (
  tool_name, lifecycle_state, compatibility_policy, side_effect_scope, reversibility,
  compensation_tool, result_envelope_version, provenance_policy, notes, legacy_doctrine_v1_debt, updated_at
)
values (
  'scout_preview_component_sandbox_portfolio', 'stable', 'additive_only', 'none', 'not_applicable', null,
  1, 'preserve_if_present',
  'Separate owner-only tool/resource association is intentional because MCP Apps binds ui.resourceUri at tool registration and hosts may cache that resource. This keeps the six portfolio raster tiles out of the bounded single-site resource.',
  false, now()
)
on conflict (tool_name) do update set
  lifecycle_state = excluded.lifecycle_state,
  compatibility_policy = excluded.compatibility_policy,
  side_effect_scope = excluded.side_effect_scope,
  reversibility = excluded.reversibility,
  compensation_tool = excluded.compensation_tool,
  result_envelope_version = excluded.result_envelope_version,
  provenance_policy = excluded.provenance_policy,
  notes = excluded.notes,
  legacy_doctrine_v1_debt = excluded.legacy_doctrine_v1_debt,
  updated_at = now();

insert into agent_contract.routing_eval_fixtures (
  fixture_key, fixture_source, prompt, expected_first_tool, forbidden_first_tools,
  expected_sequence, assertions, active, updated_at
)
values
(
  'component_sandbox_portfolio_explicit_preview', 'catalog_task_cue',
  'Show me the Warren County water tank portfolio sandbox card.',
  'scout_preview_component_sandbox_portfolio',
  array['scout_preview_component_sandbox']::text[],
  array['scout_preview_component_sandbox_portfolio']::text[],
  '{"requires_explicit_portfolio_sandbox_intent":true,"bounded_warren_only":true}'::jsonb,
  true, now()
),
(
  'component_sandbox_portfolio_not_for_live_leads', 'collision',
  'Find water-tank painting opportunities near Louisville.',
  'scout_find_opportunities',
  array['scout_preview_component_sandbox_portfolio']::text[],
  array['scout_find_opportunities']::text[],
  '{"portfolio_sandbox_must_not_replace_discovery":true}'::jsonb,
  true, now()
)
on conflict (fixture_key) do update set
  fixture_source = excluded.fixture_source,
  prompt = excluded.prompt,
  expected_first_tool = excluded.expected_first_tool,
  forbidden_first_tools = excluded.forbidden_first_tools,
  expected_sequence = excluded.expected_sequence,
  assertions = excluded.assertions,
  active = excluded.active,
  updated_at = now();

update agent_contract.tool_routing
set result_rules = '{"boundary":"Owner-only bounded developer UI projection using documented Scout opportunity evidence and matching maps. Premium exterior, water-tank and SWPPP cards remain single-site. Historical evidence is not promoted to a current job. Authorization is server-side and owner-only."}'::jsonb,
    updated_at = now()
where tool_name = 'scout_preview_component_sandbox';

update agent_presentation.tool_contracts
set max_initial_items = 1,
    section_order = array['opportunity_card', 'single_site_map']::text[],
    evidence_visibility = 'summary',
    map_priority = 'high',
    agent_instruction = 'Render one bounded owner-only opportunity card and its matching single-site map. Preserve source semantics and explicit guardrails.',
    updated_at = now()
where tool_name = 'scout_preview_component_sandbox';

update agent_privacy.tool_policies
set purpose = 'Render one owner-only bounded Scout opportunity-card developer preview',
    allowed_root_keys = array['opportunity_type']::text[],
    privacy_notes = 'Only the bounded opportunity_type selector is accepted. No chat text, arbitrary identifiers, customer data, or external-account data are accepted or persisted. Owner authorization is checked server-side.',
    updated_at = now()
where tool_name = 'scout_preview_component_sandbox';

update agent_ui.surface_catalog
set purpose = 'Owner-only MCP Apps sandbox for bounded single-site opportunity cards and the bounded Warren water-tank portfolio card.',
    supports_map = true,
    primary_tools = array['scout_preview_component_sandbox', 'scout_preview_component_sandbox_portfolio']::text[],
    resource_uri = 'ui://scout/component-sandbox/v26',
    notes = 'Single-site and portfolio routes remain owner-only. The portfolio uses a separate cacheable resource URI so its six regional raster tiles are not added to the single-site embedded-raster bundle.',
    updated_at = now()
where slug = 'component_sandbox';

update agent_ui.resource_registry
set active = false, updated_at = now()
where surface_slug = 'component_sandbox'
  and resource_uri not in (
    'ui://scout/component-sandbox/v26',
    'ui://scout/component-sandbox/warren-water-portfolio/v1'
  );

insert into agent_ui.resource_registry (
  resource_uri, surface_slug, edge_function_slug, mime_type, version,
  business_data, protocol_smoke_status, smoke_tested_at, active, updated_at
)
values
(
  'ui://scout/component-sandbox/v26', 'component_sandbox', 'scout-component-sandbox-mcp',
  'text/html;profile=mcp-app', 'v26', true, 'not_tested', null, true, now()
),
(
  'ui://scout/component-sandbox/warren-water-portfolio/v1', 'component_sandbox', 'scout-component-sandbox-mcp',
  'text/html;profile=mcp-app', 'warren-water-portfolio-v1', true, 'not_tested', null, true, now()
)
on conflict (resource_uri) do update set
  surface_slug = excluded.surface_slug,
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

commit;
