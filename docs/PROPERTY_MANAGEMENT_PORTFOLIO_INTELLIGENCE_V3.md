# Property Management Portfolio Intelligence v3

Status: deployed to production on 2026-09-07.

V3 extends Scout's property-management intelligence into a strategic-account and vendor-access model. The core objective is to recognize the option value of getting into a large management portfolio without converting portfolio size, vendor access, or management responsibility into unsupported claims of ownership, property condition, current job demand, contract value, or close probability.

## Production migrations

The V3 tranche currently includes:

- `20260907184825 denton_floyd_portfolio_lifecycle_reconciliation_v3`
- `20260907184937 prg_vendor_shield_onboarding_route_v3`
- `20260907185048 nts_project_bid_vendor_route_and_queue_logic_v3`
- `20260907185209 denton_completed_asset_enrichment_and_high_confidence_crosswalks_v3`
- `20260907185458 denton_and_fjr_operating_vendor_routes_v3`
- `20260907185637 aggregate_property_management_accounts_and_lrei_v3`
- `20260907185805 bill_stout_aggregate_association_portfolio_and_vendor_route_v3`
- `20260907190004 property_management_vendor_entry_opportunity_surface_v3`
- `20260907190519 organization_service_area_foundation_v3`
- `20260907190857 growth_account_access_integration_v3`

Exact applied SQL remains in `supabase_migrations.schema_migrations` in project `ufpkjaadmmpmeogzhrcq`.

## 1. Core semantics remain strict

Scout keeps four concepts separate:

1. legal ownership;
2. management / operating responsibility;
3. the managed property or association relationship;
4. physical building footprints.

A management relationship never implies ownership. A property or association may cover multiple buildings. Portfolio scale never proves a specific property currently needs service.

Portfolio option value remains qualitative. No fixed revenue, ROI, close-probability, or portfolio multiplier has been introduced.

## 2. Portfolio lifecycle is explicit

New internal view:

- `scout.v_property_management_portfolio_lifecycle_summary`

Lifecycle buckets:

- `operating` — stabilized/currently operating asset;
- `lease_up` — actively entering operations / accepting tenants but not fully stabilized;
- `development`, `planned`, `under_construction` — future portfolio access, not current site demand.

### Denton Floyd lifecycle reconciliation

First-party current-project, completed-project, and rental-search sources were reconciled.

Current documented set:

- 32 documented portfolio properties;
- 21 stabilized operating properties;
- 6 lease-up properties;
- 5 construction/pipeline properties;
- 2,730 known stabilized units;
- 1,778 known lease-up units;
- 1,158 known pipeline units.

The unit totals include only currently resolved first-party counts; missing values are not estimated.

The current strategic-account view treats `operating + lease_up` as serviceable portfolio scope and keeps pipeline separate.

## 3. Vendor access is not the same thing as procurement authority

`scout.property_management_account_evidence` is the canonical account-evidence store.

V3 distinguishes:

- a general contact route;
- an operating-property vendor/bid route;
- a supplier-registration/onboarding route;
- a centralized procurement decision-maker;
- a public self-service vendor portal.

Those claims are stored independently and only promoted when the source supports them.

`scout.v_property_management_account_research_queue` now treats either a documented procurement/supplier-registration route OR a source-backed operating-property vendor route as satisfying the `procurement_or_vendor_route` research step.

This prevents Scout from repeatedly researching vendor access once a credible route has already been resolved while preserving the stronger procurement distinction.

## 4. Current roster-backed account state

### Denton Floyd Real Estate Group

- `strategic_account`;
- 27 operating/lease-up properties in the current serviceable portfolio view;
- 22 serviceable properties in KY/IN/OH;
- 3 properties currently crosswalked to 3 physical building records;
- portfolio operations route available;
- first-party `Vendor Inquiries` path documented;
- supplier-registration route available through that first-party entrypoint;
- operating-property vendor route proven;
- centralized operating-property procurement not proven;
- universal supplier-onboarding requirements unresolved.

The separately documented construction/development pre-bid process remains development evidence and is not silently generalized to operating properties.

### NTS Capital

- `strategic_account`;
- 24 documented operating Louisville properties;
- 10 properties crosswalked to 12 physical buildings;
- portfolio operations roles available;
- Director of Property Services direct first-party route documented;
- the role explicitly includes project bids and project management across NTS properties;
- operating-property vendor/bid route proven;
- centralized supplier portal unresolved.

Additional first-party contacts cover commercial property maintenance, commercial property management/vendor relations, and accounts payable.

### FJR Commercial

- `strategic_account`;
- 23 operating regional properties plus 2 pipeline/development records;
- 9 properties crosswalked to 10 physical buildings;
- first-party portfolio reports 1.8M+ square feet under management and 400+ tenants;
- Director of Facilities & Maintenance Operations has documented portfolio-wide vendor-coordination responsibility;
- mediated operating-property vendor route proven through published company channels;
- public supplier portal/formal centralized onboarding unresolved.

