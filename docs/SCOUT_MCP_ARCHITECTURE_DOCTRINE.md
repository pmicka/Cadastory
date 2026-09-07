# Scout MCP Architecture Doctrine

**Status:** Normative  
**Version:** 1.0  
**Effective:** 2026-09-07  
**Scope:** Scout by Cadastory public/model-visible MCP behavior, supporting contracts, presentation surfaces, external-capability handoff, and agent-facing evolution.

This document is the durable design doctrine for Scout's MCP. It exists to keep Scout restrained, forward-looking, and difficult to accidentally degrade as the tool surface grows.

The objective is not to adopt novel agent patterns because they are interesting. The objective is to preserve the architectural seams that are cheap to establish now and expensive to retrofit later, while promoting new interaction patterns only when observed evidence supports them.

## Normative language

- **MUST / MUST NOT** — required. A violation must either fail a machine release gate or have an explicit temporary architecture exception recorded before release.
- **SHOULD / SHOULD NOT** — expected default. Deviations require written rationale and evidence.
- **MAY** — optional and should be driven by demonstrated value.

## Enforcement classes

Each rule has one of three enforcement classes.

- **Release gate** — machine-checkable and intended to block a non-compliant model-visible release.
- **Diagnostic gate** — machine-reported now, but not yet blocking legacy behavior. It may be promoted to a release gate after existing debt is classified or remediated.
- **Review gate** — requires explicit architecture review because reliable mechanical enforcement would be misleading or overbroad.

A rule may move from review -> diagnostic -> release gate as Scout gains enough evidence and structure to enforce it safely.

---

## 1. Deterministic controls outrank model instructions

### SCOUT-MCP-001 — Security and privacy controls are code, not advice
**Enforcement:** Review gate + existing deterministic controls

Privacy, authorization, exposure limits, anti-enumeration behavior, credential gates, sensitive-data handling, and presentation restrictions MUST be enforced in code/database contracts. Prompt text or tool descriptions MAY explain those controls but MUST NOT be their only enforcement mechanism.

A convenience or model-ergonomics improvement MUST NOT weaken a deterministic privacy/security boundary.

### SCOUT-MCP-002 — Every model-visible tool has a complete contract
**Enforcement:** Release gate

Every active model-visible tool MUST have explicit routing, privacy, presentation, IP-exposure, and exposure-budget registration before release.

Current machine enforcement:

- `agent_contract.v_tool_registry_integrity_v1`
- `agent_contract.assert_tool_registry_integrity_v1()`

Absent-row defaults are not an acceptable substitute for registration.

---

## 2. The public tool surface is an intent interface, not an implementation dump

### SCOUT-MCP-003 — Expose stable operator intent, not backend plumbing
**Enforcement:** Review gate

A public MCP tool SHOULD correspond to a durable operator/agent intent. Internal RPCs, enrichment stages, persistence steps, and orchestration primitives SHOULD remain internal unless exposing them materially improves host control, safety, inspectability, or task performance.

Before adding a tool, ask:

1. Does the host need to choose this operation explicitly?
2. Does the operation have distinct permissions, side effects, confirmation, evidence, or presentation semantics?
3. Would keeping it internal materially reduce model reliability or user control?

If the answer is no, prefer internal composition over another public tool.

### SCOUT-MCP-004 — Capability disclosure is selective by default
**Enforcement:** Review gate + capability-manifest contract

Scout MUST NOT treat startup as a feature dump. The host should see the capabilities relevant to the current task, recognized service, explicit setup intent, or a direct "what can Scout do?" request.

Dynamic narrowing is preferred over requiring the model to reason over the entire catalog on every turn.

---

## 3. Tool evolution must be explicit before consumers depend on it

### SCOUT-MCP-005 — Compatibility is additive by default
**Enforcement:** Release gate for new model-visible tools; review gate for existing tools

