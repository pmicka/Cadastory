# Property Management Portfolio Intelligence v3

Status: deployed to production on 2026-09-07.

V3 extends the property-management intelligence foundation from V1/V2 into an account-access model. The central design goal is to identify when a management-company relationship creates portfolio option value without converting portfolio size, vendor access, or management responsibility into unsupported claims of legal ownership, current property need, contract value, or close probability.

## Production migrations in this tranche

- `20260907184825 denton_floyd_portfolio_lifecycle_reconciliation_v3`
- `20260907184937 prg_vendor_shield_onboarding_route_v3`
- `20260907185048 nts_project_bid_vendor_route_and_queue_logic_v3`
- `20260907185209 denton_completed_asset_enrichment_and_high_confidence_crosswalks_v3`
- `20260907185458 denton_and_fjr_operating_vendor_routes_v3`
- `20260907185637 aggregate_property_management_accounts_and_lrei_v3`
- `20260907185805 bill_stout_aggregate_association_portfolio_and_vendor_route_v3`
- `20260907190004 property_management_vendor_entry_opportunity_surface_v3`

Exact applied SQL remains in `supabase_migrations.schema_migrations` in Supabase project `ufpkjaadmmpmeogzhrcq`.

## 1. Portfolio lifecycle is now explicit

A property appearing on a management-company portfolio/rental surface is no longer treated as automatically stabilized and operating.

New internal view:

- `scout.v_property_management_portfolio_lifecycle_summary`

Lifecycle buckets:

- `operating` — stabilized/currently operating property
- `lease_up` — accepting tenants / entering operations but not yet fully stabilized
- `development`, `planned`, `under_construction` — pipeline option value, not current service demand

The lifecycle summary deliberately exposes both serviceable portfolio scope (`operating + lease_up`) and pipeline separately.

### Denton Floyd reconciliation

The first-party current-project, completed-project, and rental-search surfaces were reconciled.

Current documented Denton Floyd set:

- 32 documented portfolio properties
- 21 stabilized operating properties
- 6 lease-up properties
- 5 construction/pipeline properties
- 2,730 known stabilized units from currently resolved first-party unit counts
- 1,778 known lease-up units
- 1,158 known pipeline units

These unit totals are incomplete where the source property still lacks an authoritative unit count; they are not estimates.

Pipeline properties remain strategically interesting because they may create future vendor access, but they are not counted as current site demand.

## 2. Vendor access is distinct from procurement authority

V3 formalizes three different concepts that must not be collapsed:

1. a vendor/contact route exists;
2. an operating-property vendor route is documented;
3. a centralized procurement/supplier-onboarding authority or public portal is proven.

`scout.property_management_account_evidence` remains the canonical evidence store. `scout.v_property_management_account_evidence_summary` exposes the strongest currently valid route facts.

The research queue now treats either a documented procurement/supplier-registration route OR a source-backed operating-property vendor route as satisfying the `procurement_or_vendor_route` research step.

This prevents repeated research of an account after a credible bid/vendor route has already been found while preserving the stronger procurement distinction.

## 3. Current roster-backed account state

### Denton Floyd Real Estate Group

- account class: `strategic_account`
- serviceable portfolio used by the current account view: 27 operating/lease-up properties
- 22 of those are in KY/IN/OH
- 3 properties currently crosswalked to 3 physical building records
- portfolio operations route available
- first-party `Vendor Inquiries` contact path documented
- supplier-registration route available through the first-party vendor-inquiry entrypoint
- operating-property vendor route: proven
- centralized operating-property procurement: not proven
- formal universal supplier-onboarding requirements: unresolved

The company separately documents a development/construction pre-bid process. That evidence remains distinct from operating-property vendor access.

### NTS Capital

- account class: `strategic_account`
- 24 documented operating Louisville properties
- 10 properties crosswalked to 12 physical buildings
- portfolio operations route available
- Director of Property Services route documented with direct first-party email/phone
- first-party profile explicitly documents project-bid and project-management responsibility across NTS properties
- operating-property vendor/bid route: proven
- formal centralized supplier-onboarding portal: unresolved

Additional first-party operating contacts include commercial property maintenance, commercial property management/vendor relations, and accounts payable roles.

### FJR Commercial

