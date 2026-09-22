# Farm Watch Deer Science Implementation Plan

Status: implementation plan — 2026-09-21  
Target species: white-tailed deer (`Odocoileus virginianus`)  
Primary transfer geography: central Kentucky / lower Ohio Valley  
Primary validation property: `validation-property-01`

## Objective

Implement a science-transfer deer modeling stack that reuses published white-tailed-deer ecology without collapsing neutral Farm Watch evidence into unsupported biological labels.

The intended architecture is:

```
authoritative / observed source data
  -> neutral physical and environmental products
  -> explicit biological-state/scenario context
  -> versioned literature-backed relationship modules
  -> module-specific deer science outputs
  -> optional quantitative synthesis only where coefficients are transferable
  -> local validation / calibration
```

This plan implements the relationships preserved in `FARM_WATCH_DEER_SCIENCE_EVIDENCE_LEDGER.md`.

It does not ask the validation property to rediscover established ecology. Local observations are used to evaluate transfer, calibrate parameters, or resolve property-specific state when needed.

## Non-goals

The first implementation will not:

- create a universal deer suitability score;
- assign deer meaning directly to terrain forms, field edges, roads, trails, LiDAR bands, or canopy classes;
- copy published coefficients from another population without a transfer review;
- infer hunting pressure from hunting season, road proximity, or stand geometry alone;
- infer current food from stale CDL crop identity;
- treat stream-gauge discharge as property water availability;
- infer bedding, travel corridors, or funnels directly from neutral structure/terrain;
- encode moon phase, barometric pressure, generic cold-front rules, or universal ridge/draw/saddle preferences;
- hide stale, unavailable, proxy, or out-of-scope inputs.

## Existing production baseline

Already operational:

- barrier-aware 500 m / 1.5 km / 3 km landscape domains;
- landscape physical context;
- terrain-form candidates and reference slope permeability;
- canopy/field/structure edge and patch context;
- Phase 3 LiDAR physical structure;
- local 500 m landscape structure;
- leaf-off woody-pattern context;
- mapped agricultural field / field-edge context;
- Seasonal State v1;
- property-grade NOAA HRRR meteorological forcing v1 with hourly pilot refresh;
- historical Daymet environmental context;
- QPE precipitation, drought, USGS stream, Crop-CASMA root-zone moisture, NASS crop progress/stage;
- roads, trails, buildings, and other access geometry.

The deer science ledger is normative for all future biological terms.

## Architecture principles

### 1. Neutral products first

Products that can be described without deer semantics should remain neutral.

Examples:

- `meteorological-forcing`
- `solar-exposure-context`
- `thermal-exposure-context`
- `horizontal-visibility-context`
- `field-phenology-context`
- `mast-resource-context`
- `surface-water-state`
- `human-activity-context`

These products should use `deterministic_derived`, `authoritative`, `observed`, or explicit proxy evidence classes as appropriate and must keep:

- `scoring_performed=false`
- `behavioral_inference_performed=false`

### 2. Deer-specific logic lives in separate modules

The deer layer should consume neutral products through explicit relationship modules whose provenance points back to the science ledger.

Examples:

- thermal × resource tradeoff;
- crop phenology / harvest response;
- mast response;
- localized hunting risk;
- terrain × movement-state context;
- reproductive / diel movement state.

### 3. Missing state means abstention, not imputation

If a relationship requires:

- sex,
- age,
- reproductive state,
- movement state,
- current crop stage,
- recent hunting pressure,
- current thermal forcing,

and that input is unavailable, the module must return `insufficient_input`, `not_applicable`, or an explicit scenario set rather than inventing a value.

### 4. Relationship form and coefficient transfer are separate decisions

A module may be authorized to reuse:

- direction;
- interaction form;
- state gate;
- nonlinear shape;
- threshold;

without being authorized to reuse the study's numeric coefficient.

Numeric parameters require a separate coefficient-transfer record.

### 5. First useful product is modular, not a composite score

The first production deer output should be a vector of evidence-backed module results, not one scalar probability or habitat score.

---

# Target product stack

## Neutral/state products

