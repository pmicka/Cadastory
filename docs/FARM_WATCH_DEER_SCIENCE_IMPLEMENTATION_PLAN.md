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
| `field-phenology-context-v1` | dated field state | CDL/CSB + NASA HLS L30/S30 + NASS regional context | production observation substrate; classifier pending |
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

Status: Batch 4A + Batch 4B production; 180-day growing-season HLS substrate validated; live phenology/harvest classification blocked on current-season crop identity + near-real-time method transfer  
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

Status: Batch 5A production complete 2026-09-25; Batch 5B mast-resource context implemented, with exact-year annual state intentionally unavailable when KDFWR has not published/ingested that survey year  
Priority: P1  
Ledger dependency: FW-D07.

## Objective

Represent mast as:

1. where mast-producing trees plausibly occur; and
2. what annual production state is documented/proxied.

These must remain separate.

## Proposed `mast-resource-context-v1`

### Species-capacity layer

Batch 5A operational v1 source:

- USDA Forest Service FIA BIGMAP 2018 species aboveground biomass at 30 m, sampled through the official Forest Service ArcGIS Online BIGMAP ImageServer over the barrier-aware broad_3000m domain.

Future refinement candidates:

- USFS TreeMap 2023 linked to its FIA tree table;
- future better local forest inventory if available.

Map oak groups relevant to mast:

- white-oak group;
- red-oak group;
- hickory group;
- American beech.

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

FW-D07 can consume an explicit exact-year mast state without pretending canopy density equals acorn availability. If KDFWR has not published/ingested the requested survey year, the annual component must abstain rather than carrying forward the prior year's rating.

## Batch 5B implementation — 2026-09-25

Batch 5B now has a source-controlled neutral `mast-resource-context-v1` contract and central service-only persistence.

Canonical authoritative records currently include the KDFWR 2024 and 2025 Mast Survey reports with published Table 1 values for statewide, East, and West scopes. The validation property has an explicit `west` survey-region relation derived from Figure 4 of the 2025 KDFWR report; that relation is stored as `derived_from_authoritative_map`, not as a KDFWR property observation.

The context keeps three components separate:

1. the Batch 5A `mast-capacity-v1` materialization;
2. the exact-year KDFWR annual mast proxy;
3. dated operator `mast_resource` field observations.

The 2026 row is intentionally `partial`: spatial mast capacity is available, while the annual mast proxy is unavailable because the current KDFWR report index still lists 2025 as the latest report as of 2026-09-25. 2025 values are not carried forward.

The product is also exposed separately in `deer-evidence-stack-v1`; the existing `mast-capacity` product remains independently visible so downstream deer science cannot silently conflate spatial capacity with annual production state.

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

### v1 bounded physics contract

The first implementation consumes the exact barrier-aware `local_500m` domain and current common 5 m structural grid from `landscape-structure-context-v1`, together with the current local 10 m elevation grid from `terrain-form-permeability-v1`. It does not reopen raw COPC/LAZ processing. Rays use 16 equally spaced azimuths (north = 0 degrees, clockwise), a 5 m step, and a 100 m maximum with 10/25/50/100 m summaries. Observer and target heights are equal generic physical scenarios of 1.5 m, 3 m, and 6 m; these are not deer-height assumptions.

Terrain-only, structural-support, and combined obstruction remain separate. Terrain uses complete-four-cell bilinear support; structural obstruction uses the current neutral LiDAR height-band return-share representation at the ray height. Directions leaving the exact domain or lacking required support are explicitly unsupported and excluded from summaries rather than treated as open. The source signature includes all structural, terrain, domain, grid, ray, height, band, threshold, resampling, and edge-policy dependencies so any relevant change invalidates the materialization.

The artifact remains a private checksum-addressed derived product with no browser recomputation and no deer interpretation. Its physical limitations are recorded in the source-controlled contract and artifact provenance.

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
Status: implemented in source as `surface-water-state-v1`; production migration intentionally pending explicit deployment authorization.  
Ledger dependencies: FW-D15, D19; water evidence remains weaker/context-specific.