- account class: `strategic_account`
- 23 operating regional properties plus 2 pipeline/development records in the documented portfolio
- 9 properties crosswalked to 10 physical buildings
- first-party portfolio reports more than 1.8M square feet under management and 400+ tenants
- portfolio operations route available
- Director of Facilities & Maintenance Operations explicitly has vendor-coordination responsibility across FJR-managed properties
- mediated operating-property vendor route: proven through published company contact channels
- formal supplier portal/onboarding program: unresolved

### PRG Real Estate

- account class: `portfolio_account`
- 5 documented KY properties
- 2 properties crosswalked to 4 physical buildings
- Kentucky operations and maintenance roles documented
- first-party management page identifies an AP Specialist who handles vendor management through Vendor Shield, reviews submissions, and supports vendor compliance/onboarding
- operating-property vendor route: proven
- supplier-registration route: documented via the AP/Vendor Shield routing instruction
- PRG-specific public self-service Vendor Shield URL: not resolved

### Buckingham Companies

- account class: `multi_site_account`
- 4 documented Louisville operating properties
- 1,054 known units
- portfolio operations role available
- use of prequalified third-party vendors is documented
- operating-property vendor entry route: still unresolved

### Hagan Properties

- account class: `multi_site_account`
- 3 documented Louisville serviceable properties (2 operating, 1 lease-up)
- 793 known units
- general route available
- portfolio operations/vendor route still unresolved

## 4. Aggregate-scale accounts no longer require a fake property roster

A major V3 modeling change is support for management companies that publish credible portfolio scale but not a complete property-by-property roster.

New internal views:

- `scout.v_property_management_aggregate_scale_accounts`
- `scout.v_property_management_aggregate_account_research_queue`

An aggregate count is explicitly NOT represented as individually resolved Scout properties.

The views preserve:

- reported asset count
- reported asset unit (`homes`, `managed_associations`, etc.)
- first-party source and verification window
- vendor/contact state
- portfolio-count basis
- guardrails preventing ownership, current-need, or property-resolution inference

Aggregate scale is currently an account-research priority signal only. It does not directly affect site-level opportunity ranking.

### LREI Property Management LLC

First-party evidence:

- 1,500+ managed homes across Louisville/Southern Indiana and surrounding communities
- direct public Preferred Vendors page
- direct `Start Onboarding` workflow
- Rentvine property-management platform
- Property Meld maintenance/work-order workflow
- dedicated vendor dashboard after activation
- estimate/invoice submission through Property Meld
- net-30 terms documented
- general liability/W-9/onboarding documentation required by the linked form

Scout state:

- account class: `aggregate_scale_account`
- reported scale: 1,500 homes
- complete public property roster: unresolved
- operating-property vendor route: proven
- public self-service vendor entrypoint: resolved
- supplier-registration route: resolved
- exterior-cleaning category acceptance: unresolved
- current site need: unresolved

The 1,500-home claim is never treated as 1,500 Scout properties.

### Bill Stout Properties, Inc.

First-party evidence:

- public Managed Associations page contains 36 unique managed associations (one duplicate Windsor Place listing is counted once)
- association management is a different asset semantic from a physical building count
- Stout Services documents a curated insured vendor/subcontractor network
- first-party maintenance page has a `Become a Vendor` workflow and linked vendor form/password process
- `Exterior Cleaning` is explicitly named in the list of subcontracted services
- maintenance coordinator routes are public

Scout state:

- account class: `aggregate_portfolio_account`
- reported scale: 36 managed associations
- complete physical-site/building roster: unresolved
- operating-property vendor route: proven
- supplier-registration route: resolved
- explicit `exterior-cleaning` service relevance: proven
- specific property need: NOT proven
- current contract/job award: NOT proven

## 5. Vendor-entry opportunities are modeled separately from property demand

New internal views:

- `scout.v_property_management_vendor_entry_opportunities`
- `scout.v_property_management_service_specific_vendor_entries`

These surfaces represent a new commercial concept:

> a source-backed opportunity to enter a management company's vendor network or bid path.

They do not mean a particular property needs work.

A service-specific vendor-entry opportunity requires BOTH:

1. a currently valid, source-backed operating-property vendor route; and
2. source-backed evidence that the management company uses/accepts the target service category.

Current service-specific result:

- Bill Stout Properties / `exterior-cleaning` -> `service_specific_vendor_entry_ready`

