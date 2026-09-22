# Farm Watch Field Phenology v1

Status: Batch 4A production; Batch 4B implementation candidate — not deployed  
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

The HLS materializer must preserve catalog/download failure separately from valid no-observation/cloud states. NASA's Earthdata Forum documented an August 2026 CMR-STAC defect in which some HLS items exposed metadata without expected science assets even though the underlying granules remained available. LP DAAC reported on September 2, 2026 that it believed the defect resolved. The collector should still validate required assets so a future catalog regression cannot silently become a false field observation or false cloud/no-data classification.

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

## Pre-deployment rollback validation — 2026-09-21

The exact source-controlled migration was executed against the live production schema inside a transaction and rolled back.

Validation passed for the real property/domain substrate:

- target selection: 37 fields in `broad_3000m`, 12 in `landscape_1500m`, 1 in `local_500m`, and 0 parcel-intersecting;
- no-observation resolver: `status=unavailable`, 37 unavailable fields, all `phenology_state=unknown`;
- service-only ACLs: anonymous/authenticated table and RPC access denied; service role allowed;
- synthetic current HLS observation: context became `partial` with 1 known / 36 unavailable while the observed field remained `phenology_state=unknown`, `trajectory_state=insufficient_observations`, and `harvest_method.status=not_evaluated_batch4a`;
- no scoring, behavioral inference, or harvest promotion occurred;
- post-test catalog checks confirmed the rollback left no Batch 4A table/function in production.

## Batch 4A production deployment — 2026-09-21

Batch 4A is production-operational. The migration is deployed, the validation-property context is materialized, and production retains the expected fail-closed state:

- 37 fields in `broad_3000m`;
- 12 in `landscape_1500m`;
- 1 in `local_500m`;
- 0 direct parcel-intersecting fields;
- 37 field-evidence states `unavailable`;
- every `phenology_state=unknown`;
- service-only table/RPC access;
- tool-registry and architecture-doctrine assertions passing.

The current stored identity is bound to the exact property boundary, landscape-domain identity, dated field set, crop-history provenance, and regional NASS context.

## Batch 4B protected HLS materializer

Batch 4B adds a protected GitHub Actions OIDC → Farm Watch Edge worker path for current HLS field observations.

### Distribution route

NASA LP DAAC remains the scientific source authority. Operational access uses the Microsoft Planetary Computer HLS v2.0 distribution, an official NASA-listed cloud access route for HLS:

- `hls2-l30` → NASA HLSL30 v2.0;
- `hls2-s30` → NASA HLSS30 v2.0.

This avoids introducing a personal Earthdata token as a permanent production dependency while retaining NASA HLS source provenance.

### Processing boundary

The GitHub worker:

1. requests current Farm Watch field targets through the protected Edge worker;
2. discovers HLS L30/S30 scenes over the broad landscape domain;
3. reads only required COG windows for USDA field geometries;
4. applies HLS Fmask quality exclusions;
5. computes field-level NDVI, EVI, NIR and quality summaries;
6. returns only derived observations and provenance to the Edge worker;
7. persists no raw HLS imagery.

The workflow has `contents:read` and `id-token:write`; it does not receive a Supabase service key.

### HLS quality contract

Batch 4B excludes HLS Fmask cloud, adjacent-cloud/shadow, cloud-shadow, snow/ice, water, and high-aerosol pixels before field summaries are accepted. A field observation retains:

- valid and total pixel counts;
- valid fraction;
- cloud fraction;
- QA counts;
- source collection/item/assets;
- observation timestamp;
- exact method/package provenance.

The existing 0.30 valid-pixel fraction remains a data-support threshold only. It is not a vegetation, phenology, or harvest threshold.

### Operational failure ledger

`farm_watch.property_field_vegetation_collection_runs_v1` keeps acquisition state separate from agricultural evidence. Run outcomes include:

- `available`;
- `partial`;
- `no_valid_observation`;
- `catalog_incomplete`;
- `download_error`;
- `processing_error`.

A catalog, signing, COG-download, or processing failure therefore cannot silently become "no vegetation," "no crop," or "post-harvest."

### Pre-deployment Batch 4B database validation — 2026-09-21

The exact Batch 4B database migration was executed against the live production schema inside a transaction and rolled back.

The validation lifecycle successfully:

- created a processing HLS collection run for `validation-property-01`;
- completed it as `no_valid_observation` with 37 target fields and internally consistent source/item counters;
- read the completed run back in a subsequent statement;
- retained NASA LP DAAC as `source_authority` and Microsoft Planetary Computer as `distribution_provider`;
- denied anonymous/authenticated table and RPC access while permitting the service role;
- registered the Planetary Computer HLS distribution source inside the transaction;
- confirmed after rollback that the run table and all Batch 4B run-ledger functions did not remain in production.

This validates the acquisition-state separation before the first real HLS pilot. It does not establish that the external STAC/COG path succeeds in production; that is the post-deployment Batch 4B pilot gate.

### Interpretation boundary

Batch 4B still does **not** enable harvest classification. Current HLS observations can move field evidence from `unavailable/stale` to `known`, but `phenology_state` remains `unknown` until a separately validated time-series method is implemented.

The next gate after materializer deployment is a real HLS pilot over `validation-property-01`, followed by review of observation support and the Kentucky/NHPI method-transfer requirements before any standing/senescent/harvest label is enabled.
