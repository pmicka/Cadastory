-- Canonical model-facing routing contract for Scout by Cadastory.
-- Routing guidance is behavioral metadata. It does not replace privacy, scope,
-- exposure, anti-enumeration, or authorization enforcement.

begin;

create table if not exists agent_contract.tool_routing (
  tool_name text primary key references agent_contract.tool_contracts(tool_name) on delete cascade,
  summary text not null check (char_length(summary) between 1 and 600),
  when_cues text[] not null default '{}'::text[],
  not_when_cues text[] not null default '{}'::text[],
  prefer_over text[] not null default '{}'::text[],
  prerequisites jsonb not null default '[]'::jsonb check (jsonb_typeof(prerequisites)='array'),
  usually_preceded_by text[] not null default '{}'::text[],
  usually_followed_by text[] not null default '{}'::text[],
  confirmation text not null default 'none' check (confirmation in ('none','explicit')),
  failure_policy jsonb not null default '{}'::jsonb check (jsonb_typeof(failure_policy)='object'),
  result_rules jsonb not null default '{}'::jsonb check (jsonb_typeof(result_rules)='object'),
  instruction_group text not null default 'other' check (instruction_group ~ '^[a-z][a-z0-9_]{1,63}$'),
  instruction_priority integer not null default 100 check (instruction_priority between 1 and 1000),
  active boolean not null default true,
  routing_version integer not null default 1 check (routing_version > 0),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);
alter table agent_contract.tool_routing enable row level security;
create index if not exists tool_routing_public_instruction_idx
  on agent_contract.tool_routing(active, instruction_group, instruction_priority, tool_name);

create table if not exists agent_contract.routing_policies (
  policy_key text primary key check (policy_key ~ '^[a-z][a-z0-9_]{1,63}$'),
  title text not null check (char_length(title) between 1 and 180),
  body text not null check (char_length(body) between 1 and 1800),
  instruction_priority integer not null check (instruction_priority between 1 and 1000),
  active boolean not null default true,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);
alter table agent_contract.routing_policies enable row level security;

create table if not exists agent_contract.routing_eval_fixtures (
  fixture_key text primary key check (fixture_key ~ '^[a-z][a-z0-9_.-]{2,160}$'),
  fixture_source text not null check (fixture_source in ('catalog_example','catalog_task_cue','collision','sequence','safety')),
  prompt text not null check (char_length(prompt) between 1 and 600),
  expected_first_tool text not null references agent_contract.tool_contracts(tool_name),
  forbidden_first_tools text[] not null default '{}'::text[],
  expected_sequence text[] not null default '{}'::text[],
  assertions jsonb not null default '{}'::jsonb check (jsonb_typeof(assertions)='object'),
  active boolean not null default true,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);
alter table agent_contract.routing_eval_fixtures enable row level security;
create index if not exists routing_eval_fixtures_active_idx
  on agent_contract.routing_eval_fixtures(active, fixture_source, expected_first_tool);
create index if not exists routing_eval_fixtures_expected_first_tool_idx
  on agent_contract.routing_eval_fixtures(expected_first_tool);

-- These are service-role-only contract tables. Explicit policies document the
-- intended non-public access model without granting any table privileges.
do $policy$
begin
  if not exists (select 1 from pg_policies where schemaname='agent_contract' and tablename='tool_routing' and policyname='tool_routing_service_role_only') then
    execute 'create policy tool_routing_service_role_only on agent_contract.tool_routing for all to service_role using (true) with check (true)';
  end if;
  if not exists (select 1 from pg_policies where schemaname='agent_contract' and tablename='routing_policies' and policyname='routing_policies_service_role_only') then
    execute 'create policy routing_policies_service_role_only on agent_contract.routing_policies for all to service_role using (true) with check (true)';
  end if;
  if not exists (select 1 from pg_policies where schemaname='agent_contract' and tablename='routing_eval_fixtures' and policyname='routing_eval_fixtures_service_role_only') then
    execute 'create policy routing_eval_fixtures_service_role_only on agent_contract.routing_eval_fixtures for all to service_role using (true) with check (true)';
  end if;
end
$policy$;

-- Semantically honest replacement for the non-read-only research-task getter.
insert into agent_contract.tool_contracts (
  tool_name,response_type_slug,output_schema_slug,read_only,destructive,idempotent,open_world,
  model_visible,app_visible,contract_version,active,notes,updated_at
)
select
  'scout_claim_compatibility_research_task',response_type_slug,output_schema_slug,read_only,
  destructive,idempotent,open_world,true,true,greatest(contract_version,2),active,
  'Claims one pending compatibility research task. This is non-read-only and non-idempotent; the legacy getter remains callable only for compatibility.',clock_timestamp()
from agent_contract.tool_contracts
where tool_name='scout_get_compatibility_research'
on conflict (tool_name) do update set
  response_type_slug=excluded.response_type_slug,
  output_schema_slug=excluded.output_schema_slug,
  read_only=excluded.read_only,
  destructive=excluded.destructive,
  idempotent=excluded.idempotent,
  open_world=excluded.open_world,
  model_visible=true,
  app_visible=true,
  contract_version=greatest(agent_contract.tool_contracts.contract_version,excluded.contract_version),
  active=excluded.active,
  notes=excluded.notes,
  updated_at=clock_timestamp();

insert into agent_privacy.tool_policies (
  tool_name,required_scope,purpose,allowed_root_keys,raw_payload_persisted,persistence_class,
  sensitive_exception_keys,max_argument_bytes,enabled,privacy_notes,contract_version,
  agent_free_text_allowed,nested_contract,updated_at
)
select
  'scout_claim_compatibility_research_task',required_scope,
  'Claim one pending equipment compatibility research task',
  allowed_root_keys,raw_payload_persisted,persistence_class,sensitive_exception_keys,
  max_argument_bytes,true,
  'Claims a pending Scout research task; no chat context is required. Claiming changes task ownership/state.',
  contract_version,agent_free_text_allowed,nested_contract,clock_timestamp()
from agent_privacy.tool_policies
where tool_name='scout_get_compatibility_research'
on conflict (tool_name) do update set
  required_scope=excluded.required_scope,purpose=excluded.purpose,allowed_root_keys=excluded.allowed_root_keys,
  raw_payload_persisted=excluded.raw_payload_persisted,persistence_class=excluded.persistence_class,
  sensitive_exception_keys=excluded.sensitive_exception_keys,max_argument_bytes=excluded.max_argument_bytes,
  enabled=true,privacy_notes=excluded.privacy_notes,contract_version=excluded.contract_version,
  agent_free_text_allowed=excluded.agent_free_text_allowed,nested_contract=excluded.nested_contract,updated_at=clock_timestamp();

insert into agent_presentation.tool_contracts (
  tool_name,response_type_slug,max_initial_items,section_order,evidence_visibility,primary_action_policy,
  map_priority,status_hint,agent_instruction,active,updated_at
)
select
  'scout_claim_compatibility_research_task',response_type_slug,max_initial_items,section_order,
  evidence_visibility,primary_action_policy,map_priority,status_hint,
  'Treat unresolved technical domains as claimed research tasks, not questions the operator must guess.',
  active,clock_timestamp()
from agent_presentation.tool_contracts
where tool_name='scout_get_compatibility_research'
on conflict (tool_name) do update set
  response_type_slug=excluded.response_type_slug,max_initial_items=excluded.max_initial_items,
  section_order=excluded.section_order,evidence_visibility=excluded.evidence_visibility,
  primary_action_policy=excluded.primary_action_policy,map_priority=excluded.map_priority,
  status_hint=excluded.status_hint,agent_instruction=excluded.agent_instruction,
  active=excluded.active,updated_at=clock_timestamp();

insert into agent_ip.tool_exposure_policies (
  tool_name,permitted_output_classes,explanation_mode,bulk_method_export_allowed,
  internal_diagnostics_allowed,active,updated_at
)
select
  'scout_claim_compatibility_research_task',permitted_output_classes,explanation_mode,
  bulk_method_export_allowed,internal_diagnostics_allowed,active,clock_timestamp()
from agent_ip.tool_exposure_policies
where tool_name='scout_get_compatibility_research'
on conflict (tool_name) do update set
  permitted_output_classes=excluded.permitted_output_classes,explanation_mode=excluded.explanation_mode,
  bulk_method_export_allowed=excluded.bulk_method_export_allowed,
  internal_diagnostics_allowed=excluded.internal_diagnostics_allowed,active=excluded.active,
  updated_at=clock_timestamp();

insert into agent_exposure.tool_rules (tool_name,track_entities,deep_sensitive,discovery_batch,updated_at)
select 'scout_claim_compatibility_research_task',track_entities,deep_sensitive,discovery_batch,clock_timestamp()
from agent_exposure.tool_rules
where tool_name='scout_get_compatibility_research'
on conflict (tool_name) do update set
  track_entities=excluded.track_entities,deep_sensitive=excluded.deep_sensitive,
  discovery_batch=excluded.discovery_batch,updated_at=clock_timestamp();

update agent_contract.tool_contracts
set model_visible=false,app_visible=false,
    notes='Legacy compatibility alias. Hidden from new model-facing catalogs; retained temporarily so stale clients can complete an already-started workflow.',
    updated_at=clock_timestamp()
where tool_name='scout_get_compatibility_research';

