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

A renderer may use the polygon as Scout's reconciled mapping geometry, but it must not describe it as a current survey, authoritative parcel boundary, or independently verified facade outline.

## Renderer direction

The MapLibre v13 experiment is a **known host-incompatible experiment**, not the target architecture. It reached the View but stalled at `Loading site map…` inside ChatGPT. Context7 documentation confirms MapLibre uses Web Workers and requires `worker-src`, while the current MCP Apps resource CSP contract does not expose a worker-src control.

The approved replacement is the previously proven lightweight raster-tile rendering technique recovered from Git history:

- calculate Web Mercator coordinates in ordinary application code
- choose zoom from the bounded target geometry
- load 256x256 raster tiles as ordinary `<img>` elements
- position tiles in the existing carousel viewport
- render only the bounded Scout overlay needed for the current opportunity
- keep the map non-interactive so carousel swipe remains host-friendly
- no WebGL
- no Web Worker
- no custom SVG basemap
- no third-party map runtime library

Only the rendering algorithm may be recovered from prior iterations. Deprecated host-specific MCP plumbing from those iterations must not return.

The external raster tile provider is a separate provider/CSP decision. Do not assume that a prior provider remains approved merely because the rendering algorithm is reused.

## Dead-code policy

Git history is the reference archive. Do **not** retain retired runtime code, RPCs, compatibility shims, branches of rendering logic, or dependencies solely as archaeological reference in the active product tree/database.

The following generalized sandbox map RPCs were removed from the database and must not be recreated unless a future capability explicitly requires a newly reviewed contract:

- `public.scout_get_component_sandbox_map_targets_internal(integer, integer)`
- `public.scout_get_component_sandbox_map_targets_v2_internal(integer, integer)`
- `public.scout_get_component_sandbox_map_targets_v3_internal(integer, integer)`

The temporary local-scene/context RPC created during the workerless-SVG investigation was also removed and is not part of Scout architecture.

Old `component_v*` renderers are Git-history archaeology only. Do not restore those files to the current source tree for reference.

When the raster renderer replaces the live MapLibre experiment, the same change must remove all newly-unused MapLibre artifacts, including:

- `maplibre-gl` package dependency and lockfile entries
- obsolete MapLibre renderer module/tests
- OpenFreeMap style constants and map-specific CSP domains if no longer required
- generated bundle content produced solely by MapLibre

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

The next map change is a host-fix only:

1. replace the MapLibre renderer with the proven raster-tile technique;
2. preserve the existing `single_site_map_v1` PNC payload and Figma-derived card;
3. remove all MapLibre/OpenFreeMap artifacts made unused by that replacement;
4. bump the View URI only because the rendered resource changes;
5. verify the resulting PNC map on mobile and desktop inside ChatGPT;
6. do not add a second opportunity type until that verification passes.
