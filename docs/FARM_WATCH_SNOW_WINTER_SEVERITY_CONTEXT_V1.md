# Farm Watch Snow / Winter Severity Context v1

Status: production deployed and validated — 2026-09-25

## Purpose

`snow-winter-severity-context-v1` resolves **FW-M08** for the DelGiudice, Fieberg & Sampson (2013) winter dense-conifer relationship.

It is a neutral physical environmental product. It does **not** infer deer movement, dense-cover use, bedding, mortality risk, habitat quality, or management value.

## Source-study measurement

The DelGiudice et al. winter models used two daily physical covariates directly:

- snow depth in centimeters;
- minimum daily temperature in degrees Celsius.

The study telemetry winter ran from 1 November through 14 May.

Minnesota's winter-severity index (WSI) was additional source context rather than a replacement for those model covariates. The source WSI accumulated:

- one point on a day with snow depth at least 38 cm;
- one point on a day with ambient minimum temperature at or below -17.7 °C;
- during November through May.

Farm Watch preserves this distinction.

## Farm Watch source reconciliation

### Snow depth

Primary source:

- source slug: `noaa-nohrsc-national-snow-analysis`;
- authority: NOAA / National Weather Service / NOHRSC;
- product: operational National Snow Analysis snow-depth mosaic;
- acquisition: property-targeted ArcGIS identify request;
- support: approximately 1 km² modeled/assimilated snow-analysis support;
- cadence: one Farm Watch point sample per day.

NOHRSC combines ground, airborne and satellite observations with physically based snow modeling. The Farm Watch value is therefore a modeled/observationally assimilated snow-depth estimate, not an on-property ruler measurement.

Only the property point value, source valid/ingest timestamps, source-object identifier, payload hash and provenance are persisted. No raw raster is copied to Postgres.

### Minimum daily temperature

Primary source:

- source slug: `noaa-hrrr-conus-3km`;
- authority: NOAA / NCEP;
- existing Farm Watch source: centrally persisted hourly HRRR f00 analyses;
- daily operation: minimum 2 m air temperature across the property's local calendar day.

Farm Watch requires at least **75%** of the expected hourly analyses for a local day. The expected denominator is DST-aware and may be 23, 24 or 25 hours. A day with some HRRR data below that threshold remains `partial`; zero usable analyses is `unavailable`.

The resulting minimum is an hourly-model-analysis approximation to minimum daily temperature, not a station observation.

## Time-zone contract

Daily aggregation requires an explicit IANA time zone on the Farm Watch property.

The Flat Creek validation property is configured as:

`America/New_York`

The source snow timestamp must resolve to the same local calendar date that is persisted.

## Minnesota WSI context

Farm Watch reproduces the source arithmetic only:

- snow component: +1 when snow depth ≥38 cm;
- temperature component: +1 when minimum daily temperature ≤-17.7 °C;
- source WSI window: November-May.

The context reports expected complete days, complete days, coverage ratio, snow-threshold days, temperature-threshold days and known cumulative points.

It deliberately does **not** assign a Minnesota WSI severity category to Kentucky. Missing daily evidence does not count as zero points; it lowers coverage and leaves the cumulative context partial.

Outside November-May, WSI context is `not_applicable`.

## Product contract

- key: `snow-winter-severity-context`
- algorithm: `delgiudice-daily-snow-temperature-context-v1`
- schema: `snow-winter-severity-context-v1`
- evidence state: `proxy`
- deer inference: false
- coefficient transfer: false
- severity category assigned: false

The evidence state is `proxy` because both national source measurements substitute modeled/assimilated physical products for the source study's local observations.

## Persistence and refresh

Daily rows are stored in:

`farm_watch.property_snow_winter_severity_daily_v1`

The protected worker is:

`farm-watch-snow-winter-severity`

It uses the established Vault-backed Farm Watch materialization worker credential and the intentional in-function authentication posture with `verify_jwt:false`.

Flat Creek refresh is scheduled daily at 13:25 UTC. The daily snow request also finalizes prior local-day minimum temperature from the already-persisted HRRR archive when coverage is sufficient.

## Production validation — 2026-09-25

Initial Flat Creek production refresh:

- NOAA snow request: HTTP 200;
- source valid time: 2026-09-25 12:00 UTC;
- snow depth: **0 cm**;
- record state: `partial`;
- reason for partial state: September 25 local day was still in progress, so minimum daily temperature was intentionally not finalized;
- Minnesota WSI context: `not_applicable`, because September is outside the November-May source WSI window;
- deer inference: false;
- severity category: none.

The deer evidence stack exposes `snow_winter_severity_context`.

## Deer-science boundary

M08 solves only the winter snow/minimum-temperature measurement.

FW-R03 remains blocked by **FW-M09 dense-conifer cover**. Completing M08 does not activate the northern Minnesota winter-cover relationship.

The product must not be used as:

- a generic cold-weather movement multiplier;
- a Kentucky “severe winter” category derived from Minnesota cutoffs;
- a dense-conifer preference or bedding label;
- a mortality threshold;
- a transferred DelGiudice coefficient;
- a substitute for solar/thermal context or conifer-cover availability.
