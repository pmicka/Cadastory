# Warren County water-utility portfolio map — Batch 1

Status: isolated foundation for owner review; not a registered tool or live View. No deployment or new opportunity selector in this batch.

## Approved direction

The owner selected Warren County Water District as the first larger portfolio map. This is a bounded extension of scope beyond the existing single-site cards, not authorization for arbitrary portfolio maps. Retain diagnostics until maps are functional for every opportunity type, superseding earlier remove-after-one-reproduction guidance.

## Verified snapshot — 2026-09-14

- Organization: Warren County Water District, PWSID KY1140487.
- 24 distinct WRIS tank identities; all 24 have Point locations and the stored pilot-radius flag.
- 2 names explicitly state NOT IN SERVICE: BRIGGS HILL TANK and OAKLAND TANK. The other 22 have unverified operational state, not an assertion of current serviceability.
- 2 members have linked REHAB evidence: MIZPAH and PLEASANT HILL TANK. Both candidate observations are dated 2021-12-10. These are historical rehabilitation signals, not current jobs or proof cleaning is due.
- Roster source modification timestamps are 2023-06-12. Query date is not source freshness.
- Member relation is system membership through organization PWSIDs and exact WRIS PWSID, not proof of legal ownership, contracting authority, or site access.
- Snapshot stores no contact data, raw source payload, or raster bytes. WRIS IDs identify members; names and proximity never merge identities.

`inspect_warren.sql` reproduces the bounded read-only roster projection. `warren_fixture.json` adds fixed source_slug/relationship contract assertions to that result. These fixtures are test evidence, not a production cache. Production integration must inspect provenance of the organization-to-PWSID mapping and refresh the roster and signals through an owner-gated backend projection before issuing a live payload.

## Model and presentation semantics

One selected account and one matching member roster; future map remains the first carousel slide. A portfolio member is not automatically an opportunity. Preserve historical signal dates separately from membership and service-state categories. No territory polygon, radius, access envelope, or inferred tank outline.

The model caps this first roster at 100 members and rejects over-budget or duplicate-ID payloads rather than silently truncating. Counts derive from validated members: total, mapped, explicitly unresolved location, omitted (zero for this complete bounded roster), documented not in service, and members with historical signals. Unknown locations use an explicit discriminator; missing point fields fail validation. Future filtered/truncated rosters require a separately explicit coverage contract.

The pure frame uses Web Mercator, fitted zoom with 24px padding, exact marker positions, a 280–456 by 210 viewport, and a 12-tile budget. It rejects nonregional/dateline-spanning input instead of inventing a global framing rule. No DOM, network, host lifecycle, pan/zoom, cluster rendering, or added mapping library.

For this snapshot all tested widths select zoom 9: four tiles at widths 280/330/400, six at 456. All 24 points fit within padding. There are 29 marker pairs closer than 24px. This is an overlap diagnostic, not 29 clusters or 29 duplicate assets. The next UI batch must provide readable member identification without silently dropping, jittering, or merging asset identity; stacked markers alone are insufficient.

## Integration prerequisites

- Design the overlap/member-identification treatment within the approved card, with owner review before material visible changes.
- Add a bounded owner-only backend contract; preserve authentication, service/profile gates, and exposure contracts. This model is not an authorization layer.
- Load only the selected portfolio's bounded raster frame. Do not grow the current embed-all-exemplars resource into an unbounded portfolio tile bundle.
- Current proxy permits zoom 12–18 near three exemplars; this frame needs zoom 9. Do not weaken that proxy into a general tile service. Plan exact-frame embedded delivery with bounded URLs and host verification instead.
- Preserve the working explicit non-null state transport approach and diagnostics. Confirm normalizer, tile matching, decoding, painting, overlay, and roster coverage in the real host.
- Keep historical signals distinct from current opportunity evidence; a future current-signal class needs source/freshness semantics beyond this historical fixture.

## Validation and next batch

Run from the sandbox package: `node portfolio/test.mjs` (existing esbuild dependency). Tests exercise four viewport widths, fit/padding/tile budget, counts, determinism, duplicate/mismatched IDs, bad geometry, unsupported ownership/operational claims, and partially/fully unresolved geometry.

Next batch: bounded backend projection plus owner-reviewed overlap presentation, followed by View integration and explicit deployment authorization. No browser/host rendering is claimed by this pure foundation.
