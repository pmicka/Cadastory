# Property Management Portfolio Intelligence v1

Status: deployed to production on 2026-09-07.

## Purpose

Scout now treats a large property-management relationship as a strategic account dimension rather than treating every physical building as an isolated lead.

The model deliberately separates:

1. legal ownership,
2. property/facility management responsibility,
3. a managed property/site, and
4. the physical building footprints that belong to that property/site.

A management relationship never implies ownership. A property/site may contain multiple buildings. Portfolio leverage is currently a weak ranking tiebreaker only; Scout does not assume a revenue, conversion, or ROI multiplier from portfolio size.

## Production migrations

The following Supabase migrations compose v1:

- `20260907173222 property_management_portfolio_foundation`
- `20260907173243 portfolio_leverage_ranking_tiebreaker`
- `20260907173311 include_multifamily_exterior_need_candidates`
- `20260907174357 property_site_building_crosswalk_and_denton_floyd_portfolio`
- `20260907174552 property_portfolio_identity_gate_and_strategic_account_surface`

The exact applied SQL is retained in `supabase_migrations.schema_migrations` in project `ufpkjaadmmpmeogzhrcq`.

## Core data model

`core.organization_facilities` remains the canonical organization-to-facility relationship table. It now carries relationship currentness and source metadata:

- `relationship_status`
- `valid_from`
- `valid_to`
- `source_url`
- `source_authority`

`relationship_type = 'manages'` is used for documented management responsibility.

`scout.property_building_links` is the property/site-to-building crosswalk. It is intentionally separate from the management relationship. A row can be `candidate`, `resolved`, `rejected`, or `superseded` and preserves match basis, confidence, evidence, and observation timestamps.

## Internal resolution surfaces

- `scout.v_property_management_facilities` — current source-backed management relationships; exposes whether the linked facility is a property/site or a direct building record.
- `scout.v_property_management_portfolios` — portfolio aggregation per management organization.
- `scout.v_property_building_resolution_queue` — candidate property-to-FEMA-building matches for review; proximity alone is not sufficient for a resolved link.
- `scout.v_property_management_resolution_queue` — exterior-cleaning records that still need property identity and/or manager resolution.
- `scout.v_opportunity_property_management_context` — management and portfolio context for opportunities only after a property-to-building relationship has been resolved.
- `scout.v_property_management_strategic_accounts` — qualitative strategic-account classification, contact-route state, portfolio scale, and crosswalk coverage.

These are internal views; anonymous/authenticated direct access is revoked.

## Opportunity contract integration

`scout.get_opportunity_spine_projection(candidate_key)` now adds an optional `property_management` object. This is additive to the existing spine contract.

`scout.find_opportunities_for_operator(...)` retains its public return schema. Documented portfolio scope and the count of active opportunities inside a documented portfolio are used only after existing fit, public-route, time-sensitivity, presentation-name, and contactability ordering. Portfolio leverage is therefore a reversible tiebreaker rather than an assumed economic multiplier.

## Multifamily handling and identity gate

The FEMA USA Structures corpus contains 3,524 records classified as `Multi - Family Dwelling` in the collected data. The exterior need refresh now retains qualifying multifamily buildings as research candidates when they are at least 10,000 square feet and have the same evidence-backed environmental exposure context used by other exterior-cleaning candidates.

The first Louisville review exposed false or ambiguous FEMA occupancy classifications. For that reason, multifamily rows are not allowed through `cleaning.v_exterior_cleaning_push_candidates` until a source-backed property/site identity has been resolved to the building through `scout.property_building_links` at confidence >= 0.90.

Current production state after the gate:

- 2,855 multifamily buildings retain relevant exposure context for research.
- 187 are in the multifamily identity-verification queue.
- 992 exterior-cleaning candidates remain pushable.
- 0 unverified FEMA multifamily rows are present in the public exterior opportunity candidate set.

This preserves potentially valuable discovery inventory without turning an uncertain FEMA classification into a customer lead.

## First strategic account: Denton Floyd Real Estate Group

The first portfolio-first collector/seed uses Denton Floyd's official management-company property listing rather than attempting to infer management from parcel ownership.

Source evidence:

- `https://www.dentonfloyd.com/index.aspx` — Denton Floyd describes property management as a company division and reports more than 16,000 units under management or development across several states. That combined management/development number must not be represented as a current managed-unit count.
- `https://www.dentonfloyd.com/about.aspx` — the company states that it manages apartment communities.
- `https://www.dentonfloyd.com/searchlisting.aspx` — current first-party property portfolio used for property names, addresses, and coordinates.

Production facts currently resolved:

- 32 documented managed properties in the first-party portfolio.
- 27 of those properties are in KY/IN/OH.
- account class: `strategic_account`.
- portfolio leverage band: `large_documented_portfolio`.
- durable general company phone route documented from the official site.
- no procurement route is claimed yet.
- one high-confidence property-to-building crosswalk is resolved for Clarksville Lofts; weaker geospatial candidates remain in review.

The organization record explicitly sets `ownership_claimed = false` in property evidence. The source supports management, not ownership.

## Lead-value policy

Portfolio facts are meant to support a future decomposition such as:

`immediate opportunity value + portfolio option value`

but v1 does not assign a dollar value or fixed multiplier to portfolio option value. Stronger weighting should be learned from outcomes such as:

- first-property win rate,
- second-site conversion,
- time to multi-site expansion,
- repeat-job frequency,
- revenue per management relationship,
- vendor-onboarding friction, and
- whether purchasing is centralized or property-local.

## Required release checks

Both required doctrine assertions passed after deployment:

```sql
select agent_contract.assert_tool_registry_integrity_v1();
select agent_contract.assert_architecture_doctrine_v1();
```

The opportunity spine was refreshed after the identity gate and contained 18,841 rows at contract version `2.0`.

## Next collector priority

Continue portfolio-first rather than address-first:

1. official regional property-management portfolio pages,
2. first-party property pages and current management statements,
3. property/site record creation,
4. conservative property-to-building crosswalk,
5. durable operations/facilities/vendor contact route,
6. procurement/vendor onboarding route where documented,
7. only then allow portfolio leverage to affect a specific opportunity.

Likely next regional strategic accounts should be selected by documented local portfolio scale and source quality, not brand familiarity alone.