insert into agent_contract.tool_capability_links(tool_name,capability_slug) values
  ('scout_claim_compatibility_research_task','equipment.compatibility_backfill'),
  ('scout_get_discovery_status','opportunities.discovery'),
  ('scout_reject_public_equipment_candidates','equipment.rig_readiness'),
  ('scout_set_external_capability_consent','integrations.task_context')
on conflict do nothing;

update commerce.scout_capability_catalog
set primary_tools=array_replace(primary_tools,'scout_get_compatibility_research','scout_claim_compatibility_research_task'),
    updated_at=clock_timestamp()
where slug='equipment.compatibility_backfill';

-- Baseline routing derives from the capability catalog and contract annotations.
insert into agent_contract.tool_routing (
  tool_name,summary,when_cues,not_when_cues,prefer_over,prerequisites,
  usually_preceded_by,usually_followed_by,confirmation,failure_policy,result_rules,
  instruction_group,instruction_priority,active,routing_version
)
select
  tc.tool_name,
  coalesce(cap.summary,'Use this focused Scout operation only when the request directly matches it.'),
  coalesce(cap.task_cues,array['the request directly matches this focused Scout operation']::text[]),
  '{}'::text[],'{}'::text[],'[]'::jsonb,'{}'::text[],'{}'::text[],'none',
  jsonb_build_object('retry',case when tc.read_only and tc.idempotent
    then 'For a genuinely transient retryable failure, one unchanged retry may be appropriate.'
    else 'Do not blindly retry after an ambiguous write, claim, approval, or state change; inspect state first.' end),
  '{}'::jsonb,
  case
    when tc.tool_name in ('scout_get_profile_status','scout_update_profile','scout_get_capabilities','scout_get_privacy_summary','scout_list_onboarding_options') then 'startup'
    when tc.tool_name like 'scout_find_%' or tc.tool_name in ('scout_check_opportunity_access','scout_get_discovery_status','scout_match_media_asset') then 'opportunities'
    when tc.tool_name in ('scout_get_lead_work_package','scout_prepare_outreach') then 'leads'
    when tc.tool_name like '%document%' or tc.tool_name='scout_search_knowledge' or tc.tool_name='scout_get_cleaning_compatibility' then 'knowledge_documents'
    when tc.tool_name in ('scout_plan_job','scout_get_job_preflight','scout_refresh_job_preflight') then 'jobs'
    when tc.tool_name like 'scout_get_entry_%' or tc.tool_name like 'scout_update_entry_%' or tc.tool_name='scout_get_alerts' then 'briefing'
    when tc.tool_name like '%external%' or tc.tool_name like '%action_intent%' then 'integrations'
    else 'equipment'
  end,
  100,true,1
from agent_contract.tool_contracts tc
left join lateral (
  select c.summary,c.task_cues
  from agent_contract.tool_capability_links l
  join commerce.scout_capability_catalog c on c.slug=l.capability_slug and c.active
  where l.tool_name=tc.tool_name
  order by c.sort_order,c.slug
  limit 1
) cap on true
where tc.active and tc.model_visible
on conflict (tool_name) do update set
  summary=excluded.summary,when_cues=excluded.when_cues,not_when_cues=excluded.not_when_cues,
  prefer_over=excluded.prefer_over,prerequisites=excluded.prerequisites,
  usually_preceded_by=excluded.usually_preceded_by,usually_followed_by=excluded.usually_followed_by,
  confirmation=excluded.confirmation,failure_policy=excluded.failure_policy,result_rules=excluded.result_rules,
  instruction_group=excluded.instruction_group,instruction_priority=excluded.instruction_priority,
  active=true,routing_version=greatest(agent_contract.tool_routing.routing_version,excluded.routing_version),
  updated_at=clock_timestamp();

