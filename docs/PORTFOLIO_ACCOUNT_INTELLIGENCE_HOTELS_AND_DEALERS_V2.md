# Portfolio Account Intelligence — Hotels & Dealers v2

Status: deployed to production on 2026-09-07.

V2 expands the generic hotel/dealership portfolio-account layer created in V1 and records the first stable multi-account baseline for these two archetypes.

## Production migrations added in V2

- `seed_swope_and_commonwealth_portfolio_accounts_v1`
- `generic_portfolio_exact_crosswalk_refresh_v1`
- `close_swope_commonwealth_portfolio_research_v1`
- `seed_dan_cummins_portfolio_account_v1`
- `close_dan_cummins_portfolio_research_v1`

These extend the earlier V1 migrations:

- `generic_portfolio_account_foundation_v1`
- `seed_hotel_and_dealership_portfolio_accounts_v1`
- `fix_musselman_hotel_facility_links_v1`
- `resolve_hotel_dealer_exact_buildings_and_musselman_facilities_routes_v1`
- `close_initial_hotel_dealer_research_and_aggregate_semantics_v1b`
- `portfolio_account_opportunity_context_v1`
- `seed_general_hotels_aggregate_account_v1`
- `enrich_neil_huffman_facilities_route_v1`

## Core semantics

The generic portfolio-account architecture keeps these concepts distinct:

- account / operating company
- physical site / campus / hotel property
- business unit / dealership franchise / hotel brand affiliation
- physical building footprint(s)
- operations route
- procurement/vendor route
- current service need

For dealerships, multiple brands at one address do not automatically create multiple physical-site leads.

For hotels, brand/franchisor, owner, manager and facilities authority remain separate concepts.

## Reusable exact-address resolver

V2 adds:

`scout.refresh_portfolio_account_exact_crosswalks()`

This applies the same exact normalized-address discipline used by property-management intelligence to generic hotel/dealer portfolio sites.

- unique exact FEMA address match: resolved at 0.99 confidence
- legitimate multi-building exact-address site: resolved at 0.97 confidence
- rejected links remain rejected
- unresolved sites are not proximity-matched merely to improve a coverage metric

Direct execution is restricted to service-role/internal use.

## Current roster-backed production cohort

All roster-backed accounts below currently have:

- `research_gap_count = 0`
- `research_coverage_pct = 100.0`
- `missing_steps = []`
- `next_research_step = monitor_account`

| Account | Archetype | Serviceable sites | Business units | Crosswalked sites | Resolved buildings | Physical crosswalk coverage |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Bachman Auto Group | dealership_group | 6 | 9 | 5 | 5 | 83.3% |
| Dan Cummins Auto Group | dealership_group | 5 | 5 | 2 | 3 | 40.0% |
| Neil Huffman Auto Group | dealership_group | 7 | 10 | 3 | 3 | 42.9% |
| Oxmoor Auto Group | dealership_group | 9 | 9 | 5 | 5 | 55.6% |
| Swope Family of Dealerships | dealership_group | 6 | 6 | 3 | 3 | 50.0% |
| Commonwealth Hotels | hotel_management | 8 | 8 | 5 | 5 | 62.5% |
| Musselman Hotels | hotel_management | 10 | 10 | 6 | 6 | 60.0% |

Physical crosswalk coverage is intentionally lower than research coverage where current public building corpora do not support a defensible exact identity.

## Aggregate hotel managers

Two hotel-management organizations remain aggregate strategic/account contexts rather than fabricated physical-site rosters:

### Schulte Hospitality Group

- account class: `aggregate_strategic_account`
- documented current scale: 250+ properties
- operations/procurement leadership documented
- complete public site roster is not materialized into Scout
- site-level current need remains unresolved unless a specific property is independently linked
- queue state: `monitor_account`

### General Hotels Corporation

- account class: `aggregate_portfolio_account`
- documented current scale: 50 hotels under management
- public portfolio mixes fully managed, revenue-managed and development relationships
- site-level facilities relationships are not inferred from every portfolio card
- queue state: `monitor_account`

## Commonwealth Hotels

V2 adds Commonwealth as a regional hotel-management portfolio account using only hotels explicitly listed on its current first-party management portfolio.

Seeded regional sites:

- Hampton Inn Louisville Airport — 800 Phillips Lane, Louisville, KY
- Residence Inn Louisville Airport — 700 Phillips Lane, Louisville, KY
- SpringHill Suites Louisville Airport — 820 Phillips Lane, Louisville, KY
- Tru by Hilton Louisville Airport — 810 Phillips Lane, Louisville, KY
- Hampton Inn Cincinnati Airport — 7393 Turfway Road, Florence, KY
- Residence Inn Cincinnati Airport — 2811 Circlepoint Dr, Erlanger, KY
- Courtyard Cincinnati Airport — 3990 Olympic Blvd, Erlanger, KY
- Holiday Inn Express & Suites Cincinnati — 200 Crescent Avenue, Covington, KY

