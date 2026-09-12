# Cadastory agent instructions

These instructions apply to the entire repository.

## Scout MCP architecture doctrine

Before changing any Scout MCP tool, public/model-visible capability, routing contract, privacy/exposure rule, presentation contract, external-capability handoff, persistent agent state, or specialized Scout surface, read and follow:

- `docs/SCOUT_MCP_ARCHITECTURE_DOCTRINE.md`

The doctrine is normative. Its `MUST` / `MUST NOT` rules are requirements, not suggestions.

### Scout component sandbox design source

Before changing the presentation, layout, styling, visible controls, or interaction structure of `supabase/functions/scout-component-sandbox-mcp`, read and follow:

- `supabase/functions/scout-component-sandbox-mcp/DESIGN_CONTRACT.md`

The existing Figma sandbox card referenced there is the visual source of truth. Do not redesign that surface from memory, replace it with a new card system, or add visible sections merely because more Scout data is available. Real data should be projected into the existing approved design slots unless the owner explicitly approves a design change.

The MCP Apps lifecycle implementation and the visible design are separate concerns: preserving standards-based lifecycle plumbing does not authorize changing the approved presentation. Conversely, visual parity work must not replace the proven standards-based lifecycle with host-specific or deprecated APIs.

### Scout component sandbox map source

Before changing map data, map rendering, map-resource CSP, map interaction behavior, or map-related tool/result contracts in `supabase/functions/scout-component-sandbox-mcp`, read and follow:

- `supabase/functions/scout-component-sandbox-mcp/MAP_CONTRACT.md`

Map work proceeds one opportunity type at a time. The current active map contract is the bounded PNC Tower premium-exterior single-site contract. Prior generalized `map_targets*` RPCs and old `component_v*` renderers are reference-only archaeology, not current runtime dependencies.

Check current MCP Apps behavior through Context7 before each map implementation batch. Do not reintroduce `window.openai`, raw `window.message` lifecycle plumbing, `openai/outputTemplate`, `openai/widgetAccessible`, `openai/widgetDescription`, `openai/widgetCSP`, or other host-specific metadata from the prior map implementation.

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
