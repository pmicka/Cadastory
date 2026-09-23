# Farm Watch Deer Measurement Resolution v1

Status: source-controlled study-fidelity disposition contract  
Version: 2026-09-23  
Normative upstream science: `docs/FARM_WATCH_DEER_SCIENCE_EVIDENCE_LEDGER.md`  
Machine contract: `supabase/functions/_shared/farm-watch-deer-measurement-resolution.ts`

## Purpose

The deer relationship registry intentionally blocks a study relationship when Farm Watch does not yet represent a required source-study measurement with sufficient fidelity.

This document resolves every measurement that was blocked after the 2026-09-23 study-fidelity audit into exactly one development disposition:

1. **reproduce** — Farm Watch can represent substantially the same semantic variable from authoritative geometry/state, deterministic derivation, or explicit operator/scenario input;
2. **calibrated proxy** — a map-wide derived estimate is scientifically plausible, but promotion requires calibration/validation against the source-study measurement protocol;
3. **remain unavailable** — a weak automated substitute would materially change the meaning of the source variable, so the deer relationship must remain blocked unless the actual intensive measurement is intentionally collected or a new independent evidence relationship is added.

A resolution decision is about **input measurement fidelity**, not biological transferability. Reproducing a study covariate does not authorize its published coefficient, effect magnitude, direction in a different population, or a deer-management recommendation.

## Portfolio

The current blocked set contains 36 required study measurements:

- **21 reproduce**
- **9 calibrated proxy**
- **6 remain unavailable**

Resolved since this contract was created:

- **FW-M02 — Wiemers vegetation height:** production-validated `study-aligned-vegetation-height-context-v2`; promoted to `derived_equivalent` on 2026-09-23.

CI requires every currently blocked measurement to have one and only one disposition.

## Reproduce

| ID | Source measurement | Resolution | Priority | Boundary |
| --- | --- | --- | --- | --- |
| FW-M08 | Snow depth / winter severity | Build physical snow/winter-severity context from authoritative snow depth and temperature; preserve the published Minnesota WSI only as source-defined context | P2 | No Kentucky biological threshold is implied |
| FW-M15 | Hunsaker male age | Expand explicit biological state to preserve yearling, 2-year-old, and 3+ male categories | P0 | Never infer exact age from generic adult status |
| FW-M19 | Current corn identity | Accept current-year field-bound identity from explicit observation or another validated/rights-permitted source | P0 | Stale CDL and regional crop progress cannot satisfy it |
| FW-M20 | Corn stage / harvest | Represent explicit field-level tasseling/silking or harvested state; direct/accepted observation first | P0 | Raw HLS trajectory alone cannot promote crop stage |
| FW-M24 | Building/development density | Derive from validated building-footprint geometry at study scale | P1 | Source completeness and vintage remain explicit |
| FW-M25 | Dated stand hunt | Record actual stand-specific hunt sessions with start/end time | P0 | Hunting season or stand presence is not a hunt event |
| FW-M28 | Daily hunter activity | Derive hunter use/intensity from known sessions and access activity | P0 | Off-property or unlogged activity remains unknown |
| FW-M29 | Food opportunity in adult-male hunting study | Bind to explicit food-plot / managed-food feature geometry and current management state | P1 | Generic vegetation greenness is not the study resource |
| FW-M31 | Frequent hunting risk | Derive event frequency / hunter-hours over explicit windows | P0 | Stand presence does not imply hunting frequency |
| FW-M32 | Forage-rich risky areas | Bind to explicit mapped food plots / study-relevant cover types | P1 | Does not claim measured nutrient abundance |
| FW-M33 | Low hunting pressure | Represent quantitative hunter effort density and compare with source context | P0 | Do not invent a universal low/high threshold |
| FW-M35 | Forest landscape context | Derive forest availability/configuration at the source study scales | P1 | Current local 500 m edge product alone is insufficient |
| FW-M36 | Road landscape context | Derive road geometry/proximity/density from validated transportation geometry | P1 | Neutral geometry receives no universal deer sign |
| FW-M39 | D16 study scales | Reproduce fixed 1 km² and 9 km² source windows exactly | P2 | Source hunting-unit scale remains study-administrative context unless a comparable unit is justified |
| FW-M43 | Intact deciduous forest | Derive forest type and intact/fragmented landscape state | P2 | Does not make the rest of FW-D17 available |
| FW-M45 | Extreme hurricane event | Represent explicit authoritative tropical-cyclone/extreme-event footprint and timing | P2 | Must not activate for routine rain/wind |
| FW-M47 | Forest refuge type | Derive pine/hardwood/swamp/marsh/shrub physical habitat classes | P2 | Covariate reproduction does not transfer the Florida effect |
| FW-M48 | Usable water source | Represent current stock-pond/trough availability by managed-source inventory or dated observation | P1 | Hydrography/gauge context cannot prove usable source presence |
| FW-M51 | Maternal age category | Preserve explicit fawn/yearling/adult maternal-age scenarios | P1 | Do not transfer Illinois conception dates |
| FW-M54 | Female parturition phase | Preserve explicit pre-parturition / parturition / post-parturition scenarios | P1 | Unknown state remains unknown |
| FW-M56 | Agriculture along potential dispersal paths | Reproduce source-style simulated potential paths and agricultural exposure along them | P2 | Simple landscape agriculture percentage cannot substitute |

