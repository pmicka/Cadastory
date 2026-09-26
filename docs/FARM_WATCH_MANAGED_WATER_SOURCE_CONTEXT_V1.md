# Farm Watch Managed Water Source Context v1

Status: production-capable static configuration contract  
Version: 2026-09-26  
Primary validation property: `validation-property-01`  
Science dependency: FW-M48 in `FARM_WATCH_DEER_MEASUREMENT_RESOLUTION_V1.md`

## Purpose

`managed-water-source-context-v1` represents known artificial water sources whose geometry is stable enough to configure once while their usable-water state may change by year or date range.

It exists to satisfy the source-measurement form behind FW-M48 without asking mapped hydrography, rainfall, drought, or drainage geometry to prove that a stock pond, trough, or tank is currently usable.

## Data model

Three private service-role tables keep geometry and temporal state separate:

- `property_managed_water_sources_v1` stores stable source geometry and class;
- `property_managed_water_source_state_v1` stores explicit year/date-scoped usability;
- `property_managed_water_inventory_v1` records whether the property/year inventory is configured, explicitly empty, or unknown.

Supported source classes are:

- `stock_pond`
- `trough`
- `tank`
- `other_managed_water`

Supported usability states are:

- `known_usable`
- `known_not_usable`
- `unknown`

## Current-presence semantics

The internal reader `farm_watch_get_managed_water_source_context_v1_internal(slug,date)` exposes:

- `known_managed_source_present` only when a configured source is explicitly known usable for the requested date/year;
- `known_managed_source_absent` when a complete configured inventory has no usable source for the requested date/year, or when the inventory is explicitly `confirmed_none`;
- `managed_source_state_unknown` when the property/year has not been configured or source usability is unresolved.

A missing row is never interpreted as absence.

## Relationship to Surface Water State v1

`surface-water-state-v1` remains the dated neutral environmental/hydrography product. It preserves mapped 3DHP/NWI water geometry and persistence, conditioned-D8 drainage geometry, precipitation/drought/stream/soil-moisture context, and exact-date direct observations.

`managed-water-source-context-v1` is narrower: it represents factual artificial-source identity and usability supplied through bounded static configuration.

Neither product infers deer attraction, visitation, movement, bedding, habitat quality, or management value.

## Flat Creek

No managed-water inventory assertion is currently stored for Flat Creek. The correct state is therefore unknown, not absent.

The owner may close that property-specific state without a field visit if they already know whether a stock pond, trough, tank, or other managed artificial water source exists and is usable. If that fact is not already known, FW-M48 remains abstained for the property.

## Deer-science binding

FW-M48 is `derived_equivalent` because Farm Watch now has a production-capable representation of the study's known artificial usable-water-source variable.

This closes the engineering blocker only. The FW-D19 relationship remains conditional on:

- an explicitly known usable source;
- recent-rainfall context;
- its summer and semiarid-study limitations;
- no transferred numeric coefficient.

Mapped hydrography or environmental wetness alone cannot satisfy the usable-source constraint.
