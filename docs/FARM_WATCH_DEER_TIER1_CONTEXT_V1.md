# Farm Watch Deer Tier 1 Context v1

Status: production candidate — 2026-09-25

## Scope

This unit implements the four easiest active deer-science measurements from the 2026 operating queue without introducing deer scoring or behavioral inference:

- FW-M24 — building/development density;
- FW-M36 — road landscape context;
- FW-M39 — Nagy-Reis 1 km² / 9 km² study scales;
- FW-M45 — explicit hurricane/extreme-wind event state.

The products are neutral evidence. Their purpose is to reproduce or closely align the physical/state variables used by the cited studies so later deer modules can either consume them under the relationship registry or abstain.

## Human Footprint Context v1

Product:

- key: `human-footprint-context`
- schema: `human-footprint-context-v1`
- algorithm: `fema-usastructures-osm-human-footprint-v1`

### FW-M24 building density

Delisle et al. (2024) sampled deer activity in fixed 10.36 km² landscapes and calculated the number of buildings within each landscape.

Farm Watch therefore uses:

- an exact 10.36 km² property-centered square analytical window;
- the current FEMA USA Structures View polygon layer;
- building count;
- building density expressed as count / 10.36 km².

The property-centered window reproduces the study area size but not the original Indiana landscape placement or Microsoft building-footprint source. The current FEMA USA Structures View is used as an authoritative/open current building geometry source. The result is therefore a source-aligned derived measurement, not a recreation of the original study sample.

### FW-M36 road context

Stephens et al. (2024) represented roads from paved and unpaved road geometry, created a 10 m distance-to-road raster, and evaluated landscape covariates at 30 m, 90 m, and 270 m radii.

Farm Watch uses the current local OpenStreetMap Geofabrik access snapshot and includes only canonical `feature_class=road` features. Driveways, service roads, parking aisles, and sidewalks are excluded from the source-aligned road class.

The v1 context stores:

- property-center distance to the nearest mapped road;
- clipped road length and road-feature count inside the existing barrier-aware 500 m, 1.5 km, and 3 km Farm Watch domains;
- source snapshot timestamp;
- the source study's 30/90/270 m focal radii as an explicit downstream contract.

No positive or negative deer response to roads is assigned. A future step-selection implementation must still calculate the study-style local/focal road covariate at the evaluated location.

## Multiscale Cover Context v1

Product:

- key: `multiscale-cover-context`
- schema: `multiscale-cover-context-v1`
- algorithm: `nagy-reis-property-centered-grid-scales-v1`

Nagy-Reis et al. (2019) superimposed virtual 1.0 km² and 9.0 km² grids over aerial-survey units and evaluated habitat covariates within those grid cells.

Farm Watch creates exact-area square windows centered on the property center:

- 1.0 km², 1,000 m side;
- 9.0 km², 3,000 m side.

The squares are constructed in EPSG:32616 and persisted as geographic polygons. The North Dakota hunting-unit scale is not transferred.

These windows are reusable analytical geometry for later forest, wetland, and other source-aligned covariates. Creating the windows alone does not satisfy the separate FW-M40 escape-cover or FW-M41 residual-food measurements.

## Extreme Weather Event Context v1

Product:

- key: `extreme-weather-event-context`
- schema: `extreme-weather-event-context-v1`
- algorithm: `nws-tropical-extreme-event-gate-v1`

FW-D18 is anchored to deer response during Hurricane Irma. It must not become a generic rain, wind, thunderstorm, or weather-front rule.

The Farm Watch event gate therefore accepts only authoritative NWS events in this explicit family:

- Hurricane Warning / Watch;
- Tropical Storm Warning / Watch;
- Storm Surge Warning / Watch;
- Extreme Wind Warning.

The property boundary must intersect the alert geometry and the alert must be temporally active for the requested time.

Severe thunderstorms, ordinary rain/wind, heat, routine flood context, and generic storminess do not activate this measurement.

The validation property context refreshes every 10 minutes from the existing canonical NWS weather-event table.

## Automation

- building/development context: direct unfiltered FEMA USA Structures count over the exact 10.36 km² analytical window on the first day of each month;
- roads: reused from the centrally maintained OSM access snapshot;
- 1/9 km² analytical windows: deterministic/static until property geometry changes;
- extreme-event gate: refreshed every 10 minutes from canonical NWS alerts.

No recurring user input is required.

## Interpretation boundary

These products do not claim:

- buildings increase deer activity at Flat Creek;
- roads attract or repel deer;
- 1 km² or 9 km² is the correct scale for a Kentucky deer response;
- an ordinary severe storm produces the Hurricane Irma response;
- any published coefficient transfers to Kentucky.

Those biological decisions remain in the relationship registry and downstream Batch 10+ modules.


## Source-transport refinement — 2026-09-25

The initial production collector targeted the Kentucky DGI-hosted ORNL/FEMA building layer. Supabase Edge timed out while fetching that ArcGIS service metadata. Existing Scout building-candidate tables were not substituted because their ingestion intentionally filters the national structures source for commercial-building discovery and therefore cannot represent the all-building count required by FW-M24.

The collector was consequently moved to the registered current `fema-usa-structures-current` source (`FEMA USA Structures View`) and queries that source directly with `returnCountOnly=true`. No Scout commercial-building size/use filter is applied to the deer-science measurement.