insert into agent_contract.tool_routing (
  tool_name,summary,when_cues,not_when_cues,prefer_over,prerequisites,
  usually_preceded_by,usually_followed_by,confirmation,failure_policy,result_rules,
  instruction_group,instruction_priority,active,routing_version
) values
('scout_get_profile_status','Read connected-operator setup and readiness only when it is relevant to the task.',ARRAY['a greeting or no explicit Scout task','operator-specific readiness is materially required and not already established']::text[],ARRAY['an explicit task can be completed without operator profile state','a generic privacy or capability question']::text[],ARRAY[]::text[],'[]'::jsonb,ARRAY[]::text[],ARRAY['scout_update_profile','scout_check_opportunity_access','scout_find_opportunities']::text[],'none','{"retry":"Safe read: retry once only for a genuinely transient retryable error."}'::jsonb,'{"boundary":"Read-only onboarding/readiness state. Do not ask for serial numbers during onboarding."}'::jsonb,'startup',10,true,1),
('scout_get_capabilities','Explain Scout capabilities only when the operator explicitly asks or routing remains genuinely ambiguous.',ARRAY['the operator asks what Scout can do','an unfamiliar capability must be identified after direct routing rules do not resolve the request']::text[],ARRAY['a request obviously maps to a specific Scout tool','routine startup or onboarding feature touring']::text[],ARRAY[]::text[],'[]'::jsonb,ARRAY[]::text[],ARRAY[]::text[],'none','{"retry":"Safe read: retry once only for a genuinely transient retryable error."}'::jsonb,'{"boundary":"Capability metadata is not a discovery preflight and does not expose live opportunity counts."}'::jsonb,'startup',12,true,1),
('scout_find_opportunities','Find specific evidence-backed work or leads for one supported service.',ARRAY['the operator names a supported service and asks for work, leads, or opportunities','the request is ordinary local lead discovery']::text[],ARRAY['the operator asks what service to add or where to expand','the question is whether the operator may pursue a service']::text[],ARRAY['scout_find_growth_options for service-expansion or budget analysis','scout_check_opportunity_access for readiness or blocking questions']::text[],'["an explicit supported service_slug"]'::jsonb,ARRAY[]::text[],ARRAY['scout_get_lead_work_package','scout_prepare_outreach','scout_plan_job']::text[],'none','{"on_blocked":"Do not reconstruct blocked opportunity sets or vary arguments to evade a gate."}'::jsonb,'{"boundary":"Results are evidence signals to investigate, not proof of need or permission to act."}'::jsonb,'opportunities',10,true,1),
('scout_find_growth_options','Compare bounded local service-expansion options and optional aggregate budget.',ARRAY['the operator asks what service to add','the operator asks where to expand or how to use a local growth budget']::text[],ARRAY['the operator wants ordinary work or leads for a service already selected']::text[],ARRAY['scout_find_opportunities for ordinary lead discovery']::text[],'["explicit local geography; optional aggregate budget"]'::jsonb,ARRAY[]::text[],ARRAY['scout_check_opportunity_access','scout_get_document_suite']::text[],'none','{"on_blocked":"Do not use changing geography or budget values to reconstruct gated results."}'::jsonb,'{"boundary":"Aggregate budget is transient; do not supply financial-account data."}'::jsonb,'opportunities',11,true,1),
('scout_check_opportunity_access','Check whether the connected operator can pursue a named service and what blocks it.',ARRAY['the operator asks can I pursue this service','the operator asks what blocks this work or readiness']::text[],ARRAY['the operator asks to discover leads or rank work']::text[],ARRAY['scout_find_opportunities for lead discovery','scout_get_discovery_status for discovery-control account state']::text[],'["one or more explicit service slugs"]'::jsonb,ARRAY['scout_get_profile_status']::text[],ARRAY['scout_update_profile','scout_get_document_suite']::text[],'none','{"on_blocked":"Treat the returned gate as authoritative; do not reconstruct blocked work."}'::jsonb,'{"boundary":"A readiness result is not a lead search and does not reveal blocked opportunity sets."}'::jsonb,'opportunities',12,true,1),
('scout_get_discovery_status','Read customer-safe discovery-control state.',ARRAY['the operator explicitly asks about Scout discovery limits or account-state controls']::text[],ARRAY['ordinary opportunity, growth, or readiness work']::text[],ARRAY['scout_find_opportunities for work discovery','scout_check_opportunity_access for service readiness']::text[],'[]'::jsonb,ARRAY[]::text[],ARRAY[]::text[],'none','{"retry":"Safe read: retry once only for a genuinely transient retryable error."}'::jsonb,'{"boundary":"Do not attempt to infer counters, thresholds, or hidden result sets from this status."}'::jsonb,'opportunities',30,true,1),
('scout_get_lead_work_package','Prepare broad pursuit of one exact Scout candidate.',ARRAY['the operator wants to investigate, pursue, quote, or broadly prepare a specific lead']::text[],ARRAY['the operator only wants a channel-specific outreach brief or draft']::text[],ARRAY['scout_prepare_outreach for channel/message-specific preparation']::text[],'["exact candidate_key returned by Scout"]'::jsonb,ARRAY['scout_find_opportunities']::text[],ARRAY['scout_prepare_outreach','scout_plan_job']::text[],'none','{"on_blocked":"Reuse the candidate_key and returned gate; do not reconstruct a candidate or bypass suppression."}'::jsonb,'{"boundary":"Broad work package; do not automatically call outreach when this satisfies the request."}'::jsonb,'leads',10,true,1),
('scout_prepare_outreach','Prepare evidence-backed outreach for one candidate and one channel.',ARRAY['the operator asks for a message, contact approach, or channel-specific outreach preparation']::text[],ARRAY['the operator needs broad lead investigation or work preparation without outreach']::text[],ARRAY['scout_get_lead_work_package for broad pursuit preparation']::text[],'["exact candidate_key returned by Scout; a supported channel"]'::jsonb,ARRAY['scout_find_opportunities']::text[],ARRAY[]::text[],'none','{"on_blocked":"Do not recreate the candidate or evade a suppression or gate."}'::jsonb,'{"boundary":"Prepare-only. It never sends, queues, or records outreach; do not automatically call both lead tools."}'::jsonb,'leads',11,true,1),
('scout_search_knowledge','Search bounded technical, manufacturer, regulatory, research, and field evidence.',ARRAY['a general bounded technical, regulatory, manufacturer, research, or field-evidence question']::text[],ARRAY['the question is about the connected operator''s actual rig, equipment, or product combination','the operator wants the document suite that applies to a job']::text[],ARRAY['scout_get_cleaning_compatibility for the connected operator''s rig/product combination','scout_get_document_suite for applicable paperwork']::text[],'["one bounded business or technical question"]'::jsonb,ARRAY[]::text[],ARRAY['scout_search_document_standards','scout_get_document_standard']::text[],'none','{"retry":"Safe read: retry once only for a genuinely transient retryable error."}'::jsonb,'{"boundary":"Search text is transient business/technical context only; preserve uncertainty and source limits."}'::jsonb,'knowledge_documents',10,true,1),
('scout_get_cleaning_compatibility','Inspect the connected operator''s actual cleaning rig/equipment/product compatibility.',ARRAY['the operator asks whether their current rig can use a product','the operator asks about their selected equipment/product conflicts or unresolved combinations']::text[],ARRAY['a general product, manufacturer, technical, or regulatory question without connected equipment context']::text[],ARRAY['scout_search_knowledge for general evidence']::text[],'["connected operator equipment/rig or product selection when applicable"]'::jsonb,ARRAY['scout_get_profile_status']::text[],ARRAY['scout_claim_compatibility_research_task']::text[],'none','{"retry":"Safe read: retry once only for a genuinely transient retryable error."}'::jsonb,'{"boundary":"Static compatibility evidence only; it is not field clearance or an authorization to operate."}'::jsonb,'knowledge_documents',11,true,1),
('scout_get_document_suite','Build the operator-aware paperwork and document bundle for explicit service or job context.',ARRAY['the operator asks what paperwork, forms, or document bundle applies to a service or job']::text[],ARRAY['the operator only wants to locate a reusable standard or retrieve a known standard in depth']::text[],ARRAY['scout_search_document_standards to locate a standard','scout_get_document_standard for an identified slug']::text[],'["one or more explicit service slugs; bounded applicability context if needed"]'::jsonb,ARRAY[]::text[],ARRAY['scout_search_document_standards','scout_get_document_standard']::text[],'none','{"retry":"Safe read: retry once only for a genuinely transient retryable error."}'::jsonb,'{"boundary":"Applicability guidance, not a substitute for unresolved legal, label, or site-specific requirements."}'::jsonb,'knowledge_documents',12,true,1),
('scout_search_document_standards','Locate a relevant document standard or exemplar using a bounded need.',ARRAY['the operator needs to find a relevant standard, template, or exemplar']::text[],ARRAY['the operator already has the standard slug','the request is what documents apply to an explicit job']::text[],ARRAY['scout_get_document_standard for an identified standard','scout_get_document_suite for job/service applicability']::text[],'["bounded search phrase"]'::jsonb,ARRAY[]::text[],ARRAY['scout_get_document_standard']::text[],'none','{"retry":"Safe read: retry once only for a genuinely transient retryable error."}'::jsonb,'{"boundary":"Returns candidates; retain the returned standard slug rather than reconstructing it."}'::jsonb,'knowledge_documents',13,true,1),
('scout_get_document_standard','Retrieve an already identified document standard in depth.',ARRAY['a Scout document-standard slug is already known']::text[],ARRAY['the operator needs to search for a standard','the operator needs an applicability bundle']::text[],ARRAY['scout_search_document_standards to locate the slug','scout_get_document_suite for applicable paperwork']::text[],'["exact standard slug returned by Scout"]'::jsonb,ARRAY['scout_search_document_standards']::text[],ARRAY[]::text[],'none','{"retry":"Safe read: retry once only for a genuinely transient retryable error."}'::jsonb,'{"boundary":"Preserve standard currentness, requirements, and unknowns."}'::jsonb,'knowledge_documents',14,true,1),
('scout_plan_job','Create and persist a new structured job plan.',ARRAY['the operator asks to plan a new job at a target/date','a new structured job, static preflight, and permitted live checks are needed']::text[],ARRAY['the operator wants to inspect or refresh an existing job_id']::text[],ARRAY['scout_get_job_preflight for an existing job','scout_refresh_job_preflight to recompute an existing job']::text[],'["explicit service, target, and schedule facts"]'::jsonb,ARRAY['scout_get_lead_work_package']::text[],ARRAY['scout_get_job_preflight']::text[],'none','{"retry":"Do not blindly retry creation after an ambiguous outcome; inspect returned job_id or existing job state first."}'::jsonb,'{"boundary":"Creates a durable structured job; keep static readiness separate from live operability."}'::jsonb,'jobs',10,true,1),
('scout_get_job_preflight','Inspect an existing scoped job preflight.',ARRAY['the operator asks about a job already created in Scout','the operator supplies a Scout job_id']::text[],ARRAY['the operator needs a new job created','the operator asks to recompute static readiness or refresh live checks']::text[],ARRAY['scout_plan_job for a new job','scout_refresh_job_preflight for recomputation']::text[],'["exact job_id returned by Scout"]'::jsonb,ARRAY['scout_plan_job']::text[],ARRAY['scout_refresh_job_preflight']::text[],'none','{"retry":"Safe read: retry once only for a genuinely transient retryable error."}'::jsonb,'{"boundary":"Read-only inspection of a scoped job and its separate static/live state."}'::jsonb,'jobs',11,true,1),
('scout_refresh_job_preflight','Recompute readiness and refresh permitted live checks for an existing job.',ARRAY['the operator asks to refresh, recheck, or recompute an existing job preflight','departure is near and fresh permitted live checks are needed']::text[],ARRAY['a new job has not yet been created','the operator only wants to inspect current stored preflight state']::text[],ARRAY['scout_plan_job for a new job','scout_get_job_preflight for inspection only']::text[],'["exact job_id returned by Scout"]'::jsonb,ARRAY['scout_get_job_preflight','scout_plan_job']::text[],ARRAY['scout_get_job_preflight']::text[],'none','{"retry":"Non-idempotent refresh: do not blindly repeat after an ambiguous outcome; inspect existing job state first."}'::jsonb,'{"boundary":"May queue permitted live checks; it is not a new-job creation tool."}'::jsonb,'jobs',12,true,1),
('scout_get_entry_brief','Return Scout''s bounded general business brief.',ARRAY['the operator asks to be briefed','the operator asks what Scout is seeing or what is worth investigating generally']::text[],ARRAY['the operator asks what specifically needs immediate attention']::text[],ARRAY['scout_get_alerts for actionable/current attention items']::text[],'[]'::jsonb,ARRAY[]::text[],ARRAY['scout_get_alerts','scout_get_lead_work_package']::text[],'none','{"retry":"Safe read: retry once only for a genuinely transient retryable error."}'::jsonb,'{"boundary":"General bounded brief; do not treat it as an alert queue or force a follow-on tool."}'::jsonb,'briefing',10,true,1),
('scout_get_alerts','Return current actionable Scout items.',ARRAY['the operator asks what needs attention','the operator asks for current actionable items or alerts']::text[],ARRAY['the operator asks for a general brief or what Scout is seeing overall']::text[],ARRAY['scout_get_entry_brief for a general business brief']::text[],'[]'::jsonb,ARRAY[]::text[],ARRAY['scout_update_entry_item','scout_get_lead_work_package']::text[],'none','{"retry":"Safe read: retry once only for a genuinely transient retryable error."}'::jsonb,'{"boundary":"Actionable queue only; do not infer more alerts than Scout returns."}'::jsonb,'briefing',11,true,1),
('scout_prepare_external_context_request','Prepare a minimum necessary request for one external capability in the current task.',ARRAY['the operator explicitly wants Scout to use task-relevant external context such as calendar, CRM, flight, project, or fleet data','the task cannot proceed with Scout data alone and a reported external capability is relevant']::text[],ARRAY['general integration discovery or onboarding promotion','retrieving external records before Scout defines the minimum request and consent state']::text[],ARRAY['scout_list_external_capabilities or scout_resolve_external_integration for vocabulary/mapping questions']::text[],'["a reported or host-visible external capability","a narrow business purpose and requested fields"]'::jsonb,ARRAY['scout_get_external_capabilities']::text[],ARRAY['scout_set_external_capability_consent']::text[],'none','{"on_opt_in":"If first-use opt-in is required, continue without external data unless the operator explicitly grants access."}'::jsonb,'{"when":{"opt_in_required":true},"next_actions":[{"action":"obtain_explicit_operator_consent"},{"tool":"scout_set_external_capability_consent","when":"the operator explicitly grants access"},{"action":"request_only_approved_minimum_fields","when":"consent is granted"}],"boundary":"Do not retrieve external data until the explicit first-use choice has been recorded; never send the operator reply or surrounding conversation to Scout."}'::jsonb,'integrations',10,true,1),
('scout_set_external_capability_consent','Record the operator''s explicit first-use choice for one prepared external capability/source.',ARRAY['scout_prepare_external_context_request returned a specific first-use consent request and the operator explicitly grants, declines, disables, or resets it']::text[],ARRAY['before Scout prepared the capability/source key','without an explicit operator choice','as a substitute for retrieving external data']::text[],ARRAY['scout_prepare_external_context_request to establish the narrowed request and source_key']::text[],'["exact capability_slug and source_key returned by Scout","explicit operator choice"]'::jsonb,ARRAY['scout_prepare_external_context_request']::text[],ARRAY[]::text[],'explicit','{"retry":"Consent write: do not blindly retry after an ambiguous outcome; re-inspect the prepared request or consent state."}'::jsonb,'{"boundary":"Records consent state only. The host retrieves only approved minimum fields after consent; Scout does not receive the operator''s reply or surrounding chat."}'::jsonb,'integrations',11,true,1),
('scout_get_action_intents','Read pending or recent Scout action-intent state.',ARRAY['the operator asks about pending Scout actions','the host must inspect an intent before deciding whether an external action may be executed']::text[],ARRAY['the host is ready to execute an external action without reviewing intent state']::text[],ARRAY[]::text[],'[]'::jsonb,ARRAY[]::text[],ARRAY['scout_update_action_intent']::text[],'none','{"retry":"Safe read: retry once only for a genuinely transient retryable error."}'::jsonb,'{"boundary":"Action intents are recommendations or state, never permission to act."}'::jsonb,'integrations',20,true,1),
('scout_update_action_intent','Record an allowed action-intent transition or external execution outcome.',ARRAY['an exact intent_id is known and the operator explicitly approves, suppresses, or cancels it','a host/native connector must report dispatched, succeeded, or failed execution']::text[],ARRAY['the operator has not explicitly approved an awaiting_approval intent','there is no exact Scout intent_id','to initiate an external action by itself']::text[],ARRAY['scout_get_action_intents to inspect pending state first']::text[],'["exact intent_id returned by Scout","explicit operator approval for action=approve"]'::jsonb,ARRAY['scout_get_action_intents']::text[],ARRAY['scout_get_action_intents']::text[],'explicit','{"retry":"State-changing action: do not blindly retry after ambiguous execution; inspect the intent state first."}'::jsonb,'{"boundary":"This updates Scout state; it does not independently execute an external action."}'::jsonb,'integrations',21,true,1),
('scout_reject_public_equipment_candidates','Reject source-backed provisional equipment observations during onboarding.',ARRAY['the operator explicitly rejects provisional public equipment candidates Scout showed during onboarding']::text[],ARRAY['the operator has not seen or explicitly rejected the candidate','the request includes a guessed identifier or organization identifier']::text[],ARRAY['scout_get_profile_status to obtain the source-backed observation IDs']::text[],'["exact observation_ids returned by scout_get_profile_status","explicit operator rejection"]'::jsonb,ARRAY['scout_get_profile_status']::text[],ARRAY['scout_get_profile_status']::text[],'explicit','{"retry":"Destructive onboarding correction: do not repeat blindly; re-read profile status after an ambiguous result."}'::jsonb,'{"boundary":"Marks a provisional observation not current; it never accepts an organization ID or serial number."}'::jsonb,'equipment',20,true,1),
('scout_claim_compatibility_research_task','Claim one pending compatibility research task.',ARRAY['Scout needs a researcher to take a pending equipment/component compatibility task','the operator explicitly asks to work unresolved compatibility research']::text[],ARRAY['the operator asks a read-only general compatibility question','the operator asks about their selected rig/product evidence']::text[],ARRAY['scout_get_cleaning_compatibility for connected rig/product compatibility','scout_search_knowledge for general evidence']::text[],'[]'::jsonb,ARRAY['scout_get_cleaning_compatibility']::text[],ARRAY['scout_submit_compatibility_research']::text[],'none','{"retry":"Claim is non-idempotent. Do not repeat after ambiguous outcome; inspect the claimed task state first."}'::jsonb,'{"boundary":"Claiming changes task ownership/state even though it returns research material."}'::jsonb,'equipment',10,true,1),
('scout_submit_compatibility_research','Submit sourced evidence for a claimed compatibility research task.',ARRAY['a claimed research_request_id has evidence ready to submit']::text[],ARRAY['there is no claimed Scout research task','the operator only wants generic knowledge or current rig/product compatibility']::text[],ARRAY['scout_claim_compatibility_research_task to claim a task first']::text[],'["exact research_request_id from a claimed Scout task","typed source-backed evidence"]'::jsonb,ARRAY['scout_claim_compatibility_research_task']::text[],ARRAY['scout_create_compatibility_override']::text[],'none','{"retry":"Non-idempotent submission: inspect task state before retrying an ambiguous outcome."}'::jsonb,'{"boundary":"Persist only sourced typed evidence; unresolved domains remain unresolved unless evidence supports a conclusion."}'::jsonb,'equipment',11,true,1),
('scout_create_compatibility_override','Create a short provisional visibility override after unresolved research and explicit operator agreement.',ARRAY['research remains unresolved and the operator explicitly accepts the narrow temporary override']::text[],ARRAY['research has not been exhausted or no explicit operator agreement exists']::text[],ARRAY['scout_submit_compatibility_research to record evidence first']::text[],'["exact research_request_id","explicit operator agreement","permitted reason_code"]'::jsonb,ARRAY['scout_submit_compatibility_research']::text[],ARRAY['scout_revoke_compatibility_override']::text[],'explicit','{"retry":"Non-idempotent provisional override: inspect current override state before retrying."}'::jsonb,'{"boundary":"Temporary visibility only; it does not prove compatibility or eliminate operating restrictions."}'::jsonb,'equipment',12,true,1),
('scout_get_serial_recordkeeping_options','List confirmed equipment eligible for optional secure serial recordkeeping.',ARRAY['the operator explicitly asks to store or manage an equipment serial']::text[],ARRAY['onboarding is still collecting general equipment readiness','a serial is not explicitly relevant']::text[],ARRAY['scout_store_equipment_serial only after a confirmed eligible unit is selected']::text[],'[]'::jsonb,ARRAY[]::text[],ARRAY['scout_store_equipment_serial']::text[],'none','{"retry":"Safe read: retry once only for a genuinely transient retryable error."}'::jsonb,'{"boundary":"Does not reveal serial plaintext."}'::jsonb,'equipment',35,true,1),
('scout_store_equipment_serial','Store one operator-selected serial through the secure recordkeeping path.',ARRAY['the operator explicitly asks to store a serial for a confirmed eligible unit']::text[],ARRAY['during ordinary onboarding or without an operator-provided serial']::text[],ARRAY['scout_get_serial_recordkeeping_options to identify the eligible unit']::text[],'["explicit operator request","exact provider_equipment_id from Scout"]'::jsonb,ARRAY['scout_get_serial_recordkeeping_options']::text[],ARRAY['scout_update_recall_watch']::text[],'explicit','{"retry":"Secure write: do not blindly retry after an ambiguous outcome; inspect recordkeeping state first."}'::jsonb,'{"boundary":"Serials are a narrow sensitive exception and are never ordinary telemetry."}'::jsonb,'equipment',36,true,1),
('scout_reveal_equipment_serial','Explicitly reveal one stored serial.',ARRAY['the operator explicitly asks to see a particular stored serial']::text[],ARRAY['a serial is merely convenient or implied','the record_id is not exact']::text[],ARRAY[]::text[],'["explicit operator request","exact serial record_id"]'::jsonb,ARRAY['scout_get_serial_recordkeeping_options']::text[],ARRAY[]::text[],'explicit','{"retry":"Safe read of sensitive record: do not expand scope or guess record IDs."}'::jsonb,'{"boundary":"Reveal only the requested record; never enumerate serials."}'::jsonb,'equipment',37,true,1),
('scout_delete_equipment_serial','Delete one stored serial record.',ARRAY['the operator explicitly asks to delete a particular stored serial record']::text[],ARRAY['the record_id is guessed or deletion is not explicit']::text[],ARRAY[]::text[],'["explicit operator deletion request","exact serial record_id"]'::jsonb,ARRAY['scout_get_serial_recordkeeping_options']::text[],ARRAY[]::text[],'explicit','{"retry":"Destructive deletion: inspect record state before retrying an ambiguous outcome."}'::jsonb,'{"boundary":"Deletes the requested secure serial record only."}'::jsonb,'equipment',38,true,1),
('scout_get_due_recall_checks','Read due public recall/service-bulletin research tasks.',ARRAY['the operator asks what equipment recall or bulletin checks are due']::text[],ARRAY['the operator asks to manage serials generally']::text[],ARRAY['scout_get_serial_recordkeeping_options for serial recordkeeping']::text[],'[]'::jsonb,ARRAY[]::text[],ARRAY['scout_submit_recall_check']::text[],'none','{"retry":"Safe read: retry once only for a genuinely transient retryable error."}'::jsonb,'{"boundary":"Never returns serial plaintext."}'::jsonb,'equipment',40,true,1),
('scout_submit_recall_check','Record typed public recall research for a due unit.',ARRAY['a due recall task has authoritative public-source findings ready to record']::text[],ARRAY['there is no due task or source-backed public finding']::text[],ARRAY['scout_get_due_recall_checks to obtain due task context']::text[],'["exact record_id","typed public-source evidence"]'::jsonb,ARRAY['scout_get_due_recall_checks']::text[],ARRAY[]::text[],'none','{"retry":"Non-idempotent submission: inspect existing recall state before retrying ambiguous outcome."}'::jsonb,'{"boundary":"Public recall evidence only; do not submit notes or serial plaintext."}'::jsonb,'equipment',41,true,1),
('scout_list_external_capabilities','Read Scout''s external capability vocabulary and conservative mappings.',ARRAY['the operator asks what connected capabilities or integrations may help','a capability mapping needs discovery before task-specific consent']::text[],ARRAY['the task already has a known relevant capability and needs a narrowed request']::text[],ARRAY['scout_prepare_external_context_request for a specific task-context request']::text[],'[]'::jsonb,ARRAY[]::text[],ARRAY['scout_prepare_external_context_request']::text[],'none','{"retry":"Safe read: retry once only for a genuinely transient retryable error."}'::jsonb,'{"boundary":"Metadata only; it does not inspect external accounts or retrieve records."}'::jsonb,'integrations',35,true,1),
('scout_resolve_external_integration','Resolve a host-visible integration product name to conservative Scout mappings.',ARRAY['the host knows an integration product name but needs Scout''s capability mapping']::text[],ARRAY['the host needs task data or consent handling']::text[],ARRAY['scout_prepare_external_context_request for a task-specific request']::text[],'["host-visible integration name"]'::jsonb,ARRAY[]::text[],ARRAY['scout_prepare_external_context_request']::text[],'none','{"retry":"Safe read: retry once only for a genuinely transient retryable error."}'::jsonb,'{"boundary":"Uses a product name only; never send account identifiers or credentials."}'::jsonb,'integrations',36,true,1),
('scout_report_external_capabilities','Report only Scout-relevant capabilities already visible to the host.',ARRAY['the host needs to tell Scout which relevant capabilities it already has']::text[],ARRAY['the host would need to inspect external accounts, credentials, or records to report them']::text[],ARRAY[]::text[],'["capability metadata already visible to the host"]'::jsonb,ARRAY[]::text[],ARRAY['scout_prepare_external_context_request']::text[],'none','{"retry":"Write metadata: do not blindly retry after ambiguous outcome; inspect reported capability state."}'::jsonb,'{"boundary":"Capability metadata only; never report external account data, customer records, tool output, or chat."}'::jsonb,'integrations',37,true,1),
('scout_get_external_capabilities','Read the capability metadata already reported for this Scout connection.',ARRAY['the operator asks what Scout knows about currently reported external capabilities']::text[],ARRAY['the host needs general vocabulary or a task-specific narrowed request']::text[],ARRAY['scout_list_external_capabilities for vocabulary','scout_prepare_external_context_request for a task']::text[],'[]'::jsonb,ARRAY[]::text[],ARRAY['scout_prepare_external_context_request']::text[],'none','{"retry":"Safe read: retry once only for a genuinely transient retryable error."}'::jsonb,'{"boundary":"Returns capability metadata, never external records."}'::jsonb,'integrations',38,true,1),
('scout_update_profile','Persist explicitly requested typed business setup and readiness changes.',ARRAY['the operator explicitly asks to update services, operating area, rigs, equipment, credentials, or profile state']::text[],ARRAY['Scout only needs to inspect readiness','the host has inferred values that the operator has not confirmed']::text[],ARRAY['scout_get_profile_status to inspect current state','scout_list_onboarding_options to browse supported choices']::text[],'["explicit operator-provided or confirmed typed values"]'::jsonb,ARRAY['scout_get_profile_status']::text[],ARRAY['scout_get_profile_status']::text[],'none','{"retry":"Profile write: inspect current state before repeating an ambiguous update."}'::jsonb,'{"boundary":"Do not persist generic notes, conversations, or inferred services/equipment as confirmed state."}'::jsonb,'startup',35,true,1),
('scout_list_onboarding_options','Read supported service, credential, and onboarding choices.',ARRAY['the operator explicitly asks which services, credentials, or setup choices Scout supports']::text[],ARRAY['the operator only needs current profile state or a task-specific action']::text[],ARRAY['scout_get_profile_status for current state','scout_get_capabilities for the broad feature picture']::text[],'[]'::jsonb,ARRAY[]::text[],ARRAY['scout_update_profile']::text[],'none','{"retry":"Safe read: retry once only for a genuinely transient retryable error."}'::jsonb,'{"boundary":"Catalog only; do not infer that a parent-only or unconfirmed service is directly configurable."}'::jsonb,'startup',36,true,1),
('scout_search_equipment_models','Resolve an operator-provided equipment model without a serial.',ARRAY['the operator needs Scout to identify or look up an equipment model']::text[],ARRAY['a serial must be stored or revealed']::text[],ARRAY['scout_get_serial_recordkeeping_options for serial workflows']::text[],'["bounded model text"]'::jsonb,ARRAY[]::text[],ARRAY['scout_update_profile']::text[],'none','{"retry":"Safe read: retry once only for a genuinely transient retryable error."}'::jsonb,'{"boundary":"Model lookup only; never send serial numbers."}'::jsonb,'equipment',45,true,1),
('scout_match_media_asset','Match bounded typed photo clues to public business/facility records.',ARRAY['the operator asks to identify a business or building from bounded location/name/address/signage clues']::text[],ARRAY['the host only has image binary, URLs, EXIF dumps, a media-library identifier, or a visual narrative']::text[],ARRAY[]::text[],'["typed bounded clues only"]'::jsonb,ARRAY[]::text[],ARRAY['scout_get_lead_work_package']::text[],'none','{"retry":"Safe read: retry once only for a genuinely transient retryable error."}'::jsonb,'{"boundary":"A match does not prove ownership, condition, or service need."}'::jsonb,'opportunities',45,true,1),
('scout_get_privacy_summary','Explain Scout''s connection privacy, retention, scopes, and allowed-tool boundary.',ARRAY['the operator explicitly asks what Scout can access, store, or see']::text[],ARRAY['a task merely needs routing or profile state']::text[],ARRAY[]::text[],'[]'::jsonb,ARRAY[]::text[],ARRAY[]::text[],'none','{"retry":"Safe read: retry once only for a genuinely transient retryable error."}'::jsonb,'{"boundary":"Present the practical privacy boundary first; do not dump internal implementation unless audit detail is requested."}'::jsonb,'startup',45,true,1),
('scout_get_entry_preferences','Read bounded briefing/feed preferences.',ARRAY['the operator asks to inspect Scout greeting or feed behavior']::text[],ARRAY['the operator asks to change it']::text[],ARRAY['scout_update_entry_preferences to change settings']::text[],'[]'::jsonb,ARRAY[]::text[],ARRAY['scout_update_entry_preferences']::text[],'none','{"retry":"Safe read: retry once only for a genuinely transient retryable error."}'::jsonb,'{"boundary":"Finite UX preferences only."}'::jsonb,'briefing',35,true,1),
('scout_update_entry_preferences','Update bounded briefing/feed behavior.',ARRAY['the operator explicitly asks to change Scout greeting or feed preferences']::text[],ARRAY['the host has inferred a preference without an explicit request']::text[],ARRAY['scout_get_entry_preferences to inspect current settings']::text[],'["explicit requested preference change"]'::jsonb,ARRAY['scout_get_entry_preferences']::text[],ARRAY['scout_get_entry_preferences']::text[],'none','{"retry":"Preference write: inspect state before repeating an ambiguous update."}'::jsonb,'{"boundary":"Finite settings only; no arbitrary preference blob or personal commentary."}'::jsonb,'briefing',36,true,1),
('scout_update_entry_item','Update one exact Scout entry/feed item.',ARRAY['the operator explicitly asks to dismiss, snooze, complete, reset, or mark a returned entry item opened']::text[],ARRAY['an item_key is not exact or the operator has not selected an item']::text[],ARRAY['scout_get_alerts or scout_get_entry_brief to obtain current item context']::text[],'["exact item_key returned by Scout","explicit requested action"]'::jsonb,ARRAY['scout_get_alerts','scout_get_entry_brief']::text[],ARRAY[]::text[],'none','{"retry":"State-changing feed action: inspect state before retrying ambiguity."}'::jsonb,'{"boundary":"Acts only on the selected Scout item."}'::jsonb,'briefing',37,true,1),
('scout_revoke_compatibility_override','Revoke an active provisional compatibility override.',ARRAY['the operator explicitly requests an override revoked or a permitted revocation reason is established']::text[],ARRAY['no exact active override_id is known']::text[],ARRAY[]::text[],'["exact override_id"]'::jsonb,ARRAY['scout_create_compatibility_override']::text[],ARRAY[]::text[],'explicit','{"retry":"State-changing revocation: inspect override state before retrying ambiguity."}'::jsonb,'{"boundary":"Revokes only the specified provisional override."}'::jsonb,'equipment',42,true,1),
('scout_update_recall_watch','Enable or disable recall monitoring for one stored unit.',ARRAY['the operator explicitly requests recall-watch changes for a selected stored unit']::text[],ARRAY['the record_id is not exact or the operator did not request the change']::text[],ARRAY['scout_get_serial_recordkeeping_options for secure unit context']::text[],'["exact record_id","explicit operator request"]'::jsonb,ARRAY['scout_get_serial_recordkeeping_options']::text[],ARRAY['scout_get_due_recall_checks']::text[],'none','{"retry":"State-changing watch update: inspect watch state before retrying ambiguity."}'::jsonb,'{"boundary":"Never uses or exposes serial plaintext."}'::jsonb,'equipment',43,true,1)
on conflict (tool_name) do update set
  summary=excluded.summary,when_cues=excluded.when_cues,not_when_cues=excluded.not_when_cues,
  prefer_over=excluded.prefer_over,prerequisites=excluded.prerequisites,
  usually_preceded_by=excluded.usually_preceded_by,usually_followed_by=excluded.usually_followed_by,
  confirmation=excluded.confirmation,failure_policy=excluded.failure_policy,result_rules=excluded.result_rules,
  instruction_group=excluded.instruction_group,instruction_priority=excluded.instruction_priority,
  active=excluded.active,routing_version=greatest(agent_contract.tool_routing.routing_version,excluded.routing_version),
  updated_at=clock_timestamp();

