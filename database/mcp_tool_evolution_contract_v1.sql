-- Scout MCP tool evolution contract foundation.
--
-- Goal: make lifecycle, compatibility, side effects, reversibility,
-- result-envelope versioning, and provenance policy explicit before the
-- public tool surface grows further. This is intentionally non-blocking:
-- existing registry integrity remains the release gate while this diagnostic
-- exposes future-readiness work early.

begin;

create table if not exists agent_contract.tool_evolution (
  tool_name text primary key references agent_contract.tool_contracts(tool_name) on update cascade on delete cascade,
  lifecycle_state text not null default 'stable' check (lifecycle_state in ('experimental','stable','deprecated','retired')),
  compatibility_policy text not null default 'additive_only' check (compatibility_policy in ('additive_only','versioned_breaking','frozen')),
  side_effect_scope text not null default 'unknown' check (side_effect_scope in ('none','scout_state','external_system','mixed','unknown')),
  reversibility text not null default 'unknown' check (reversibility in ('not_applicable','reversible','compensatable','irreversible','unknown')),
  compensation_tool text null references agent_contract.tool_contracts(tool_name) on update cascade on delete set null,
  result_envelope_version integer not null default 1 check (result_envelope_version >= 1),
  provenance_policy text not null default 'preserve_if_present' check (provenance_policy in ('not_applicable','preserve_if_present','required_for_evidence')),
  deprecated_at timestamptz null,
  sunset_after timestamptz null,
  notes text null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (tool_name <> compensation_tool),
  check (lifecycle_state <> 'deprecated' or deprecated_at is not null),
  check (sunset_after is null or deprecated_at is not null)
);

comment on table agent_contract.tool_evolution is
  'Forward-compatibility metadata for Scout MCP tools. Separates lifecycle, compatibility, side effects, reversibility, result-envelope version and provenance policy from runtime routing so these concerns can evolve without reshaping the public tool schema.';

insert into agent_contract.tool_evolution (
  tool_name,
  lifecycle_state,
  compatibility_policy,
  side_effect_scope,
  reversibility,
  result_envelope_version,
  provenance_policy,
  notes
)
select
  t.tool_name,
  'stable',
  'additive_only',
  case when t.read_only then 'none' else 'scout_state' end,
  case when t.read_only then 'not_applicable' else 'unknown' end,
  1,
  'preserve_if_present',
  case when t.read_only then 'Seeded from existing read_only contract.' else 'Mutation scope seeded as Scout-owned state; reversibility intentionally left unknown pending tool-by-tool review.' end
from agent_contract.tool_contracts t
on conflict (tool_name) do nothing;

create or replace view agent_contract.v_tool_future_readiness_v1 as
select
  t.tool_name,
  t.active,
  t.model_visible,
  t.read_only,
  t.destructive,
  t.idempotent,
  t.contract_version,
  e.lifecycle_state,
  e.compatibility_policy,
  e.side_effect_scope,
  e.reversibility,
  e.compensation_tool,
  e.result_envelope_version,
  e.provenance_policy,
  case
    when e.tool_name is null then false
    when t.read_only and (e.side_effect_scope <> 'none' or e.reversibility <> 'not_applicable') then false
    when not t.read_only and e.side_effect_scope = 'unknown' then false
    else true
  end as evolution_contract_complete,
  array_remove(array[
    case when e.tool_name is null then 'missing_evolution_contract' end,
    case when t.read_only and e.side_effect_scope <> 'none' then 'read_tool_side_effect_scope' end,
    case when t.read_only and e.reversibility <> 'not_applicable' then 'read_tool_reversibility' end,
    case when not t.read_only and e.side_effect_scope = 'unknown' then 'mutation_side_effect_scope' end,
    case when not t.read_only and e.reversibility = 'unknown' then 'mutation_reversibility_unclassified' end,
    case when e.lifecycle_state = 'deprecated' and e.deprecated_at is null then 'deprecated_without_date' end,
    case when e.sunset_after is not null and e.deprecated_at is null then 'sunset_without_deprecation' end
  ], null)::text[] as readiness_notes
from agent_contract.tool_contracts t
left join agent_contract.tool_evolution e on e.tool_name=t.tool_name;

comment on view agent_contract.v_tool_future_readiness_v1 is
  'Non-blocking future-readiness diagnostic for MCP evolution. Registry integrity remains the release gate; this view highlights lifecycle/reversibility/provenance work before those concerns become expensive migrations.';

revoke all on agent_contract.tool_evolution from public, anon, authenticated;
revoke all on agent_contract.v_tool_future_readiness_v1 from public, anon, authenticated;
grant select, insert, update, delete on agent_contract.tool_evolution to service_role;
grant select on agent_contract.v_tool_future_readiness_v1 to service_role;

commit;
