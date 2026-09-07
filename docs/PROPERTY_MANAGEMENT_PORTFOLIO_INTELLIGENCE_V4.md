# Property Management Portfolio Intelligence v4

Status: deployed to production on 2026-09-07.

V4 closes the coverage-work tranche for Scout's property-management intelligence layer. The release separates three concepts that must not be conflated:

1. portfolio/account coverage,
2. physical property-to-building crosswalk coverage, and
3. research coverage.

The release is considered coverage-complete when every currently serviceable roster-backed property has either a resolved physical crosswalk or a current reviewed resolution outcome, and every account-level research queue has no unresolved research step. Physical crosswalk coverage is intentionally allowed to remain below 100% when current source evidence cannot support a defensible building identity.

## Production migrations

- `20260907193605 property_management_coverage_closure_foundation_v4`
- `20260907194354 property_management_coverage_evidence_and_association_roster_v4`
- `20260907194421 property_management_coverage_contacts_and_review_evidence_v4`
- `20260907194437 property_management_account_evidence_summary_coverage_v4`
- `20260907194723 property_management_property_resolution_reviews_seed_direct_v4`
- `20260907194743 property_management_property_research_coverage_views_v4`
- `20260907194817 property_management_account_research_queue_coverage_semantics_v4`
- `20260907195425 property_building_resolution_reviews_rls_v4`

Exact applied SQL remains in `supabase_migrations.schema_migrations` for project `ufpkjaadmmpmeogzhrcq`.

## Verified final roster-backed coverage

Production totals after release validation:

- serviceable portfolio properties: **88**
- research-complete properties: **88**
- research gaps: **0**
- physically crosswalked properties: **26**
- resolved building footprints: **33**

Per-account state:

| Account | Serviceable properties | Crosswalked properties | Resolved buildings | Research complete | Research gaps | Physical crosswalk coverage |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Buckingham Companies | 4 | 0 | 0 | 4 | 0 | 0.0% |
| Denton Floyd Real Estate Group | 27 | 3 | 3 | 27 | 0 | 11.1% |
| FJR Commercial | 23 | 10 | 11 | 23 | 0 | 43.5% |
| Hagan Properties | 5 | 1 | 3 | 5 | 0 | 20.0% |
| NTS Capital | 24 | 10 | 12 | 24 | 0 | 41.7% |
| PRG Real Estate | 5 | 2 | 4 | 5 | 0 | 40.0% |

The difference between research coverage and physical crosswalk coverage is intentional. Scout does not choose a nearby footprint merely to improve a coverage percentage.

## Resolution-review semantics

New internal table:

- `scout.property_building_resolution_reviews`

A serviceable managed property can terminate research in one of these states:

- a resolved row exists in `scout.property_building_links`, or
- a current reviewed resolution outcome documents why a defensible building link could not be created from available evidence.

Reviewed outcomes distinguish ambiguity/source coverage from an untouched research task and have finite verification windows so improved source data can reopen the case later.

New/updated internal surfaces:

- `scout.v_property_management_property_coverage_summary`
- `scout.v_property_management_property_research_queue`
- `scout.v_property_management_account_research_queue`
- `scout.v_property_management_aggregate_account_research_queue`

Account queues now measure research completion separately from physical crosswalk percentage.

## Queue closure

All six roster-backed account queues currently report:

- `missing_steps = []`
- `next_research_step = monitor_account`

Accounts:

- Denton Floyd Real Estate Group
- FJR Commercial
- NTS Capital
- Hagan Properties
- PRG Real Estate
- Buckingham Companies

Both aggregate accounts also report:

- `missing_steps = []`
- `next_research_step = monitor_account`

Aggregate accounts:

- Bill Stout Properties, Inc.
- LREI Property Management LLC

A closed research step does not imply a vendor route, physical building match, or current service need exists. It means the current evidence state has been investigated and explicitly recorded.

## Hagan portfolio correction

V4 corrected a material undercount in Hagan's portfolio representation.

The earlier seed only represented residential assets. Current first-party Hagan portfolio evidence also supports active retail assets, including Shelbyville Road Plaza and TaylorHurst Shopping Center.

Production state after correction:

- Hagan serviceable managed properties: **5**
- account class: `portfolio_account`
- Shelbyville Road Plaza is represented as a managed property/site
- three FEMA retail footprints sharing the exact `4600 SHELBYVILLE ROAD` address resolve to that site
- TaylorHurst is retained as a current portfolio property but remains physically uncrosswalked until a defensible building source is available
- portfolio operations routing is documented

The Hagan leasing contact is not treated as facilities procurement authority.

## FJR crosswalk correction

