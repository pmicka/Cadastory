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

It also preserves **study-fidelity contracts**:

- study variable / field protocol;
- the Farm Watch binding that is proposed to represent it;
- measurement-alignment class;
- whether alignment is required for activation or context-only;
- value/subtype constraints that a future evaluator must enforce;
- explicit limitations where the current Farm Watch product is only adjacent physical context.

## Measurement-alignment discipline

Product-name compatibility is not sufficient to activate a deer relationship.

The v1 measurement-alignment vocabulary is:

- `measurement_equivalent` — Farm Watch represents substantially the same measured variable;
- `derived_equivalent` — Farm Watch deterministically derives the same semantic quantity from authoritative geometry/state;
- `calibrated_proxy` — a proxy is permitted only after calibration/validation against a study-aligned measurement;
- `mechanism_context_only` — physically/biologically related context, but not the variable measured in the source study;
- `unsupported` — the source-study variable is not currently represented well enough for activation.

A future deer module is rejected when any measurement marked `required` is only `mechanism_context_only` or `unsupported`.

A relationship whose measurements are all context-only may be used only as `mechanism_context`; it cannot silently become an ordinal or quantitative selection effect.

Examples established by the 2026-09-23 fidelity audit:

- current Thermal Exposure is useful physical context but does not calculate the operative temperature used by FW-D01;
- Batch 6 generalized horizontal visibility is not the FW-D04 Gallina cover-pole concealment measurement;
- current `juvenile | yearling | adult` age classes cannot reproduce FW-D06's yearling / 2-year-old / 3+ male age contrast;
- FW-D15 riparian path selection consumes mapped river/stream geometry, not current water-presence evidence;
- FW-D16's published 1 km² / 9 km² / hunting-unit scale design is not equivalent to generic 500 m / 1.5 km / 3 km context;
- FW-D17 requires predator-occurrence context in addition to human footprint and natural habitat.

## Value/subtype constraints

Some studies require more than a valid product and scale. The registry therefore stores machine-readable value constraints.

Examples:

- FW-D08 requires **corn**, not merely a known crop, and the relevant tasseling/silking or post-harvest state;
- FW-D10 requires an actual **hunting** event at a specific stand;
- FW-D13's null result requires documented **low hunting pressure**;
- FW-D19 requires an actually available water source rather than mapped hydrography or an off-property gauge.

A future module definition must declare the study-measurement contracts and value constraints it enforces. The registry validator rejects omitted constraints.

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

The registry instead requires the planned `low-height-concealment-context` input for FW-D04 relationships. Gallina et al. used a 2 m cover pole, four 50 cm vertical sections, readings from 15 m, and directional concealment. This preserves the completed Batch 6 general physical visibility product while preventing its generic 1.5 / 3 / 6 m equal-height rays from being silently substituted for the field protocol.

The generalized viewshed remains useful for neutral physical visibility and may later help derive a **stand vulnerability-zone** product for FW-D10, whose source study mapped what a hunter could actually see from each stand rather than using a uniform distance buffer. That is a separate measurement-alignment problem and requires validation/calibration before deer-risk interpretation.

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

## Blocked-measurement resolution

The 2026-09-23 study-fidelity audit produced a second source-controlled contract:

- `supabase/functions/_shared/farm-watch-deer-measurement-resolution.ts`
- `docs/FARM_WATCH_DEER_MEASUREMENT_RESOLUTION_V1.md`

Every measurement that currently blocks a relationship has exactly one disposition:

- `reproduce` — implement the same semantic variable;
- `calibrated_proxy` — implement a plausible estimator and promote it only after study-aligned validation;
- `remain_unavailable` — do not create a weak substitute.

The current portfolio contains 36 blocked measurements: 21 reproducible, 9 calibrated proxies, and 6 intentionally unavailable. FW-M02 vegetation height has exited this queue after production validation and promotion to `derived_equivalent`; FW-R01 remains blocked by FW-M01, FW-M03, FW-M04, and FW-M05.

This resolution layer is planning/governance only. A `reproduce` or `calibrated_proxy` decision does not change the relationship registry's current alignment status. The relationship remains blocked until the corresponding neutral product is implemented and its exit gate is satisfied.

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
