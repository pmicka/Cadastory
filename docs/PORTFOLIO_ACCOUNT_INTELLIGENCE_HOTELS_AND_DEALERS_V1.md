# Portfolio Account Intelligence — Hotels and Dealerships v1

Status: deployed to production on 2026-09-07.

This release generalizes the account → portfolio/site → physical building pattern established by Scout's property-management work to two new business structures:

- hotel management companies
- dealership groups

The implementation deliberately preserves category-specific semantics rather than reducing every business network to a generic property manager.

## Core semantic rules

### Hotels

- hotel manager ≠ legal owner
- hotel brand/franchisor ≠ hotel manager
- presence on a hospitality-company portfolio page does not always prove physical facilities-management responsibility
- one hotel property/site may contain multiple physical buildings
- revenue-management-only relationships must not be treated as facilities-management relationships

### Dealership groups

- dealership brand/franchise/business unit ≠ physical dealership site
- multiple franchises at one street address are one physical serviceable campus until evidence proves otherwise
- automotive service department ≠ building/facilities department
- sales/service/parts contacts must not be promoted into facilities/procurement routes without evidence

Examples in the initial cohort:

- Neil Huffman Chevrolet, GMC and Nissan share 1220 Versailles Road and are modeled as one physical site with three business units.
- Neil Huffman Mazda and Volkswagen share 4926 Dixie Highway and are one physical site with two business units.
- Bachman Ram Commercial, Chrysler Dodge Jeep Ram and Hyundai share 630 Broadway Street and are one physical site with three business units.

## Production migrations

- `20260907200635 generic_portfolio_account_foundation_v1`
- `20260907200808 seed_hotel_and_dealership_portfolio_accounts_v1`
- `20260907200852 fix_musselman_hotel_facility_links_v1`
- `20260907201001 resolve_hotel_dealer_exact_buildings_and_musselman_facilities_routes_v1`
- `20260907201234 close_initial_hotel_dealer_research_and_aggregate_semantics_v1b`
- `20260907201601 portfolio_account_opportunity_context_v1`
- `20260907201722 seed_general_hotels_aggregate_account_v1`
- `20260907201814 enrich_neil_huffman_facilities_route_v1`

Exact applied SQL remains in `supabase_migrations.schema_migrations` in Supabase project `ufpkjaadmmpmeogzhrcq`.

## Generic portfolio-account architecture

### `scout.portfolio_account_evidence`

New internal evidence table for account archetypes that should not write into property-management-specific evidence.

Initial archetypes:

- `hotel_management`
- `dealership_group`
- `other`

Evidence kinds include:

- portfolio scale
- operations structure
- vendor route
- service relevance
- brand structure
- current-need scan
- roster research

RLS is enabled. Direct `anon` and `authenticated` access is revoked.

### `scout.v_portfolio_account_facilities`

Generic physical-site layer over `core.organization_facilities`.

It preserves both:

- serviceable physical site count
- business-unit count / brand array

This prevents brand/franchise cardinality from inflating physical-site opportunity counts.

### `scout.v_portfolio_account_summary`

Produces:

- serviceable site count
- serviceable business-unit count
- regional serviceable site count
- physical crosswalk count
- resolved building count
- research-complete site count
- research gap count
- research coverage percentage
- physical crosswalk coverage percentage
- account class

As with property-management V4, research coverage may reach 100% while physical crosswalk coverage remains lower.

### `scout.v_portfolio_account_research_queue`

A research step may close either because the desired route/identity was resolved or because current first-party/public research produced a dated, explicit negative resolution outcome.

`research complete` never means `vendor route exists`, `building is resolved`, or `current demand exists`.

### Aggregate portfolio views

- `scout.v_portfolio_aggregate_accounts`
- `scout.v_portfolio_aggregate_research_queue`

These support credible enterprise-scale claims when a safe site-level facilities roster cannot be materialized.

## Hotel accounts

### Musselman Hotels

First-party source: `https://musselmanhotels.com/our-hotels/`

Production state:

- 10 current hotel properties in the seeded first-party roster
- 9 in KY/IN/OH regional scope
- 10 business units
- 6 properties physically crosswalked
- 6 resolved building footprints
- 100% research coverage
- 60.0% physical crosswalk coverage
- account class: `portfolio_account`

Portfolio operations:

- Jay Nichols — Vice President of Operations

First-party property pages also identify site-level engineering / maintenance leadership for eight properties, including Director of Engineering, Chief Maintenance Engineer and Maintenance Manager roles.

No portfolio-wide exterior/facilities supplier-registration route is currently proven.

Current Scout need scan:

- resolved hotel sites scanned: 6
- active exterior-cleaning buildings currently resolved: 0

Interpretation: no active need is currently resolved in Scout's existing signal layers. This is not evidence that the hotels have no cleaning need.

### Schulte Hospitality Group

First-party sources:

- `https://www.schultehospitality.com/portfolio`
- `https://www.schultehospitality.com/hospitality-management-group`

Production state:

- first-party scale: 250+ properties
- 30,000+ keys
- 40 states
- 5 countries
- account class: `aggregate_strategic_account`
- complete deterministic site roster: not resolved from the current public portfolio surface
- research queue: `monitor_account`

Leadership evidence includes:

- Sam Grabush — Chief Operating Officer
- Jennifer Hitcho — Vice President of Procurement

The procurement role is real, but the public profile emphasizes design/procurement, FF&E, renovations and new builds. Scout therefore does not claim that an operating-hotel exterior-maintenance supplier route is proven.

### General Hotels Corporation

First-party sources:

- `https://www.genhotels.com/`
- `https://www.genhotels.com/portfolio`
- `https://www.genhotels.com/team`

Production state:

- 50 hotels under management
- 5,000+ keys
- 4 hotels under construction
- account class: `aggregate_portfolio_account`
- Cindy Kurtz, EVP Operations, resolved through a direct first-party email route
- research queue: `monitor_account`

Important guardrail:

GHC's public portfolio explicitly mixes `Fully Managed`, `Revenue Managed`, and `In Development` properties. Scout does not convert every portfolio card into a physical facilities-managed site because revenue-management-only responsibility does not prove facilities/vendor authority.

This is recorded as aggregate account scale until property-level management mode can be attributed deterministically.

## Dealership accounts

### Oxmoor Auto Group

First-party source: `https://www.oxmoorautogroup.com/contact-us/`

Production state:

- 9 physical sites
- 9 business units
- 5 physically crosswalked sites
- 5 resolved building footprints
- 100% research coverage
- 55.6% physical crosswalk coverage
- account class: `portfolio_account`

No public centralized facilities/procurement role was resolved from the current first-party surfaces. Scout retains a group routing request rather than treating sales/service departments as facilities contacts.

### Neil Huffman Auto Group

First-party sources:

- `https://www.neilhuffman.com/locations/index.htm`
- `https://www.neilhuffman.com/dealership/staff.htm`

Production state:

- 7 physical sites
- 10 business/franchise units
- 3 physically crosswalked sites
- 3 resolved building footprints
- 100% research coverage
- 42.9% physical crosswalk coverage
- account class: `portfolio_account`

The difference between 7 sites and 10 business units is intentional: co-located franchises are collapsed to physical campuses.

Buyer/operations improvement:

- Daniel Wolford — Facilities Manager

This is a source-backed group facilities role. No procurement authority or direct personal contact detail is inferred beyond the first-party role listing.

### Bachman Auto Group

First-party source: `https://www.bachmanautogroup.com/about-us-contact`

Production state:

- 6 physical sites
- 9 business units
- 5 physically crosswalked sites
- 5 resolved building footprints
- 100% research coverage
- 83.3% physical crosswalk coverage
- account class: `portfolio_account`

No public centralized facilities/procurement role is currently resolved. Co-located business units remain one physical site.

## Physical-resolution behavior

Exact normalized address + state matches against FEMA were promoted at 0.99 confidence.

Initial exact-match results:

- Musselman: 6 / 10 sites
- Oxmoor: 5 / 9 sites
- Neil Huffman: 3 / 7 sites
- Bachman: 5 / 6 sites

Unmatched sites received time-bounded `source_gap_current_sources` reviews after checking current FEMA / Kentucky ORNL / Indiana / Overture building corpora.

No proximity-only footprint was promoted merely to improve coverage percentages.

## Opportunity-spine integration

New internal views:

- `scout.v_opportunity_portfolio_account_links`
- `scout.v_opportunity_portfolio_account_context`

`scout.get_opportunity_spine_projection(candidate_key)` now adds an optional:

- `portfolio_account`

context object for visible opportunities whose physical building has already been resolved to a hotel/dealer site.

Guardrails:

- context only; no portfolio revenue or close-probability multiplier
- no sister-site enumeration simply because two sites share an account
- opportunity linkage requires resolved physical site → building identity
- hotel brand remains distinct from manager/owner
- dealership brand/business unit remains distinct from physical site

Current active spine overlap after the initial release:

- portfolio-linked active opportunities: 0

This is a valid negative result. The accounts remain high-leverage business-development structures without fabricated present demand.

## Current-need scans

For all roster-backed dealer/hotel accounts, resolved buildings were checked against the current exterior-cleaning push layer.

Current result:

- active exterior-cleaning buildings resolved across these accounts: 0

Again, this means `not currently resolved`, not `no need`.

## Privacy and release validation

All new generic internal views have no direct `anon` or `authenticated` grants.

`scout.portfolio_account_evidence`:

- RLS enabled
- no direct `anon` / `authenticated` grants

Release assertions pass:

```sql
select agent_contract.assert_tool_registry_integrity_v1();
select agent_contract.assert_architecture_doctrine_v1();
select agent_privacy.assert_rls_posture_v1();
```

All three return successfully.

Multifamily identity-gate regression:

- unverified multifamily opportunity leakage: `0`

The updated opportunity projection also returns normally after the additive `portfolio_account` context change.

## Initial cohort totals

Roster-backed physical accounts:

| Account | Archetype | Physical sites | Business units | Crosswalked sites | Buildings | Research coverage | Physical coverage |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Musselman Hotels | hotel management | 10 | 10 | 6 | 6 | 100% | 60.0% |
| Oxmoor Auto Group | dealership group | 9 | 9 | 5 | 5 | 100% | 55.6% |
| Neil Huffman Auto Group | dealership group | 7 | 10 | 3 | 3 | 100% | 42.9% |
| Bachman Auto Group | dealership group | 6 | 9 | 5 | 5 | 100% | 83.3% |

Aggregate hotel accounts:

- Schulte Hospitality Group — 250+ properties; aggregate strategic account
- General Hotels Corporation — 50 hotels under management; aggregate portfolio account

## Next phase

This baseline architecture is complete enough to support additional account archetypes without creating separate silos.

For hotels/dealers specifically, next work should favor:

1. monitor new/changed sites and refresh expiring source-gap reviews;
2. resolve public supplier/vendor onboarding when it becomes available;
3. collect actual outreach/onboarding/site-win outcomes;
4. resolve additional building footprints as public building/address corpora improve;
5. only strengthen ranking weights after observed portfolio conversion data supports it.