### PRG Real Estate

- `portfolio_account`;
- 5 documented KY properties;
- 2 properties crosswalked to 4 physical buildings;
- Kentucky operations and maintenance roles documented;
- first-party AP role documents vendor management through Vendor Shield, review of vendor submissions, and vendor compliance/onboarding support;
- operating-property vendor route proven;
- supplier-registration routing instruction documented;
- PRG-specific public Vendor Shield self-service URL not resolved.

### Buckingham Companies

- `multi_site_account`;
- 4 documented Louisville operating properties;
- 1,054 known units;
- portfolio operations route available;
- use of prequalified third-party vendors documented;
- actual vendor entry/onboarding route still unresolved.

### Hagan Properties

- `multi_site_account`;
- 3 documented Louisville serviceable properties (2 operating, 1 lease-up);
- 793 known units;
- general route available;
- portfolio operations/vendor route remains unresolved.

## 5. Aggregate-scale accounts do not require fake property records

Some management firms publish credible account scale without publishing a complete property roster. V3 represents those claims directly instead of creating fake site rows.

Internal views:

- `scout.v_property_management_aggregate_scale_accounts`
- `scout.v_property_management_aggregate_account_research_queue`

The surfaces preserve:

- reported asset count;
- asset unit (`homes`, `managed_associations`, etc.);
- first-party source/currentness;
- vendor/contact state;
- portfolio-count basis;
- explicit guardrails stating that the aggregate claim is not an individually resolved property count.

### LREI Property Management LLC

First-party evidence documents:

- 1,500+ managed homes across Louisville/Southern Indiana and surrounding communities;
- public Preferred Vendors page;
- public `Start Onboarding` workflow;
- Rentvine property-management platform;
- Property Meld maintenance/work-order workflow;
- vendor dashboard after activation;
- estimate and invoice submission through Property Meld;
- net-30 payment terms;
- insurance/W-9/onboarding requirements in the linked form.

Scout state:

- `aggregate_scale_account`;
- reported scale: 1,500 homes;
- complete public property roster unresolved;
- operating-property vendor route proven;
- public vendor onboarding entrypoint resolved;
- supplier-registration route resolved;
- exterior-cleaning category acceptance unresolved;
- current property need unresolved.

The 1,500-home claim is never represented as 1,500 Scout properties.

### Bill Stout Properties, Inc.

First-party evidence documents:

- 36 unique managed associations on the public Managed Associations page (one duplicate Windsor Place listing removed from the count);
- curated insured subcontractor/vendor network;
- `Become a Vendor` workflow and linked vendor form/password process;
- `Exterior Cleaning` explicitly listed among subcontracted services;
- public maintenance coordinator routes.

Scout state:

- `aggregate_portfolio_account`;
- reported scale: 36 managed associations;
- associations are not treated as single physical buildings;
- operating-property vendor route proven;
- supplier-registration route resolved;
- explicit `exterior-cleaning` service relevance proven;
- specific property need not proven;
- contract/job award not proven.

## 6. Vendor-entry opportunities are distinct from property demand

Internal views:

- `scout.v_property_management_vendor_entry_opportunities`
- `scout.v_property_management_service_specific_vendor_entries`

The commercial concept is:

> a source-backed opportunity to enter a management company's vendor network or project-bid path.

It is not a site-condition claim.

A service-specific vendor-entry opportunity requires BOTH:

1. a current source-backed operating-property vendor route; and
2. current source-backed evidence that the management company uses/accepts the target service category.

Current service-specific result:

- Bill Stout Properties / `exterior-cleaning` -> `service_specific_vendor_entry_ready`.

The following accounts currently have valid operating-property vendor routes but unresolved exterior-cleaning category fit:

- LREI Property Management LLC;
- Denton Floyd Real Estate Group;
- NTS Capital;
- FJR Commercial;
- PRG Real Estate.

Their state is `vendor_entry_route_ready_service_fit_unresolved`, not a service-specific lead.

Vendor-entry records explicitly state that they do not prove:

- a specific property needs service;
- a buyer requested work;
- a contract/assignment exists;
- contract value;
- close probability;
- revenue/ROI.

## 7. Organization service-area geography

V3 adds a generic reusable primitive:

- `core.organization_service_areas`

It stores evidence-backed organization activity/service areas with:

- `service_scope`;
- `area_kind`;
- canonical `area_key`;
- state/county/place context;
- source/currentness/confidence;
- evidence and validity window.

New property-management view:

- `scout.v_property_management_account_service_areas`

That view combines two evidence paths:

1. `explicit_service_area` — first-party service-area statements mapped to canonical county geography;
2. `documented_managed_property_presence` — county coverage derived from source-backed current managed-property coordinates.

Examples currently resolved:

- Bill Stout: Jefferson, Shelby, and Bullitt counties, KY from explicit first-party service-area evidence;
- LREI: Jefferson County, KY from the explicit Louisville market statement; Southern Indiana is deliberately NOT expanded into counties without county-level resolution;
- Denton Floyd: multiple county presences derived from its documented managed-property coordinates.

