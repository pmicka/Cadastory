# Farm Watch Solar Exposure v1

Status: implementation candidate — not deployed  
Validation property: `validation-property-01`

## Purpose

Solar Exposure v1 creates neutral, centrally materialized terrain/canopy solar context for later physical thermal modeling.

It deliberately separates:

1. static terrain orientation and terrain horizon;
2. deterministic date-specific direct-beam exposure potential;
3. an explicitly simplified canopy-screened proxy.

It does **not** infer thermal refuge, operative temperature, habitat quality, deer presence, movement, bedding, travel, or management value.

## Products

### `solar-terrain-context-v1`

Date-independent physical context.

Algorithm:

`terrain-horizon-canopy-context-v1`

Product key:

`solar-terrain-context`

Evidence class:

`deterministic_derived`

### `solar-exposure-context-v1`

Date-keyed deterministic solar exposure.

Algorithm:

`terrain-canopy-potential-solar-exposure-v1`

Product key:

`solar-exposure-context`

Evidence class:

`deterministic_derived`

The date is part of the materialization source signature, so each date has a distinct deterministic identity without requiring a new table.

## Central dependency reuse

### Terrain target grids

Solar Terrain v1 reuses the current canonical `terrain-form-permeability` materialization:

- local 500 m target grid: 10 m;
- landscape 1.5 km target grid: 30 m;
- elevation is decoded from the persisted compact artifact;
- property/domain masks remain the target masks.

Target-cell elevation is therefore **not re-downloaded or re-sampled**.

### Terrain horizon support

The barrier-aware Farm Watch target domain is not a physically valid terrain-shadow mask: a ridge outside a hydrologic or access barrier can still block sunlight.

For that reason, Solar Terrain v1 samples one bounded **unmasked** DEM support grid from the same authoritative KyFromAbove Phase 3 DEM:

- support resolution: 30 m;
- horizon search radius: 3,000 m from each target;
- ray step: 90 m;
- azimuth sectors: 24, at 15° spacing;
- CRS: EPSG:32616.

This support is build input only. The final materialization stores horizon angles, not a duplicate source DEM raster.

### Canopy

Local 500 m canopy reuses the canonical `spatial-edge-patch-context` 2025 NLCD TCC grid.

For the 1.5 km target grid, Solar Terrain v1 samples the same authoritative TCC ImageServer using the same:

- 2025 year;
- `v2025-6` product version;
- 30 m target grain.

NLCD TCC remains **percent modeled tree canopy cover**. It is not:

- leaf area index;
- gap fraction;
- crown transmissivity;
- leaf-on optical depth;
- measured under-canopy radiation.

## Terrain orientation

Slope and aspect are deterministic finite-difference derivatives.

Aspect convention:

- degrees clockwise from true north;
- downslope direction;
- flat cells use aspect 0 while retaining explicit orientation validity.

For target-boundary cells where a masked target neighbor is unavailable, the unmasked DEM support grid may provide the derivative neighbor. This avoids turning a Farm Watch barrier edge into an artificial cliff or missing orientation.

## Terrain horizon

Each target cell receives 24 geometric terrain-horizon angles.

For each sector:

1. march outward at 90 m intervals;
2. sample the 30 m unmasked support DEM;
3. compute vertical angle relative to the canonical target-cell elevation;
4. retain the maximum positive obstruction angle through 3 km.

Encoding:

- unsigned byte;
- one unit = 0.5°;
- zero = no positive terrain obstruction found within the modeled search radius.

The artifact also stores mean and maximum horizon angles per target cell.

The horizon is **terrain only**. Trees, buildings, and other above-ground objects do not contribute to the v1 horizon.

## Solar geometry

Date-specific exposure uses deterministic NOAA-style solar-position equations implemented locally.

Atmospheric refraction is omitted because this is geometric physical potential rather than an apparent sunrise product.

The solar anchor is the geographic center of the canonical local target grid. Across the 1.5 km analysis radius, a common solar position is used for each integration instant.

The artifact records:

- geometric sunrise;
- solar noon;
- geometric sunset;
- daylight minutes;
- integration cadence;
- exact daylight-window boundaries.

## Integration

Cadence:

15-minute midpoint integration, with the final step shortened if required.

Named windows are **equal thirds of geometric daylight**:

- morning;
- midday;
- evening;
- full day.

These are neutral solar windows, not animal diel-state classifications.

For a cell with slope \(\beta\), aspect \(\gamma\), solar elevation \(\alpha\), and solar azimuth \(A\):

```
cos(i) =
  sin(alpha) * cos(beta)
  + cos(alpha) * sin(beta) * cos(A - gamma)
```

Direct terrain potential is:

```
0
```

when:

- sun elevation is non-positive;
- sun elevation is at or below the interpolated terrain horizon;
- the incidence term is non-positive.

Otherwise:

```
max(0, cos(i))
```

is integrated over time.

The resulting unit is documented as **sun-hours-equivalent direct-beam potential**. It is not irradiance in W/m².

## Terrain shadow

Horizon angle is circularly interpolated between adjacent 15° sectors at the current solar azimuth.

A cell is terrain-shadowed when:

```
solar_elevation <= interpolated_terrain_horizon
```

