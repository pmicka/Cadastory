## Temporary owner approval — 2026-09-13

For one SWPPP host reproduction only, the owner approved a collapsed “Show map diagnostics” control below the existing card. It contains categorical, bounded diagnostics and is visible only for SWPPP results. The existing card, map, carousel, and action controls are unchanged. This is an explicit temporary exception to the prohibition on visible lifecycle diagnostics; remove after reproduction as described in MAP_CONTRACT.md.

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

Approved incrementally on 2026-09-12:

- Scout map work proceeds one opportunity type at a time.
- The first host-verified map experience is the bounded PNC Tower `premium_exterior` single-site map defined in `MAP_CONTRACT.md`.
- The second approved map experience is the bounded SOUTH PRESSURE ZONE TANK `water_tank` single-site map defined in `MAP_CONTRACT.md`.
- The third approved pre-host-verification experience is the bounded HAM–Brent Spence Project `swppp_site` permit-location point map defined in `MAP_CONTRACT.md`.
- The fourth approved experience is the bounded Warren County Water District `water_utility_portfolio` documented tank-roster map defined in `WATER_UTILITY_PORTFOLIO_MAP_CONTRACT.md`.
- One sandbox tool result represents exactly one selected opportunity type. The card and map must always describe the same opportunity; never mix a water-tank map into the PNC card or vice versa.
- The sandbox preview tool may select `premium_exterior`, `water_tank`, `swppp_site`, or `water_utility_portfolio`; omitting the selector preserves the PNC premium-exterior compatibility default.
- Map implementation builds on the existing media carousel rather than redesigning the card.
- Exactly one existing media tile is the selected opportunity's map; the other two remain placeholders.
- The initial map tile remains non-interactive so map gestures do not compete with carousel swipe.
- The Warren County documented asset portfolio is explicitly approved. Generalized clustering, inferred service territory, heatmap, market territory, or route-planning semantics remain unapproved.
- Both approved map types use the proven raster-tile technique from the prior working map iteration, ported into the current MCP Apps lifecycle.
- The raster basemap is composed from ordinary image tiles; no MapLibre, WebGL, Web Worker, or custom SVG basemap is part of the approved design path.

## Approved real-data substitutions

The existing placeholder/card copy may be replaced only by fields already present in the bounded selected-opportunity contract.

For `premium_exterior`, approved fields are:

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

For `water_tank`, approved fields are:

- tank name
- water-system name in the existing subtitle/address line
- explicit `REHAB` maintenance signal status
- engineering-document morphology confidence
- linked project source-modified date
- elevated tank type
- capacity
- morphology class
- single-pedestal support geometry
- favorable operator geometry assessment
- linked project purpose
- project guardrail stating that the signal is not proof of active procurement

The approved PNC map consumes only the bounded `single_site_map_v1` payload. The approved water-tank map consumes only the bounded `water_tank_single_site_map_v1` payload. The SWPPP map consumes only `swppp_site_map_v1` and preserves its authoritative point semantics; documented permit acreage is not a displayed boundary. Do not fabricate freshness, evidence counts, images, contacts, active procurement status, buyer intent, current need, access conditions, tank dimensions, ownership or disturbance boundaries, or action state.

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
- maps beyond the bounded approved exemplars described above without separate owner approval
- multiple opportunity maps in one card
- portfolio semantics beyond the approved Warren County documented-roster exemplar, or generalized clustering, heatmap, inferred territory, or route-planning semantics
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

## Owner-approved Warren portfolio marker refinement — 2026-09-14

Within the existing map media tile, the Warren County portfolio uses flat 2D circular markers with no drop shadow. Fill color encodes documented WRIS tank form; historical rehab and documented not-in-service states use non-color ring/hollow marker cues. A compact in-map legend is approved because the color encoding would otherwise be ambiguous. This does not authorize a new card section or generalized portfolio-map redesign.


## Municipal facilities portfolio extension (owner-approved 2026-09-15)

`municipal_facilities_portfolio` is approved as the next bounded portfolio map. Its first exemplar is Louisville Metro Government. The implementation must preserve the existing card geometry and three-slide carousel; exactly one slide remains the map. Municipal location membership, geometry evidence, ownership/maintenance responsibility, and member-specific opportunity signals are separate claims and must never be collapsed into one another.

## Telecom-change single-site extension (owner-approved 2026-09-16)

`telecom_change` is approved as the next bounded single-site opportunity family. Its first exemplar is FCC ASR registration 1333510 / The Towers, LLC near Leavenworth, Indiana. The existing card geometry and three-slide carousel remain unchanged; exactly one slide is the non-interactive FCC registration-point map. Raw FCC codes may be displayed as codes but must not be silently decoded without authoritative support.
