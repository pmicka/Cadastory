# Farm Watch Deer Science Context v4

> **Superseded:** Current evaluator semantics are defined in `FARM_WATCH_DEER_SCIENCE_CONTEXT_V5.md`. v5 retains the v4 fidelity matrix and adds the explicit fail-closed deer state framework and relationship-specific state gates.

- **Status:** implementation candidate — explicit evidence-fidelity matrix
- **Version:** 2026-10-01
- **Species:** white-tailed deer (`Odocoileus virginianus`)
- **Normative science source:** `FARM_WATCH_DEER_SCIENCE_EVIDENCE_LEDGER.md`
- **Registry source:** `farm-watch-deer-relationship-registry.ts`

## Purpose

`deer-science-context-v4` is the first Farm Watch property/date/scenario evaluator.

It consumes the machine-readable deer relationship registry plus current Farm Watch evidence and determines, relationship by relationship, whether the relationship is:

- `active`;
- `not_applicable`;
- `insufficient_input`;
- `blocked_measurement_alignment`.

It does not create a universal deer score, deer-presence probability, movement probability, bedding score, habitat score, or hunting recommendation.

The evaluator implementation is:

- `supabase/functions/_shared/farm-watch-deer-science-evaluator.ts`
- `supabase/functions/_shared/farm-watch-deer-science-evaluator.test.ts`

The private Farm Watch endpoint is the initial transport surface.

## Request contract

The authenticated private endpoint retains its existing default behavior. Optional query parameters select an explicit deer scenario:

- `at=<ISO timestamp>`
- `deer_sex=male|female|unknown`
- `deer_age_class=juvenile|yearling|adult|unknown`
- `deer_movement_state=resident|dispersal|unknown`
- `deer_reproductive_state=unknown|nonbreeding|estrus|pregnant|parturition|lactation`

Omitted biological dimensions remain `unknown`.

The evaluator never fills an unknown biological dimension from a generic calendar heuristic. The existing Kentucky regional breeding context remains population-level timing evidence only.


## Evaluator-active versus property-specific directional evidence

An `active` registry relationship means that the relationship's biological gates, study-fidelity requirements, product bindings, spatial scales, and value constraints are satisfied for the requested scenario. It does **not** establish that the property exhibits a study-aligned covariate contrast or a local deer response.

Each relationship carries one of four decision-relevance classes:

- `directional_relationship_context`: an active quantitative or ordinal relationship whose literature-supported direction is relevant to the scenario;
- `mechanism_context`: active explanatory or conditional context;
- `negative_constraint`: active guardrail that blocks an unsupported generic rule;
- `abstained`: not applicable, insufficient input, or measurement blocked.

Directional relationships may now declare an explicit `property_conditioning` rule in the registry. The evaluator applies such a rule only after the relationship is registry/scenario active and only to the configured measured covariate.

Property-directional evidence uses a separate state machine:

- `not_configured`: no property-conditioning contract exists for the directional relationship;
- `insufficient_measurement`: the contract exists but the configured measured contrast cannot be resolved;
- `measured_no_contrast`: the configured metric is measured but has no non-zero ordered-scale contrast;
- `hypothesis_available`: a real property covariate contrast exists and a bounded property-conditioned hypothesis may be stated;
- `not_applicable`: the relationship output is not directional.

A `hypothesis_available` result is still **not** a local deer-use or behavioral-response inference. `decision_actionable=false`, `behavioral_probability_inferred=false`, and coefficient transfer remain unchanged unless a future contract separately authorizes stronger inference.

## Evaluation order

Each registry relationship is evaluated in this order:

1. **Registry applicability** — an explicitly `not_applicable` registry record remains not applicable.
2. **Biological gate** — known state mismatches are `not_applicable`; required but unknown state is `insufficient_input`.
3. **Study measurement fidelity** — unresolved required source-study measurements return `blocked_measurement_alignment`.
4. **Output-kind fidelity** — a context-only measurement contract cannot emit an ordinal or quantitative effect.
5. **Required product bindings** — product key, evidence state, spatial scale, and any/all semantics must match the registry.
6. **Study-specific value constraints** — known false constraints are `not_applicable`; unresolved constraints are `insufficient_input`.
7. **Active relationship result** — only then may the evaluator emit the relationship form, output kind, and registry-authorized direction.
8. **Property conditioning** — only an active directional relationship with an explicit registry rule may inspect the configured measured property covariate and emit a bounded property-conditioned hypothesis.
9. **Measurement-fidelity reporting** — every declared source-study variable is emitted as an evaluated matrix row that keeps scientific equivalence separate from current product availability/binding.

