-- Promote canonical routing fixtures into Scout's executable model-evaluation surface.
-- Prompts here are curated catalog/eval prompts, never captured operator chat.

begin;

alter table agent_eval.results
  add column if not exists evaluation_signals jsonb not null default '{}'::jsonb;

do $constraint$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='results_evaluation_signals_contract_v1'
      and conrelid='agent_eval.results'::regclass
  ) then
    alter table agent_eval.results add constraint results_evaluation_signals_contract_v1 check (
      jsonb_typeof(evaluation_signals)='object'
      and (evaluation_signals - array[
        'tool_sequence',
        'ambiguous_non_idempotent_retries',
        'external_context_over_request',
        'approval_required_execution_without_approval',
        'blocked_result_reconstruction_attempt',
        'completed_intent'
      ])='{}'::jsonb
      and (not (evaluation_signals ? 'tool_sequence') or jsonb_typeof(evaluation_signals->'tool_sequence')='array')
      and (not (evaluation_signals ? 'ambiguous_non_idempotent_retries') or jsonb_typeof(evaluation_signals->'ambiguous_non_idempotent_retries')='number')
      and (not (evaluation_signals ? 'external_context_over_request') or jsonb_typeof(evaluation_signals->'external_context_over_request')='boolean')
      and (not (evaluation_signals ? 'approval_required_execution_without_approval') or jsonb_typeof(evaluation_signals->'approval_required_execution_without_approval')='boolean')
      and (not (evaluation_signals ? 'blocked_result_reconstruction_attempt') or jsonb_typeof(evaluation_signals->'blocked_result_reconstruction_attempt')='boolean')
      and (not (evaluation_signals ? 'completed_intent') or jsonb_typeof(evaluation_signals->'completed_intent')='boolean')
    );
  end if;
end
$constraint$;
comment on column agent_eval.results.evaluation_signals is
  'Bounded routing-evaluation signals only. Never store prompt text, model reasoning, raw MCP payloads, external data, or operator chat here.';

-- Historical direct-signal case is retained but deactivated: the product feature is parked.
update agent_eval.golden_cases
set active=false,
    rationale='Historical case retained inactive: business-signal ingress is parked and is not a public model-visible Scout tool.'
where case_key='business_signal_direct'
  and expected_tool='scout_submit_business_signal';

update agent_eval.golden_cases
set rationale='Negative guardrail: business-signal ingress is parked, and surrounding conversation may never be submitted.'
where case_key='business_signal_no_chatdump';

-- Keep one runnable golden case per canonical routing fixture. These cases are
-- explicitly namespaced so existing product-specific cases remain untouched.
insert into agent_eval.golden_cases(
  case_key,prompt,intent_family,expected_tool,expected_no_call,required_argument_keys,
  forbidden_tools,expected_surface,difficulty,rationale,active
)
select
  'routing.'||f.fixture_key,
  f.prompt,
  'routing_'||f.fixture_source,
  f.expected_first_tool,
  false,
  '{}'::text[],
  f.forbidden_first_tools,
  'public_mcp',
  case f.fixture_source
    when 'catalog_example' then 'easy'
    when 'catalog_task_cue' then 'normal'
    when 'collision' then 'hard'
    when 'sequence' then 'hard'
    else 'adversarial'
  end,
  'Canonical routing fixture; assertions='||f.assertions::text,
  true
from agent_contract.routing_eval_fixtures f
where f.active
on conflict (case_key) do update set
  prompt=excluded.prompt,
  intent_family=excluded.intent_family,
  expected_tool=excluded.expected_tool,
  expected_no_call=excluded.expected_no_call,
  required_argument_keys=excluded.required_argument_keys,
  forbidden_tools=excluded.forbidden_tools,
  expected_surface=excluded.expected_surface,
  difficulty=excluded.difficulty,
  rationale=excluded.rationale,
  active=true;

update agent_eval.golden_cases g
set active=false,
    rationale='Inactive because the underlying canonical routing fixture is no longer active.'
where g.case_key like 'routing.%'
  and not exists (
    select 1 from agent_contract.routing_eval_fixtures f
    where f.active and g.case_key='routing.'||f.fixture_key
  );

create or replace function agent_contract.routing_sequence_matches(p_expected text[],p_actual text[])
returns boolean
language plpgsql
immutable
set search_path to ''
as $function$
declare
  v_expected_index integer:=1;
  v_tool text;
begin
  if coalesce(cardinality(p_expected),0)=0 then return true; end if;
  if coalesce(cardinality(p_actual),0)=0 then return false; end if;
  foreach v_tool in array p_actual loop
    if v_tool=p_expected[v_expected_index] then
      v_expected_index:=v_expected_index+1;
      if v_expected_index>cardinality(p_expected) then return true; end if;
    end if;
  end loop;
  return false;
end
$function$;

