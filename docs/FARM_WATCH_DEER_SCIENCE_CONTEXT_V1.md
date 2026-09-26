# Farm Watch Deer Science Context v1

Status: implementation candidate  
Version: 2026-09-26  
Species: white-tailed deer (`Odocoileus virginianus`)  
Normative science source: `FARM_WATCH_DEER_SCIENCE_EVIDENCE_LEDGER.md`  
Registry source: `farm-watch-deer-relationship-registry.ts`

## Purpose

`deer-science-context-v1` is the first Farm Watch property/date/scenario evaluator.

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

## Evaluation order

Each registry relationship is evaluated in this order:

1. **Registry applicability** — an explicitly `not_applicable` registry record remains not applicable.
2. **Biological gate** — known state mismatches are `not_applicable`; required but unknown state is `insufficient_input`.
3. **Study measurement fidelity** — unresolved required source-study measurements return `blocked_measurement_alignment`.
4. **Output-kind fidelity** — a context-only measurement contract cannot emit an ordinal or quantitative effect.
5. **Required product bindings** — product key, evidence state, spatial scale, and any/all semantics must match the registry.
6. **Study-specific value constraints** — known false constraints are `not_applicable`; unresolved constraints are `insufficient_input`.
7. **Active result** — only then may the evaluator emit the relationship form, output kind, and registry-authorized direction.

This order deliberately distinguishes “the study does not apply here” from “we do not know enough.”

## Evidence adapter

The Farm Watch adapter converts current backend products into explicit registry bindings. It preserves unavailable and stale states rather than silently promoting them.

Current bindings include:

- deer biological state;
- diel / photoperiod;
- seasonal precipitation state;
- field phenology;
- mapped agricultural land-cover geometry;
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
- output kind and direction when active;
- transfer limitations;
- abstention / non-applicability reasons.

## Coefficient and score boundary

The evaluator does not synthesize relationships.

It publishes:

- `scoring_performed=false`;
- `coefficient_synthesis_performed=false`;
- `behavioral_probability_inferred=false`.

A relationship whose registry says `coefficient_transfer.status=not_supported` emits no numeric parameters.

The output is therefore a vector of independently gated scientific relationships, not an arbitrary weighted overlay.

## Flat Creek consequences

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

FW-R18 remains conditional mechanism context and does not assign a universal ridge, valley, or road sign.

### Hunting pressure

Relationships requiring actual hunter activity remain blocked/insufficient as dictated by the registry. Open hunting season, roads, stands, or access geometry do not manufacture pressure.

## Deployment boundary

This unit implements and source-controls the evaluator and private-endpoint integration.

Production deployment of the updated private Edge Function is a separate action. Until that deployment is explicitly authorized, production continues to serve the previously deployed private endpoint version.
