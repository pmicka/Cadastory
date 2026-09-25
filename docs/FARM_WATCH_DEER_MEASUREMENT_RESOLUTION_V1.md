# Farm Watch Deer Measurement Resolution v1

Status: source-controlled study-fidelity disposition contract  
Version: 2026-09-25  
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

The current blocked set contains 30 required study measurements:

- **16 reproduce**
- **8 calibrated proxy**
- **6 remain unavailable**

Resolved since this contract was created:

- **FW-M02 — Wiemers vegetation height:** production-validated `study-aligned-vegetation-height-context-v2`; promoted to `derived_equivalent` on 2026-09-23.
- **FW-M17 — annual mast fall / production:** Batch 5A + 5B now provide production mast capacity plus exact-year KDFWR statewide/regional mast state. The registry promotes FW-M17 from `unsupported` to `calibrated_proxy` **only at the authoritative regional-survey scope**. This does not establish property mast abundance, does not authorize prior-year carry-forward, and does not make the modeled capacity layer annual production.
- **FW-M24 — building/development density:** production `human-footprint-context-v1` supplies the FEMA USA Structures count/density over the exact 10.36 km² Delisle landscape area and now records live service edit dates, local feature production/imagery vintage coverage, the source's >450 sq ft inventory threshold, and explicit unquantified spatial completeness. It remains `derived_equivalent`; no claim of census-complete building capture is made.
- **FW-M36 — road landscape context:** production `human-footprint-context-v1` preserves canonical road geometry and `road-focal-context-v1` now supplies an on-demand 10 m distance-to-nearest-road grid with mean 30/90/270 m focal extraction. This closes the physical measurement path while recording the OSM-for-TIGER source substitution; the measurement remains `derived_equivalent` and assigns no road-response sign.
- **FW-M39 — D16 study scales:** production `multiscale-cover-context-v1` supplies exact 1 km² and 9 km² analytical windows; promoted to `derived_equivalent`. North Dakota hunting-unit geometry remains untransferred.
- **FW-M45 — extreme hurricane event:** production `extreme-weather-event-context-v1` supplies an authoritative NWS tropical/extreme-wind event + footprint + time gate. The v2 source-health contract returns `not_applicable` only after a fresh successful jurisdiction poll, and fails closed on stale/failed polling or unresolved qualifying alert geometry; ordinary weather remains excluded. The measurement remains `derived_equivalent`.
- **FW-M35 — multiscale forest landscape context:** `multiscale-forest-context-v1` reproduces 10 m tree-class forest proportion and built-excluded internal forest-edge density at 30/90/270 m. The open Sentinel-2 annual LULC classifier is a documented substitution for the study Dynamic World 2015–2019 composite; no forest-response sign or Stephens coefficient transfers.

CI requires every currently blocked measurement to have one and only one disposition.

## 2026 operating posture

Scientific disposition and implementation priority are now separated from **operating posture**. A measurement can remain scientifically important while being intentionally removed from the 2026 implementation queue.

Machine posture values:

- `active` — still in the implementation queue because it can be pursued autonomously or with bounded one-time/static configuration;
- `parked_2026_individual_state` — scientifically preserved, but individual identity/state differentiation is not reliably captured this season;
- `parked_2026_manual_or_noncore` — scientifically preserved, but the measurement would require repeated manual user input, a calibration/technology stack outside the intended operating model, or a study-specific variable that is not operationally available.

Current posture counts across the 30 blocked measurements:

- **12 active**
- **3 parked — individual state**
- **15 parked — manual/non-core**

Parking does **not** weaken the science contract. Parked measurements still cause abstention wherever the relationship requires them; they simply no longer appear as active engineering work for the 2026 season.

### Parked B — individual-state differentiation

- FW-M15 — Hunsaker male age;
- FW-M51 — maternal age category;
- FW-M54 — female parturition phase.

These are parked because Farm Watch will not rely on repeated individual identification/differentiation this season.

### Parked D — repeated manual input / non-core stack

- FW-M01 — operative temperature calibration;
- FW-M03 — forage chemistry index;
- FW-M05 — movement-defined activity periods;
- FW-M19 — current corn identity;
- FW-M20 — corn stage / harvest;
- FW-M23 — woody twig density;
- FW-M25 — dated stand hunt;
- FW-M28 — daily hunter activity;
- FW-M31 — frequent-hunt risk;
- FW-M33 — low hunting pressure;
- FW-M40 — complete D16 escape-cover bundle;
- FW-M41 — residual winter cropland food;
- FW-M42 — oil-sands human-footprint composition;
- FW-M44 — wolf occurrence;
- FW-M53 — individual male rut/post-rut phase.