Implementation:

- source-controlled contract: `supabase/functions/_shared/farm-watch-surface-water-state-contract.ts`;
- date-keyed guarded table/resolver migration: `20260923001000_add_farm_watch_surface_water_state_v1.sql`;
- current 3DHP + NWI hydrology cache is reused rather than recollected;
- current conditioned-D8 `terrain-analysis-v2` is bound as drainage geometry only;
- Batch 4 Seasonal State supplies QPE, drought, off-property gauge, and root-zone moisture with its existing freshness/scope semantics;
- existing private operator observations supply exact-date `surface_water_presence` evidence;
- current 3DHP attributes do not establish perennial/intermittent status, so 3DHP persistence remains `mapped_unknown_persistence` rather than being invented;
- explicit NWI water-regime attributes support mapped persistent/seasonal/temporary classes without being promoted to current water presence;
- v1 retains raw dated wetness context and deliberately does not invent a generic wet/dry threshold.

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
Status: implemented in `deer-relationship-registry-v1`; no production deployment is required for this repository-level contract.  
Can begin in parallel once the neutral contracts are stable.

Implementation:

- source-controlled registry: `supabase/functions/_shared/farm-watch-deer-relationship-registry.ts`;
- ledger-coverage and contract tests: `supabase/functions/_shared/farm-watch-deer-relationship-registry.test.ts`;
- CI: `.github/workflows/farm-watch-deer-relationship-registry-ci.yml`;
- durable contract: `docs/FARM_WATCH_DEER_RELATIONSHIP_REGISTRY_V1.md`;
- Batch 3 `applicable_relationship_ids` now delegates to registry metadata rather than maintaining a separate hard-coded FW-D selector;
- every active biological relationship now carries a study-measurement contract with explicit alignment class and permitted use;
- value/subtype constraints are machine-readable where a generic product binding is insufficient;
- a future module is rejected when a required study variable is only mechanism context or unsupported;
- FW-D04 is explicitly bound to a future research-aligned `low-height-concealment-context` input rather than treating the general Batch 6 horizontal-visibility product as measurement-equivalent;
- FW-D15 is split into spring dispersal probability, dispersal distance, and path-selection relationships so season/path/riparian findings cannot collapse into one generic agriculture rule.

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
- an active biological relationship without a study-measurement contract;
- a numeric coefficient when coefficient-transfer status is false;
- a relationship missing required biological state;
- a blocked universal assumption;
- stale/unavailable required input being silently accepted;
- a module whose scale does not match its input product;
- a future module that omits a required study-measurement contract;
- a future module that omits a study-specific value/subtype constraint;
- activation when a required study variable is only `mechanism_context_only` or `unsupported`.

## Exit gate

The science ledger has a testable machine representation; deer logic is no longer hidden in ad hoc code.

### Study-fidelity hardening — 2026-09-23

A read-only study-fidelity audit after Batch 6 visibility review found that relationship provenance/state/scale controls were stronger than measurement-equivalence controls. Batch 9 was therefore hardened before Batch 10.

Key consequences:

- `thermal-exposure-context` cannot be treated as FW-D01 operative temperature because the current product explicitly does not calculate operative temperature;
- FW-D06 age-dependent male movement remains blocked until age state can distinguish the study's yearling / 2-year-old / 3+ classes;
- FW-D08 requires current corn identity plus the relevant field-level crop stage/harvest state;
- FW-D10 requires a dated stand-specific hunt event and a stand-specific visibility/vulnerability zone rather than generic distance-to-stand;
- FW-D13's negative constraint requires documented low hunting pressure;
- FW-D14 is explicitly juvenile-male dispersal evidence;
- FW-D15 now separates spring dispersal probability, dispersal distance, and dispersal path selection, with riparian geometry kept distinct from current water state;
- FW-D16 is blocked from property evaluation until the published multiscale cover/food design has an aligned representation;
- FW-D17 now preserves the female-only telemetry sample and requires predator-occurrence context;
- FW-D18 requires forest/habitat refuge type in addition to elevation/extreme-event state;
- FW-D19 requires current usable-water-source evidence rather than generic hydrography/product availability.