The date artifact stores a daylight terrain-shadow fraction byte in addition to the integrated potential.

## Canopy-screened proxy

Solar Exposure v1 publishes the terrain potential independently from canopy.

Where TCC is available, it additionally publishes:

```
canopy_screened_proxy =
  terrain_potential * (1 - TCC_percent / 100)
```

This is deliberately named a **linear canopy-open proxy**.

It is **not**:

- canopy optical transmittance;
- shortwave radiation beneath the canopy;
- absorbed radiation;
- operative temperature;
- thermal refuge.

If canopy is unavailable, the canopy-screened value is not treated as an open-canopy estimate. Canopy validity remains explicit.

## Spatial support

v1 publishes:

- 10 m over the barrier-aware local 500 m domain;
- 30 m over the barrier-aware 1.5 km landscape domain.

A 3 km solar raster is intentionally not generated in v1. Existing 3 km evidence is not sufficient to justify fabricating a spatial surface at that extent. A later coarse summary can be added if a downstream physical/scientific requirement establishes value.

## Static artifact fields

Each local/landscape grid stores:

- target domain mask;
- canonical elevation;
- slope;
- aspect;
- orientation-valid mask;
- canopy-valid mask;
- TCC percent;
- 24 terrain-horizon sector arrays;
- mean terrain horizon;
- maximum terrain horizon.

All compact arrays use the existing Farm Watch base64-packed little-endian artifact convention.

## Date artifact fields

Each local/landscape grid stores:

- target domain mask;
- orientation-valid mask;
- canopy-valid mask;
- terrain-shadow daylight fraction;
- full-day terrain potential;
- full-day canopy-screened proxy;
- morning terrain potential;
- morning canopy-screened proxy;
- midday terrain potential;
- midday canopy-screened proxy;
- evening terrain potential;
- evening canopy-screened proxy.

Potential arrays use unsigned 16-bit **milli-sun-hours-equivalent** encoding.

## Identity and invalidation

### Static source signature

The Solar Terrain identity binds:

- current terrain materialization identity and artifact SHA;
- current spatial-pattern materialization identity and artifact SHA;
- KyFromAbove source;
- DEM support resolution;
- horizon sector count;
- horizon search radius;
- ray step;
- TCC year/version;
- target grid resolutions.

A changed terrain or canopy dependency therefore creates a new Solar Terrain input identity.

### Date source signature

Solar Exposure identity binds:

- Solar Terrain materialization identity;
- Solar Terrain artifact SHA;
- solar date;
- integration cadence;
- daylight-window policy;
- solar-geometry method;
- canopy-screening method.

## Materialization architecture

Both products use the existing private Farm Watch generic materialization framework:

- `farm_watch.property_materialization_builds_v1`;
- `farm_watch.property_materializations_v1`;
- private `farm-watch-derived` Storage;
- checksum-validated reads;
- source/input/final identities;
- lease/attempt/failure handling.

No new persistence table is required.

The existing `farm-watch-materialization` Edge Function is extended to route both product keys.

`solar-exposure-context` requires an exact `YYYY-MM-DD` `date` parameter.

## Worker path

The existing owner-only GitHub OIDC materialization workflow is extended with the exact issue title:

`[ops] Materialize Farm Watch solar exposure`

It builds:

1. `solar-terrain-context`;
2. `solar-exposure-context` for the requested/current date.

No worker secret is stored in GitHub.

## Presentation policy

Both fine-grid solar products are summary-only for Farm Watch viewers.

Owners retain full artifact access.

This follows the privacy posture already used for fine terrain, structure, and spatial-pattern materializations.

## Physical acceptance tests

The implementation tests:

- equinox solar noon near the equator approaches zenith;
- sunrise/sunset/daylight thirds are deterministic;
- south-facing slope receives greater direct-beam potential than north-facing slope under a southern sun;
- a terrain horizon above the sun blocks direct potential;
- horizon interpolation wraps correctly across north;
- Kelvin/weather forcing is not involved in this product;
- static dependency/source signatures change when dependencies change;
- date source signatures change with date;
- target elevations are reused from the canonical terrain artifact;
- date full-day potential equals morning + midday + evening within encoding tolerance;
- canopy-screened proxy never exceeds raw terrain potential;
- neutral evidence flags are retained;
- forbidden deer/habitat/bedding/stand score semantics do not appear.

## Explicit non-goals

Solar Exposure v1 does not yet model:

- atmospheric direct-normal or diffuse irradiance;
- cloud forcing;
- HRRR shortwave forcing;
- leaf-on/leaf-off canopy optical transmission;
- longwave exchange;
- convective cooling;
- humidity effects;
- surface temperature;
- operative temperature;
- animal heat balance.

Those belong in the later `thermal-exposure-context-v1` layer, where current meteorological forcing from Batch 1 can be combined with this neutral geometric exposure context.

## Deployment boundary

This Batch 2A implementation is intended to be merged only after CI and physical contract validation.

Deployment/materialization is a separate explicit action.

Before deployment:

- `farm-watch-materialization` must remain `verify_jwt:false`;
- the OIDC workflow ref gate must remain exact;
- both Scout architecture assertions must pass;
- production dependencies must resolve to the current canonical terrain/spatial artifacts;
- no new browser-side raster processing may be introduced.
