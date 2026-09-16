# Scout responsible-party resolution

Scout's responsible-party resolver is the upstream identity stage between a site-based opportunity and buyer/contact research.

Its purpose is to answer a narrow question: **which public record or first-party source documents a party with responsibility for this site?** It does not establish purchasing authority by itself.

## Role separation

Scout keeps these roles distinct:

- `property_owner`
- `property_manager`
- `operator`
- `permit_contractor`
- `project_owner`
- buyer / procurement route

A documented property owner is not automatically the property manager, operator, tenant, contractor, or buyer. A documented operator is not automatically the buyer. Purchasing authority requires its own evidence.

Person/household property owners are retained as authoritative property evidence only. They must not be promoted into `core.organizations`, buyer hints, or generic personal-name web research. Database triggers guard both buyer-identity and buyer-queue promotion.

## Durable evidence

Authoritative responsible-party facts live in:

- `scout.opportunity_responsible_party_evidence`

The evidence record preserves the party name and kind, responsibility role, site/parcel context, source authority and URL, confidence, and provider-specific attributes.

`scout.restore_responsible_party_buyer_candidates_v1()` may restore only strong organization property-owner evidence into the unresolved buyer projection. Full buyer-route rebuilds overlay this durable evidence before reconstructing the queue.

## Provider profiles

Provider configuration lives in:

- `research.responsible_party_source_profiles`

Provider profiles declare geography, provider kind, eligible opportunity source kinds, source authority, source URL, and provider-specific fields. Adding another opportunity type to an existing compatible provider should normally be configuration, not a new closed-world branch in the seeder.

Current provider kinds are:

### `pva_lrsn_html`

Used for Jefferson County, Kentucky.

The primary Jefferson mode spatially intersects an opportunity point with the locally ingested LOJIC parcel layer, requires exactly one parcel, reads its LRSN, then fetches the public Jefferson PVA detail page. The public detail page supplies owner identity and parcel/assessment context.

Jefferson also has an alternate `address_point_lrsn_recovery` mode for opportunities already deferred by the primary spatial profile. This is a fallback for cases where the opportunity point does not intersect a unique usable parcel; it is **not** a nearest-parcel heuristic.

The recovery chain is:

1. take the opportunity's documented site address;
2. issue a bounded query to the authoritative LOJIC current-address point service;
3. require an exact normalized address match;
4. require the matching LOJIC address point to expose one distinct usable `PARCELID` + `LRSN` pair;
5. fetch the Jefferson PVA detail page for that LRSN; and
6. require the PVA parcel ID to equal the LOJIC address-point parcel ID before accepting owner evidence.

The LOJIC address-point query is bounded and paginated because a common house number can exceed one ArcGIS page. The worker currently reads at most five pages of 200 rows each and fails closed if the bounded result set still cannot be proven complete.

The assessor's primary situs address is allowed to differ from the operational/site address. Multi-building or multi-address parcels make that a normal condition. Parcel identity, not fuzzy situs-address equality, is the cross-source join after the exact LOJIC address-point match.

The recovery profile is `ky_jefferson_pva_address_lrsn`. It keeps `eligible_source_kinds=[]` so it cannot enter the ordinary spatial seeder. Its dedicated recovery seeder reads `recovery_source_kinds`. The profile deliberately keeps `automated_dispatch=false`; recovery work is consumed only through the dedicated `address_recovery` claim scope, not through the ordinary local claim RPC.

### `arcgis_point_owner`

Used for authoritative public ArcGIS parcel services that expose owner and parcel identifiers directly.

Scout does **not** bulk-mirror the county dataset. It issues a bounded point-intersection query only for a current opportunity and requests only the configured owner and parcel-ID fields.

The worker must fail closed when the service returns:

- zero parcel features;
- more than one parcel feature;
- no owner value;
- no parcel identifier;
- malformed JSON;
- an ArcGIS error; or
- invalid/missing query configuration.

A successful point lookup remains property-owner evidence only. Management, operation, and purchasing authority are not implied.

### `embedded_parcel_owner`

Reserved for locally ingested assessor layers whose schema has been explicitly verified to contain owner identity. A field named `NAME` is not enough by itself: the source schema must establish that it means owner name. Do not treat geometry-only parcel layers or street-name fields as owner data.

No production seeder should claim this provider kind until an explicit embedded-owner implementation exists.

## Local and remote seed lanes

Local and remote providers are seeded separately.

The local seeder operates only on supported locally backed providers. The remote seeder operates only on `arcgis_point_owner` profiles. This prevents remote-provider candidates from being repeatedly scanned by a local spatial join that cannot resolve them.

Jefferson address recovery is a third seed stage inside the same responsible-party scheduler. It considers only candidates with an active deferral from the canonical Jefferson spatial profile and clusters them by normalized site address. It does not replace the primary spatial seeder and does not create a separate cron.

All seeders skip candidates already attached to an active responsible-party job. Exhausted jobs may re-enter only when their bounded `requery_after` interval is due.