Public tool contracts SHOULD use additive evolution by default. Removing fields, changing field meaning, tightening accepted values incompatibly, or changing result semantics requires a versioned breaking path rather than silent mutation.

Every tool MUST have an evolution record declaring:

- lifecycle state
- compatibility policy
- side-effect scope
- reversibility
- result-envelope version
- provenance policy

Current source of truth: `agent_contract.tool_evolution`.

### SCOUT-MCP-006 — Output semantics are typed and versionable
**Enforcement:** Release gate for new model-visible tools

Every active model-visible tool MUST declare both a `response_type_slug` and an `output_schema_slug`.

Scout SHOULD converge on a small, stable outer-result vocabulary so future clients can reason consistently about concepts such as:

- result/data
- status
- contract/schema version
- evidence/provenance
- uncertainty/unknowns
- presentation contract
- exposure contract
- safe diagnostics

Not every response must emit every field. The architectural requirement is that equivalent semantics are not reinvented incompatibly across tools.

Raw JSON is machine-facing. User-facing rendering follows the presentation contract unless raw output is explicitly requested.

### SCOUT-MCP-007 — Deprecation is a lifecycle, not deletion
**Enforcement:** Release gate where mechanically represented; review gate otherwise

A model-visible tool that has consumers MUST NOT simply disappear or silently change meaning. Deprecation requires an explicit lifecycle state and date; a sunset date may be added when justified. Replacement tools SHOULD be identified when one exists.

---

## 4. Mutations are classified before they become ambient agent powers

### SCOUT-MCP-008 — Every mutation declares its side effects and reversibility
**Enforcement:** Release gate for tools introduced after Doctrine v1; diagnostic gate for legacy tools

Before a new non-read-only tool becomes model-visible, Scout MUST classify:

- whether it affects Scout state, an external system, both, or neither
- whether it is idempotent
- whether it is destructive
- whether it is reversible, compensatable, or irreversible
- any compensation tool when one exists

`unknown` is acceptable during implementation but not for a newly released model-visible mutation.

Legacy mutation tools with `reversibility='unknown'` are tracked as explicit debt; they are not assumed reversible or irreversible.

### SCOUT-MCP-009 — Risky writes require explicit confirmation
**Enforcement:** Release gate for tools introduced after Doctrine v1

A new destructive model-visible operation MUST require explicit confirmation.

A new operation that writes to an external system or mixes Scout-state and external-system effects MUST require explicit confirmation unless a narrower, separately reviewed interaction contract proves that automatic execution is both expected and safe.

Preview/commit/rollback semantics SHOULD be introduced only where the actual mutation risk justifies them. They are not a universal MCP requirement.

---

## 5. Evidence, uncertainty, and provenance survive presentation

### SCOUT-MCP-010 — Preserve evidence lineage through derived surfaces
**Enforcement:** Review gate; diagnostic where schema support exists

When Scout derives a conclusion from evidence, transformations such as ranking, Scout Lens, Evidence Time Machine, Opportunity Constellation, work packages, and briefs SHOULD preserve stable evidence/source identifiers and material uncertainty.

A presentation surface is a projection over canonical Scout facts and derivations; it MUST NOT become a separate source of truth.

Scout SHOULD preserve enough lineage to answer "why is Scout saying this?" without exposing proprietary scoring, source orchestration, calibration, security controls, or reverse-engineering-sensitive internals.

### SCOUT-MCP-011 — Epistemic state is explicit where decisions depend on it
**Enforcement:** Review gate + existing evidence semantics

Material claims SHOULD distinguish documented facts from inference, unresolved unknowns, contradiction, or missing evidence using Scout's canonical evidence semantics rather than ad hoc prose.

A missing signal MUST NOT be silently converted into proof of absence.

---

## 6. Errors teach safe recovery without leaking internals

### SCOUT-MCP-012 — Structured errors are part of the public contract
**Enforcement:** Diagnostic gate + error catalog

