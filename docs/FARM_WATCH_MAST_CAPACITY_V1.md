# Farm Watch Mast Capacity v1

Status: Batch 5A implementation contract

## Purpose

`mast-capacity-v1` represents **where mast-producing tree species have modeled biomass capacity** inside the current Farm Watch barrier-aware landscape domain. It is deliberately separate from annual mast production, mast-fall timing, property observations, and deer interpretation.

## Operational v1 source

Batch 5A uses USDA Forest Service FIA **BIGMAP 2018 Tree Species Aboveground Biomass**, a 30 m modeled/imputed species biomass product expressed in tons/acre. The public Forest Service ImageServer is used for bounded analytical reads; raw CONUS rasters are not copied into Farm Watch.

TreeMap 2023 remains a fresher future refinement candidate because its plot-ID raster can be linked to the accompanying FIA tree table. Batch 5A does not block on that bulk-delivery path.

## Mast groups

The v1 artifact maintains separate continuous modeled biomass surfaces for:

- white-oak group;
- red-oak group;
- hickory group;
- American beech.

Species membership is source-controlled in `farm-watch-mast-capacity-contract.ts`. Oak grouping follows the established white-oak/red-oak botanical split used by Kentucky forestry references; the species list is scoped to the Kentucky/Central Hardwood use case.

## Spatial scope

The product uses the current `broad_3000m` geometry from `farm_watch_get_landscape_domain_v1_internal`, preserving the landscape-domain identity in the materialization signature. Summaries are emitted for property, local 500 m, landscape 1.5 km, and broad 3 km scopes.

## Output semantics

Per 30 m cell, the artifact preserves modeled live-tree aboveground biomass in tons/acre for each mast group.

Neutral summaries include:

- modeled-cell count;
- positive-biomass cell count and share;
- mean / median / p90 / maximum modeled biomass density.

No ecological threshold is assigned to those values.

## Interpretation boundary

This is **capacity**, not mast production. A positive white-oak biomass pixel does not establish that an observed white oak occurs at that exact location, that it is mature enough to fruit, that it produced acorns in the current year, that acorns are currently falling/present on the ground, or that deer use the location.

Annual KDFWR mast state belongs to Batch 5B and remains separate.
