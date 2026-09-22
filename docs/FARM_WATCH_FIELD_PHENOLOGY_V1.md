# Farm Watch Field Phenology v1

Status: Batch 4A + Batch 4B production; 180-day growing-season HLS substrate validated; current-season crop source gate reviewed; live phenology/harvest classifier not yet authorized  
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

### Production deployment and HLS pilot — 2026-09-21

Batch 4B is production-operational.

Deployment state:

- PR #198 merged at `c9a91f802e313b9b85b1aa8594b2347b3f245ab8`;
- database migration `20260922031000_add_farm_watch_hls_field_materializer_v1.sql` applied successfully;
- protected Edge Function `farm-watch-field-phenology-worker` deployed as version 1 with the established in-function GitHub OIDC authentication and `verify_jwt=false`;
- owner-triggered GitHub workflow successfully exercised the production STAC/COG path;
- PR #200 merged the scene-dataset reuse hotfix at `aa54ac7e8ed15aff89084bcbaa5e6676737c207a`.

The first real pilot and the post-hotfix idempotence rerun both resolved the same source set and field context:

- 37 target fields;
- 17 complete HLS scenes discovered and sampled;
- 5 HLSL30 scenes and 12 HLSS30 scenes;
- 629 canonical field/scene observation rows;
- 252 rows met the `valid_fraction >= 0.30` quality-support threshold;
- all 37 target fields had a quality-qualified observation within the 10-day freshness window;
- newest stored observation: 2026-09-19;
- oldest stored observation in the 45-day window: 2026-08-08;
- zero incomplete catalog items;
- zero COG/download failures;
- no raw HLS imagery persisted.

The refreshed `field-phenology-context-v1` is now `available` with:

- `known=37`;
- `stale=0`;
- `unavailable=0`;
- `phenology_state=unknown` for all 37 fields;
- `scoring_performed=false`;
- `behavioral_inference_performed=false`;
- identity `cd9cadafaced8dca3df60410263782e147622de293f39529a8c33193cb161e47`.

The post-hotfix rerun produced the same context identity and the same 17-scene / 629-row / 37-current-field result. Reusing open scene datasets therefore preserved data semantics exactly. It did not materially reduce observed wall-clock runtime; remote COG window reads remain the dominant cost.

Production numeric sanity checks found:

- NDVI means within [0.4712, 0.9187], with no values outside the physical [-1,1] range;
- EVI means within [0.2638, 0.7967], with no extreme/nonfinite values under the validation rule;
- mean NIR reflectance within [0.1913, 0.5053], with no extreme values under the validation rule.

The median valid fraction across all retained field/scene rows is 0 because many cloudy/invalid scene-field combinations are deliberately persisted with explicit QA instead of being hidden. Downstream dated state uses only quality-qualified observations.

Both `agent_contract.assert_tool_registry_integrity_v1()` and `agent_contract.assert_architecture_doctrine_v1()` pass after deployment. Supabase advisors report only the expected INFO-level RLS-without-policy notices on the service-only Farm Watch tables.

### Interpretation boundary

Batch 4B does **not** enable harvest classification. Current HLS observations now establish a usable dated field-observation time series, but every field remains `phenology_state=unknown` until a separately validated classification method is authorized.

The next dependency-correct gate is the Batch 4 phenology/harvest method-transfer pass: evaluate the HLS time series against the Kentucky curve-change and NHPI evidence, define the minimum observation/quality requirements, and only then implement standing/active crop, senescence, probable-harvest-transition, post-harvest/residual, or explicit abstention semantics.

## Batch 4 classifier transfer review — 2026-09-22

The first classifier review found that the 45-day production collection window is too short to authorize a published harvest method. The quality-qualified production observations currently span 2026-08-09 through 2026-09-19, with only 5–8 usable observation dates per field. That is enough for a recent vegetation trajectory but not enough to establish the full seasonal/post-peak trajectory required by the retained harvest methods.

Scientific disposition:

- Yang et al. (2021) is Kentucky-specific and supports a curve-change method form, but its implementation identifies crop-season landmarks from a smoothed daily MODIS NDVI trajectory. Its MODIS coefficients/windows are not automatically HLS 30 m coefficients.
- Liu et al. (2025) supports the NIR + NDVI NHPI harvest-transition form, but NHPI requires locating the post-peak senescence trajectory before evaluating the harvest transition. The published threshold remains study-calibrated and is not authorized as a Kentucky coefficient.
- A generic latest-versus-prior NDVI drop remains forbidden.
- The current 2025 CDL/CSB crop identity remains stale for a 2026 request. Crop-specific corn/soy harvest logic must not silently assume the 2026 crop from last year's identity.

