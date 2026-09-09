# Scout Field Calibration Loop

**Status:** Design doctrine / research architecture. No user-facing workflow is required yet.

**Purpose:** Define a reusable human-in-the-loop calibration system for turning operator experience and completed-job outcomes into progressively stronger Scout evidence without allowing anecdote, attractive derived features, or experimental models to silently become production truth.

**Initial motivating use case:** Validate 3DEP-derived terrain/access/difficulty features against real operator experience.

---

## 1. Design intent

Scout should be able to learn from experienced operators in a way that is useful immediately, conservative epistemically, and increasingly general only when the evidence earns it.

The Field Calibration Loop is the bridge between:

- authoritative or high-quality source data,
- Scout-derived features and hypotheses,
- operator-specific field knowledge,
- observed job outcomes,
- shadow evaluation,
- and production decisioning.

Its central principle is:

> Human experience may calibrate Scout immediately, but it must remain scoped to the evidence actually observed. Generalization is earned through repeated, independent validation.

This is deliberately different from a conventional feedback/rating system. The goal is not simply to ask whether a recommendation was good. The goal is to preserve the relationship between:

1. what Scout predicted before a job,
2. what the operator expected or remembered,
3. what actually happened in the field,
4. which derived features plausibly explain the difference,
5. and how strongly that evidence is allowed to influence future decisioning.

---

## 2. Why this exists

A high-authority source does not automatically produce a high-authority business inference.

For example, USGS 3DEP may provide excellent elevation data. Scout might derive:

- local slope,
- elevation differential,
- terrain around a structure,
- plausible staging-area elevation,
- relative vertical working envelope,
- access or approach difficulty features.

Even if the source data are excellent, the derived business claims remain separate hypotheses:

- does the feature accurately describe the site?
- does it predict job difficulty?
- does it predict setup time?
- does it predict hose or fluid-delivery burden?
- does it predict price or profitability?
- does it matter equally across operators, rigs, structures, and service types?

The Field Calibration Loop prevents Scout from collapsing these distinct claims into one confidence score.

---

## 3. Evidence categories remain distinct

The loop must preserve Scout's existing evidence/provenance categories, including:

- observed fact,
- authoritative record,
- derived fact,
- heuristic,
- model inference,
- operator knowledge,
- hypothesis.

Operator testimony about a completed job is not automatically an authoritative universal rule.

A useful hierarchy for calibration evidence is:

### Site fact
A directly observed or authoritative property of a site or job.

Example: a measured or authoritative terrain/elevation value.

### Derived feature
A reproducible transformation of underlying evidence.

Example: elevation difference between a plausible staging zone and the working face.

### Operator observation
An operator's report about what occurred.

Example: "The rear grade made setup substantially harder."

### Outcome label
A structured representation of the operator observation for evaluation.

Example: `terrain_access_difficulty = high`.

### Hypothesis
A proposed relationship between one or more features and an outcome.

Example: large staging-to-workface elevation differential predicts setup difficulty.

### Validated relationship
A relationship that has passed the defined evidence and evaluation threshold for a specified scope.

### Production rule or feature
A validated relationship explicitly approved for a specified decisioning use.

The system must not silently promote one category into another.

---

## 4. Two complementary calibration paths

### 4.1 Retrospective calibration

Retrospective calibration solves the cold-start problem.

An operator may optionally identify a small number of memorable historical jobs, especially examples such as:

- unusually difficult,
- unusually easy,
- unexpectedly time-consuming,
- unexpectedly profitable or unprofitable,
- difficult because of height,
- difficult because of terrain,
- difficult because of staging/access,
- difficult because of hose or fluid routing,
- difficult because of surface/material conditions,
- or otherwise operationally distinctive.

Scout can then reconstruct the site from available historical/public data and compute candidate derived features.

The operator's recollection supplies the outcome label. The derived feature does **not** get to define its own success criterion.

Example:

`known difficult job -> reconstruct site -> derive 3DEP/access features -> compare predicted difficulty with operator-labeled outcome`

A useful initial operator calibration set may be small. Five to ten memorable jobs can be enough to identify whether a proposed feature is worth further testing, but not enough to establish a universal production rule.

Retrospective evidence should therefore be treated as calibration and hypothesis evidence unless stronger validation requirements are met.

### 4.2 Prospective post-job calibration

Prospective calibration is stronger because Scout can preserve the prediction made **before** the job outcome is known.

The sequence is:

1. Scout generates or stores a pre-job prediction/feature set.
2. The operator performs the job.
3. A lightweight post-job observation captures relevant outcomes.
4. Scout compares prediction with outcome.
5. The result becomes evaluation evidence for the specific feature/model version that produced the prediction.

