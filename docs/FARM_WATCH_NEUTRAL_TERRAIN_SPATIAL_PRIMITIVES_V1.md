# Farm Watch Neutral Terrain and Spatial Primitives v1

Status: production materialized  
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

## Production validation — 2026-09-21

Both v1 products are centrally materialized for `validation-property-01` through the owner-only GitHub Actions OIDC workflow `.github/workflows/farm-watch-neutral-primitives.yml`.

### Terrain form / permeability

- materialization identity: `a4d02fa0738ea005efd0456027b0940a66b1155f7cd1a6c24a1287312e1f102f`;
- artifact SHA-256: `b69a778cb91aa0d87e92fedfe9213d07b72caadf551ba6dfb2b95f4b45af45ee`;
- stored size: 632,109 bytes; Storage metadata size matches exactly;
- barrier-aware local grid: 17,136 domain-valid 10 m cells, with 16,697 cells carrying valid slope/form output;
- barrier-aware 1.5 km grid: 6,550 domain-valid 30 m cells;
- current source signature binds to landscape-domain identity `bd69c24e98c485a9320c07db036548c4b065a2c381e77f2ab5cd73fc73e9ae5f` and landscape-physical identity `c89b681dd724390087249d4b92dbacc0fdfaea06f3bf1acbe46999a6d2547bc6`.

The current form counts among cells with valid local slope/form output are 2,139 ridge-like candidates, 2,033 draw-like candidates, 1,078 saddle-like candidates, 999 bench-like candidates, 77 slope-break candidates, and 10,371 unclassified-surface cells. These remain computational geometry labels only.

### Spatial edge / patch context

- materialization identity: `9cdb6dd495a1e6e6de158e2686485b95ef94e83394b9121171f6455012f9ee4c`;
- artifact SHA-256: `99edf000a5c5ad846b25be8d61c36b352ecb5fb25f30db1468499ea3ddc532e0`;
- stored size: 1,406,006 bytes; Storage metadata size matches exactly;
- current source signature binds to:
  - landscape-domain identity `bd69c24e98c485a9320c07db036548c4b065a2c381e77f2ab5cd73fc73e9ae5f`;
  - landscape-physical identity `c89b681dd724390087249d4b92dbacc0fdfaea06f3bf1acbe46999a6d2547bc6`;
  - resource-edge identity `2a57436d1c289f0496972cfe020071db2c8e7e1fc82bacb22a060b02d06e9051`;
  - landscape-structure identity `403f75926234f88e5ebc69e1cec7c0af3fbeac5b1ca23468a7d1cbc3464c5b69`;
  - exact landscape-structure artifact SHA-256 `8dee53eaf17e725e467806cbfc7a0ca6c5106f87d2f117123c36703ca5a2fccf`.

The production read path downloaded and contract-validated both stored artifacts immediately after materialization. Both builds completed on their first attempt with no persisted error.

## Relationship to future deer modeling

Future deer-focused work may consume these primitives as separately versioned inputs. Any biological or behavioral hypothesis must remain a new evidence layer with:

- named hypothesis;
- explicit assumptions;
- its own model version;
- validation/calibration state;
- uncertainty and limitations.

No universal scalar deer score is introduced here.