Tool/RPC errors MUST NOT be reduced to object coercions such as `[object Object]`.

Safe structured failures SHOULD preserve, when applicable:

- stable error code
- safe message
- validation reason/field
- retryability/recoverability
- recommended next action
- diagnostic identifier

Internal implementation detail is disclosed only when explicitly safe under the exposure/IP contract.

Retry behavior MUST respect idempotency and side-effect semantics. A non-idempotent write MUST NOT be blindly retried after an ambiguous outcome.

---

## 7. External context is capability-scoped and consent-minimized

### SCOUT-MCP-013 — External integrations receive the minimum task context
**Enforcement:** Release/review gates through external-capability contracts

Scout MUST request only the minimum external fields needed for a bounded business purpose. First-use consent remains explicit when required.

Scout MUST NOT receive or persist surrounding chat simply because the host can access it.

Credentials, secrets, unrelated personal context, and broad external account data MUST NOT be included in capability reports or narrowed context requests.

### SCOUT-MCP-014 — No passive conversation-to-insight pipeline
**Enforcement:** Review gate + privacy/telemetry implementation

Ordinary conversations MUST NOT be silently transformed into Scout business signals, product insights, training records, or durable operator facts.

Telemetry MAY record bounded privacy-safe operational dimensions needed to evaluate tool behavior, reliability, routing, or product health. Raw prompts/chat content are not the default telemetry substrate.

Business-signal or improvement ingestion requires an explicit purpose-built workflow and its own privacy contract; it is not an ambient side effect of using Scout.

---

## 8. Presentation is part of the contract

### SCOUT-MCP-015 — Machine payload and operator presentation remain separate
**Enforcement:** Release gate through presentation registration; review gate for UX semantics

Every model-visible tool MUST have a presentation contract. Scout SHOULD provide enough metadata for the host to render the result appropriately while keeping proprietary methodology and restricted internals out of the operator-facing view.

Host-rendered MCP chrome is not controllable by Scout. Tool names, descriptions, pre-call language, result payloads, and Scout-provided surfaces SHOULD therefore minimize unnecessary visual noise rather than trying to fight host UI.

### SCOUT-MCP-016 — Specialized surfaces must earn their existence
**Enforcement:** Review gate

A specialized surface such as Lens, Time Machine, or Constellation SHOULD exist only when its representation materially improves comprehension, comparison, temporal reasoning, or graph reasoning relative to ordinary prose/cards.

Surface state MUST be derivable from canonical Scout state or a clearly scoped ephemeral projection. A UI surface MUST NOT silently mutate canonical ranking/evidence unless the operator explicitly performs a state-changing action.

---

## 9. Advanced MCP patterns require evidence before adoption

### SCOUT-MCP-017 — Novel architecture uses an evidence gate
**Enforcement:** Review gate

Before adopting a new agent/MCP interaction pattern, document:

1. **Observed problem or opportunity** — what current behavior is measurably inadequate?
2. **Hypothesis** — why should the proposed pattern improve it?
3. **Metric/evidence** — what would count as improvement or failure?
4. **Smallest reversible experiment** — can value be tested without committing the architecture?
5. **Rollback path** — how do we remove it without corrupting contracts/data?
6. **Control impact** — does it alter privacy, exposure, authorization, anti-enumeration, or presentation guarantees?
7. **Promotion condition** — what evidence moves it from experiment to supported architecture?

Novelty alone is not evidence.

### SCOUT-MCP-018 — Do not prematurely build speculative agent infrastructure
**Enforcement:** Review gate

The following patterns are not forbidden, but SHOULD NOT be introduced without demonstrated Scout-specific need:

- runtime-generated public tools
- agent-created persistent macros
- broad autonomous investigation/session memory
- generalized transaction engines for harmless internal writes
- universal counterfactual/simulation layers
- passive semantic mining of user conversations
- large multi-agent orchestration frameworks
- dynamic schema negotiation solely because MCP permits it

