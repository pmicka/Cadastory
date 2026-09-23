# Farm Watch Structure Evidence Ledger

Status: current as of 2026-09-22
Validation property: `validation-property-01`

## Purpose

> Deer-specific biological interpretation is governed separately by `docs/FARM_WATCH_DEER_SCIENCE_EVIDENCE_LEDGER.md`. This structure ledger remains the source of truth for neutral LiDAR/imagery/terrain evidence and must not be used as a substitute for published deer-science support.

This document is the durable index for Farm Watch structural-science work involving LiDAR, leaf-off aerial imagery, and their cross-layer diagnostics.

Its primary purpose is to prevent repeated analysis from being proposed as new work.

Before adding another structural analysis, check this ledger and the cited implementation/artifact first. If a prior result is not durably preserved, that is a provenance/recovery problem, not permission to silently rerun or reinterpret the experiment.

## Status vocabulary

- **canonical-central** — current result is centrally materialized with dependency identity/provenance.
- **persisted-QA** — experimental/QA result has a durable artifact, but is not a canonical Farm Watch product.
- **implemented-QA** — method exists in the notebook and has been exercised historically, but the current audit did not locate a durable numeric result.
- **historical-session-only** — a prior session reported a result, but no authoritative current artifact was located.
- **protocol-ready** — experimental protocol exists, but completion/result evidence was not located.
- **superseded** — replaced by a more current central implementation/result.

## Current canonical products

| Product | Current identity | Status | Key facts |
| --- | --- | --- | --- |
| LiDAR source coverage | `kyfromabove-stac-coverage-plan-v1` | canonical-central | Phase 2 and Phase 3 parcel coverage plans are explicit and source-selected rather than “first STAC result wins.” |
| Phase 3 LiDAR physical structure | `phase3-copc-physical-v3-multiasset` | canonical-central | 5 m height-above-ground grid; 6,621 eligible cells; 496,417 normalized structure points; current artifact SHA `af8ee1d3ff4fcb09a7ee5c983edb1a9c8fbdd93754715337a0f2afab7d5759a4`. |
| Leaf-off woody-pattern context | `leaf_off_structure_v1_2_7m` | canonical-central, experimental_derived | 2019 and 2024 products, each 253×445 with 70,806 valid cells; current artifact SHA `7b8127da0a729d79b5a521cc4f27599334651a83db24f1036906771ffecfce75`. |
| Structural complementarity | `current-leaf-off-lidar-complementarity-v4` | canonical-central | 6,662 shared 5 m cells; current artifact SHA `01dc786d4f258bc1b5b78f43e935ff397f931293d298b9548da48ef1d600c074`. |
| Terrain form / reference permeability | `barrier-aware-phase3-dem-terrain-form-permeability-v1` | canonical-central | 10 m local terrain-form candidates + 30 m 1.5 km reference slope-friction; identity `a4d02fa0738ea005efd0456027b0940a66b1155f7cd1a6c24a1287312e1f102f`; artifact SHA `b69a778cb91aa0d87e92fedfe9213d07b72caadf551ba6dfb2b95f4b45af45ee`. |
| Spatial edge / patch context | `local500m-canopy-field-structure-pattern-v1` | canonical-central | 30 m canopy/field pattern + reused 5 m structural transitions; identity `9cdb6dd495a1e6e6de158e2686485b95ef94e83394b9121171f6455012f9ee4c`; artifact SHA `99edf000a5c5ad846b25be8d61c36b352ecb5fb25f30db1468499ea3ddc532e0`. |
| Horizontal visibility / obstruction | `barrier-aware-local500m-horizontal-visibility-v1` | canonical-central | Bounded 5 m physical ray summaries over the exact `local_500m` domain; consumes current central landscape structure and terrain-form artifacts; no deer semantics. Validation-property materialization identity `1c1c4375f4dc7b4aa905e1978ebcadf2dd1304ed480c0fac6b311650fba76c10`; artifact SHA `c2e2ac940def006d7232fe4be817211c92495f703a15e6f4f3bed3e8dc7818a0`. |

Current central materializations are stored in `farm_watch.property_materializations_v1`. The structural complementarity source signature binds to the exact current LiDAR and leaf-off artifact SHA-256 values.

## Experiment ledger

### FW-S01 — LiDAR source coverage / parcel source selection

**Question:** Which KyFromAbove point-cloud assets actually cover the parcel, and can point processing proceed without silently selecting an arbitrary STAC result?

