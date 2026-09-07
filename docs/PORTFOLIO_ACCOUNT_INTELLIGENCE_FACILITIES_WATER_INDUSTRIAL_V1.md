# Portfolio Account Intelligence — Facilities Management, Water Utilities, Industrial/Logistics V1

Date: 2026-09-07
Status: Production baseline

## Scope

This tranche extends Scout's account→portfolio→asset model to three additional commercial structures:

- facilities-management intermediaries,
- water utilities,
- industrial/logistics portfolios.

The implementation reuses Scout's generic organization, facility, evidence, contact, service-area, opportunity-spine, and privacy architecture while preserving archetype-specific relationship semantics.

## Relationship semantics

### Facilities management

Use `facilities_manages` / facilities-management intermediary semantics. Client sites are not invented or enumerated when the facilities-management company keeps its customer roster private.

A facilities-management vendor route is not proof that a particular client site needs service or that a contract is available.

### Water utilities

Water tanks use native WRIS infrastructure identity. They do not require a property→building crosswalk.

The utility relationship is represented as operating a water-system asset portfolio. Operating responsibility is distinct from legal ownership and procurement authority.

### Industrial/logistics

Use the existing `owns`, `manages`, and `operates` semantics as supported by source evidence.

Documented market scale is distinct from individually materialized physical facilities. A first-party claim of 23 properties does not create 23 Scout facility records unless the sites themselves are resolved.

## Facilities-management production state

Initial cohort:

1. City Wide Facility Solutions - Louisville
2. City Wide Facility Solutions - Central Kentucky
3. City Wide Facility Solutions - Cincinnati
4. CBRE Provider Network

All 4 are research-complete and at `monitor_account`.

### City Wide Louisville

First-party sources document:

- managed facility-services model,
- vetted/supervised vendors,
- pressure washing,
- window washing,
- roofing,
- local Directors of Operations and Facility Solutions Managers.

Scout therefore exposes City Wide Louisville as an exterior-cleaning account-access opportunity with `fit_status = ready` and `account_service_fit_status = documented_service_relevance`.

Client sites remain private/unresolved and are not enumerated.

### CBRE Provider Network

First-party provider-network material documents:

- 120,000+ client locations,
- 4.1M annual work orders,
- approximately $4B annual maintenance spend,
- 25,000+ service providers,
- public provider-network application,
- interior and exterior trades.

Pressure washing/exterior cleaning is not explicitly listed, so Scout exposes CBRE as:

`account_service_fit_status = needs_service_fit_verification`

rather than as a ready exterior-cleaning route.

### Growth integration

Facilities-management entries are additive to the existing connection-scoped `account_access_opportunities` surface and remain separate from ordinary site-demand growth options.

Verified regression:

- Jefferson County, KY: Bill Stout + City Wide Louisville + CBRE.
- Fayette County, KY: CBRE only.
- City Wide Louisville does not leak outside its conservative local service geography.
- CBRE remains nationally applicable but explicitly requires account-side service-fit verification.
- No private client-site enumeration is returned.

## Water-utility production state

Scout materialized the complete current Kentucky WRIS water-tank→utility graph represented in the source:

- 149 water-utility portfolios,
- 719 WRIS tanks,
- 719 explicit tank→utility operating relationships.

Current opportunity state:

- 71 utilities have one or more active tank-maintenance signals,
- 150 active tank signals total,
- 110 high-strength signals.

Examples of portfolio leverage visible in production:

- Edmonson County Water District: 18 tanks, 6 active high signals.
- Green-Taylor Water District: 6 tanks, 6 active signals.
- Parksville Water District: 4 tanks, 4 active high signals.
- Warren County Water District: 24 tanks.

### Water-utility opportunity context

Visible water-tank opportunities now receive `water_utility_portfolio` context.

Production smoke for Parksville Tank returns:

- Parksville Water District,
- 4 tanks,
- 4 active high signals,
- 317,000 gallons combined capacity,
- operations route available.

The individual tank signal remains the opportunity evidence. Portfolio context is context-only; no revenue, close-probability, conversion, or contract multiplier is applied.

### Contact closure

All 71 utilities with active tank signals now have an actionable contact route.

Route-quality distribution:

- 5 documented procurement routes,
- 35 direct/named operations routes,
- 31 Kentucky Drinking Water Branch active-system registry fallbacks,
- 0 unresolved.

The registry fallback is intentionally lower-quality than a named superintendent, engineering lead, or procurement route. It is represented as a current authoritative operations/contact fallback keyed by PWSID and explicitly does not prove procurement authority.

This closes the active-signal utility contact queue without flattening route quality.

Utilities without a current tank signal remain monitoring accounts; absence of a current signal is not evidence of no need.

## Industrial/logistics production state

Initial cohort:

1. Link Logistics
2. Prologis
3. Dermody Properties

Production coverage:

- 3 accounts,
- 7 materialized physical sites,
- 4 physically crosswalked sites/buildings,
- 7/7 research-complete,
- 0 research gaps,
- 0 active exterior-cleaning signals on the currently resolved sites.

### Link Logistics

First-party Louisville market evidence documents:

- 23 Louisville properties,
- approximately 5.2M square feet.

Scout currently materializes 3 exact physical sites. The 23-property market count remains separate portfolio-scale evidence.

### Prologis

First-party Louisville market evidence documents:

- 15+ properties,
- 8M+ square feet.

Scout currently materializes 3 exact facilities, 2 of which crosswalk physically.

### Dermody Properties

Scout materializes the currently attributable Airport West facility and records a property-management/operations route. Historical development projects are not treated as current managed assets.

All three industrial accounts have operations routes. Exterior-maintenance vendor onboarding remains unresolved and is not inferred from property management or leasing contacts.

## Generic portfolio behavior

Industrial/logistics accounts participate in the existing generic opportunity portfolio context only when a visible opportunity resolves to a source-backed physical site/building relationship.

Sister sites are not enumerated merely because they share an account.

Adding industrial portfolios did not create new exterior-cleaning demand signals. The roster-backed portfolio scanner remained at the same active-signal count after the industrial cohort was added.

## Public/account-access behavior

The connection-facing Growth wrapper remains the controlled public handoff.

- property-management and facilities-management account-access opportunities share one additive array,
- each entry carries `account_archetype`,
- operator readiness and account-side service fit are separate concepts,
- claim limits state that property/client need, contract award, contract value, and close probability are not proven,
- geography is enforced before a local intermediary is returned.

## Security and privacy validation

Final production checks passed:

- `agent_contract.assert_tool_registry_integrity_v1()`
- `agent_contract.assert_architecture_doctrine_v1()`
- `agent_privacy.assert_rls_posture_v1()`

Multifamily regression:

- multifamily push candidates: 0
- leaked unverified multifamily: 0

Direct exposure checks:

- no direct `anon`, `authenticated`, or `PUBLIC` table grants on the new internal facilities-management, water-utility, or industrial/logistics views,
- connection-facing Growth wrapper remains service-role gated,
- facilities-management helper is not executable by `anon` or `authenticated`.

## Relevant migrations

- `portfolio_archetypes_facilities_water_industrial_foundation_v1`
- `materialize_wris_water_utility_tank_portfolios_v1`
- `seed_facilities_management_intermediary_accounts_v1`
- `seed_industrial_logistics_portfolios_v1`
- `close_industrial_logistics_site_research_v1`
- `water_utility_portfolio_context_and_contacts_v1`
- `portfolio_facilities_water_industrial_product_surfaces_v1`
- `fix_generic_portfolio_queue_industrial_contacts_v1`
- `facilities_management_growth_account_access_v1`
- `close_priority_water_routes_and_harden_fm_growth_v1`
- `water_utility_registry_fallback_contact_closure_v1`

## Closure status

V1 baseline is closed.

Remaining work is refresh/expansion rather than baseline architecture or unresolved active-signal coverage:

- periodically revalidate state-registry fallback contacts,
- upgrade registry fallbacks to named/direct operations or procurement routes when discovered,
- add additional facilities-management firms only with source-backed vendor/intermediary evidence,
- expand industrial/logistics site rosters from first-party portfolio evidence,
- continue monitoring WRIS tank state and current maintenance signals.

The core guardrail remains unchanged: portfolio leverage improves account organization and context, but does not itself prove demand, procurement, contract value, close probability, or realized revenue.
