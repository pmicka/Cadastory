# Property Management Portfolio Intelligence v2

Status: deployed to production on 2026-09-07.

This document extends `PROPERTY_MANAGEMENT_PORTFOLIO_INTELLIGENCE_V1.md`. V1 established the management-company -> property/site -> physical-building separation, the multifamily identity gate, and qualitative portfolio leverage. V2 turns that foundation into a repeatable strategic-account and research workflow.

## Design contract

Scout continues to keep these concepts separate:

1. legal ownership,
2. property/facility management responsibility,
3. managed property/site identity,
4. physical building footprints,
5. current service need,
6. buyer/operations routing,
7. procurement/vendor onboarding.

A fact in one layer is not silently promoted into another. In particular:

- management does not imply ownership;
- a large portfolio does not imply current demand;
- evidence that a company uses vendors does not prove a vendor-onboarding route;
- a development/construction procurement process does not automatically apply to operating-property maintenance;
- a property may contain multiple physical buildings;
- a missing current opportunity means `not_currently_resolved`, not `no need`.

Portfolio leverage remains a weak ranking tiebreaker. No fixed revenue, close-probability, ROI, or portfolio multiplier is used.

## V2 production migrations

- `20260907182522 property_portfolio_lifecycle_and_crosswalk_automation_v2`
- `20260907182543 seed_regional_property_management_accounts_v2`
- `20260907182605 seed_nts_local_managed_portfolio_v2`
- `20260907182625 seed_prg_buckingham_hagan_portfolios_v2`
- `20260907182658 portfolio_leverage_uses_operating_assets_v2`
- `20260907182859 resolve_multi_building_exact_property_addresses_v2`
- `20260907183017 enrich_nts_property_services_routes_v2`
- `20260907183052 property_management_account_value_context_v2`
- `20260907183327 generalize_property_manager_links_and_constellations_v2`
- `20260907183550 resolve_verified_nts_louisville_jeffersontown_crosswalks_v2`
- `20260907183646 property_management_account_research_queue_v2`
- `20260907183806 property_management_account_evidence_and_denton_routes_v2`
- `20260907183945 property_management_account_evidence_summary_v2`
- `20260907184104 enrich_prg_buckingham_operations_routes_v2`
- `20260907184233 seed_fjr_commercial_strategic_account_v2`

The applied SQL remains available in `supabase_migrations.schema_migrations` for Supabase project `ufpkjaadmmpmeogzhrcq`.

## Portfolio lifecycle

`scout.v_property_management_facilities` now distinguishes property lifecycle and known scale through appended fields:

- `portfolio_asset_status`
- `portfolio_property_type`
- `portfolio_unit_count`

Operating/lease-up properties are separated from development/planned/under-construction pipeline. Strategic-account leverage and opportunity ranking use operating/lease-up scope rather than blindly counting every portfolio record.

`scout.v_property_management_portfolios` now exposes, in addition to the v1 fields:

- `operating_managed_property_count`
- `pipeline_property_count`
- `known_unit_count`
- `regional_operating_property_count`

## Property-to-building resolution

### Normalization

`scout.normalize_address_key_v2(text)` normalizes directional and common street-suffix variants before comparison. This allows first-party addresses such as `950 Breckenridge Lane` to match normalized physical-building addresses without broad fuzzy matching.

### Automatic exact crosswalk

`scout.refresh_property_building_exact_crosswalks()` resolves exact normalized property-address matches against FEMA USA Structures when state/locality evidence is compatible.

It supports two explicit cases:

- unique exact-address building: confidence `0.99`;
- multiple physical buildings sharing the same exact managed-property address: confidence `0.97`, modeled as a multi-building site rather than an ambiguity.

Rejected links remain rejected on refresh.

A narrow observed Louisville/Jeffersontown exception was separately resolved for NTS properties where:

- the official NTS portfolio labels the city `Louisville`,
- FEMA labels the exact same address `Jeffersontown`,
- FEMA county is Jefferson,
- state is Kentucky.

This is recorded as source-specific evidence and is not a global rule that city conflicts may be ignored.

### Review queue