**Method:** `kyfromabove_parcel_lidar_stac_coverage_audit_v2` / central `kyfromabove-stac-coverage-plan-v1`.

**Implementation:** `pmicka/notebook/public/projects/farm-watch/lidar-audit.js`; central source materialization in Cadastory.

**Result:** Phase 2 and Phase 3 each currently resolve to one parcel-covering COPC asset with sampled parcel coverage of 100%.

**Boundary:** Source-selection evidence only; not a vegetation interpretation.

**Status:** canonical-central.

---

### FW-S02 — LiDAR raw point-content audit and source-specific ground normalization

**Question:** Can each LiDAR phase support a defensible height-above-ground normalization without assuming classification semantics beyond what is observed?

**Methods:** raw point-content audit; `source_specific_class2_ground_grid_idw_v1`; parcel-clipped COPC historical QA product.

**Implementation:** `lidar-point-audit.js`.

**Result durability:** The current Phase 3 physical product is central and reports 100% ground-supported parcel coverage. Historical Phase 2/Phase 3 QA numeric outputs remain browser-QA and are not represented by a current canonical artifact.

**Boundary:** Ground normalization only; no brush/midstory/canopy/species/habitat labels.

**Status:** canonical-central for current Phase 3 physical structure; implemented-QA for historical cross-phase diagnostics.

---

### FW-S03 — Vertical height distributions and candidate thresholds

**Question:** What does the normalized vertical return distribution look like before assigning any ecological semantics?

**Methods:** height quantiles, 1 ft histogram, threshold shares, candidate histogram valleys.

**Implementation:** `summarizeVerticalHeights()` in `lidar-point-audit.js`.

**Result durability:** Method and historical run path remain available; the audit did not locate a durable standalone numeric result artifact.

**Boundary:** Descriptive diagnostics only. Histogram valleys and thresholds are not vegetation classes.

**Status:** implemented-QA.

---

### FW-S04 — Neutral LiDAR strata and threshold sensitivity

**Question:** Are fixed neutral height bands spatially stable enough to use as a structural representation, and how sensitive are results to nearby band schemes?

**Methods:** neutral height-band grids, `neutral_height_band_surface_sensitivity_v1`, `common_10m_anchor_band_share_comparison_v1`.

**Implementation:** `lidar-point-audit.js`.

**Result durability:** Historical browser QA exists in code/history; no durable standalone numeric result located in this audit.

**Boundary:** Height strata remain neutral physical bands.

**Status:** implemented-QA.

---

### FW-S05 — Historical/cross-phase LiDAR temporal structure

**Question:** How do neutral height-band composition and presence patterns differ/persist between Phase 2 and Phase 3 on a common grid?

**Methods:** `common_10m_neutral_strata_temporal_structure_v1`; dominant-band transition matrix; composition overlap; ordinal-band deltas; spatial shift coherence; presence persistence.

**Implementation:** `temporalStructureAudit()` in `lidar-point-audit.js`.

**Result durability:** Browser/Internal-QA only; no current canonical result artifact located.

**Boundary:** Differences are not automatically vegetation growth, succession, habitat change, or hunting significance.

**Status:** implemented-QA.

---

### FW-S06 — Leaf-off woody-pattern estimator construction

**Question:** Can leaf-off aerial imagery provide a stable horizontal woody-pattern observation distinct from LiDAR vertical structure?

**Method:** luminance local standard deviation + gradient magnitude, 45/55 weighting, slope surface correction, independent within-acquisition robust normalization, false-color support/confidence.

**Scale work:** 5/7/9 m neighborhood diagnostic was implemented; 7 m was selected and frozen as the working estimator on 2026-09-18.

**Sources:** 2024 Phase 3 RGB/IR plus DEM; independent 2019 Phase 2 RGB/IR observation.

**Implementation:** `leaf-off-structure.js`; central contract `farm-watch-leaf-off-contract.ts`.

**Result:** Current central artifact contains both supported acquisitions. 2024 has 89.64% high-observation-support cells; 2019 has 94.00%.

**Boundary:** Horizontal woody-pattern context only. Not understory density, stem density, regeneration, species, habitat quality, management condition, bedding, mast, or animal use.

**Status:** canonical-central, experimental_derived.

---

### FW-S07 — Independent 2019↔2024 leaf-off transfer

**Question:** Does the independently normalized spatial ranking recur across two leaf-off acquisitions?

**Method:** `independent_relative_rank_transfer_v1`.

