# Farm Watch Conifer Cover Context v1

Status: production deployed and validated — 2026-09-25

## Purpose

`conifer-cover-context-v1` resolves **FW-M09** for the DelGiudice, Fieberg & Sampson (2013) winter dense-conifer relationship.

It is a neutral physical vegetation-availability product. It does **not** infer deer use, bedding, snow shelter value, mortality risk, movement, habitat quality, or management value.

## Source-study measurement

DelGiudice et al. delineated stands from leaf-off color-infrared aerial photography, assigned dominant tree species, and classified conifer canopy closure as:

- open conifer: less than 40% closure;
- moderately dense conifer: 40% to less than 70% closure;
- dense conifer: at least 70% closure.

The fitted habitat-availability representation used three classes:

- moderately dense conifer;
- dense conifer;
- other.

The source `other` class included open conifer, openings, and hardwoods. Habitat availability was calculated at the study-site scale and updated for timber harvest and succession.

The four source study sites were approximately 13, 20, 23, and 24 km². Farm Watch therefore uses the current `broad_3000m` barrier-aware domain as the relationship-binding availability scale. Smaller summaries are retained as neutral diagnostics rather than substituted for the source site-scale availability context.

## Farm Watch source reconciliation

Farm Watch uses two already-registered federal 30 m products:

### Dominant vegetation-type proxy

- source slug: `usgs-annual-nlcd-land-cover`;
- authority: USGS / Multi-Resolution Land Characteristics Consortium;
- class 42: `Evergreen Forest`;
- role: conservative proxy for a conifer-dominant stand.

Annual NLCD class 42 is used because evergreen trees dominate the mapped tree cover. `Mixed Forest` (43) is **not** promoted to conifer: it remains in the study `other` class because neither evergreen nor deciduous trees establish the required dominant lifeform signal.

### Canopy closure proxy

- source slug: `nlcd-tree-canopy-cover-2025`;
- authority: USDA Forest Service / MRLC;
- product family: National Annual Tree Canopy Cover v2025-6;
- values: modeled percent tree canopy cover from 0–100;
- spatial support: 30 m.

### Common-year rule

The two source families are paired using the **latest year available in both**.

At initial production validation:

- latest Annual NLCD land-cover year: 2024;
- latest TCC year: 2025;
- M09 common source year: **2024**.

This deliberately avoids crossing a 2024 vegetation-type mask with 2025 canopy closure.

## Classification

For each valid 30 m paired source cell:

- Annual NLCD 42 + TCC <40% → open conifer diagnostic → study class `other`;
- Annual NLCD 42 + TCC 40% to <70% → `moderately_dense_conifer`;
- Annual NLCD 42 + TCC ≥70% → `dense_conifer`;
- all other valid land-cover classes, including Mixed Forest 43 → `other`.

The exact 40% and 70% source thresholds are preserved.

No generic canopy-density cell becomes conifer without the evergreen-dominant type mask.

## Spatial domains

The worker downloads aligned nearest-neighbor 30 m rasters once over the current broad landscape extent and summarizes cells whose centers fall within the exact Farm Watch geometries:

- property;
- local 500 m;
- landscape 1.5 km;
- broad 3 km.

The product records both exact polygon area and center-sampled raster area. Landscape-domain identity is part of persistence identity; a domain change makes the stored product stale.

Deterministic identity includes the property boundary, landscape-domain identity, common source year, source-service metadata hashes, exported raster hashes, classification contract, and normalized scientific context. The top-level retrieval timestamp is stored as provenance but is excluded from the content hash. Consecutive unchanged production refreshes were verified to retain the same identity while `retrieved_at` advanced.

The deer relationship registry binds M09 at `broad_3000m`. Property, 500 m, and 1.5 km outputs are diagnostic physical context.

## Evidence state

M09 is a **calibrated proxy**, not a derived-equivalent measurement.

Reasons:

- the source study used manual air-photo stand delineation and dominant-species interpretation;
- Annual NLCD Evergreen Forest is a national categorical model rather than the source stand map;
- NLCD TCC is modeled 30 m percent canopy rather than source air-photo closure interpretation;
- the rare moderate class is particularly sensitive to 30 m edge placement.

These limitations are retained rather than being hidden by the shared physical units and matching closure thresholds.

## Flat Creek production validation — 2026-09-25

Validation property: `validation-property-01` / Flat Creek Test Property.

Production identity:

`3a01b1c88aa92769ebf37955c1c8b7be99844af374b3f9224934868c7936840a`

Common source year: **2024**.

All four domains had 100% valid paired source-cell coverage.

| Domain | Exact area | Moderate conifer | Dense conifer | Other |
| --- | ---: | ---: | ---: | ---: |
| Property | 17.369 ha | 0% | 0% | 100% |
| Local 500 m | 171.217 ha | 0% | 0.6835% | 99.3165% |
| Landscape 1.5 km | 589.447 ha | 0.0153% | 1.2366% | 98.7481% |
| Broad 3 km | 2,139.412 ha / 21.394 km² | 0.0421% | 2.3345% | 97.6235% |

Broad-domain diagnostics:

- 565 Evergreen Forest cells;
- 555 dense-conifer cells;
- 10 moderately dense-conifer cells;
- 0 open-conifer cells;
- 3,368 Mixed Forest cells retained in `other`;
- mean TCC inside mapped Evergreen Forest: 84.24%.

The broad 3 km domain's ~21.4 km² area lies within the source study-site size range and is therefore the Farm Watch binding scale for availability.

## Bounded imagery QA

Representative source cells were checked against current high-resolution KyFromAbove Phase 3 RGB imagery using temporary in-memory crops.

Observed QA:

- dense samples were centered on compact, visibly evergreen closed-canopy patches;
- Mixed Forest samples were visibly heterogeneous, supporting the conservative `Mixed Forest → other` treatment;
- the rare moderate samples occurred in partially closed / edge-like evergreen settings rather than uniformly dense conifer.

No open-conifer source cell occurred in the Flat Creek broad domain, so the local QA did not independently exercise that class.

The imagery was used only for transient verification and was not persisted in Farm Watch. The temporary QA transport was removed immediately after inspection.

The result supports production use as a **calibrated proxy**. It does not justify promotion to `derived_equivalent`.

## Persistence and refresh

Table:

`farm_watch.property_conifer_cover_context_v1`

Protected worker:

`farm-watch-conifer-cover-context`

The worker retains the established Farm Watch materialization-worker authentication and `verify_jwt:false` posture.

Flat Creek refresh is scheduled monthly. The annual/common-year source rule means routine refreshes are inexpensive and idempotent until a newer common source year becomes available.

## Deer-science boundary

FW-M09 is no longer a blocked study measurement.

Together with completed FW-M08, the required snow/minimum-temperature and conifer-availability measurements no longer block FW-R03 on measurement fidelity. **FW-R03 nevertheless remains `context_only`** because FW-M10 winter solar/thermal exposure is context-only.

This product does not authorize:

- a generic `conifers = winter bedding` rule;
- a generic cold-weather movement multiplier;
- a positive Kentucky conifer preference;
- a snow-shelter or energetic-benefit score;
- transfer of Minnesota habitat-availability coefficients or effect magnitudes;
- treating Mixed Forest as conifer-dominant;
- treating canopy closure alone as conifer cover.
