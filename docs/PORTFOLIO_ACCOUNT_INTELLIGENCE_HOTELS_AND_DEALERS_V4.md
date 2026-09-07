# Portfolio Account Intelligence — Hotels and Dealerships V4

Status: deployed to production on 2026-09-07.

V4 expands Scout's generic account→portfolio→site→building model for hotel management companies and dealership groups while preserving the distinctions established in prior versions:

- account scale is not local physical-site count;
- hotel brand/franchisor is not hotel manager, owner, or facilities authority;
- dealership franchise/business unit is not a physical dealership campus;
- portfolio relationship is not proof of current service need;
- opportunity signals/proxies are not proof of visible condition, buyer intent, procurement, contract award, or revenue;
- research coverage is distinct from physical building-crosswalk coverage.

## Production baseline

After the V4 expansion:

- roster-backed hotel/dealer accounts: **13**
- serviceable physical sites: **85**
- pilot-scope sites: **84**
- physically crosswalked sites: **47**
- resolved building footprints: **50**
- research-complete sites: **85**
- research gaps: **0**

All roster-backed account queues are drained to `monitor_account` after current source review.

## V4 additions

### White Lodging

Current first-party Louisville portfolio materialized as five managed hotel sites:

1. Hotel Distil Louisville Downtown — 101 West Main Street
2. Homewood Suites by Hilton Louisville Downtown — 635 West Market Street
3. Aloft Louisville Downtown — 102 West Main Street
4. Moxy Louisville Downtown — 100 W Washington Street
5. Marriott Louisville Downtown — 280 West Jefferson Street

Enterprise scale is stored separately at approximately 60 hotels / 15,000+ rooms based on current first-party company material.

Buyer/operations research resolves distinct corporate functions:

- Joe Pagone — Senior Vice President of Operations
- Greg Ruff — Vice President, Facilities & Capital Planning
- Pete Reardon — Vice President, Purchasing and Procurement

These role routes are available through White Lodging's corporate channel. The existence of purchasing/procurement leadership does not prove a public exterior-maintenance supplier onboarding path.

Physical identity:

- five serviceable / pilot sites
- one exact physical crosswalk currently resolved
- four unresolved sites have current reviewed outcomes
- Aloft has an independent exact-address construction-project point, but the nearest lodging footprint is approximately 24m away at a different address; Scout does not promote that plausible match to identity.

Current signal:

- Hotel Distil, 101 W Main, currently has a medium `cleaning_need_proxy`, confidence 0.52, associated with proximity to an operating distillery/ethanol-vapor anchor.
- This remains inspection/prospecting evidence only until visible condition is verified.
- `specific_need_proven = false`.

### Jeff Wyler Automotive Family

Enterprise-scale evidence is intentionally stored with source inconsistency preserved:

- current first-party site counter: 37 locations / 31 brands
- current narrative copy elsewhere on the same site still says “over 23 locations” / older franchise language

Scout uses the current 37-location counter as scale context only; it is not treated as a fully normalized legal-location roster.

Nine pilot-market physical campuses are materialized across Louisville, Clarksville, Northern Kentucky, and Lawrenceburg.

Physical identity:

- nine serviceable / pilot sites
- five sites physically crosswalked
- six resolved building footprints
- four current reviewed unresolved outcomes
- Jeff Wyler Honda Auto Mall has an independent exact-address construction-project point, but the nearest repair-services footprint is about 20m away at 5224 Dixie Hwy rather than 5244 Dixie Hwy; Scout leaves the relationship unresolved.

Buyer-route guardrail:

- current first-party group contact is captured as a general route
- vehicle sales/service/parts departments are not treated as building-facilities or exterior-service procurement authority
- no public portfolio facilities role or exterior vendor onboarding path was resolved in current research

Current signal:

- Jeff Wyler CDJR of Lawrenceburg, 875 E Eads Pkwy, currently carries a medium `cleaning_need_proxy`, confidence 0.52, from the same distillery/ethanol-vapor exposure class.
- The signal is prospecting/inspection evidence, not confirmed staining, buyer intent, or service demand.

### John Jones Auto Group

Current first-party portfolio publishes seven business locations in Southern Indiana / the Louisville service area.

Physical-site normalization reduces this to six physical sites because two Corydon franchises share 1735 Gardner Ln NW. The shared Corydon campus therefore has `business_unit_count = 2` rather than producing duplicate physical leads.

Current state:

- six serviceable / pilot physical sites
- seven business units
- three physically crosswalked sites
- three resolved building footprints
- six research-complete sites
- zero research gaps
- no current exterior opportunity signal resolved

Vehicle service, fleet, police-pursuit, parts, and sales functions are not treated as building-facilities buyer routes.

### First Hospitality

Enterprise scale is stored separately from local physical coverage:

- 60+ hotels
- 9,000+ keys
- one current Louisville hotel materialized from the first-party portfolio: Tempo by Hilton Louisville Downtown NuLu, 710 E Jefferson Street

Current operations route:

- Dave Montrose — Chief Operating Officer
- direct first-party email route captured from the current team page

