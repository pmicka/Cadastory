-- Transactional enforcement for Scout MCP model-visible tool contracts.
--
-- Contract rows may be created or changed in any order inside one transaction,
-- but the transaction cannot commit while an active model-visible tool is
-- missing routing, privacy, presentation, IP-exposure, or exposure-budget
-- registration.

begin;

create or replace function agent_contract.enforce_tool_registry_integrity_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_tool_name text := coalesce(new.tool_name, old.tool_name);
  v_missing text[];
begin
  if v_tool_name is null then
    return null;
  end if;

  select i.missing_contracts
  into v_missing
  from agent_contract.v_tool_registry_integrity_v1 i
  where i.tool_name = v_tool_name
    and i.active
    and i.model_visible
    and not i.model_contract_complete;

  if found then
    raise exception using
      errcode = '23514',
      message = 'Scout MCP model-visible tool contract is incomplete',
      detail = v_tool_name || ' is missing [' || array_to_string(v_missing, ',') || ']',
      hint = 'Register every deterministic contract layer in the same transaction, or keep the tool model_visible=false until it is complete.';
  end if;

  return null;
end
$function$;

revoke all on function agent_contract.enforce_tool_registry_integrity_v1() from public, anon, authenticated;

-- Constraint triggers are initially deferred so a migration can compose a
-- complete tool registration across the normalized contract tables before the
-- invariant is evaluated at transaction end.
drop trigger if exists tool_contract_registry_integrity_v1 on agent_contract.tool_contracts;
create constraint trigger tool_contract_registry_integrity_v1
after insert or update or delete on agent_contract.tool_contracts
deferrable initially deferred
for each row execute function agent_contract.enforce_tool_registry_integrity_v1();

drop trigger if exists tool_routing_registry_integrity_v1 on agent_contract.tool_routing;
create constraint trigger tool_routing_registry_integrity_v1
after insert or update or delete on agent_contract.tool_routing
deferrable initially deferred
for each row execute function agent_contract.enforce_tool_registry_integrity_v1();

drop trigger if exists tool_privacy_registry_integrity_v1 on agent_privacy.tool_policies;
create constraint trigger tool_privacy_registry_integrity_v1
after insert or update or delete on agent_privacy.tool_policies
deferrable initially deferred
for each row execute function agent_contract.enforce_tool_registry_integrity_v1();

drop trigger if exists tool_presentation_registry_integrity_v1 on agent_presentation.tool_contracts;
create constraint trigger tool_presentation_registry_integrity_v1
after insert or update or delete on agent_presentation.tool_contracts
deferrable initially deferred
for each row execute function agent_contract.enforce_tool_registry_integrity_v1();

drop trigger if exists tool_ip_registry_integrity_v1 on agent_ip.tool_exposure_policies;
create constraint trigger tool_ip_registry_integrity_v1
after insert or update or delete on agent_ip.tool_exposure_policies
deferrable initially deferred
for each row execute function agent_contract.enforce_tool_registry_integrity_v1();

drop trigger if exists tool_exposure_registry_integrity_v1 on agent_exposure.tool_rules;
create constraint trigger tool_exposure_registry_integrity_v1
after insert or update or delete on agent_exposure.tool_rules
deferrable initially deferred
for each row execute function agent_contract.enforce_tool_registry_integrity_v1();

select agent_contract.assert_tool_registry_integrity_v1();

commit;
