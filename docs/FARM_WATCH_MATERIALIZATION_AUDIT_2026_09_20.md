# Farm Watch materialization audit — Stage 1

Date: 2026-09-20. Status: audit complete; no runtime migration or deployment performed.

## Evidence and scope

Inspected current GitHub implementation and live Supabase project `ufpkjaadmmpmeogzhrcq` before recommending a contract.

- Cadastory main: `5d461cc38e565c6227ad35dcfa5b12528028a993`.
- Notebook main tree: `59bda09a84b71a754a89d84f991a81e715fe27e4`.
- Read supplied SCOUT_CHATGPT_DEVELOPMENT_WORKSPACE.md, Cadastory AGENTS.md and MCP architecture doctrine.
- Notebook has no AGENTS.md in the inspected recursive tree. No standalone Farm Watch architecture/contract Markdown was found in either current tree. Operative Farm Watch contracts are embedded in `index.html` (FarmWatchLayerContract, defaults, caveats), product interpretation fields, backend code and migrations.
- Inspected all six requested browser modules plus app, environment, land, regulatory, soil, hydrology, interpretation and registration modules.
- Retrieved deployed source for all four Farm Watch Edge Functions. Versions: private 6, environment 1, regulatory 1, land 10. All four have `verify_jwt:false`.
- SQL inspection was read-only. No source refresh, property mutation, raw-data download, Scout sandbox call or production deployment occurred.

This is an implementation and live-state audit, not a browser performance benchmark. No user IndexedDB was inspected. Transfer sizes and wall-clock savings are unknown unless specifically labeled below.

## Live backend baseline

| Surface | Observed state | Disposition |
|---|---|---|
| properties | 1 row; geometry, metadata and active owner-only scope | Preserve canonical geometry and access gate |
| property_soil_map_units_v1 / property_soil_profiles_v1 | 4 map units and 4 deep profiles | Preserve SSURGO provenance, units and methods |
| property_hydrology_features_v1 / hydrology_refresh_state_v1 | 36 features; explicit refresh state | Preserve mapped-water versus modeled-flow distinction |
| property_environment_context_v1 | 6 rows | Preserve dated external environmental evidence |
| property_regulatory_context_v1 | 1 row | Preserve separate static and FAA freshness |
| property_land_context_v1 | 1 available row; serialized JSON text 32,040 bytes; context_version 5 | Preserve canonical terrain, geology, watershed, synthesis and canopy semantics |
| General property materializations | No matching materialization table found in information_schema; none in farm_watch | A shared durable product surface is still missing |
| Storage | Only scout-private-media; private; 25 MiB limit; JPEG/PNG/WebP/HEIC/HEIF only | Do not broaden this media bucket to accommodate geospatial artifacts |

Important deployed-versus-materialized difference: land function v10 and current GitHub code require context_version 6 and implement Science TCC plus Science TCC standard error. The stored row is still version 5, contains NLCD TCC year 2025 / product v2025-6, and has neither `canopy_science` nor `canopy_science_standard_error`. The code can refresh these centrally; their presence as stored products is not yet demonstrated. Do not describe them as already materialized. This audit did not trigger refresh.

All nine farm_watch tables have RLS enabled. All 21 inspected public farm_watch RPCs deny EXECUTE to anon/authenticated and permit service_role. Existing Edge access is bearer validation through auth.getUser, followed by farm_watch_authorize_user_v1_internal and bounded property selection. New retrieval must preserve those checks and active-property behavior. Do not add a direct authenticated-table shortcut.

The canonical land context is not an equivalent of the 61×61 grid: geometry-clipped raster min/max/relief, slope/aspect/elevation histograms and exact vector-unit synthesis must remain distinct from coarse browser samples.

## Product inventory and decisions

Classes: 1 raw external source; 2 transient intermediate; 3 experimental derivative; 4 mature deterministic derivative; 5 canonical structured evidence; 6 render-only client state. Mixed bundles are split below rather than promoted wholesale.