**Current central result:** 70,806 overlapping cells; Spearman rank correlation 0.1037; exact-quintile agreement 22.93%; within-one-quintile 56.11%; sparse-20% Dice 22.87%; dense-20% Dice 27.95%.

**Interpretation:** Weak but non-zero rank transfer. Independently normalized products are not subtracted, and disagreement is not classified as vegetation change.

**Status:** canonical-central as a diagnostic embedded in the leaf-off artifact.

---

### FW-S08 — Leaf-off registration sensitivity

**Question:** Could apparent cross-year disagreement be explained by small translational registration error?

**Method:** `registration_shift_sensitivity_v1`; translation sweep over ±10 m, tracking Spearman and sparse/dense overlap.

**Implementation:** `sweepRegistrationSensitivity()` in `leaf-off-structure.js`.

**Result durability:** Diagnostic path exists and was exercised historically; exact output was not found in a durable artifact during this consolidation.

**Boundary:** Diagnostic translation sweep only; no image is moved, corrected, or treated as registered by the result.

**Status:** implemented-QA.

---

### FW-S09 — Leaf-off transfer component decomposition

**Question:** Which stages of the leaf-off estimator drive cross-year agreement/disagreement?

**Method:** `leaf_off_transfer_component_decomposition_v1`; compares luminance standard deviation, gradient magnitude, combined pre-slope texture, terrain-adjusted signal, and final relative score.

**Implementation:** `compareTransferComponents()` in `leaf-off-structure.js`.

**Result durability:** Method exists and was exercised historically; exact numeric output not durably located.

**Boundary:** Diagnostic decomposition; does not retune weights or classify disagreement as change.

**Status:** implemented-QA.

---

### FW-S10 — Leaf-off aggregation/spatial-support transfer

**Question:** Does broader spatial aggregation improve transfer between acquisitions?

**Method:** `leaf_off_transfer_spatial_support_v1`; block aggregation at 10, 15, and 20 m while leaving the canonical 7 m estimator unchanged.

**Implementation:** `compareAggregationScales()` in `leaf-off-structure.js`.

**Result durability:** Method exists and was exercised historically; exact numeric output not durably located.

**Boundary:** Diagnostic aggregation only; no estimator retuning.

**Status:** implemented-QA.

---

### FW-S11 — Frozen aerial × independent LiDAR Batch 5 comparison

**Question:** After both estimators are frozen independently, how does leaf-off horizontal structure relate to neutral LiDAR vertical structure?

**Method:** `frozen_leaf_off_vs_independent_lidar_strata_v1`.

**Implementation:** `leaf-off-lidar-audit.js`; introduced in the 2026-09-19 Batch 5 work.

**Boundary:** Does not retune either estimator, infer species, label habitat, or turn association into causation. The imagery and LiDAR observations are non-contemporaneous.

**Status:** implemented-QA; current-state portions were later promoted into FW-S12–FW-S15.

---

### FW-S12 — Current dominant-band complementarity

**Question:** How much leaf-off variation exists within the same LiDAR dominant-height regime, and how does leaf-off vary with 4–32 ft share where 32+ ft returns are present?

**Original QA method:** `current_leaf_off_lidar_complementarity_v1`.

**Current central result:** 6,662 shared 5 m cells. Dominant LiDAR band explains 0.6569% of leaf-off variance; 99.3431% remains within dominant-band groups. Among 5,945 cells with ≥10% 32+ ft returns, 4–32 ft share vs leaf-off score Spearman rho = +0.0889.

**Interpretation:** The dominant-band rendering is a lossy summary and the two layers are complementary. This does not identify the residual dimension as understory or any ecological class.

**Status:** canonical-central in structure-complementarity v4.

---

### FW-S13 — Full LiDAR-profile explanatory model

**Question:** Can the full neutral LiDAR vertical profile explain the frozen leaf-off score better than dominant-band classification?

**Method:** `blocked_5fold_vertical_profile_ridge_v1`; five east-west held-out spatial folds; predictors are 4–16, 16–32, 32–64, 64+ ft shares with 0–4 ft as reference, plus vertical entropy and profile spread.

**Current central result:** 6,662 out-of-fold predictions; cross-validated R² = 0.01993; predicted-vs-observed r = 0.14505.

**Interpretation:** The tested linear vertical-profile representation explains about 2.0% of held-out leaf-off variance. This is model performance, not the theoretical maximum information contained in LiDAR.

**Status:** canonical-central in structure-complementarity v4.

