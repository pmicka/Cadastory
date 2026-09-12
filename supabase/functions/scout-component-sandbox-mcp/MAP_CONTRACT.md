# Scout component sandbox map contract

This file is the durable guardrail for incremental map work in `scout-component-sandbox-mcp`.

## Current opportunity scope

Map work proceeds one opportunity type at a time.

The first and only active map data contract is the bounded **premium exterior / PNC Tower single-site** contract:

- RPC: `public.scout_get_component_sandbox_premium_exterior_map_v1_internal()`
- contract version: `single_site_map_v1`
- opportunity type: `premium_exterior`
- exemplar: `PNC Tower`
- opportunity id: `0edb82cd-7487-4f72-a036-8faa8a40bd54`

No second opportunity type may be introduced until the PNC single-site map is verified in ChatGPT.

## Allowed payload

The single-site map contract is intentionally narrow:

- opportunity id, name, and address
- one geocoded site point for provenance/context
- one reconciled building footprint polygon
- exact footprint bounds
- footprint area already resolved by Scout
- geometry-source provenance
- building-link provenance and guardrail

It must not grow portfolio members, clusters, territories, contacts, competitors, heatmaps, route planning, or unrelated opportunity overlays during the PNC single-site phase.

The Census/address geocode is not building identity and must not be rendered as a competing target marker.

## Geometry provenance

The PNC site point comes from the premium-exterior target record and is documented as a US Census exact-address match.

The footprint comes from `ky-ornl-building-footprints` / Kentucky ORNL / FEMA USA Structures Building Footprints and is linked to PNC Tower through Scout's reconciled building evidence.

Important caveats remain explicit:

- footprint source image date: `2011-07-06`
- source validation method: `Unverified`
- Scout building-link status: `reconciled_existing_evidence`
- Scout link guardrail: `Facility geocode is not itself building identity; link selected by corroborating physical evidence.`
- current target-point-to-footprint distance: approximately `24.2 m`

The current renderer uses the reconciled footprint bounds to frame the map and places the Scout marker at the footprint-bounds center. It does **not** render the Census/address geocode as the target marker. The marker is a locator for the reconciled building geometry, not a claim that the footprint is a current survey, authoritative parcel boundary, or independently verified facade outline.

## Proven raster-tile renderer

The active renderer is the lightweight raster-tile technique recovered from the previously working Scout map implementation and ported into the current MCP Apps lifecycle.

It must:

- calculate Web Mercator coordinates in ordinary application code
- choose zoom from the bounded reconciled footprint geometry
- load only the raster tiles required for the current viewport as ordinary 256x256 `<img>` elements
- position those tiles in the existing carousel viewport
- place only the bounded PNC Scout marker required for this single-site phase
- remain non-interactive so carousel swipe is not captured by map pan/zoom
- recalculate framing on host/window resize through the renderer handle
- expose visible provider attribution
- provide deterministic teardown by clearing the renderer DOM and timers
- use no WebGL
- use no Web Worker
- use no custom SVG basemap
- use no third-party map runtime library

Only the rendering algorithm was recovered from Git history. Deprecated host-specific MCP plumbing from prior iterations must not return.

## Raster provider and MCP CSP

For the bounded owner-only v14 sandbox preview, the raster provider is the OpenStreetMap standard tile service:

- tile template: `https://tile.openstreetmap.org/{z}/{x}/{y}.png`
- MCP Apps CSP: `resourceDomains: ["https://tile.openstreetmap.org"]`
- no `connectDomains` entry is required because the View loads tiles as image resources rather than fetch/XHR/WebSocket traffic
- every tile `<img>` sets `referrerPolicy = "origin"`
- the View declares `<meta name="referrer" content="origin">`
- the renderer does not prefetch adjacent zoom levels or bulk areas; it requests only tiles intersecting the current viewport
- browser caching is left enabled; Scout does not add no-cache headers to tile requests
- visible attribution is `© OpenStreetMap contributors`

The OSM standard tile service is best-effort and not an SLA-backed production dependency. If Scout later needs sustained commercial map traffic, provider selection must be revisited without changing the renderer contract unnecessarily.

## Dead-code policy

Git history is the reference archive. Do **not** retain retired runtime code, RPCs, compatibility shims, branches of rendering logic, or dependencies solely as archaeological reference in the active product tree/database.

The following generalized sandbox map RPCs were removed from the database and must not be recreated unless a future capability explicitly requires a newly reviewed contract:

- `public.scout_get_component_sandbox_map_targets_internal(integer, integer)`
- `public.scout_get_component_sandbox_map_targets_v2_internal(integer, integer)`
- `public.scout_get_component_sandbox_map_targets_v3_internal(integer, integer)`

The temporary local-scene/context RPC created during the workerless-SVG investigation was also removed and is not part of Scout architecture.

Old `component_v*` renderers are Git-history archaeology only. Do not restore those files to the current source tree for reference.

The superseded MapLibre experiment must leave no active artifacts after the raster host fix: no `maplibre-gl` dependency/lockfile entries, no MapLibre model module, no OpenFreeMap style constant/CSP origin, no MapLibre CSS build path, and no generated MapLibre bundle content.

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

## Current integration boundary

v14 is a host-fix only:

1. preserve the existing `single_site_map_v1` PNC payload and Figma-derived card;
2. replace the host-incompatible MapLibre experiment with the proven raster-tile renderer;
3. remove all MapLibre/OpenFreeMap artifacts made unused by that replacement;
4. keep the other two carousel tiles as placeholders;
5. verify the resulting PNC map on mobile and desktop inside ChatGPT;
6. do not add a second opportunity type until that verification passes.
