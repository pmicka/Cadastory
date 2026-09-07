-- Ensure every canonical routing field that affects recovery is model-facing.

begin;

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

commit;
