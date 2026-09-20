# Farm Watch Landscape Context v1

## Purpose

Farm Watch landscape context extends property-centered physical evidence into a bounded surrounding-landscape domain before any deer-focused scoring or behavioral prediction is introduced.

The product answers a narrower question:

> What physical, agricultural, access, structure, and barrier context surrounds the selected property on the same modeled movement side of major barriers?

It does **not** assert where deer are, where deer will travel, where deer bed, where deer feed, or where a hunter should set up.

## Evidence boundary

The landscape domain and summaries are deterministic derivatives of existing Farm Watch / Scout evidence plus explicit property-scoped model assumptions.

Evidence classes remain distinct:

- authoritative source evidence: property geometry, USGS 3DHP, USFWS NWI, mapped agricultural fields, Scout access features, registered structure sources;
- deterministic derived evidence: buffered landscape zones, barrier subtraction, connected-component selection, counts, distances, and intersected acreage;
- operator/model assumption: movement permeability assigned to a named barrier;
- future deer-focused inference: movement, security-cover, resource-edge, thermal-refuge, or other hypothesis surfaces.

A barrier rule is never promoted to wildlife observation merely because it is used in deterministic geometry.

## Nested analysis domains

The initial contract uses three nested distances from the selected property:

| Domain | Radius | Intended consumers |
| --- | ---: | --- |
| local | 500 m | immediate structural continuity, fine access, later LiDAR / leaf-off context |
| landscape | 1,500 m | terrain connectivity, canopy context, human access, hydrology |
| broad | 3,000 m | agriculture, generalized land use, development / structure context |

These are maximum Euclidean extents before barrier handling. The actual domain may be substantially smaller.

## Barrier-aware geometry

For a hard barrier, Farm Watch:

1. buffers the exact selected property;
2. resolves the configured authoritative barrier geometry;
3. subtracts that barrier geometry from the buffer;
4. decomposes the remainder into polygon components;
5. retains only components that intersect the selected property.

The resulting domain therefore represents the property-side connected landscape under the configured barrier assumptions.

### Kentucky River rule for validation-property-01

The initial validation-property rule is:

- label: `Kentucky River`
- class: `major_river`
- source: USGS 3DHP
- source match: named flowline `Kentucky River`
- permeability: `0`
- evidence class: `operator_model_assumption`

The preferred barrier polygon is an intersecting USGS 3DHP waterbody whose feature type is `River`. If that polygon cannot be resolved but the named flowline is available, v1 uses a 30 m buffered flowline as a conservative fallback.

This rule is intentionally overrideable. It means “treat the Kentucky River as non-traversable in this initial property-scale model,” not “white-tailed deer are biologically incapable of crossing the Kentucky River.”

If a configured hard barrier cannot be resolved, the domain fails closed rather than silently reverting to a circular buffer.

## Hydrology dependency

The landscape domain requires canonical Farm Watch hydrology coverage through 3,000 m.

The hydrology product remains authoritative USGS 3DHP + USFWS NWI evidence. Extending its model buffer does not mean the UI should render all 3 km of hydrology.

The normal Farm Watch map remains bounded to a 1,000 m display subset while the backend may retain the full 3,000 m context for landscape analysis.

## Initial neutral context

`farm_watch_get_landscape_context_v1_internal` initially reports:

### Agriculture

For each 500 / 1,500 / 3,000 m barrier-aware zone:

- mapped field count;
- fields with crop-history metadata;
- mapped field acreage intersecting the domain.

Interpretation boundary: a mapped agricultural field does not by itself establish current forage quality, crop availability, or deer use.

### Human access

Within the 1,500 m barrier-aware domain:

- mapped access feature count;
- drivable feature count;
- driveway count;
- track count;
- access point count;
- routing-barrier count;
- nearest mapped drivable feature;
- nearest mapped driveway;
- nearest mapped track.

Interpretation boundary: infrastructure is human-access exposure context, not measured visitation, hunting pressure, or disturbance frequency.

### Structures

Within the 3,000 m barrier-aware domain, structure evidence remains source-specific for now.

The first source set includes:

- FEMA USA Structures;
- Kentucky ORNL building footprints;
- Overture buildings;
- targeted OpenStreetMap building identity.

Counts are not merged because source coverage and overlap are not yet reconciled. A zero count from one source is not evidence that no buildings exist.

## Identity and invalidation

The landscape-domain identity includes:

- property boundary SHA-256;
- algorithm version;
- output schema version;
- canonical hydrology identity;
- hydrology retrieval state;
- active property-scoped barrier rules.

A changed property boundary, hydrology contract/refresh, or barrier rule invalidates the stored domain.

## Initial validation-property result

The read-only prototype against current production evidence produced:

| Radius | Raw circular buffer | Barrier-aware domain |
| --- | ---: | ---: |
| 500 m | 1.8555 km² | 1.7121 km² |
| 1,500 m | 9.8891 km² | 5.8942 km² |
| 3,000 m | 33.6404 km² | 21.3934 km² |

Agricultural context after Kentucky River barrier handling:

| Radius | Fields | Intersected field area |
| --- | ---: | ---: |
| 500 m | 1 | 2.79 ac |
| 1,500 m | 12 | 36.82 ac |
| 3,000 m | 37 | 205.73 ac |

At 1,500 m the same prototype found 16 Scout access features: 6 drivable, 4 driveways, 1 track, 1 access point, and 1 routing barrier.

These are validation outputs for the current data snapshot, not durable ecological constants.

## Next consumers

Once this domain is stable, the next deer-focused work should consume it without changing its semantics:

1. neighboring canopy / canopy-transition primitives;
2. landscape terrain / movement-cost primitives;
3. agricultural/open-land resource-edge primitives;
4. human-access exposure primitives;
5. later, centrally materialized LiDAR / leaf-off structural-cover primitives.

Only after those neutral primitives exist should Farm Watch introduce named deer-relevant hypothesis surfaces. No universal deer score is part of this contract.
