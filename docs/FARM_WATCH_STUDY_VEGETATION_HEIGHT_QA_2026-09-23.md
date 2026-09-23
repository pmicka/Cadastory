# Farm Watch Study-Aligned Vegetation Height — Production QA

Status: **passed for FW-S21 neutral physical product**  
Date: 2026-09-23  
Validation property: `validation-property-01` / Flat Creek Test Property  
Study measurement: `FW-M02-vegetation-height`  
Production product: `study-aligned-vegetation-height-context-v2`  
Algorithm: `wiemers-first-return-minus-ground-local500m-v1`

## Production artifact under test

- materialization ID: `667f1cae-d1a6-43a6-a5e8-ee5aaa56c36c`
- identity SHA-256: `8d6a7e4d8fffe71994982983cedb937215e5db40ab2b02352c03215087bd87bb`
- artifact SHA-256: `68f11b6fc11d79a12e679f2c8f932fa51eccb73adba5fda61eeb452917ad144a`
- artifact size: 6,458,411 bytes
- property coverage: 100%
- local-500 m domain valid coverage: 99.9559%
- Phase 3 processing items: four COPC assets
- QA workflow run: GitHub Actions run `35925845150`, job `107400620816`
- QA source commit: `e3ad7081b9f3a02837fbb3b64367ed7f30dbe81d`

The QA runner rebuilt the production artifact from the same authoritative Phase 3 source lineage before profile inspection. The rebuilt artifact matched the persisted production artifact exactly:

- artifact SHA-256 match: **yes**
- artifact size match: **yes**
- sampled source coverage: **100%**

## Raw-point/profile QA method

The QA sampled:

- three representative property cells from each physical height class:
  - open: <= 0.25 m
  - low: > 0.25 m to 2 m
  - mid: > 2 m to 10 m
  - high: >= 15 m
- ten worst raw negative first-return-minus-ground residual cells retained by production QA.

Representative cells were restricted to cells with:

- height available;
- direct first-return support;
- no negative-clamp flag;
- local direct LAS Class 2 ground support;
- cell center inside the validation property.

For every sampled cell, QA independently interrogated the original COPC point data and calculated:

- exact 1.2 m-cell first-return points;
- exact-cell Class 2 ground points;
- Class 2 ground points within 10 m;
- a local ground-plane fit;
- first-return height above the fitted ground plane;
- direct cell-mean first-return minus direct cell-mean ground where available;
- first-return versus ground XY centroid separation.

This raw-profile calculation is not the production raster interpolation itself. It is an independent physical consistency check against source points.

## Representative-cell results

| Class | Production height range | Raw-profile mean AGL range | Absolute production-minus-raw mean difference | Ground-plane RMSE |
| --- | ---: | ---: | ---: | ---: |
| Open | 0.01–0.05 m | 0.089–0.112 m | 0.043–0.102 m | 0.090–0.147 m |
| Low | 0.54–1.91 m | 0.616–1.851 m | 0.034–0.076 m | 0.088–0.168 m |
| Mid | 2.77–9.20 m | 2.864–9.306 m | 0.031–0.106 m | 0.075–0.119 m |
| High | 18.43–22.48 m | 18.637–22.606 m | 0.126–0.224 m | 0.086–0.092 m |

All 12 representative cells preserved the intended physical ordering and magnitude. Direct cell-mean first-return-minus-ground values were also consistent with the persisted raster values.

The open-class raw point profiles sit slightly above the raster values by roughly 4–10 cm, which is compatible with the documented difference between the Farm Watch cell-mean/interpolated surface and the source study's TIN-derived surfaces. It does not alter the physical class or interpretation.

## Negative-residual tail

The production artifact contains 132,462 negative raw first-return-minus-ground residuals before zero clamping, but the distribution is strongly concentrated near zero:

- median negative magnitude: 0.0127 m;
- p90: 0.0583 m;
- 873 cells below -0.25 m;
- 88 cells below -0.50 m;
- 1 cell below -1.0 m.

The ten worst retained cells were raw-profiled separately.

Observed characteristics of those ten cells:

- all ten were **outside the validation property**, in the surrounding local-500 m domain;
- exact first-return support was sparse: 1–3 points per cell;
- local terrain was commonly steep/rough, with fitted slopes from about 17% to 121%;
- first-return and ground centroids were offset by roughly 0.44–1.04 m within the 1.2 m cell;
- local ground-plane RMSE ranged from about 0.22 m to 1.46 m;
- some independent point-level AGL profiles were positive while others remained negative, confirming that the tail is dominated by difficult sub-cell terrain/sampling geometry rather than a single uniform failure mode.

These cells are therefore **not accepted as valid physical 0 m vegetation measurements**.

The v2 support bitmask records the negative-clamp condition. For any study-aligned or scientific consumer:

> Cells with the `negative-raw-height-clamped-to-zero` support flag are QA-excluded/unavailable height observations and MUST NOT be interpreted as genuine zero-height vegetation.

This rule is part of the validation decision.

## Validation decision

FW-S21 passes production validation for the neutral physical vegetation-height product because:

1. the production artifact deterministically rebuilds to the exact persisted checksum and size;
2. source coverage is complete for the sampled domain;
3. packed-grid/schema validation and production storage validation passed;
4. negative residuals are quantified and retained in cell-level QA flags;
5. representative open/low/mid/high cells agree closely with independent raw COPC point profiles;
6. the rare large-negative tail was specifically inspected and is isolated as flagged interpolation/sampling anomalies rather than silently promoted to zero vegetation height;
7. the validation property itself has 100% valid product coverage.

## Remaining boundaries

This QA validates **FW-S21**, the neutral physical first-return-minus-ground vegetation-height product.

It does **not** by itself:

- promote FW-M02 to `derived_equivalent` in the deer relationship registry;
- unblock FW-D01;
- reproduce the original ArcMap TIN interpolation numerically;
- resolve the Phase 3 acquisition-time provenance discrepancy;
- establish operative temperature, forage index, woody canopy percent, or activity-period fidelity;
- establish deer use, bedding, habitat quality, concealment, movement, or hunting value.

Any future FW-M02 consumer must honor support flags and exclude negative-clamped cells from valid study-height observations.
