# Farm Watch Meteorological Forcing v1

Status: production — deployed 2026-09-21  
Validation property: `validation-property-01`

## Purpose

Meteorological Forcing v1 provides a centrally persisted, property-targeted hourly weather-model state for downstream neutral physical modeling such as solar and thermal exposure.

It does **not** describe deer movement, habitat quality, bedding, feeding, hunting conditions, or management value.

The v1 collector intentionally stores **HRRR f00 analysis** only. The schema records `source_state` and forecast lead explicitly so a later forecast extension cannot silently masquerade as current analyzed forcing.

## Source

Primary source:

- authority: NOAA / NCEP;
- model: High-Resolution Rapid Refresh (HRRR) CONUS;
- nominal grid: approximately 3 km;
- source transport: NOAA Open Data GRIB2 + sidecar `.idx`;
- acquisition: HTTP byte-range requests for only the required GRIB records.

Source model slug:

`noaa-hrrr-conus-3km`

The collector does not download or persist the full HRRR GRIB file. It retrieves the small text index, identifies the exact required records, and byte-ranges those records from the authoritative NOAA object.

The decoder implementation is pinned to `@azohra/meteo.grib@0.1.4`. That library is a decoding dependency only; NOAA remains the data authority.

## Product contract

Algorithm:

`noaa-hrrr-nearest-grid-analysis-v1`

Output schema:

`farm-watch-meteorological-forcing-v1`

Evidence class:

`modeled_environmental_proxy`

The nearest HRRR grid point must be within 5 km of the property target point.

## Stored forcing fields

The v1 collector resolves these f00 analysis records:

| Output | HRRR record | Stored units |
| --- | --- | --- |
| air temperature | `TMP:2 m above ground` | °C |
| dew point | `DPT:2 m above ground` | °C |
| relative humidity | `RH:2 m above ground` | % |
| grid-relative U wind | `UGRD:10 m above ground` | m/s |
| grid-relative V wind | `VGRD:10 m above ground` | m/s |
| downward shortwave | `DSWRF:surface` | W/m² |
| downward longwave | `DLWRF:surface` | W/m² |
| total cloud cover | `TCDC:entire atmosphere` | % |
| precipitation rate | `PRATE:surface` | mm/hr |

HRRR 10 m wind is grid-relative on its Lambert conformal grid. The collector retains the source grid-relative U/V values, rotates them to true east/north using the HRRR Lambert definition, then derives wind speed and meteorological “from” direction.

The rotation constants are explicit:

- orientation: 262.5°;
- standard latitude: 38.5°;
- tangent-cone constant: `sin(38.5°)`.

## Analysis versus forecast

The storage schema supports:

- `analysis`;
- `forecast`.

Batch 1 collector behavior is deliberately narrower:

- source state: `analysis`;
- file: `wrfsfcf00`;
- forecast lead: 0 hours;
- `valid_at = reference_time`.

The database independently enforces those analysis semantics.

A future forecast collector may reuse the table only if it preserves:

- reference/run time;
- positive lead;
- valid time;
- source state = `forecast`;
- exact source identity.

## Central persistence

Table:

`farm_watch.property_meteorological_forcing_v1`

Primary identity dimensions:

- property;
- valid time;
- source model;
- source state.

Each row also stores:

- reference time;
- forecast lead;
- target coordinates;
- sampled HRRR grid coordinates;
- nearest-grid distance;
- exact source GRIB URL;
- SHA-256 of the complete HRRR index text;
- SHA-256 of selected-record descriptors plus sampled values;
- property-boundary SHA-256;
- algorithm/schema versions;
- final identity SHA-256;
- retrieval timestamp.

The final identity therefore changes when the selected source run/records, sampled grid state, property boundary, or product contract changes.

## Read semantics

`farm_watch_get_meteorological_forcing_v1_internal` resolves the newest row at or before the requested valid time for the requested source state.

Responses are:

- `available` — within the requested maximum age;
- `stale` — older than the requested maximum age but still returned as explicit stale evidence;
- `missing` — no row exists.

A property-boundary or product-contract change invalidates the row and returns stale with context withheld.

Staleness relative to a query time is different from invalidation: an old but internally valid forcing row remains inspectable as stale evidence.

## Source selection

The collector floors current UTC time to the hour and searches backward over a bounded lookback window for the newest HRRR f00 index that:

1. exists;
2. parses correctly;
3. contains every required analysis record.

The source cycle is selected once per collector run and reused for all requested Farm Watch targets.

Required GRIB fields are decoded once per source field and sampled for all target properties before moving to the next field. This avoids repeating full HRRR field decoding per property.

## Source and field validation

Persistence rejects:

- malformed source state;
- nonzero lead for an analysis row;
- valid/reference-time mismatch;
- unsupported source model;
- non-NOAA HRRR source URL;
- invalid SHA-256 identities;
- incomplete/non-numeric required forcing fields;
- RH or cloud cover outside 0–100%;
- negative wind speed, radiation, or precipitation rate;
- wind direction outside [0,360);
- grid points beyond 5 km;
- disagreement between forcing JSON and persisted source/grid metadata;
- scoring or behavioral inference.

