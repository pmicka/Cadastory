# Farm Watch materialization dependency manifest v1

Status: P0.1 canonical dependency contract  
Scope: all product kinds persisted in `farm_watch.property_materializations_v1`

## Purpose

Farm Watch materialization retention and scientific freshness are separate concerns.

An artifact can remain stored and unexpired while no longer representing the current dependency state. The canonical dependency manifest makes that state explicit and gives every materialized product one shared dependency contract.

This contract is intentionally neutral infrastructure. It does not add deer interpretation, scores, habitat claims, or new scientific datasets.

## P0.1 boundary

P0.1 establishes:

- one canonical registry for all 14 materialized product kinds;
- explicit internal, external, temporal, and state dependencies;
- one runtime dependency-manifest resolver;
- one generic materialization freshness path driven by that registry;
- transitive dependency propagation;
- synthetic dependency-identity overrides for internal regression testing;
- fail-closed handling for unregistered products and dependency graph errors.

P0.1 does **not** claim that external provider freshness is solved.

External scientific sources are registered with `resolution_status=contract_only` and `authoritative=false`. Their current P0.1 identity is a deterministic hash of the pinned source contract, not an observation of the provider's live revision or content state.

P0.2 is responsible for replacing those contract-only identities with authoritative or bounded provider-observation identities before cache reuse.

## Canonical product registry

| Product kind | Current contract | Canonical dependencies |
| --- | --- | --- |
| `terrain-analysis` | `phase3-dem-61x61-conditioned-flow-v2 / terrain-analysis-v2` | KyFromAbove Phase 3 DEM |
| `lidar-source-coverage` | `kyfromabove-stac-coverage-plan-v1 / lidar-source-coverage-v1` | KyFromAbove LiDAR STAC |
| `lidar-physical-structure` | `phase3-copc-physical-v3-multiasset / lidar-physical-structure-v1` | current LiDAR source-coverage artifact; Phase 3 COPC source |
| `leaf-off-woody-structure` | `leaf_off_structure_v1_2_7m / leaf-off-woody-structure-v1` | 2024 Phase 3 imagery; 2019 Phase 2 imagery; Phase 3 DEM |
| `structure-complementarity` | `current-leaf-off-lidar-complementarity-v4 / structure-complementarity-v1` | current LiDAR physical artifact; current leaf-off artifact |
| `landscape-structure-context` | `local500m-phase3-lidar-2024-leafoff-structure-v1 / landscape-structure-context-v1` | landscape domain; LiDAR STAC; Phase 3 COPC; 2024 imagery; Phase 3 DEM |
| `study-aligned-vegetation-height-context` | `wiemers-first-return-minus-ground-local500m-v1 / study-aligned-vegetation-height-context-v2` | landscape domain; LiDAR STAC; Phase 3 COPC |
| `terrain-form-permeability` | `barrier-aware-phase3-dem-terrain-form-permeability-v1 / terrain-form-permeability-v1` | landscape domain; landscape physical context; Phase 3 DEM |
| `spatial-edge-patch-context` | `local500m-canopy-field-structure-pattern-v1 / spatial-edge-patch-context-v1` | landscape domain; landscape physical context; resource-edge context; current landscape-structure artifact; NLCD TCC 2025 |
| `solar-terrain-context` | `terrain-horizon-canopy-context-v3 / solar-terrain-context-v1` | current terrain-form artifact; current spatial-pattern artifact; Phase 3 DEM; USGS 3DEP fallback; NLCD TCC 2025 |
| `solar-exposure-context` | `terrain-canopy-potential-solar-exposure-v1 / solar-exposure-context-v1` | current solar-terrain artifact; requested calendar date |
| `thermal-exposure-context` | `hrrr-solar-component-context-v1 / thermal-exposure-context-v1` | current solar-terrain artifact; exact admissible HRRR forcing identity/time/source hashes |
| `horizontal-visibility-context` | `barrier-aware-local500m-horizontal-visibility-v1 / horizontal-visibility-context-v1` | landscape domain; current landscape-structure artifact; current terrain-form artifact |
| `mast-capacity` | `bigmap2018-species-biomass-broad3000-v2 / mast-capacity-v1` | landscape domain; FIA BIGMAP 2018 species-biomass source |