| Product | Type | Primary evidence | Status |
| --- | --- | --- | --- |
| `meteorological-forcing-v1` | dated/hourly state | NOAA HRRR + historical Daymet fallback where appropriate | production |
| `solar-exposure-context-v1` | gridded physical | canonical terrain + solar geometry + horizon + canopy | production |
| `thermal-exposure-context-v1` | dated gridded physical/proxy | static solar terrain + exact HRRR analysis | production |
| `field-phenology-context-v1` | dated field state | CDL + NASA HLS VI + NASS regional context | build |
| `mast-resource-context-v1` | annual/seasonal resource proxy | USFS TreeMap/BIGMAP + Kentucky mast survey | build |
| `horizontal-visibility-context-v1` | gridded physical | LiDAR + terrain | build |
| `surface-water-state-v1` | dated physical/proxy | 3DHP/NWI + DEM + QPE/soil moisture + observations | build |
| `human-activity-context-v1` | event/state | explicit owner/operator observations | build |
| `diel-photoperiod-context-v1` | deterministic state | date/time/location solar geometry | production |

## Deer-specific products

| Product | Purpose |
| --- | --- |
| `deer-biological-state-v1` | explicit sex/age/reproductive/movement/diel scenario |
| `deer-relationship-registry-v1` | machine-readable implementation of science-ledger relationships |
| `deer-science-context-v1` | module-by-module evaluated output with provenance, applicability, freshness, and uncertainty |
| later: `deer-relative-selection-v1` | quantitative synthesis only when parameter transfer is justified |

Gridded artifacts should continue to use the generic Farm Watch materialization framework/private Storage. Date-keyed scalar/state products should use guarded central tables and service-only internal readers.

---

# Implementation sequence

## Batch 0 — Science governance and baseline

Status: substantially complete.

### Deliverables

- deer science evidence ledger;
- AGENTS.md requirement to cite ledger evidence;
- blocked assumptions;
- transfer vocabulary;
- current-input readiness inventory.

### Exit gate

No deer-specific model term may ship without a ledger relationship ID and transfer disposition.

---

# Batch 1 — Property-grade meteorological forcing

Status: production; deployed and hourly pilot refresh active  
Priority: P0  
Ledger dependencies: FW-D01, D02, D03, D05, D18, D19, D20.

## Objective

Create a central, property-relevant meteorological state suitable for physical thermal modeling and extreme-event context.

## Preferred current source

NOAA HRRR is the selected v1 source. The implementation uses authoritative NOAA Open Data GRIB2 sidecar indexes plus byte-range retrieval of the required `wrfsfcf00` analysis records. It was selected because it is:

- operational over CONUS;
- approximately 3 km;
- updated hourly;
- capable of supplying 2 m temperature/dew point or relative humidity;
- 10 m wind components;
- downward shortwave radiation;
- cloud fields;
- precipitation and other near-surface state.

Historical Daymet remains useful for historical daily environmental context but is not a substitute for hourly thermal forcing.

The v1 collector is analysis-only (`f00`, lead 0) even though the persistence schema records analysis/forecast state explicitly for future extension. Grid-relative HRRR 10 m winds are retained and rotated to true east/north before wind speed/direction are derived. Full model files are not persisted.

## Proposed contract

`farm_watch.property_meteorological_forcing_v1`

Key:

- property;
- valid timestamp;
- source/model cycle.

Fields:

- air temperature;
- dew point and/or relative humidity;
- wind U/V and derived speed/direction;
- downward shortwave radiation;
- cloud fraction when available;
- precipitation;
- source run time;
- forecast lead;
- valid time;
- spatial resolution;
- distance/grid-cell metadata;
- source class;
- analysis/forecast classification;
- retrieved time;
- freshness state;
- exact source identity/hash.

## Requirements

- Do not reuse the existing generic Scout weather row when it is spatially unrelated.
- Never silently mix forecast and analyzed/historical state.
- Preserve HRRR grid resolution and model provenance.
- A forecast value remains forecast evidence.
- A model grid value remains a spatial proxy, not an on-property weather station.

## Tests / exit gate

- source selection deterministic;
- valid/run/lead times correct across UTC/date boundaries;
- vector wind conversion tested;
- radiation units tested;
- stale/future handling tested;
- validation property resolves to a nearby HRRR grid cell;
- no deer semantics.

---

# Batch 2 — Solar and thermal physical context

Status: production; Batch 2A and Batch 2B deployed and validated  
Priority: P0  
Depends on: Batch 1 + existing DEM/canopy/terrain.

