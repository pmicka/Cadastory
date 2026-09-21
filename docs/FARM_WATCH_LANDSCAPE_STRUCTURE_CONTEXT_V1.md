# Farm Watch Landscape Structure Context v1

## Purpose

Landscape Structure Context extends Farm Watch's fine structural evidence from the parcel to the exact barrier-aware `local_500m` domain.

The product answers a narrow physical question:

> Does fine vegetation structure observed on the selected property continue into the immediately surrounding landscape, transition near the ownership boundary, or terminate against a larger structural contrast?

It does **not** assert deer movement, security cover, bedding, feeding, travel corridors, or hunting value.

## Why this is a separate product

The canonical parcel products remain unchanged:

- Phase 3 LiDAR physical structure: `phase3-copc-physical-v3-multiasset`;
- leaf-off woody-pattern context: `leaf_off_structure_v1_2_7m`;
- parcel structural complementarity: `current-leaf-off-lidar-complementarity-v4`.

Those artifacts were built and normalized for the selected property. Expanding their geometry in place would change their meaning and provenance.

Landscape Structure Context therefore has its own identity, artifact, and normalization while reusing the frozen physical methods.

## Domain contract

The analysis geometry is the stored `farm_watch.property_landscape_domains_v1.local_500m` geometry for the selected property.

That geometry already includes the configured hard-barrier handling. For `validation-property-01`, the Kentucky River exclusion therefore applies automatically.

A circular 500 m buffer is not an acceptable fallback. If the current local domain is unavailable, the product is unavailable.

The product identity binds to the exact landscape-domain `identity_sha256`. Any property-boundary, hydrology, barrier-rule, or landscape-domain algorithm change therefore invalidates this product.

## LiDAR method

The product reuses the current Phase 3 physical method without retuning:

- KyFromAbove Phase 3 COPC;
- clean Class 2 ground support;
- 2 m ground grid;
- 10 m ground-support radius;
- 5 m structure cells;
- minimum 10 returns per eligible structure cell;
- neutral thresholds at 4, 16, 32, and 64 ft.

Source coverage is resolved against the **entire barrier-aware local_500m geometry**, not against the parcel.

This is important because the parcel's current one-tile source plan is not evidence that the full 500 m domain is covered by the same COPC tile. The landscape product must select all intersecting usable Phase 3 assets and fail closed if sampled domain coverage is incomplete.

## 2024 leaf-off method

The product reuses the frozen 2024 Phase 3 leaf-off estimator:

- 1 m target imagery;
- 2 m target terrain support;
- 7 m neighborhood;
- luminance local standard deviation + gradient magnitude;
- 45/55 texture weighting;
- slope surface correction;
- false-color observation support;
- documented 2024 solar geometry.

Only the current 2024 observation is required for this product. The 2019 transfer experiment remains a separate parcel-scale QA question.

The 2024 score is normalized within the local_500m analysis domain. That makes inside/outside comparison coherent within this product but means the numeric scores are not interchangeable with the canonical parcel-normalized leaf-off artifact.

## Combined 5 m grid

LiDAR and 2024 leaf-off evidence are synthesized onto one 5 m grid spanning the local_500m domain.

Every cell records masks for:

- valid barrier-aware domain;
- selected property;
- valid LiDAR structure;
- valid leaf-off observation.

The compact artifact carries at least:

- neutral LiDAR dominant-height band;
- 2024 leaf-off score;
- property/domain masks.

Raw source rasters and COPC data are not retained merely for this product.

## Initial neutral summaries

### Property versus surrounding local ring

For both the exact property and `local_500m - property`, report:

- eligible 5 m cell count;
- LiDAR neutral height-band composition;
- 4–32 ft combined share;
- 32+ ft combined share;
- dominant-band composition;
- leaf-off score distribution;
- leaf-off observation-support coverage.

These are physical composition summaries, not habitat labels.

### Cross-boundary adjacency

Use neighboring valid 5 m cells that lie on opposite sides of the property boundary.

Report:

- valid cross-boundary pair count;
- mean and percentile absolute difference in leaf-off score;
- mean neutral LiDAR profile distance;
- dominant-band agreement rate;
- observation-support coverage.

The v1 metric is deliberately descriptive. It does not classify a pair as a corridor, edge, funnel, security-cover connection, or movement route.

### Structural-break preparation

The v1 artifact retains enough combined-grid information to support a later named edge/break product without re-downloading raw source data. At 5 m it stores the neutral LiDAR band shares as byte-scaled fractions plus uint16 return counts, along with the leaf-off score/support fields used for synthesis. The duplicate LiDAR JSON count arrays are intentionally omitted so the artifact remains inside the existing 10 MB private-storage object limit. The higher-resolution 2024 leaf-off score, confidence, spectral-support, and validity grids are retained because they add spatial information not present in the 5 m synthesis.

A thresholded "major structural break" distance is **not** frozen in this contract. It should be introduced only after its contrast definition and scale are specified and validated. Until then, use the continuous adjacency contrasts above.

## Operator field observations

Field observations remain separate from this product.

A water observation associated with a DEM-derived drainage trace may record:

- `observation_kind = surface_water_presence`;
- `observation_state = observed_present`;
- `persistence_status = unknown` or `intermittent_or_seasonal` when actually known;
- `timing_status = unknown`, `approximate`, or `dated`;
- optional notes;
- the observed geometry;
- optional linkage to the specific terrain materialization and flow-trace feature.

This creates the evidence chain:

`DEM-derived drainage hypothesis → operator field observation of water`

The field observation does not turn the derived trace into an authoritative mapped stream.

## Evidence boundary

Landscape Structure Context is `deterministic_derived` evidence.

It may later support explicitly named deer-relevant hypotheses, but v1 performs:

- no deer scoring;
- no movement prediction;
- no bedding prediction;
- no habitat-quality classification;
- no security-cover label;
- no route recommendation.

## Scale boundary

Fine structure intentionally stops at 500 m.

The 1,500 m and 3,000 m rings continue to use the existing coarse canopy, land-cover, terrain, agriculture, hydrology, access, and structure context unless a later deer-model validation shows that fine LiDAR/leaf-off structure beyond 500 m materially improves decision quality.