**Reconciliation note:** A prior chat/session reported an older browser-QA value near R² = 0.057. No durable artifact matching that number was located in this audit. Do not use or average the 0.057 result as canonical until its exact source/grid/provenance is recovered.

---

### FW-S14 — Residual attribution, spatial patches, and matched controls

**Question:** What remains after the LiDAR profile model, is it associated with aerial observation/support variables, and is the residual spatially organized?

**Methods:** `leaf_off_profile_residual_attribution_v1`; correlations against spectral support, confidence, slope, illumination, mean luminance, luminance standard deviation, and gradient; standardized residual classes; eight-neighbor positive-residual patches; matched near-zero controls with similar LiDAR profiles.

**Implementation:** `buildResidualAttribution()`, `residualSpatialProduct()`, matched-control helpers in `leaf-off-lidar-audit.js`.

**Important distinction:** Luminance standard deviation and gradient are direct components of the leaf-off score, not independent validation signals. Spectral support/confidence are observation/support context.

**What was *not* found:** No existing model in the current repo conditions these residuals jointly against canopy + terrain position + SSURGO + hydrology/wetlands. Physical/landscape context exists elsewhere, but a residual-environmental-covariate model was not located.

**Status:** implemented-QA; residual spatial core later promoted and strengthened in FW-S15.

---

### FW-S15 — Model-adequacy stress test and residual spatial null

**Question:** Is the leaf-off signal readily recoverable by several bounded LiDAR-only profile models, and does best-model residual connectivity exceed local-structure-preserving null rearrangements?

**Models, same five held-out east-west folds:**
- linear ridge: R² = 0.01993;
- fixed quadratic/interactions ridge: R² = 0.02666;
- deterministic shallow CART: R² = 0.01144.

Best tested method: quadratic/interactions ridge. About 97.3% of held-out mean-baseline variance remains uncaptured by that tested model.

**Residual spatial result:** 655 confidence/spectral-support-gated cells; upper-tail residual selection = 131 cells; 77.10% of selected cells occur in multi-cell patches; 33 multi-cell patches; largest patch = 10 cells / 250 m².

**Conditional block-permutation null:** 99 deterministic permutations at 15, 20, and 30 m tile scales. Observed multi-cell fraction = 77.10%; null means = 57.01%, 64.98%, and 67.33%; exceedance p = 0.01 at all three scales. Largest-patch exceedance p = 0.02, 0.01, and 0.02 respectively.

**Boundary:** Bounded model stress test, not exhaustive LiDAR modeling. Tile null preserves within-tile selected-cell structure and is not a universal test of spatial randomness or evidence of a biological process.

**Status:** canonical-central in structure-complementarity v4.

---

### FW-S16 — Blind matched-pair morphology review, first follow-up

**Question:** With LiDAR profile held closely matched, are high-positive residual locations visually/morphologically distinguishable from near-zero controls without revealing which side is which?

**Design:** 24 deterministic A/B matched pairs; high-positive residual target vs matched near-zero control; LiDAR-share RMSE matching; morphology coding frozen before reveal.

**Persisted evidence located:** `farm-watch-blind-morphology-reveal-v1.json` (File Library, created 2026-09-19) contains all 24 role assignments and post-reveal deltas. It explicitly warns that the reveal is only for post-annotation attribution.

**What is *not* durably located:** The actual frozen morphology annotation labels/notes were not found in the repo or File Library during this consolidation. Therefore the reveal key alone must not be treated as a completed morphology result.

**Status:** persisted-QA for reveal metadata; morphology-result durability unresolved.

---

### FW-S17 — Strict second-round blind morphology sample

**Question:** Can the blind morphology comparison be repeated on a stricter, non-overlapping holdout with tighter LiDAR matching and balanced residual severity?

**Method:** `blind_morphology_matched_pair_sample_v3_balanced_global`.

**Protocol:** 12 pairs balanced 4/4/4 across positive-residual quartiles 2–4; excludes six exploratory pairs plus every target/control from the revealed 24-pair first follow-up; globally unique controls; |control residual| ≤ 0.50 sigma; LiDAR-share RMSE ≤ 0.06; target-minus-control residual ≥ 0.05; target-to-target spacing ≥ 2 grid cells; deterministic blinded A/B role assignment.

**Implementation:** `buildExpandedBlindReviewSample()` in `leaf-off-lidar-audit.js`. Supporting diagnostics include global unique-control matching capacity and control residual-band sweeps.

**Completion evidence:** No second-round reveal/annotation artifact was located during this consolidation.