insert into agent_contract.routing_policies(policy_key,title,body,instruction_priority,active) values
('direct_routing','Direct routing before lookup','Route an explicit, recognizable Scout task directly to its tool. Do not call scout_get_capabilities or scout_get_profile_status as a routine preflight.',10,true),
('startup','Conditional startup','For a greeting or no explicit Scout task, call scout_get_profile_status. For an explicit task, route directly; inspect profile state only when that task materially needs operator-specific readiness that is not already known.',20,true),
('identifiers','Stable identifiers and sequences','Reuse exact Scout identifiers such as candidate_key, job_id, intent_id, research_request_id, observation_id, source_key, and standard slug. Never reconstruct identifiers, infer hidden records, or replace a returned identifier with a newly guessed one.',30,true),
('errors','Structured error recovery','When retryable=false, do not repeat unchanged. For a safe, read-only, idempotent operation with a genuinely transient retryable=true error, one unchanged retry may be appropriate. Never blindly retry a write, claim, approval, or destructive action after an ambiguous outcome; inspect state first.',40,true),
('privacy_and_presentation','Privacy and presentation','Send the minimum structured business data accepted by the selected tool; never send chat, transcripts, credentials, secrets, or unrelated context. Honor display_contract and exposure_contract when presenting results, but do not render the contract objects or expose proprietary methods, security controls, internal diagnostics, or scoring.',50,true)
on conflict (policy_key) do update set
  title=excluded.title,body=excluded.body,instruction_priority=excluded.instruction_priority,
  active=excluded.active,updated_at=clock_timestamp();

