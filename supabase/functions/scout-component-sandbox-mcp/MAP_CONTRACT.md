# Scout component sandbox map contract

This file is the durable guardrail for incremental map work in `scout-component-sandbox-mcp`.

## Current opportunity scope

Map work proceeds one opportunity type at a time.

The first and only active map contract is the bounded **premium exterior / PNC Tower single-site** contract:

- RPC: `public.scout_get_component_sandbox_premium_exterior_map_v1_internal()`
- contract version: `single_site_map_v1`
- opportunity type: `premium_exterior`
- exemplar: `PNC Tower`
- opportunity id: `0edb82cd-7487-4f72-a036-8faa8a40bd54`

No second opportunity type may be introduced until the PNC single-site experience is verified in ChatGPT.

## Batch 2 renderer scope

Batch 2 adds the isolated renderer implementation only. It does **not**:

- expose the map payload through the current tool result
- import the renderer from `view.ts`
- alter the visible carousel or Figma-derived card
- choose or hardcode a production basemap/tile provider
- change MCP resource CSP
- bump the View URI
- deploy a new Edge Function version

The renderer implementation is `single_site_map_renderer.ts` with pure render-model construction in `single_site_map_model.ts`.

### Renderer standards

- Map engine: `maplibre-gl` pinned to `6.9.0` from npm.
- Security floor: never use `maplibre-gl <= 6.4.0`; those versions are affected by critical attribution-sanitizer XSS advisory `GHSA-jrc7-96c5-q579` / `CVE-2026-85061`. The upstream fix begins at `6.4.1`; Scout currently pins the newer `6.9.0` release.
- MapLibre JavaScript and `maplibre-gl/dist/maplibre-gl.css` are bundled locally by the application build; no CDN runtime script or stylesheet is allowed.
- A future integration must pass an approved `style` into the renderer. Provider selection and the corresponding `_meta.ui.csp` origins are an integration concern, not a renderer default.
- The map is created with `interactive: false` so carousel gestures cannot be captured by map pan/zoom in the initial single-site experience.
- The renderer visualizes the reconciled building footprint only. The Census address geocode remains provenance/context and is deliberately **not** rendered as a competing point marker because Scout records that the geocode is not itself building identity.
- Framing uses the contract's exact footprint bounds via `fitBounds`, default padding `24`, default `maxZoom` `19`, and animation duration `0` for deterministic embedded rendering.
- Provider attribution remains enabled.
- Resize tracking remains enabled so MapLibre can react to host/container changes.
- Teardown must call `map.remove()` exactly through the renderer handle; no orphan WebGL/map instance may survive host teardown or a future carousel remount.
- Footprint styling reuses existing Scout card greens (`#4d6b52` fill and `#263128` outline) rather than creating a new map-specific visual system.

No clustering, grouping, portfolios, territories, contacts, competitors, heatmaps, route planning, markers, popups, map controls, 3D extrusion, or opportunity overlays are allowed in this phase.

## Allowed payload

The single-site map contract is intentionally narrow:

- opportunity id, name, and address
- one geocoded site point
- one reconciled building footprint polygon
- exact footprint bounds
- footprint area already resolved by Scout
- geometry-source provenance
- building-link provenance and guardrail

It must not grow portfolio members, clusters, territories, contacts, competitors, heatmaps, route planning, or unrelated opportunity overlays during the PNC single-site phase.

## Geometry provenance

The PNC site point comes from the premium-exterior target record and is documented as a `US Census exact address match`.

The footprint comes from `ky-ornl-building-footprints` / `Kentucky ORNL / FEMA USA Structures Building Footprints` and is linked to PNC Tower through Scout's existing reconciled building evidence.

Important source caveats are part of the contract rather than hidden:

- footprint source image date: `2011-07-06`
- source validation method: `Unverified`
- Scout building-link status: `reconciled_existing_evidence`
- Scout link guardrail: `Facility geocode is not itself building identity; link selected by corroborating physical evidence.`
- current target-point-to-footprint distance: approximately `24.2 m`

A renderer may use the polygon as Scout's reconciled mapping geometry, but it must not describe it as a current survey, authoritative parcel boundary, or independently verified facade outline.

## Legacy map quarantine

The prior generalized map iteration remains useful as an algorithm/reference archive, but its old runtime contracts are not active inputs to the current sandbox.

These RPCs are **legacy reference only** and have `service_role` execution revoked:

- `public.scout_get_component_sandbox_map_targets_internal(integer, integer)`
- `public.scout_get_component_sandbox_map_targets_v2_internal(integer, integer)`
- `public.scout_get_component_sandbox_map_targets_v3_internal(integer, integer)`

Do not grant them back to the current sandbox or call them from the component server, Scout connect gateway, or contract gateway without an explicit owner decision to revive a specific capability.

Old `component_v*` map renderers may be inspected for proven geometry/framing/collision algorithms only. Do not import those files wholesale into the current View.

## MCP Apps standards lock

Before each implementation batch, check current MCP Apps behavior through Context7.

The current implementation must remain standards-based:

- `@modelcontextprotocol/ext-apps`
- one `App`
- one `PostMessageTransport`
- handlers registered before `connect()`
- tool result data read from `result.structuredContent`
- `_meta.ui.resourceUri` for the tool/View association
- standard `_meta.ui.csp` when map resources require external origins
- `app.getHostContext()` / `onhostcontextchanged` for host context if needed
- `app.requestDisplayMode()` only when supported by `availableDisplayModes`

The following deprecated/host-specific patterns must not re-enter the current sandbox/map path:

- `window.openai`
- raw `window.message` lifecycle plumbing
- `openai/outputTemplate`
- `openai/widgetAccessible`
- `openai/widgetDescription`
- `openai/widgetCSP`
- other OpenAI-specific resource/tool metadata used by the prior map iteration

## Next integration boundary

A later batch may expose `single_site_map_v1` through the sandbox result and replace exactly one approved media placeholder with the PNC map. That integration must preserve the full-width carousel contract and must define an approved basemap provider plus modern `_meta.ui.csp` origins before deployment.