| Product / implementation | Browser download and compute today | Persistence / identity / trigger | Class | Decision and reason |
|---|---|---|---|---|
| Imagery, IR, DEM, COPC/LAZ and federal raster source assets | ArcGIS exportImage/tile requests; COPC range reads; raster statistics fetched by backend | Provider remains source of truth | 1 | Leave external; retain exact identities and retrieval metadata, not bulk copies |
| Reference tiles, imagery/IR/hillshade display; app.js | Visible map tiles and per-tile exportImage; coordinate transforms | Browser HTTP/render state; current viewport | 1 + 6 | Leave source external; keep rendering local |
| ImageServer service extent / coverage check; app.js | Service metadata JSON and extent intersection | localStorage + Map; service key; 30-day TTL | 1 + 2 | Retain browser cache temporarily; compact metadata, not a mature parcel product |
| Imagery acquisition resolution; environment-context.js | identify catalog request at property center; raster-name/date parsing | Session sourceDateCache; source/property context | 4, bounded metadata derivation | Retain temporarily; later share source-resolution provenance without changing date-confidence rules |
| Terrain samples; analysis-layers.js | 3,721 samples via five serial getSamples POSTs (900,900,900,900,121); 8% bounds padding | Included in IndexedDB terrain-analysis bundle | 4 | Centralize first with grid, coordinate/units, validity and exact source identity |
| Contour levels/paths and summary | Marching squares, parcel-touch filtering, endpoint stitching | Same terrain bundle/version | 4 | Centralize with terrain; preserve current geometry semantics exactly |
| D8 network / sorted valid cell indexes | Neighbor descent and accumulation; currently computed for flow paths and again for anatomy | Ephemeral arrays | 2 | Keep intermediate in compute worker; avoid persisting unless a consumer needs it |
| Terrain flow traces | D8-based path extraction | terrain bundle flow_paths | 4 | Centralize first; retain unconditioned local-downhill limitation |
| Sampled high/low sectors and outlet-zone summary | Point-in-polygon, routing terminals, clustering, percentage and stated-acre conversion | terrain bundle anatomy | 4 with approximate interpretation | Centralize first, but include stated_acres dependency or move that presentation conversion outside immutable core |
| LiDAR source manifest; lidar-audit.js | Two STAC collection searches, POST then GET fallback; item/asset metadata normalization | IndexedDB lidar-source-audit / kyfromabove-stac-v1; property boundary key; 30-day TTL or force | 4, source/coverage metadata only | Centralize as supporting source manifest when LiDAR phase begins; STAC match is not proof of full coverage |
| COPC headers, hierarchy, decoded returns; lidar-point-audit.js | copc@0.0.9 module, laz-perf@0.0.7 JS/WASM; range reads; parcel clipping and return filtering | Raw returns are not in saved bundle | 1 + 2 | Leave raw external; keep decoding intermediates transient in an off-browser worker |
| Ground support, normalized per-point heights | 2 m ground grid; 10 m support radius; ground interpolation; HAG normalization | Working arrays, not saved normalized point cloud | 2 | Keep transient; persist method/QA and derived grids rather than raw or normalized point arrays |
| Phase 3 neutral physical structure | 5 m anchor grid, five bands split at 4/16/32/64 feet; minimum 10 returns | physical_structure_model inside IndexedDB lidar-point-products / copc-v5-batch4-physical-v1 | 4 | Centralize after terrain contract is proven; preserve neutral HAG meaning, acquisition uncertainty and coverage |
| Classification counts, GPS provenance, height histogram, QA summaries | Per-phase count/histogram/quantile and timestamp analysis | point_audit.results in same bundle | 4 for QA measurements; some diagnostics 3 | Carry essential support/quality/provenance with physical product; do not promote candidate histogram valleys or thresholds into biological interpretation |
| Phase 2/3 common 10 m grids, temporal share/persistence comparison | Reprojection, neutral-band comparison, sensitivity schemes | batch5_comparison_context and temporal fields bundled with current structure | 4 numerical derivative + 3 validation interpretation | Retain browser-local temporarily; separate optional historical product from current physical grid before migration |
| Leaf-off horizontal texture; leaf-off-structure.js | Per supported source: imagery + IR + DEM slope PNG + hillshade PNG when solar time is known; canvas decode, texture integrals, 7 m neighborhoods, normalization and support surfaces | Session Map/buildPromises keyed by source id and reset by property context; method leaf_off_structure_v1_2_7m | 3 explicitly: experimental_horizontal_woody_spatial_context | Retain browser-local temporarily. Later persistence may retain experimental class; not eligible for automatic canonical promotion |
| Leaf-off image arrays and integral surfaces | Luminance, gradients, spectral arrays, slope/hillshade RGBA, integral sums | Session compute intermediates | 2 | Keep transient |
| Leaf-off transfer/registration/decomposition/aggregation | Cross-year comparisons and alternate spatial support | Session diagnostics behind leafOffInternalQa flag | 3 | Keep transient and dormant; do not migrate |
| Leaf-off × LiDAR residual/matching/blind-packet QA; leaf-off-lidar-audit.js | Consumes previous grids; blocked-CV/residuals, matched patches, blind packet and reveal exports | Session products plus local review annotations | 3 | Keep experimental/dormant; no new inference work and no automatic centralization |
| Manual registration control points; registration-probe.js | User-captured points, differences and shift summary | localStorage; explicitly manual | 3, user-authored QA input | Retain local; not deterministic source processing and outside this migration |
| Property geometry, soils, hydrology, environment, regulation, geology/watersheds | Authenticated backend retrieval; browser styles/formatting | Existing Supabase tables/RPCs | 5 | Preserve current canonical stores; no second generic copy |
| Canonical DEM statistics, terrain distributions, cross-layer synthesis, NLCD TCC; Science pair capability | Backend raster statistics and exact PostGIS intersections | property_land_context_v1, method/context versions, TTLs | 5; canopy remains modeled source evidence | Preserve semantics and stores; separately note Science pair materialization gap |
| Legends, panes, selected year, toggles, overlays, popup formatting, interpretation.js projections | Canvas/Leaflet rendering and text projection | UI memory/state | 6 | Keep client-side; central storage would not improve source reuse |