create or replace function public.scout_get_agent_tool_contract_manifest_internal()
returns jsonb
language sql
security definer
set search_path to ''
as $function$
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'tool_name', t.tool_name,
      'response_type_slug', t.response_type_slug,
      'output_schema_slug', t.output_schema_slug,
      'output_schema', s.json_schema,
      'annotations', jsonb_build_object(
        'readOnlyHint', t.read_only,
        'destructiveHint', t.destructive,
        'idempotentHint', t.idempotent,
        'openWorldHint', t.open_world
      ),
      'model_visible', t.model_visible,
      'app_visible', t.app_visible,
      'contract_version', t.contract_version,
      'routing', case when r.tool_name is null or not r.active then null else jsonb_build_object(
        'version',r.routing_version,
        'summary',r.summary,
        'when',to_jsonb(r.when_cues),
        'not_when',to_jsonb(r.not_when_cues),
        'prefer_over',to_jsonb(r.prefer_over),
        'prerequisites',r.prerequisites,
        'usually_preceded_by',to_jsonb(r.usually_preceded_by),
        'usually_followed_by',to_jsonb(r.usually_followed_by),
        'confirmation',r.confirmation,
        'failure_policy',r.failure_policy,
        'result_rules',r.result_rules,
        'instruction_group',r.instruction_group,
        'instruction_priority',r.instruction_priority
      ) end,
      'routing_description', case when r.tool_name is null or not r.active then null else
        concat_ws(E'\n',
          case when cardinality(r.when_cues)>0 then 'Use this when: '||array_to_string(r.when_cues,'; ')||'.' end,
          case when cardinality(r.not_when_cues)>0 then 'Do not use this when: '||array_to_string(r.not_when_cues,'; ')||'.' end,
          case when cardinality(r.prefer_over)>0 then 'Prefer this over: '||array_to_string(r.prefer_over,', ')||'.' end,
          case when jsonb_array_length(r.prerequisites)>0 then 'Prerequisite: '||(select string_agg(x.value,'; ') from jsonb_array_elements_text(r.prerequisites) x(value))||'.' end,
          case when r.confirmation='explicit' then 'Confirmation: obtain explicit operator approval before this action.' end,
          case when coalesce(r.failure_policy->>'retry','')<>'' then 'Failure/retry: '||(r.failure_policy->>'retry') end,
          case when coalesce(r.failure_policy->>'on_blocked','')<>'' then 'If blocked: '||(r.failure_policy->>'on_blocked') end,
          case when coalesce(r.failure_policy->>'on_opt_in','')<>'' then 'If opt-in is required: '||(r.failure_policy->>'on_opt_in') end,
          case when coalesce(r.result_rules->>'boundary','')<>'' then 'Important: '||(r.result_rules->>'boundary') end
        )
      end
    ) order by t.tool_name
  ), '[]'::jsonb)
  from agent_contract.tool_contracts t
  join agent_contract.output_schema_families s on s.slug=t.output_schema_slug
  left join agent_contract.tool_routing r on r.tool_name=t.tool_name
  where t.active;