## Acquisition transport lanes

Acquisition transport is deliberately separate from evidence semantics.

### Local Jefferson transport

`pva_lrsn_html` jobs are processed by the private authenticated Supabase Edge Function `collect-responsible-party-resolution`.

Ordinary Jefferson jobs are claimed through `internal_claim_local_responsible_party_resolution_jobs_v1()`. The legacy claim RPC delegates to this local-only lane so the scheduled Edge Function cannot consume remote ArcGIS jobs or address-recovery jobs.

Recovery jobs use the separate `internal_claim_responsible_party_address_recovery_jobs_v1()` claim RPC and invoke the same Edge Function with `claim_scope=address_recovery`. Recovery first resolves an exact LOJIC address point to LRSN/PARCELID, then fetches the same public PVA detail source used by primary Jefferson jobs.

The release cadence remains the existing responsible-party cadence: seed at minute `21`, then the existing worker cron at minutes `22` and `52`. The worker cron does not gain another schedule. Instead, its command invokes a scheduler wrapper that spends the same eight-job budget as a fixed **4 primary + 4 recovery** split per run. This prevents a large recovery backlog from starving ordinary parcel work while guaranteeing bounded recovery progress.

The split is intentionally enforced outside priority ordering. During pre-release fairness analysis, 308 active recovery candidates outranked the primary Jefferson queue's then-current maximum priority, so a single merged priority queue would have allowed fallback work to monopolize the worker.

### Remote ArcGIS transport

Schneider's public Nelson and Daviess ArcGIS services were verified to reset outbound connections from Supabase Edge before an HTTP response was returned. Forcing HTTP/1.1 did not change that behavior. The services were then successfully exercised from GitHub-hosted Actions runners.

`arcgis_point_owner` jobs therefore use `internal_claim_remote_responsible_party_resolution_jobs_v1()` and `scripts/scout_responsible_party_arcgis_worker.py`, scheduled by `.github/workflows/scout-responsible-party-arcgis.yml`.

This is a private unattended enrichment transport, not an MCP/runtime dependency. It uses the existing GitHub Actions Supabase service-role secrets, performs a live source probe before claiming work, restricts outbound ArcGIS requests to the approved Schneider host, retains no source media, and writes only through Scout's existing responsible-party completion RPC.

Successful remote evidence records `acquisition_transport=github_actions` and preserves the exact reproducible ArcGIS point-query URL.

## Resolver-specific deferrals

A local parcel lookup that currently has no unique usable parcel match is recorded in:

- `research.responsible_party_resolution_deferrals`

Deferral reasons are bounded to:

- `no_local_parcel_match`
- `ambiguous_local_parcel_match`
- `missing_local_parcel_lookup_key`

These deferrals suppress only this responsible-party parcel resolver for the affected provider until requery is due. They **must not** delay or block the global buyer queue, because another upstream strategy may still resolve the opportunity.

This distinction also prevents high-priority no-match parcels from monopolizing every seed window and starving lower-priority resolvable candidates.

Jefferson address recovery deliberately leaves the original spatial deferral intact. The deferral documents that the primary point-to-parcel method failed; the alternate recovery job records whether the authoritative address-point route succeeded. The two states are not contradictory and should not be collapsed into one generic "parcel resolved" flag.

## Documented manager and operator lane

Scout may also derive site-responsibility evidence from current first-party portfolio sources that explicitly document management or operation of a site.

A strong current `property_manager` relationship may enter the named-responsibility lane when the opportunity is otherwise unresolved. This does **not** establish that the manager owns the property or has purchasing authority for the relevant service.

A strong current `operator` relationship is evidence-only. Operator evidence must not be auto-promoted into buyer identity or buyer hints.

Address-based matching for this lane requires exact normalized site address plus state, or a stronger canonical property/building link. Ambiguous multi-organization matches fail closed.

## Manager contact-research projection boundary

Documented property managers may be researched for durable public facilities, maintenance, procurement, vendor, or general organizational contact routes. This is still research only; Scout does not send messages, submit forms, place calls, register vendors, or otherwise contact the organization.

Manager-contact research may reuse the bounded `buyer_organization_contact_v1` worker engine only when buyer projection is structurally suppressed.

The generic table:

- `research.document_evidence_job_candidates`

is a buyer-identity projection boundary. Jobs linked through it can participate in downstream buyer restoration and projection. **Manager-only contact research must not use that table.**

Instead, manager-contact jobs use:

- `research.responsible_party_contact_job_candidates`

and keep the opportunity association separate from buyer projection. The job context must record `research_domain=responsible_party_contact`, `responsibility_role=property_manager`, `identity_projection=suppressed`, and `buyer_authority_not_implied=true`.

A successful manager-contact job may add defensible public routes to the known manager organization in `core.organization_contact_points`. It must not change the opportunity's buyer identity, buyer-resolution state, or purchasing-authority semantics merely because a manager contact route was found.

## Worker contracts