## Security

The table is RLS-enabled with no end-user policy.

Direct table privileges and internal RPC execution are restricted to `service_role`.

The collector uses the existing custom collector-key path and recorded collector-run lifecycle. It is intended to deploy with `verify_jwt:false`, preserving Scout's established collector authentication posture.

No model-visible MCP tool is introduced by Batch 1.

## Evidence boundary

Every forcing payload sets:

- `scoring_performed=false`;
- `behavioral_inference_performed=false`.

Interpretation boundary:

> HRRR forcing is modeled environmental state at the nearest model grid point. It is not an on-property weather-station observation and performs no deer-use, movement, bedding, habitat-quality, or management inference.

## Relationship to existing environmental products

This product does not replace `property_environment_context_v1`.

The older environment product remains appropriate for historical acquisition-date context using Daymet daily temperature/precipitation plus historical hydrology/drought evidence.

Meteorological Forcing v1 adds hourly current forcing needed by later physical solar/thermal products.

It also does not reuse Scout's generic weather snapshots when those rows are not spatially appropriate for the Farm Watch property.

## Batch 1 exit checks

Before deployment, implementation must pass:

- TypeScript contract checks;
- HRRR URL/cycle/index-record tests;
- UTC date-boundary source-selection tests;
- Lambert wind-rotation tests;
- persistence migration invariants;
- service-only privilege checks in a rollback integration test;
- Scout architecture assertions.

Deployment verification should additionally establish for `validation-property-01`:

- an authoritative current HRRR f00 run is selected;
- the nearest model grid point is within 5 km;
- all required fields decode;
- a persisted analysis row reads back as `available`;
- source/index/record hashes are valid;
- the edge function remains `verify_jwt:false`;
- no deer semantics are present.

## Pre-deployment integration validation — 2026-09-21

The complete migration DDL was executed against the live production schema inside one explicit PostgreSQL transaction and then rolled back.

The rollback test exercised:

- source registration and table/function creation;
- `validation-property-01` meteorological target resolution;
- property-boundary identity binding;
- storage of one contract-valid synthetic HRRR analysis payload;
- `available` read-back within the configured age window;
- `stale` but inspectable read-back outside the age window;
- rejection of an analysis payload with a nonzero forecast lead;
- neutral evidence flags;
- anonymous/authenticated denial and service-role access;
- `agent_contract.assert_tool_registry_integrity_v1()`;
- `agent_contract.assert_architecture_doctrine_v1()`.

A post-rollback catalog check confirmed that production retained:

- no `property_meteorological_forcing_v1` table;
- no Farm Watch meteorological-forcing functions;
- no public meteorological-forcing wrappers;
- no `noaa-hrrr-conus-3km` source row.

That rollback validation preceded deployment. Batch 1 is now deployed and operational in production.

The pre-deployment test validated persistence, security, identity, and read semantics before release.

## Production deployment verification — 2026-09-21

Production components:

- migration `add_farm_watch_meteorological_forcing_v1` applied successfully;
- Edge Function `collect-farm-watch-meteorology` deployed ACTIVE, version 1;
- `verify_jwt=false` preserved because the function uses Scout's established custom collector-key authentication;
- collector route enabled and dispatchable through `ingest.invoke_edge_collector`;
- hourly pilot refresh scheduled as cron job 77, `farm-watch-meteorological-forcing-hourly-v1`, at minute 50 of every hour.

Real HRRR validation for `validation-property-01`:

- selected source: HRRR CONUS f00 analysis at `2026-09-21T17:00:00Z`;
- nearest sampled model grid point: 1,024.1 m from the property target;
- source index SHA-256: `63f1049caa4589947bc4015144b1e8f1a6a7ee38b2a35a695ed15171785e0dc9`;
- selected-record/value SHA-256: `a78f534ace4f6a25626d4c7bd860ae52d4e7e793dd152a395c010726898ea08a`;
- final forcing identity SHA-256: `dcf4e228603989e79e81e8078bb010ddf31a1a385299a0f0399245649da8cb41`.

Validated forcing values at that analysis time:

- air temperature: 27.988489 °C;
- dew point: 20.121164 °C;
- relative humidity: 67.5%;
- true 10 m wind: 1.182671 m/s from 146.577°;
- downward shortwave: 771.4 W/m²;
- downward longwave: 385.7 W/m²;
- total cloud cover: 13%;
- precipitation rate: 0 mm/hr.

The standard dispatcher was exercised successfully after route registration. Anonymous and authenticated table access remain denied; `service_role` access is present. Both Scout architecture assertions passed after deployment.

## Next dependency

Batch 2A, `solar-exposure-context-v1`, may use this forcing product's shortwave/cloud state only after Batch 1 is deployed and validated.

The later `thermal-exposure-context-v1` will combine physical terrain/canopy exposure with meteorological forcing. It must not relabel raw HRRR values as operative temperature.
