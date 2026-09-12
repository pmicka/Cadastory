# Scout component sandbox map contract

This file is the durable guardrail for incremental map work in `scout-component-sandbox-mcp`.

## Current opportunity scope

Map work proceeds one opportunity type at a time.

The first active and host-verified map contract is the bounded **premium exterior / PNC Tower single-site** contract:

- RPC: `public.scout_get_component_sandbox_premium_exterior_map_v1_internal()`
- contract version: `single_site_map_v1`
- opportunity type: `premium_exterior`
- exemplar: `PNC Tower`
- opportunity id: `0edb82cd-7487-4f72-a036-8faa8a40bd54`

The second opportunity type is now staged through an **isolated point-renderer batch**. It is still not exposed through `ScoutSandboxResult`, the tool output schema, the View, or the carousel:

- RPC: `public.scout_get_component_sandbox_water_tank_map_v1_internal()`
- contract version: `water_tank_single_site_map_v1`
- opportunity type: `water_tank`
- exemplar: `SOUTH PRESSURE ZONE TANK`
- water system: `BOWLING GREEN MUNICIPAL UTILITIES`
- stable WRIS FID: `00AB7B0C8D56F05717FDFCF0B4000001`
- PWSID: `KY1140038`

No third opportunity type may be introduced until the water-tank single-site path has been integrated and host-verified.

## Premium-exterior allowed payload

The premium-exterior single-site map contract is intentionally narrow:

- opportunity id, name, and address
- one geocoded site point for provenance/context
- one reconciled building footprint polygon
- exact footprint bounds
- footprint area already resolved by Scout
- geometry-source provenance
- building-link provenance and guardrail

It must not grow portfolio members, clusters, territories, contacts, competitors, heatmaps, route planning, or unrelated opportunity overlays.

The Census/address geocode is not building identity and must not be rendered as a competing target marker.

## Premium-exterior geometry provenance

The PNC site point comes from the premium-exterior target record and is documented as a US Census exact-address match.

The footprint comes from `ky-ornl-building-footprints` / Kentucky ORNL / FEMA USA Structures Building Footprints and is linked to PNC Tower through Scout's reconciled building evidence.

Important caveats remain explicit:

- footprint source image date: `2011-07-06`
- source validation method: `Unverified`
- Scout building-link status: `reconciled_existing_evidence`
- Scout link guardrail: `Facility geocode is not itself building identity; link selected by corroborating physical evidence.`
- current target-point-to-footprint distance: approximately `24.2 m`

The current renderer uses the reconciled footprint bounds to frame the map and places the Scout marker at the footprint-bounds center. It does **not** render the Census/address geocode as the target marker. The marker is a locator for the reconciled building geometry, not a claim that the footprint is a current survey, authoritative parcel boundary, or independently verified facade outline.

## Water-tank bounded data contract

The staged water-tank contract is point-based. It must not invent a footprint, tank diameter, service radius, property boundary, access area, or other polygon.

The allowed payload is limited to:

- one WRIS water-tank point and its primary-source provenance
- stable asset identifiers (`wris_fid`, `pwsid`, tank id/candidate key)
- tank name, system name, type, capacity, known maintenance dates, and out-of-service state
- evidence-backed morphology/support geometry
- geometry evidence kind/confidence/source and the no-media-retention state
- the trusted-operator cleaning-geometry assessment, clearly separated from the structural evidence
- one recent linked `REHAB` project record with match method/distance and source-modified timestamp
- explicit guardrails that the project is a maintenance signal, not proof of an active cleaning procurement opportunity

The initial exemplar is `SOUTH PRESSURE ZONE TANK`, selected because it is inside the supported Louisville radius, has a January 2026 `REHAB / TANK IMPROVEMENTS` record, and has a 0.995-confidence engineering-document classification as `composite_elevated` with `single_pedestal` support and no cross-bracing.

The contract deliberately does **not** copy the broader candidate view's `time_sensitive` field. Timing must remain grounded in the project evidence and be verified before outreach.

## Water-tank Batch 2 isolated renderer boundary

Batch 2 adds only a pure point-map model and raster-frame calculation. It does not mount a water-tank map in the View.

The water-tank renderer:

- centers on the exact normalized WRIS asset point
- places the Scout marker on that same exact WRIS point
- uses render-only zoom `17` for the initial single-point framing
- ports the same proven Web Mercator/tile calculation into an isolated pure point-renderer module rather than introducing a second map runtime
- loads no tiles by itself during model/frame tests; it only calculates the bounded tile set required for a supplied viewport
- keeps the model point-only and does not synthesize or persist any domain geometry

The fixed zoom is a presentation choice only. It does not define a service radius, ownership boundary, parcel extent, access envelope, tank diameter, inspection perimeter, or any other real-world spatial claim.

The working PNC `single_site_map_renderer.ts` is deliberately restored to the exact `main` blob for Batch 2. A fresh View build must therefore leave `view.generated.ts` byte-for-byte unchanged. The small duplicated Web Mercator/tile framing kernel in the isolated water-tank module is intentional at this stage: sharing/refactoring the active PNC runtime is deferred until a later integration batch where a View revision is already intentional and can be host-regression-tested.