## 2A — `solar-exposure-context-v1`

Implementation is split into a reusable static `solar-terrain-context-v1` materialization plus date-keyed `solar-exposure-context-v1`. Build a deterministic physical solar-exposure product independent of deer.

### Inputs

- canonical terrain-form-permeability elevation grids;
- deterministic slope/aspect;
- unmasked KyFromAbove DEM support for terrain horizon only;
- property/domain target geometry;
- date/time;
- sun position;
- terrain horizon/self-shading;
- canopy/TCC;
- optional fine structural support where appropriate.

### Suggested spatial support

- 10 m over barrier-aware local 500 m;
- 30 m over barrier-aware 1.5 km;
- no 3 km raster in v1; add only a coarse summary later if a downstream scientific requirement shows value.

### Outputs

For hourly or named diel windows:

- solar elevation/azimuth;
- direct-beam terrain exposure;
- terrain-shadow flag;
- relative potential solar load;
- canopy attenuation proxy;
- sky-view/horizon summary if implemented;
- cumulative exposure for morning/midday/evening/day.

Do not call this operative temperature.

## 2B — `thermal-exposure-context-v1`

Co-register the exact current HRRR analysis with static solar-terrain context while preserving each physical component independently.

### Initial v1 output

v1 intentionally does **not** collapse unlike physical variables into a weighted thermal score.

It retains:

- ambient air temperature;
- dew point;
- relative humidity;
- true 10 m wind speed/direction;
- downward shortwave;
- downward longwave;
- cloud cover;
- precipitation rate;
- exact solar elevation/azimuth;
- terrain direct-beam incidence/shadow factor;
- explicit linear TCC-open screening proxy.

HRRR shortwave/longwave and wind remain scalar modeled forcing components in v1. They are not spatially redistributed using unsupported direct/diffuse radiation or aerodynamic-shelter assumptions.

The artifact explicitly records that operative temperature and composite thermal index are not calculated.

If a later biophysical review supports a defensible operative-temperature or animal heat-balance formulation for deer, introduce that as a new version with its own validation contract.

## Scientific acceptance checks

Implementation should reproduce the qualitative physics required by FW-D01–D03:

- shaded terrain/canopy should reduce midday solar exposure;
- the direction can reverse in cold conditions where solar gain matters;
- canopy alone must not equal “thermal refuge”;
- solar radiation alone must not equal realized thermal state.

## Exit gate

A dated physical thermal surface can be produced with no deer label and with all assumptions/versioning visible.

---

# Batch 3 — Diel and biological-state contracts

Status: production; deployed and validated 2026-09-21  
Priority: P0  
Depends on: deterministic solar time; regional phenology review.

## 3A — `diel-photoperiod-context-v1`

Deterministically compute:

- sunrise;
- sunset;
- solar noon;
- civil twilight if needed;
- day length;
- biologically useful named periods such as night / morning-crepuscular / day / evening-crepuscular.

The exact deer-module use of these periods must cite the ledger.

## 3B — regional breeding/reproductive-state evidence review

The targeted Kentucky / lower Ohio Valley review is complete for the v1 state contract.

Evidence disposition:

- FW-D21: Kentucky statewide qualitative breeding context — October through January with peak activity usually in mid-November; suitable for a regional timing gate only;
- FW-D22: Illinois female conception timing varies materially by maternal age; age-effect form is reusable, but Illinois dates are not Kentucky coefficients;
- FW-D23: Ohio mature-doe physiological onset in early November is regional corroboration only and does not fire a Kentucky relationship;
- FW-D06: Wisconsin male age × breeding-season movement form remains available only after a locally appropriate Kentucky breeding gate is active; Wisconsin dates are not imported.

Exact annual Kentucky physiographic-region conception-date values remain deferred until the authoritative KDFWR product is captured in structured, source-controlled form.

## 3C — `deer-biological-state-v1`

Explicit scenario object:

- species;
- sex: male / female / unknown;
- age class: juvenile / yearling / adult / unknown;
- reproductive state;
- diel period;
- season;
- movement state: resident / dispersal / unknown;
- state provenance;
- confidence;
- applicable relationship IDs.

If sex or age is unknown, the state remains unknown; later evaluation may return parallel scenarios rather than averaging them.

Regional population timing is stored separately from `individual_reproductive_state`. A date inside Kentucky's documented breeding season must never auto-set estrus, conception, pregnancy, or mate-searching state for an individual deer.