This order deliberately distinguishes “the study does not apply here” from “we do not know enough.”

## Evidence adapter

The Farm Watch adapter converts current backend products into explicit registry bindings. It preserves unavailable and stale states rather than silently promoting them.

Current bindings include:

- deer biological state;
- diel / photoperiod;
- seasonal precipitation state;
- field phenology;
- mapped agricultural land-cover geometry;
- barrier-aware 500 m / 1.5 km / 3 km mapped-field acreage and denominator areas, converted deterministically to explicit agricultural-fraction measurements for property conditioning;
- current crop identity only when explicitly accepted;
- thermal exposure;
- terrain form;
- LiDAR physical structure;
- study-aligned vegetation height;
- spatial edge / patch context;
- horizontal visibility;
- mast capacity;
- exact-year annual mast state;
- conifer cover;
- forest type;
- human footprint;
- exact study-scale context;
- multiscale forest context;
- snow / winter severity;
- extreme-event context;
- surface-water state;
- managed food;
- managed artificial water;
- mapped hydrography;
- source-aligned road focal context.

A catalog product that is not actually available is represented as `unavailable`, not omitted and not inferred.

## Evidence-fidelity matrix

Every `study_measurements` entry now produces one runtime matrix row. The matrix does not replace the relationship gate; it makes the gate inspectable.

Scientific equivalence uses five explicit classes:

- `exact` — the Farm Watch variable is measurement-equivalent to the source-study variable for the permitted use;
- `study_aligned_derivative` — the same physical/semantic variable is reproduced through a documented deterministic derivative;
- `calibrated_proxy` — the variable is an authorized calibrated proxy, not an exact copy;
- `mechanism_only` — the available Farm Watch variable can explain mechanism/context but cannot substitute for the source-study measurement in relationship activation;
- `unavailable` — no authorized substitute exists.

Each row separately exposes:

- source measurement ID, variable, and protocol;
- registry alignment and normalized fidelity class;
- activation role (`required`, `context_only`, or `not_applicable`);
- relationship use (`supports_activation`, `context_only`, `blocks_relationship`, or `not_applicable`);
- bound Farm Watch product(s);
- allowed evidence states and spatial scales;
- current binding status;
- matched current evidence;
- permitted use and limitations;
- an explicit proxy-inflation guard.

This separation is intentional. **Product availability is not measurement equivalence.** A current Farm Watch product may bind successfully while the source-study variable remains `mechanism_only` or `unavailable`; in that case the product's presence cannot promote the relationship.

For example, FW-R01 can have current `thermal-exposure-context` available while FW-M01 operative temperature remains `mechanism_only`, because the source study used black-globe operative temperature rather than Farm Watch's current physical thermal context. FW-M03 forage index remains `unavailable` because greenness/phenology does not reproduce standing crop plus forage chemistry. By contrast, FW-M02 vegetation height is `study_aligned_derivative` because the production product preserves the source variable family and support while documenting its interpolation differences.

FW-M55/R30 is `mechanism_only` and required for activation. Mapped agriculture is measurable across Farm Watch fixed-radius domains, but those domains do not reproduce the source study's individual 95% aKDE natal-range support. The current covariate remains visible in the fidelity matrix, while it blocks both relationship activation and the directional property hypothesis until source-aligned support is available.

## On-demand road context

The source-aligned M36 road focal calculation is comparatively expensive. The private endpoint resolves it on demand only when the requested scenario can reach FW-R18:

- male;
- juvenile;
- dispersal.

Other scenarios do not pay that computation cost because FW-R18 is already biologically not applicable.

## Value-constraint hardening

The evaluator enforces all registry value constraints.

A new explicit FW-R22 constraint was added:

`FW-C06-extreme-event-active`

It requires:

`extreme_event.applicability_state = active_extreme_event`

Therefore a healthy NWS poll with no qualifying property-intersecting tropical/extreme-wind event produces `not_applicable`. Product freshness alone cannot activate the Hurricane Irma relationship.

Existing FW-C05 likewise requires an actually present usable water source. Flat Creek's explicit 2026 managed-water absence therefore cannot activate the semiarid water-visitation relationship.

## Output

The private response adds:

`deer_science_context`

It contains:

- schema / algorithm version;
- property and evaluation timestamp;
- explicit scenario;
- counts by relationship status;
- module-family summaries;
- one evaluation record per registry relationship;
- source relationship and ledger IDs;
- source citations;
- biological gate result;
- required-input matches;
- study-fidelity status;
- enforced value constraints;
- output kind and literature-supported relationship direction when active;
- per-relationship source-variable evidence-fidelity matrix;
- aggregate fidelity-class and current-binding counts;
- explicit property-directional-evidence state;
- measured property-covariate observations and contrasts when a registry conditioning rule exists;
- property-conditioned hypothesis counts and IDs;
- directional relationship-context counts and IDs;
- decision-actionable counts and IDs, which remain empty for the current hypothesis-only conditioning contract;
- transfer limitations;
- abstention / non-applicability reasons.