Service-area rows support deterministic filtering only. They do not claim exclusivity or management of every property in a county.

## 8. Public Explore Growth integration

V3 now safely exposes service-specific strategic account access through the existing public Growth response.

The original implementation of:

- `public.scout_find_connection_growth_options_v2(...)`

was preserved as an internal base function:

- `public.scout_find_connection_growth_options_v2_base_v3(...)`

Direct `service_role` access to the base implementation was revoked. The public wrapper retains the original signature and original response fields, then additively supplies:

- `account_access_opportunity_count`
- `account_access_opportunities`
- `account_access_boundary`

The opportunity-set output schema already allows additive properties, so this does not require a breaking schema version.

Helper function:

- `scout.find_property_management_vendor_entries_for_operator(...)`

The helper only returns service-specific vendor entries that pass deterministic geography matching against `scout.v_property_management_account_service_areas`.

### Growth response semantics

An `account_access_opportunity` contains:

- opportunity kind `strategic_account_vendor_entry`;
- management account identity/class;
- portfolio scope and its count basis;
- service slug/name;
- operator fit and whether the service is already offered;
- vendor route/onboarding state;
- geography evidence;
- next action;
- source-backed evidence;
- explicit claim limits.

It remains separate from the ordinary `growth_options` array because account access is not the same kind of growth as adding a new service capability.

### Geography regression tests

Using the live sandbox operator:

- Jefferson County, KY -> returns exactly one account-access opportunity: Bill Stout / Exterior Cleaning;
- Fayette County, KY -> returns zero account-access opportunities;
- 25-mile Louisville radius -> returns Bill Stout and explains the matched explicit service-area counties.

The Jefferson result reports:

- `service_specific_vendor_entry_ready`;
- operator `fit_status: ready`;
- service already offered by the test operator;
- supplier-registration route available;
- specific property need = false;
- contract award = false;
- contract value = unknown;
- close probability = unknown.

This is the intended interpretation of the pilot customer's insight: getting into a portfolio can be strategically valuable, while the system still refuses to fabricate a job.

## 9. Find Work and multifamily identity remain unchanged

Vendor-entry does not use the site-demand path and is not injected into ordinary `Find Work` building candidates.

The generic `scout.v_signal_window_opportunity_candidates` continues to exclude `exterior-cleaning` business-need signals, so V3 does not use generic signals to bypass the exterior-cleaning identity gate.

The latest regression check confirms:

- unverified multifamily candidates in the public opportunity set: `0`.

## 10. Property crosswalk improvements

Denton Floyd gained two additional high-confidence building resolutions without lowering the global identity threshold:

- Chandler Park Assisted Living -> FEMA nursing-home footprint, 9m from first-party property coordinate, compatible property type, confidence 0.96;
- The Summit of Edgewood -> Kentucky ORNL footprint, 7.7m from first-party property coordinate, confidence 0.93; confidence remains below address-matched resolution because the ORNL record lacks address/occupancy attributes.

Additional first-party completion/unit metadata was captured for Clarksville Lofts, Forest Hills Commons, Chandler Park, Cardinal Landing, Maristone of Franklin, Maristone of Providence, The Landing of Long Cove, and The Summit of Edgewood.

Proximity-only cases remain unresolved when independent identity evidence does not converge.

## 11. Privacy and authorization

New V3 internal tables/views/functions do not grant direct `anon` or `authenticated` access.

The Growth base function now has only owner (`postgres`) execute privilege. The public wrapper retains `service_role` execute privilege and the original public signature.

No chat-derived data is used to create these account/vendor facts. Sources are first-party/public evidence stored through Scout's existing evidence model.

## 12. Release validation

After the current V3 migrations:

```sql
select agent_contract.assert_tool_registry_integrity_v1();
select agent_contract.assert_architecture_doctrine_v1();
```

Both pass.

Other validated conditions:

- Jefferson Growth positive account-access test passes;
- Fayette negative geography test passes;
- Louisville-radius geography test passes;
- unverified multifamily leak count remains `0`;
- direct `anon`/`authenticated` grants remain absent on the new internal surfaces;
- direct `service_role` access to the Growth base function is revoked;
- public Growth wrapper retains the expected service-role execution privilege.

## 13. Next priorities

1. Resolve priority sites for aggregate accounts (LREI and Bill Stout) rather than attempting bulk reconstruction of every asset.
2. Continue Denton/FJR/NTS property-to-building crosswalk expansion.
3. Resolve Buckingham's actual vendor-entry route.
4. Add service-category relevance only when first-party evidence supports it; do not assume exterior-cleaning fit from a generic vendor program.
5. Find current site-need evidence separately from account-access evidence.
6. Record outcomes from vendor onboarding, first-site wins, second-site conversion, repeat work, and time-to-portfolio expansion before assigning any economic multiplier to portfolio access.
