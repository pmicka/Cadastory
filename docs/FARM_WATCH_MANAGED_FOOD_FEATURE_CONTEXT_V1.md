# Farm Watch Managed Food Feature Context v1

Status: production static configuration contract  
Version: 2026-09-25  
Primary validation property: `validation-property-01`  
Science dependencies: FW-M29 and FW-M32 in `FARM_WATCH_DEER_MEASUREMENT_RESOLUTION_V1.md`

## Purpose

`managed-food-feature-context-v1` represents explicit managed food plots, managed forage areas, and study-relevant managed cover polygons without inventing a forage-chemistry model.

The product exists to close the source-measurement gap for deer relationships whose studies used mapped managed food features. It is a property configuration product, not a remote-sensing classifier.

## Data model

Geometry is stable and reusable:

- `property_managed_food_features_v1` stores a polygon once;
- `property_managed_food_feature_state_v1` stores the feature's year-specific active/inactive/unknown management state;
- `property_managed_food_inventory_v1` stores whether the property's managed-food inventory for a year is complete, explicitly empty, or unknown.

This lets a food-plot polygon be configured once and reused in later seasons without redrawing it.

## Evidence states

The internal reader `farm_watch_get_managed_food_feature_context_v1_internal(slug, date)` returns:

- `known` when the year is explicitly confirmed to contain no managed-food features, or when a configured inventory contains no active features;
- `available` when a complete configured inventory contains one or more active features;
- `unavailable` when the year has not been assessed or configured feature state is unresolved.

A confirmed empty inventory is a known absence. It is not missing data.

## Interpretation boundary

This product does **not** infer:

- forage crude protein or fiber;
- standing biomass;
- nutritional abundance;
- deer attraction or use;
- feeder effects;
- mineral-attractant effects;
- crop phenology or harvest state outside explicitly configured managed features.

Supplemental feeders and mineral attractants remain separate point observations.

## Flat Creek 2026

The owner confirmed on 2026-09-25 that Flat Creek has no food plots or managed forage areas in 2026. The 2026 inventory is therefore `confirmed_none`.

Two separate point observations remain outside this product:

- `flat-creek-deer-feeder-01`: large corn feeder, retained as `supplemental_feed_point`;
- `flat-creek-salt-block-01`: salt block at the operator-identified three-way canonical trail junction, retained as `mineral_attractant_point`.

The screenshot used to identify the salt-block junction is transient verification only and is not persisted.

## Deer-science binding

FW-M29 and FW-M32 are promoted to `derived_equivalent` only for the mapped managed-food measurement form.

That does not make their hunting-risk relationships active by itself:

- FW-R15 still requires FW-M28 daily hunter activity;
- FW-R16 still requires FW-M31 frequent-hunt risk.

No coefficient transfer or composite deer score is authorized.