The HLS acquisition contract is therefore extended from 45 to **180 days**. On a late-September run this reaches into late March, before the Kentucky study's documented corn and soybean planting windows, while preserving the existing field-clipped COG workflow and remote-sensing evidence boundary. The longer window is an observation-substrate change only; it does not enable classification.

A published open-source CONUS in-season HLS crop-type mapper was also reviewed as a possible current-year crop-identity proxy. Its released implementation requires two years of raw HLS, a TensorFlow model, and substantially broader spectral inputs than the current Farm Watch field sampler. It is retained as a transfer candidate rather than introduced as an operational dependency in this Batch 4 unit.

Classifier state remains fail-closed until the expanded trajectory has been materialized and reviewed.

### Expanded production trajectory validation — 2026-09-22

PR #206 expanded the protected HLS acquisition contract from 45 to 180 days and deployed `farm-watch-field-phenology-worker` version 2 with the existing GitHub OIDC/custom-auth posture unchanged.

Production workflow run `35691287320` completed successfully for `validation-property-01`:

- lookback start: 2026-03-26;
- 37 target fields;
- 82 complete HLS scenes discovered and sampled;
- 3,034 canonical field/scene rows;
- 1,136 rows meeting the `valid_fraction >= 0.30` support gate;
- 37 current-quality fields;
- quality-qualified observations span 2026-03-29 through 2026-09-19;
- the 2025-corn field has 32 distinct quality dates;
- the 2025-soybean fields have 28–31 distinct quality dates;
- the 2025-grass/pasture fields have 23–32 distinct quality dates;
- zero catalog-incomplete items;
- zero download errors;
- no raw imagery persisted.

This closes the short-trajectory blocker. The dated field context remains intentionally fail-closed: 37/37 fields are current, 37/37 retain `phenology_state=unknown`, and `scoring_performed=false` / `behavioral_inference_performed=false`.

### Live-classifier transfer disposition

1. **Yang et al. (2021), Kentucky curve-change phenology** remains method-form evidence for corn/soybean planting and harvest timing. Its published implementation uses a smoothed seasonal MODIS NDVI curve and crop-specific phenological windows. Farm Watch cannot apply crop-specific harvest logic while the only field crop identity is the stale 2025 CDL/CSB identity for a 2026 request.
2. **Liu et al. (2025), NHPI** remains strong harvest-transition evidence for corn/soybean, but its published method normalizes HPI within a field-specific window beginning at middle-of-senescence and extending two months afterward; the published 0.6 threshold was calibrated against study-region field truth. Using a truncated future window or copying that threshold into Kentucky would be an unvalidated modification.
3. **Tang et al. (2026), Reaped Index (RI)**, DOI `10.1016/j.jag.2026.105510`, is a newer near-real-time, unsupervised harvest method using Sentinel-2 and adaptive thresholding. It is operationally better aligned with Farm Watch's current-state objective and was validated for grain crops including maize at a U.S. Iowa site. It remains a candidate method form, not a production classifier. RI requires spectral inputs beyond the current NDVI/EVI/NIR summaries, notably red and SWIR1 behavior, and still requires a defensible current-season crop mask.
4. A 2026 peer-reviewed 10 m In-season Crop-type Data Layer (ICDL) product (Li et al. 2026, DOI `10.1038/s41597-026-07099-1`) and a published HLS Transformer crop mapper (Zhang et al. 2025, DOI `10.1016/j.rse.2025.114950`) establish defensible current-year crop-mapping routes. Operational availability/ingestion for the current 2026 Kentucky fields has not yet been verified, so neither is silently substituted for crop identity.

**Gate result:** the seasonal observation substrate is now adequate. The remaining classifier blockers are (a) defensible current-season crop identity and (b) selection/implementation of a genuinely near-real-time harvest method whose required spectral inputs and threshold/segmentation semantics transfer to the target fields.

Until those conditions are satisfied, `probable_harvest_transition` and `post_harvest_residual` remain unauthorized and `unknown` is the correct production result.

## Current-season crop identity source gate — 2026-09-22

Batch 4 requires a current-season field crop identity before any crop-specific harvest rule can be applied. The 2025 CDL/CSB identity remains a historical prior only for a 2026 request.

### 10 m In-season Crop-type Data Layer (ICDL)

Li et al. (2026), DOI `10.1038/s41597-026-07099-1`, describes June/July/August current-year 10 m ICDL maps produced with Sentinel-2 and Landsat 8/9 and states that current-year layers are intended to be public within about five days after month end.

Operational verification on 2026-09-22 did not establish a consumable 2026 Kentucky layer:

- the currently discoverable public iCrop layer catalog tops out at `2025-August`;
- exact searches for `2026-June`, `2026-July`, and `2026-August` coverage identifiers returned no discoverable public layer;
- CropSmart's current public site describes the digital-twin platform but does not surface a 2026 ICDL download/service endpoint;
- the documented iCrop WMS/WCS service endpoints were identifiable from the peer-reviewed iCrop software paper, but direct capability/coverage retrieval could not be completed reliably from the development environment.

