# Farm Watch Forest Type Context v1

## Purpose

`forest-type-context-v1` is the production implementation of **FW-M47** for the Abernathy et al. (2019) Hurricane Irma relationship.

It is a neutral physical habitat-distance product. It does **not** score refuge quality, infer deer use, transfer a Florida selection coefficient, or turn ordinary weather into a storm-response term.

## Source-study measurement

Abernathy et al. used Florida Natural Areas Inventory Cooperative Land Cover v3.2 at 10 m. The study reclassified land cover, retained six habitat classes, calculated Euclidean distance to each class from every raster cell, extracted those distance covariates at used and available deer locations, and scaled/centered the model variables.

The six retained classes were:

1. pine forest
2. hardwood swamp
3. marsh
4. prairie
5. shrub
6. hardwood hammock

M47 therefore preserves **six continuous distance-to-class variables**, not one categorical “refuge type.”

## Farm Watch source reconciliation

Florida CLC communities are not available nationally and must not be silently relabeled in Kentucky. Farm Watch preserves the measurement form and records a source-substituted `proxy` evidence state.

| Study class | Farm Watch source class | Boundary |
| --- | --- | --- |
| pine forest | Annual NLCD Evergreen Forest (42) | broad evergreen analogue; not a pine-species map |
| hardwood swamp | NWI PFO1* Palustrine Forested Broad-Leaved Deciduous | forested deciduous-wetland analogue |
| marsh | NWI PEM* Palustrine Emergent | emergent-wetland analogue |
| prairie | Annual NLCD Grassland/Herbaceous (71) | herbaceous analogue; pasture/hay and cultivated crops excluded |
| shrub | Annual NLCD Shrub/Scrub (52) | broad shrub/scrub analogue |
| hardwood hammock | Annual NLCD Deciduous Forest (41) | upland/broad hardwood analogue; not literal Florida hammock |

Annual NLCD is consumed from the public USGS/MRLC ImageServer at its current latest service year and nearest-neighbor 30 m support. NWI is consumed from Farm Watch's existing authoritative USFWS wetland cache.

## Distance contract

The product uses a fixed **3,000 m** search radius around each evaluation point.

For Annual NLCD classes, distance is measured to source-grid cell centers. If the evaluation point falls inside the target class, distance is zero.

For NWI classes, distance is measured directly to stored wetland geometry.

If a healthy source contains no matching class inside 3 km, the row is `right_censored` with `distance_lower_bound_m: 3000`. Source failure or inadequate NWI coverage is `unavailable`, never treated as mapped absence.

The persisted property product is anchored at the property center. Protected on-demand evaluation may be performed at points inside the property; that boundary preserves the existing 3 km NWI collection guarantee.

## Production identity

- Algorithm: `abernathy-habitat-distance-source-reconciliation-v1`
- Output schema: `forest-type-context-v1`
- Evidence class: `deterministic_derived`
- Evidence state: `proxy`
- Annual NLCD source slug: `usgs-annual-nlcd-land-cover`
- NWI source slug: `usfws-nwi`
- Refresh: quarterly, using the existing Vault-backed Farm Watch materialization worker credential
- Edge Function: `farm-watch-forest-type-context`
- Edge Function auth posture: existing in-function worker-token validation with `verify_jwt:false`

## Flat Creek production validation

Validation property: `validation-property-01` / Flat Creek Test Property.

Initial production materialization used Annual NLCD **2024** and the available NWI 3 km cache. Property-center distances were:

| Study class | Distance |
| --- | ---: |
| pine forest analogue | 377.9 m |
| hardwood swamp analogue | 2,011.5 m |
| marsh analogue | 1,766.3 m |
| prairie analogue | 443.4 m |
| shrub | 2,651.3 m |
| hardwood hammock / upland-hardwood analogue | 0 m |

These values are source-class geometry only. They carry no positive/negative deer interpretation.

## Deer-science boundary

FW-D18 remains **extreme-event-only**. M47 removes the unresolved habitat-measurement blocker, but the relationship still requires the explicit production extreme-event gate and relative-elevation context. The Abernathy Florida coefficients remain `not_supported` for transfer.

Generic tree cover, total canopy cover, forest proportion, forest edge, or a generic wetland flag must not be substituted for these six M47 variables.
