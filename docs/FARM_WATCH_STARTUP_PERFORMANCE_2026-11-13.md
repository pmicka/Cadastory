# Farm Watch post-OAuth performance remediation

This is an implementation and controlled regression result, **not a deployed production performance claim**. Work started from Cadastory `738593b` and notebook `1fbbe1e` on main. `Patrick-Micka/main` (`a1bb9d0`) contains no Farm Watch client; the user confirmed the frontend changes belong in `pmicka/notebook`.

## Critical path and evidence

The supplied production observations for `farm-watch-private` are 44.5 s and 28.2 s on November 13, and 16.0 s and 8.9 s on November 12, with successful responses around 1.53 MB before compression. No new authenticated production sample was collected in this workspace.

| Dependency | Previous startup | New startup |
| --- | --- | --- |
| Pinned SDK / PKCE exchange / `getSession()` | Before private-context load | Before authorized bootstrap; measured from page entry |
| `auth.getUser(token)` | Required | Required; server validated |
| Account allowlist + normalized role | Sequential | Independent RPCs in parallel; both must succeed |
| Active property lookup | Required | Required, after authorization |
| Property/capability presentation | Waits for all analysis | Bootstrap allowlist of display fields, stored geometry/center, canonical identity and capabilities |
| Roads/trails and operator observations | Sequential, before full response | Independent map group; two RPCs in parallel |
| Soils / deep soils / hydrology | Read + conditional synchronous refresh | Parallel ordinary reads in requested physical group; explicit stale states |
| Landscape domain/context | Conditional regeneration in full response | Read only; current domain and hydrology gates remain required |
| Deer context / tomorrow solar timing | Full-response prerequisites | Requested deer group; same deterministic timing and evaluator assembly |
| Authoritative external sources | All eight provider slots before full response | Still all required slots before deer evidence freshness; timed per provider |
| Materialization / terrain | Private-context event starts many consumers | Selected contours/flow load independently of reference fetch completion; central artifact/checksum validation retained |
| LiDAR / structural products / QA | Eager module loading and initialization | Technical-only module group on relevant section/layer demand; explicit expensive QA actions retained |
| Imagery | Map plus eager coverage discovery and duplicate imagery render | Immediate selected image; bounded local-history discovery when opened; no redundant unchanged image render |
| Land / environment / regulatory | Private-context broadcast starts requests | Existing endpoints, independently requested; hunting also requests its regulatory dependency |
| Guided home / manuals | Most routes initialize map and data | Bootstrap only until a map/analytical section is opened |

The old auth listener was installed after the awaited initial load. Every subsequent `SIGNED_IN` also started the full load. The new controller subscribes before restoring the session, defers work outside the SDK callback, deduplicates by session/account, updates refreshed tokens without restarting, and uses aborts plus generation checks for all protected fetches. A late initial session result cannot override a newer sign-out. Account changes and sign-out clear protected state and cached artifacts. Ordinary same-account startup retains the materialization cache and its existing server revalidation requirement.

## Smallest implementation boundary

The deployed endpoint name stays `farm-watch-private`; no database migration, new endpoint fleet, new framework, or science model is introduced.

| `context` | Response/work |
| --- | --- |
| `bootstrap` | Validated session, allowlist, role, active property; small property projection plus server capabilities. No external fetch, refresh, analytical RPC, evidence stack, evaluator or geocoder. |
| `map` | Access features and operator observations only. |
| `physical` | Ordinary soils, hydrology, domain/context reads. Independent RPC failures stay localized. Expired features are withheld; stale deep-profile fields are withheld without relabeling current soil map units. |
| `deer` | Hydrology/domain inputs needed by the existing evaluator; exact-time evidence freshness, authoritative source observations and unchanged science assembly. No access/soil payload. |
| `refresh` | Owner/admin only, enforced server-side. Reuses existing bounded soil/hydrology/domain refresh routines; returns revalidated physical reads without running deer evaluation. Triggered explicitly by the technical Refresh data control. |
| omitted / `full` | Legacy response and refresh behavior retained for compatibility. |

All modes use the existing authenticated authorization gate and property selector. Unknown roles remain denied; owner/admin remain distinct technical roles and viewer remains guided. Existing service-only SQL grants, materialization restrictions and private Storage authorization are unchanged. No new property access rules are inferred in the browser.

The handler is extracted into `handler.ts` so tests can exercise the real HTTP boundary with injected dependencies. The runtime entrypoint retains the existing environment/credential handling and pinned Supabase client.

## Freshness and maintenance

No external identity is fabricated, bypassed or persistently cached. The resolver already runs unique provider dependencies concurrently and shares its in-request LiDAR selection promise. The client now avoids repeated evidence-group requests and shares identical in-flight authenticated URLs. Timing callbacks observe provider probes without changing selection, coverage checks, identity hashes, provider timeouts or unavailable results. Protected workers' pre-claim/completion checks are untouched.