Batch 2 must remain isolated:

- `ScoutSandboxResult` keeps the existing PNC `map` field only
- the component server must not call `scout_get_component_sandbox_water_tank_map_v1_internal()` yet
- `view.ts` must not import the water-tank model/renderer yet
- the carousel must not receive a water-tank map tile yet
- the generated View must not contain the water-tank contract/model/renderer
- no resource URI bump is required because no host-visible View behavior changes
- no Edge Function deployment occurs in this batch

## Proven raster-tile renderer

The active renderer is the lightweight raster-tile technique recovered from the previously working Scout map implementation and ported into the current MCP Apps lifecycle.

It must:

- calculate Web Mercator coordinates in ordinary application code
- choose zoom from bounded target geometry/point framing appropriate to the active opportunity type
- load only the raster tiles required for the current viewport as ordinary 256x256 `<img>` elements
- position those tiles in the existing carousel viewport
- remain non-interactive so carousel swipe is not captured by map pan/zoom
- recalculate framing on actual host/container size changes through the renderer handle
- preserve the currently active carousel slide across host/container resize
- avoid refetching/rebuilding the same raster frame when the rendered width and height have not changed
- expose visible provider attribution
- provide deterministic teardown by clearing renderer DOM/timers and disconnecting View-side resize observers/listeners
- use no WebGL
- use no Web Worker
- use no custom SVG basemap
- use no third-party map runtime library

Only the rendering algorithm was recovered from Git history. Deprecated host-specific MCP plumbing from prior iterations must not return.

## Raster provider and MCP CSP

For the bounded owner-only sandbox preview, the raster provider is the OpenStreetMap standard tile service:

- tile template: `https://tile.openstreetmap.org/{z}/{x}/{y}.png`
- MCP Apps CSP: `resourceDomains: ["https://tile.openstreetmap.org"]`
- no `connectDomains` entry is required because the View loads tiles as image resources rather than fetch/XHR/WebSocket traffic
- every tile `<img>` sets `referrerPolicy = "origin"`
- the View declares `<meta name="referrer" content="origin">`
- the renderer does not prefetch adjacent zoom levels or bulk areas; it requests only tiles intersecting the current viewport
- browser caching is left enabled; Scout does not add no-cache headers to tile requests
- visible attribution is `© OpenStreetMap contributors`

The OSM standard tile service is best-effort and not an SLA-backed production dependency. If Scout later needs sustained commercial map traffic, provider selection must be revisited without changing the renderer contract unnecessarily.

## Host verification state

- mobile ChatGPT host: **verified working** — Android v15 rendered the hardened PNC premium-exterior raster map successfully in the existing carousel on 2026-09-12.
- desktop ChatGPT host: still requires explicit visual verification before the PNC pattern is considered verified there.
- the water-tank contract/renderer is not yet exposed to the host and therefore has no host-render verification state.

The earlier transient v14 `Site map unavailable` state resolved after an app refresh and is not treated as a renderer-architecture failure.

## Dead-code policy

Git history is the reference archive. Do **not** retain retired runtime code, RPCs, compatibility shims, branches of rendering logic, or dependencies solely as archaeological reference in the active product tree/database.

The following generalized sandbox map RPCs were removed from the database and must not be recreated unless a future capability explicitly requires a newly reviewed contract:

- `public.scout_get_component_sandbox_map_targets_internal(integer, integer)`
- `public.scout_get_component_sandbox_map_targets_v2_internal(integer, integer)`
- `public.scout_get_component_sandbox_map_targets_v3_internal(integer, integer)`

The temporary local-scene/context RPC created during the workerless-SVG investigation was also removed and is not part of Scout architecture.

Old `component_v*` renderers are Git-history archaeology only. Do not restore those files to the current source tree for reference.

The superseded MapLibre experiment must leave no active artifacts: no `maplibre-gl` dependency/lockfile entries, no MapLibre model module, no OpenFreeMap style constant/CSP origin, no MapLibre CSS build path, and no generated MapLibre bundle content.

Negative regression assertions may name retired APIs/RPCs in order to prevent reintroduction; that is not considered vestigial runtime code.

## MCP Apps standards lock

Before each implementation batch, check current MCP Apps behavior through Context7.

The current implementation must remain standards-based:

- `@modelcontextprotocol/ext-apps`
- one `App`
- one `PostMessageTransport`
- handlers registered before `connect()`
- tool result data read from `result.structuredContent`
- `_meta.ui.resourceUri` for the tool/View association
- standard `_meta.ui.csp` only for origins actually required by the View
- `app.getHostContext()` / `onhostcontextchanged` for host context if needed
- `app.requestDisplayMode()` only when supported by `availableDisplayModes`

The following deprecated/host-specific patterns must not re-enter the current sandbox/map path:

- `window.openai`
- raw `window.message` lifecycle plumbing
- `openai/outputTemplate`
- `openai/widgetAccessible`
- `openai/widgetDescription`
- `openai/widgetCSP`
- other OpenAI-specific resource/tool metadata used by prior map iterations