$function$;

create or replace function public.scout_get_mcp_routing_manifest_internal()
returns jsonb
language sql
stable
security definer
set search_path to ''
as $function$
  with policy_rows as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'key',p.policy_key,'title',p.title,'body',p.body,'priority',p.instruction_priority
    ) order by p.instruction_priority,p.policy_key),'[]'::jsonb) as payload
    from agent_contract.routing_policies p
    where p.active
  ),
  tool_rows as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'tool_name',r.tool_name,
      'summary',r.summary,
      'when',to_jsonb(r.when_cues),
      'not_when',to_jsonb(r.not_when_cues),
      'prefer_over',to_jsonb(r.prefer_over),
      'prerequisites',r.prerequisites,
      'usually_preceded_by',to_jsonb(r.usually_preceded_by),
      'usually_followed_by',to_jsonb(r.usually_followed_by),
      'confirmation',r.confirmation,
      'failure_policy',r.failure_policy,
      'result_rules',r.result_rules,
      'instruction_group',r.instruction_group,
      'instruction_priority',r.instruction_priority,
      'capabilities',coalesce(cap.payload,'[]'::jsonb)
    ) order by r.instruction_group,r.instruction_priority,r.tool_name),'[]'::jsonb) as payload
    from agent_contract.tool_routing r
    join agent_contract.tool_contracts t on t.tool_name=r.tool_name and t.active and t.model_visible
    left join lateral (
      select jsonb_agg(jsonb_build_object(
        'slug',c.slug,'title',c.title,'status',c.status,
        'task_cues',to_jsonb(c.task_cues),'example_requests',to_jsonb(c.example_requests),
        'primary_tools',to_jsonb(c.primary_tools),'required_scopes',to_jsonb(c.required_scopes),
        'requires_critical_setup',c.requires_critical_setup,
        'requires_external_capability',c.requires_external_capability,
        'first_use_opt_in',c.first_use_opt_in,'suggestion_policy',c.suggestion_policy
      ) order by c.sort_order,c.slug) as payload
      from agent_contract.tool_capability_links l
      join commerce.scout_capability_catalog c on c.slug=l.capability_slug and c.active
      where l.tool_name=r.tool_name
    ) cap on true
    where r.active
  )
  select jsonb_build_object(
    'version','routing-v1',
    'policies',policy_rows.payload,
    'tools',tool_rows.payload
  )
  from policy_rows,tool_rows;
$function$;
revoke all on function public.scout_get_mcp_routing_manifest_internal() from public,anon,authenticated;
grant execute on function public.scout_get_mcp_routing_manifest_internal() to service_role;