### Resolved: FW-M02 vegetation height

Wiemers et al. derived vegetation height from LiDAR first-return and bare-ground elevation surfaces. Farm Watch implemented and production-validated the same physical variable family at 1.2 m support as `study-aligned-vegetation-height-context-v2`. Raw COPC profile QA passed on Flat Creek, and negative-clamped cells are explicitly excluded from scientific height use. FW-M02 is therefore no longer part of this blocked-measurement queue.

### Why activity/hunting records are reproducible

Sullivan et al. and later hunting-risk studies depend on observed or recorded human activity. On a property controlled by the operator, known stand sessions, access events, and hunter-hours are ordinary factual event data. Farm Watch can represent those events without inferring deer response. Unknown neighboring activity must remain unknown.

## Calibrated proxy

| ID | Source measurement | Proposed proxy | Priority | Calibration requirement |
| --- | --- | --- | --- | --- |
| FW-M01 | Black-globe operative temperature at 0.5 m | Physical operative-temperature model using air temperature, wind, radiation, terrain/canopy context | P1 | Black-globe logger comparison across sun/shade and vegetation classes |
| FW-M04 | Woody canopy line-intercept percent | Remote woody-canopy percent from high-resolution imagery/TCC | P1 | Compare against line-intercept measurements |
| FW-M05 | Movement-defined activity periods | Local deer-activity-period proxy from independent detections | P2 | Estimate/validate local diel activity curves; solar phase alone is insufficient |
| FW-M09 | Dense conifer cover | Forest type + canopy closure | P2 | Validate conifer class and closure against imagery/field observations |
| FW-M11 | Gallina directional 2 m concealment profile | Virtual cover-board from terrain + height-specific vegetation + woody continuity + seasonal foliage | P0 | Segmented 2 m target, 15 m distance, directional field observations; holdout validation |
| FW-M13 | Gallina 0–50 / 50–100 cm concealment | Same virtual cover-board, preserving low strata separately | P0 | Validate each low stratum independently |
| FW-M17 | Annual mast fall / production | Regional mast evidence + standardized local low-disturbance observations | P1 | Compare local observations with regional survey state; never conflate capacity with production |
| FW-M26 | Stand-specific hunter vulnerability zone | Seasonal terrain/vegetation viewshed from each stand | P0 | Laser/rangefinder visibility spot checks by bearing; leaf-on/off validation |
| FW-M41 | Residual winter cropland food | Crop identity + harvest state + residue-state model | P2 | Roadside/operator residue observations by crop/harvest class |

### Calibration does not mean bedding-site intrusion

Gallina concealment calibration targets **physical screening**, not bed occupancy. Field targets can be placed at non-sensitive representative structure classes. There is no requirement to walk high-probability bedding locations during hunting season.

Likewise, stand-vulnerability calibration measures what can physically be seen from a known stand. It does not require disturbing deer-use locations.

## Remain unavailable

