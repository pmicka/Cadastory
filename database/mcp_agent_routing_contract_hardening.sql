-- Follow-up hardening for already-applied routing-contract installations.
-- Keeps routing metadata private to the service role and covers the fixture FK.

begin;

create index if not exists routing_eval_fixtures_expected_first_tool_idx
  on agent_contract.routing_eval_fixtures(expected_first_tool);

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

commit;