These are contract blockers, not requests to invent replacement proxies. Batch 10 must abstain until the required alignment is resolved.

### Blocked-measurement resolution — 2026-09-23

The follow-on resolution pass classifies every currently blocked required measurement in `farm-watch-deer-measurement-resolution.ts` and `FARM_WATCH_DEER_MEASUREMENT_RESOLUTION_V1.md`.

Current blocked-measurement disposition counts:

- 21 `reproduce`;
- 9 `calibrated_proxy`;
- 6 `remain_unavailable`.

FW-M02 vegetation height is no longer in the blocked queue. The production-validated `study-aligned-vegetation-height-context-v2` is promoted to `derived_equivalent` for FW-R01. FW-D01 nevertheless remains blocked by operative temperature (FW-M01), forage index (FW-M03), woody canopy (FW-M04), and activity-period fidelity (FW-M05).

The private `deer-evidence-stack-v1` inventory now exposes `study-aligned-vegetation-height-context` metadata/summary alongside the other neutral Farm Watch products; this exposure does not alter relationship applicability or coefficient-transfer status.

The remaining highest-value P0 units are source-faithful male age categories; current corn identity/stage; explicit hunting-event/effort evidence; calibrated stand-vulnerability viewshed; and calibrated Gallina concealment.

A resolution decision does not itself unblock a deer relationship. Registry alignment changes only after that measurement product is actually implemented and validated.

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

Complete the remaining **Batch 4 phenology/harvest classification gate** on top of the now-production HLS observation substrate:

1. use the 17-scene / 629-row production HLS time series to characterize observation spacing, cloud/QA support, and field-specific trajectories without assigning biological or harvest meaning;
2. formalize the transfer review for the Kentucky curve-change method and the NIR+NDVI NHPI method, explicitly separating reusable method form from non-transferable study coefficients/thresholds;
3. define minimum time-series support and ambiguity/abstention rules for `green_up`, `vegetative`, `mature_senescing`, `probable_harvest_transition`, `post_harvest_residual`, and `unknown`;
4. implement classification only where the evidence contract supports it; regional NASS progress remains proxy context and stale CDL/CSB remains annual identity rather than current field truth;
5. preserve operator observations as separate provenance and never silently overwrite remote-sensing evidence.

The production HLS pilot currently has 37/37 fields with current evidence but deliberately retains `phenology_state=unknown` for all 37. The first classifier transfer review found the original 45-day HLS collection window too short for the retained published harvest methods, so the HLS acquisition contract is being expanded to 180 days to preserve the full growing-season trajectory before any classifier is authorized. That is a prerequisite-data problem, not permission to substitute a generic NDVI-drop rule.

The machine-readable deer relationship registry remains downstream of explicit biological state and the neutral resource-state inputs required by its first modules.

## Batch 4 transfer-gate update — 2026-09-22

The protected HLS acquisition window is now 180 days in production. Validation-property run `35691287320` sampled 82 scenes and persisted 3,034 canonical field/scene rows, including 1,136 quality-qualified rows from 2026-03-29 through 2026-09-19. All 37 fields remain current while all 37 correctly retain `phenology_state=unknown`.

The short-trajectory prerequisite is therefore closed. The remaining Batch 4 prerequisites are:

1. verify and ingest a defensible current-season 2026 crop-identity source rather than promoting stale 2025 CDL/CSB identity;
2. select a near-real-time harvest method appropriate to current-state inference. Yang et al. remains Kentucky-specific curve-form evidence; NHPI remains strong retrospective harvest-date evidence but depends on a middle-of-senescence-to-plus-two-month normalization window and a study-calibrated threshold; Tang et al. (2026, DOI `10.1016/j.jag.2026.105510`) is a newer near-real-time Reaped Index candidate but requires additional spectral inputs and a current crop mask.

Published current-season crop-mapping routes now include the 10 m ICDL product (Li et al. 2026, DOI `10.1038/s41597-026-07099-1`) and the HLS Transformer mapper (Zhang et al. 2025, DOI `10.1016/j.rse.2025.114950`). Operational Kentucky ingestion must be verified before either is production evidence.

No generic NDVI drop, stale crop identity, regional NASS progress, truncated NHPI future window, or copied study threshold may close the gate.

## Batch 4 current-season crop identity gate — 2026-09-22

Direct current-year ICDL ingestion was investigated first because it would avoid operating a local crop classifier. The published 2026 ICDL method is scientifically suitable, but a consumable 2026 Kentucky layer could not be operationally verified: the public iCrop catalog discoverable on 2026-09-22 exposes layers only through 2025-August, and no 2026 June/July/August layer was discoverable through the public service surface.

Accordingly, 2025 CDL/CSB remains stale historical crop identity and cannot gate crop-specific harvest logic.

The preferred fallback is the published Zhang et al. (2025) HLS Transformer (`10.1016/j.rse.2025.114950`). Its Apache-2.0 application code and public ~69.9 MB trained model are operationally plausible for the 37-field validation domain, but the model requires two years of richer HLS spectra than the current Farm Watch NDVI/EVI/NIR sampler. If adopted, implement it as a protected field-scoped spectral/inference path rather than reproducing the released whole-tile architecture.

**Next Batch 4 unit:** perform the bounded Transformer integration spike: confirm model reuse terms, enumerate exact HLS band/time inputs and normalization contract, estimate field-scoped IO/inference cost, and define a neutral `current_crop_identity` evidence contract with confidence/abstention. Do not enable harvest classification in the same unit.


## Batch 4 Transformer integration spike — 2026-09-22

The bounded Zhang et al. HLS Transformer spike is complete at the contract/design level.

Findings:

- the model consumes two-year per-pixel HLS time series, not the existing Farm Watch NDVI/EVI/NIR field summaries;
- Landsat inference uses seven reflective bands + DOY; Sentinel-2 uses eleven reflective bands + DOY;
- Landsat thermal bands are read by the released loader but are not crop-model predictors;
- the published QA mask differs from the current Farm Watch vegetation sampler, so model-faithful spectral collection must remain a separate protected path;
- the released model returns raw 50-class logits and does not provide calibrated per-pixel prediction probabilities;
- the paper does not publish a validated field-level consensus threshold for converting pixel labels into one accepted field crop identity;
- the validation-property footprint is ~1,135 30 m pixel areas across 37 fields, about 1/11,800 of a full HLS tile, making field-scoped inference architecturally plausible;
- a fully padded field-pixel inference tensor is ~36.6 MiB, compared with ~869 MiB for the full 3 km-domain bounding rectangle;
- the known March–September 2026 scene set accounts for ~912 required COG band-window reads; because the model needs a full previous year plus current year from January 1, the conservative absolute two-year upper bound at the released 176-period-per-sensor capacity is ~7,040 reads;
- model execution was not benchmarked because the exact Zenodo model-artifact rights/license was not independently verified. Code is Apache-2.0 and the paper is CC BY 4.0, but public download availability is not treated as permission to vendor/run the trained artifact.

A neutral `current-crop-identity-v1` contract is now source-controlled. It supports candidate predictions, uncalibrated field-support diagnostics, explicit abstention, and blocks crop predictions from becoming harvest or deer inference.