Potential post-job observations include:

- actual difficulty,
- setup/staging difficulty,
- access constraints,
- height-estimate error,
- terrain effects,
- hose/run complications,
- water-source usefulness,
- unexpected material/surface behavior,
- chemical/product compatibility observations,
- actual labor/time versus expectation,
- equipment-specific constraints,
- and whether Scout's pre-job assumptions were materially wrong.

The user-facing collection mechanism is intentionally deferred. The architecture should be designed now so future UI can remain lightweight and optional.

---

## 5. Calibration is claim-specific, not source-specific

Maturity belongs to the **derived claim and intended use**, not merely to the source dataset.

Examples:

- 3DEP may be authoritative for elevation while `terrain_access_penalty` remains experimental.
- A building height estimate may be accurate enough for context but not accurate enough for pricing.
- Tower support morphology may be reliable while the claimed effect on job duration remains operator-specific.
- A chemical compatibility relationship may be supported scientifically but not yet safe for execution guidance for a particular product/application method.

Scout should therefore record maturity at a sufficiently granular level to distinguish:

`feature/version + target scope + intended decisioning use`

A feature can be production-grade for one use and experimental for another.

---

## 6. Suggested research maturity lifecycle

The Field Calibration Loop should integrate with a general research maturity model.

### Research
Source material, candidate features, and observations may be stored and inspected.

**Production ranking effect:** none.

### Supported
The underlying relationship has credible external or internal support, but Scout has not established local predictive validity.

**Production ranking effect:** none.

### Hypothesis
Scout has a testable, explicit claim and a defined evaluation method.

**Production ranking effect:** none.

### Validated
The claim has passed its specified retrospective/prospective evaluation threshold for a defined scope and version.

**Production ranking effect:** still none unless separately promoted.

### Production
The exact claim/use pair is explicitly approved to affect canonical decisioning.

**Production ranking effect:** allowed only within the approved scope/version.

### Deprecated
The feature/rule remains auditable for provenance and historical evaluations but no longer affects current decisioning.

**Production ranking effect:** none.

Promotion should be explicit and auditable. Data accumulation alone must not automatically change maturity.

---

## 7. Shadow evaluation before ranking promotion

Experimental features should be usable aggressively in a shadow lane without influencing canonical production ordering.

Scout should be able to preserve:

- production score/rank,
- experimental score/rank,
- feature/model version,
- evaluation population,
- pre-job prediction timestamp,
- later outcome labels,
- and measured lift/error/calibration.

This permits questions such as:

- Would 3DEP terrain features have improved job-difficulty prediction?
- Would building-height estimates have improved execution planning?
- Does the operator's stated morphology heuristic hold across completed tower jobs?
- Does Organic Growth Pressure discriminate actual cleaning need better than simpler baselines?
- Do material/chemistry features improve recommendations without increasing unsafe or incorrect guidance?

Shadow scoring is the preferred bridge between interesting research and production ranking.

---

## 8. Operator-specific knowledge versus generalized Scout knowledge

An operator's field experience can be valuable immediately without being universal.

The loop should support at least three scopes:

### Job-specific
The observation applies to one completed job/site.

### Operator-specific
Repeated evidence may justify a rule or calibration that improves decisioning for that operator, equipment configuration, service method, or operating style.

Example: a particular rig may tolerate elevation/head-pressure conditions differently from another operator's setup.

### Generalized Scout knowledge
Promotion beyond one operator should require independent corroboration and appropriate held-out validation.

A strong operator insight should not require being ignored while generalized validation is pending. It may influence that operator's decisioning if the system records the scope explicitly and the evidence supports that use.

Conversely, operator-specific evidence must not leak silently into universal ranking.

---

## 9. Initial 3DEP calibration program

3DEP is a strong first use case because the source data may be authoritative while the operational interpretation remains testable.

Candidate derived features should be versioned individually. Examples include:

- terrain slope near structure,
- elevation variance around footprint,
- likely staging-area elevation,
- staging-to-workface elevation differential,
- terrain asymmetry around structure,
- relative vertical working envelope,
- approach/access grade,
- and combinations with footprint/site-access geometry.

Initial evaluation should avoid assuming that generic slope is the useful feature. Retrospective operator examples may reveal that a more specific operational quantity—such as elevation differential between feasible staging and the working face—is more predictive.

A possible progression is:

`3DEP-derived hypothesis -> retrospective operator examples -> shadow model -> prospective pre-job predictions -> post-job outcomes -> independent/cross-operator validation -> scoped production promotion`

The source authority of 3DEP must never be used as a shortcut around this progression for derived operational claims.

---

## 10. Reuse across Scout

The loop should be generic enough to validate more than 3DEP.

