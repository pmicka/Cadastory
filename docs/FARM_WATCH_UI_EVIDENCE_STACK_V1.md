# Farm Watch UI Evidence Stack v1

Status: production-deployed private evidence inventory.

## Purpose

The Farm Watch UI previously surfaced Deer Context from four components only:

- Seasonal State;
- diel / photoperiod;
- deer biological state;
- field phenology.

That remains useful, but it omitted neutral physical products that were already available centrally. The inventory now includes both generalized structural products and the production-validated study-aligned vegetation-height measurement.

`deer-evidence-stack-v1` adds a private presentation inventory. It does not compute new environmental evidence and does not perform deer interpretation.

## Source contract

The service-only reader returns the latest central metadata/summary for:

- LiDAR physical vertical structure;
- study-aligned vegetation height (`study-aligned-vegetation-height-context-v2`);
- landscape physical structure;
- terrain form / permeability;
- spatial edge / patch context;
- potential solar exposure;
- thermal exposure context;
- horizontal visibility / obstruction;
- mast-producing species capacity.

For each product the UI can receive:

- availability state;
- algorithm/schema version;
- materialization identity;
- evidence class;
- compact summary;
- source provenance;
- limitations;
- artifact checksum;
- completion/expiration time.

Raw private artifact paths are not exposed by this inventory.

## Dependency-aware freshness

Materialization retention and evidence freshness are separate concerns.

The evidence stack now resolves each materialized product against the current product contract and the identities of the dependencies that produced it. An artifact is reported as `available` only when the applicable checks still match, including:

- current algorithm and output-schema contract;
- ordinary materialization expiration;
- current landscape/domain or upstream materialization identity and artifact checksum where the product depends on them;
- the requested calendar date for date-bound solar exposure;
- the requested exact timestamp and currently admissible HRRR analysis identity, valid time, source-index checksum, and selected-record checksum for thermal exposure.

A retained artifact that no longer matches those dependencies is reported as `stale` with explicit `freshness_reason_codes`. It is not deleted or rewritten. The same retained artifact can still be `available` for an exact historical date/time when its bound dependencies match that historical request.

The private Farm Watch response uses the exact timestamp-aware reader so the deer-science evaluator receives freshness state for the same scenario time it is evaluating. Date-only compatibility reads remain supported; current-date reads resolve at current time and historical date-only reads use local noon as the deterministic timestamp convention.

This rule is generalized across the materialized evidence dependency graph rather than implemented as a thermal/HRRR exception.

## Surface Water State

The reader also exposes the exact-date `surface-water-state-v1` snapshot when Batch 7 is deployed and materialized.

Batch 7 is intentionally optional at this boundary. If its table is not deployed, the UI receives:

`status = not_deployed`

If the table exists but no exact-date snapshot exists, the UI receives:

`status = not_materialized`

This prevents the rest of the evidence UI from failing because Batch 7 has a separate deployment lifecycle.

## Privacy and semantics

The reader and public-schema wrapper remain service-role only.

The output is a private UI review inventory. Product availability does not mean:

- a deer relationship is applicable;
- a coefficient is transferable;
- a deer state has been inferred;
- a deer-use prediction has been made;
- a score exists.

The UI must preserve each product's own limitations and distinguish neutral physical evidence from later literature-backed relationship modules.


## FW-M02 vegetation-height exposure

The evidence inventory includes `study-aligned-vegetation-height-context` as neutral physical evidence.

Its presence means only that the production-validated first-return-minus-ground vegetation-height product is available for review. The deer relationship registry separately controls whether a study relationship may consume it.

For FW-R01/FW-D01:

- FW-M02 is `derived_equivalent`;
- negative-clamped cells remain unavailable for scientific height use;
- FW-D01 remains blocked by operative temperature, forage index, woody canopy, and activity-period fidelity.


## Technical-view catch-up — 2026-09-25

The private Farm Watch response now augments the neutral evidence inventory with three technical-only presentation inputs:

- `managed-food-feature-context-v1`, including explicit known-absence semantics for a configured property/year;
- `managed-water-source-context-v1`, including explicit known-absence semantics for managed artificial water;
- `deer-science-readiness-v1`, derived from the canonical relationship registry and measurement-resolution contract rather than browser-maintained status lists.

The science-readiness summary exposes:

- the currently active measurement-calibration queue;
- parked measurement counts by operating posture;
- relationship study-fidelity counts (`module_eligible`, `context_only`, and `blocked_measurement_alignment`).

This is a technical readiness/status surface only. It does not evaluate current property applicability, biological-state gates, relationship value constraints, coefficient transfer, or deer use.

For Flat Creek 2026, the technical UI may therefore distinguish:

- managed forage: confirmed absent;
- managed artificial water: confirmed absent;
- supplemental feed/mineral attractant point observations: factual operator evidence, separate from managed-food and managed-water configuration;
- remaining active science work: field calibration only.

The guided viewer remains unchanged in this unit.