`collect-responsible-party-resolution` is an internal authenticated Edge Function for the local Jefferson lane. It uses Scout's established `x-scout-key` custom authentication and intentionally retains the existing `verify_jwt:false` posture because authentication is enforced in-function.

The remote ArcGIS GitHub worker uses the same database completion contract but a separate claim lane. Both workers are bounded by claim size, source timeout, retry budget, and lease semantics. Unsupported or ambiguous evidence is not guessed into a buyer identity.

Jefferson address recovery inherits the same completion contract and therefore the same role boundary: a successful recovery writes `property_owner` evidence. Organization owners may enter the named-responsibility lane and later be materialized as organizations for contact research; person/household owners remain evidence-only and must not be used as personal-name research targets.

No source media is retained.

## Current geography

Jefferson County uses the LOJIC parcel geometry plus public Jefferson PVA detail source and currently supports construction, exterior-cleaning, and roof-lifecycle responsibility resolution. For primary spatial deferrals, the Jefferson-only fallback uses the LOJIC current-address point service to bridge an exact site address to LRSN/PARCELID before the same PVA owner lookup.

This fallback is intentionally county-specific. The architecture is reusable, but another county must have its own authoritative address/parcel identity source and provider profile; Scout must not assume Jefferson field names or resolution semantics elsewhere.

Nelson and Daviess Counties use bounded public Schneider/ArcGIS point-owner queries for exterior-cleaning candidates. Production acceptance on 2026-09-15 verified both source probes from the GitHub Actions transport and a four-job live batch: all four completed with authoritative owner/parcel evidence, three organization owners entered the named-responsibility lane, and one person/household owner remained evidence-only with no buyer-identity or queue-hint promotion.

## Jefferson address-recovery acceptance

Bounded production acceptance on 2026-09-16 exercised the recovery lane before autonomous dispatch was enabled.

The accepted chain was:

- exact site address -> LOJIC address point;
- one distinct LOJIC `PARCELID` + `LRSN`;
- public Jefferson PVA detail page;
- exact LOJIC/PVA parcel-ID agreement;
- property-owner evidence only.

The first accepted set contained seven opportunity evidence rows across six recovery jobs:

- five organization-owner rows;
- two person/household-owner rows;
- zero household promotions;
- five organization owners materialized to durable `core.organizations` through the existing buyer-document pipeline; and
- zero outbound contact.

Acceptance also caught and corrected two worker defects before release:

1. the PVA page has a branded masthead `<h1>` before the property-address `<h1>`, so the parser now selects the plain property heading; and
2. common house numbers can exceed a single 200-row ArcGIS page, so LOJIC address lookup now uses bounded pagination up to five pages / 1,000 rows and fails closed if the bounded set is still incomplete.

The unauthorized Edge Function boundary returned `401` during acceptance.

A full `scout.refresh_opportunity_buyer_routes()` rebuild was then run against the accepted evidence. All five organization-owner rows retained their durable organization IDs and named-responsibility projection, while both person/household rows remained `role_only` with no organization ID, buyer organization, buyer hint, or buyer name. That rebuild is the persistence acceptance for the fallback lane.

Pre-release fairness analysis then evaluated the full active Jefferson deferral population. Of 1,014 then-current eligible deferred candidates, 308 had priority above the primary local queue's maximum. Recovery therefore uses a fixed 4/4 lane split rather than merging fallback jobs into the primary priority ordering.

## Production acceptance

A new provider or opportunity type is not considered production-ready solely because its schema or public service metadata looks correct.

Deployment verification should include:

1. seed a bounded set of jobs;
2. execute a very small live worker batch through the intended production transport;
3. confirm zero/ambiguous/malformed responses fail closed;
4. inspect representative owner and parcel evidence;
5. verify person/household owners are not promoted;
6. verify organization-owner evidence survives normalized-facts and buyer-route rebuilds;
7. verify the seeder advances across the backlog rather than repeatedly selecting the same no-match candidates;
8. confirm unauthorized Edge Function access returns `401` for Edge-hosted lanes; and
9. run the standard Scout architecture assertions.

For Jefferson address recovery, acceptance additionally requires exact LOJIC address-point matching, LOJIC/PVA parcel-ID agreement, bounded pagination behavior, confirmation that the ordinary spatial deferral remains resolver-specific rather than blocking the global buyer queue, and a bounded dispatch strategy that cannot starve primary Jefferson work.

For manager-contact research, acceptance additionally requires proving that successful contact-route extraction leaves buyer identity and buyer queue state unchanged and that no `research.document_evidence_job_candidates` rows are created for `responsible_party_contact` jobs.

Required assertions:

```sql
select agent_contract.assert_tool_registry_integrity_v1();
select agent_contract.assert_architecture_doctrine_v1();
```

The responsible-party internal tables also follow Scout's RLS posture. Privacy assertion failures from unrelated tables should be reported separately rather than masked by weakening this subsystem.

Treat successful assertion execution as completion without assertion failure; do not weaken privacy, authorization, provenance, or evidence controls to make an assertion pass.