## Exit gate

Every deer relationship can ask for a named state and fail closed when that state is unknown.

---

# Batch 4 — Dynamic agricultural resource state

Status: Batch 4A implementation candidate — not deployed; Batch 4B HLS materializer pending  
Priority: P0/P1  
Ledger dependencies: FW-D08, D09, D15, D16.

## Objective

Replace “mapped crop class = current food” with current field state.

## `field-phenology-context-v1`

Batch 4 is split into two dependency-correct layers. **Batch 4A** establishes the service-only field-observation store, landscape-aware field target selection, dated field-state resolver, provenance/identity contracts, and fail-closed unknown phenology semantics. **Batch 4B** adds the protected HLS time-series materializer and only then may enable evidence-backed phenology/harvest classification.

The validation property itself intersects no current USDA CSB field polygon, while its existing Farm Watch landscape domains contain 1 field in `local_500m`, 12 in `landscape_1500m`, and 37 in `broad_3000m`. Field state is therefore modeled by explicit multiscale domain membership rather than assuming agricultural fields and the watched parcel are coextensive.


### Inputs

- current/latest USDA CDL;
- existing field boundaries;
- NASA HLS vegetation-index time series;
- NASS crop progress/stage as regional context;
- known farm/operator observations when available.

USDA CDL is now 10 m beginning with 2024, improving field attribution, but it remains annual crop identity rather than phenology.

NASA HLS vegetation indices provide temporally repeated vegetation state suitable for detecting green-up/senescence and candidate harvest transitions.

### Per-field state

- crop identity + crop-year provenance;
- HLS observation dates;
- NDVI/EVI or selected VI trajectory;
- phenology state:
  - green-up;
  - vegetative;
  - mature/senescing;
  - probable harvest transition;
  - post-harvest/residual;
  - unknown;
- cloud/data support;
- confidence/state class;
- regional NASS context;
- operator override/observation if present.

### Important constraint

Harvest detection should be a remote-sensing state with uncertainty, not an assertion when cloud gaps or ambiguous vegetation changes prevent classification.

## Exit gate

The deer layer can distinguish standing/active crop, probable harvest transition, post-harvest, and unknown rather than relying on static CDL.

---

# Batch 5 — Mast capacity and annual mast state

Priority: P1  
Ledger dependency: FW-D07.

## Objective

Represent mast as:

1. where mast-producing trees plausibly occur; and
2. what annual production state is documented/proxied.

These must remain separate.

## Proposed `mast-resource-context-v1`

### Species-capacity layer

Candidate authoritative/proxy sources:

- USFS TreeMap;
- FIA BIGMAP species biomass;
- future better local forest inventory if available.

Map oak groups relevant to mast:

- white-oak group;
- red-oak group;
- optional hickory/beech context.

TreeMap/BIGMAP are modeled/imputed forest products. They establish probabilistic/species-capacity context, not observed trees at each pixel.

### Annual-production layer

Kentucky Fish & Wildlife publishes annual mast survey reports with white oak/red oak/hickory/beech ratings by survey site/region.

Store:

- survey year;
- group;
- survey geography;
- percent bearing any mast / published category;
- distance/region relation to property;
- evidence state = regional proxy unless the property itself is observed.

### Combined context

Output separately:

- `mast_capacity`
- `annual_mast_proxy`
- `property_observation` if one exists.

Do not multiply these into an undocumented “food score” in the neutral product.

## Exit gate

FW-D07 can consume an explicit current mast state without pretending canopy density equals acorn availability.

---

# Batch 6 — Neutral horizontal visibility / obstruction

Priority: P1  
Ledger dependency: FW-D04 and future white-tailed-deer visibility work.

## Objective

Convert existing 3-D physical structure into a neutral visibility/obstruction representation without labeling it security cover or bedding.

## Proposed `horizontal-visibility-context-v1`

Possible outputs at several neutral observer heights:

- directional visible distance;
- obstruction fraction by distance band;
- horizon/line-of-sight openness;
- near-field obstruction;
- angular visibility;
- summary over 10 / 25 / 50 / 100 m.

Use multiple observer-height scenarios so the neutral product is not hard-coded to deer eye height.

## Data

