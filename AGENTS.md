# Cadastory agent instructions

These instructions apply to the entire repository.

## Scout MCP architecture doctrine

Before changing any Scout MCP tool, public/model-visible capability, routing contract, privacy/exposure rule, presentation contract, external-capability handoff, persistent agent state, or specialized Scout surface, read and follow:

- `docs/SCOUT_MCP_ARCHITECTURE_DOCTRINE.md`

The doctrine is normative. Its `MUST` / `MUST NOT` rules are requirements, not suggestions.

### Required checks

For relevant database/contract changes, verify both gates before treating the work as release-ready:

```sql
select agent_contract.assert_tool_registry_integrity_v1();
select agent_contract.assert_architecture_doctrine_v1();
```

Do not bypass a failing assertion by weakening privacy, authorization, anti-enumeration, exposure, presentation, or evidence controls.

### New model-visible mutations

A new non-read-only model-visible tool must have an explicit `agent_contract.tool_evolution` classification before release, including side-effect scope and reversibility. Do not ship a new mutation with either value left `unknown`.

`agent_contract.tool_evolution.legacy_doctrine_v1_debt` is a one-time grandfather marker for mutation debt that was already model-visible when Doctrine v1 became normative. **Never set this flag to true for a new tool or use it to silence a release violation.**

Destructive tools and new tools with external/mixed side effects require the confirmation behavior mandated by the doctrine.

### Architecture exceptions

Where the doctrine permits an exception, record it in `agent_ip.architecture_decisions` with the affected `SCOUT-MCP-*` rule IDs, rationale, consequences, compensating controls, verification, and revisit/sunset condition.

An architecture exception does not authorize weakening non-negotiable privacy/security guarantees.

### Design posture

Prefer the smallest evidence-backed change that preserves stable public semantics. Do not introduce speculative agent infrastructure merely because it is technically possible. When a new pattern proves repeatedly useful, update the doctrine so the lesson becomes durable and, where practical, machine-enforced.