`scout.v_property_building_resolution_queue` retains non-exact and spatial candidates for review. Proximity alone does not establish property identity.

## Strategic-account model

`scout.v_property_management_strategic_accounts` now distinguishes:

- `strategic_account`: >=20 documented regional operating properties;
- `portfolio_account`: >=5;
- `multi_site_account`: >=2;
- otherwise ordinary account.

The surface also preserves:

- operating and regional property counts,
- known unit count when first-party evidence supplies it,
- resolved-building and crosswalk coverage,
- current-need status,
- contact-route quality,
- strict procurement-route availability,
- enterprise-scale context,
- qualitative portfolio leverage.

`current_need_status='not_currently_resolved'` is explicitly not evidence of no need.

## Account evidence

`scout.property_management_account_evidence` stores time-bounded, source-backed commercial context without promoting it to a stronger claim.

Current evidence kinds are intentionally narrow:

- `portfolio_scale`
- `vendor_model`
- `operations_structure`
- `vendor_route`
- `service_relevance`

`scout.v_property_management_account_evidence_summary` exposes the active evidence and keeps `operating_property_vendor_route_proven` separate from evidence that vendors are merely used.

Examples currently recorded:

- Denton Floyd: a formal first-party new-vendor/pre-bid process is documented for development/construction; operating-property applicability remains unresolved.
- Buckingham: first-party commercial-management material documents use of prequalified third-party vendors for specialized work; onboarding path remains unresolved.
- NTS: first-party leadership material documents portfolio-wide property-services leadership and project-bid responsibility; formal supplier onboarding remains unresolved.
- FJR: first-party leadership material documents vendor coordination under Facilities & Maintenance Operations; supplier onboarding remains unresolved.
- PRG: first-party management pages document Kentucky regional operations and maintenance authority.

## Research queues

V2 adds deterministic internal research queues rather than repeatedly researching accounts ad hoc.

### `scout.v_property_management_account_research_queue`

For each strategic/portfolio/multi-site account, Scout exposes transparent gaps such as:

- `property_building_crosswalk`
- `portfolio_operations_contact`
- `procurement_or_vendor_route`
- `current_need_evidence`

It exposes a deterministic `next_research_step`, crosswalk gap count, contact quality, vendor context, and current-need state.

The queue contains transparent facts and missing evidence. It is not a lead-value score.

### `scout.v_property_management_property_research_queue`

Each operating property is classified as:

- resolved,
- high-confidence crosswalk review,
- candidate crosswalk review, or
- building-identity research required.

This lets portfolio enrichment proceed property-first and reproducibly.

## Current regional account state

### Denton Floyd Real Estate Group

- account class: `strategic_account`
- documented operating properties: 32
- documented regional operating properties: 27
- crosswalked properties: 1
- resolved buildings: 1
- contact quality: portfolio operations role available
- current first-party role routes include President of Property Management and Vice President-level operations roles through the documented company channel
- vendor context: development/construction pre-bid process documented
- operating-property procurement route: unresolved
- current service need: not currently resolved

### NTS Capital

- account class: `strategic_account`
- documented operating Louisville properties: 24
- regional operating properties: 24
- known units in the explicitly ingested local multifamily subset: 1,272
- crosswalked properties: 10
- resolved physical buildings: 12
- portfolio operations role available
- current first-party role routes include Director of Property Services, Property Services Operations Manager, Multi-Family Operations Manager, and Commercial Operations Manager
- enterprise first-party context preserved separately: 11M real-estate square feet, 6,000+ multifamily units, 48 office/healthcare buildings
- formal operating-property procurement/onboarding route: unresolved
- current service need: not currently resolved

### FJR Commercial

- account class: `strategic_account`
- first-party portfolio page: more than 1.8M square feet under management and 400+ tenants
- documented regional operating properties: 23
- development/lot entries retained separately: 2
- crosswalked properties after first deterministic pass: 9
- resolved physical buildings: 10
- portfolio operations role available
- current first-party role routes include Senior Director of Operations & Property Management and Director of Facilities & Maintenance Operations
- vendor coordination is explicitly documented under Facilities & Maintenance Operations
- formal supplier onboarding route: unresolved
- current service need: not currently resolved