These remain scientifically explicit, but no 2026 implementation effort should be spent manufacturing substitutes or asking for recurring manual data entry.

## Reproduce

| ID | Source measurement | Resolution | Priority | Boundary |
| --- | --- | --- | --- | --- |
| FW-M08 | Snow depth / winter severity | Build physical snow/winter-severity context from authoritative snow depth and temperature; preserve the published Minnesota WSI only as source-defined context | P2 | No Kentucky biological threshold is implied |
| FW-M15 | Hunsaker male age | Expand explicit biological state to preserve yearling, 2-year-old, and 3+ male categories | P0 | Never infer exact age from generic adult status |
| FW-M19 | Current corn identity | Accept current-year field-bound identity from explicit observation or another validated/rights-permitted source | P0 | Stale CDL and regional crop progress cannot satisfy it |
| FW-M20 | Corn stage / harvest | Represent explicit field-level tasseling/silking or harvested state; direct/accepted observation first | P0 | Raw HLS trajectory alone cannot promote crop stage |
| FW-M25 | Dated stand hunt | Record actual stand-specific hunt sessions with start/end time | P0 | Hunting season or stand presence is not a hunt event |
| FW-M28 | Daily hunter activity | Derive hunter use/intensity from known sessions and access activity | P0 | Off-property or unlogged activity remains unknown |
| FW-M29 | Food opportunity in adult-male hunting study | Bind to explicit food-plot / managed-food feature geometry and current management state | P1 | Generic vegetation greenness is not the study resource |
| FW-M31 | Frequent hunting risk | Derive event frequency / hunter-hours over explicit windows | P0 | Stand presence does not imply hunting frequency |
| FW-M32 | Forage-rich risky areas | Bind to explicit mapped food plots / study-relevant cover types | P1 | Does not claim measured nutrient abundance |
| FW-M33 | Low hunting pressure | Represent quantitative hunter effort density and compare with source context | P0 | Do not invent a universal low/high threshold |
| FW-M43 | Intact deciduous forest | Derive forest type and intact/fragmented landscape state | P2 | Does not make the rest of FW-D17 available |
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

## Active 2026 implementation queue

Priority labels remain useful for scientific sequencing, but the operating posture is authoritative for what Farm Watch should actually build this season.

### Active calibrated/static work

- **FW-M11 / FW-M13 — Gallina concealment:** optional calibrated one-time/static configuration path; no bedding-site intrusion is required.
- **FW-M26 — stand vulnerability zone:** optional calibrated one-time/static stand viewshed path.
- **FW-M04 — woody canopy:** autonomous/static spatial measurement once calibration is bounded.
- **FW-M09 — dense conifer cover:** autonomous/static spatial classification once validation is bounded.

### Active autonomous spatial/environmental work

- **FW-M08 — snow depth / winter severity**
- **FW-M29 / FW-M32 — explicit managed-food feature geometry**
- **FW-M43 — intact deciduous forest**
- **FW-M47 — forest refuge type**
- **FW-M48 — usable managed-water-source state only where stable source inventory can be configured without recurring field input**
- **FW-M56 — agriculture along simulated potential dispersal paths**

The parked B/D measurements remain in their scientific disposition tables above for provenance, but they are not part of this active queue. FW-M24, FW-M35, FW-M36, FW-M39, and FW-M45 are no longer listed here because their production exit gates passed on 2026-09-25.

The six `remain_unavailable` measurements continue to force abstention. Their inclusion in parked D means there is also no 2026 effort to find weak substitutes.

## Machine enforcement

`farm-watch-deer-measurement-resolution.ts` derives the currently blocked measurement IDs from the relationship registry and requires exactly one resolution decision for each.

CI fails if:

- a blocked measurement has no disposition;
- a decision exists for a measurement that is not currently blocked;
- a measurement has duplicate decisions;
- a reproducible or calibrated-proxy decision has no target product;
- an operating posture is missing or invalid;
- the blocked/disposition/posture portfolio invariants regress.

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