Current Scout state:

- 8 regional serviceable hotel sites
- 5 exact-address physical crosswalks
- 100% research coverage
- VP Operations route documented: Jon Gustin
- VP Purchasing route documented: Lisa G. Litke
- company-wide 50+ hotel scale stored separately from the eight regional sites
- exterior-maintenance supplier onboarding is not assumed merely because a purchasing executive exists
- current need scan: no active Scout opportunity currently resolved on crosswalked buildings

## Swope Family of Dealerships

V2 adds six current Central Kentucky physical dealership sites from the current first-party directory:

- Swope Chrysler Dodge Jeep Ram — 1012 N Dixie Hwy, Elizabethtown
- Bob Swope Ford — 1307 N Dixie Ave, Elizabethtown
- Swope Hyundai — 1104 N Dixie Ave, Elizabethtown
- Swope Mitsubishi — 253 S Dixie Blvd, Radcliff
- Swope Nissan — 1100 N Dixie Hwy, Elizabethtown
- Swope Toyota — 1085 N Dixie Ave, Elizabethtown

Current Scout state:

- 6 physical sites / 6 business units
- 3 exact-address physical crosswalks
- 100% research coverage
- group main route documented
- public building/facilities role unresolved
- public centralized exterior/facilities vendor route unresolved
- automotive service departments are not treated as building-facilities contacts
- current need scan: no active Scout opportunity currently resolved on crosswalked buildings

## Dan Cummins Auto Group

V2 adds five current first-party Central Kentucky dealership campuses:

- Chevrolet Buick of Paris
- Ford Lincoln — Nicholasville
- Chrysler Dodge Jeep RAM of Paris
- Chevrolet Buick of Georgetown
- Chrysler Dodge Jeep RAM of Georgetown

Current Scout state:

- 5 physical sites / 5 business units
- 2 crosswalked sites
- 3 resolved building footprints
- one exact-address dealership site legitimately maps to multiple building footprints
- 100% research coverage
- group route documented
- public facilities/procurement route unresolved
- current need scan: no active Scout opportunity currently resolved on crosswalked buildings

## Dealer-group role quality

Current operations-route status among roster-backed dealer groups:

- Neil Huffman Auto Group: group Facilities Manager documented
- Bachman Auto Group: public portfolio facilities role not resolved
- Oxmoor Auto Group: public portfolio facilities role not resolved
- Swope Family of Dealerships: public portfolio facilities role not resolved
- Dan Cummins Auto Group: public portfolio facilities role not resolved

Dealership automotive service and parts departments are not accepted as substitutes for building/facilities authority.

## Opportunity integration

`scout.get_opportunity_spine_projection(candidate_key)` can now include additive `portfolio_account` context when a visible opportunity is already physically linked to a resolved hotel/dealership portfolio building.

Guardrails:

- no sister-site enumeration solely because one property is visible
- no portfolio multiplier applied to ranking yet
- no current demand inferred from account membership
- no ownership inferred from management/operation

At the V2 baseline, none of the currently resolved hotel/dealer buildings carries an active Scout opportunity. This is represented as `not currently resolved`, not `no need`.

## Research-complete semantics

A roster-backed hotel/dealer site is considered research-complete when either:

1. it has a resolved physical building link; or
2. it has a current reviewed resolution outcome explaining that current sources do not support a defensible building identity.

This mirrors the V4 property-management coverage doctrine and prevents incomplete public building data from creating endless research queues or encouraging false matches.

## Release validation

After the V2 expansion:

- `agent_contract.assert_tool_registry_integrity_v1()` passes
- `agent_contract.assert_architecture_doctrine_v1()` passes
- `agent_privacy.assert_rls_posture_v1()` passes
- unverified multifamily rows in `cleaning.v_exterior_cleaning_push_candidates`: 0
- all generic portfolio evidence remains internal with no direct public grants

## Next expansion tier

Preferred next research order:

1. Don Franklin Auto — large Kentucky dealer portfolio; resolve a regional subset before materializing statewide scale
2. Peachtree Group — Louisville/Florence hotel holdings; distinguish owner/operator/manager roles per property
3. First Hospitality — Louisville Tempo property plus broader portfolio context; local leverage currently limited
4. additional hotel managers with multiple attributable KY/IN properties
5. additional dealer groups only where current first-party physical location rosters are available

Do not expand account counts merely by scraping brand/franchise directories. Portfolio relationships must remain source-backed and operationally attributable.