### PRG Real Estate

- account class: `portfolio_account`
- documented Kentucky operating properties ingested: 5
- crosswalked properties: 2
- resolved physical buildings: 4
- current first-party Kentucky role routes:
  - Danielle Porche — Regional Director (KY, MO)
  - Jon Milton — Regional Maintenance Director (KY)
- direct personal contact details are not asserted; routing uses the documented corporate contact channel
- procurement/onboarding route: unresolved
- current service need: not currently resolved

### Buckingham Companies

- account class: `multi_site_account`
- documented Louisville operating properties ingested: 4
- known units across those four: 1,054
- current exact building crosswalk: unresolved
- current first-party portfolio role routes include SVP Property Management and a senior property-management/asset-management executive route
- prequalified third-party vendor use is documented for specialized commercial-property work
- supplier onboarding route: unresolved
- current service need: not currently resolved

### Hagan Properties

- account class: `multi_site_account`
- operating/lease-up Louisville residential properties ingested: 3
- known units: 793
- current exact building crosswalk: unresolved
- general durable company route available
- property-management function documented
- operations role and vendor-onboarding route remain unresolved
- current service need: not currently resolved

## Opportunity graph integration

`scout.v_opportunity_property_manager_links` generalizes the property-management graph to any opportunity already on Scout's authoritative opportunity spine when its source/canonical building is crosswalked to a managed property.

This prevents the portfolio feature from being exterior-cleaning-specific.

`scout.v_opportunity_property_management_context` now derives from those generalized spine links.

## Opportunity Constellation integration

The existing public `scout_get_connection_opportunity_constellation_v1` behavior was extended additively.

New explainable relationships:

- `shared_property_manager` — medium relationship strength
- `same_managed_property` — strong relationship strength

New cluster bases:

- `shared_property_manager`
- `same_managed_property`

Anti-enumeration behavior is preserved:

- every supplied candidate must already be known to the Scout connection;
- only relationships between supplied, already-visible candidates are evaluated;
- no hidden manager/property/opportunity nodes are added;
- management is explicitly not represented as ownership.

A production smoke test on two known opportunities returned the existing `nearby` relationship normally after this extension, confirming the additive code path compiles and preserves prior behavior.

## Multifamily safety state

After V2 crosswalk expansion:

- unverified multifamily rows leaking into the public push-candidate set: 0
- verified multifamily push candidates currently produced by the environmental need path: 0

Portfolio enrichment therefore does not itself create demand.

## Lead-value direction

The account model now has the data needed to eventually decompose lead value into auditable components such as:

- immediate current-need evidence,
- asset/job scale,
- buyer accessibility,
- management portfolio breadth,
- number of currently actionable sister properties,
- repeat/recurrence evidence,
- vendor-entry friction,
- purchasing centralization/locality,
- operator fit.

Scout still does not collapse these into a dollar estimate or fixed portfolio multiplier. Stronger weighting should be learned from outcome data: first-property conversion, second-site expansion, repeat cadence, time-to-expansion, revenue per management relationship, and vendor-onboarding friction.

## Release verification

After the V2 public Constellation extension and the final account/evidence migrations, both required architecture gates pass:

```sql
select agent_contract.assert_tool_registry_integrity_v1();
select agent_contract.assert_architecture_doctrine_v1();
```

The public Constellation smoke test also passed with its existing `contract_version='1.1'` and prior relationship behavior intact.

## Next work

The research queue should drive the next passes rather than brand familiarity. Current high-value gaps are:

1. expand Denton Floyd property-to-building coverage;
2. expand NTS crosswalk coverage;
3. expand FJR exact/reviewable crosswalk coverage;
4. resolve Buckingham and Hagan building identities from better building/geocode evidence;
5. resolve operating-property supplier/onboarding routes without treating vendor-use evidence as procurement access;
6. resolve current need independently of portfolio scale;
7. add additional first-party portfolios only when property-level evidence is strong enough to preserve the same management/property/building distinctions.
