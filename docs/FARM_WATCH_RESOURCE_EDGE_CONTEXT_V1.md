# Farm Watch Resource Edge Context v1

## Purpose

Resource Edge Context centralizes neutral agricultural-field and field-boundary evidence inside the current barrier-aware Farm Watch landscape domain.

It is designed to answer questions such as:

- How close is the selected property to the nearest mapped agricultural field?
- How much mapped field area exists in the surrounding same-side landscape?
- How much mapped field-boundary linework exists at each scale?
- Which current CDL classes dominate the mapped field context?
- How much mapped field area or boundary occurs close to the selected property?

It does **not** answer where deer feed, travel, bed, cross, or prefer to spend time.

## Dependency

The product requires a current `landscape-domain` product.

That means all resource-edge calculations inherit the same barrier-aware 500 m / 1.5 km / 3 km usable-neighborhood geometry. For the current validation property, the Kentucky River remains an explicit overrideable hard movement-boundary assumption in the landscape-domain layer.

Operator-confirmed or imagery-derived trails are **not** an input to this product.

## Source evidence

Current source tables:

- `agriculture.field_boundaries`
- `agriculture.cdl_classes`

Only present mapped field geometries intersecting the current 3 km barrier-aware domain are included.

The source boundary status and source confidence remain exposed because mapped field geometry quality is part of the evidence.

## Stored geometry

The product stores two central geometries:

- `field_area_geometry`: unioned mapped field polygons clipped to the current same-side 3 km domain;
- `field_edge_geometry`: unioned mapped field-boundary linework clipped to the same domain.

Shared or coincident linework is unioned before length measurement so a shared mapped boundary is not counted twice.

These geometries are deterministic derivatives. They do not imply that every mapped field boundary is a meaningful habitat or movement edge.

## Zone primitives

For the cumulative 500 m, 1.5 km, and 3 km landscape domains, Farm Watch stores:

- mapped field count;
- mapped field area in acres;
- mapped field fraction of the domain;
- mapped field-boundary length;
- mapped field-boundary density in km per square km.

## Property-proximity primitives

Within same-side 100 m, 250 m, and 500 m buffers from the selected property, Farm Watch stores:

- mapped field count;
- mapped field area;
- mapped field-boundary length.

This provides a neutral proximity profile without converting field proximity into a wildlife-use conclusion.

## Nearest mapped field

The nearest mapped field record retains:

- field id;
- source-native id;
- distance from the selected property;
- latest crop year/code/class;
- boundary status;
- source confidence.

Distance is geometric distance between the property and the mapped field polygon.

## Crop composition

The broad 3 km same-side domain reports current/latest CDL composition for mapped fields:

- year;
- class code;
- class name;
- field count;
- mapped field area.

A CDL class does not establish current forage availability, crop maturity, harvest state, browse quality, or wildlife use.

## Identity and invalidation

The product identity depends on:

- current property boundary;
- current `landscape-domain` identity;
- the exact mapped field rows intersecting the current broad domain;
- relevant CDL class rows;
- algorithm version;
- output schema version.

Changing the barrier-aware domain, mapped field data, crop attribution, or product contract invalidates the persisted context.

## Evidence boundary

The persisted context explicitly records:

- `evidence_class: deterministic_derived`;
- `scoring_performed: false`;
- `behavioral_inference_performed: false`.

The intended next consumer is a later named deer-relevant resource/edge hypothesis. That hypothesis must remain separate from this evidence layer.

## Validation-property snapshot

Before materialization, the current same-side validation-property field geometry produced approximately:

- nearest mapped field: 304.7 m, 2025 Grassland/Pasture;
- 500 m: 1 field, 2.79 mapped acres, 0.511 km mapped field boundary;
- 1.5 km: 12 fields, 36.82 mapped acres, 7.096 km mapped field boundary;
- 3 km: 37 fields, 205.73 mapped acres, 27.128 km mapped field boundary;
- 3 km CDL composition: about 119.90 ac Grassland/Pasture, 82.37 ac Soybeans, and 3.47 ac Corn.

These values are a validation snapshot, not permanent ecological facts.
