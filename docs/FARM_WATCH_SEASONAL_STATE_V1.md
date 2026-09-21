# Farm Watch Seasonal State v1

Status: production operational  
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

- precipitation: `proxy` — configured QPE sample `qpe_2_0` is about 17.1 km away; the latest daily snapshot is 2026-09-19, exactly at the 2-day freshness boundary;
- drought: `known` — latest available map vintage is 2026-09-15 and the property point is outside mapped D0+ polygons;
- stream: `proxy` — USGS gauge 03289500 is about 8.8 km away with a same-day provisional discharge observation;
- root-zone soil moisture: `proxy` — nearest available Crop-CASMA/SMAP context is about 17.1 km away, observed 2026-09-17;
- state fieldwork: `stale` under the 14-day contract — latest Kentucky week ending 2026-09-06;
- regional crop progress: `proxy` — latest usable gridded layer week ending 2026-09-13;
- state crop stage: `proxy` — latest Kentucky stage observations week ending 2026-09-13;
- mapped crop context: `stale` for current-crop identity — resource-edge evidence currently carries 2025 CDL classes.

The first read-only integration test initially assumed precipitation was unavailable because the convenience current view was null. The resolver correctly found the underlying daily QPE history instead; this is why Seasonal State reads the authoritative snapshot tables directly.

These are verification expectations, not a persisted canonical result. Production state should be recorded only after deployment and successful materialization.

## Pre-deployment integration validation — 2026-09-21

The migration was executed against the live production schema inside a single PostgreSQL transaction and explicitly rolled back.

The test exercised:

- migration DDL and function creation;
- the real `validation-property-01` resolver path for 2026-09-21;
- all eight component-state classifications;
- aggregate `partial` status;
- snapshot refresh/upsert;
- stored identity generation;
- read-back through the guarded seasonal-state reader.

The expected live classification passed with six current `known`/`proxy` components and two `stale` components.

A post-test catalog check confirmed that the rollback left no seasonal-state table or function in production.

## Operational refresh

The validation property is refreshed once daily through `pg_cron` using the database-native resolver:

- job name: `farm-watch-seasonal-state-pilot-v1`;
- schedule: `5 14 * * *` (14:05 UTC);
- target: `validation-property-01`;
- as-of date: database `current_date`.

The schedule is intentionally after the daily QPE snapshot at 12:30 UTC and both Crop-CASMA root-zone collector passes at 13:20 and 13:32 UTC. It also follows the 13:42 UTC hourly stream-collector invocation closely enough to consume the morning hydrologic state without turning the seasonal snapshot into an hourly identity churn surface.

Weekly fieldwork, crop-stage, crop-progress, and drought sources may update later in the day; those changes enter the next morning's snapshot. Their own freshness and observation dates remain explicit in the stored context.

## Production validation — 2026-09-21

Seasonal State v1 is live for `validation-property-01`.

Current persisted snapshot:

- as-of date: `2026-09-21`;
- aggregate status: `partial`;
- identity SHA-256: `3a18a57521082af098a4cf4a8ecc5c7b8f316698e27f81ea743b148ebf87b209`;
- source-signature SHA-256: `e6c0ca86703c5f9883c39e60373ae4a31d40f614be9e1e2ac1a38782c9e65f89`;
- component counts: 6 current `known`/`proxy`, 2 `stale`, 0 `unavailable`;
- `scoring_performed=false`;
- `behavioral_inference_performed=false`.

Current component states:

- precipitation: `proxy`;
- drought: `known`;
- stream: `proxy`;
- root-zone soil moisture: `proxy`;
- state fieldwork: `stale`;
- regional crop progress: `proxy`;
- state crop stage: `proxy`;
- mapped crop context: `stale`.

The production refresh consumed a same-day provisional USGS stream observation and a 2026-09-18 Crop-CASMA/SMAP root-zone observation; freshness classification remained consistent with the contract.

Operational controls:

- cron job `farm-watch-seasonal-state-pilot-v1` is active as job 76;
- schedule: `5 14 * * *`;
- anonymous and authenticated roles have no execute privilege on either seasonal-state public RPC;
- `service_role` retains execute privilege;
- both Scout architecture assertions pass.

Supabase's security advisor reports an INFO-level `rls_enabled_no_policy` notice for the seasonal-state table. This is expected: RLS is enabled and no end-user policy exists because direct table access is intentionally restricted to `service_role`.

## Evidence boundary

Seasonal State v1 sets:

- `evidence_class=deterministic_derived`;
- `scoring_performed=false`;
- `behavioral_inference_performed=false`.

A future deer-use hypothesis may consume this snapshot only as a separately identified input. That layer must preserve stale/unavailable states and must not convert a regional proxy into direct property truth.
