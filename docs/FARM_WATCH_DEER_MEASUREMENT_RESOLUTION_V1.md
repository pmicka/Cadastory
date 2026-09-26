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

The current blocked set contains 25 required study measurements:

- **12 reproduce**
- **7 calibrated proxy**
- **6 remain unavailable**

Resolved since this contract was created:

- **FW-M02 — Wiemers vegetation height:** production-validated `study-aligned-vegetation-height-context-v2`; promoted to `derived_equivalent` on 2026-09-23.
- **FW-M17 — annual mast fall / production:** Batch 5A + 5B now provide production mast capacity plus exact-year KDFWR statewide/regional mast state. The registry promotes FW-M17 from `unsupported` to `calibrated_proxy` **only at the authoritative regional-survey scope**. This does not establish property mast abundance, does not authorize prior-year carry-forward, and does not make the modeled capacity layer annual production.
- **FW-M24 — building/development density:** production `human-footprint-context-v1` supplies the FEMA USA Structures count/density over the exact 10.36 km² Delisle landscape area and now records live service edit dates, local feature production/imagery vintage coverage, the source's >450 sq ft inventory threshold, and explicit unquantified spatial completeness. It remains `derived_equivalent`; no claim of census-complete building capture is made.
- **FW-M36 — road landscape context:** production `human-footprint-context-v1` preserves canonical road geometry and `road-focal-context-v1` now supplies an on-demand 10 m distance-to-nearest-road grid with mean 30/90/270 m focal extraction. This closes the physical measurement path while recording the OSM-for-TIGER source substitution; the measurement remains `derived_equivalent` and assigns no road-response sign.
- **FW-M29 / FW-M32 — managed food feature geometry:** production `managed-food-feature-context-v1` now stores stable operator-configured food-plot/managed-forage polygons separately from year-specific management state, with an explicit per-year inventory state so `confirmed_none` is a known absence rather than missing data. Both measurements are promoted to `derived_equivalent`; supplemental feeders and mineral attractants remain separate point observations.
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

Current posture counts across the 25 blocked measurements:

- **7 active**
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
| FW-M15 | Hunsaker male age | Expand explicit biological state to preserve yearling, 2-year-old, and 3+ male categories | P0 | Never infer exact age from generic adult status |
| FW-M19 | Current corn identity | Accept current-year field-bound identity from explicit observation or another validated/rights-permitted source | P0 | Stale CDL and regional crop progress cannot satisfy it |
| FW-M20 | Corn stage / harvest | Represent explicit field-level tasseling/silking or harvested state; direct/accepted observation first | P0 | Raw HLS trajectory alone cannot promote crop stage |
| FW-M25 | Dated stand hunt | Record actual stand-specific hunt sessions with start/end time | P0 | Hunting season or stand presence is not a hunt event |
| FW-M28 | Daily hunter activity | Derive hunter use/intensity from known sessions and access activity | P0 | Off-property or unlogged activity remains unknown |
| FW-M31 | Frequent hunting risk | Derive event frequency / hunter-hours over explicit windows | P0 | Stand presence does not imply hunting frequency |
| FW-M33 | Low hunting pressure | Represent quantitative hunter effort density and compare with source context | P0 | Do not invent a universal low/high threshold |
| FW-M43 | AVI species-specific overstorey composition (“intact deciduous forest” shorthand) | Reproduce point-extracted percent overstorey composition for the source tree-species family, or keep unresolved until a defensible source-equivalent species-composition method exists | P2 | Generic Trees/TCC, broad deciduous class, edge density or fragmentation is not equivalent; does not make the rest of FW-D17 available |
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

### Active autonomous spatial/environmental work

- **FW-M43 — AVI species-specific overstorey composition (“intact deciduous forest” shorthand)**
- **FW-M48 — usable managed-water-source state only where stable source inventory can be configured without recurring field input**
- **FW-M56 — agriculture along simulated potential dispersal paths**

The parked B/D measurements remain in their scientific disposition tables above for provenance, but they are not part of this active queue. FW-M08, FW-M09, FW-M24, FW-M35, FW-M36, FW-M39, FW-M45, and FW-M47 are no longer listed here because their production exit gates passed on 2026-09-25.

The six `remain_unavailable` measurements continue to force abstention. Their inclusion in parked D means there is also no 2026 effort to find weak substitutes.

### FW-M08 production resolution — 2026-09-25

The DelGiudice et al. (2013) winter measurement has been production-resolved as `snow-winter-severity-context-v1`.

The source relationship did **not** use a generic “winter severity” class as its fitted physical predictor. The study modeled daily snow depth in centimeters and minimum daily temperature in degrees Celsius directly. Minnesota's winter-severity index (WSI) was a separate cumulative context measure: one point per day for snow depth at least 38 cm and one point per day for minimum temperature at or below -17.7 °C during November-May.

