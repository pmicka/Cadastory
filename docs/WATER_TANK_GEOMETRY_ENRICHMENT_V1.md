# Water Tank Geometry Enrichment V1

Date: 2026-09-07

## Objective

Add source-backed water-tank morphology and operator-fit context so Scout can distinguish simple single-pedestal tower geometry from multi-leg/cross-braced geometry without conflating WRIS tank type with drone-cleaning difficulty.

## Core semantic separation

Scout now keeps these concepts distinct:

- native WRIS tank type
- engineering/visual/operator-confirmed morphology
- support geometry
- cross-bracing
- trusted operator cleaning assessment
- measured productivity outcomes (not yet available)

WRIS remains authoritative source history, but stronger morphology evidence can supersede its coarse type for geometry interpretation.

## Production objects

### `water.tank_geometry_evidence`

Multi-source evidence table keyed to canonical `water.tanks` assets.

Evidence kinds:

- `native_registry`
- `engineering_document`
- `visual_review`
- `operator_verified`

Morphology classes:

- `pedesphere`
- `fluted_column`
- `composite_elevated`
- `hydropillar`
- `waterspheroid`
- `multi_column_cross_braced`
- `standpipe`
- `ground_storage`
- `elevated_unknown`
- `other_unknown`

Support geometry is modeled independently as `single_pedestal`, `multi_column`, `ground_supported`, or `unknown`.

### `water.tank_cleaning_geometry_rules`

Stores trusted pilot-operator field expertise separately from structural evidence.

Current rules:

- single pedestal + no cross-bracing -> `favorable`
- multi-column + cross-bracing -> `challenging`

The current evidence state is `trusted_operator_expertise`, not measured outcome support.

No dollar, ROI, close-probability, or productivity multiplier is inferred.

### `water.v_tank_geometry_profile`

Selects the strongest current morphology evidence with precedence:

1. operator verified
2. visual review
3. engineering document
4. native registry

This preserves conflicts instead of overwriting source records.

### `scout.v_water_tank_geometry_research_queue`

Prioritizes unresolved elevated morphology:

1. active high-signal unknown elevated tanks
2. other active unknown elevated tanks
3. non-active unknown elevated tanks
4. already resolved geometry

The queue includes coordinates, current opportunity signal context, and a suggested research query.

### Opportunity context

`scout.get_opportunity_spine_projection(candidate_key)` now includes optional `water_tank_geometry` context.

`water_utility_portfolio.geometry_mix` now exposes resolved/favorable/challenging/unknown counts for the utility without changing opportunity ranking.

## Initial full-corpus enrichment

All 719 WRIS tanks now have structural-family evidence.

Current resolved profile baseline:

- 211 standpipes
- 95 ground-storage tanks
- 8 native hydropillar/single-pedestal profiles after stronger overrides
- 1 engineering-confirmed fluted-column tank
- 1 engineering-confirmed composite elevated tank
- 1 engineering-confirmed multi-column/cross-braced tank
- 396 generic elevated tanks still unresolved
- 6 other/unknown

Total morphology-resolved at V1 baseline: 317 / 719.

Operator geometry assessment baseline:

- favorable: 10
- challenging: 1
- unrated/unknown: remainder

Active morphology research backlog:

- 105 active opportunities need morphology resolution
- 74 are active high-priority unknowns

## Document-confirmed Kentucky examples

### Cecilia Tank — Hardin County Water District #2

- WRIS native type: `HYDROPILAR`
- engineering morphology: `fluted_column`
- support: single pedestal
- cross-bracing: none
- operator geometry assessment: favorable
- confidence: 0.99

This is an intentional example of stronger engineering morphology overriding the coarser WRIS label while preserving both evidence records.

### Springfield Rd Tank — Hardin County Water District #2

- WRIS native type: `HYDROPILAR`
- engineering morphology: `composite_elevated`
- support: single pedestal
- cross-bracing: none
- operator geometry assessment: favorable
- confidence: 0.96

### St. Johns Tank — North Shelby Water District

- WRIS native type: `ELEVATED`
- engineering morphology: `multi_column_cross_braced`
- support: multi-column
- cross-bracing: present
- operator geometry assessment: challenging
- confidence: 0.97

## Demo behavior

An active tank with unresolved elevated morphology now explicitly returns:

- `status = geometry_research_needed`
- native registry evidence and confidence
- `operator_cleaning_geometry_assessment = unrated`
- next step: engineering-document or visual morphology review

Scout does not guess from capacity or generic `ELEVATED` type.

A resolved tank returns morphology, support geometry, bracing status, evidence source/confidence, and trusted operator assessment.

## Evidence discipline

Industry/manufacturer documentation supports the structural distinction:

- pedesphere: spherical/spheroidal elevated tank on one cylindrical steel pedestal
- fluted column: elevated tank on one large-diameter steel support column
- composite elevated: elevated steel tank on one reinforced-concrete pedestal
- multi-column: elevated tank on multiple steel columns with cross-bracing
- standpipe: ground-supported cylindrical storage tank

The pilot operator's cleaning judgment applies to support geometry rather than to hydraulic storage category. Standpipes and ground-storage tanks are therefore not automatically rated by the pedesphere-vs-cross-braced rule.

## Safety and release checks

At release:

- `agent_contract.assert_tool_registry_integrity_v1()` passes
- `agent_contract.assert_architecture_doctrine_v1()` passes
- `agent_privacy.assert_rls_posture_v1()` passes
- new geometry tables have RLS enabled
- direct `anon` / `authenticated` / `PUBLIC` grants on geometry tables: 0
- unverified multifamily opportunity leaks: 0

## Next enrichment loop

Prioritize the 74 active high-signal unknown elevated towers. Use this evidence order:

1. engineering/project specifications
2. tank-specific first-party or public authoritative imagery
3. operator field verification

Visual review should classify only mechanically observable geometry (single pedestal vs multiple supports, cross-bracing, support count when visible). It must not infer exact engineering type from capacity alone.

Outcome instrumentation can later validate the trusted operator rule using setup time, cleaning duration, reposition count, inaccessible surface, operator difficulty, chemical use, and realized job economics.