Prefer existing central LiDAR artifacts where sufficient. If full 3-D point geometry is required, use the protected central worker path; do not restore browser COPC processing.

## Physical validation

Validate against:

- held-out LiDAR-derived geometry;
- imagery where useful;
- field photographs or operator observations if available.

This is validation of visibility physics, not testing whether deer bed there.

## Exit gate

A deer module can later consume a physical visibility metric with known scale and quality.

---

# Batch 7 — Surface-water availability / persistence context

Priority: P1/P2  
Ledger dependencies: FW-D15, D19; water evidence remains weaker/context-specific.

## Objective

Separate hydrography, recent wetness, and observed water presence.

## Proposed `surface-water-state-v1`

### Static evidence

- current USGS 3DHP water/flowline network;
- streamflow-permanence attributes when available;
- NWI wetlands;
- DEM-derived drainage;
- known ponds/water bodies.

3DHP should be preferred over retired NHD where current 3DHP coverage exists.

### Dynamic evidence

- recent QPE;
- drought;
- soil-moisture context;
- stream gauge as regional/off-property proxy;
- operator observation of water present/absent.

### Output classes

Per feature/location:

- mapped perennial/intermittent/unknown source state;
- DEM-derived drainage only;
- recently wet/dry context;
- observed water present/absent when actually observed;
- persistence confidence;
- source provenance.

Do not call this deer water preference.

## Exit gate

Deer modules can distinguish mapped/observed usable-water evidence from mere drainage geometry.

---

# Batch 8 — Explicit human-activity and hunting-pressure evidence

Priority: P1  
Ledger dependencies: FW-D10–D13, D17.

## Objective

Represent actual recent human/hunting activity rather than treating access geometry as pressure.

## New observation/event schema

A guarded property event table should support:

- hunter presence;
- stand use;
- access trip;
- vehicle/ATV presence;
- farm operation;
- recreational presence;
- unknown human activity.

Fields:

- geometry;
- start/end or observed time;
- event type;
- source;
- direct observation vs inferred/recorded;
- confidence;
- notes;
- optional related stand/trail/access feature.

## Neutral `human-activity-context-v1`

Derive, without deer semantics:

- distance to recent events;
- time since most recent event;
- count/duration within recent windows;
- diel overlap;
- access route context.

No deer-specific decay function belongs here.

## Deer risk module

The later deer module can apply study-backed temporal/localized responses from FW-D10–D13.

## Exit gate

A hunting-risk module is unavailable when actual pressure evidence is unavailable. “Season open” alone may gate possible hunting but cannot create pressure magnitude.

---

# Batch 9 — Machine-readable science relationship registry

Priority: P0 for deer-specific evaluation  
Can begin in parallel once the neutral contracts are stable.

## Proposed artifact

`deer-relationship-registry-v1`, preferably code-reviewed and versioned in the repository.

Each relationship record:

- relationship ID;
- ledger IDs;
- source citations;
- response variable;
- required inputs;
- allowed input evidence states;
- biological-state gates;
- spatial scale;
- temporal scale;
- movement-state gate;
- sex/age/reproductive gate;
- transformation / relationship form;
- direction;
- threshold/nonlinearity if supported;
- coefficient-transfer status;
- parameter source/version;
- null/blocked conditions;
- output kind;
- limitations.

## Output-kind vocabulary

- `quantitative_relative_selection`
- `ordinal_directional`
- `mechanism_context`
- `negative_constraint`
- `not_applicable`
- `insufficient_input`

## Machine checks

CI should reject:

- a relationship without ledger IDs;
- a numeric coefficient when coefficient-transfer status is false;
- a relationship missing required biological state;
- a blocked universal assumption;
- stale/unavailable required input being silently accepted;
- a module whose scale does not match its input product.

## Exit gate

The science ledger has a testable machine representation; deer logic is no longer hidden in ad hoc code.

---

# Batch 10 — First deer-science evaluation modules

Priority: P0 after required inputs.

Implement modules independently.

## 10A — thermal-resource tradeoff

Evidence: FW-D01, D02, D03, D20.

Inputs:

- thermal exposure;
- diel state;
- season;
- canopy/structure;
- forage/resource state;
- biological scenario.

Initial output should be ordinal/directional unless a coefficient-transfer review authorizes quantitative parameters.

## 10B — agriculture-resource response

Evidence: FW-D08, D09, D15, D16.