Farm Watch therefore keeps the two daily physical variables first-class:

- snow depth from NOAA/NWS/NOHRSC National Snow Analysis, sampled once daily at the property target;
- minimum daily temperature derived from the centrally persisted NOAA/NCEP HRRR f00 analysis archive over the property's local calendar day.

The HRRR-derived daily minimum is accepted only when at least 75% of the expected 23-25 local-day hourly analyses are present. Lower coverage stays partial rather than being promoted to a complete daily minimum.

The Minnesota WSI arithmetic is reproduced only as **source provenance/context**. Farm Watch does not emit a Minnesota severity category, copy a northern biological threshold to Kentucky, transfer a DelGiudice coefficient, infer dense-cover use, or create a generic cold-weather movement rule.

The initial Flat Creek production sample on 2026-09-25 returned 0 cm NOHRSC snow. Because the local day was still in progress, the daily record correctly remained `partial` with minimum temperature pending. The WSI context was `not_applicable` because September is outside its November-May source window.

FW-M08 is therefore no longer a blocked measurement. M08 by itself did not activate the northern winter-cover relationship; FW-M09 was resolved separately below.

### FW-M09 production resolution — 2026-09-25

FW-M09 has been production-resolved as `conifer-cover-context-v1` with a **calibrated-proxy** disposition.

The source study's vegetation measurement was not generic canopy density. Leaf-off color-infrared aerial photography was used to delineate stands, assign dominant tree species, and classify conifer canopy closure. The source closure classes were open conifer <40%, moderately dense conifer 40% to <70%, and dense conifer ≥70%. The fitted availability categories were moderately dense conifer, dense conifer, and `other`; `other` included open conifer, openings, and hardwoods.

Farm Watch reproduces that class structure with a conservative national source substitution:

- Annual NLCD Evergreen Forest (42) supplies the conifer-dominant type mask;
- NLCD Tree Canopy Cover supplies modeled percent canopy closure;
- Annual NLCD Mixed Forest (43) remains `other` rather than being promoted to conifer;
- the exact <40 / 40–<70 / ≥70% thresholds are retained.

The latest common year across the two source families is used so type and canopy closure are not silently drawn from different years. Initial production validation used matched 2024 land cover + 2024 TCC.

The relationship-binding availability scale is the current barrier-aware `broad_3000m` domain. At Flat Creek this domain is 21.394 km², within the cited study-site area range. Smaller property/500 m/1.5 km summaries remain neutral diagnostics.

Initial Flat Creek broad-domain availability was:

- moderately dense conifer: **0.0421%**;
- dense conifer: **2.3345%**;
- other: **97.6235%**.

Bounded transient QA against 2024 KyFromAbove Phase 3 RGB imagery supported the conservative classification: sampled dense cells corresponded to compact evergreen patches, Mixed Forest cells were visibly heterogeneous, and the rare moderate cells occupied edge/partially closed evergreen settings. No open-conifer source cell occurred in the Flat Creek broad domain, so that class was not locally image-validated.

The source substitution remains `calibrated_proxy`, not `derived_equivalent`, because the 30 m national classification/model is not the source air-photo stand interpretation and the moderate class is edge-sensitive.

FW-M09 is no longer a blocked measurement. With FW-M08 and FW-M09 resolved, FW-R03 has no remaining **required measurement-alignment blocker**, but it remains `context_only` because FW-M10 winter solar/thermal exposure is context-only. No Minnesota response coefficient, dense-cover preference, bedding label, or Kentucky winter threshold is transferred.

### FW-M29 / FW-M32 production resolution — 2026-09-25

FW-M29 and FW-M32 are production-resolved as `managed-food-feature-context-v1`.

The product is deliberately configuration-first rather than a chemistry or remote-sensing model:

- stable polygons are stored once for `food_plot`, `managed_forage_area`, or `study_relevant_managed_cover`;
- year-specific feature state is stored separately as `active`, `inactive`, or `unknown`;
- a property/year inventory explicitly distinguishes `confirmed_none`, `configured`, and `unknown`;
- the internal reader returns known absence when the inventory is explicitly empty rather than treating zero polygons as missing data.

Flat Creek is configured as `confirmed_none` for 2026 because the owner confirmed there are no food plots or managed forage areas on the property this year.

The existing deer feeder is separately documented as a large corn `supplemental_feed_point`. The salt block identified on 2026-09-25 is separately documented as a `mineral_attractant_point` at the existing three-way canonical trail junction `[-84.8850346, 38.3234328]`, whose trail topology was independently verified as three incident segments. Neither point is promoted into a managed-food polygon, and the verification screenshot is not persisted.

