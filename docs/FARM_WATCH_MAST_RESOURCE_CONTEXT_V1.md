# Farm Watch Mast Resource Context v1

Status: Batch 5B production deployed and validated — 2026-09-25; 2026 exact-year KDFWR annual component unavailable pending publication/ingest

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

## Production validation — 2026-09-25

Production migration and validation completed for `validation-property-01`.

- canonical KDFWR reports stored: 2 (2024 and 2025);
- canonical annual group rows stored: 24 (4 groups × 3 scopes × 2 years);
- validation-property survey region: `west`, derived from authoritative KDFWR Figure 4;
- 2025 context: `available`, identity `f570fd3d2c10e4c2bc9a546008bb484ab78702c4e1282f39fc4c54096ee46e69`;
- 2026 context: `partial`, identity `99ba13dbad88b07afa3c2522d0aaa63db145aef758113eeb575ae9e646fe1992`;
- 2026 mast capacity: `available`;
- 2026 annual mast proxy: `unavailable`, latest canonical report year 2025, `applied_prior_year=false`;
- current property mast observations: none.

The deer evidence stack exposes both the existing `mast-capacity` product and the separate 2026 `mast_resource_context`, preserving the intended capacity-versus-annual-state boundary.

Both required agent-contract assertions passed after deployment. Supabase advisory review identified no Batch 5B-specific release blocker; project-wide informational RLS/no-policy and unused-index notices remain consistent with existing service-only/private table patterns.

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