Inputs:

- crop identity;
- crop phenology / harvest;
- alternative browse/resource context;
- season/diel;
- movement state.

Do not apply dispersal findings to resident adults.

## 10C — mast response

Evidence: FW-D07.

Inputs:

- mast-producing tree capacity;
- annual mast state;
- season;
- distance/availability.

## 10D — localized hunting-risk response

Evidence: FW-D10–D13.

Inputs:

- actual pressure events;
- diel period;
- sex;
- food/resource context.

Must abstain if pressure is unknown.

## 10E — terrain/movement-state context

Evidence: FW-D14, D15.

Inputs:

- terrain form;
- forest/canopy context;
- roads/access;
- movement state;
- scale.

This module should often return `context-conditional` rather than a sign because the literature documents direction reversal.

## 10F — water/hydrology context

Evidence: FW-D15, D19.

Use conservatively. Riparian selection during dispersal and semiarid water visitation are not universal resident-deer water rules.

---

# Batch 11 — `deer-science-context-v1`

Priority: first production deer-model milestone.

## Input

- property;
- timestamp/date;
- requested biological scenario;
- current neutral product identities.

## Output

For each module:

- status;
- applicability;
- spatial artifact or summary;
- output kind;
- direction or quantitative value if authorized;
- input freshness;
- input evidence classes;
- relationship IDs;
- source-study IDs;
- biological-state assumptions;
- scale;
- limitations;
- abstention reason where relevant.

## No universal score

v1 should not sum unlike outputs.

A location might be:

- favorable under the thermal-resource module;
- unknown under hunting pressure;
- conditionally relevant under terrain;
- strongly resource-linked under mast;

without those becoming “82/100 deer score.”

## Presentation

Owner-facing output can support maps where authorized. Viewer restrictions on fine structure must still apply to downstream products as required.

The output should explain why a module fired and what would change it.

---

# Batch 12 — Quantitative coefficient transfer and synthesis

Priority: P2, after module architecture works.

## Objective

Move selected modules from ordinal relationship form to quantitative relative-selection output without inventing weights.

## Process

For each candidate relationship:

1. retrieve full original model specification;
2. record coefficient, SE/CI, covariance where available;
3. record variable units, scaling, centering and availability design;
4. compare geography/population/season/sex/movement state with target use;
5. identify multiple comparable studies where possible;
6. harmonize effect scales;
7. construct a meta-analytic or Bayesian prior distribution when defensible;
8. document coefficient transfer decision;
9. version parameters independently of code.

## Rule

No arbitrary normalization weights are allowed to substitute for missing scientific parameters.

Where coefficients cannot be transferred, retain module-specific ordinal/directional output.

## Potential later product

`deer-relative-selection-v1`

This should only combine modules whose response scale and parameter interpretation are compatible.

---

# Batch 13 — Transfer validation and calibration

This is validation of imported science, not discovery of basic deer ecology.

## Local evidence

Possible inputs:

- camera detections;
- sightings;
- tracks/sign;
- bed observations;
- rub/scrape observations;
- feeder use;
- explicit pressure events;
- water observations.

## Uses

- check calibration;
- identify local transfer failure;
- refine local parameter priors;
- compare scenarios;
- quantify false positives/negatives.

## Prohibited interpretation

Failure on one property does not automatically falsify the published relationship; it may indicate:

- wrong biological state;
- wrong scale;
- poor input proxy;
- coefficient transfer failure;
- missing interacting resource/risk variable;
- observation bias.

---

# Source-specific implementation decisions

## NOAA HRRR

Use for current/hourly meteorological forcing subject to implementation spike.

Store only the subset needed for Farm Watch rather than bulk model archives.

Fields of interest include:

- T02M;
- DP2M/RH2M;
- U10M/V10M;
- DSWF;
- total cloud where useful;
- precipitation.

## NASA Daymet

Keep for historical daily context and longer historical environmental comparison.

Do not use it as an hourly thermal substitute.

## USDA CDL

Use for annual crop identity.

The 2025 national CDL was released February 27, 2026; spatial resolution increased to 10 m beginning with 2024.

Annual crop identity is not crop phenology.

## NASA HLS Vegetation Indices

Use as a candidate time-series source for field vegetation state / phenology.

Cloud, observation support and time-series gaps must remain explicit.

## USFS TreeMap / FIA BIGMAP

