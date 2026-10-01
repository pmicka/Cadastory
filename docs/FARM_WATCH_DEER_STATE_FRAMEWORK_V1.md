# Farm Watch Deer State Framework v1

Status: implementation candidate — evaluator-integrated
Version: 2026-10-01
Species: white-tailed deer (`Odocoileus virginianus`)

## Purpose

`deer-state-framework-v1` makes the state assumptions consumed by deer-science evaluation explicit without creating a deer score or behavioral prediction.

It separates five state families:

- biological;
- temporal;
- environmental;
- resource;
- disturbance.

Each state dimension reports:

- a normalized status: `known | proxy | unknown | stale | unavailable`;
- the current value or bounded context;
- provenance;
- source product when one exists;
- source evidence state;
- relationship IDs that depend on the dimension;
- an interpretation boundary.

The framework is emitted inside `deer-science-context-v5`.

## Critical unknown-versus-unavailable rule

`unknown` means the state could exist for the focal animal/property but has not been explicitly established.

Examples:

- individual movement state;
- sex or age when not supplied;
- individual reproductive state.

`unavailable` means Farm Watch does not currently have an authorized source-aligned measurement or state product.

Examples:

- current leaf state;
- regional reproductive context outside a supported evidence scope;
- current crop identity when no accepted crop-state evidence exists.

These statuses are never silently converted into one another.

## Biological state

The framework preserves:

- sex;
- age class;
- movement state;
- individual reproductive state;
- regional reproductive context.

Sex, age, movement state, and individual reproductive state are explicit scenario dimensions. Regional breeding timing is population context only and never imputes individual estrus, pregnancy, mating, or movement state.

## Temporal state

The framework preserves:

- meteorological/calendar season;
- deterministic solar/diel period.

Calendar season does not automatically reproduce a source study's biological-season definitions. Solar phase does not automatically mean deer activity.

## Environmental state

The framework publishes explicit state availability for:

- recent precipitation;
- drought;
- stream/discharge context;
- root-zone soil moisture;
- thermal physical context;
- snow/winter physical context;
- extreme-weather event state;
- current leaf state.

Seasonal-state component evidence retains its own `known | proxy | stale | unavailable` semantics.

The current leaf-state row is intentionally `unavailable`. Historical leaf-off woody-structure imagery is a structure product, not a current phenological leaf-state measurement, and calendar date is not used as a silent substitute.

Snow context preserves current physical variables such as snow depth and minimum daily temperature. Minnesota WSI remains source provenance/context and is not a Kentucky severity category.

Extreme-event state remains separate from routine weather. A known no-event state is valid state evidence; it does not activate an extreme-event relationship.

## Resource state

The framework keeps separate:

- field phenology;
- accepted current crop identity;
- annual mast survey state;
- surface-water presence state;
- configured managed-food state;
- configured managed-water state.

Crop identity is not crop stage, standing forage, harvest state, access, or deer feeding.

Regional annual mast state is not property mast production.

Known water presence is not deer water use.

## Disturbance state

The framework exposes human/hunting-activity state separately.

Roads, trails, stands, access geometry, and an open hunting season do not establish current hunting pressure. When actual activity evidence is absent, the disturbance state remains unavailable rather than inferred.

## Relationship-specific state gate

Every evaluated relationship now carries `state_gate`.

The gate reports:

- required explicit biological dimensions;
- missing biological dimensions;
- known biological mismatches;
- stateful input keys;
- missing/incompatible state inputs;
- state-specific value constraints;
- failed and unresolved state-constraint IDs.

Status vocabulary:

- `pass`;
- `not_applicable` — a known state or state constraint makes the relationship inapplicable;
- `insufficient_state` — a required state is unknown, unavailable, stale/incompatible, or unresolved.

This state gate is diagnostic and remains separate from:

- measurement-fidelity gating;
- structural/spatial covariates;
- source/product freshness logic;
- property-conditioned covariate hypotheses.

## Fail-closed examples

- Unknown juvenile-male dispersal state cannot activate a dispersal relationship.
- Known absence of a usable water source makes a water-use relationship not applicable rather than merely missing.
- Missing recent-precipitation state keeps a rainfall-conditioned relationship insufficient.
- A healthy extreme-weather source reporting no active event makes the storm relationship not applicable.
- Missing hunting-pressure evidence does not inherit risk from season-open status.
- Current leaf state remains unavailable until an authorized current-state product exists.

## Output boundary

The framework performs no:

- deer-use inference;
- movement probability;
- bedding classification;
- habitat quality score;
- hunting recommendation;
- coefficient synthesis;
- cross-state weighted overlay.

Its purpose is to make state eligibility and uncertainty inspectable before any ecological relationship is interpreted.
