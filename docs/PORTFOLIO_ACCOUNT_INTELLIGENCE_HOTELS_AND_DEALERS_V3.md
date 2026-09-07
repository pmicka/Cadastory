# Portfolio Account Intelligence — Hotels & Dealers v3

Status: deployed to production on 2026-09-07.

V3 extends the generic account→portfolio→site→building model introduced for hotel-management and dealership groups. It adds Don Franklin Auto and Peachtree Group, separates Louisville-pilot scope from enterprise scale, adds a reusable portfolio current-signal scan, and preserves management/ownership/site/business-unit distinctions.

## New production migrations

- `portfolio_account_pilot_scope_semantics_v2`
- `seed_don_franklin_and_peachtree_portfolios_v3`
- `close_don_franklin_peachtree_and_enterprise_scale_v3`
- `portfolio_signal_semantics_and_scale_context_v3`

## Current roster-backed baseline

Production totals after V3:

- roster-backed hotel/dealer accounts: **9**
- serviceable physical sites: **64**
- Louisville-pilot sites: **63**
- research-complete sites: **64**
- research gaps: **0**
- physically crosswalked sites: **38**
- resolved building footprints: **40**

All roster-backed account queues currently resolve to `monitor_account`.

## Pilot scope vs enterprise scale

V3 makes three portfolio-scope concepts distinct:

1. `serviceable_site_count` — individually materialized operating/lease-up physical sites.
2. `pilot_serviceable_site_count` — materialized sites explicitly scoped to Scout's Louisville-centered pilot.
3. `enterprise_property_count_minimum` — first-party aggregate account scale when documented.

The corresponding account classes remain separate:

- `pilot_account_class`
- `enterprise_account_class`

Enterprise scale never creates fake local sites and never changes physical crosswalk counts.

### Don Franklin Auto

Current first-party company scale:

- 29 dealerships
- 17 brands

Scout materializes **11 clearly pilot-market campuses** rather than all Kentucky locations:

- Don Franklin Bardstown Buick Chevrolet
- Don Franklin Campbellsville Chevrolet GMC
- Don Franklin Campbellsville Chrysler Dodge Jeep Ram
- Don Franklin Hardin County Ford
- Don Franklin Lexington Buick GMC
- Don Franklin Lexington Hyundai
- Don Franklin Lexington Nissan
- Genesis of Lexington
- Don Franklin Lincoln Elizabethtown
- Don Franklin Nicholasville Hyundai
- Don Franklin Nicholasville Mitsubishi

Production coverage:

- serviceable/pilot sites: **11**
- crosswalked sites: **8**
- resolved buildings: **9**
- research coverage: **100%**
- physical crosswalk coverage: **72.7%**
- pilot account class: `portfolio_account`
- enterprise account class: `portfolio_account`
- enterprise property count minimum: **29**

No public portfolio facilities role or centralized exterior/vendor onboarding route was resolved. Automotive service/parts departments remain explicitly disallowed as substitutes for building/facilities authority.

### Peachtree Group

Current first-party hotel-management scale:

- **112 hotels managed**
- **14,053 keys**
- **27 states**
- **30 brands**

Two current Kentucky hotels from Peachtree's hotel-management portfolio are materialized locally:

- Homewood Suites by Hilton Louisville Airport — 130 Central Avenue, Louisville, KY
- Hilton Garden Inn Florence Cincinnati Airport South — 205 Meijer Drive, Florence, KY

Production coverage:

- serviceable/pilot sites: **2**
- crosswalked sites: **1**
- resolved buildings: **1**
- research coverage: **100%**
- physical crosswalk coverage: **50%**
- pilot account class: `multi_site_account`
- enterprise account class: `strategic_account`
- enterprise property count minimum: **112**

Peachtree's first-party hotel-management portfolio marks both materialized hotels as Owned. Scout records ownership as a separate `owns` relationship while portfolio counting uses the controlling `manages` relationship, preventing double-counting.

Documented operations routes:

- Vickie Callahan — President, Hospitality Management
- Steve Mackenzie — EVP Operations, Hospitality Management
- general corporate route: 404-497-4111

No public exterior/facilities supplier onboarding route is claimed.

## Controlling relationship semantics

`scout.v_portfolio_account_facilities` now counts only the controlling portfolio relationship:

- hotel-management account → `manages`
- dealership group → `operates`

Separate ownership relationships can coexist without duplicating physical-site or business-unit counts.

## Reusable current-signal scan

New internal function:

`scout.refresh_portfolio_account_current_need_scans()`

It scans physically resolved portfolio sites against Scout's exterior-cleaning push-candidate layer and records time-bounded account evidence.

Important semantic change:

- active push candidate → `active_exterior_opportunity_signal_resolved`
- no active push candidate → `no_active_exterior_opportunity_currently_resolved`

The function always preserves:

- `specific_need_proven = false`

unless some future evidence layer explicitly proves visible condition/need. A proxy/signal does not prove service requirement, buyer intent, procurement event, contract award, or revenue.

Current scan result across all 9 roster-backed accounts:

- accounts scanned: **9**
- accounts with active exterior opportunity signals: **1**
- specific need inferred: **false**

## Don Franklin Bardstown signal

The sole current portfolio-linked exterior signal is:

**Don Franklin Bardstown Buick Chevrolet**

- address: 120 W John Rowan Blvd, Bardstown, KY
- building occupancy: Retail Trade
- building area: ~30,376.79 sq ft
- signal kind: `cleaning_need_proxy`
- signal strength: `medium`
- signal confidence: **0.52**
- contamination pressure: `medium`
- appearance sensitivity: `high`

Scout's reason remains:

> Moderate proximity to an operating distillery/ethanol-vapor anchor. Use as prospecting/inspection evidence only until visible staining is verified.

This is not treated as confirmed staining or a contract-ready need.

## Opportunity projection context

`scout.v_opportunity_portfolio_account_context` now exposes, for an already-visible opportunity only:

- specific linked site/account
- physical site/business-unit identity
- serviceable site count
- tri-state regional count
- Louisville-pilot site count
- pilot account class
- enterprise property count minimum
- enterprise account class
- crosswalk/research coverage

It does **not** enumerate sister sites merely because they share an account.

The live Bardstown projection currently shows:

- Don Franklin pilot sites: **11**
- Don Franklin enterprise dealerships: **29**
- physical crosswalk coverage: **72.7%**
- research coverage: **100%**
- portfolio scoring treatment: context only

No portfolio revenue, conversion, close-probability, or ROI multiplier is applied.

## Existing aggregate hotel accounts

V3 preserves the existing aggregate-only semantics for:

- Schulte Hospitality Group — 250+ properties documented previously
- General Hotels Corporation — 50+ hotels documented previously

Aggregate account scale remains separate from resolved local physical sites.

## Release validation

After V3:

- `agent_contract.assert_tool_registry_integrity_v1()` passes
- `agent_contract.assert_architecture_doctrine_v1()` passes
- `agent_privacy.assert_rls_posture_v1()` passes
- unverified multifamily leak count remains **0**
- Bardstown opportunity spine projection returns normally with additive `portfolio_account` context

## Guardrails preserved

- hotel brand/franchisor != manager != owner
- dealership brand/business unit != physical dealership campus
- portfolio relationship != specific current service need
- opportunity signal != confirmed condition
- enterprise scale != local site count
- local site count != physical building count
- ownership does not imply vendor authority
- automotive service department does not imply facilities authority
- no sister-site enumeration through portfolio context
- no portfolio value multiplier until observed conversion/revenue outcomes support one