**Status:** protocol-ready. Do not describe the second-round morphology result as completed unless its frozen annotations/reveal artifact are recovered.

### FW-S18 — Barrier-aware local-500 m structural continuity

**Question:** Does fine structural evidence on the selected property continue into the immediate surrounding landscape, transition at the ownership boundary, or meet a larger structural contrast?

**Method:** Deployed `landscape-structure-context-v1` product over the exact barrier-aware `local_500m` domain. Reuses the frozen Phase 3 LiDAR physical method from FW-S02/FW-S04 and the frozen 2024 leaf-off estimator from FW-S06 without retuning. LiDAR source coverage is resolved against the full local domain rather than reusing the parcel source plan. LiDAR and leaf-off evidence are synthesized on a common 5 m grid with property/domain masks and descriptive cross-boundary adjacency contrasts.

**New uncertainty resolved:** Existing canonical products stop at the parcel boundary and therefore cannot distinguish a real structural termination from an ownership-boundary processing artifact. This product extends spatial support only; it does not repeat the prior complementarity experiments.

**Production validation — 2026-09-21:**
- Current barrier-aware domain identity: `bd69c24e98c485a9320c07db036548c4b065a2c381e77f2ab5cd73fc73e9ae5f`.
- Phase 3 source plan required four COPC assets: `N071E278_LAS_Phase3.copc`, `N071E279_LAS_Phase3.copc`, `N072E278_LAS_Phase3.copc`, and `N072E279_LAS_Phase3.copc`.
- Sampled Phase 3 coverage of the barrier-aware local domain: 100%.
- Common 5 m grid: 277 × 336 cells; 68,472 valid domain cells, including 6,941 property cells and 61,531 surrounding local-ring cells.
- Neutral LiDAR composition: property 4–32 ft share 0.34097 and 32+ ft share 0.64145; local ring 4–32 ft share 0.38085 and 32+ ft share 0.59096.
- Leaf-off score median: property 0.41961; local ring 0.45490. These are within-product relative scores, not habitat values.
- Cross-boundary adjacency: 1,114 boundary pairs; 1,062 with valid LiDAR on both sides. Median absolute leaf-off score difference 0.25882; median LiDAR profile total-variation distance 0.24902; dominant-band agreement 59.23%.
- Central materialization identity: `403f75926234f88e5ebc69e1cec7c0af3fbeac5b1ca23468a7d1cbc3464c5b69`.
- Artifact SHA-256: `8dee53eaf17e725e467806cbfc7a0ca6c5106f87d2f117123c36703ca5a2fccf`; stored size 6,261,256 bytes. Storage metadata size matches the materialization record.
- Artifact domain identity matches the current landscape-domain identity exactly.

**Implementation contract:** `supabase/functions/_shared/farm-watch-landscape-structure-contract.ts`; `docs/FARM_WATCH_LANDSCAPE_STRUCTURE_CONTEXT_V1.md`.

**Boundary:** No security-cover label, corridor/funnel inference, deer movement, bedding, habitat quality, or hunting recommendation. The 2024 leaf-off surface is normalized within the local domain and must not replace the canonical parcel-normalized artifact. Cross-boundary differences are descriptive physical contrasts only.

**Status:** centrally materialized and checksum-addressed. The first production artifact is available and current for `validation-property-01`.

---


### FW-S21 — Study-aligned first-return minus ground vegetation height

**Question:** Can Farm Watch reproduce the neutral LiDAR vegetation-height variable used by FW-D01/Wiemers et al. without substituting the existing 5 m return-share strata?

**Relationship to prior work:** Extends FW-S02/FW-S04 and the local-domain source handling established by FW-S18. It reuses the canonical KyFromAbove Phase 3 source lineage and the exact barrier-aware `local_500m` domain, but resolves a new measurement-fidelity requirement: FW-D01 used a first-return elevation surface minus a bare-ground elevation surface at 1.2 m support.

**Published measurement:** Wiemers et al. (2014) created separate bare-ground and first-return TINs, rasterized each to 1.2 m DEMs, and calculated vegetation height from their elevation difference.

**Farm Watch method:** `study-aligned-vegetation-height-context-v1`, algorithm `wiemers-first-return-minus-ground-local500m-v1`. Uses LAS `ReturnNumber = 1` for the first-return surface and Classification 2 for ground, excludes withheld/overlap/noise-class points, aggregates at 1.2 m, fills only within bounded local support, and stores vegetation height as uint16 centimetres plus a support byte.