create or replace function public.scout_decorate_agent_response(p_tool_name text,p_payload jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_payload jsonb;
  v_next_actions jsonb;
begin
  v_payload:=public.scout_apply_ip_exposure_policy(p_tool_name,coalesce(p_payload,'{}'::jsonb));
  if jsonb_typeof(v_payload)='object' then
    select r.result_rules->'next_actions' into v_next_actions
    from agent_contract.tool_routing r
    where r.tool_name=p_tool_name
      and r.active
      and r.result_rules ? 'next_actions'
      and (not (r.result_rules ? 'when') or v_payload @> (r.result_rules->'when'))
    limit 1;
    if v_next_actions is not null and not (v_payload ? 'next_actions') then
      v_payload:=v_payload||jsonb_build_object('next_actions',v_next_actions);
    end if;
    return v_payload||jsonb_build_object(
      'display_contract',public.scout_get_agent_display_contract(p_tool_name,v_payload),
      'exposure_contract',public.scout_get_agent_exposure_contract(p_tool_name)
    );
  end if;
  return jsonb_build_object(
    'data',v_payload,
    'display_contract',public.scout_get_agent_display_contract(p_tool_name,null),
    'exposure_contract',public.scout_get_agent_exposure_contract(p_tool_name)
  );
end
$function$;

CREATE OR REPLACE FUNCTION public.scout_get_connection_privacy_summary_core_v2(p_connection_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_conn commerce.provider_agent_connections%rowtype;
  v_settings agent_privacy.connection_settings%rowtype;
  v_notice agent_privacy.privacy_notices%rowtype;
  v_tools jsonb;
  v_retention jsonb;
  v_purposes jsonb;
begin
  select * into v_conn from commerce.provider_agent_connections
  where id=p_connection_id and status='active' and (expires_at is null or expires_at>now());
  if not found then raise exception 'active Scout connection not found'; end if;

  select * into v_settings from agent_privacy.connection_settings where connection_id=p_connection_id;
  if not found then raise exception 'Scout privacy settings are missing for this connection'; end if;
  select * into v_notice from agent_privacy.privacy_notices where version=v_settings.privacy_notice_version;
  if not found then raise exception 'Scout privacy notice is missing for this connection'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'tool_name',p.tool_name,
    'required_scope',p.required_scope,
    'purpose',p.purpose,
    'raw_payload_persisted',p.raw_payload_persisted,
    'persistence_class',p.persistence_class,
    'privacy_notes',p.privacy_notes,
    'contract_version',p.contract_version,
    'agent_free_text_allowed',p.agent_free_text_allowed,
    'nested_contract',p.nested_contract
  ) order by p.tool_name),'[]'::jsonb)
  into v_tools
  from agent_privacy.tool_policies p
  join agent_contract.tool_contracts tc on tc.tool_name=p.tool_name and tc.active and tc.model_visible
  where p.enabled and (p.required_scope is null or p.required_scope=any(v_conn.scopes));

  select coalesce(jsonb_agg(jsonb_build_object(
    'data_class',r.data_class,
    'retention_seconds',r.retention_seconds,
    'persistence_mode',r.persistence_mode,
    'rationale',r.rationale
  ) order by r.data_class),'[]'::jsonb)
  into v_retention from agent_privacy.retention_rules r where r.user_visible;

  select coalesce(jsonb_agg(jsonb_build_object(
    'code',b.code,'title',b.title,'allowed_domains',to_jsonb(b.allowed_domains)
  ) order by b.code),'[]'::jsonb)
  into v_purposes from agent_privacy.business_purpose_codes b where b.active;

  return jsonb_build_object(
    'privacy_mode',v_settings.privacy_mode,
    'purpose','business_only',
    'privacy_contract_version','privacy-contract-v2',
    'consent_state',v_settings.consent_state,
    'consent_granted_at',v_settings.consent_granted_at,
    'notice_version',v_notice.version,
    'notice_title',v_notice.title,
    'summary',v_notice.summary,
    'commitments',v_notice.commitments,
    'zero_chat_explanation','Zero chat means Scout does not retain the originating AI conversation or raw MCP request body. It does not mean Scout collects no product analytics.',
    'product_analytics',jsonb_build_object(
      'purpose',jsonb_build_array('product reliability','feature usefulness','activation and workflow analysis','opportunity/source usefulness','privacy and abuse detection'),
      'captures',jsonb_build_array('tool and feature names','timestamps and sessionization','client type','organization/connection/user/OAuth-client identifiers used internally','outcome and HTTP status','latency and request size','argument field names and privacy flags','coarse selected workflow dimensions such as service, county/state, bands, filters, counts, source family, rank/evidence metadata, timing buckets, and equipment counts'),
      'does_not_intentionally_capture',jsonb_build_array('originating AI message or transcript','system or developer prompts','raw MCP request bodies','passwords, API keys, tokens, or obvious secrets','unrelated sensitive personal data','exact job address or coordinates in telemetry','exact Explore Growth budget in telemetry'),
      'raw_structured_retention_days',730,
      'aggregate_rollups','Aggregate product rollups may remain after underlying raw telemetry expires.',
      'visibility','Private Scout operational analytics; not exposed to other operators.'
    ),
    'raw_request_retention_seconds',v_settings.raw_request_retention_seconds,
    'request_audit_metadata_retention_days',v_settings.audit_metadata_retention_days,
    'scopes',to_jsonb(v_conn.scopes),
    'allowed_tools',v_tools,
    'external_business_purpose_codes',v_purposes,
    'retention_rules',v_retention,
    'cannot_access',jsonb_build_array('general AI chat history','AI account inbox/history','unconnected email','unconnected calendar','unconnected drive/files','unconnected photo library'),
    'separate_opt_in_connections',jsonb_build_array('calendar','email','drive/files','media libraries','accounting','CRM'),
    'activity_visibility','Scout keeps a short metadata-only request audit and a separate privacy-minimized product-analytics stream. Neither intentionally stores raw AI requests; the product-analytics stream may be retained for up to 730 days.',
    'input_minimization','Operational decisions use fixed reason/purpose codes and structured business fields. Generic agent notes/comments are rejected. Sourced prose is accepted only where the business evidence artifact itself requires it.'
  );
end
$function$;

-- Catalog examples and task cues become auditable routing fixtures without storing live user prompts.
insert into agent_contract.routing_eval_fixtures(
  fixture_key,fixture_source,prompt,expected_first_tool,forbidden_first_tools,expected_sequence,assertions,active
)
select
  'catalog.example.'||regexp_replace(c.slug,'[^a-z0-9]+','_','g'),
  'catalog_example',c.example_requests[1],c.primary_tools[1],'{}'::text[],array[c.primary_tools[1]],
  jsonb_build_object('catalog_seed',true),true
from commerce.scout_capability_catalog c
join agent_contract.tool_contracts t on t.tool_name=c.primary_tools[1] and t.active and t.model_visible
where c.active and c.status='available' and cardinality(c.example_requests)>0 and cardinality(c.primary_tools)>0
on conflict (fixture_key) do update set
  fixture_source=excluded.fixture_source,prompt=excluded.prompt,expected_first_tool=excluded.expected_first_tool,
  forbidden_first_tools=excluded.forbidden_first_tools,expected_sequence=excluded.expected_sequence,
  assertions=excluded.assertions,active=excluded.active,updated_at=clock_timestamp();

insert into agent_contract.routing_eval_fixtures(
  fixture_key,fixture_source,prompt,expected_first_tool,forbidden_first_tools,expected_sequence,assertions,active
)
select
  'catalog.cue.'||regexp_replace(c.slug,'[^a-z0-9]+','_','g'),
  'catalog_task_cue',c.task_cues[1],c.primary_tools[1],'{}'::text[],array[c.primary_tools[1]],
  jsonb_build_object('catalog_seed',true),true
from commerce.scout_capability_catalog c
join agent_contract.tool_contracts t on t.tool_name=c.primary_tools[1] and t.active and t.model_visible
where c.active and c.status='available' and cardinality(c.task_cues)>0 and cardinality(c.primary_tools)>0
on conflict (fixture_key) do update set
  fixture_source=excluded.fixture_source,prompt=excluded.prompt,expected_first_tool=excluded.expected_first_tool,
  forbidden_first_tools=excluded.forbidden_first_tools,expected_sequence=excluded.expected_sequence,
  assertions=excluded.assertions,active=excluded.active,updated_at=clock_timestamp();

insert into agent_contract.routing_eval_fixtures(
  fixture_key,fixture_source,prompt,expected_first_tool,forbidden_first_tools,expected_sequence,assertions,active
) values
  ('collision.find_roof_work','collision','Find roof inspection work.','scout_find_opportunities',array['scout_find_growth_options','scout_get_capabilities','scout_get_profile_status'],array['scout_find_opportunities'],jsonb_build_object('no_capability_preflight',true,'no_profile_preflight',true),true),
  ('collision.add_drone_service','collision','What drone service should I add?','scout_find_growth_options',array['scout_find_opportunities','scout_get_capabilities','scout_get_profile_status'],array['scout_find_growth_options'],jsonb_build_object('no_capability_preflight',true,'no_profile_preflight',true),true),
  ('collision.current_rig_product','collision','Can my current rig use this product?','scout_get_cleaning_compatibility',array['scout_search_knowledge','scout_get_capabilities'],array['scout_get_cleaning_compatibility'],jsonb_build_object('near_neighbor','connected_equipment'),true),
  ('collision.service_paperwork','collision','What paperwork applies to this service?','scout_get_document_suite',array['scout_search_document_standards','scout_get_document_standard'],array['scout_get_document_suite'],jsonb_build_object('near_neighbor','applicability'),true),
  ('collision.attention','collision','What needs my attention?','scout_get_alerts',array['scout_get_entry_brief'],array['scout_get_alerts'],jsonb_build_object('near_neighbor','actionability'),true),
  ('collision.brief','collision','Brief me on what Scout is seeing.','scout_get_entry_brief',array['scout_get_alerts'],array['scout_get_entry_brief'],jsonb_build_object('near_neighbor','general_brief'),true),
  ('collision.capabilities','collision','What does Scout do?','scout_get_capabilities',array['scout_get_profile_status'],array['scout_get_capabilities'],jsonb_build_object('meta_tool_explicit_request',true),true),
  ('startup.greeting','safety','Hello, Scout.','scout_get_profile_status','{}'::text[],array['scout_get_profile_status'],jsonb_build_object('conditional_startup',true),true),
  ('sequence.document_standard','sequence','Find the applicable document standard, then open it.','scout_search_document_standards','{}'::text[],array['scout_search_document_standards','scout_get_document_standard'],jsonb_build_object('stable_slug_reuse',true),true),
  ('sequence.job_preflight','sequence','Create a new structured job plan and then inspect its preflight.','scout_plan_job','{}'::text[],array['scout_plan_job','scout_get_job_preflight'],jsonb_build_object('stable_job_id_reuse',true,'non_idempotent_retry_guard',true),true),
  ('sequence.external_consent','sequence','Use my calendar only if I explicitly approve the minimum needed data request.','scout_prepare_external_context_request','{}'::text[],array['scout_prepare_external_context_request','scout_set_external_capability_consent','scout_prepare_external_context_request'],jsonb_build_object('explicit_consent',true,'minimum_data_only',true),true),
  ('sequence.action_intent','sequence','Show pending action intents; approve one only after I explicitly say yes.','scout_get_action_intents','{}'::text[],array['scout_get_action_intents','scout_update_action_intent'],jsonb_build_object('explicit_approval',true,'execution_requires_state_reporting',true),true),
  ('sequence.compatibility_claim','sequence','Take a pending compatibility research task and submit evidence for it.','scout_claim_compatibility_research_task',array['scout_get_compatibility_research'],array['scout_claim_compatibility_research_task','scout_submit_compatibility_research'],jsonb_build_object('claim_is_non_idempotent',true),true),
  ('safety.discovery_status','safety','Am I at a Scout discovery limit?','scout_get_discovery_status',array['scout_find_opportunities','scout_find_growth_options'],array['scout_get_discovery_status'],jsonb_build_object('not_discovery_preflight',true),true),
  ('safety.public_equipment_rejection','safety','That public equipment candidate is not mine; reject it.','scout_reject_public_equipment_candidates','{}'::text[],array['scout_get_profile_status','scout_reject_public_equipment_candidates'],jsonb_build_object('explicit_confirmation',true,'source_backed_id_only',true),true)
