# Farm Watch Thermal Exposure v1

Status: production — deployed 2026-09-21  
Validation property: `validation-property-01`

## Purpose

`thermal-exposure-context-v1` is the neutral physical bridge between current Farm Watch meteorological forcing and the static terrain/canopy solar geometry introduced in Batch 2A.

The product does **not** calculate a deer thermal score or a human-style comfort index.

It co-registers:

- one exact, centrally persisted HRRR analysis;
- the current canonical `solar-terrain-context-v1` artifact;
- the geometric solar position at the HRRR valid time;
- per-cell terrain direct-beam incidence/shadow;
- an explicitly simplified TCC-open screening proxy.

The individual physical components remain inspectable.

## Product

Product key:

`thermal-exposure-context`

Algorithm:

`hrrr-solar-component-context-v1`

Schema:

`thermal-exposure-context-v1`

Evidence class:

`deterministic_derived`

## Meteorological dependency

The materializer resolves Farm Watch's central:

`farm_watch_get_meteorological_forcing_v1_internal`

Contract:

- source state: `analysis`;
- maximum forcing age at requested resolution: 180 minutes;
- current product identity is bound to the exact HRRR forcing identity;
- stale or missing forcing fails closed;
- no weather source is fetched by the thermal materializer.

Required forcing fields remain separate:

- 2 m air temperature;
- 2 m dew point;
- 2 m relative humidity;
- true 10 m wind speed;
- true meteorological wind direction;
- true east/north wind components;
- downward shortwave;
- downward longwave;
- total cloud cover;
- precipitation rate.

The product preserves HRRR grid provenance and the modeled-grid-point caveat.

## Static spatial dependency

The product requires the current canonical:

`solar-terrain-context-v1`

Its source signature binds:

- static solar-terrain materialization identity;
- static solar-terrain artifact SHA;
- meteorological forcing identity;
- forcing valid time;
- forcing source-index SHA;
- forcing selected-record/value SHA;
- forcing age/source-state contract;
- physical spatial-component method.

A changed HRRR analysis creates a new thermal materialization identity.

A changed static terrain/canopy solar product also creates a new identity.

## Timestamp semantics

The API accepts an optional exact `at` timestamp.

If omitted for the thermal product, current UTC time is used as the requested resolution time.

The selected forcing row is the newest allowed HRRR analysis at or before that requested time.

The final artifact is anchored to **the HRRR analysis valid time**, not the request wall-clock time.

This allows repeated requests that resolve to the same forcing analysis to reuse one deterministic materialization.

## Spatial fields

Both the 10 m local 500 m grid and 30 m landscape 1.5 km grid publish:

- target domain mask;
- terrain-orientation-valid mask;
- canopy-valid mask;
- terrain-shadow flag;
- terrain direct-beam factor;
- canopy-screened direct-beam factor.

### Terrain direct-beam factor

For the exact forcing valid time:

1. calculate geometric solar elevation and azimuth at the Solar Terrain anchor;
2. circularly interpolate the 24-sector terrain horizon at solar azimuth;
3. determine terrain shadow;
4. calculate slope/aspect direct-beam incidence using the Solar Exposure v1 geometry.

The factor is dimensionless and constrained to 0–1.

Encoding:

`u16 round(factor * 1000)`

Nighttime has zero direct-beam factor. Night is not relabeled as terrain shadow.

### Canopy-screened factor

Where TCC is valid:

```
canopy_screened_factor =
  terrain_direct_beam_factor * (1 - TCC_percent / 100)
```

This remains a transparent **linear canopy-open proxy**.

It is not:

- optical canopy transmittance;
- leaf-area-index radiative transfer;
- measured under-canopy shortwave;
- absorbed radiation;
- surface temperature;
- operative temperature.

Canopy validity remains explicit.

## Radiation policy

HRRR downward shortwave and longwave are stored as scalar forcing components.

v1 deliberately does **not** calculate:

```
local_shortwave =
  HRRR_shortwave * terrain_factor
```

because HRRR surface downward shortwave includes radiative components that v1 does not partition into direct and diffuse flux.

Likewise, v1 does not model:

- sky-view-factor longwave exchange;
- terrain-reflected shortwave;
- canopy longwave exchange;
- multiple scattering.

Those require a dedicated physical contract rather than an arbitrary multiplication.

## Wind policy

HRRR 10 m true wind remains a scalar modeled forcing component.

v1 does not spatially alter wind using:

- terrain exposure;
- canopy percentage;
- LiDAR structure;
- slope/aspect;
- an invented shelter coefficient.

A later aerodynamic/microclimate product may do so only with a defensible physical model and validation.

## No composite thermal index

The artifact explicitly records:

- `operative_temperature_calculated:false`;
- `composite_thermal_index_calculated:false`;
- `scoring_performed:false`;
- `behavioral_inference_performed:false`.

Air temperature, humidity, wind, cloud, shortwave, longwave, precipitation, terrain incidence and canopy screening stay separately inspectable.

Human heat-index and wind-chill formulas are not used as deer proxies.

## Materialization architecture

The product reuses the generic private Farm Watch materialization spine:

- `farm_watch.property_materialization_builds_v1`;
- `farm_watch.property_materializations_v1`;
- private `farm-watch-derived` Storage;
- lease/failure handling;
- source/input/final SHA-256 identities;
- checksum-validated artifact reads.

No new persistence table is required.

Historical thermal artifacts remain identity-bound; their long artifact retention does not make them "current." Current resolution always selects forcing by requested time and freshness contract.

## Worker path

The established GitHub OIDC materialization workflow accepts the exact owner-created issue title:

`[ops] Materialize Farm Watch thermal exposure`

The runner:

1. ensures `solar-terrain-context` is materialized/reused;
2. requests `thermal-exposure-context` at the supplied/current timestamp.

The workflow retains:

- exact repository/workflow-ref trust;
- owner actor gate;
- `id-token: write`;
- no GitHub-stored Farm Watch worker secret.

## Presentation policy

Fine thermal grids are summary-only for Farm Watch viewers.

Owners retain full artifact access.

## Tests

The implementation verifies:

- source signatures change when forcing identity changes;
- exact forcing valid time is bound into identity;
- a daytime south-facing slope receives greater direct-beam factor than a north-facing slope under southern sun;
- the linear canopy proxy never exceeds the raw terrain factor;
- a 50% TCC test cell produces approximately 50% of the raw factor;
- nighttime forcing yields zero solar factors without marking night as terrain shadow;
- HRRR forcing fields survive independently;
- no composite thermal score is produced;
- no deer/habitat/bedding/refuge score appears;
- viewer fine-grid restrictions remain intact;
- the shared materialization Edge Function type-checks.

## Explicit non-goals

v1 does not calculate:

- operative temperature;
- black-globe temperature;
- mean radiant temperature;
- animal heat balance;
- metabolic heat;
- evaporative heat loss;
- surface temperature;
- soil temperature;
- wind shelter/downscaling;
- direct/diffuse shortwave partition;
- canopy radiative transfer;
- a thermal-refuge class;
- deer selection or movement.

## Downstream use

This product exists so a later deer-science relationship module can evaluate literature-supported thermal relationships without hiding physical assumptions inside the biological model.

Any deer-specific use still requires:

- relationship-registry/ledger IDs;
- season and diel gates;
- sex/age/reproductive/movement-state gates where supported;
- explicit source-study transfer limitations;
- abstention when required inputs are unavailable.

## Production deployment verification — 2026-09-21

Production materialization:

- algorithm: `hrrr-solar-component-context-v1`;
- schema: `thermal-exposure-context-v1`;
- identity SHA-256: `5ffb6225cc3d40d6a1133f03ca59ba51c040bf62876ab95241546cdf0638e58d`;
- artifact SHA-256: `94fec6846448e3a175dd2453f636c19cb4ff263905dd03797417d02596069a99`;
- artifact size: 381,501 bytes;
- exact HRRR analysis valid time: `2026-09-21T21:00:00Z`;
- exact HRRR forcing identity: `2df4c084680b7c9a4531100b80bcf2414d0add43ba1a11a6ab38fc18b49f0dd6`;
- exact Solar Terrain identity: `e33bd91e280d9bfd2fb46600d24c8250909fedd7dcf392d34be6aa7cc3688866`;
- HRRR nearest-grid distance: 1,024.1 m.

The private production reader downloaded the stored artifact, recalculated its SHA-256, validated it against the persisted artifact SHA, parsed the artifact, and passed the current `thermal-exposure-context-v1` validator.

Production summary at the selected HRRR analysis:

- local orientation-valid cells: 17,136;
- local canopy-valid cells: 16,959;
- local terrain-shadow cells: 523;
- local mean terrain direct-beam factor: 0.4424181505;
- local mean canopy-screened direct-beam factor: 0.1535636723;
- landscape orientation-valid cells: 6,550;
- landscape terrain-shadow cells: 101;
- landscape mean terrain direct-beam factor: 0.4673252878;
- landscape mean canopy-screened direct-beam factor: 0.2440134527.

The HRRR forcing remained component-wise and provenance-bound:

- air temperature: 27.093378 °C;
- dew point: 19.05166 °C;
- relative humidity: 64.1%;
- true 10 m wind: 4.232197 m/s from 1.735°;
- downward shortwave: 433.6 W/m²;
- downward longwave: 374.7 W/m²;
- total cloud cover: 7%;
- precipitation rate: 0 mm/hr.

The artifact explicitly retained:

- `operative_temperature_calculated:false`;
- `composite_thermal_index_calculated:false`;
- `scoring_performed:false`;
- `behavioral_inference_performed:false`.

The deployed `farm-watch-materialization` function is ACTIVE, version 22, with `verify_jwt:false`. Fine thermal grids remain viewer-summary-only under the shared presentation policy. Both Scout architecture assertions passed after deployment.

## Deployment state

Batch 2B is production-operational for the validation property.

A new HRRR analysis changes the thermal source identity and therefore supports a new deterministic thermal materialization. Historical artifacts remain identity-bound evidence and do not become “current” merely because they remain stored.
