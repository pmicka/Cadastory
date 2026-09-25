# Farm Watch Multiscale Forest Context v1

Status: implementation candidate — 2026-09-25

## Purpose

`multiscale-forest-context-v1` resolves FW-M35, the forest-availability/configuration measurement required by the Stephens et al. (2024) juvenile-male dispersal relationship.

It is a neutral physical land-cover product. It does not infer deer selection, dispersal likelihood, corridor use, road response, or a Kentucky forest preference.

## Source-study measurement

Stephens et al. evaluated forest context from 10 m land cover and extracted the forest covariate around observed/available step endpoints at three focal radii:

- 30 m;
- 90 m;
- 270 m.

The study represented forest as the tree land-cover class, used forest proportion, and calculated forest edge density in m/ha relative to other land-cover classes after removing built land. The source analysis used a Dynamic World dominant land-cover composite covering 2015-06-01 through 2019-12-31.

The relationship changed across two Missouri landscapes with substantially different forest availability/configuration. Farm Watch therefore preserves the physical multiscale measurement and does **not** transfer a universal forest-response direction.

## Farm Watch source

Farm Watch uses the public **Sentinel-2 10m Land Use/Land Cover Time Series** distributed by Impact Observatory / Esri / Microsoft.

Contract:

- source slug: `esri-sentinel2-10m-lulc`;
- source support: 10 m;
- forest class: `Trees` / value 2;
- built class: `Built Area` / value 7;
- cloud class: value 10;
- license: CC BY 4.0;
- source pixels remain remote and are not persisted in Postgres.

This is a documented **source substitution**. It preserves the 10 m Sentinel-2 land-cover support and the source measurement form, but it is not the original Dynamic World classifier and it does not reproduce the original 2015–2019 temporal composite.

## Spatial evaluation

The product can be evaluated at:

- the property center, which is centrally materialized; or
- an explicit downstream evaluation point inside the current Farm Watch `broad_3000m` landscape domain.

Each request builds a deterministic EPSG:32616 10 m raster window around the point with one-cell support beyond the largest focal radius.

For each of 30 m, 90 m, and 270 m, Farm Watch reports:

- valid land-cover cell count;
- tree/forest cell count;
- forest proportion and percent;
- built, cloud, and excluded/no-data cell counts;
- edge-metric cell count and analyzed area;
- internal forest/nonforest edge length;
- forest edge density in m/ha.

## Forest proportion

Forest proportion is:

`Trees cells / valid non-cloud land-cover cells`

Built cells remain part of the general land-cover denominator for forest proportion, consistent with representing forest availability among mapped land cover.

## Forest edge density

The edge metric is designed to preserve the source `lsm_l_ed` measurement form:

- binary `Trees` versus other eligible land cover;
- Built Area is removed from the edge metric;
- cloud/no-data cells are removed;
- only internal rook-adjacency forest/nonforest cell boundaries are counted;
- the artificial circular focal-window boundary is not counted;
- edge density = internal edge length / analyzed edge-metric area × 10,000, reported in m/ha.

The implementation does not label high edge density as favorable or unfavorable.

## Persistence and provenance

Property-center output is stored in:

`farm_watch.property_multiscale_forest_context_v1`

Identity includes:

- property boundary SHA-256;
- source annual year;
- live source-service metadata SHA-256;
- exported bounded raster SHA-256;
- algorithm and schema versions;
- normalized context content.

The stored context also preserves the source substitution and measurement-method alignment.

## Refresh

The source is annual. Flat Creek refresh is scheduled monthly so a newly published annual layer can be adopted without user input.

On-demand explicit-point evaluation is not centrally persisted.

## Interpretation boundary

This product authorizes only the M35 physical input measurement.

It does **not** authorize:

- a positive or negative forest-selection sign;
- a claim that Flat Creek matches the study's North or South Missouri landscape;
- any Stephens coefficient or effect magnitude;
- a resident-deer relationship;
- application to adult deer;
- activation outside an explicit juvenile-male dispersal state.

Those conditions remain enforced by FW-R18 and the deer relationship registry.
