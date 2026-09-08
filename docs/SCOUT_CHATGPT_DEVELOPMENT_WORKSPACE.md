# Scout by Cadastory — ChatGPT Development Workspace

**Purpose:** Canonical source for ChatGPT Project instructions and development-session provisioning rules for Scout by Cadastory.

**Scope:** Developer-side work on Scout. This document does not replace `AGENTS.md` or `docs/SCOUT_MCP_ARCHITECTURE_DOCTRINE.md`; those remain normative for repository and MCP architecture behavior.

**Last updated:** 2026-09-08

---

## Development environment

Unless explicitly requested otherwise:

- Do **not** mount, invoke, or test through the Scout by Cadastory MCP/app.
- Work on Scout from the developer side.
- Use GitHub repository `pmicka/Cadastory`.
- Use Supabase project `ufpkjaadmmpmeogzhrcq` (`built-environment-intelligence`).
- Firecrawl is available as developer-side research tooling.
- Prefer the actual current GitHub and Supabase state over recollections from previous conversations.

Do not assume an implementation, migration, deployment, collector, repair, or enrichment job is still in the state described by an old chat when the live system can be checked directly.

## Source-of-truth hierarchy

For implementation questions, use this priority:

1. Current production/database state when behavior depends on deployed data or schema.
2. Current GitHub code and configuration.
3. Durable project documentation and project sources.
4. Previous Scout conversations.
5. General memory or inference.

If these disagree, investigate the discrepancy rather than silently choosing whichever version is convenient.

## Scout MCP usage

Do **not** use the Scout by Cadastory MCP as the default data-access layer during development.

Prefer:

- **Supabase first** for data, counts, enrichment coverage, stored evidence, opportunity records, operator/profile state, database behavior, and other backend questions that can be answered directly from the database.
- **GitHub first** for code, migrations, contracts, edge functions, implementation state, architecture, and repository documentation.
- **Scout MCP only when the MCP itself is part of what is being tested.**

Typical reasons to invoke Scout include:

- UI/UX testing
- host rendering behavior
- tool ergonomics
- capability discovery
- tool routing
- public/model-visible contract behavior
- privacy/exposure behavior
- presentation contracts
- structured result handoff
- error marshalling
- end-to-end MCP regression testing
- external-agent behavior

Do not call Scout merely as an indirect route to information already available cleanly in Supabase.

When testing Scout against backend truth, use **Supabase as the control** and Scout as the test surface.

## Firecrawl role

Firecrawl has two standing development roles.

### 1. MCP and app-development intelligence

Use Firecrawl when meaningful architectural, product, or agent-interface work would benefit from current external evidence.

Research areas include:

- MCP design and protocol evolution
- agent-app architecture
- tool design and tool ergonomics
- model-facing API design
- host/app integration patterns
- structured output and presentation contracts
- capability discovery
- authentication and authorization patterns
- error handling and error marshalling
- context management
- agent reliability
- observability
- interoperability
- current practices from OpenAI, Anthropic, Google, the MCP ecosystem, and other credible implementations

Prefer current primary documentation, specifications, engineering material, and strong real-world implementations.

External novelty is not automatically a Scout requirement. Recommend adoption only when there is a defensible benefit to usability, reliability, decision quality, security, interoperability, maintainability, or developer ergonomics.

Prefer reversible experiments and measurable improvements over speculative architecture.

### 2. OWASP and security engineering

Use current OWASP guidance as an active development reference, including relevant material from:

- OWASP Cheat Sheet Series
- OWASP Application Security Verification Standard (ASVS)
- OWASP Web Security Testing Guide (WSTG)
- secure-code-review guidance
- relevant API and application security guidance

Apply it particularly to:

- authentication
- authorization
- tenant and user isolation
- input validation
- output encoding
- secrets
- API boundaries
- MCP/tool boundaries
- error handling
- data exposure
- logging
- abuse resistance
- secure defaults
- privilege boundaries
- external integrations
- uploaded or retrieved content
- prompt/tool injection boundaries

OWASP is development guidance, not a Scout runtime dependency.

A full OWASP-informed security audit remains a required pre-release task before Scout ships.

## External-tool architecture constraint

Do **not** build Scout product features, runtime workflows, architecture, or core capabilities around the availability of Firecrawl, Figma, another MCP, or another developer-side integration.

Developer tools may assist:

- research
- design
- implementation
- testing
- validation
- audits

Scout itself must continue to function without those development tools.

## Storage and media discipline

Do **not** use Firecrawl as transient storage for:

- images
- screenshots
- extracted media
- temporary documents
- analysis artifacts

Do **not** use Google Drive as transient or scratch storage for those materials.

Use local ephemeral/container storage for temporary processing.

Only save or deliver something to Google Drive when explicitly requested.

Firecrawl may retrieve or inspect public web content; retrieval is not permission to use Firecrawl as an artifact store.

When images or other bulky source material are needed only to derive structured facts, prefer retaining the derived facts and provenance rather than permanently retaining the source media.

Do not retain images merely because they were used during verification.

## Evidence and provenance

Scout should distinguish:

- observed fact
- authoritative record
- derived fact
- heuristic
- model inference
- operator knowledge
- hypothesis

Do not silently convert one category into another.

When practical, externally derived intelligence should retain enough provenance to determine:

- source
- source authority
- observation/publication date
- collection date
- geographic scope
- confidence
- freshness or expiration
- licensing/use restrictions where relevant
- whether the underlying evidence is redistributable
- whether Scout is storing the source itself or only a derived fact

Do not manufacture precision when the source does not support it.

## Operator knowledge

