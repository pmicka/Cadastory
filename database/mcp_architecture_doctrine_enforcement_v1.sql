-- Scout MCP architecture doctrine v1 enforcement.
--
-- Companion to docs/SCOUT_MCP_ARCHITECTURE_DOCTRINE.md.
-- This migration machine-enforces the subset of the doctrine that is safe to
-- make blocking today while explicitly grandfathering only the model-visible
-- mutation reversibility debt that existed when Doctrine v1 became normative.

begin;

create table if not exists agent_contract.architecture_doctrine_versions (
  version integer primary key check (version >= 1),
  document_path text not null,
  status text not null check (status in ('draft','normative','superseded')),
  effective_at timestamptz not null default clock_timestamp(),
  active boolean not null default true,
  notes text null,
  created_at timestamptz not null default clock_timestamp()
);

insert into agent_contract.architecture_doctrine_versions (
  version, document_path, status, effective_at, active, notes
)
values (
  1,
  'docs/SCOUT_MCP_ARCHITECTURE_DOCTRINE.md',
  'normative',
  clock_timestamp(),
  true,
  'Doctrine v1: restrained evidence-backed MCP evolution with progressive machine enforcement.'
)
on conflict (version) do update set
  document_path = excluded.document_path,
  status = excluded.status,
  active = excluded.active;

alter table agent_contract.tool_evolution
  add column if not exists legacy_doctrine_v1_debt boolean not null default false;

-- Grandfather only the mutation debt that was already model-visible when
-- Doctrine v1 became normative. Hidden/internal tools do not receive this
-- exemption merely because they predate the doctrine.
update agent_contract.tool_evolution e
set legacy_doctrine_v1_debt = true,
    updated_at = clock_timestamp()
from agent_contract.tool_contracts t
where t.tool_name = e.tool_name
  and t.active
  and t.model_visible
  and not t.read_only
  and e.reversibility = 'unknown';

comment on column agent_contract.tool_evolution.legacy_doctrine_v1_debt is
  'Temporary Doctrine v1 grandfather flag for mutation reversibility that was already model-visible and unclassified when the doctrine became normative. Do not set for new tools; clear after classification.';

create or replace view agent_contract.v_architecture_doctrine_release_issues_v1 as
select
  'SCOUT-MCP-002'::text as rule_id,
  'release_gate'::text as enforcement_class,
  i.tool_name as object_name,
  'missing contract layers: ' || array_to_string(i.missing_contracts, ',') as detail
from agent_contract.v_tool_registry_integrity_v1 i
where i.active and i.model_visible and not i.model_contract_complete

union all

select
  'SCOUT-MCP-005'::text,
  'release_gate'::text,
  t.tool_name,
  'missing tool evolution contract'
from agent_contract.tool_contracts t
left join agent_contract.tool_evolution e on e.tool_name=t.tool_name
where t.active and t.model_visible and e.tool_name is null

union all

select
  'SCOUT-MCP-006'::text,
  'release_gate'::text,
  t.tool_name,
  case
    when t.response_type_slug is null and t.output_schema_slug is null then 'missing response_type_slug and output_schema_slug'
    when t.response_type_slug is null then 'missing response_type_slug'
    else 'missing output_schema_slug'
  end
from agent_contract.tool_contracts t
where t.active and t.model_visible
  and (t.response_type_slug is null or t.output_schema_slug is null)

union all

select
  'SCOUT-MCP-007'::text,
  'release_gate'::text,
  t.tool_name,
  'retired tool cannot remain active and model-visible'
from agent_contract.tool_contracts t
join agent_contract.tool_evolution e on e.tool_name=t.tool_name
where t.active and t.model_visible and e.lifecycle_state='retired'

union all

select
  'SCOUT-MCP-008'::text,
  'release_gate'::text,
  t.tool_name,
  case
    when t.read_only and e.side_effect_scope <> 'none' then 'read-only tool has non-none side_effect_scope'
    when t.read_only and e.reversibility <> 'not_applicable' then 'read-only tool has mutation reversibility semantics'
    when not t.read_only and e.side_effect_scope = 'unknown' then 'mutation side_effect_scope is unknown'
    else 'mutation reversibility is unknown'
  end
from agent_contract.tool_contracts t
join agent_contract.tool_evolution e on e.tool_name=t.tool_name
where t.active and t.model_visible
  and not e.legacy_doctrine_v1_debt
  and (
    (t.read_only and (e.side_effect_scope <> 'none' or e.reversibility <> 'not_applicable'))
    or (not t.read_only and (e.side_effect_scope='unknown' or e.reversibility='unknown'))
  )

union all

select
  'SCOUT-MCP-009'::text,
  'release_gate'::text,
  t.tool_name,
  case
    when t.destructive then 'destructive model-visible mutation requires explicit confirmation'
    else 'external or mixed side effects require explicit confirmation'
  end
from agent_contract.tool_contracts t
join agent_contract.tool_evolution e on e.tool_name=t.tool_name
left join agent_contract.tool_routing r on r.tool_name=t.tool_name
where t.active and t.model_visible
  and not e.legacy_doctrine_v1_debt
  and (
    t.destructive
    or e.side_effect_scope in ('external_system','mixed')
  )
  and coalesce(r.confirmation,'none') <> 'explicit';

comment on view agent_contract.v_architecture_doctrine_release_issues_v1 is
  'Machine-enforced release subset of docs/SCOUT_MCP_ARCHITECTURE_DOCTRINE.md. Legacy Doctrine v1 mutation debt remains diagnostic via v_tool_future_readiness_v1 until classified.';

create or replace function agent_contract.assert_architecture_doctrine_v1()
returns void
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_gaps text;
begin
  select string_agg(
    x.rule_id || ' ' || x.object_name || ' [' || x.detail || ']',
    '; ' order by x.rule_id, x.object_name
  )
  into v_gaps
  from agent_contract.v_architecture_doctrine_release_issues_v1 x;

  if v_gaps is not null then
    raise exception using
      errcode='23514',
      message='Scout MCP architecture doctrine release check failed',
      detail=v_gaps,
      hint='Resolve the cited SCOUT-MCP rule violations or record an approved architecture exception where the doctrine permits one.';
  end if;
end
$function$;

revoke all on agent_contract.architecture_doctrine_versions from public, anon, authenticated;
revoke all on agent_contract.v_architecture_doctrine_release_issues_v1 from public, anon, authenticated;
revoke all on function agent_contract.assert_architecture_doctrine_v1() from public, anon, authenticated;
grant select on agent_contract.architecture_doctrine_versions to service_role;
grant select on agent_contract.v_architecture_doctrine_release_issues_v1 to service_role;
grant execute on function agent_contract.assert_architecture_doctrine_v1() to service_role;

select agent_contract.assert_architecture_doctrine_v1();

commit;
