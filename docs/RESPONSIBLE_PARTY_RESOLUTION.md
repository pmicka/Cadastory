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

Scout spatially intersects an opportunity point with the locally ingested LOJIC parcel layer, requires exactly one parcel, reads its LRSN, then fetches the public Jefferson PVA detail page. The public detail page supplies owner identity and parcel/assessment context.

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

Both seeders skip candidates already attached to an active responsible-party job. Exhausted jobs may re-enter only when their bounded `requery_after` interval is due.

## Acquisition transport lanes

Acquisition transport is deliberately separate from evidence semantics.

### Local Jefferson transport

`pva_lrsn_html` jobs are claimed through `internal_claim_local_responsible_party_resolution_jobs_v1()` and processed by the private authenticated Supabase Edge Function `collect-responsible-party-resolution`.

The legacy claim RPC delegates to this local-only lane so the scheduled Edge Function cannot consume remote ArcGIS jobs.

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

## Worker contracts

`collect-responsible-party-resolution` is an internal authenticated Edge Function for the local Jefferson lane. It uses Scout's established `x-scout-key` custom authentication and intentionally retains the existing `verify_jwt:false` posture because authentication is enforced in-function.

The remote ArcGIS GitHub worker uses the same database completion contract but a separate claim lane. Both workers are bounded by claim size, source timeout, retry budget, and lease semantics. Unsupported or ambiguous evidence is not guessed into a buyer identity.

No source media is retained.

## Current geography

Jefferson County uses the LOJIC parcel geometry plus public Jefferson PVA detail source and currently supports construction, exterior-cleaning, and roof-lifecycle responsibility resolution.

Nelson and Daviess Counties use bounded public Schneider/ArcGIS point-owner queries for exterior-cleaning candidates. Production acceptance on 2026-09-15 verified both source probes from the GitHub Actions transport and a four-job live batch: all four completed with authoritative owner/parcel evidence, three organization owners entered the named-responsibility lane, and one person/household owner remained evidence-only with no buyer-identity or queue-hint promotion.

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

Required assertions:

```sql
select agent_contract.assert_tool_registry_integrity_v1();
select agent_contract.assert_architecture_doctrine_v1();
```

The responsible-party internal tables also follow Scout's RLS posture. Privacy assertion failures from unrelated tables should be reported separately rather than masked by weakening this subsystem.

Treat successful assertion execution as completion without assertion failure; do not weaken privacy, authorization, provenance, or evidence controls to make an assertion pass.