Both study measurements are promoted to `derived_equivalent` because Farm Watch now reproduces the mapped managed-food feature form and current/absent seasonal state. This does **not** claim forage chemistry, nutrient abundance, deer attraction, or feeder/mineral effects.

The downstream hunting-risk relationships remain blocked for their independent human-activity requirements: FW-R15 still requires FW-M28 daily hunter activity, and FW-R16 still requires FW-M31 frequent-hunt risk.

### FW-M43 method-definition correction — 2026-09-25

The source measurement has now been recovered from Darlington et al. (2022) closely enough to remove an earlier ambiguity.

The paper's abstract describes the cumulative model as including **intact deciduous forest**, but the Methods and Table 1 operationalize natural forest composition as Alberta Vegetation Inventory (AVI) overstorey species-composition percentages:

- `PCT Aw` — trembling aspen (*Populus tremuloides*);
- `PCT Bw` — white birch (*Betula papyrifera*);
- `PCT Fb` — balsam fir (*Abies balsamea*);
- `PCT Lt` — tamarack (*Larix laricina*);
- `PCT Pb` — balsam poplar (*Populus balsamifera*);
- `PCT Pj` — jack pine (*Pinus banksiana*);
- `PCT Sb` — black spruce (*Picea mariana*);
- `PCT Sw` — white spruce (*Picea glauca*).

The paper defines `PCT` as the percent of the forest-canopy overstorey dominated by the leading tree species. These covariates were extracted at each used and available point and the percent-cover variables were standardized before modeling. The season-specific 2,093 / 4,249 / 2,172 / 3,903 m buffers defined the RSF availability domain; they were **not** focal radii used to compute forest composition.

Accordingly, FW-M43 is **not** a source-defined fragmentation metric, edge metric, distance-to-deciduous metric, binary intact-forest class, or focal-buffer proportion. “Intact deciduous forest” is retained in the stable measurement ID for provenance, but it must not drive implementation semantics.

Current Farm Watch registered substrates do not yet satisfy the reproduced measurement:

- Sentinel-2 10 m LULC supplies a generic `Trees` class;
- NLCD / Science TCC supplies total percent tree-canopy cover;
- neither registered source supplies source-equivalent overstorey tree-species composition.

Therefore M43 remains an active research/implementation candidate but **unmaterialized**. A broad deciduous/forest-type product may still be useful neutral context, but it cannot be promoted as reproduced FW-M43 without an explicit fidelity reclassification and validation. USFS FIA/TreeMap and LANDFIRE are plausible source families to evaluate, but accepting either as source-equivalent requires a separate method decision; categorical forest type alone is insufficient.

This correction does not change the FW-D17 abstention boundary. FW-M42 human-footprint composition and FW-M44 wolf occurrence remain unavailable, so resolving M43 alone cannot activate the Darlington relationship.

### FW-M47 production resolution — 2026-09-25

The Abernathy et al. (2019) source measurement is now recovered and production-materialized.

The study did **not** model a single categorical “forest refuge type” flag. It reclassified Florida Natural Areas Inventory Cooperative Land Cover v3.2 at 10 m, retained six habitat classes, calculated a continuous Euclidean-distance surface to each class, extracted those distances at used and available deer locations, and scaled/centered model variables. The six retained source classes were:

- pine forest;
- hardwood swamp;
- marsh;
- prairie;
- shrub;
- hardwood hammock.

Farm Watch therefore implements M47 as six **neutral distance-to-class covariates**, not as a refuge score or deer-habitat classification.

Because the FNAI classes are Florida-specific, the production product records an explicit national source substitution rather than pretending literal equivalence:

- pine forest → Annual NLCD Evergreen Forest (42), treated as a broad evergreen analogue rather than a pine-species map;
- hardwood swamp → NWI PFO1*, Palustrine Forested Broad-Leaved Deciduous;
- marsh → NWI PEM*, Palustrine Emergent;
- prairie → Annual NLCD Grassland/Herbaceous (71), with pasture/hay and cultivated crops intentionally excluded;
- shrub → Annual NLCD Shrub/Scrub (52);
- hardwood hammock → Annual NLCD Deciduous Forest (41), treated as an upland/broad hardwood analogue rather than asserting that a Florida hammock community occurs in Kentucky.

The product preserves the source measurement form while carrying `evidence_state: proxy` for the class crosswalk. It stores no deer selection sign, refuge quality, hurricane response, survival benefit, or weighted habitat score. Right-censored distances are reported explicitly when a mapped class is absent inside the fixed 3 km search radius; source failure remains unavailable rather than absence.

Flat Creek production validation used Annual NLCD 2024 plus the existing authoritative NWI cache. All six classes resolved within the search radius at the property center. The source substitution does **not** authorize Abernathy’s Florida coefficients in Kentucky and does not turn ordinary rain or wind into an FW-D18 event.

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