**Next Batch 4 unit:** resolve the trained-model rights gate and, if authorized, implement a non-persistent field-scoped spectral/inference prototype for the validation property. That prototype should emit candidate pixel/field class distributions only; field acceptance and harvest classification remain separate gates.


## Batch 4 trained-model rights gate — 2026-09-22

The Zhang et al. trained-model artifact on Zenodo record `10.5281/zenodo.14715402` remains blocked for Farm Watch execution.

The exact public Zenodo record was reviewed. It exposes the model file and describes the dataset/model contents, but its rendered metadata does not expose a Rights/License section. Zenodo's own guidance states that permission for reuse is determined by the license conditions shown in that Rights section. The Apache-2.0 license in the GitHub repository applies to the application code; it is not assumed to license the separately deposited `.h5` weights. The CC BY 4.0 paper and the authors' statement that the trained model is publicly available support intended openness but do not replace an explicit model-artifact license.

Contract state is now `blocked_no_record_license`.

**Next Batch 4 unit:** obtain explicit trained-model permission/license clarification. Until that clears, do not download, vendor, redistribute, or execute the model artifact. If permission is obtained, the next implementation unit remains the non-persistent field-scoped inference prototype with candidate-only output and no harvest promotion.

## Batch 5A source-transport resolution — 2026-09-24

The neutral mast-capacity implementation remains merged/deployed, and the prior cloud source-access failure is now bounded by an operator-assisted transport path rather than a Farm Watch architecture change.

The failed cloud routes remain documented: the legacy Geoplatform ImageServer returns HTTP 403 to GitHub-hosted Actions; the official Forest Service ArcGIS Online BIGMAP ImageServer cannot currently be DNS-resolved from Supabase Edge; and a direct GitHub Actions fetch to that host fails before an ArcGIS response.

A workstation fallback was validated using the official Forest Service Raster Data Gateway. The owner downloads the official per-species archive locally, verifies/extracts it, and crops only the current Farm Watch native-grid broad-domain bounding window before any transport into the cloud path. White oak SPCD 0802 proved the contract end to end at the source boundary: the official 89,932 × 91,150, 30 m Float32 CONUS raster cropped exactly to source window `42166,43231,206,222`, bounds `957150,1752060,963330,1758720`, with zero reprojection/resampling. The resulting bounded TIFF was 100 KB with SHA-256 `b9cfdb257ae7c55e5ada6bbf1ef20305ddc04eb61e16cb517edeee4d9cca3045`.

The implementation now includes a source-controlled Debian crop/manifest helper and a draft-release handoff into the existing GitHub OIDC materializer. The draft release is ephemeral transport for bounded official source crops only; it is not a national source cache and should be deleted after successful materialization.

Batch 5A production validation completed on 2026-09-25. All 28 required species crops were validated and bundled on the operator workstation, the bounded bundle was transferred through the owner-only GitHub workflow, and the protected Supabase worker completed the canonical `mast-capacity-v1` materialization for `validation-property-01`.

Production identifiers:

- materialization ID: `4815b4fb-20c6-4f46-bb3c-1dc145bb31d5`;
- artifact SHA-256: `7b20a6b46673ebee42df42ce090dafcbcf8c151bcc72911421dc8967496f3834`;
- landscape-domain identity: `bd69c24e98c485a9320c07db036548c4b065a2c381e77f2ab5cd73fc73e9ae5f`;
- sampled species count: 28;
- transport provenance: `operator_workstation_usfs_raster_gateway_bounded_crop`;
- raw national source persistence: false.

The final production handoff also verified two operational controls: draft-release assets are downloaded by resolved asset ID, and `workflow_dispatch` OIDC trust is authorized only for the mast-capacity workflow while the remaining trusted Farm Watch workflows retain their existing `issues`-only event gate.

Batch 5A is therefore **complete for the validation property**. Batch 5B may proceed independently as annual/regional mast-state evidence and must not collapse into or overwrite the modeled species-capacity semantics established here.
