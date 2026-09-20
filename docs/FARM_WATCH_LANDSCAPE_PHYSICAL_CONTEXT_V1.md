# Farm Watch Landscape Physical Context v1

## Purpose

Landscape Physical Context adds centrally persisted, barrier-aware canopy and terrain primitives around a selected Farm Watch property.

It is a deterministic evidence product. It does **not** compute deer suitability, likely travel, bedding, feeding, security cover, hunting pressure, or any other wildlife-use conclusion.

## Spatial contract

The product consumes the current `landscape-domain` identity and summarizes four adjacent analysis areas:

| Area | Geometry |
| --- | --- |
| selected property | exact property boundary; canonical parcel land context is reused rather than recomputed |
| local ring | barrier-aware 500 m domain minus the selected property |
| mid ring | barrier-aware 1,500 m domain minus the 500 m domain |
| outer ring | barrier-aware 3,000 m domain minus the 1,500 m domain |

Ring geometry is derived centrally in PostGIS. The Edge Function does not recreate barrier logic.

## Canopy primitives

Canonical canopy source:

- USDA Forest Service / MRLC National Annual Tree Canopy Cover;
- NLCD TCC CONUS v2025-6;
- 2025;
- 30 m modeled percent tree canopy cover.

For every surrounding ring, Farm Watch stores:

- minimum and maximum modeled canopy percent;
- mean, median, P10, P25, P75, and P90;
- standard deviation;
- raster observation count;
- modeled canopy-equivalent acreage;
- canopy-band shares and acreage for 0%, 1–20%, 21–40%, 41–60%, 61–80%, and 81–100%.

The selected-property values come from canonical `property_land_context_v1`; they are not re-fetched.

## Canopy composition gradients

Adjacent areas are compared as:

1. selected property → local ring;
2. local ring → mid ring;
3. mid ring → outer ring.

For each comparison Farm Watch reports:

- mean-canopy delta;
- 0–20% canopy-share delta;
- 21–60% canopy-share delta;
- 61–100% canopy-share delta;
- `composition_shift_pp`, equal to one-half of the L1 difference among those three aggregate shares.

These are **aggregate composition gradients**.

They are not:

- mapped forest-edge length;
- pixel adjacency;
- edge density;
- corridor detection;
- habitat classification;
- deer-use inference.

A future true edge/adjacency product should use an explicitly spatial raster/vector algorithm and a different contract.

## Terrain primitives

Canonical terrain source:

- Kentucky Division of Geographic Information / KyFromAbove;
- Phase 3 DEM;
- ArcGIS ImageServer geometry-clipped statistics.

For each ring Farm Watch stores:

- elevation min/max/mean/median/standard deviation/relief;
- slope min/max/mean/median/P90/standard deviation;
- slope-area bands: 0–10%, 10–20%, 20–30%, 30–50%, and 50%+;
- raster observation counts.

Slope semantics remain percent rise with `ZFactor = 0.3048`.

Adjacent-area terrain gradients report:

- mean-elevation delta;
- relief delta;
- mean-slope delta;
- share-of-area delta at 30%+ slope.

These are descriptive terrain contrasts, not movement cost or route preference.

## Storage and refresh

The product is stored in:

`farm_watch.property_landscape_physical_context_v1`

The current identity includes:

- selected property boundary;
- `landscape-domain` identity and retrieval state;
- current parcel `land` identity and retrieval state;
- raster-source and algorithm contract.

A changed property boundary, barrier-aware domain, canonical parcel land refresh, source signature, algorithm version, or output schema invalidates the stored product.

The normal cache horizon is 30 days.

## Execution

`farm-watch-land` remains the authenticated execution surface.

After resolving/refeshing the canonical parcel land context, it:

1. reads the current barrier-aware ring geometries;
2. queries authoritative canopy/DEM raster services for the three surrounding rings;
3. normalizes the structured statistics;
4. derives aggregate adjacent-area gradients;
5. persists the result centrally;
6. returns it as `landscape_physical` alongside the existing `land` result.

No browser-side raster download or deterministic landscape recomputation is introduced.

## Evidence boundary

The product explicitly records:

- `evidence_class: deterministic_derived`;
- `scoring_performed: false`;
- `behavioral_inference_performed: false`.

This product is intended to become input to later named deer-relevant hypotheses, not to silently become one.
