# Farm Watch Diel + Deer Biological State v1

Status: implementation candidate — not deployed  
Validation property: `validation-property-01`

## Purpose

Batch 3 introduces two different kinds of state and keeps them deliberately separate:

1. `diel-photoperiod-context-v1` — deterministic physical light/solar timing;
2. `deer-biological-state-v1` — an explicit white-tailed-deer scenario object whose unknown biological dimensions remain unknown.

This layer does not predict where deer are, how fast they move, whether they are bedding, or whether a location is good habitat.

## Product A — Diel / photoperiod context

Product:

`diel-photoperiod-context-v1`

Algorithm:

`farm-watch-diel-photoperiod-v1`

Evidence class:

`deterministic_derived`

### Inputs

- Farm Watch property center or point-on-surface;
- UTC date/timestamp;
- deterministic NOAA-style solar geometry aligned to Solar Exposure v1.

### Date-keyed events

The central date record contains:

- civil dawn;
- geometric sunrise;
- solar noon;
- geometric sunset;
- civil dusk;
- daylight minutes;
- civil-light minutes;
- property anchor and identity.

### Instantaneous solar phase

The instantaneous resolver publishes:

- `night`;
- `morning_civil_twilight`;
- `day`;
- `evening_civil_twilight`.

Definitions are physical:

- day: geometric solar elevation >= 0°;
- civil twilight: -6° <= elevation < 0°;
- night: elevation < -6°;
- morning/evening is determined by solar hour-angle sign.

### Critical boundary

Civil twilight is a light-transition proxy, not a measured deer activity state.

FW-D05 supports crepuscular movement as an important biological form, but individual studies use their own time windows around sunrise/sunset. A later relationship module must cite the specific study contract when translating physical solar time into a deer behavior term.

The neutral diel product therefore does not publish:

- `deer_active`;
- `crepuscular_score`;
- `movement_multiplier`;
- moon-phase effects;
- weather-front effects.

## Product B — Deer biological state

Product:

`deer-biological-state-v1`

Algorithm:

`farm-watch-deer-biological-state-v1`

Species:

`Odocoileus virginianus`

### Explicit scenario dimensions

- sex: `male | female | unknown`;
- age class: `juvenile | yearling | adult | unknown`;
- movement state: `resident | dispersal | unknown`;
- individual reproductive state:
  - `unknown`;
  - `nonbreeding`;
  - `estrus`;
  - `pregnant`;
  - `parturition`;
  - `lactation`;
- deterministic diel state;
- meteorological season;
- regional reproductive context;
- state provenance;
- confidence;
- applicable relationship IDs.

No unknown biological dimension is imputed.

## Kentucky regional breeding evidence

### FW-D21 — active Kentucky gate

University of Kentucky Forestry and Natural Resources states that Kentucky white-tailed deer breed from October through January and that peak breeding activity usually occurs in mid-November:

https://forestry.mgcafe.uky.edu/deer

Kentucky Department of Fish and Wildlife Resources independently describes its season beginning in mid-November as designed to coincide with peak fall breeding:

https://fw.ky.gov/News/Pages/Kentucky%E2%80%99s-Modern-Gun-Deer-Season-Opens-Nov.-13.aspx

The v1 machine-readable Kentucky row therefore stores:

- breeding start month: October;
- breeding end month: January;
- peak timing label: `mid-November`;
- exact peak start/end date: null.

The resulting regional phases are:

- `outside_documented_breeding_season`;
- `within_documented_breeding_season`;
- `within_peak_month_context`;
- `unavailable`.

`within_peak_month_context` means only that the timestamp lies in November under a source-supported statewide qualitative “mid-November” peak description. It is not an exact peak-day assertion.

### FW-D22 — age-aware female timing form

Green et al. (2017), Illinois:

DOI: 10.1016/j.theriogenology.2017.02.010

The study found later estimated conception timing in fawns than in yearlings/adults.

Farm Watch may therefore preserve maternal age as a relevant state dimension when female age is explicitly known.

The Illinois mean conception dates are not transferred into the Kentucky calendar. The product records:

`coefficient_transfer_authorized:false`.

### FW-D23 — Ohio onset corroboration only