Disposition: **do not promote ICDL to production evidence yet**. The scientific product is appropriate, but current 2026 operational availability for the target Kentucky fields is not verified.

### Published HLS Transformer fallback

Zhang et al. (2025), DOI `10.1016/j.rse.2025.114950`, provides a trained within-season CONUS crop-type Transformer, application code, and public model artifact. The published model is explicitly designed to classify on arbitrary current-season dates and reported F1 > 0.8 for corn by May 11 and soybean by May 31 in the 2023 evaluation.

Operational characteristics relevant to Farm Watch:

- application code: `hankui/In-season-crop-type-mapper`, Apache-2.0;
- trained model artifact: approximately 69.9 MB on Zenodo record `14715402`;
- model input spans the previous year plus current year HLS time series;
- the released model consumes substantially richer spectra than Farm Watch's current NDVI/EVI/NIR observation rows;
- Landsat inputs include coastal/blue/green/red/NIR/SWIR1/SWIR2 plus thermal bands and timing;
- Sentinel-2 inputs include coastal/blue/green/red/NIR-A/SWIR1/SWIR2 plus red-edge/NIR8 bands and timing.

The released application processes HLS tiles, but that whole-tile/raw-data architecture is not required by Farm Watch. A future integration should adapt the published model to **field-scoped pixel/time-series reads** through the existing protected HLS access pattern, avoiding bulk raw HLS persistence.

Disposition: the Transformer is the preferred fallback candidate if a direct 2026 ICDL service cannot be verified. It is **not yet production evidence**. Before implementation, confirm model-artifact reuse terms, define a field-scoped spectral contract, and benchmark inference/IO cost on the 37-field validation domain.

### Gate result

Current-season crop identity remains unresolved in production. No 2025 crop class may be silently promoted to 2026 truth. Batch 4 remains fail-closed until either:

1. a current 2026 ICDL layer is directly consumable and provenance-stable for the target fields; or
2. the published HLS Transformer is integrated through a bounded field-scoped pipeline with explicit model/source identity and uncertainty.


## HLS Transformer bounded integration spike — 2026-09-22

This spike defines the integration boundary for Zhang et al. (2025), DOI `10.1016/j.rse.2025.114950`, without enabling crop classification.

### Reuse-rights gate

The application code in `hankui/In-season-crop-type-mapper` is Apache-2.0 and the paper is CC BY 4.0. The trained model is publicly downloadable from Zenodo record `10.5281/zenodo.14715402` and the record publishes the model MD5 `75b13ac5743d1d3449ffe5e2425e6ece`.

The exact record-level rights/license attached to the Zenodo model artifact could not be independently verified from the accessible record metadata during this spike. Public availability is not treated as sufficient permission to vendor, redistribute, or operationally execute the model artifact. Farm Watch therefore records `modelArtifactReuseStatus=blocked_pending_explicit_rights_verification`.

### Exact model input contract

The released application classifies a current-year 30 m pixel from **two years** of HLS: the complete previous year plus current-year observations through the requested date.

The inference tensor is aligned as:

1. previous-year Landsat;
2. previous-year Sentinel-2;
3. current-year Landsat;
4. current-year Sentinel-2.

The released implementation reserves up to 176 acquisition dates per sensor per year and pads missing positions with `-9999`. It dynamically shortens the sequence to the maximum union of good-quality acquisition dates in the processing block.

The model-input features are:

- Landsat HLSL30: DOY + `B01 B02 B03 B04 B05 B06 B07`;
- Sentinel-2 HLSS30: DOY + `B01 B02 B03 B04 B8A B11 B12 B05 B06 B07 B08`.

The released HLS loader reads Landsat B10/B11 thermal bands, but the crop classification model **does not feed them into inference**. Prior Farm Watch notes that described thermal bands as model inputs were therefore too broad.

HLS reflectance is first scaled by `0.0001`. Reflectance is then standardized with the released mean/std file. DOY is encoded as:

`year_offset + (doy - 1) / 366`

so the previous/current two-year sequence spans approximately 0–2.

Published-application QA excludes:

- fill;
- cloud;
- adjacent cloud/shadow;
- cloud shadow;
- snow/ice.

The published application does not explicitly exclude water or high aerosol. That differs from the existing Farm Watch HLS vegetation sampler, which excludes both. The crop-model spectral collector must therefore remain a separate evidence path unless equivalence is established.

The source-controlled normalization constants and exact band order are recorded in `farm-watch-current-crop-identity-contract.ts`.

### Output / confidence semantics

