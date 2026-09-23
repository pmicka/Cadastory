# Farm Watch Study-Aligned Vegetation Height v1

Status: **production-validated neutral physical product**  
Primary deer-science measurement: `FW-M02-vegetation-height`  
Neutral product: `study-aligned-vegetation-height-context-v2`  
Algorithm: `wiemers-first-return-minus-ground-local500m-v1`

## Purpose

This product reconstructs the physical vegetation-height variable used by Wiemers et al. (2014) closely enough for Farm Watch to bind the study relationship to a study-aligned measurement rather than to generic LiDAR return-share strata.

It remains a **neutral physical product**. It does not evaluate deer use or produce a habitat, bedding, thermal-cover, forage, concealment, movement, or hunting score.

## Published measurement

Wiemers et al. collected LiDAR over the study area, created separate bare-ground and first-return TIN surfaces, rasterized each to a 1.2 m DEM, and calculated vegetation height as first-return elevation minus bare-ground elevation.

Citation:

Wiemers, D.W., Fulbright, T.E., Wester, D.B., Ortega-S., J.A., Rasmussen, G.A., Hewitt, D.G., and Hellickson, M.W. 2014. *Role of Thermal Environment in Habitat Selection by Male White-Tailed Deer during Summer in Texas, USA.* Wildlife Biology 20:47–56. DOI: 10.2981/wlb.13029.

## Farm Watch derivation

Farm Watch preserves:

- LAS first returns: `ReturnNumber = 1`;
- LAS bare-ground support: Classification 2;
- 1.2 m spatial support;
- vegetation height = first-return elevation minus bare-ground elevation;
- deterministic exclusion of withheld, overlap, and noise classes 7/18;
- the exact barrier-aware `local_500m` analysis domain;
- current central KyFromAbove Phase 3 source selection and provenance.

The implementation differs from the publication in one explicit way:

- the paper used ArcMap TIN interpolation;
- Farm Watch uses 1.2 m cell-mean first-return and ground surfaces with bounded deterministic inverse-distance filling.

Therefore the product is intended as a **derived-equivalent measurement**, not a claim that the original TIN interpolation has been numerically reproduced.

## Grid and encoding

- output support: 1.2 m;
- native CRS: EPSG:6473;
- height unit: metres;
- encoded height: uint16 centimetres;
- support byte is a bitmask:
  - bit 0 (`1`): height available;
  - bit 1 (`2`): first-return surface required local filling;
  - bit 2 (`4`): raw first-return-minus-ground residual was negative and the physical height was clamped to zero;
  - bit 3 (`8`): the local ground cell contains direct LAS Class 2 support;
  - `0`: outside domain or unavailable;
- ground fill radius: 10 m;
- first-return fill radius: 2.4 m.

Only the derived height surface and support byte are persisted. Negative raw residuals remain distinguishable through the support flags and aggregate QA. Cells carrying the negative-clamp flag are **QA-excluded/unavailable height observations** for scientific consumers and must not be interpreted as genuine 0 m vegetation. Raw COPC/LAZ data, duplicate ground surfaces, and duplicate first-return elevation surfaces are not stored.

## Spatial scope

The product uses the current exact barrier-aware `local_500m` Farm Watch domain rather than stopping at the ownership boundary.

This allows the same physical covariate to be compared across candidate locations and immediate surrounding context while preserving the existing Farm Watch landscape-domain identity.

## Provenance

The source signature binds:

- current landscape-domain identity and algorithm;
- KyFromAbove LiDAR source contract;
- Phase 3 source collection;
- native CRS;
- 1.2 m cell support;
- ground and first-return support radii;
- return/classification rules;
- first-return-minus-ground derivation.

Each materialization additionally persists a source fingerprint with selected COPC item identities and header/node counts.

## Validation gates

The FW-S21 neutral product validation gates have now been satisfied:

1. source coverage is complete across the current `local_500m` domain;
2. the artifact passes schema/packed-grid validation;
3. direct and supported first-return/ground coverage are reported;
4. negative raw heights are quantified rather than silently discarded;
5. selected raw-point/profile checks confirm representative open/low/mid/high cells are physically consistent with source first-return and Class 2 ground points;
6. the rare large-negative tail was explicitly profiled and is isolated by the v2 negative-clamp support flag;
7. storage checksum/size matches the materialization record;
8. the validation property has 100% valid product coverage.

Production QA is preserved in:

- `docs/FARM_WATCH_STUDY_VEGETATION_HEIGHT_QA_2026-09-23.md`
- GitHub Actions run `35925845150`, job `107400620816`

**Important:** FW-S21 production validation does not itself promote FW-M02 in the deer relationship registry. A future FW-M02 promotion must bind the relationship to this product, require valid support flags, and leave all other FW-D01 blockers intact.

The product may be promoted only for the **vegetation-height measurement**. It does not unblock the other FW-D01 inputs: operative temperature, forage index, woody canopy cover, or movement-defined activity period.

## Interpretation boundary

Vegetation height here means a LiDAR-derived vertical physical distance between a first-return surface and a ground surface.

It is not:

- plant species;
- forage quantity or chemistry;
- woody canopy percent;
- concealment;
- browse density;
- bedding cover;
- habitat quality;
- deer presence/use;
- deer movement;
- hunting value.

## Temporal boundary

The product inherits the current Phase 3 LiDAR acquisition metadata. The existing acquisition-time discrepancy documented in `FARM_WATCH_STRUCTURE_EVIDENCE_LEDGER.md` remains unresolved and must not be silently converted into a precise vegetation-date claim.
