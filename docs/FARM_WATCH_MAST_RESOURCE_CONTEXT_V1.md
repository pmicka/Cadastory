# Farm Watch Mast Resource Context v1

Status: Batch 5B implementation candidate — 2026-09-25

## Purpose

`mast-resource-context-v1` adds annual mast-production state without collapsing it into the existing spatial mast-capacity product.

The product keeps three evidence streams separate:

1. `mast_capacity` — the Batch 5A modeled/imputed 30 m BIGMAP species-biomass materialization;
2. `annual_mast_proxy` — the exact-year Kentucky Department of Fish and Wildlife Resources (KDFWR) annual mast survey at statewide and East/West survey-region scope;
3. `property_observations` — explicitly dated operator field observations using `observation_kind=mast_resource`.

No multiplication, weighted overlay, food score, deer score, or deer-use inference is performed.

## Deer-science boundary

Batch 5B supplies the annual-state input required by FW-D07.

FW-D07 supports transfer of the relationship form that acorn mast can materially alter deer foraging and space use during mast fall. It does not authorize a universal numeric coefficient or permit a regional survey rating to become property-specific mast abundance.

The neutral product therefore stops before biological interpretation.

## Authoritative annual source

Source authority:

- Kentucky Department of Fish and Wildlife Resources (KDFWR)
- Kentucky Mast Survey
- report index: `https://fw.ky.gov/Hunt/Pages/Deer-Hunting-Stats.aspx`

The current survey method began in 2007. Surveyors scan each tree crown for 30 seconds and estimate the percentage of crown area bearing mast (PCA). KDFWR also reports PBA, the percentage of surveyed trees bearing any mast, and publishes qualitative ratings.

Batch 5B stores the published values rather than recomputing ratings from PBA. This is intentional: wording at category boundaries is not perfectly uniform across report sections/years, and the authoritative published rating should not be silently re-derived.

## Canonical seeded reports

### 2024

Report:

- `https://fw.ky.gov/Hunt/Documents/mast_report_2024.pdf`
- publication date: 2024-10-04
- 35 routes
- 33 counties
- 2,853 sampled trees

Published Table 1 statewide PBA/rating:

| Group | PBA | Rating |
| --- | ---: | --- |
| White oak | 42% | Average |
| Red oak | 79% | Good |
| Hickory | 44% | Average |
| Beech | 29% | Poor |

Published West-region PBA/rating:

| Group | PBA | Rating |
| --- | ---: | --- |
| White oak | 47% | Average |
| Red oak | 82% | Bumper |
| Hickory | 51% | Average |
| Beech | 26% | Poor |

### 2025

Report:

- `https://fw.ky.gov/Hunt/Documents/2025-mast-report.pdf`
- publication date: 2025-09-29
- 35 routes
- 32 counties
- 2,766 sampled trees

Published Table 1 statewide PBA/rating:

| Group | PBA | Rating |
| --- | ---: | --- |
| White oak | 62% | Good |
| Red oak | 66% | Good |
| Hickory | 42% | Average |
| Beech | 68% | Good |

Published West-region PBA/rating:

| Group | PBA | Rating |
| --- | ---: | --- |
| White oak | 61% | Good |
| Red oak | 69% | Good |
| Hickory | 43% | Average |
| Beech | 54% | Average |

The full canonical rows also retain trees surveyed and PCA median/IQR values for statewide, East, and West scopes.

## Validation-property survey-region relation

`validation-property-01` is assigned to the KDFWR `west` mast-survey region using the regional boundary shown in Figure 4 of the 2025 report.

This relation is explicitly stored as:

- evidence class: `derived_from_authoritative_map`;
- source: KDFWR 2025 Mast Survey Report, Figure 4;
- scope: regional classification only.

It is not represented as a KDFWR property-level survey observation.

A future multi-property implementation should replace one-off mapped relations with a source-controlled, reproducible survey-region geography if KDFWR or the referenced USFS classification can be operationalized cleanly.

## Current-year handling

As of 2026-09-25, the KDFWR report index still lists 2025 as the latest Kentucky Mast Survey report.

Therefore:

- the 2025 context can be materialized as an exact-year annual regional proxy;
- the 2026 context must report annual mast state as `unavailable`;
- 2025 ratings are not carried forward into 2026;
- the completed 2026 context may still be `partial` because Batch 5A mast capacity remains available.

When a 2026 KDFWR report is published and canonically ingested, refreshing the 2026 row will promote the exact-year annual proxy without changing Batch 5A.

## Evidence semantics

### PBA

PBA means the percentage of surveyed trees bearing any mast.

KDFWR explicitly notes that PBA is not an abundance metric: a tree with one acorn and a tree with many acorns both count as bearing mast.

### PCA

PCA is the estimated percentage of tree crown bearing mast.

It is a closer production-intensity measure than PBA, but it still does not establish mast on the ground, mast accessibility, or mast abundance at the selected property.

### Regional proxy

Statewide/East/West results remain regional evidence for an unsurveyed property. KDFWR reports substantial site-to-site variation, including variation between nearby sites.

### Beech

KDFWR cautions that beechnut results are uncertain because nut viability is not routinely checked with float tests.

## Database products

Batch 5B adds:

- `farm_watch.mast_survey_reports_v1`
- `farm_watch.mast_survey_group_results_v1`
- `farm_watch.property_mast_survey_region_v1`
- `farm_watch.property_mast_resource_context_v1`

Internal readers:

- `farm_watch_resolve_mast_resource_context_v1_internal`
- `farm_watch_refresh_mast_resource_context_v1_internal`
- `farm_watch_get_mast_resource_context_v1_internal`

All tables and readers remain service-only.

The validation property is initially materialized for survey years 2024, 2025, and 2026. The 2026 row deliberately preserves the current-year source gap rather than substituting 2025 evidence.

## Farm Watch evidence-stack integration

`deer-evidence-stack-v1` continues to expose `mast-capacity` as a neutral materialized spatial product and separately exposes `mast_resource_context` for the requested calendar year.

This preserves the architecture required for later FW-D07 evaluation:

- spatial capacity available;
- exact-year annual survey state available or unavailable;
- property observation available or unavailable;
- deer-specific mast response remains downstream.

## Interpretation boundary

`mast-resource-context-v1` does not establish:

- observed mast-producing trees at each BIGMAP pixel;
- property-specific mast abundance from a regional survey;
- acorns/nuts present on the ground;
- current mast consumption;
- deer attraction or avoidance;
- deer movement, bedding, travel, or habitat quality;
- a management recommendation.

Those require separate evidence and, for deer-specific conclusions, the science-transfer gates in the deer evidence ledger.