Ordinary scoped reads do not refresh data. Retention TTL and identity failures stay stale/unavailable; expired geometry is not drawn as current, and stale deep-profile measurements are not exposed as current soil attributes. Refresh requests reuse the existing implementation and retry bounds. No new scheduler or independent maintenance system was added. Existing worker/scheduling mechanisms continue unchanged; scheduling automatic soil/hydrology refresh instead of the existing on-demand refresh can be a separate narrowly scoped operations unit if required.

## Instrumentation

The frontend exposes a bounded, in-memory `FarmWatchPerformance.snapshot()` and `farm-watch:performance` events. Neither contains URLs, tokens, property values, user identities or request selectors. Measurements include:

- page/callback entry to restored session and authorized dashboard (animation-frame render boundary);
- bootstrap and individual API duration, headers wait, body read, JSON parse, decoded bytes and request count;
- browser-reported transfer/encoded bytes where Resource Timing permits them;
- map usability marker and capability hydration timing, independent of dashboard visibility.

`Server-Timing` separates session validation, every named RPC, provider identity probes, science hydration and JSON encoding. Structured server logs report only whitelisted mode, status, elapsed duration, slowest operation name/time and response bytes. Allowed browser origins receive Timing-Allow-Origin and exposed Server-Timing. Headers wait includes network and server execution; body read includes transfer/decompression. Compare Server-Timing with Resource Timing to distinguish those components rather than interpreting all fetch time as backend compute.

## Controlled measurements and checks

The notebook benchmark serves the old main archive and new client with the same cached vendor assets, synthetic authorization and property, 390×844 viewport, 1,500 ms analytical API delay and 80 ms bootstrap delay. Each role/revision ran three times. It injects a 1.53 MB legacy payload to reproduce the transfer/parse shape; it does not represent real property geometry or provider latency. Results and runnable harness are committed in notebook `docs/farm-watch-startup-browser-results.json` and `scripts/check_farm_watch_startup_browser.py`.

| Metric | Before | After |
| --- | --- | --- |
| Viewer dashboard median | 2,199 ms | 308 ms |
| Owner dashboard median | 2,240 ms | 389 ms |
| Initial decoded fixture response | ~1,530,903 B | 454–455 B |
| Viewer API requests by dashboard visibility, final run | 10 | 1 |
| Owner API requests by dashboard visibility, final run | 10 | 5 concurrent requests; only bootstrap gates visibility |
| Bootstrap API, final runs | Not separate | 92–98 ms |
| Initial owner boundary-map marker, final run | Not instrumented | 330 ms |

The map marker describes interactive Leaflet/property geometry, not proof that remote imagery/parcel tiles have arrived. These fixtures and injected latencies demonstrate separation and reduced startup work, **not** the production/mobile performance targets.

Regression coverage includes HTTP authorization/roles, minimal bootstrap dependencies/payload, independent physical failure, stale materializations, stale deep soils, authoritative provider outage, unavailable overrides reaching the canonical reader, exact-time legacy/scoped science parity, protected refresh, duplicate auth, progressive requests, retry, single-map preservation, sign-out during in-flight requests, guided/technical routes, manuals and the pinned SDK PKCE return flow. Existing science/contract tests and freshness invariant scripts remain part of the release checks.

## Deployment and production acceptance

1. Deploy the backend `farm-watch-private` function, including its handler and shared timing hook, through the existing deployment process. Preserve its current JWT/gateway settings and CORS origins. No migrations or credential changes are needed.
2. Verify authorized bootstrap, unauthorized 404, each normalized role, and scoped responses. Confirm that bootstrap logs have no scientific-source/refresh dependencies.
3. Deploy notebook through its existing static build/deployment process; publish the changed assets with the new query versions. Do not deploy the frontend from Patrick-Micka.
4. For the same accounts/property, device, network and warm-cache conditions as the baseline, capture multiple OAuth returns and warm sessions, including viewer and owner/admin. Export only aggregate timing/size/count metrics; do not export HAR tokens or private payloads.
5. Check the <2 s authorized-dashboard, preferably <500 ms bootstrap, substantially smaller real bootstrap and <3 s first usable property-map targets. Confirm science can be slow/unavailable without changing those results, and that current/stale states agree with the canonical materialization reader.
6. Keep production acceptance open until those deployed measurements are recorded. This task does not deploy either repository or claim the targets have been reached in production.

If bootstrap remains above target, use its auth/RPC timing breakdown to choose a single next change (for example combining the existing server authorization/role/property reads in a protected bootstrap RPC). If remote map tiles dominate, measure their first successful load separately before changing imagery delivery. Additional automatic maintenance should extend the existing protected scheduling/worker mechanism, not create another refresh system.