An older facilities appointment was deliberately not promoted as current evidence.

Current state:

- one serviceable / pilot site
- no exact current building crosswalk
- one reviewed source-gap outcome
- 100% research coverage
- enterprise `portfolio_account`, local/pilot `ordinary_account`
- no current exterior opportunity signal resolved

## Existing roster-backed cohort retained

V4 preserves and revalidates the earlier roster-backed accounts:

- Musselman Hotels
- Commonwealth Hotels
- Peachtree Group
- Oxmoor Auto Group
- Neil Huffman Auto Group
- Bachman Auto Group
- Swope Family of Dealerships
- Dan Cummins Auto Group
- Don Franklin Auto

Aggregate-only hotel accounts remain separate where a defensible local facilities-managed roster is unavailable or management modes are mixed:

- General Hotels Corporation
- Schulte Hospitality Group

## Account-scale semantics

The generic portfolio views now distinguish:

- `serviceable_site_count`
- `regional_serviceable_site_count` — legacy tri-state KY/IN/OH measure
- `pilot_serviceable_site_count` — actual Scout pilot scope
- `enterprise_property_count_minimum`
- `pilot_account_class`
- `enterprise_account_class`

This prevents a statewide or national portfolio from masquerading as a larger local serviceable footprint.

Example:

- Peachtree Group: two current materialized KY managed sites → pilot `multi_site_account`; 112 managed hotels enterprise-wide → enterprise `strategic_account`.
- First Hospitality: one current materialized Louisville site → pilot `ordinary_account`; 60+ hotels enterprise-wide → enterprise `portfolio_account`.

## Exact-crosswalk automation

The reusable function remains:

`scout.refresh_portfolio_account_exact_crosswalks()`

Rules:

- unique exact normalized address: 0.99 confidence
- legitimate multiple-building exact-address campus: 0.97 confidence
- rejected links stay rejected
- unresolved sites do not receive proximity-only auto-links

After V4, the complete generic roster universe contains 85 serviceable hotel/dealer sites, with 47 sites linked to 50 resolved buildings.

## Research-coverage closure

Every serviceable roster site now ends in one of two states:

1. resolved physical building crosswalk; or
2. current reviewed unresolved outcome with an expiry date and explicit source/ambiguity basis.

That yields 85/85 research-complete sites without incentivizing weak identity matching.

## Current opportunity-signal scan

`scout.refresh_portfolio_account_current_need_scans()` now scans the 13 roster-backed accounts.

Current result:

- 13 accounts scanned
- 3 accounts have one or more current exterior opportunity signals on physically linked sites
- `specific_need_inferred = false`

Accounts with current signals:

1. Don Franklin Auto — Bardstown Buick Chevrolet, 120 W John Rowan Blvd
2. White Lodging — Hotel Distil, 101 W Main
3. Jeff Wyler Automotive Family — CDJR Lawrenceburg, 875 E Eads Pkwy

All three current signals are medium-strength 0.52 `cleaning_need_proxy` records associated with distillery/ethanol-vapor exposure context. They are prospecting/inspection signals only.

## Opportunity projection behavior

The opportunity spine projection includes optional `portfolio_account` context only after a visible opportunity is physically linked to a source-backed portfolio site.

Context exposes relevant account facts such as:

- account name/type
- portfolio archetype
- local site identity
- brands/business units
- pilot site count/class
- enterprise scale/class
- physical crosswalk coverage
- research coverage

It does not enumerate hidden sister sites or apply a portfolio revenue/close-probability multiplier.

## Production migrations in this tranche

- `20260907211541 seed_white_lodging_and_jeff_wyler_portfolios_v4`
- `20260907211638 fix_white_lodging_jeff_wyler_raw_and_facilities_v4`
- `20260907211916 close_white_lodging_jeff_wyler_site_research_v4`
- `20260907212110 seed_john_jones_and_first_hospitality_portfolios_v4`
- `20260907212133 close_john_jones_first_hospitality_site_research_v4`

The first White Lodging/Jeff Wyler seed exposed a PostgreSQL snapshot nuance: source rows inserted by one data-modifying CTE were not visible to sibling raw-record insertion logic in the same SQL statement. No incorrect facility rows were created. The repair split source creation from raw/facility seeding into a subsequent migration.

## Release validation

All production assertions pass:

```sql
select agent_contract.assert_tool_registry_integrity_v1();
select agent_contract.assert_architecture_doctrine_v1();
select agent_privacy.assert_rls_posture_v1();
```

Additional regression:

- unverified multifamily rows leaking into the public exterior-cleaning push set: **0**
- generic hotel/dealer research gaps: **0**

## Next phase

The architecture is stable. Continued hotel/dealer work should primarily be:

- new first-party portfolio coverage;
- refreshed physical crosswalks as building sources improve;
- buyer/vendor-route resolution;
- current-signal monitoring;
- outcome instrumentation for first-site win → additional-site expansion.

Do not introduce a portfolio-value multiplier until observed conversion/revenue outcomes support one.