on conflict (fixture_key) do update set
  fixture_source=excluded.fixture_source,prompt=excluded.prompt,expected_first_tool=excluded.expected_first_tool,
  forbidden_first_tools=excluded.forbidden_first_tools,expected_sequence=excluded.expected_sequence,
  assertions=excluded.assertions,active=excluded.active,updated_at=clock_timestamp();

create or replace function agent_contract.assert_tool_routing_integrity()
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_missing text[];
  v_unprotected text[];
begin
  select array_agg(t.tool_name order by t.tool_name) into v_missing
  from agent_contract.tool_contracts t
  left join agent_contract.tool_routing r on r.tool_name=t.tool_name and r.active
  where t.active and t.model_visible and r.tool_name is null;
  if coalesce(cardinality(v_missing),0)>0 then
    raise exception 'model-visible Scout tools without active routing metadata: %',array_to_string(v_missing,', ');
  end if;

  select array_agg(t.tool_name order by t.tool_name) into v_unprotected
  from agent_contract.tool_contracts t
  left join agent_privacy.tool_policies p on p.tool_name=t.tool_name and p.enabled
  where t.active and t.model_visible and p.tool_name is null;
  if coalesce(cardinality(v_unprotected),0)>0 then
    raise exception 'model-visible Scout tools without enabled privacy policy: %',array_to_string(v_unprotected,', ');
  end if;

  if not exists (select 1 from agent_contract.tool_capability_links where tool_name='scout_get_discovery_status' and capability_slug='opportunities.discovery')
     or not exists (select 1 from agent_contract.tool_capability_links where tool_name='scout_reject_public_equipment_candidates' and capability_slug='equipment.rig_readiness')
     or not exists (select 1 from agent_contract.tool_capability_links where tool_name='scout_set_external_capability_consent' and capability_slug='integrations.task_context') then
    raise exception 'required routing ownership links are missing';
  end if;

  if exists (select 1 from agent_contract.tool_contracts where tool_name='scout_submit_business_signal' and (model_visible or app_visible))
     or exists (select 1 from agent_privacy.tool_policies where tool_name='scout_submit_business_signal' and enabled)
     or exists (select 1 from commerce.scout_capability_catalog where slug='integrations.business_signal_ingress' and status<>'paused') then
    raise exception 'parked business-signal ingress must remain non-exposed and paused';
  end if;

  if not exists (select 1 from agent_contract.tool_contracts where tool_name='scout_claim_compatibility_research_task' and active and model_visible and not read_only and not idempotent)
     or exists (select 1 from agent_contract.tool_contracts where tool_name='scout_get_compatibility_research' and model_visible) then
    raise exception 'compatibility research claim migration is not coherent';
  end if;
end
$function$;

revoke all on function agent_contract.assert_tool_routing_integrity() from public,anon,authenticated;
grant execute on function agent_contract.assert_tool_routing_integrity() to service_role;

create or replace function agent_contract.assert_routing_eval_fixtures()
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_bad text[];
  v_sequence_bad text[];
begin
  select array_agg(f.fixture_key order by f.fixture_key) into v_bad
  from agent_contract.routing_eval_fixtures f
  left join agent_contract.tool_contracts t on t.tool_name=f.expected_first_tool and t.active and t.model_visible
  left join agent_contract.tool_routing r on r.tool_name=f.expected_first_tool and r.active
  where f.active and (t.tool_name is null or r.tool_name is null or f.expected_first_tool=any(f.forbidden_first_tools));
  if coalesce(cardinality(v_bad),0)>0 then
    raise exception 'invalid routing first-tool fixtures: %',array_to_string(v_bad,', ');
  end if;

  with expanded as (
    select f.fixture_key,u.tool_name
    from agent_contract.routing_eval_fixtures f
    cross join lateral unnest(f.expected_sequence) u(tool_name)
    where f.active
  )
  select array_agg(e.fixture_key||':'||e.tool_name order by e.fixture_key,e.tool_name) into v_sequence_bad
  from expanded e
  left join agent_contract.tool_contracts t on t.tool_name=e.tool_name and t.active and t.model_visible
  where t.tool_name is null;
  if coalesce(cardinality(v_sequence_bad),0)>0 then
    raise exception 'routing fixtures reference non-visible tools: %',array_to_string(v_sequence_bad,', ');
  end if;

  if not exists (
    select 1 from agent_contract.routing_eval_fixtures
    where fixture_key='sequence.external_consent' and assertions @> '{"explicit_consent":true}'::jsonb
  ) or not exists (
    select 1 from agent_contract.routing_eval_fixtures
    where fixture_key='collision.find_roof_work' and 'scout_find_growth_options'=any(forbidden_first_tools)
  ) then
    raise exception 'required routing collision/consent fixtures are missing';
  end if;
end
$function$;

revoke all on function agent_contract.assert_routing_eval_fixtures() from public,anon,authenticated;
grant execute on function agent_contract.assert_routing_eval_fixtures() to service_role;

create or replace view analytics.routing_quality
with (security_invoker=true)
as
with ordered as (
  select
    e.session_id,e.client_type,e.tool_name,e.outcome,e.occurred_at,e.id,
    row_number() over (partition by e.session_id order by e.occurred_at,e.id) as session_call_number,
    lead(e.tool_name) over (partition by e.session_id order by e.occurred_at,e.id) as next_tool
  from telemetry.events e
  where e.event_type='tool_call' and e.tool_name is not null
),
scored as (
  select o.*,tc.idempotent,tr.usually_followed_by
  from ordered o
  left join agent_contract.tool_contracts tc on tc.tool_name=o.tool_name
  left join agent_contract.tool_routing tr on tr.tool_name=o.tool_name and tr.active
)
select
  client_type,
  count(*) as tool_calls,
  count(*) filter (where outcome='allowed') as allowed_tool_calls,
  count(*) filter (where outcome in ('rejected_privacy','rejected_scope','error')) as blocked_or_error_calls,
  count(*) filter (where tool_name='scout_get_capabilities') as capability_lookup_calls,
  count(*) filter (where tool_name='scout_get_profile_status') as profile_status_calls,
  count(*) filter (where session_id is not null and session_call_number=1 and tool_name in ('scout_get_capabilities','scout_get_profile_status')) as meta_or_profile_first_calls,
  count(*) filter (where session_id is not null and next_tool=tool_name) as same_tool_loop_pairs,
  count(*) filter (where session_id is not null and next_tool=tool_name and coalesce(idempotent,false)=false) as non_idempotent_repeat_pairs,
  count(*) filter (where session_id is not null and next_tool is not null and next_tool=any(coalesce(usually_followed_by,'{}'::text[]))) as canonical_routing_transitions,
  count(*) filter (where tool_name='scout_prepare_external_context_request') as external_context_prepare_calls,
  count(*) filter (where tool_name='scout_set_external_capability_consent') as external_consent_choice_calls,
  count(*) filter (where tool_name in ('scout_get_action_intents','scout_update_action_intent')) as action_intent_lifecycle_calls,
  count(*) filter (where session_id is not null and next_tool is null and outcome='allowed') as successful_terminal_call_proxy,
  round(
    count(*)::numeric / nullif(count(*) filter (where session_id is not null and next_tool is null and outcome='allowed'),0),
    2
  ) as tool_calls_per_successful_terminal_call_proxy
from scored
group by client_type;
comment on view analytics.routing_quality is
  'Privacy-minimized routing quality proxies. It intentionally does not infer user intent from chat or retain prompts; use routing_eval_fixtures for explicit behavioral expectations and tool_sequences/tool_reliability/feature_adoption for operational analysis.';

select agent_contract.assert_tool_routing_integrity();
select agent_contract.assert_routing_eval_fixtures();

commit;