Harder and Moorhead (1980), Plum Brook Station, Ohio:

DOI: 10.1095/biolreprod22.2.185

Active corpora lutea were first observed in mature does collected November 6.

This is retained as lower-Ohio-region physiological context. FW-D23 does not fire as an applicable Kentucky relationship and does not define a Kentucky onset or peak date.

## Regional state is not individual state

This distinction is a hard contract.

Example:

A timestamp in November may resolve to:

`regional_reproductive_context.phase = within_peak_month_context`

while simultaneously resolving to:

`individual_reproductive_state = unknown`

unless the caller explicitly supplies a defensible individual scenario.

Farm Watch must never infer:

- estrus;
- conception;
- pregnancy;
- mating;
- mate searching;
- tending;
- rut movement intensity;

from regional date alone.

## Relationship gates

The biological-state resolver only identifies relationships whose required state dimensions are available enough to be considered later.

Current v1 behavior:

- FW-D05 — retained as the diel/reproductive-state and ordinary-weather negative-constraint anchor;
- FW-D21 — available for Kentucky regional timing;
- FW-D22 — added only for females with a known age class;
- FW-D06 — added only for males with a known age class while regional context is inside the documented Kentucky breeding season;
- FW-D23 — context-only; never an active Kentucky relationship.

Being listed as applicable does not calculate a biological effect. The later relationship registry still decides the permitted transformation, output kind, scale, and abstention logic.

## Central persistence

`farm_watch.property_diel_photoperiod_context_v1`

is keyed by:

- property;
- solar date.

It stores:

- deterministic context;
- property-boundary SHA-256;
- source signature and hash;
- algorithm/schema versions;
- final identity;
- retrieval timestamps.

Boundary or contract changes invalidate the stored row.

## Breeding evidence registry

`farm_watch.deer_regional_breeding_evidence_v1`

supports:

- statewide summaries;
- physiographic-region evidence;
- peer-reviewed reference evidence.

v1 intentionally seeds only a Kentucky statewide qualitative gate.

Exact annual KDFWR physiographic-region conception dates are deferred until the authoritative annual product is captured in a structured, source-controlled form. Secondary reproductions are not silently promoted into canonical dates.

## Access posture

Both new tables are service-role only.

The service-only public wrappers are:

- `public.farm_watch_refresh_diel_photoperiod_v1_internal`;
- `public.farm_watch_get_diel_photoperiod_v1_internal`;
- `public.farm_watch_resolve_deer_biological_state_v1_internal`.

No `anon` or `authenticated` execution is granted.

No Edge Function or browser-side computation is required for v1.

## Acceptance tests

The implementation verifies:

- physical day/twilight/night classification;
- morning/evening twilight direction;
- deterministic meteorological season;
- Kentucky cross-year October–January breeding-season handling;
- November qualitative peak-month handling;
- unknown individual reproductive state remains unknown during regional peak context;
- female age-aware FW-D22 gating without Illinois date transfer;
- male FW-D06 gating requires known age plus breeding-season context;
- Ohio FW-D23 is not an active Kentucky relationship;
- no universal deer/habitat/rut/movement score appears;
- service-only migration posture;
- regional population timing never auto-populates individual reproductive state.

## Explicit non-goals

Batch 3 does not:

- predict deer presence;
- calculate movement probability;
- calculate rut intensity;
- infer estrus or pregnancy from calendar date;
- use moon phase;
- use barometric-pressure folklore;
- assign generic cold-front effects;
- score ridge/draw/saddle terrain;
- infer hunting pressure;
- infer bedding or security cover;
- create a universal habitat score.

## Deployment boundary

This document describes an implementation candidate.

Deployment is a separate explicit action.

Production deployment would require:

1. apply the Batch 3 migration;
2. materialize the current diel date for `validation-property-01`;
3. cross-check SQL solar events against the existing Solar Exposure geometry;
4. resolve an all-unknown deer scenario and verify all biological unknowns remain unknown;
5. resolve explicit female-age and male-age scenarios to verify relationship gating;
6. verify service-only privileges;
7. run Scout tool-registry and architecture-doctrine assertions.

No Batch 4 work is required for Batch 3 deployment.
