# Farm Watch Mast Capacity v1

Status: Batch 5A implementation merged/deployed; operator-assisted bounded BIGMAP transport validated 2026-09-24; full 28-species production materialization pending

## Purpose

`mast-capacity-v1` represents **where mast-producing tree species have modeled biomass capacity** inside the current Farm Watch barrier-aware landscape domain. It is deliberately separate from annual mast production, mast-fall timing, property observations, and deer interpretation.

## Operational v1 source

Batch 5A uses USDA Forest Service FIA **BIGMAP 2018 Tree Species Aboveground Biomass**, a 30 m modeled/imputed species biomass product expressed in tons/acre. The preferred operational source remains the official Forest Service ArcGIS Online BIGMAP ImageServer (`di-usfsdata.img.arcgis.com`) for bounded analytical reads; raw CONUS rasters are not copied into Farm Watch. Production validation on 2026-09-22 established that neither available cloud execution path can currently reach the analytical service: `imagery.geoplatform.gov` returned edge-level HTTP 403 responses to GitHub-hosted Actions on both GET and POST; the official `di-usfsdata.img.arcgis.com` host failed DNS resolution from Supabase Edge; and direct GitHub Actions access to that host failed before an HTTP response.

On 2026-09-24 an operator-assisted fallback was validated against the official Forest Service Raster Data Gateway: download the authoritative whole-CONUS species archive on a trusted workstation, crop only the exact Farm Watch native-grid `broad_3000m` bounding window with GDAL, verify the bounded crop, and transport only that bounded source into the existing OIDC-gated GitHub materializer. The national raster remains workstation-local and is not persisted by Farm Watch.

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

## Source-transport validation — 2026-09-24

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

The Forest Service Raster Data Gateway whole-CONUS archive is now used only as a **workstation transport source**, not as a Farm Watch storage architecture. The validated white-oak (`SPCD 0802`) source raster was 89,932 × 91,150 Float32 cells on the expected 30 m NAD83 CONUS Albers grid. The exact Farm Watch crop used source window `42166,43231,206,222`, producing bounds `957150,1752060,963330,1758720` with zero reprojection or resampling. The bounded crop was 100 KB with SHA-256 `b9cfdb257ae7c55e5ada6bbf1ef20305ddc04eb61e16cb517edeee4d9cca3045`; independent GDAL statistics reported 42.25% valid cells, mean white-oak biomass 1.6397 tons/acre, and maximum 11.0013 tons/acre.

A source-controlled Debian helper now validates the national grid, performs the same native-grid crop for all 28 required mast species, hashes the bounded crops, and emits a manifest/bundle. The GitHub materializer accepts that bundle through a draft-release handoff and still uses the existing OIDC-gated claim/complete/storage path. The draft release is transport only and should be deleted after successful materialization.

**Current state:** bounded authoritative transport is validated, but the full 28-species source bundle has not yet been supplied and the production `mast-capacity-v1` artifact is therefore still unavailable. Batch 5B remains out of scope until Batch 5A production materialization passes.
