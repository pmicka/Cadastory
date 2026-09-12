# Scout component sandbox design contract

This file is the durable UI guardrail for `scout-component-sandbox-mcp`.

## Canonical design source

- Figma file: `SRyiFBNfEGIAPHmc9jeG52`
- Page: `12:2` — `AI Client Sandbox`
- Frame: `12:3` — `Scout AI Client — Component Sandbox`
- Card: `12:7` — `Scout / AI response card`
- Reference URL: `https://www.figma.com/design/SRyiFBNfEGIAPHmc9jeG52?node-id=12-2`

The Figma card is the visual source of truth. Do not redesign the sandbox from memory or replace it with a new card system unless the owner explicitly changes the design direction.

## Required visible structure

The live MCP Apps View should preserve the card's existing visual hierarchy:

1. White card surface, 24px radius, subtle green-gray border and shadow.
2. Scout identity row: green dot, `Scout`, `Component preview`, circular ellipsis control.
3. Divider.
4. Opportunity title.
5. Status pill plus compact metadata line.
6. `Media` label and the existing horizontally swipeable carousel treatment.
7. Carousel count/dots.
8. One compact factual summary region. Approved Scout guardrail copy may extend this region as muted supporting text; it must not become a separate boxed redesign.
9. Divider.
10. `Save for later` and `Investigate` controls in the existing Figma geometry. Until their behaviors are explicitly wired, they remain visually present but inert.

## Owner-approved carousel refinement

Approved 2026-09-11 from the live mobile review:

- Every media tile must occupy exactly 100% of the visible carousel viewport width.
- Adjacent tiles must not intentionally peek into the viewport.
- Horizontal swipe, mandatory snap, carousel count, and dots remain intact.
- Tile-internal placeholder content remains centered responsively inside the full-width tile.

This refinement intentionally supersedes the narrower 330px tile geometry in the original Figma frame. Do not revert to a fixed 330px tile or reintroduce an adjacent-tile preview unless the owner explicitly changes direction again.

## Owner-approved map direction

Approved 2026-09-12:

- Scout map work proceeds incrementally, one opportunity type at a time.
- The first map experience is the bounded PNC Tower `premium_exterior` single-site map defined in `MAP_CONTRACT.md`.
- Map implementation builds on the existing media carousel rather than redesigning the card.
- Exactly one existing media tile is the PNC map; the other two remain placeholders.
- The initial map tile is non-interactive so map gestures do not compete with carousel swipe.
- No portfolio/clustering/territory map semantics are approved by this design decision.
- The renderer uses the proven raster-tile technique from the prior working map iteration, ported into the current MCP Apps lifecycle.
- The raster basemap is composed from ordinary image tiles; no MapLibre, WebGL, Web Worker, or custom SVG basemap is part of the approved design path.

## Approved real-data substitutions

The existing placeholder copy may be replaced only by fields already present in the bounded sandbox opportunity contract:

- opportunity name
- opportunity tier
- score
- confidence
- address
- target class/subclass
- glazing status
- stories
- resolved height
- footprint
- observation date
- buyer/site-route classification
- Scout guardrail

The approved PNC map consumes only the bounded `single_site_map_v1` payload defined in `MAP_CONTRACT.md`. Do not fabricate freshness, evidence counts, images, contacts, active procurement status, current need, or action state.

## Forbidden divergence

Unless the owner explicitly changes direction, the sandbox View must not introduce:

- a metric-tile grid
- a separate details table/list
- a boxed guardrail panel
- a replacement dark-theme card design
- an all-caps `Scout by Cadastory` eyebrow in place of the Figma Scout header
- standalone-app chrome or dashboard scaffolding
- lifecycle diagnostics in the visible UI
- images, contacts, `.vcf`, or persistent Save/Investigate behavior before those are separately approved
- maps beyond the bounded PNC single-site direction described above
- `window.openai`, raw `window.message` lifecycle plumbing, `openai/outputTemplate`, or host-specific lifecycle APIs

## Lifecycle invariant

Keep the current standards-based MCP Apps lifecycle:

- `@modelcontextprotocol/ext-apps`
- one `App`
- one `PostMessageTransport`
- all lifecycle handlers registered before `connect()`
- result data read from `result.structuredContent`
- `_meta.ui.resourceUri`
- current MCP Apps MIME

The generated View must continue to have exactly one `<!doctype html>`, contain no `window.openai`, and use `build-view.mjs` only to bundle the standards-based JavaScript into the approved HTML template. The MapLibre-only CSS bundle path is retired and must not be restored unless an explicitly approved future implementation requires a separate generated stylesheet.