**Interpolation boundary:** The source paper used ArcMap TIN interpolation. Farm Watch uses cell-mean surfaces with deterministic inverse-distance filling. The physical variable and 1.2 m support are aligned, but the original interpolation implementation is not claimed to be numerically identical.

**Boundary:** Neutral vegetation height only. No forage, concealment, canopy-percent, browse, habitat, bedding, deer use, movement, or hunting semantics.

**Implementation contract:** `supabase/functions/_shared/farm-watch-study-vegetation-height-contract.ts`; `docs/FARM_WATCH_STUDY_VEGETATION_HEIGHT_V1.md`.

**Status:** implementation complete in source; production materialization/validation pending.

---

## Provenance discrepancies that must remain explicit

### LiDAR acquisition-time basis

The older browser QA path contains point-time logic and a historical note using a 2025-03-09 point-time inference under a documented COPC/header conflict.

The current central Phase 3 physical artifact intentionally uses **central STAC item datetime metadata**, currently `2025-12-13T00:00:00Z`, as `acquisition_utc_range` / display provenance.

These are different provenance interpretations. The structural computations do not depend on the displayed date, but any temporal language does.

**Status:** unresolved provenance reconciliation. Do not silently substitute one date for the other.

### Historical R² ≈ 0.057

A prior session reported a browser-QA full-profile result around R² ≈ 0.057. No durable artifact matching that value was found here, while the current central reproduction yields linear R² = 0.01993 and best tested bounded-model R² = 0.02666.

**Status:** historical-session-only. Recover the exact old artifact/source state before drawing conclusions from the discrepancy.

## What is already answered well enough not to repeat by default

1. **Is the 7 m leaf-off product merely the LiDAR dominant-height rendering in disguise?** No under the tested current representation; dominant band explains only ~0.7% of leaf-off variance.
2. **Does using the full tested LiDAR vertical profile remove the complementarity?** No; linear held-out R² is ~0.020 and the best bounded nonlinear tested model reaches ~0.027.
3. **Are high-positive best-model residuals only isolated single cells?** No under the current gated upper-tail definition; 77.1% occur in multi-cell patches.
4. **Does that connectivity exceed the specific 15/20/30 m local-structure-preserving tile nulls?** Yes for the current validation parcel and v4 artifact.
5. **Did we already investigate residual morphology with LiDAR-matched controls?** Yes. Exploratory matched controls, a 24-pair blinded follow-up/reveal, and a stricter second-round protocol all exist. The missing piece is durable annotation/result preservation, not invention of another generic morphology experiment.
6. **Did we already examine cross-year leaf-off transfer, registration sensitivity, estimator-component decomposition, and broader spatial support?** Yes as QA. Only the basic independent rank-transfer result is currently central; the other numeric outputs are not durably preserved.

## Actually unresolved / high-value follow-ups

These are the current gaps after consolidation:

1. **Recover or formally retire the missing morphology annotations.** Locate the frozen first-round morphology labels/notes and any strict second-round review output. If they cannot be recovered, record that loss explicitly before deciding whether a rerun is scientifically justified.
2. **Reconcile LiDAR temporal provenance.** Resolve STAC 2025-12-13 versus the older point-time/header interpretation before using LiDAR timing in any temporal/change claim.
3. **Recover the historical ~0.057 R² artifact or retire that number.** Determine whether it came from a different grid, source selection, date interpretation, product version, or transient browser state.
4. **Decide whether non-central QA results need preservation.** Registration, decomposition, aggregation, and historical LiDAR temporal outputs are method-complete but numerically fragile because their outputs were not centrally materialized.
5. **Environmental conditioning is genuinely separate work.** No current code was found that jointly models best-model residuals against canopy, terrain position, SSURGO, and hydrology/wetland context. If pursued, it should be framed as a new named experiment and should reuse the frozen central v4 residual definition rather than recomputing the earlier pipeline.

## Source map

Notebook:
- `public/projects/farm-watch/lidar-audit.js`
- `public/projects/farm-watch/lidar-point-audit.js`
- `public/projects/farm-watch/leaf-off-structure.js`
- `public/projects/farm-watch/leaf-off-lidar-audit.js`
- `public/projects/farm-watch/structure-synthesis.js`

