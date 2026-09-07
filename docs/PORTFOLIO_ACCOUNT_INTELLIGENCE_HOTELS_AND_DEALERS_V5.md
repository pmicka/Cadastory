# Portfolio Account Intelligence — Hotels and Dealerships V5

Status: deployed to production on 2026-09-07.

V5 extends the V4 hotel/dealership portfolio baseline with Hospitality Ventures Management Group (HVMG) and Germain Motor Company. The architecture and guardrails remain unchanged: local physical-site coverage, enterprise portfolio scale, physical building identity, buyer route, and current opportunity signals remain separate facts.

## Verified production baseline

- roster-backed hotel/dealer accounts: **15**
- serviceable physical sites: **93**
- pilot-scope serviceable sites: **92**
- physically crosswalked sites: **51**
- resolved building footprints: **54**
- research-complete sites: **93**
- research gaps: **0**

All roster-backed research queues are drained to `monitor_account`.

The current opportunity-signal scanner covers all 15 accounts and continues to infer **no specific service need** from proxy evidence.

## Hospitality Ventures Management Group (HVMG)

Current first-party portfolio/careers evidence supports five Kentucky managed hotels:

1. Hilton Garden Inn Louisville Downtown — 350 West Chestnut Street, Louisville
2. Home2 Suites by Hilton Louisville Downtown NuLu — 240 South Hancock Street, Louisville
3. The Brown Hotel — 335 West Broadway, Louisville
4. DoubleTree Suites by Hilton Lexington — 2601 Richmond Road, Lexington
5. The Campbell House Lexington — 1375 S Broadway, Lexington

Current enterprise context is stored separately at **60 hotels minimum**, based on HVMG's August 2026 first-party announcement describing its current operating portfolio.

### Operations and facilities routes

Current first-party leadership resolves a genuine above-property operating/facilities structure:

- Richard Jones — EVP & Chief Operating Officer
- Ronald Mader — SVP Operations
- Bob Kisker — SVP Operations
- Jamison Conrey — VP Engineering, Capital Projects & Risk Management

The facilities/engineering route is especially relevant to exterior-building services and is stored as a portfolio facilities route through HVMG's corporate channel.

No public exterior-maintenance supplier onboarding workflow was resolved. Operations, engineering/capital, and design/construction responsibility therefore do not become a procurement claim.

### Physical identity

Production state:

- serviceable/pilot sites: **5**
- crosswalked sites: **2**
- resolved buildings: **2**
- physical crosswalk coverage: **40.0%**
- research coverage: **100%**
- research gaps: **0**
- pilot class: `portfolio_account`
- enterprise class: `portfolio_account`

The unresolved sites include Hilton Garden Inn Louisville Downtown, Home2 Suites Louisville NuLu, and The Brown Hotel.

The Brown Hotel has independent exact-address evidence, but the nearest FEMA structure is labeled as a multifamily building at a different 4th Street address. Scout therefore does not create a physical crosswalk from proximity.

## Germain Motor Company

Current first-party Louisville portfolio materializes three distinct physical dealership sites:

1. Land Rover Louisville — 4700 Bowling Boulevard
2. Porsche Louisville — 4720 Bowling Blvd
3. Audi Louisville — 4730 Bowling Boulevard

These are separate physical addresses on the Louisville luxury-auto campus and are therefore separate sites rather than three brands collapsed onto one address.

### Enterprise scale

Current first-party Germain sources are not perfectly consistent:

- current AI-discovery surface, reviewed August 13, 2026: **more than 20 locations across seven regions**
- another current shopping surface reports 18 locations

Scout stores **20+** as enterprise scale context with an explicit source-variation guardrail. It does not treat the number as a normalized exact legal-location roster.

### Buyer-route research

No current group-level building facilities or exterior-service procurement role was resolved from Germain's first-party public surfaces.

The group main contact is retained as a general route only. Vehicle sales, automotive service, and parts departments are not treated as building-maintenance buyer evidence.

### Physical identity

Production state:

- serviceable/pilot sites: **3**
- crosswalked sites: **2**
- resolved buildings: **2**
- physical crosswalk coverage: **66.7%**
- research coverage: **100%**
- research gaps: **0**
- pilot class: `multi_site_account`
- enterprise class: `portfolio_account`

Porsche Louisville has independent exact-address construction-project evidence, but the nearest current building footprints are approximately 24–25m away and use different/absent address labels. The site remains reviewed-ambiguous rather than being force-crosswalked.

## Current exterior opportunity signals

After adding HVMG and Germain, the account signal scan still reports **three accounts with active exterior opportunity signals**, so neither new account introduced a new current signal.

The three existing signals remain:

1. Don Franklin Auto — Bardstown Buick Chevrolet, 120 W John Rowan Blvd
2. White Lodging — Hotel Distil, 101 W Main
3. Jeff Wyler Automotive Family — CDJR Lawrenceburg, 875 E Eads Pkwy

Each is a medium-strength, 0.52-confidence `cleaning_need_proxy` associated with distillery/ethanol-vapor exposure context. Each remains prospecting/inspection evidence only, with `specific_need_proven = false`.

## Research closure semantics

All V5 sites follow the same terminal research contract:

- resolved building crosswalk, or
- current reviewed unresolved outcome with source basis and expiry.

Research completion never means a physical building match was proven.

## Production migrations

V5 expansion migrations:

- `20260907211541 seed_white_lodging_and_jeff_wyler_portfolios_v4`
- `20260907211638 fix_white_lodging_jeff_wyler_raw_and_facilities_v4`
- `20260907211916 close_white_lodging_jeff_wyler_site_research_v4`
- `20260907212110 seed_john_jones_and_first_hospitality_portfolios_v4`
- `20260907212133 close_john_jones_first_hospitality_site_research_v4`
- `seed_hvmg_and_germain_portfolios_v5`
- `close_hvmg_germain_site_research_v5`

## Release validation

All production assertions pass after V5:

```sql
select agent_contract.assert_tool_registry_integrity_v1();
select agent_contract.assert_architecture_doctrine_v1();
select agent_privacy.assert_rls_posture_v1();
```

Additional regression:

- unverified multifamily push leaks: **0**
- roster-backed research gaps: **0**

## Source-quality decision from this tranche

Coyle Nissan was researched as a potential next Southern Indiana group, but current first-party evidence resolved only one defensible Coyle physical site. Scout did not create a multi-site portfolio account merely from the business name or assumed related dealerships.

This is the desired behavior: portfolio leverage should be source-backed, not inferred from naming or brand familiarity.

## Next work

Further hotel/dealer expansion is now predominantly data work. Prioritize accounts only when one of these is available:

- a current first-party physical roster;
- attributable current management/operating responsibility;
- useful operations/facilities/procurement routing;
- or enterprise scale that materially changes account value while local site scope remains separately documented.

Continue to avoid portfolio ranking multipliers until downstream wins and multi-site expansion outcomes are measured.