FJR's Behavioral Health Campus at `4627 Dixie Hwy` was previously blocked by the Louisville/Shively locality difference despite an exact normalized address.

V4 resolves the property to the exact-address FEMA building record with source-backed locality-alias evidence. FJR now has:

- 23 serviceable properties
- 10 crosswalked properties
- 11 resolved building footprints

## Bill Stout association roster

Bill Stout's first-party managed-association roster is now represented as **36 managed association assets** using the namespace:

- `ingest.managed_association`

These are linked through `core.organization_asset_links` with `relationship_type = 'manages'`.

Guardrail:

**36 managed associations does not mean 36 physical buildings or 36 current exterior-cleaning jobs.**

Association identity remains distinct from physical property/building identity.

## Aggregate-account coverage semantics

LREI and Bill Stout no longer remain perpetually incomplete simply because they do not expose a complete physical building roster.

For aggregate accounts, Scout records whether current public roster/site research has been completed and preserves the aggregate-vs-resolved distinction.

- Bill Stout: named managed-association roster captured; physical building mapping is separate.
- LREI: aggregate portfolio scale and vendor onboarding are documented; a complete public physical site roster remains unavailable/unresolved and is not fabricated.

## Current-need research

V4 records dated current-need research outcomes for the property-management account set.

A negative scan means:

> no active need is currently resolved in Scout's present evidence layers.

It does **not** mean the portfolio has no exterior-cleaning or building-service need. The evidence is time-bounded and should be refreshed as its verification window expires.

## Vendor/buyer-route coverage

The account queues now consider a source-backed operating-property vendor route or supplier/procurement route sufficient to close the vendor-access research step. A current reviewed `no public route resolved` outcome can close the research task without pretending a route exists.

Existing high-value routes remain intact:

- Denton Floyd: first-party Vendor Inquiries route
- NTS Capital: portfolio Property Services/project-bid route
- FJR Commercial: Facilities & Maintenance vendor-coordination route
- PRG Real Estate: Vendor Shield onboarding/compliance route
- Bill Stout: Become a Vendor workflow; exterior cleaning explicitly named as a subcontracted service
- LREI: public preferred-vendor onboarding workflow

Buckingham and Hagan retain documented operational/vendor context without a fabricated centralized procurement claim.

## Explore Growth regression

Public Growth behavior remains geographically bounded.

Verified against the sandbox operator connection after V4:

- Jefferson County, KY: **1** account-access opportunity — Bill Stout Properties, Inc.
- Fayette County, KY: **0** account-access opportunities

Bill Stout is surfaced as a strategic account/vendor-entry opportunity, not as proof of a specific property cleaning need or contract award.

## Multifamily identity gate

Regression result after all V4 changes:

- unverified multifamily rows leaking into the public exterior-cleaning opportunity set: **0**

The portfolio coverage work therefore did not create a bypass around Scout's multifamily identity-verification gate.

## Privacy / RLS posture

All V4 internal research views have no direct `anon` or `authenticated` grants.

The new `scout.property_building_resolution_reviews` table also has direct public/anon/authenticated privileges revoked and RLS explicitly enabled.

The RLS hardening migration was added after final audit because the table initially had no public grants but RLS itself was not enabled. V4 treats that as defense-in-depth drift and corrects it rather than relying solely on grants.

## Final production assertions

All release assertions pass after the RLS correction:

```sql
select agent_contract.assert_tool_registry_integrity_v1();
select agent_contract.assert_architecture_doctrine_v1();
select agent_privacy.assert_rls_posture_v1();
```

All three return successfully.

## Coverage-complete definition going forward

For this property-management tranche, Scout now considers coverage complete when:

1. the management account itself is source-backed;
2. serviceable portfolio scope is documented or explicitly aggregate-only;
3. each roster-backed serviceable property is either physically resolved or has a current resolution-review outcome;
4. portfolio operations/contact research has a current outcome;
5. vendor/procurement research has a current outcome;
6. current-need evidence has a current outcome;
7. the account research queue is drained to `monitor_account`;
8. public geography, identity, privacy, and anti-enumeration gates remain intact.

This definition intentionally does **not** require 100% building-footprint crosswalk coverage. Requiring that would incentivize false identity resolution where the underlying public corpora are incomplete.

## Next phase

The coverage-build phase is complete. Future work should be refresh/measurement work rather than repeated baseline research:

- refresh expiring resolution reviews when better building/parcel/geocoder sources arrive;
- refresh current-need scans;
- resolve newly published portfolio assets;
- record vendor-onboarding outcomes;
- record first-site wins and subsequent multi-site expansion;
- calibrate portfolio-option value only from observed conversion/revenue outcomes.