create or replace function agent_contract.routing_same_tool_loop_count(p_tools text[])
returns integer
language sql
immutable
set search_path to ''
as $function$
  select count(*)::integer
  from generate_subscripts(coalesce(p_tools,'{}'::text[]),1) i
  where i>1 and p_tools[i]=p_tools[i-1];
$function$;

revoke all on function agent_contract.routing_sequence_matches(text[],text[]) from public,anon,authenticated;
grant execute on function agent_contract.routing_sequence_matches(text[],text[]) to service_role;
revoke all on function agent_contract.routing_same_tool_loop_count(text[]) from public,anon,authenticated;
grant execute on function agent_contract.routing_same_tool_loop_count(text[]) to service_role;

create or replace function agent_contract.assert_routing_eval_golden_cases()
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_bad text[];
begin
  select array_agg(f.fixture_key order by f.fixture_key) into v_bad
  from agent_contract.routing_eval_fixtures f
  left join agent_eval.golden_cases g on g.case_key='routing.'||f.fixture_key
  where f.active and (
    g.case_key is null
    or not g.active
    or g.expected_no_call
    or g.expected_tool is distinct from f.expected_first_tool
    or not (f.forbidden_first_tools <@ g.forbidden_tools)
  );
  if coalesce(cardinality(v_bad),0)>0 then
    raise exception 'routing fixtures missing or drifting from golden cases: %',array_to_string(v_bad,', ');
  end if;

  if exists (select 1 from agent_eval.golden_cases where case_key='business_signal_direct' and active) then
    raise exception 'parked business-signal ingress still has an active direct-call golden case';
  end if;
end
$function$;
revoke all on function agent_contract.assert_routing_eval_golden_cases() from public,anon,authenticated;
grant execute on function agent_contract.assert_routing_eval_golden_cases() to service_role;

create or replace view analytics.routing_eval_quality
with (security_invoker=true)
as
with scoped_results as (
  select
    run.host,run.model,run.server_version,
    f.fixture_key,f.fixture_source,f.expected_first_tool,f.forbidden_first_tools,f.expected_sequence,
    result.actual_tool,result.call_count,coalesce(result.evaluation_signals,'{}'::jsonb) as signals,
    case when jsonb_typeof(coalesce(result.evaluation_signals,'{}'::jsonb)->'tool_sequence')='array'
      then array(select jsonb_array_elements_text(result.evaluation_signals->'tool_sequence'))
      else '{}'::text[] end as actual_sequence
  from agent_eval.results result
  join agent_eval.runs run on run.id=result.run_id
  join agent_eval.golden_cases golden on golden.id=result.case_id and golden.active
  join agent_contract.routing_eval_fixtures f on golden.case_key='routing.'||f.fixture_key and f.active
)
select
  host,model,server_version,
  count(*) as evaluated_intents,
  count(*) filter (where actual_tool=expected_first_tool) as correct_first_tool,
  count(*) filter (where actual_tool=any(forbidden_first_tools)) as forbidden_first_tool,
  count(*) filter (where actual_tool='scout_get_capabilities' and expected_first_tool<>'scout_get_capabilities') as unnecessary_capability_lookup,
  count(*) filter (where actual_tool='scout_get_profile_status' and expected_first_tool<>'scout_get_profile_status') as unnecessary_profile_status,
  count(*) filter (where fixture_source='collision' and actual_tool=expected_first_tool) as correct_near_neighbor_selection,
  count(*) filter (where agent_contract.routing_sequence_matches(expected_sequence,actual_sequence)) as canonical_sequence_completion,
  coalesce(sum(agent_contract.routing_same_tool_loop_count(actual_sequence)),0) as same_tool_loops,
  coalesce(sum(case when jsonb_typeof(signals->'ambiguous_non_idempotent_retries')='number' then (signals->>'ambiguous_non_idempotent_retries')::integer else 0 end),0) as non_idempotent_ambiguous_retries,
  count(*) filter (where signals @> '{"external_context_over_request":true}'::jsonb) as external_context_over_request,
  count(*) filter (where signals @> '{"approval_required_execution_without_approval":true}'::jsonb) as approval_required_execution_without_approval,
  count(*) filter (where signals @> '{"blocked_result_reconstruction_attempt":true}'::jsonb) as blocked_result_reconstruction_attempt,
  count(*) filter (where signals @> '{"completed_intent":true}'::jsonb) as successfully_completed_intents,
  round((sum(call_count) filter (where signals @> '{"completed_intent":true}'::jsonb))::numeric /
    nullif(count(*) filter (where signals @> '{"completed_intent":true}'::jsonb),0),2) as tool_calls_per_successfully_completed_intent
from scoped_results
group by host,model,server_version;
comment on view analytics.routing_eval_quality is
  'Aggregated routing-model evaluation quality. It joins curated evaluation fixtures only and deliberately excludes real operator conversations and raw MCP payloads.';

select agent_contract.assert_routing_eval_golden_cases();

commit;
