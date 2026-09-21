# Farm Watch Neutral Terrain and Spatial Primitives v1

Status: implementation candidate  
Validation property: `validation-property-01`

## Purpose

This layer closes the neutral-primitive gap between the existing Farm Watch physical evidence products and any future deer-focused hypothesis surface.

It deliberately produces **physical geometry and explicitly parameterized reference cost**, not animal-use inference.

Two independent materialization products are defined:

1. `terrain-form-permeability`
2. `spatial-edge-patch-context`

Neither product computes a deer score, corridor, funnel, bedding area, security cover, forage quality, stand location, or hunting recommendation.

## 1. Terrain-form and permeability product

### Dependencies

The product is keyed to:

- the current barrier-aware landscape-domain identity;
- the current landscape-physical identity;
- the KyFromAbove Phase 3 DEM source contract;
- fixed grid and terrain-form parameters;
- the exact named permeability scenario parameters.

### Analysis scales

The v1 product intentionally separates two grains:

| Grid | Scope | Cell size | Purpose |
| --- | --- | ---: | --- |
| local form grid | current barrier-aware `local_500m` domain | 10 m | terrain-form candidates and fine slope geometry |
| landscape cost grid | current barrier-aware `landscape_1500m` domain | 30 m | broader reference terrain friction |

The existing 61×61 terrain artifact remains unchanged and retains its conditioned-D8 drainage semantics. It is not relabeled as movement evidence.

### Terrain-form candidates

The 10 m grid derives:

- metric slope;
- 30 m local topographic-position index;
- 90 m broad topographic-position index;
- 90 m neighborhood relief;
- orthogonal second-difference curvature sign;
- local slope-break contrast.

The following labels are computational candidates only:

- `ridge_like_candidate`
- `draw_like_candidate`
- `saddle_like_candidate`
- `bench_like_candidate`
- `slope_break_candidate`

Every threshold is stored in the artifact contract. Labels are deterministic geometry, not field-surveyed landforms and not behavioral interpretation.

### Reference permeability scenario

The initial scenario is `reference-slope-only-v1`.

Its dimensionless friction is:

`cost = 1 + slope_weight × (bounded_slope / slope_reference)^exponent`

with explicit v1 parameters:

- base cost: 1;
- slope reference: 30 percent rise;
- slope weight: 1;
- exponent: 1.5;
- slope cap: 100 percent rise.

The reciprocal is encoded as a convenience permeability byte.

This scenario is intentionally **not calibrated to deer or another species**. The current configured hard-barrier domain is honored; other hydrology is contextual only unless a later scenario explicitly assigns it a cost.

## 2. Spatial edge / patch / transition product

### Dependencies

The product is keyed to:

- current landscape-domain identity;
- current landscape-physical identity;
- current resource-edge identity;
- current local landscape-structure materialization identity;
- exact local landscape-structure artifact SHA-256.

The 5 m structure artifact is reused directly. This product does not redownload or recompute raw COPC or aerial imagery.

### Canopy pattern

The current 2025 NLCD TCC surface is sampled on a 30 m metric grid over the exact barrier-aware `local_500m` domain.

Fixed canopy bins are:

- 0–20%;
- 21–60%;
- 61–100%.

The product records:

- 8-neighbor connected patch identities;
- patch area/perimeter summaries;
- class-transition edge length;
- edge density in m/ha;
- class-adjacency edge lengths.

These are grain-dependent physical pattern metrics, not habitat-quality or cover-value scores.

### Mapped field-edge geometry

The product reuses the current Farm Watch resource-edge geometry and records:

- mapped-field membership at the 30 m grid grain;
- distance to the nearest currently mapped field edge.

The result inherits the source boundary-quality limitations and does not establish forage availability, crop condition, harvest state, access permission, or animal use.

### Five-meter structural pattern

The current central `landscape-structure-context` compact grid is decoded without repeating source processing.

Two transition layers are derived from 8-neighbor comparisons:

- mean absolute leaf-off score difference;
- mean LiDAR neutral-profile total-variation distance.

Two categorical patch systems are also recorded:

- leaf-off score quartile patches;
- LiDAR dominant neutral-height-band patches.

These remain measurement-space continuity/discontinuity products. They are not security-cover, corridor, funnel, bedding, regeneration, species, or animal-use classifications.

## Evidence and presentation boundaries

Both products use `deterministic_derived` evidence class and set:

- `scoring_performed=false`
- `behavioral_inference_performed=false`

Raw fine-grid artifacts follow the existing owner-only fine-structure presentation posture. Viewer accounts receive summaries only.

## Invalidation

A change to any bound upstream identity or artifact checksum changes the materialization source signature. The generic Farm Watch materialization identity therefore invalidates the stale derivative rather than silently reusing it.

## Relationship to future deer modeling

Future deer-focused work may consume these primitives as separately versioned inputs. Any biological or behavioral hypothesis must remain a new evidence layer with:

- named hypothesis;
- explicit assumptions;
- its own model version;
- validation/calibration state;
- uncertainty and limitations.

No universal scalar deer score is introduced here.
