# Farm Watch stable-product validity

November 13, 2026. This is a validity-policy correction, not a scientific model
change. Stable source snapshots must not require a user to rebuild or reverify
them merely because 30, 90, or 365 days elapsed.

## Evidence and boundary

Production inspection found expired retained artifacts for LiDAR coverage,
physical structure, landscape structure, study vegetation height, terrain form,
spatial patterns, solar terrain support, horizontal visibility, and structure
complementarity. Their latest October 30 expiry followed September 30 builds.
The old reader returned `expired` before checking whether dependencies still
matched. Age alone could therefore prevent reuse of unchanged evidence.

The smallest correction removes calendar expiry for these twelve products:

| Stable product | Validity inputs that remain enforced |
| --- | --- |
| terrain-analysis | DEM identity, property inputs, algorithm/schema |
| lidar-source-coverage | Authoritative LiDAR catalog identity and property inputs |
| lidar-physical-structure | Coverage, authoritative COPC identity, property inputs |
| leaf-off-woody-structure | Versioned imagery, DEM, property inputs |
| structure-complementarity | Physical and leaf-off materialization identities/hashes |
| landscape-structure-context | Domain, authoritative source identities, property inputs |
| study-aligned-vegetation-height-context | Domain, authoritative LiDAR identities, property inputs |
| terrain-form-permeability | Domain/physical context, DEM, property inputs |
| spatial-edge-patch-context | Domain, resource/structure context, canopy snapshot |
| solar-terrain-context | Terrain/spatial context, DEM/fallback/canopy source identities |
| horizontal-visibility-context | Domain, landscape structure, terrain form |
| mast-capacity | Domain and fixed BIGMAP inventory identity |

All entries also retain current algorithm/schema matching and recursive canonical
dependency validation. Historical source years and interpretation limitations
remain attached to each artifact. Stable does not mean the physical landscape
can never change; it means the stored analysis describes its identified source
snapshot until a relevant dependency changes.

## Behavior

- Stable worker contracts use `refreshDays: null`, producing `expires_at: null`.
- A database trigger enforces the same explicit allowlist for older workers.
- A migration clears only `expires_at` on existing allowlisted rows. It does not
  rewrite hashes, provenance, source dates, completion dates, summaries, or files.
- The canonical reader, authoritative resolver, build identities, completion
  rechecks, authorization, worker leases, and retry bounds remain unchanged.
- Source checks already happen automatically in the reader and claim/completion
  paths. No additional user verification or new refresh scheduler is introduced.
- Changed/missing property bindings, source corrections, changed model/schema,
  stale upstream contexts, and provider observation failures still reject reuse.
  Pre-contract artifacts do not become current through this migration.
- Daily solar and weather/thermal products retain date/forcing checks and their
  existing retention values. Unknown product kinds keep their expiry by default.
  SSURGO/hydrology provider snapshots and other context tables are outside this
  materialization policy and retain their existing source-refresh rules.

This removes calendar-driven rebuilds. It does not reduce authoritative provider
request latency or create an indefinitely cached provider identity. The separate
progressive-loading and hunting-reference changes isolate provider delays from
dashboard visibility and everyday hunting references.

## Verification

The focused Postgres suite seeds one-year-old artifacts, proves the old reader
rejects them solely for age, applies the migration, and verifies stable reuse.
It also verifies unchanged scientific/provenance/identity columns, compatibility
with old worker insert/update paths, preserved temporal/unknown expiry, source
drift/outages, boundary/acreage/SRID changes, model mismatch, and private access.
It executes the production candidate reader and comparison functions with a
controlled manifest fixture; it does not contact or impersonate live providers.
The existing authoritative resolver and dependency contract suites cover those
separate paths.

Run only against an empty scratch Postgres database:

```sh
python scripts/test-farm-watch-static-validity.py psql -h localhost -U postgres
deno test --allow-read supabase/functions/_shared/farm-watch-materialization-expiry.test.ts
```

## Deployment and remaining measurement

Before applying the migration, save an access-controlled export of `id`,
`product_kind`, and `expires_at` for the allowlisted rows for rollback.
Apply the new migration first. It centrally fixes persisted expiry even while old
workers remain deployed. Deploy the changed materialization/worker functions to
align their returned metadata, and let existing GitHub workflows pick up the
updated terrain script. No frontend deployment or artifact rebuild is required
for this policy. The existing terrain schedule can keep checking current source
identities; it reuses matching artifacts rather than rebuilding them for age.

After deployment, verify allowlisted expiry counts are zero, check canonical
reader statuses/reasons with real authoritative observations, and measure live
hydration. This policy is not evidence that every old artifact is current or
that provider latency or mobile dashboard timing meets its performance targets.

Rollback requires the saved prior per-row expiry values plus reverting the
trigger/worker policy. Reconstructing expiry from the new deployment time would
misrepresent original completion dates and must not be used as a rollback.
