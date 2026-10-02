# Farm Watch Deer Interaction Registry v1

Status: evaluator-integrated implementation candidate  
Species: white-tailed deer (`Odocoileus virginianus`)  
Contract: `farm-watch-deer-interaction-registry.ts`  
Evaluator: `deer-science-context-v6`

## Purpose and boundary

An interaction is a source-supported biological structure in which the meaning or direction of a relationship depends on another covariate or state. Two measurements being available at the same property is co-occurrence, not interaction. A relationship record may describe one covariate; the interaction registry records only published statistical interactions, conditional effects, state-dependent relationships, or clearly documented joint mechanisms.

Interaction structure is evidence in its own right. Farm Watch does not infer an interaction from ecological plausibility, shared location, or correlated availability. No registry row contains an arithmetic formula, weighted sum, product term for Farm Watch values, score, or transferred coefficient.

The interaction evaluator consumes the existing relationship evaluations and their #5 state-gate results. It does not create a second state resolver. A state mismatch yields `not_applicable`; unresolved biological state yields `blocked_by_state`; missing measurements or bindings yield `insufficient_input`; required measurements below their declared fidelity floor yield `blocked_by_fidelity`. Only a relationship whose gates, required bindings, and fidelity pass can yield `eligible_context`.

## Registered structures

| ID | Ledger | Source-supported form | Current limiting condition |
|---|---|---|---|
| `FW-I01` | `FW-D01` | Summer thermal, vegetation, forage and activity-period statistical interaction | Operative temperature, forage index, woody-canopy and study activity-period measurements are not all aligned; blocked by fidelity |
| `FW-I02` | `FW-D03` | Winter snow response modified by dense-conifer availability | Winter state and daily snow/minimum-temperature plus broad-scale conifer availability required; solar context remains distinct |
| `FW-I03` | `FW-D09` | Winter woody-twig-density association changes with landscape agriculture amount | Study-aligned agriculture and woody twig-density measurements unavailable; blocked by fidelity |
| `FW-I04` | `FW-D08` | Female space-use response conditional on corn identity and field stage/harvest | Current field-level corn stage is unavailable; known corn alone is insufficient |
| `FW-I05` | `FW-D10` | Localized hunting-event response depends on diel period | Dated stand event, study vulnerability geometry and hunter-occupancy-aware diel period required |
| `FW-I06` | `FW-D11` | Adult-male risk response depends on hunter activity, food and diel period | Measured hunter-use intensity is unavailable; no “5×” transfer |
| `FW-I07` | `FW-D12` | Sex modifies risk/food response | Explicit adult sex, measured pressure and study-relevant food context required |
| `FW-I08` | `FW-D07` | Fall relationship requires exact-year realized mast state | Static mast capacity is context only; annual survey state is exact-year/regional and not property abundance |
| `FW-I09` | `FW-D14` | Terrain and road responses vary with landscape context and dispersal state | Requires explicit juvenile-male dispersal state; terrain is mechanism-only and cannot satisfy the required study measurement |
| `FW-I10` | `FW-D06` | Male breeding-season movement depends on age class and source-defined date/phase | Age and regional phase gates apply; source age bins and Wisconsin timing do not transfer |

Every record preserves source and Farm Watch measurement IDs, gates, scales, temporal scope, conditional form, coefficient disposition, blocked conditions, and transfer limitations. `FW-I08` keeps mast capacity as context and requires `FW-M17` annual state. `FW-I04` keeps crop identity and stage as distinct required variables. No property-conditioned interaction hypothesis is configured by v1.

## Activation order

1. Resolve the relationship's state gate using the existing #5 state framework. Do not infer sex, age, movement, individual reproductive state, or source-specific season from habitat covariates.
2. Require every registered study measurement. A missing covariate blocks the whole interaction; other available covariates may remain visible as context.
3. Compare each binding's existing #3 fidelity class with the interaction's minimum fidelity. Mechanism-only context cannot satisfy a required variable. The interaction is no stronger than its weakest required measurement.
4. Require the linked ordinary relationship evaluation to be active. A separately active property-conditioned hypothesis does not activate or validate an interaction.
5. Emit literature-supported context only. `decision_actionable`, `behavioral_probability_inferred`, and `scoring_performed` remain false.

Seasonal and event examples:

- Unknown movement state blocks `FW-I09`; a known resident or non-juvenile-male state is not applicable.
- `FW-I08` is fall/female gated and cannot activate from static mast capacity alone or a prior-year report.
- `FW-I04` with corn identity but unknown stage remains insufficient input; a known non-corn crop is not applicable.
- A regional breeding window never creates an individual reproductive state.
- A calendar season is not automatically equivalent to the biological seasons used by a source paper.

## Co-occurrence and unsupported combinations

The FW-D15 source reports separate dispersal outcomes: spring natal-range agriculture relates to dispersal probability; agriculture in potential paths relates to distance; and actual paths avoid agriculture while selecting near rivers/streams. Farm Watch keeps these as separate relationships and does not register agriculture × riparian geometry as an interaction term. The relationship direction for R19 is therefore `mixed`; its source-supported covariates are not represented as a statistical interaction. R31 likewise keeps its seasonal and potential-path associations separate and uses `mixed` direction.

The following combinations remain unregistered absent specific source evidence: mast capacity × bedding; terrain form × hunting pressure; ridge × wind; saddle × rut; south-facing slope × cold front; edge density × mast capacity; visibility × terrain as bedding quality; concealment × thermal context as security cover; crop identity × nearest water as feeding location; and generic solar exposure × deer use. Their variables can remain separate context where an existing product supports them.

FW-D24 is a seasonal edge/aspect guardrail, not “more edge × fall = positive.” Its source biological seasons and forest-edge protocol are not reproduced by the current generic season and edge products, so it is not registered as an activatable interaction. FW-D25 keeps neonatal horizontal visibility, fawn concealment and vegetation height separate; its null concealment result and distinct field protocols do not support a visibility × concealment security-cover interaction.

## Coefficients, conditioning and scores

All v1 interaction rows set coefficient transfer to `not_authorized`. The registry preserves conditional direction or source interaction form in words; it does not transfer numeric model parameters. Property covariates alone do not establish deer behavior. V1 sets property-conditioning eligibility to `not_configured`, and the evaluator always reports `property_conditioned_interaction_hypothesis_available: false`.

The interaction output is separate from ordinary relationship output and property-conditioned deer-use claims. There is no interaction score, deer score, behavioral probability, or decision-actionable interaction in this contract.

## Evaluator output

`interaction_evaluation` exposes registered and evaluated counts, eligible-context, blocked-by-state, blocked-by-fidelity, insufficient-input and not-applicable counts, plus IDs grouped by status. Each row returns its supporting ledgers, relationships and measurement bindings; state and fidelity results; interpretation and limitations; property-conditioning state; and explicit false scoring, probability and actionability flags.

Regression tests cover unknown and incompatible state, mechanism-only fidelity, missing covariates, annual mast versus static capacity, crop identity versus stage, movement-state gating, FW-D24/FW-D25 guardrails, coefficient transfer and score absence, and separation from property-conditioned deer-use hypotheses.
