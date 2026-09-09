# Scout document evidence worker

Scout's document evidence worker is a private, developer-side enrichment subsystem for extracting durable facts from public engineering reports, specifications, drawings with extractable text, inspection reports, project pages, and other public documents.

It exists to keep evidence-heavy enrichment from consuming interactive development sessions. It is **not** a Scout MCP/runtime dependency and is not model-visible.

## Contract

The worker:

1. seeds bounded domain jobs from existing Scout queues;
2. claims jobs with a lease from Supabase;
3. discovers documents from authoritative/known source roots and source-specific discoverers;
4. downloads source files only into the GitHub runner's temporary filesystem;
5. extracts PDF text with Poppler and HTML text directly;
6. records page-level derived evidence, hashes, source URLs, and confidence;
7. auto-applies only direct, non-conflicting evidence allowed by the rule pack;
8. checkpoints partial/no-evidence/failure states for later retries; and
9. retains **no source PDF/image/media** in Scout or GitHub artifacts.

The durable queue and evidence tables are:

- `research.document_evidence_jobs`
- `research.document_evidence_findings`

Service-role-only RPCs are:

- `internal_seed_document_evidence_jobs()`
- `internal_claim_document_evidence_jobs(limit, rule_pack)`
- `internal_complete_document_evidence_job(job_id, outcome, findings, error)`

## Initial rule packs

### `water_tank_morphology_v1`

The worker may auto-apply:

- explicit `pedesphere` / `pedosphere` -> single pedestal, no external bracing;
- explicit `composite elevated` -> single pedestal, no external bracing;
- explicit `fluted column` -> single pedestal, no external bracing;
- explicit standpipe or ground-storage terminology -> operator support heuristic not applicable;
- explicit multi-column/multiple-leg evidence **plus** explicit bracing, strut, or windage-rod evidence -> challenging multi-column/cross-braced geometry;
- explicit multiple-column/leg evidence without bracing -> partial only (`multi_column`, bracing unknown).

Capacity, construction date, generic `ELEVATED`, double-ellipsoidal/toroellipsoidal terminology by itself, or a project number by itself never clears the geometry queue.

Kentucky PSC is the first source-specific discoverer. It uses the PSC's public case-year and case-filing pages, matches the exact utility, ranks engineering/inspection/specification documents, and then applies the same document-identity and conflict controls as direct source URLs.

### `facade_material_glazing_v1`

The first pass is seeded only from Scout's **high-priority** facade verification queue. Detailed terms are retained as evidence, but automatic facade-material promotion is intentionally narrower:

- the document must establish exact building/project identity;
- a primary/predominant exterior-material statement is required before a singular facade material is promoted;
- explicit curtain-wall/window-wall/unitized/stick-built glazing can establish facade-system glazing;
- explicit storefront can establish localized glazing;
- conflicting documents or multiple incompatible direct claims go to review rather than being forced into a single value.

The existing coarse facade-material taxonomy remains the canonical building attribute. More specific terms such as EIFS, precast concrete, metal panels, or limestone are retained in the finding/extracted-value provenance even when mapped to a coarser canonical material.

## Retry and failure budget

A job gets at most three claims by default. Later attempts may use broader source discovery. No-evidence claims are retried after a backoff; repeated failures eventually become `exhausted`. Conflicting direct evidence becomes `needs_review` immediately.

This is deliberate: the worker must not grind indefinitely or turn weak evidence into a classification merely to reduce a backlog count.

## GitHub Actions

`.github/workflows/scout-document-evidence.yml` runs every two hours with single-run concurrency and may also be invoked manually. Opening an issue titled exactly:

`[ops] Run Scout document evidence worker`

also triggers one run, matching Scout's existing operations pattern.

The workflow installs Poppler at runtime and uploads no artifacts.

## Adding another domain

New domains should reuse acquisition/indexing and add a rule pack with:

- explicit subject identity requirements;
- allowed evidence codes;
- conflict semantics;
- the narrow set of server-side auto-apply mappings; and
- a queue seeding rule.

Do not let a Python rule pack name arbitrary database tables/columns. Server-side RPCs must continue to validate each supported write path explicitly.
