-- Scout MCP registry integrity guard.
--
-- Goal: make model-visible tool contract drift machine-detectable before the
-- public MCP catalog grows further. This does not replace privacy, exposure,
-- authorization, anti-enumeration, or presentation enforcement.

begin;

-- These operations tools do not disclose opportunity/customer identity sets,
-- so register them explicitly as neutral in the exposure-budget layer. The
-- important invariant is that every model-visible tool has an explicit rule,
-- rather than relying on an absent-row default.
insert into agent_exposure.tool_rules (
  tool_name,
  track_entities,
  deep_sensitive,
  discovery_batch,
  updated_at
)
values
  ('scout_get_action_intents', false, false, false, clock_timestamp()),
  ('scout_update_action_intent', false, false, false, clock_timestamp()),
  ('scout_reject_public_equipment_candidates', false, false, false, clock_timestamp())
on conflict (tool_name) do update set
  track_entities = excluded.track_entities,
  deep_sensitive = excluded.deep_sensitive,
  discovery_batch = excluded.discovery_batch,
  updated_at = excluded.updated_at;

-- One canonical diagnostic view across the contract layers that must be
-- present for every active model-visible tool. Capability links are omitted
-- deliberately: meta/router tools such as scout_get_capabilities may be
-- intentionally capability-agnostic.
create or replace view agent_contract.v_tool_registry_integrity_v1
with (security_invoker = true)
as
select
  t.tool_name,
  t.active,
  t.model_visible,
  t.app_visible,
  t.contract_version,
  coalesce(r.active, false) as routing_registered,
  coalesce(p.enabled, false) as privacy_registered,
  coalesce(pr.active, false) as presentation_registered,
  coalesce(ip.active, false) as ip_exposure_registered,
  (ex.tool_name is not null) as exposure_rule_registered,
  case
    when t.active and t.model_visible then
      coalesce(r.active, false)
      and coalesce(p.enabled, false)
      and coalesce(pr.active, false)
      and coalesce(ip.active, false)
      and ex.tool_name is not null
    else true
  end as model_contract_complete,
  array_remove(array[
    case when t.active and t.model_visible and not coalesce(r.active, false) then 'routing' end,
    case when t.active and t.model_visible and not coalesce(p.enabled, false) then 'privacy' end,
    case when t.active and t.model_visible and not coalesce(pr.active, false) then 'presentation' end,
    case when t.active and t.model_visible and not coalesce(ip.active, false) then 'ip_exposure' end,
    case when t.active and t.model_visible and ex.tool_name is null then 'exposure_rule' end
  ], null)::text[] as missing_contracts
from agent_contract.tool_contracts t
left join agent_contract.tool_routing r
  on r.tool_name = t.tool_name
left join agent_privacy.tool_policies p
  on p.tool_name = t.tool_name
left join agent_presentation.tool_contracts pr
  on pr.tool_name = t.tool_name
left join agent_ip.tool_exposure_policies ip
  on ip.tool_name = t.tool_name
left join agent_exposure.tool_rules ex
  on ex.tool_name = t.tool_name;

comment on view agent_contract.v_tool_registry_integrity_v1 is
  'Cross-layer integrity diagnostic for Scout MCP tool contracts. Active model-visible tools should have model_contract_complete=true before release.';

revoke all on agent_contract.v_tool_registry_integrity_v1 from public, anon, authenticated;
grant select on agent_contract.v_tool_registry_integrity_v1 to service_role;

-- Release/CI-friendly assertion. A deployment can call this in a transaction;
-- it raises if any active model-visible tool is missing a required contract
-- layer, turning registry drift into a release failure rather than a runtime
-- discovery.
create or replace function agent_contract.assert_tool_registry_integrity_v1()
returns void
language plpgsql
stable
security invoker
set search_path to ''
as $function$
declare
  v_gaps text;
begin
  select string_agg(
    i.tool_name || ' [' || array_to_string(i.missing_contracts, ',') || ']',
    '; ' order by i.tool_name
  )
  into v_gaps
  from agent_contract.v_tool_registry_integrity_v1 i
  where i.active
    and i.model_visible
    and not i.model_contract_complete;

  if v_gaps is not null then
    raise exception using
      errcode = '23514',
      message = 'Scout MCP tool registry integrity check failed',
      detail = v_gaps,
      hint = 'Register routing, privacy, presentation, IP exposure, and exposure-budget contracts before making the tool model-visible.';
  end if;
end
$function$;

revoke all on function agent_contract.assert_tool_registry_integrity_v1() from public, anon, authenticated;
grant execute on function agent_contract.assert_tool_registry_integrity_v1() to service_role;

-- Prove this migration leaves the currently model-visible registry complete.
select agent_contract.assert_tool_registry_integrity_v1();

commit;
