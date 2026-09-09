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
- `research.document_evidence_job_candidates` (one clustered buyer job to many base opportunities)

The demo-enrichment layer additionally uses:

- `research.demo_exemplar_priorities_v1` — private manual priority pins; these are boosts, not a portfolio freeze;
- `research.v_demo_exemplar_enrichment_queue_v1` — manual pins plus dynamic water-tank, exterior-cleaning, specialty-facade, and premium-facade candidates; and
- `research.v_demo_exemplar_account_queue_v1` — property-management, facilities-management, builder/contractor, engineering/inspection, and other multi-opportunity accounts.

Service-role-only RPCs are:

- `internal_seed_document_evidence_jobs()`
- `internal_claim_document_evidence_jobs(limit, rule_pack)`
- `internal_complete_document_evidence_job(job_id, outcome, findings, error)`
- `internal_seed_buyer_document_evidence_jobs(cluster_limit)`
- `internal_complete_buyer_document_evidence_job(job_id, outcome, findings, error)`
- `internal_seed_exemplar_document_evidence_jobs()`

## Rule packs

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

### `buyer_organization_contact_v1`

Buyer work is clustered by an already-resolved organization, an exact named project party, or—only when neither exists—normalized site address. Priority combines time sensitivity, documented commercial scale, queue priority, and the number of opportunities a reusable organization result can unlock.

The worker checks existing first-party roots and performs at most two bounded public-web searches and eight page fetches per cluster. It extracts organization identity signals and durable facilities, procurement, supplier-registration, or general contact routes. Server-side persistence is deliberately stricter than extraction:

- a route may attach only to an existing organization ID or one unique exact canonical-name/alias match;
- automated research never creates an organization, a person, or an inferred personal email;
- generic routes are capped below `0.90` confidence and cannot become `VERIFIED DIRECT`;
- address-only evidence and proximity remain investigatory and never become buyer assignments;
- owner, operator, tenant, property manager, contractor, broker, and buyer roles are not collapsed; and
- buyer normalization plus a buyer-only spine projection update the canonical route state without rerunning unrelated classifiers or changing opportunity scores.

Ambiguous or bounded-no-result work becomes `exhausted` with an explicit reason and a 90-day `requery_after`. A changed candidate/source fingerprint can reopen it sooner. The linked buyer queue rows are blocked with `research_exhausted` context rather than being immediately reclaimed.

High-leverage demo accounts may receive **one** bounded deeper retry after normal exhaustion. The retry is explicitly marked `demo_exemplar_retry_used=true`, raises the attempt budget only to three, and cannot reopen indefinitely.

### `surface_work_condition_v1`

This is an **evidence-only** rule pack for demo-exemplar enrichment. It searches exact subject/organization/address context for public text that can narrow or close missing surface-work facts, including:

- explicit exterior/facade, brick, EIFS, masonry, limestone, glass, or window cleaning;
- algae, mold/mildew, moss, lichen, other organic growth, staining/soiling, efflorescence, corrosion/rust, coating failure, or paint failure;
- exterior painting/repainting and coating/recoating;
- surface preparation, including explicit cleaning prior to paint/coating;
- tuckpointing/repointing, facade/masonry restoration or rehabilitation, and sealant work; and
- nearby/current project-year context when the source explicitly states it.

The identity threshold remains strict. This pack **never auto-applies** a visible-condition, chemistry, cleaning-need, or project-status fact into a canonical table. A textual finding is durable provenance that can support a later specialist resolver or human/visual verification. It must not convert a generic cleaning proxy into a claim that a facade is visibly dirty.

### `account_portfolio_context_v1`

This is an **evidence-only** rule pack for account-level demo enrichment. It looks for public first-party evidence of:

- portfolio/property/community/project/location rosters;
- explicit portfolio counts;
- property/facilities management and operating context;
- procurement, purchasing, vendor/supplier, subcontractor/trade-partner, or prequalification routes;
- service-area/market coverage; and
- project portfolios and current/recent project rosters.

It does not create organizations, owners, buyers, people, inferred contacts, or property crosswalks. Findings remain provenance until the existing organization/contact, property-portfolio, building-identity, or buyer-resolution contracts accept them.

## Demo exemplar routing

The exemplar system is deliberately broader than the document worker. Every exemplar records `desired_evidence` and `worker_routes` so missing facts are sent to the strongest existing Scout subsystem instead of being invented by a generic worker.

Typical routing is:

| Missing evidence | Authoritative/primary route |
| --- | --- |
| Water-tank morphology/support geometry | `water_tank_morphology_v1` |
| Facade material / glazing | `facade_material_glazing_v1` + facade attribute views |
| Textual cleaning/paint/coating/condition evidence | `surface_work_condition_v1` |
| Buyer/contact/procurement route | `buyer_organization_contact_v1` |
| Account portfolio/project context | `account_portfolio_context_v1` |
| Property roster / property-to-account crosswalk | property portfolio resolver / account research queues |
| Exact premium-building identity | building identity/reconciliation subsystem |
| Mapped site access/staging | site-access enrichment pipeline |
| Actual visible staining/condition | facade visual verification pipeline; document text cannot substitute for visual evidence |
| Water-source/hose/staging execution | building-cleaning water/hose/preflight decisioning |
| Chemistry/operator fit | chemistry decisioning; document worker does not infer product suitability |

This separation is intentional. The goal is maximum attainable completeness without weakening provenance or turning a document crawler into an all-purpose classifier.

## Retry and failure budget

A document-classification job gets at most three claims by default. Buyer jobs get two claims, with a seven-day evidence retry and 90-day exhausted requery interval, except for the single bounded high-leverage exemplar retry described above. Later attempts may use broader source discovery. No-evidence claims are retried after a backoff; repeated failures eventually become `exhausted`. Conflicting direct evidence becomes `needs_review` immediately.

This is deliberate: the worker must not grind indefinitely or turn weak evidence into a classification merely to reduce a backlog count.

## GitHub Actions

`.github/workflows/scout-document-evidence.yml` runs every two hours with single-run concurrency and may also be invoked manually. It now executes `scripts/scout_document_evidence_runner.py`, which supports all five rule packs while reusing the original worker's acquisition, PDF extraction, hashing, and no-media-retention behavior.

Opening an issue titled exactly:

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

Do not let a Python rule pack name arbitrary database tables/columns. Server-side RPCs must continue to validate each supported write path explicitly. Evidence-only packs are preferred when the correct canonical write path belongs to another Scout subsystem.
