# Farm Watch Deer Relationship Registry v1

Status: Batch 9 implementation contract  
Species: white-tailed deer (`Odocoileus virginianus`)  
Normative science source: `docs/FARM_WATCH_DEER_SCIENCE_EVIDENCE_LEDGER.md`

## Purpose

`deer-relationship-registry-v1` is the machine-readable transfer layer between the durable deer-science evidence ledger and future deer-specific evaluation modules.

It does **not** evaluate a property, predict deer use, or produce a score. It records what a future module is allowed to evaluate, which inputs and biological states are required, what spatial/temporal scale is supported, whether a coefficient may be transferred, and when the module must abstain or remain blocked.

The implementation lives in:

- `supabase/functions/_shared/farm-watch-deer-relationship-registry.ts`
- `supabase/functions/_shared/farm-watch-deer-relationship-registry.test.ts`

## Registry model

A relationship record is distinct from a ledger entry.

One ledger study may support multiple machine relationships. For example:

- FW-D04 supports a general hot-bedsite mechanism and a narrower fawning-female low-concealment relationship.
- FW-D05 supplies both positive diel/reproductive context and negative constraints against moon-phase / routine-weather movement rules.
- FW-D06 supplies an age-dependent breeding-season relationship and a separate negative constraint against treating firearm opening as a generic movement trigger.

Every relationship preserves:

- relationship ID;
- one or more FW-D ledger IDs;
- source citations;
- response variable;
- required input products;
- allowed input evidence states;
- biological-state gates;
- spatial and temporal scale;
- relationship form and direction;
- supported nonlinearity where present;
- coefficient-transfer disposition;
- parameter-source version;
- null / blocked conditions;
- output kind;
- transfer limitations.

## Output kinds

The v1 vocabulary is:

- `quantitative_relative_selection`
- `ordinal_directional`
- `mechanism_context`
- `negative_constraint`
- `not_applicable`
- `insufficient_input`

No v1 relationship currently authorizes a transferred numeric deer-selection coefficient.

## Input-state discipline

Required inputs may accept only explicitly permitted states.

For a required input, v1 rejects:

- `stale`
- `unavailable`
- `blocked`
- `abstained`

unless a future contract is deliberately revised with scientific justification. Proxy inputs are permitted only where the relationship record explicitly allows them.

The registry also declares the spatial scales supported by each current or planned Farm Watch input product. A future module definition fails validation when its bound product scale does not match the relationship contract.

## Biological-state discipline

Relationship gates reuse the existing deer biological-state vocabulary:

- sex;
- age class;
- movement state;
- individual reproductive state;
- regional reproductive context;
- season;
- diel period.

When a relationship narrows one of these dimensions, that dimension must be listed as required. Unknown biological state therefore cannot silently inherit a sex-, age-, reproductive-, or movement-state-specific relationship.

The existing Batch 3 `applicable_relationship_ids` annotation is now derived from registry metadata rather than separate hard-coded FW-D rules.

## Blocked universal assumptions

The registry machine-enforces the evidence ledger's current blocked assumptions, including generic:

- moon-phase movement effects;
- barometric-pressure movement effects;
- wind movement effects;
- cold-weather movement effects;
- north/south slope preference;
- ridge/draw/saddle travel rules;
- road avoidance/selection;
- dense vegetation = bedding/security cover;
- field edge = deer use;
- CDL crop identity = current food;
- nearest water/discharge = deer use;
- open hunting season = current hunting pressure.

A future module definition containing one of these assumptions fails registry validation.

## Batch 6 measurement-alignment boundary

FW-D04 does **not** consume `horizontal-visibility-context-v1` as if it were the study's low-height concealment measurement.

The registry instead requires the planned `low-height-concealment-context` input for FW-D04 relationships. This preserves the completed Batch 6 general physical visibility product while preventing its generic 1.5 / 3 / 6 m ray scenarios from being silently substituted for the study's sub-meter concealment strata.

## Ledger coverage

CI reads `FARM_WATCH_DEER_SCIENCE_EVIDENCE_LEDGER.md` and compares every `FW-Dxx` heading against the registry.

Therefore:

- a new ledger entry requires registry representation;
- a registry relationship without ledger provenance is invalid;
- mixed studies may map to multiple relationship records;
- provenance-only evidence can be represented as `not_applicable` rather than being forced into an active module.

## Coefficient rule

`coefficient_transfer.status` is independent of relationship-form transfer.

CI rejects:

- numeric parameters when transfer status is `not_supported` or `not_applicable`;
- `quantitative_relative_selection` output unless coefficient transfer is explicitly `authorized`.

This prevents published study magnitudes, dates, distances, or effect sizes from becoming Kentucky coefficients merely because the relationship form is useful.

## Batch 9 boundary

Batch 9 ends at the relationship contract and validation layer.

It does not implement:

- thermal/resource deer evaluation;
- agriculture response evaluation;
- mast response;
- localized hunting-risk evaluation;
- terrain/movement evaluation;
- water response;
- `deer-science-context-v1`;
- a universal deer score.

Those remain Batch 10+ work and must consume this registry rather than recreate scientific rules in ad hoc code.