No current product is selected for immediate retirement. Obsolete browser computation becomes removable only after a central replacement has passed cold-client verification. Human review notes are not a disposable deterministic cache.

## Current identity and reliability gaps

1. **Terrain source identity is insufficient.** Cache key is kind + algorithm version + slug + 32-bit FNV-style hash of JSON boundary. Source URL exists only in metadata. No TTL or source revision check is requested. A mutable service can change beneath a healthy-looking local product.
2. **Terrain has another deterministic input.** deriveTerrainAnatomy uses stated_acres for outlet estimates. Neither stated_acres nor its revision is in the persistent key. updated_at affects session initialization but does not invalidate the IndexedDB record.
3. **Cache key is not an exact durable boundary identity.** A 32-bit hash can collide; JSON ordering/representation can cause unnecessary misses. Central identity must derive from authoritative full-precision geometry and explicitly defined canonical serialization, not a browser-supplied slug/hash.
4. **LiDAR bundle mixes availability domains.** Current Phase 3 product, historic grids, temporal diagnostics and point audit share a single record and version. Physical rendering can work without temporal comparison, but the build still attempts both collections.
5. **LiDAR selection is not all-tile processing.** auditAsset selects collection.items[0]. STAC discovery requests limit 100 and does not follow pagination. Signature sorts all reported items, whereas processing uses only the first item in returned order. A reordered result may change the selected asset without changing the signature. A central worker must establish explicit asset coverage/order and report partial coverage; this audit does not claim an actual missing tile on the current property.
6. **Signature refresh is not continuous.** LiDAR source signature uses item id, updated, count, density and stable asset URL/key; source audit can remain cached for 30 days. It is not an object checksum or guaranteed immutable revision. Query strings are stripped, which must be revisited if a provider encodes a meaningful version there.
7. **Stale LiDAR can look healthy.** Local point bundle is applied before source revalidation. If source audit then fails, an existing available pointAudit is retained without explicit stale labeling. Outer pointAudit status is available after collection processing even when a collection returns a non-available status. Product availability needs per-product validation, not that outer flag alone.
8. **Serialization must preserve array types.** IndexedDB structured-clones typed grids. JSON.stringify of Uint32Array does not produce a normal array that passes the current length checks. Central format needs explicit dimensions, types, counts, endian/version if binary, and reconstruction/validation.
9. **Leaf-off identity is property-specific and mutable-source-dependent.** Acquisition labels are hardcoded for supported example imagery. Requests use ImageServer exportImage rather than a pinned raster identifier. Do not generalize those labels to every property or treat a source-id string as exact acquisition identity.
10. **Experimental and observed must remain distinct.** LiDAR physical model text calls it authoritative physical evidence, while the enclosing audit says local materializations are not canonical. Central records should explicitly identify deterministic height derivation from authoritative point observations, preserving limitations rather than interpreting storage location as scientific authority.
11. **Existing backend freshness is not the desired generic contract.** Land context validates method/version and TTL, and can return cache:stale alongside an old status. The new materialization path must expose freshness independently and never quietly relabel incompatible old data as available.

## Artifact size and savings

These are code-derived payload estimates, not measured production transfer sizes:

| Product | Size basis | Implication |
|---|---|---|
| Terrain base grid | 3,721 × (lon, lat, elevation) × 8 = 89,304 bytes of numeric payload before metadata, null masks or contour/flow geometry; regular coordinates could be implicit | Full JSON size depends on geometry and decimal encoding; measure actual artifact in first migration |
| Terrain derived paths | Variable with relief/contour count and path lengths | Prefer artifact storage if complete bundle exceeds a deliberately bounded inline limit |
| LiDAR band grid | Five Uint32 bands + total: 24 bytes per bounding-grid cell, plus metadata | 10,000 cells = 240,000 bytes; 100,000 = 2.4 MB per grid. Two historical 10 m grids add their own payload |
| LiDAR intermediates | XYZ buffer 24 bytes per decoded candidate point plus normalized heights 8 bytes per retained point, ground surfaces, decoder memory | Strong reason for off-browser compute; no defensible total range-transfer estimate without a measured run |
| Leaf-off retained surfaces | Four Uint8 arrays + six Float32 arrays = 28 bytes per terrain cell | At 1000×1000 cap: 28 MB decimal before metadata/overlay/intermediates; do not persist default JSON expansion |
| Leaf-off decoded source imagery | Each 1800×1800 RGBA image up to 12.96 MB; imagery and IR up to 25.92 MB combined | Transient decoded memory only, not compressed provider bytes |
| Canonical land context | Measured SQL octet_length(context::text): 32,040 bytes | Existing compact canonical facts already fit Postgres well |

