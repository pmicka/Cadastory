-- Follow-up hardening for already-applied routing evaluation installations.

begin;

do $policy$
begin
  if not exists (select 1 from pg_policies where schemaname='agent_eval' and tablename='golden_cases' and policyname='golden_cases_service_role_only') then
    execute 'create policy golden_cases_service_role_only on agent_eval.golden_cases for all to service_role using (true) with check (true)';
  end if;
  if not exists (select 1 from pg_policies where schemaname='agent_eval' and tablename='runs' and policyname='runs_service_role_only') then
    execute 'create policy runs_service_role_only on agent_eval.runs for all to service_role using (true) with check (true)';
  end if;
  if not exists (select 1 from pg_policies where schemaname='agent_eval' and tablename='results' and policyname='results_service_role_only') then
    execute 'create policy results_service_role_only on agent_eval.results for all to service_role using (true) with check (true)';
  end if;
end
$policy$;

commit;
