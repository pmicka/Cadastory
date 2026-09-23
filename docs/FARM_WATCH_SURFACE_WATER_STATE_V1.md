# Farm Watch Surface Water State v1

Status: implemented, pending production deployment  
Validation property: `validation-property-01`  
Deer-science dependencies: FW-D15, FW-D19

## Purpose

`surface-water-state-v1` is the neutral dated layer that separates four things that must not be conflated:

1. authoritative mapped hydrography;
2. mapped persistence/regime attributes where an authoritative source actually supplies them;
3. deterministic DEM drainage geometry;
4. dated evidence about current environmental conditions or directly observed water presence.

It does **not** predict deer water preference, deer use, travel, bedding, attraction, habitat quality, or management value.

## Existing sources reused

Batch 7 does not introduce another hydrography collector.

### USGS 3DHP

Farm Watch already maintains identity-aware cached 3DHP features within the property hydrology context.

3DHP flowlines and waterbodies remain authoritative mapped hydrography. The current cached feature attributes do not expose a defensible perennial/intermittent field for the validation property, so v1 records their persistence as:

`mapped_unknown_persistence`

A feature type such as `Lake`, `Channel Line`, or `Waterbody Connector` is not promoted to current water presence.

### USFWS NWI

NWI wetlands retain their published water-regime attribute.

v1 maps only explicit source terms:

- `Permanently Flooded` → `mapped_persistent`
- `Seasonally Flooded` → `mapped_seasonal`
- `Temporary Flooded` / `Temporarily Flooded` → `mapped_temporary`
- all other/missing regime values → `mapped_unknown_persistence`

These are mapped regime classes, not observations that water is present on the requested date.

### Conditioned DEM drainage

The current canonical terrain materialization is:

- product: `terrain-analysis`
- algorithm: `phase3-dem-61x61-conditioned-flow-v2`

Batch 7 records its identity, artifact checksum, flow-trace count, flow-channel-cell count, and minimum contributing area as a dependency.

Its semantic state is always:

`geometry_only`

D8 traces are not streams, water presence, persistence, crossings, or wildlife-use evidence.

### Seasonal State v1

Batch 7 reuses the existing dated Seasonal State resolver for:

- QPE precipitation;
- drought;
- nearest USGS stream-gauge discharge;
- root-zone soil-moisture context.

The component's existing state, scope, observation date, freshness, and interpretation boundary are preserved.

No new numeric threshold converts these inputs into a universal `wet` / `dry` water-availability class. The v1 synthesis therefore records:

`qualitative_wetness_state = not_classified`

This is intentional: QPE, drought, a regional/off-property gauge, and modeled soil moisture provide environmental context but do not prove water is present at a mapped feature.

## Direct operator observations

The existing private `farm_watch.property_operator_observations_v1` table is reused.

Batch 7 reserves:

`observation_kind = surface_water_presence`

Existing observation-state semantics are preserved:

- `observed_present`
- `observed_absent`
- `uncertain`

A direct observation may also retain the existing persistence field:

- `unknown`
- `intermittent_or_seasonal`
- `persistent_when_observed`
- `event_driven`

Only an observation explicitly dated to the requested `as_of_date` (or whose explicit date range contains that date) becomes current-presence evidence in that snapshot.

Older observations remain valid historical evidence but are not silently promoted to current water presence.

An observation may bind to a mapped hydrology feature through `related_feature_key`, using the stable hydrology feature key:

`<source_slug>:<feature_kind>:<source_feature_id>`

Unlinked water observations remain location evidence in the snapshot without rewriting authoritative source geometry.

## Stored product

The planned production table is:

`farm_watch.property_surface_water_state_v1`

Key:

- property;
- `as_of_date`.

Each snapshot stores:

- aggregate availability status;
- full neutral context;
- property-boundary SHA-256;
- source fingerprint;
- source-signature SHA-256;
- algorithm/schema versions;
- final identity SHA-256;
- retrieval timestamp.

The identity binds:

- current hydrology identity;
- exact Seasonal State identity for the date;
- current canonical conditioned-D8 terrain identity/artifact;
- exact-date operator water observations.

A boundary change or contract version change invalidates the stored snapshot on read.

## Validation-property pre-deployment expectation

Current live source inspection on 2026-09-22 shows why this separation is necessary.

No cached authoritative 3DHP/NWI feature currently intersects the selected parcel.

Nearby evidence includes approximately:

- NWI Riverine Streambed, `Seasonally Flooded`: 29.8 m from the parcel;
- USGS 3DHP first-order Channel Line: 32.8 m;
- USGS 3DHP waterbody classified `Lake`: 37.1 m;
- NWI Freshwater Pond, `Permanently Flooded`: 279.3 m;
- additional permanently flooded NWI ponds and riverine features within the broader 3 km hydrology cache.

The latest canonical conditioned-D8 terrain product contains 12 flow traces. Those remain geometry-only.

There are currently no `surface_water_presence` operator observations on the validation property, so v1 should report `no_current_observation` for mapped features rather than fabricate present/absent water state.

## Access and operation

The new table and internal functions are service-role only.

No anonymous or authenticated-user table/RPC access is introduced.

The migration defines a validation-property cron refresh at 14:10 UTC, immediately after the existing 14:05 UTC Seasonal State snapshot. This preserves the dated upstream identity instead of independently reimplementing its collectors.

## Evidence boundary

Every context sets:

- `evidence_class=deterministic_derived`;
- `scoring_performed=false`;
- `behavioral_inference_performed=false`;
- `deer_water_preference_inferred=false`.

The first deer water/hydrology module must consume this product through the machine-readable deer relationship registry and preserve FW-D15/FW-D19's movement-state and geographic limitations.
