# Scout component sandbox map contract

This file is the durable guardrail for incremental map work in `scout-component-sandbox-mcp`.

## Current batch scope

Map work proceeds one opportunity type at a time.

The first and only active map contract is the bounded **premium exterior / PNC Tower single-site** contract:

- RPC: `public.scout_get_component_sandbox_premium_exterior_map_v1_internal()`
- contract version: `single_site_map_v1`
- opportunity type: `premium_exterior`
- exemplar: `PNC Tower`
- opportunity id: `0edb82cd-7487-4f72-a036-8faa8a40bd54`

Batch 1 defines data and guardrails only. It does **not** add a visible map, change the carousel, bump the View URI, or deploy a renderer.

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

The following deprecated/host-specific patterns must not re-enter the current path:

- `window.openai`
- raw `window.message` lifecycle plumbing
- `openai/outputTemplate`
- `openai/widgetAccessible`
- `openai/widgetDescription`
- `openai/widgetCSP`
- other OpenAI-specific resource/tool metadata used by the prior map iteration

## Renderer boundary

A future renderer batch may consume `single_site_map_v1`, but Batch 1 does not expose the map payload through the existing tool result and does not alter the visible Figma-derived card.

When a renderer is added, it must start with one PNC site only: no clustering, no grouping, no portfolio semantics, and no second opportunity type until the PNC experience is verified in ChatGPT.