Cadastory:
- `supabase/functions/_shared/farm-watch-lidar-physical-contract.ts`
- `supabase/functions/_shared/farm-watch-leaf-off-contract.ts`
- `supabase/functions/_shared/farm-watch-structure-synthesis-contract.ts`
- `scripts/farm-watch-lidar-physical-materialize.ts`
- `scripts/farm-watch-leaf-off-materialize.ts`
- `supabase/functions/farm-watch-structure-synthesis-worker/index.ts`
- `docs/FARM_WATCH_LANDSCAPE_CONTEXT_V1.md`
- `docs/FARM_WATCH_LANDSCAPE_PHYSICAL_CONTEXT_V1.md`
- `docs/FARM_WATCH_LANDSCAPE_STRUCTURE_CONTEXT_V1.md`
- `supabase/functions/_shared/farm-watch-landscape-structure-contract.ts`

External preserved artifact located during consolidation:
- `farm-watch-blind-morphology-reveal-v1.json` — 24-pair first-follow-up reveal metadata only; morphology labels were not located.

## Rule for future Farm Watch structural work

A proposed experiment must identify which ledger item it extends and state exactly what new uncertainty it resolves.

“Correlate leaf-off with LiDAR,” “look at residual patches,” “compare matched controls,” “test whether the layers are complementary,” and “see whether broader spatial support helps” are not new experiments without a materially different, pre-specified question.


---

### FW-S19 — Neutral terrain and spatial pattern primitives

**Question:** Can Farm Watch materialize reusable terrain-form, reference terrain-friction, canopy/field-edge, and fine structural patch/transition geometry without introducing deer-use semantics or repeating raw structural source processing?

**Relationship to prior work:** Extends FW-S18. FW-S18 established the canonical barrier-aware local-500 m structural grid and property-boundary continuity statistics. FW-S19 adds neutral intra-domain spatial derivatives and an independent DEM-derived terrain-form/reference-friction family. It does not repeat the LiDAR or leaf-off source estimators.

**Products:**
- `terrain-form-permeability-v1`: 10 m local terrain-form candidate grid over `local_500m`, plus a 30 m reference slope-friction grid over `landscape_1500m`.
- `spatial-edge-patch-context-v1`: 30 m NLCD TCC patch/edge geometry, mapped field-edge proximity from the current resource-edge product, and 5 m structure patch/transition metrics derived from the existing FW-S18 artifact.

**Terrain-form method:** Explicit fixed-threshold geometry using metric slope, 30 m and 90 m topographic-position indices, 90 m neighborhood relief, orthogonal second-difference sign, and local slope-break contrast. Labels are suffixed `_candidate` and remain geometric candidates rather than field-surveyed landforms.

**Permeability method:** `reference-slope-only-v1`, an explicitly parameterized dimensionless friction scenario. It is not calibrated to deer or another species. Configured hard barriers are inherited from the current barrier-aware domain; other hydrology is not silently assigned a biological cost.

**Spatial-pattern method:** Fixed 2025 NLCD TCC bins (0–20%, 21–60%, 61–100%) with 8-neighbor patch identities and edge metrics; mapped-field membership/edge distance from current resource-edge geometry; 8-neighbor leaf-off absolute-difference and LiDAR neutral-profile total-variation transitions; leaf-score-quartile and LiDAR-dominant-band patches.

**Evidence reuse:** The 5 m structural component consumes the exact current `landscape-structure-context` artifact by identity and SHA-256. It performs no COPC or aerial-imagery source reprocessing.

**Boundary:** No deer score, travel route, corridor, funnel, bedding, security-cover, habitat-quality, forage-quality, stand-location, or hunting recommendation is computed. All outputs remain deterministic physical/measurement-space derivatives.

**Production validation — 2026-09-21:**
- `terrain-form-permeability`: materialization identity `a4d02fa0738ea005efd0456027b0940a66b1155f7cd1a6c24a1287312e1f102f`; artifact SHA-256 `b69a778cb91aa0d87e92fedfe9213d07b72caadf551ba6dfb2b95f4b45af45ee`; 632,109 bytes; 17,136 local-domain cells and 6,550 1.5 km-domain cells.
- `spatial-edge-patch-context`: materialization identity `9cdb6dd495a1e6e6de158e2686485b95ef94e83394b9121171f6455012f9ee4c`; artifact SHA-256 `99edf000a5c5ad846b25be8d61c36b352ecb5fb25f30db1468499ea3ddc532e0`; 1,406,006 bytes.
- The spatial product is checksum-bound to current resource-edge identity `2a57436d1c289f0496972cfe020071db2c8e7e1fc82bacb22a060b02d06e9051` and FW-S18 artifact SHA `8dee53eaf17e725e467806cbfc7a0ca6c5106f87d2f117123c36703ca5a2fccf`.
- Storage metadata sizes match materialization-record sizes exactly. Both builds completed on attempt 1 with no persisted error, and the production edge read path revalidated each artifact after upload.