The evidence supports using the documented `Become a Vendor` workflow and referencing the explicitly listed exterior-cleaning category.

The following accounts currently have valid vendor-entry routes but service-category fit remains unresolved:

- LREI Property Management LLC
- Denton Floyd Real Estate Group
- NTS Capital
- FJR Commercial
- PRG Real Estate

Their internal state is `vendor_entry_route_ready_service_fit_unresolved`, not a service-specific prospect.

### Vendor-entry guardrails

Every vendor-entry record states that it does NOT prove:

- a specific property has a service need
- a customer has requested work
- a contract or assignment exists
- a contract value
- a close probability
- revenue/ROI

## 6. Why vendor-entry is not yet in public Explore Growth

V3 intentionally stops one step short of inserting vendor-entry opportunities into the public Growth response.

Reason: aggregate accounts do not yet have normalized, deterministic service-area geography suitable for county/radius enforcement.

Exposing a Louisville vendor program in an unrelated geography query would violate Scout's deterministic routing/precision goals.

The internal vendor-entry surface is therefore production-ready, but public Growth integration is deferred until an account service-area model can enforce geography without prompt-based inference.

This is an intentional restraint, not unfinished schema plumbing.

## 7. Property crosswalk quality improvements

Denton Floyd gained two additional high-confidence physical-building resolutions without lowering the global identity threshold:

- Chandler Park Assisted Living -> FEMA nursing-home footprint, 9m from first-party property coordinate, compatible property type, confidence 0.96
- The Summit of Edgewood -> Kentucky ORNL footprint, 7.7m from first-party property coordinate, confidence 0.93; lower than an address match because the ORNL footprint lacks an address/occupancy attribute

Additional first-party completion/unit metadata was added for Clarksville Lofts, Forest Hills Commons, Chandler Park, Cardinal Landing, Maristone of Franklin, Maristone of Providence, The Landing of Long Cove, and The Summit of Edgewood.

Proximity-only candidates such as Grocers Ice Lofts remain unresolved when address/identity evidence does not converge sufficiently.

## 8. Research-queue behavior

Roster-backed accounts use `scout.v_property_management_account_research_queue`.

The queue now distinguishes:

- `property_building_crosswalk`
- `portfolio_operations_contact`
- `procurement_or_vendor_route`
- `current_need_evidence`

A proven operating-property vendor route clears the vendor-access research gap even when formal procurement remains unresolved.

Aggregate accounts use `scout.v_property_management_aggregate_account_research_queue`, whose primary next step is:

- `resolve_priority_sites_from_aggregate_portfolio`

This keeps aggregate account value visible without fabricating site-level resolution.

## 9. Privacy and public-contract status

All new V3 views are internal. Direct privileges for `anon` and `authenticated` were revoked.

No public MCP tool schema was expanded in this tranche.

The generic `scout.v_signal_window_opportunity_candidates` already excludes `exterior-cleaning` business-need signals; V3 preserves that boundary instead of using a generic business signal to bypass the exterior-cleaning identity gate.

Vendor-entry is therefore not an alternate path for injecting an unverified exterior-cleaning lead into Find Work.

## 10. Release validation

After the V3 migrations:

```sql
select agent_contract.assert_tool_registry_integrity_v1();
select agent_contract.assert_architecture_doctrine_v1();
```

Both passed.

Multifamily regression check:

- unverified multifamily candidates present in the public opportunity set: `0`

Direct `anon` / `authenticated` grants on the new internal V3 views: none.

## 11. Next implementation priority

The next architectural step is an evidence-backed account service-area model that can represent:

- states
- counties / metro areas
- explicit management markets
- optional geography geometry where source resolution supports it
- evidence source and currentness

Once deterministic service-area filtering exists, the internal vendor-entry opportunity surface can be evaluated for additive integration into Explore Growth.

After that, the highest-value research work is:

1. resolve priority sites for aggregate accounts (LREI and Bill Stout) rather than attempting complete bulk roster reconstruction;
2. continue Denton/FJR/NTS property-to-building crosswalk expansion;
3. resolve Buckingham's actual vendor entry route;
4. find current service-need evidence only where source-backed;
5. capture outcome data from vendor onboarding, first-site wins, and multi-site expansion before assigning any economic multiplier to portfolio access.