The released model outputs **50 raw class logits** and the application assigns the class with `argmax`. It does not publish a calibrated per-pixel probability contract.

Farm Watch therefore MUST NOT call any of the following a calibrated crop probability without a separate calibration study:

- softmax(logits);
- top logit magnitude;
- top-two logit margin.

For field review, neutral diagnostics may include:

- count of field pixels classified;
- distribution of pixel class votes;
- modal-class vote fraction;
- top-two vote margin;
- class entropy;
- previous/current-year temporal support.

These are support diagnostics, not scientific confidence coefficients.

The source paper is a pixel-mapping study and does not publish a validated rule for promoting pixel predictions to one accepted USDA-field crop identity. No arbitrary majority threshold is introduced here. The neutral contract therefore distinguishes a `candidate_only` crop from an `accepted` crop and requires explicit abstention until a field-level acceptance rule has been validated.

### Field-scoped cost estimate

The validation domain contains 37 fields totaling approximately **252.38 acres**, equivalent to about **1,135 30 m pixel areas**. The current broad-domain bounding box is approximately 4.78 × 5.08 km, or about 26,969 30 m pixels.

For comparison, one HLS tile is 3660 × 3660 = 13,395,600 pixels. The validation fields therefore contain roughly **1/11,800** as many 30 m pixel areas as a full HLS tile.

At the published maximum shape, a float32 model tensor for ~1,135 field pixels, 704 time slots, and 12 inference features is approximately **36.6 MiB**. Reading the whole 3 km-domain bounding rectangle instead would raise that padded tensor to roughly **869 MiB**, so the preferred architecture is polygon/pixel scoped rather than bounding-box inference.

The already-materialized March–September 2026 window contains 18 HLSL30 and 64 HLSS30 scenes. Reading the published model bands plus Fmask once per granule would require approximately **912 band-window reads** for that known partial-current-year segment. The Transformer, however, requires the complete previous year plus all current-year observations from January 1 through the target date. At the released model's maximum 176 dates per sensor per year, the conservative absolute two-year planning bound is **7,040 band-window reads** (2 × [176 Landsat × 8 assets + 176 Sentinel-2 × 12 assets]). Actual scene counts should be lower and must be measured by the prototype.

The paper reports approximately three hours per full HLS tile on a dual-A100 server and notes that image loading accounts for about half of classification time. Because the Farm Watch field footprint is orders of magnitude smaller than a tile, the spike concludes that model arithmetic is unlikely to be the dominant cost; remote COG access, TensorFlow/model startup, and two-year scene discovery are the more likely fixed costs. This is a scaling estimate, not an empirical benchmark, because the model-artifact rights gate intentionally prevented executing the model in this unit.

### Neutral `current_crop_identity` contract

`farm-watch-current-crop-identity-contract.ts` reserves a neutral evidence product with:

- field ID and as-of date;
- method/model/source provenance;
- candidate crop and optional accepted crop;
- explicit state: `candidate_only | accepted | abstained | unavailable | blocked`;
- uncalibrated support diagnostics;
- abstention reasons;
- `scoring_performed=false`;
- `behavioral_inference_performed=false`;
- `harvest_inference_performed=false`.

A candidate prediction cannot masquerade as accepted crop identity, and no calibrated probability is allowed under the current contract.

### Spike exit

The bounded integration is technically feasible and small enough at the 37-field scale, but production execution remains blocked by two explicit gates:

1. verify the Zenodo trained-model artifact's reuse rights;
2. validate a field-level pixel-consensus / abstention rule before model predictions can become accepted current crop identity.

Harvest classification remains separately disabled.


## Trained-model rights gate — 2026-09-22

The rights gate for Zenodo record `10.5281/zenodo.14715402` was rechecked against the exact public record and Zenodo's own licensing guidance.

Verified facts:

- the record explicitly distributes the trained `.h5` model and training/evaluation data;
- the record is publicly downloadable;
- the record's rendered metadata does **not** expose a Rights/License section;
- Zenodo's guidance states that permission to reuse a specific record depends on the license conditions shown in the record's Rights section;
- the application-code repository is separately licensed Apache-2.0;
- the published paper is CC BY 4.0 and describes the model/code as publicly available for users;
- neither the repository's Apache-2.0 license nor the paper's CC BY 4.0 license is treated as automatically attaching to the separately deposited Zenodo model weights.

Disposition: **the trained-model artifact remains blocked for operational execution, vendoring, or redistribution**. Public availability and apparent author intent are useful context but do not substitute for an explicit artifact license.

The rights gate can be cleared by either:

1. an explicit license appearing on the Zenodo model record that covers the trained model artifact; or
2. direct written permission from the rights holder(s) covering Farm Watch's intended use.

No model download or inference was performed in this unit.
