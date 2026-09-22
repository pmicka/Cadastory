# Farm Watch Field Phenology v1

Status: Batch 4A implementation candidate — not deployed  
Validation property: `validation-property-01`

## Purpose

Field Phenology v1 is the neutral agricultural-state layer required before Farm Watch can use crop phenology or harvest state in a deer relationship. It replaces the unsafe shortcut “mapped crop class = current food” with dated field identity, satellite observations, explicit data quality, multiscale landscape scope, and regional context.

Batch 4A intentionally stops short of classifying harvest. It establishes the durable field-observation and state contract so the later HLS time-series processor can add an evidence-backed phenology method without changing the public semantic boundary.

## Existing substrate reused

The implementation reuses current production assets rather than creating a parallel agriculture model:

- `agriculture.field_boundaries` for USDA NASS Crop Sequence Boundary field geometry;
- `agriculture.field_crop_history` for annual field crop identity/provenance;
- `agriculture.crop_progress_layers` for regional synthetic NASS crop-progress context;
- `farm_watch.property_landscape_domains_v1` for the existing barrier-aware `local_500m`, `landscape_1500m`, and `broad_3000m` domains;
- `farm_watch.property_operator_observations_v1` remains the future explicit field-observation override/evidence lane rather than being silently mixed into remote sensing.

The validation property's parcel boundary intersects no current USDA field boundary. The barrier-aware landscape domain does contain agricultural fields: one in `local_500m`, twelve in `landscape_1500m`, and thirty-seven in `broad_3000m`. Field Phenology therefore treats property, local, landscape, and broad scope as separate memberships instead of assuming farm fields and the watched parcel are coextensive.

## New central products

### `farm_watch.field_vegetation_observations_v1`

Service-only central persistence for field-level HLS summaries. Each row records:

- canonical field identity;
- HLS source product and granule identity;
- observation time;
- NDVI, EVI, and NIR field summaries when available;
- valid/total pixel counts and valid fraction;
- cloud fraction and QA context;
- source URL and SHA-256 source identity;
- retrieval timestamp.

Raw HLS imagery is not persisted merely to support Farm Watch. The durable product is the small derived field observation plus source provenance.

### `farm_watch.property_field_phenology_context_v1`

Date-keyed property context that binds:

- property boundary identity;
- current landscape-domain identity;
- all qualifying fields in the `broad_3000m` domain;
- field scope memberships;
- annual crop identity/provenance;
- latest/prior quality-qualified HLS observations;
- descriptive VI trajectory;
- regional NASS progress context;
- explicit evidence state and harvest-method status.

A stored context becomes stale if the property boundary, landscape-domain identity, or algorithm/schema contract changes.

## Evidence-state contract

Each field observation is classified independently as:

- `known` — a quality-qualified HLS field observation exists within the 10-day freshness window;
- `stale` — a quality-qualified observation exists but is older than the freshness window;
- `unavailable` — no qualifying HLS observation exists for the requested date.

A minimum valid-pixel fraction of 0.30 is required before an HLS observation can participate in the dated context. This is a data-support gate, not a harvest threshold.

Crop identity is separately classified as current/stale/unavailable by crop year. A 2025 CSB/CDL crop identity requested for 2026 remains stale even when a 2026 HLS observation is current.

## Batch 4A phenology semantics

The schema reserves the following eventual state vocabulary:

- `green_up`;
- `vegetative`;
- `mature_senescing`;
- `probable_harvest_transition`;
- `post_harvest_residual`;
- `unknown`.

Batch 4A returns `phenology_state = unknown` for every field. It may describe a latest-versus-prior NDVI trajectory as increasing, stable, declining, insufficient observations, or unknown, but trajectory direction is not itself a phenology or harvest label.

The resolver explicitly sets:

- `scoring_performed=false`;
- `behavioral_inference_performed=false`;
- harvest method state `not_evaluated_batch4a`;
- coefficient/threshold transfer authorization `false`.

## Harvest-method evidence boundary

Two method forms are retained as implementation candidates rather than silently converted into coefficients:

1. Yang et al. (2021), *Detecting Recent Crop Phenology Dynamics in Corn and Soybean Cropping Systems of Kentucky*, Remote Sensing 13(9):1615, DOI `10.3390/rs13091615`. The Kentucky study used a curve-change-based dynamic-threshold approach on smoothed MODIS NDVI time series. It supports a Kentucky-specific method form, but its MODIS workflow and calibrated stage thresholds are not automatically HLS field coefficients.
2. Liu et al. (2025), *A novel Normalized Harvest Phenology Index (NHPI) for corn and soybean harvesting date detection using Landsat and Sentinel-2 imagery on Google Earth Engine*, Remote Sensing of Environment 331:115016, DOI `10.1016/j.rse.2025.115016`. NHPI uses NIR and NDVI dynamics to identify the senescent-crop-to-residue transition and performed strongly across Midwestern evaluation data. The published threshold was calibrated to study-region ground truth; Batch 4 does not copy that threshold into Kentucky without validation.

Accordingly, Batch 4A MUST NOT assign `probable_harvest_transition` or `post_harvest_residual` from a generic NDVI drop, a single low vegetation-index observation, stale CDL identity, or a regional NASS progress value.

## HLS source contract for Batch 4B

Registered source families:

- HLSL30 v2.0 Landsat surface reflectance;
- HLSS30 v2.0 Sentinel-2 surface reflectance;
- HLSL30_VI v2.0 vegetation indices;
- HLSS30_VI v2.0 vegetation indices.

HLS supplies harmonized 30 m surface reflectance and quality masks with repeated observations suitable for field-scale trajectories. HLS-VI can supply precomputed NDVI/EVI, but methods such as NHPI require NIR reflectance as well, so the surface-reflectance products remain part of the source contract.

The HLS materializer must preserve catalog/download failure separately from valid no-observation/cloud states. NASA documented 2026 cases where CMR-STAC exposed metadata without the expected science assets even though underlying granules remained available. STAC asset absence therefore must not be translated into a false field observation or a false cloud/no-data classification.

## Production expectation before HLS materialization

With Batch 4A schema present but no HLS observations stored, `validation-property-01` should resolve to:

- 37 fields in `broad_3000m`;
- 12 in `landscape_1500m`;
- 1 in `local_500m`;
- 0 direct parcel-intersecting fields;
- aggregate status `unavailable` because there is no current field-level HLS evidence;
- every field `phenology_state=unknown`;
- no harvest inference.

This is the correct fail-closed state, not an incomplete implementation result.

## Batch 4B dependency

The next layer is a protected HLS field-observation materializer using the existing owner-only GitHub Actions OIDC → Farm Watch worker pattern. Heavy raster sampling should occur in the worker workflow, not in the browser. The worker should persist field summaries/provenance through the service-only store RPC and then refresh `field-phenology-context-v1`.

Long-lived production operation also requires a sustainable Earthdata authentication posture; a short-lived personal token must not become an undocumented permanent dependency.
