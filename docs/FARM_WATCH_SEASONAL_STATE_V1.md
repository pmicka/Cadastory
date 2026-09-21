# Farm Watch Seasonal State v1

Status: implementation candidate  
Validation property: `validation-property-01`

## Purpose

Seasonal State v1 is the dated evidence layer between Farm Watch's centrally stored physical context and any future biological hypothesis.

It answers a deliberately narrow question:

> What environmental and agricultural state is currently documented, proxied, stale, or unavailable for this property as of a specific date?

It does **not** answer where deer are, where they travel, where they bed, whether mapped crops are currently forage, whether water is usable, whether hunting pressure is high, or what management action should be taken.

## State vocabulary

Every component is independently classified as exactly one of:

- `known` — a current source directly supports the mapped/source state at the component's stated scope;
- `proxy` — the source is current enough to use, but it is regional, modeled, off-property, synthetic, or otherwise not direct property truth;
- `stale` — evidence exists but is outside the component freshness contract or represents an older annual crop vintage;
- `unavailable` — no defensible input is available for the requested date and configured scope.

Missing inputs are not imputed.

The aggregate row status is:

- `available` only when every component is current `known` or `proxy`;
- `partial` when at least one current component exists but another is stale or unavailable;
- `unavailable` when no component is current enough to be `known` or `proxy`.

## Central storage

`farm_watch.property_seasonal_state_v1` is keyed by:

- property;
- `as_of_date`.

Each snapshot stores:

- the neutral context JSON;
- property-boundary SHA-256;
- exact selected-source fingerprint SHA-256;
- source-signature SHA-256;
- algorithm and output-schema versions;
- final identity SHA-256;
- retrieval timestamp.

The source fingerprint includes the exact selected observations or source vintages, not merely table names. Corrections or changed upstream rows therefore produce a different seasonal-state identity when refreshed.

A property-boundary change invalidates the stored snapshot on read.

## Component contracts

### Precipitation

Source:

- `hydrology.precip_sample_points`;
- `hydrology.precip_daily_snapshots`.

Method:

- nearest active configured sample point within 25 km;
- latest daily snapshot on or before the requested date;
- 1-, 7-, and 30-day accumulated precipitation from the daily history.

Freshness: 2 days.

State semantics: current observations remain `proxy`, because this is remote/grid precipitation context at the nearest configured sample point, not a parcel rain gauge.

### Drought

Source:

- `hydrology.drought_areas`.

Method:

- latest available U.S. Drought Monitor vintage on or before the requested date;
- point-in-polygon classification at the property anchor;
- if the map vintage contains drought polygons but the property point intersects none, the output records `none_mapped`.

Freshness: 9 days.

State semantics: current map classification is `known` at the map's regional-classification scope. `none_mapped` means only that the property point is outside mapped D0+ polygons in that vintage; it is not measured soil moisture.

### Stream state

Source:

- `hydrology.stream_gauges`;
- `hydrology.stream_observations`.

Method:

- nearest active gauge within 25 km;
- latest discharge observation on or before the requested date.

Freshness: 1 day.

State semantics: always `proxy` while current because an off-property gauge does not measure property water depth, crossing condition, or flow.

### Root-zone soil moisture

Source:

- `hydrology.field_soil_moisture_context`.

Method:

- newest modeled observation on or before the requested date within 30 km;
- nearest row breaks ties within the newest observation date.

Freshness: 7 days.

State semantics: always `proxy`. The current source is Crop-CASMA / SMAP model-assimilated regional root-zone volumetric water content, not an in-field sensor.

### State fieldwork / soil moisture

Source:

- `agriculture.state_fieldwork_context`.

Method:

- latest state weekly report on or before the requested date.

Freshness: 14 days.

State semantics: `proxy`. Days suitable for fieldwork and statewide topsoil/subsoil distributions do not establish property conditions.

### Regional gridded crop progress

Source:

- `agriculture.crop_progress_layers`.

Method:

- latest usable week on or before the requested date;
- retains crop/metric values, grid resolution, radius, and the source's synthetic-data flag.

Freshness: 14 days.

State semantics: `proxy`. These NASS grids are synthetic regional representations of confidential survey data and do not establish a specific field's crop stage or condition.

### State crop stage

Source:

- `agriculture.state_crop_stage_observations`.

Method:

- latest state reporting week on or before the requested date.

Freshness: 14 days.

State semantics: `proxy`. Statewide stage percentages are not field observations.

### Mapped crop context

Source:

- current `farm_watch.property_resource_edge_context_v1`.

The resolver consumes this through the existing identity-aware resource-edge reader rather than reading a stale row blindly.

State semantics:

- same-year CDL crop composition: `known` only as mapped crop/land-cover identity for that year;
- older CDL year: `stale`;
- a persisted resource-edge identity mismatch: `stale`;
- a crop vintage later than the requested as-of year: `unavailable`.

Even a `known` mapped crop class does not establish standing crop, harvest state, forage quality, access, or wildlife use.

## Current pre-deployment expectation — 2026-09-21

Live source inspection before deployment indicates the validation property should currently resolve to a **partial** state:

- precipitation: `unavailable` — no active configured QPE sample point was found within the 25 km contract radius;
- drought: `known` — latest available map vintage is 2026-09-15 and the property point is outside mapped D0+ polygons;
- stream: `proxy` — USGS gauge 03289500 is about 8.8 km away with a same-day provisional discharge observation;
- root-zone soil moisture: `proxy` — nearest available Crop-CASMA/SMAP context is about 17.1 km away, observed 2026-09-17;
- state fieldwork: `stale` under the 14-day contract — latest Kentucky week ending 2026-09-06;
- regional crop progress: `proxy` — latest usable gridded layer week ending 2026-09-13;
- state crop stage: `proxy` — latest Kentucky stage observations week ending 2026-09-13;
- mapped crop context: `stale` for current-crop identity — resource-edge evidence currently carries 2025 CDL classes.

These are verification expectations, not a persisted canonical result. Production state should be recorded only after deployment and successful materialization.

## Evidence boundary

Seasonal State v1 sets:

- `evidence_class=deterministic_derived`;
- `scoring_performed=false`;
- `behavioral_inference_performed=false`.

A future deer-use hypothesis may consume this snapshot only as a separately identified input. That layer must preserve stale/unavailable states and must not convert a regional proxy into direct property truth.
