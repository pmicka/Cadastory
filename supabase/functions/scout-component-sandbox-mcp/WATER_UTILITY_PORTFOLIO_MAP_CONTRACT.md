# Water-utility portfolio sandbox map contract

This companion contract is subordinate to `MAP_CONTRACT.md` and narrows the first bounded portfolio-map exemplar without changing the existing single-site contracts.

## Warren County Water District exemplar

- Resource: `ui://scout/component-sandbox/v28`
- Opportunity type: `water_utility_portfolio`
- Map contract: `water_utility_portfolio_map_v1`
- RPC: `public.scout_get_component_sandbox_water_portfolio_v1_internal()`
- Account: `Warren County Water District`
- PWSID: `KY1140487`
- Source: `ky-kia-water-tanks`
- Relationship: `system_membership`
- Scope: `documented_roster`

The map is a documented asset-portfolio projection. It is not a Warren County boundary, utility service territory, ownership polygon, market territory, or inferred service radius. The viewport is fit only to the documented tank points returned by the bounded RPC.

The initial roster contains 24 documented WRIS tank records. `BRIGGS HILL TANK (NOT IN SERVICE)` and `OAKLAND TANK (NOT IN SERVICE)` are rendered with their documented not-in-service state and must not be promoted as active targets. `MIZPAH` and `PLEASANT HILL TANK` carry historical rehab-record signals; those signals remain historical and do not establish current work, procurement, or service need. All other current service states remain unverified.

`source_modified_at` represents the newest source modification timestamp among the bounded member records. `generated_at` represents projection time only and must never be presented as evidence freshness.

## Rendering contract

The portfolio map uses the same workerless embedded-raster strategy already proven for the single-site sandbox maps. It:

- computes bounds from resolved member points only;
- chooses a bounded fit-to-bounds Web Mercator frame;
- renders 24 flat 2D asset markers for the current exemplar;
- colors markers by documented WRIS tank form only: `ELEVATED` → elevated, `GROUND STORAGE` → ground storage, `STANDPIPE` → standpipe, and `OTHER` + `FLUTED COLUMN` → fluted column; unknown or unsupported source values remain explicitly unclassified;
- uses marker fill for morphology, a ring for historical rehab evidence, and a slash for documented not-in-service status so evidence dimensions do not compete for the same color channel;
- preserves documented not-in-service and historical-rehab distinctions without inferring current need;
- uses no WebGL, MapLibre, worker, service-radius polygon, county polygon, property polygon, or ownership polygon;
- remains non-interactive inside the approved existing card/map slot;
- keeps the card identity and map identity tied to the same account and PWSID.

The canonical 456×210 Warren frame uses render zoom 9 and six raster tiles. The overall embedded-raster budget is 32 tiles across the four bounded sandbox exemplars.

## Evidence guardrail

This surface is for account-level investigation. Before outreach or selecting an individual asset, Scout must still verify current tank service state, maintenance ownership, procurement route, current need, access, and applicable operator constraints. Portfolio membership is not proof of an active opportunity.

## Owner-approved marker refinement — 2026-09-14

The owner approved flat 2D portfolio markers and morphology color-coding for the Warren County exemplar. Morphology is source-derived from Kentucky WRIS `TYPE` / `OTHTYPE`; it is not inferred from map imagery. The compact legend remains inside the existing map media slot and does not add a new card section.
