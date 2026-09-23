# Farm Watch UI Evidence Stack v1

Status: implemented in source; production migration/Edge deployment pending explicit deployment authorization.

## Purpose

The Farm Watch UI previously surfaced Deer Context from four components only:

- Seasonal State;
- diel / photoperiod;
- deer biological state;
- field phenology.

That remains useful, but it omitted neutral physical products that were already available centrally, including the new horizontal-visibility product.

`deer-evidence-stack-v1` adds a private presentation inventory. It does not compute new environmental evidence and does not perform deer interpretation.

## Source contract

The service-only reader returns the latest central metadata/summary for:

- LiDAR physical vertical structure;
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