Where a narrow version solves a real problem, implement the narrow version first.

---

## 10. Routing quality is tested, not assumed

### SCOUT-MCP-019 — Meaningful routing changes get eval coverage
**Enforcement:** Review gate today; candidate for future diagnostic/release gate

A new model-visible tool or a material change to routing semantics SHOULD add or update routing eval fixtures covering:

- a positive/direct route
- at least one plausible confusion case when an adjacent tool exists
- forbidden first tools where a wrong call would leak information, mutate state, or create avoidable friction
- required tool sequence when ordering matters

Tool descriptions are part of routing behavior and should be treated as executable UX, not decorative documentation.

---

## 11. Architecture exceptions

A temporary exception to a MUST rule requires an entry in `agent_ip.architecture_decisions` containing:

- affected rule ID(s)
- scope
- rationale
- risk/consequences
- compensating controls
- verification plan
- revisit/sunset condition when temporary

An exception is not permission to weaken non-negotiable privacy/security guarantees. Some controls may have no acceptable exception path.

---

## 12. Current enforcement registry

| Rule | Current enforcement | State |
|---|---|---|
| SCOUT-MCP-002 | `v_tool_registry_integrity_v1` / `assert_tool_registry_integrity_v1()` | Release gate |
| SCOUT-MCP-005 | `tool_evolution.compatibility_policy` | Release for new tools; review for legacy |
| SCOUT-MCP-006 | `tool_contracts.response_type_slug`, `output_schema_slug`, `tool_evolution.result_envelope_version` | Release for new tools |
| SCOUT-MCP-007 | `tool_evolution.lifecycle_state`, deprecation/sunset constraints | Partial release gate |
| SCOUT-MCP-008 | `tool_contracts` mutation semantics + `tool_evolution` side-effect/reversibility metadata | Release for new tools; diagnostic for legacy |
| SCOUT-MCP-009 | `tool_routing.confirmation` + mutation/evolution metadata | Release for new risky writes |
| SCOUT-MCP-010/011 | evidence semantics/output contracts | Review/diagnostic |
| SCOUT-MCP-012 | error catalog + structured MCP error boundary | Diagnostic/review |
| SCOUT-MCP-013/014 | external-capability/privacy contracts + bounded telemetry dimensions | Release/review |
| SCOUT-MCP-015 | presentation registry integrity | Release gate |
| SCOUT-MCP-017/018 | architecture review | Review gate |
| SCOUT-MCP-019 | routing eval fixtures | Review gate |

The companion database gate is `agent_contract.assert_architecture_doctrine_v1()` and the diagnostic view is `agent_contract.v_architecture_doctrine_release_issues_v1`.

---

## 13. Known architecture debt as of Doctrine v1

The initial `tool_evolution` migration intentionally seeded existing read tools conservatively and left mutation reversibility unclassified. Existing model-visible mutations therefore require a tool-by-tool review before their reversibility field can be treated as authoritative.

This debt is visible through `agent_contract.v_tool_future_readiness_v1` and MUST remain visible until classified; do not bulk-mark legacy mutations merely to make a diagnostic green.

---

## 14. Change procedure

For any new model-visible tool, material tool-contract change, new persistent agent state, new external write, or new specialized presentation surface:

1. Identify the applicable doctrine rule IDs.
2. Prefer the smallest change that preserves stable public semantics.
3. Add deterministic contracts before relying on model instructions.
4. Run registry-integrity and architecture-doctrine assertions.
5. Add routing/evidence/presentation eval coverage appropriate to the change.
6. Record an architecture decision when the design creates a new durable pattern, exception, or security/privacy boundary.
7. Update this doctrine when a repeated design decision has become a general rule.

This document is intentionally a living constitution, not a frozen specification. Changes should make its guarantees sharper as evidence accumulates, not fill it with speculative requirements.