## 2026-10-01 research guardrails

The registry now includes two additional active negative constraints from the updated evidence ledger:

- `FW-R32-seasonal-edge-aspect-negative-constraint` — forest-edge and north/south aspect effects are season-dependent in the 2025 southwest Wisconsin telemetry study; no universal edge or aspect sign is authorized.
- `FW-R33-fawn-visibility-concealment-negative-constraint` — the 2026 Minnesota neonatal-fawn study keeps horizontal visibility, predator-view concealment and vegetation height separate and blocks a universal cover-to-survival rule.

Their source measurement rows are emitted through the v4 evidence-fidelity matrix as context-only research provenance. They do not create new property-conditioned hypotheses, decision-actionable outputs, or coefficients.

## Coefficient and score boundary

The evaluator does not synthesize relationships.

It publishes:

- `scoring_performed=false`;
- `coefficient_synthesis_performed=false`;
- `behavioral_probability_inferred=false`.

A relationship whose registry says `coefficient_transfer.status=not_supported` emits no numeric parameters.

The output is therefore a vector of independently gated scientific relationships, not an arbitrary weighted overlay. A registry-active directional relationship is relationship context only until property-conditioned evidence is evaluated.

## Flat Creek consequences

### R08 diel hardening

FW-R08 now accepts only `morning_civil_twilight` and `evening_civil_twilight`. Civil twilight remains a transparent time-of-day proxy rather than a measurement-equivalent copy of the source activity-period windows. At `night` or `day`, the relationship is not applicable.

### Managed water

Flat Creek 2026 is explicitly configured with no managed artificial water.

FW-R23 can therefore return `not_applicable` when its summer gate would otherwise match, because FW-C05 requires current usable-source presence. Nearby mapped hydrography does not override that absence.

### Extreme events

When the authoritative current extreme-event product reports a healthy poll with no qualifying property intersection, FW-R22 returns `not_applicable`.

Ordinary rain, wind, or thunderstorms cannot activate it.

### Mast

The 2026 KDFWR annual mast state is currently unavailable. The evaluator cannot create an exact-year mast effect from modeled mast-producing-tree capacity or a prior-year survey.

In addition, FW-R11 currently carries context-only measurement fidelity while its registry output is ordinal; the evaluator therefore refuses to emit that ordinal result.

### Dispersal relationships

FW-R18 and FW-R19 can become active only under an explicitly requested juvenile-male dispersal scenario and their required source-aligned physical inputs.

An adult resident scenario does not inherit those findings.

FW-R18 remains conditional mechanism context and does not assign a universal ridge, valley, or road sign. FW-R19 may expose its literature-supported interaction direction as `directional_relationship_context`, but no path-specific conditioning rule exists, so it remains `not_configured` for property directional evidence.

### R30 property-conditioning contract

FW-R30 is the first relationship with an explicit property-conditioning contract.

The source study measured the proportion of each juvenile male's pre-dispersal range classified as agricultural land use using 95% aKDE range vertices. Farm Watch does **not** reproduce that animal-specific support geometry. Instead, it already carries mapped agricultural-field acreage and exact barrier-aware denominator areas at 500 m, 1.5 km, and 3 km around the property.

The registry retains an explicit property-conditioning rule for possible future use, but its presence does not establish measurement alignment. The evaluator currently:

1. expose the mapped agricultural values and declared scales in the evidence-fidelity matrix;
2. mark FW-M55 `mechanism_only` and required;
3. block relationship activation and property conditioning because fixed-radius windows do not reproduce the source study's individual 95% aKDE support.

No directional property hypothesis is emitted until source-aligned support is available. The fixed-radius windows remain a support-geometry proxy, not an aKDE natal range. The evaluator must not transfer the Wisconsin logistic coefficient, estimate dispersal probability, establish that Flat Creek is a natal range, or claim that a juvenile male dispersed. Any future eligible result remains `decision_actionable=false`.

### Hunting pressure

Relationships requiring actual hunter activity remain blocked/insufficient as dictated by the registry. Open hunting season, roads, stands, or access geometry do not manufacture pressure.

## Deployment boundary

This unit implements and source-controls the evaluator and private-endpoint integration.

Production deployment of the updated private Edge Function is a separate action. Until that deployment is explicitly authorized, production continues to serve the previously deployed private endpoint version.
