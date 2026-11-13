# Farm Watch hunting reference loading

## Production findings

On November 13, two `context=deer` requests took 15,096 ms and 17,874 ms of backend execution and returned about 2,389,714 bytes. Authoritative USGS 3DEP observation consumed 12,147 ms and 16,619 ms respectively. These are server execution measurements, not browser paint or mobile transfer times.

The guided At a glance renderer uses dated biological context, daylight planning, and normalized hunting regulations. It clears the technical evidence inventory after rendering. Nevertheless, opening that guided section requested the entire deer-science response and waited for provider observations and evaluation. Technical evidence placeholders were also present in the initial HTML without a technical presentation marker, making them flash in guided mode before the module rendered.

Production retention metadata also confirms that the latest retained LiDAR source/physical, study vegetation height, landscape structure, terrain form, spatial pattern, solar-terrain, horizontal visibility, and structure-complementarity products expired on October 30. Terrain analysis has a newer unexpired artifact. Solar/thermal long retention dates do not establish current date/forcing/dependency freshness. The canonical recursive reader must continue to decide availability.

## Implementation

Add `context=hunting` to the existing authenticated private endpoint. It uses the same canonical deer-context, requested biological scenario, and deterministic solar readers as the scientific response. It returns only the fields the guided reference consumes: date/time, season/diel phase, regional breeding timing, per-component availability, today/tomorrow solar events, and interpretation limits. It does not call soils, hydrology, the evidence reader, external identity probes, or the evaluator.

The response owns a separate `hunting_reference` field, so a late lightweight response cannot overwrite the technical science context and its evidence. Its availability describes the visible dated reference; the original full-context status is retained separately. Unavailable biological/timing data stays partial/unavailable; stale retained clock events and biological content are withheld.

The frontend independently requests `context=hunting` and `context=rules` on the existing private endpoint. The rules response projects the same normalized local hunting authority used by the regulatory endpoint, with no FAA, zoning, or flood refresh. The full regulatory endpoint remains available for its own technical section. Guided presentation does not request the unused full scientific response. Technical presentation still loads the unchanged `context=deer` response, with all authoritative freshness checks, and can retry that resource independently. Static technical evidence/caveat markup is hidden by presentation before module hydration. Failed science requests terminate their placeholders; stale technical status explains that rechecking does not rebuild expired products.

Hunting rules have a targeted retry inside Timing & rules. Missing/unavailable regulatory data is not treated as a known empty season schedule. Available sunrise/sunset remain visible while legal hours are explicitly unavailable. Map and reference data remain usable during scientific failures.

No source identity, materialization expiration, scientific equation, scoring model, worker authorization, or canonical artifact identity changes are included.

## Regression and rollout

Backend tests cover compact responses with large unused source datasets, authorization for the new mode, unavailable biological context, zero external/evidence/physical calls on the lightweight path, and existing scoped/legacy science parity. The ordinary regulatory endpoint also refreshes FAA data after a five-minute TTL and can perform external GIS reads; that work is not needed for normalized hunting rules. Browser tests cover no guided science request, no technical placeholder flash, failed hunting/reference retries, independent rules retries, and failed technical science retaining the quick reference.

Deploy the backend function **before merging/deploying the frontend**, since the preceding backend rejects the new context selector. Preserve the deployed function's gateway setting and its existing in-function authorization. No migration is required. After rollout, collect real `context=hunting` Server-Timing, response bytes, and browser visibility measurements; local synthetic fixtures are not production timing claims.

## Existing maintenance still required

Rechecking a retained artifact is not rebuilding it. Expired products must be renewed by the existing protected GitHub OIDC materializers in dependency order, with authoritative observations at claim and completion. Do not extend retention dates in SQL or label retained artifacts current to remove a warning.

The existing materialization dependency manifest is the ordering authority. Relevant workflows already exist for LiDAR physical, study vegetation height, landscape structure, neutral primitives, solar/thermal, horizontal visibility, and structure complementarity. Except for terrain's scheduled renewal, those workflows currently use the repository's owner-authenticated operations issue triggers. Product renewal is a separate protected maintenance operation; this UI/API change does not add another scheduler or bypass the workflow gate.