Use as modeled species-capacity evidence.

Do not present an imputed 30 m species raster as observed property tree inventory.

## Kentucky Mast Survey

Use as annual regional/site mast-production evidence.

Keep site/region scope explicit. A statewide or survey-site rating is not property mast abundance.

## USGS 3DHP

Prefer current 3DHP hydrography over retired NHD where coverage exists.

Use permanence attribution when available but preserve source scope. Current water presence may still require dynamic or observed evidence.

---

# Priority order

## P0 — unblock scientifically meaningful first deer output

1. meteorological forcing;
2. solar exposure;
3. thermal exposure;
4. diel/photoperiod;
5. regional breeding-state review + biological-state contract;
6. field phenology;
7. science relationship registry;
8. first thermal/resource/agriculture modules;
9. `deer-science-context-v1`.

## P1 — materially improve decision quality

10. mast resource context;
11. horizontal visibility;
12. human-activity / pressure observations;
13. mast and localized-risk modules;
14. surface-water state.

## P2 — quantitative sophistication

15. browse-resource proxy;
16. coefficient recovery/meta-analysis;
17. quantitative relative-selection synthesis;
18. local calibration/validation;
19. broader multi-property rollout.

---

# Acceptance gates before any deer-specific production release

A deer-specific release is not complete unless:

- every biological term cites ledger IDs;
- exact neutral input identities are retained;
- stale/proxy/unavailable states survive into output;
- no blocked assumption appears;
- no unapproved numeric coefficient is used;
- state/sex/age/movement gates are explicit;
- module scale is explicit;
- output provenance lists study and relationship versions;
- owner/viewer privacy rules remain intact;
- database/contract changes pass:
  - `agent_contract.assert_tool_registry_integrity_v1()`
  - `agent_contract.assert_architecture_doctrine_v1()`;
- all fine-grid artifact reads validate checksum and contract;
- no browser-side raw-data recomputation is reintroduced.

---

# First implementation milestone

The first production milestone should **not** be “predict where deer are.”

It should be:

> For a named date/time and explicit deer scenario, Farm Watch can evaluate a set of published-science relationship modules against current, centrally materialized property evidence; each module returns its own supported direction/context or abstains, with complete provenance and no arbitrary composite weighting.

A representative result might say:

- thermal/resource: applicable, current, relative cooler-refuge condition during hot midday;
- crop resource: unknown because current field phenology is unsupported;
- mast: regional proxy available;
- hunting risk: insufficient input because no recent pressure event is documented;
- terrain: context-conditional, no universal ridge/draw sign;
- water: contextual only;
- reproductive movement: applicable only under the selected male/age/rut scenario.

That is already materially more scientifically defensible than a conventional habitat-score overlay and creates a stable platform for later quantitative synthesis.

---

# Current production milestone — Batches 1–3 complete

The neutral meteorological/solar/thermal chain is now production-operational for `validation-property-01`:

1. property-grade HRRR meteorological forcing;
2. static Solar Terrain v3 with complete authoritative elevation support;
3. date-specific Solar Exposure v1;
4. HRRR-bound Thermal Exposure v1;
5. Diel/Photoperiod Context v1 and Deer Biological State v1 with Kentucky regional breeding context kept separate from individual reproductive state.

The chain remains neutral: no operative temperature, composite thermal score, deer-use inference, or habitat label is produced.

# Recommended next implementation batch

Complete **Batch 4 — dynamic agricultural resource state** in dependency order:

1. merge/deploy **Batch 4A** only after CI and explicit deployment authorization; this creates the service-only HLS field-observation persistence and fail-closed field-state contract but intentionally leaves phenology/harvest unknown;
2. implement **Batch 4B** using the protected GitHub Actions OIDC → Farm Watch worker pattern for HLS raster sampling, with explicit Earthdata/catalog/download failure states and no browser-side HLS processing;
3. validate an evidence-backed time-series method for standing/active crop, senescence, probable harvest transition, and post-harvest/residual before enabling those labels;
4. keep CDL/CSB as annual identity and NASS/state crop-progress as regional context rather than field truth;
5. preserve operator observations as separate evidence/override provenance rather than silently mixing them into remote-sensing truth.

The machine-readable deer relationship registry remains downstream of explicit biological state and the neutral resource-state inputs required by its first modules.