| ID | Source measurement | Decision | Reason |
| --- | --- | --- | --- |
| FW-M03 | Wiemers forage index | Remain unavailable | The index combined standing crop with laboratory crude protein and acid detergent fiber. NDVI/EVI/crop identity do not reproduce forage chemistry |
| FW-M23 | Woody twig density / browse availability | Remain unavailable | LiDAR understory structure and leaf-off texture do not measure accessible palatable twig density/species composition |
| FW-M40 | D16 forest/wetland/CRP escape-cover bundle | Remain unavailable as a complete relationship input | Forest/wetland components are reproducible, but current reliable parcel-level CRP enrollment geometry is not available from the existing source stack |
| FW-M42 | D17 oil-sands industrial human-footprint composition | Remain unavailable for Flat Creek | Generic Kentucky development is not the same industrial footprint treatment used in the boreal oil-sands study |
| FW-M44 | Camera-derived wolf occurrence | Remain unavailable for Flat Creek | Coyote presence or generic predator habitat would be a different biological relationship |
| FW-M53 | Individual male rut/post-rut phase | Remain unavailable | Regional Kentucky breeding calendar does not establish an individual male's reproductive/movement phase |

### What “unavailable” means

Unavailable is not a dead end for Farm Watch generally.

It means **this specific published relationship cannot consume an invented substitute**.

For example:

- Farm Watch can still map low vegetation structure without calling it woody browse density.
- Farm Watch can still map roads and buildings without activating the boreal oil-sands cumulative-effects model.
- Farm Watch can still preserve Kentucky regional breeding timing without asserting that a particular male is in the study's rut/post-rut phase.
- A future Kentucky predator study could justify a different predator relationship without pretending wolf occurrence and coyote context are interchangeable.

## Highest-value P0 resolution work

The following measurement gaps are both tractable and directly useful to the eventual pre-flight system:

1. **FW-M15 — source-faithful male age scenarios**  
   Small biological-state contract change; immediately prevents age-category collapse.

2. **FW-M19 / FW-M20 — current corn identity and crop stage**  
   Direct observation/accepted-source route first; automation can follow only after classifier validation.

3. **FW-M25 / FW-M28 / FW-M31 / FW-M33 — explicit hunting activity and effort**  
   Factual operator activity is unusually high-value because it supports several hunting-risk studies without requiring wildlife disturbance.

4. **FW-M26 — stand vulnerability zone**  
   Builds directly on the generalized viewshed work and has an unusually practical calibration protocol.

5. **FW-M11 / FW-M13 — Gallina concealment**  
   Reuses the same terrain/structure/foliage substrate but preserves the original 15 m cover-board geometry and low vertical strata.

These remain independent units. Completing one does not authorize another.

## P1 resolution work

- operative-temperature proxy and black-globe calibration;
- woody-canopy percent calibration;
- annual mast state;
- building/development density;
- explicit food-plot/managed-food feature context;
- usable managed-water-source state;
- maternal-age and female-parturition scenario alignment;
- multiscale forest context and roads.

## P2 / deferred work

P2 includes snow/conifer winter context, local activity-period calibration, D16 scale/residual-crop work, forest-type/extreme-event context, and potential dispersal-path simulation.

The six unavailable measurements should not enter an implementation queue unless their evidentiary situation changes.

## Machine enforcement

`farm-watch-deer-measurement-resolution.ts` derives the currently blocked measurement IDs from the relationship registry and requires exactly one resolution decision for each.

CI fails if:

- a blocked measurement has no disposition;
- a decision exists for a measurement that is not currently blocked;
- a measurement has duplicate decisions;
- a reproducible or calibrated-proxy decision has no target product;
- the expected portfolio invariants regress.

The decision contract does **not** itself unblock a relationship. Each future measurement implementation must update the corresponding measurement-alignment state only after its own evidence/validation exit gate is satisfied.

## Relationship-release boundary

Before Batch 10 can consume a relationship:

1. all required source-study measurements must be resolved to an implemented `measurement_equivalent`, `derived_equivalent`, or validated `calibrated_proxy`;
2. value/subtype constraints must be enforced;
3. biological state gates must be explicit;
4. source geography/population/season/movement limitations remain attached;
5. coefficient transfer remains independently unauthorized unless separately reviewed;
6. unavailable study variables cause abstention rather than substitution.

This preserves the central rule:

> **A useful adjacent layer is not automatically the variable the study measured.**