## External dependency slots

P0.1 declares eight external-source identity slots:

- `external:kyfromabove-phase3-dem`
- `external:kyfromabove-lidar-stac`
- `external:kyfromabove-phase3-copc`
- `external:kyfromabove-phase3-imagery-2024`
- `external:kyfromabove-phase2-imagery-2019`
- `external:nlcd-tcc-v2025-6`
- `external:usgs-3dep-dynamic`
- `external:fia-bigmap-2018-species-biomass`

A product that depends directly or transitively on any contract-only external slot reports `authoritative_external_resolution_complete=false`.

That flag is not a stale judgment. It records that P0.1 cannot yet prove whether the remote provider changed in place.

## Dependency kinds

The manifest supports four dependency classes:

- **materialization** — another centrally persisted Farm Watch artifact, compared by the identity and/or artifact checksum declared in the registry;
- **context** — centrally resolved Farm Watch context such as landscape domain, landscape physical context, or resource-edge context;
- **state/temporal** — a requested date or exact-time state such as HRRR forcing;
- **external** — an authoritative external scientific source identity slot.

Internal materialization dependencies recurse through the same registry. This makes invalidation transitive instead of encoding a separate hand-maintained cascade.

## Runtime behavior

`farm_watch_get_current_materialization_ref_v1_internal(...)` remains the service-role freshness entry point.

It now delegates to the canonical manifest-based resolver. For each candidate artifact the resolver:

1. verifies the registered algorithm and output-schema contract;
2. checks ordinary expiration;
3. resolves the current dependency manifest;
4. compares the artifact's recorded dependency bindings with the current dependency state;
5. reports explicit reason codes when any binding differs;
6. keeps historical artifacts persisted rather than deleting them.

The runtime manifest has schema `farm-watch-materialization-dependency-manifest-v1` and its own deterministic identity hash.

## Synthetic identity testing

The override-aware resolver is internal and has no `anon`, `authenticated`, or `service_role` execution grant. It exists so migration/regression checks can replace a dependency identity without mutating real Farm Watch data.

P0.1 tests cover direct and transitive invalidation, including:

- a synthetic Phase 3 DEM identity change invalidating `terrain-analysis`;
- the same DEM change propagating through terrain/structure dependencies into `horizontal-visibility-context`;
- a synthetic Phase 3 COPC identity change propagating into `structure-complementarity`;
- a historical solar materialization remaining reusable for its matching date;
- that same historical solar materialization becoming stale when a transitive DEM identity changes;
- exact calendar-date and HRRR identity/hash comparison behavior.

No Flat Creek rows or external source data need to be edited for these tests.

## P0.2 handoff

P0.2 should implement the external identity resolvers in blast-radius order:

1. KyFromAbove LiDAR STAC / COPC;
2. KyFromAbove Phase 3 DEM;
3. NLCD TCC;
4. USGS 3DEP fallback;
5. fixed acquisition imagery and BIGMAP 2018.

Each resolver should prefer an immutable authoritative provider revision or release identity. Where none exists, use the smallest deterministic provider probe capable of detecting an in-place source change. Do not redownload full scientific rasters merely to prove freshness.

When P0.2 promotes an external slot from `contract_only`, the artifact's recorded dependency binding must also preserve the authoritative identity that was current at build time. That is what permits a later provider change to invalidate the retained artifact without destroying historical reproducibility.

## Interpretation boundary

This architecture governs whether a stored derivative corresponds to its declared inputs. It does not establish that the derivative is scientifically valid for deer inference, that a literature relationship transfers to Flat Creek, or that an available evidence product predicts deer use.