**Status:** canonical-central for `validation-property-01`.

### FW-S20 — Neutral horizontal visibility / obstruction

**Question:** Can physical horizontal line-of-sight and obstruction geometry be represented on the current barrier-aware structural domain without reopening raw COPC/LAZ processing or assigning deer-use semantics?

**Relationship to prior work:** Extends FW-S18's canonical local-500 m / 5 m structural continuity grid and FW-S19's neutral terrain and spatial-pattern primitives. It resolves a new uncertainty: existing vertical-profile, edge/patch, and terrain-form products do not represent horizontal ray occlusion. This is not another LiDAR-versus-leaf-off experiment.

**Contract:** `horizontal-visibility-context-v1`, algorithm `barrier-aware-local500m-horizontal-visibility-v1`, source-controlled in `supabase/functions/_shared/farm-watch-horizontal-visibility-contract.ts`. The source signature binds the current landscape-domain identity, landscape-structure identity and artifact SHA, terrain-form identity and artifact SHA, grid definitions, three observer/target height scenarios (1.5 m, 3 m, 6 m), 16 north-origin clockwise azimuths, 5 m ray step, 10/25/50/100 m bands, maximum 100 m, support threshold, complete-four-cell terrain resampling, and unsupported-not-open edge handling.

**Inputs and method:** The central materialization consumes the current private `landscape-structure-context-v1` compact 5 m neutral LiDAR band-share grid and current private `terrain-form-permeability-v1` local 10 m elevation grid. Terrain rays use complete-support bilinear interpolation. Structural obstruction is the maximum neutral LiDAR return-share support at the ray height along each sampled path; this is an explicit physical support proxy, not exact continuous vegetation volume or within-cell horizontal point geometry. Terrain-only and combined obstruction, angular openness, visible-distance summaries, valid-direction counts, and unsupported-direction counts remain separate continuous/diagnostic fields.

**Boundary:** Heights are generic physical scenarios, not deer eye/body heights. Unsupported directions are abstentions, never open directions. The product produces no security-cover, concealment, bedding, escape-cover, travel-cover, habitat-quality, deer-visibility, deer-use, movement, hunting-quality, stand-suitability, or score output.

**Validation:** Synthetic flat/open, added-obstruction monotonicity, directional/ray, packed-artifact, observer-height, distance-band, and unsupported-support checks are source-controlled in `supabase/functions/_shared/farm-watch-horizontal-visibility.test.ts`. The protected GitHub worker was merged through PRs #223, #225, #226, #228, #229, #230, #231, and #232; the materialization Edge Function is active with custom in-function authentication and `verify_jwt:false`.

**Production validation — 2026-09-22 (`validation-property-01`):** Materialization `13ae60ab-3972-4ad3-9d60-35504367cc8f` is `available`, identity `1c1c4375f4dc7b4aa905e1978ebcadf2dd1304ed480c0fac6b311650fba76c10`, artifact SHA `c2e2ac940def006d7232fe4be817211c92495f703a15e6f4f3bed3e8dc7818a0`, stored size `1,267,296` bytes, input signature `860dafcd3fc40cd47935f15728ce38bdbec74b2d25c8475da4b017a7ec07738c`, and source-signature SHA `8d13cbc54c2151f0579b7e9530fdfcb077b6e6ea9b01f26860740b7ee5b1f60e`. The private `farm-watch-derived` Storage metadata reports the same size and artifact SHA-addressed path; storage encoding is deterministic `gzip-v1` with no raw LiDAR/COPC persistence.

The artifact covers 68,472 exact local-domain cells, including 6,941 property cells and 58,669 structurally valid cells, on the 5 m output grid. It contains three generic equal observer/target height scenarios (1.5 m, 3 m, 6 m), 16 directions, and 10/25/50/100 m bands. The physical summary varies by scenario: combined obstruction fraction at 10/25/50/100 m is approximately 0.960/0.994/0.998/0.999 at 1.5 m, 0.960/0.990/0.996/0.998 at 3 m, and 0.794/0.914/0.962/0.986 at 6 m; terrain-only median visible distance at 100 m is 100 m while combined median is 5 m. Valid and unsupported direction totals are retained per band, and unsupported support is not treated as open.

**Status:** canonical-central for `validation-property-01`; deterministic physical QA passed. No deer-use inference or score was produced.