Likely applications include:

### Building geometry
- height estimates,
- stories,
- footprint-derived hose distance,
- facade geometry,
- staging feasibility.

### Site access
- parking/staging assumptions,
- approach difficulty,
- gate/access constraints,
- equipment-to-workface route estimates.

### Water and fluid logistics
- water-source usefulness,
- hose-length assumptions,
- elevation/head implications,
- refill/logistics burden.

### Water-tower morphology
- single-pedestal favorable heuristic,
- cross-braced multi-column difficulty,
- geometry-specific time/cost implications.

### Materials and chemistry
- surface/material identification,
- cleaning-response observations,
- product/equipment compatibility,
- field outcomes versus modeled chemistry rules.

Chemistry should retain separate safety/regulatory gates. Field calibration may strengthen evidence but does not by itself authorize chemical execution advice.

### Organic Growth Pressure
- compare ecological/environmental pressure estimates against actual observed surface condition,
- compare physical plausibility against actual commercial cleaning demand,
- test whether the composite adds lift beyond simpler features.

### Lead value and commercial prediction
- quoted versus actual job value,
- conversion likelihood,
- actual profitability,
- buyer-route usefulness,
- timing-signal usefulness.

Commercial outcomes must remain distinct from physical/site-condition validation.

---

## 11. Data/contract principles for future implementation

No concrete schema is mandated by this document yet, but eventual implementation should preserve these concepts explicitly:

- operator/account scope,
- job/site identity,
- observation timestamp,
- whether evidence is retrospective or prospective,
- pre-outcome prediction snapshot,
- feature/model/rule version,
- outcome label and measurement semantics,
- operator commentary separately from normalized labels,
- confidence/uncertainty,
- provenance,
- applicability scope,
- maturity state,
- promotion/deprecation history,
- and whether a feature is allowed to affect production decisioning.

Prediction snapshots should be immutable enough to prevent hindsight from rewriting what Scout actually believed before the job.

Outcome labels should preserve unknown/uncertain states rather than forcing favorable or unfavorable conclusions.

Where an observation is subjective, the system should say so.

---

## 12. Privacy and exposure constraints

Historical and completed-job examples may contain commercially sensitive operator information.

Default posture:

- treat operator-provided calibration evidence as private to the operator/account unless explicitly authorized otherwise,
- do not expose one operator's job history to another,
- preserve tenant/user isolation,
- preserve Scout's anti-enumeration and authorization controls,
- distinguish generalized learned relationships from the private examples that helped validate them,
- avoid retaining source media when derived structured observations are sufficient,
- and do not make raw operator anecdotes model-visible unless required for the intended workflow.

Generalized rules should not require exposing the underlying private examples.

---

## 13. Human-in-the-loop design principle

The desired interaction is not "the human corrects the AI after it fails."

It is a cooperative loop:

- Scout brings scale, reconstruction, measurement, and consistency.
- The operator brings tacit field knowledge and ground truth that public datasets cannot fully observe.
- Scout preserves that human knowledge faithfully and narrowly.
- Repeated outcomes determine what deserves broader authority.

The operator should not have to become a data annotator to participate. Future user-facing interactions should favor small, meaningful prompts tied to memorable jobs or recently completed work rather than long questionnaires.

The value exchange should be visible: operator feedback improves their own planning/calibration first, while broader Scout rules are promoted only when independent evidence justifies them.

---

## 14. User-facing implementation is deferred

This document intentionally does **not** require building onboarding screens, post-job surveys, notification workflows, or feedback UI now.

When that work is eventually considered, candidate surfaces may include:

- an optional onboarding aside asking for a handful of memorable prior jobs,
- a lightweight post-job follow-up,
- a private calibration review surface,
- or an agent-mediated conversation that writes only explicit structured observations with the user's knowledge.

Those are product-design options, not current commitments.

In particular, Scout should not repurpose unrelated conversations or silently capture arbitrary chat as calibration evidence.

---

## 15. Promotion standard

No Field Calibration Loop feature should affect canonical opportunity ordering, lead value, service fit, buyer priority, execution difficulty, pricing, or "worth investigating" qualification merely because:

- the source dataset is authoritative,
- the feature is intuitively plausible,
- one operator strongly believes it,
- the model can calculate it reliably,
- or it produces attractive-looking maps/results.

Production influence requires explicit promotion of the exact claim/use pair after the relevant evidence gate has been satisfied.

Unknowns remain unknown. Failed hypotheses remain useful research history. Operator expertise remains valuable even when it is not universal.

That is the intended Field Calibration Loop: a durable mechanism for keeping the human in the loop while allowing Scout's decisioning to become progressively more evidence-backed over time.