Operator expertise is valuable and may materially improve Scout.

Model it explicitly rather than treating anecdotal knowledge as universally established fact.

Prefer structures that allow:

- operator-specific knowledge
- confidence
- corroboration
- applicability conditions
- evidence
- later promotion into generalized Scout knowledge when justified

A strong operator insight may immediately influence that operator's decisioning without prematurely becoming a universal rule.

## Cross-vertical design

Look for reusable factors across Scout verticals — spatial, geometric, seasonal, ecological, material, operational, social, regulatory, and financial — but do not force unrelated industries into an artificial universal model.

Normalize a concept when doing so genuinely improves reasoning or reuse.

Preserve vertical-specific rules when the underlying business mechanics differ.

Scout should be capable of combining generic factors with specialized domain intelligence.

## Security and privacy invariants

Preserve Scout's existing:

- privacy boundaries
- authorization controls
- anti-enumeration protections
- exposure contracts
- presentation contracts
- tenant/user isolation
- deterministic security controls

Do not weaken a deterministic security or privacy control in favor of prompt instructions.

Do not expose internal data simply because it would make an MCP response easier to implement.

For MCP-related changes, also follow `AGENTS.md` and `docs/SCOUT_MCP_ARCHITECTURE_DOCTRINE.md`.

## Database changes

Before material database work, inspect the relevant current schema and migrations rather than assuming an earlier chat describes them perfectly.

Use migrations for schema/DDL changes.

Avoid untracked schema drift.

After material schema or security changes, check relevant Supabase security and performance advisors.

Prefer additive, reversible migrations when practical.

Do not hard-code generated production identifiers into migrations.

## Code changes

Inspect the relevant current implementation before modifying it.

When changing an interface or behavior, trace the important downstream callers and contracts rather than patching only the first failing location.

Prefer fixing shared abstractions when multiple failures have the same root cause.

Do not duplicate logic simply to make an isolated test pass.

Preserve backward compatibility where it has product value; do not preserve accidental behavior merely because it exists.

## Documentation durability

Important implementation knowledge should not exist only inside a ChatGPT conversation.

When a change establishes a lasting architectural rule, schema contract, operational procedure, security invariant, or deployment requirement, update or create appropriate durable repository documentation when warranted.

Do not create documentation merely for documentation's sake.

Prefer concise documentation adjacent to the thing it governs.

## Implementation versus deployment

Treat implementation and deployment as distinct operations unless an instruction clearly combines them.

Implementing code does not automatically authorize a production deployment.

Phrases such as:

- `push this to production`
- `deploy it`
- `ship it`
- `make it live`

authorize the appropriate deployment and verification steps for the work in context.

Phrases such as:

- `proceed`
- `continue`
- `finish this`
- `implement it`

mean continue the current development task without repeatedly asking for permission for ordinary non-destructive work.

Use extra care around destructive data operations, irreversible changes, credential/security changes, and ambiguous production-impacting actions.

## Verification standard

Do not equate "code written" with "task complete."

When feasible, verify changes at the appropriate layers:

- static/code correctness
- database behavior
- integration behavior
- regression behavior
- exposed MCP contract behavior when relevant
- production behavior when deployment was requested

If verification is incomplete, state exactly what remains unverified.

## Research adoption discipline

External research should produce three distinguishable outcomes:

1. useful information
2. recommendation for Scout
3. adopted Scout behavior

Do not blur them together.

Something discovered in OpenAI, Anthropic, Google, OWASP, another MCP implementation, academic literature, or an industry product should not silently become a Scout requirement.

Explain why an externally derived idea is applicable before materially restructuring Scout around it.

## Current-work behavior

At the beginning of a substantial new Scout workstream, orient to the relevant live state first.

Do not redo previously completed collection, recovery, enrichment, or migration work unless current evidence shows it is incomplete, stale, incorrect, or needs extension.

When instructed to "pin this," treat the decision or idea as something that should remain recoverable and distinguish it from an instruction to implement immediately.

When an investigation uncovers adjacent low-risk work that is clearly required to complete the requested task, continue through it instead of stopping unnecessarily.

Surface material discoveries, especially:

- hidden architectural coupling
- privacy/security issues
- data-quality defects
- provenance problems
- significant technical debt
- unexpectedly valuable reusable abstractions
- assumptions that current evidence disproves

## Product philosophy

Scout should be restrained but forward-looking.

Adopt new techniques when evidence suggests they materially improve:

- usability
- reliability
- model/tool ergonomics
- decision quality
- security
- interoperability
- maintainability

Avoid novelty for its own sake.

Prefer measurable benefit, strong evidence, reversible experiments, and incremental adoption.

The objective is not to build the most technically elaborate system possible.

The objective is to build an unusually capable, trustworthy decision-support system that turns fragmented real-world information into actionable business intelligence.

---

## ChatGPT Project usage

This file is intended to serve as the canonical source for Scout's ChatGPT development workspace.

For a dedicated ChatGPT Project:

1. Add this file as a Project source or copy its operative sections into Project Instructions.
2. Keep Scout development chats inside that Project when practical.
3. Use Project-only memory when isolation from unrelated conversations is desired.
4. Keep GitHub canonical for code and durable engineering documentation.
5. Keep Supabase canonical for live structured backend state.
6. Keep Project sources deliberately small and high-signal rather than mirroring the entire repository or database.

Recommended durable Project sources include:

- current architecture snapshot
- current-state handoff
- decision register
- security invariants
- data-source register

Use conversation branching for genuine architectural or product experiments so alternative approaches can be explored without corrupting the main line of work.
