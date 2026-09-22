# Farm Watch Mast Capacity v1

Status: Batch 5A implementation merged/deployed; production materialization blocked on upstream BIGMAP source transport

## Purpose

`mast-capacity-v1` represents **where mast-producing tree species have modeled biomass capacity** inside the current Farm Watch barrier-aware landscape domain. It is deliberately separate from annual mast production, mast-fall timing, property observations, and deer interpretation.

## Operational v1 source

Batch 5A uses USDA Forest Service FIA **BIGMAP 2018 Tree Species Aboveground Biomass**, a 30 m modeled/imputed species biomass product expressed in tons/acre. The intended operational source is the official Forest Service ArcGIS Online BIGMAP ImageServer (`di-usfsdata.img.arcgis.com`) for bounded analytical reads; raw CONUS rasters are not copied into Farm Watch. Production validation on 2026-09-22 established that neither available cloud execution path can currently reach the analytical service: `imagery.geoplatform.gov` returned edge-level HTTP 403 responses to GitHub-hosted Actions on both GET and POST; the official `di-usfsdata.img.arcgis.com` host failed DNS resolution from Supabase Edge; and direct GitHub Actions access to that host failed before an HTTP response. Therefore no BIGMAP source raster was materialized and no mast-capacity artifact is currently available in production.

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

Per 30 m cell, the artifact preserves modeled live-tree aboveground biomass in tons/acre for each mast group. The grid remains in BIGMAP's native USA Contiguous Albers projection (`ESRI:102039`) and uses nearest-neighbor export on an aligned 30 m grid so the materializer does not introduce a Web Mercator resampling step.

Neutral summaries include:

- modeled-cell count;
- positive-biomass cell count and share;
- mean / median / p90 / maximum modeled biomass density.

No ecological threshold is assigned to those values.

## Interpretation boundary

This is **capacity**, not mast production. A positive white-oak biomass pixel does not establish that an observed white oak occurs at that exact location, that it is mature enough to fruit, that it produced acorns in the current year, that acorns are currently falling/present on the ground, or that deer use the location.

Annual KDFWR mast state belongs to Batch 5B and remains separate.

## Production validation stopping point — 2026-09-22

Implementation is merged and the protected worker is deployed, but Batch 5A has **not** passed its production exit gate.

Validated successfully:

- `mast-capacity-v1` contract and tests;
- source-controlled white-oak, red-oak, hickory, and beech groups;
- 30 m native BIGMAP grid / ESRI:102039 processing contract;
- barrier-aware `broad_3000m` domain identity binding;
- OIDC-gated claim/fail/complete/storage path;
- private derived-artifact design with no raw source persistence;
- CI for contract, materializer, worker, and shared OIDC consumers.

Production source-access attempts:

1. `imagery.geoplatform.gov` from GitHub Actions: HTTP 403 on GET and form-POST catalog requests;
2. official Forest Service ArcGIS Online BIGMAP host from Supabase Edge: DNS resolution failure;
3. official Forest Service ArcGIS Online BIGMAP host directly from GitHub Actions: fetch failure before an ArcGIS HTTP response.

The Forest Service Raster Data Gateway does provide official whole-CONUS per-species downloads with checksums, but replacing a bounded 3 km analytical read with 28 whole-CONUS downloads would violate the intended bounded-centralization architecture and was not adopted.

**Current state:** implementation-ready but source-transport blocked. No capacity values, annual mast state, deer inference, or Batch 5B work should be considered production-complete until a bounded, authoritative, cloud-reachable BIGMAP/TreeMap delivery route is verified.