Per additional cold terrain client, a central hit removes five upstream sample requests and contour/flow/anatomy processing, replacing them with central metadata/artifact retrieval. For N independent cold clients under one unchanged identity, avoid 5×(N−1) sample calls after one successful build, excluding source-metadata validation.

A LiDAR central hit should eliminate COPC hierarchy/point range requests, decoder loading and normalization for that product. Savings are substantial in kind but not quantified in seconds or MB yet. Do not claim benchmark improvements without recording source bytes, worker runtime, artifact bytes and cold-client requests.

## Execution and storage assessment for Stage 2

The following are audit recommendations, not an implemented schema or finalized contract.

- Reuse Farm Watch service-only schema/RPC convention and established authenticated Edge retrieval. Keep verify_jwt:false and in-function authorization.
- Compact summaries, QA, manifests, provenance and product lifecycle belong in Postgres. Dense grids and larger path payloads belong in a separate private derived-artifact Storage bucket with deliberate MIME/size restrictions.
- A single shared product family should include product kind, algorithm/output schema version, authoritative property/boundary identity, complete source manifest signature, other deterministic input signature, evidence class/limitations, summary and immutable artifact metadata including checksum/size/format.
- Separate immutable identity and healthy completed artifact from rebuild attempts. Preserve the last artifact on failure, but return it only with explicit stale/incompatible status and consumer rules. Never overwrite a healthy artifact with partial bytes.
- Source manifests need dataset/version/item/acquisition and retrieval metadata, units/CRS, request parameters/mosaic rule and provider revision/checksum where available. If upstream revision is unresolved, say so and require revalidation policy; a phase label or URL is not an exact snapshot.
- First terrain compute should use a bounded development/import worker using extracted pure existing algorithms. Five network calls and contour work are modest, but there is no measured synchronous Edge budget yet. Retrieval should not require waiting on raw source processing.
- LiDAR needs a background/local import worker, pinned COPC/LAZ tooling and explicit per-asset coverage. Do not move it into synchronous Edge requests.
- Leaf-off requires a separate maturity/identity decision after terrain and current LiDAR. Preserve experimental status if later materialized.

Existing queue infrastructure was inspected: document_evidence_jobs uses SKIP LOCKED, leases, attempts, max_attempts and next_attempt_at, with scoped rule-pack claim lanes; site-access queues are purpose-specific. job_resolution_queue is a domain resolution surface, not a generic processing queue. Do not send raster work through document-research completion semantics or site-access buffer constraints. Reuse the established lease/retry pattern or a compatible worker entrypoint after deeper integration review; no new queue service/framework is justified by this audit. A bounded manual importer is sufficient to prove first-product persistence and retrieval.

## Migration order and release evidence

1. Define shared identity/lifecycle/artifact contract using these findings. Specify missing/queued/processing/available/stale/failed states, retryability, lease ownership/fencing, attempt limits and artifact validation.
2. Terrain only: extract compute without altering algorithm; address stated-acre input identity; record source manifest; persist one complete product; add authorized retrieval and optional IndexedDB L2 keyed by server materialization identity/checksum.
3. Verify cold client with IndexedDB absent/disabled: same central artifact, zero DEM sampling or derivation, expected contour/flow/anatomy output. Test denial for unauthenticated/revoked users and inactive property.
4. Verify boundary, source, algorithm and other input changes; concurrent rebuild deduplication; failed upload; crash/expired lease; retry; source outage; corrupt artifact; explicit stale handling. Confirm canonical elevation and hydrology meanings unchanged.
5. Only after terrain is verified, migrate current Phase 3 physical grid and required provenance/QA. Resolve first-item selection/coverage and typed-array serialization first. Keep optional temporal comparisons independent.
6. Reassess supported leaf-off derivatives separately. Dormant residual models, blind packets and unresolved diagnostics remain excluded.
7. Remove duplicate browser compute only after replacement verification; retain explicit operational fallback only if justified and labeled. Keep useful L2 cache.

For relevant eventual database/contract changes, run the repository integrity/doctrine assertions and Supabase advisors. They were not used to claim a release in this read-only audit.

## Completion boundary

Stage 1 is complete. Stage 2 contract, schema migration, worker, retrieval API, browser changes and cold-client verification are not implemented. No product is claimed as centrally migrated. Production deployment remains a distinct action under the workspace instructions.
