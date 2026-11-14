# Farm Watch custom map pins v1

Shared, **unverified user annotations**, available to both guided and technical accounts. They never enter operator observations, evidence, analytics, materializations, or model inputs. The ruler is temporary browser state and has no backend interface.

## Authorization contract

Farm Watch currently authorizes accounts globally through `farm_watch_authorize_user_v1_internal` and `farm_watch_get_account_role_v1_internal`, then selects an active property by slug. It has **no property-membership relation**. Pins deliberately reuse that existing scope; this change does not create a new access model. Each request must select exactly one property. If property membership is introduced later, the pin RPC must adopt the same membership predicate before that new contract ships.

`farm_watch.property_map_pins_v1` is private, with forced RLS, no client policies and no grants to `PUBLIC`, `anon`, `authenticated`, or `service_role`. The sole data interface is `public.farm_watch_map_pins_v1`, executable only by `authenticated`. Its SECURITY DEFINER privilege is needed to access existing private authorization/property tables. It uses an empty search path, checks `auth.uid()`, existing Auth user presence, non-anonymous identity, allowlist and recognized account role on every call. Creator identity is derived in SQL; no creator argument exists. Direct calls to the RPC have the same checks as Edge calls.

`farm-watch-map-pins` verifies the bearer token using `auth.getUser(token)` and forwards the **same user JWT** to the RPC using the anon key. It uses no service credentials. CORS follows the existing Farm Watch origin allowlist, but authorization does not depend on Origin. Server responses omit creator UUIDs/emails; labels are `You` or `Property member` and `can_edit` is calculated server-side. Account roles/presentation previews never confer mutation permission over another person's pin.

The RPC scopes every query to the selected active property. Updates/deletes additionally require creator equality. An immutable-identity trigger prevents changing ID, creator, property or creation timestamp even through privileged maintenance writes. Updates and deletes lock the row and compare the supplied integer revision. A successful update increments revision and maintains `updated_at`. A stale revision raises `PT409` (HTTP 409), not a retryable database serialization failure. Clients must reload and review conflicts; they never silently retry mutations.

## Data and limits

- WGS84 `geometry(Point,4326)` is authoritative; coordinates in responses are derived from it. No duplicated latitude/longitude columns.
- Required trimmed title: 1–100 Unicode characters; optional notes: at most 2,000 characters. Text remains plain text, including literal markup. Frontend rendering uses DOM text/value properties.
- Coordinates must be finite, longitude −180…180, latitude −90…90. Point type/SRID, nonempty and valid geometry are enforced.
- `ST_Covers` against the stored valid property boundary is mandatory. Exterior edges and hole edges are allowed; hole interiors and outside points are rejected. Missing/invalid boundaries fail closed. There is no off-property exception in v1.
- At most 500 pins per property. Creates serialize on the property row before counting, so concurrent creates cannot exceed the cap. A list is therefore bounded to 500 records (maximum approximately 1 MB of notes). HTTP mutation bodies are bounded to 16 KiB before parsing.
- Foreign keys link the canonical property and Auth user; deletion of either cascades. Pins have UUID IDs and property/creator indexes.

## API

Edge URL: `/functions/v1/farm-watch-map-pins?property=<selected-property-slug>`.

| Method | JSON request | Response |
| --- | --- | --- |
| GET | none | `{pins: [...]}` |
| POST | `title, notes?, longitude, latitude, color?` | `{pin: {...}}`, HTTP 201 |
| PATCH | `id, revision, title, notes?, longitude, latitude, color?` | `{pin: {...}}` |
| DELETE | `id, revision` | `{deleted: true}` |

Unexpected mutation fields, including ownership/property fields or arbitrary GeoJSON, are rejected. Errors are bounded and omit database details. No public/anonymous listing or cross-property list endpoint exists.

## Verification

The database runner refuses an existing `farm_watch` schema. Use an **empty scratch database created from template0**, with PostGIS available. It applies the original account/property migration, original confirmed-Google email allowlist migration, current role migration, and the new pin migration. Only the minimal Auth schema and PostgREST claim helper bootstrap are synthetic; pin operations, privileges, triggers, authorization functions and concurrency are the actual migration SQL.

```sh
python scripts/test-farm-watch-map-pins.py psql -d pins_test
deno check supabase/functions/farm-watch-map-pins/index.ts
deno test supabase/functions/farm-watch-map-pins/handler.test.ts \
  supabase/functions/farm-watch-private/handler.test.ts \
  supabase/functions/_shared/farm-watch-presentation-policy.test.ts
```

The runner checks real role denial, shared reads, viewer creation, owner/admin noncreator mutation denial, property isolation/reassignment, immutable ownership, plain-text preservation, input/geometry/boundary policy, revoked/missing/anonymous identities, creator editing/moving/deleting, stale revisions, and **two concurrent independent sessions with exactly one winning revision**.

The CI workflow additionally starts PostgREST v13.0.7 against this scratch database. `scripts/test-farm-watch-map-pins-http.py` sends signed fixture JWTs directly to the RPC and attempts direct table writes and extra ownership/property arguments. This proves bypass attempts fail at the actual HTTP/database boundary. It accepts loopback URLs only. Its JWT secret is a public, test-only constant, never a deployment credential. Edge handler tests separately verify session validation, request bounds, field rejection, user-scoped RPC arguments, CORS, and non-sensitive error mapping.

Local verification: Postgres 17.7/PostGIS 3.5, PostgREST 13.0.7; real database/HTTP suites passed, including concurrent edits and concurrent creates at the 500-pin cap; 30 pin/private-startup/presentation handler tests passed; Edge entrypoint typecheck passed. Supabase CLI v3.1.0 security advisors passed on the scratch database after setting the test helper's search path. Frontend interaction/startup evidence is in the paired notebook PR. No production security check or deployment was performed.

`supabase db lint` was attempted against the scratch database but could not run because the image lacks the PostgreSQL 17 `plpgsql_check` extension (its current Alpine package targets PostgreSQL 18). This is a lint-tool limitation, not a passing lint result. The actual SQL branches, constraints, authorization and concurrency were executed by the database and HTTP suites above.

## Deployment and rollback

1. Review and apply `20261114001403_farm_watch_property_map_pins_v1.sql` through the normal migration process. Do not replay historical migrations against production.
2. Deploy `farm-watch-map-pins` with existing Supabase Auth JWT handling and `SUPABASE_URL` / `SUPABASE_ANON_KEY`. Follow the current Farm Watch Edge deployment convention for gateway JWT verification; the handler always validates the bearer token and SQL always derives identity from it. No service credential is required.
3. Before publishing the paired notebook frontend, verify the migrated interface using authorized test accounts: viewer create/read, second authorized account read, noncreator owner/admin direct update/move/delete rejection, stale revision conflict, boundary rejection and unauthenticated denial. Check Supabase security advisors for the new table/function. The authenticated RPC is intentionally exposed; the table remains private.
4. Publish the paired frontend, then smoke-test desktop and an actual Android device with the keyboard open, profile switching, reload and sign-out. Browser touch emulation does not substitute for physical-device acceptance.

Do not merge/deploy until the security-sensitive checks pass. Roll back the frontend utility first; the existing map continues to function if pin loading fails. Disable the Edge function and revoke RPC execution if needed. Retain the annotation table/data during rollback; do not drop user pins as a routine rollback step. No analytical product needs rebuilding.

## Persistent colors

`20261114015747_farm_watch_map_pin_colors_v1.sql` adds presentation-only `color`, constrained to a lowercase six-digit hex value. Existing rows gain the original gold (`#ffd27e`) without changing identity, title/notes, geometry, timestamps or revision. Responses include `color` for all authorized viewers. Recoloring uses the same creator check, boundary validation, row lock and revision as any other edit; it grants no additional authority.

The RPC adds a final optional `p_color` argument. Its previous signature is dropped and replaced atomically to avoid ambiguous PostgREST overloads; execute privileges remain authenticated-only. Omitted/null color means gold on create and preserve-current-color on update, so older clients cannot erase someone's selected color. The Edge handler rejects non-string, non-hex, non-seven-character colors (including CSS/markup payloads and trailing newlines) and forwards normalized lowercase hex. Direct RPC calls receive equivalent SQL validation.

Deploy this migration and the updated `farm-watch-map-pins` Edge function **before** publishing the color-picker frontend. The existing frontend continues to work during that rollout. Rollback the frontend first; leave the metadata column and compatible RPC in place so saved colors are retained.

The existing real PostGIS/PostgREST suites now cover colored create/read/update, another user's rejected recolor, stale color conflicts, malformed colors, omitted-color compatibility, and an existing-row upgrade fixture proving that other data/revisions remain unchanged. The original ownership, property isolation, geometry, concurrent edits and cap tests continue to run. The UI removes repetitive annotation disclaimers; this remains an unverified annotation table outside all scientific/evidence products.

## Account-restricted icon styles

`20261114042305_farm_watch_map_pin_icons_v1.sql` adds bounded presentation-only `icon`: `pin` (default), `deerstand`, `water_pump`, `container`, `trail_camera`, `gate`, `bonfire` and `crop`. Existing rows keep every prior field/revision and gain `pin`. The new tenth optional RPC argument `p_icon` defaults to standard on create and preserves the existing icon when omitted/null on update. The old nine-argument signature is atomically replaced, retaining authenticated-only execution. The Edge handler accepts only the named values and never accepts a capability or creator identity from the client.

The private, forced-RLS `farm_watch.map_pin_icon_users_v1` table stores explicit Auth-user grants, with no client/service-role table privileges or public grant-management RPC. The migration bootstraps the **sole existing active owner account** once; if zero or multiple active owners exist it grants nobody. Future owner/admin assignments do not inherit this capability. Deployment must verify that exactly the intended account was seeded. Additional grants require a trusted database administrator; presentation previews, email/user metadata and claimed browser roles cannot enable it. Deleted Auth accounts lose their grant through referential integrity.

The selected-property list response adds only a boolean `capabilities.can_use_pin_icons`. Reads remain shared and creator-only mutations remain enforced. Selecting a nonstandard icon requires the explicit account grant in the RPC, and the existing table guard independently checks every nonstandard insert/update. Revoking the grant blocks subsequent symbol creates/updates even for an existing session; creators may still delete their pins. Plain pins remain available to every authorized property account. Neither the icon nor its label changes a pin into a verified fixture, water/crop observation, scientific feature or model input.

Rollout: run the real SQL, signed-HTTP and Edge suites, apply the icon migration, verify the intended singleton grant and authenticated/anonymous privileges, then deploy `farm-watch-map-pins` **before** publishing the paired notebook frontend. No privileged credentials enter the browser. An old server response simply keeps the new selector hidden. An old client editing a symbol preserves it through the optional-argument contract. Roll back the frontend first and retain the column/compatible RPC; do not delete annotations. The explicit grant can be removed to disable new symbol use without changing account roles.

Coverage includes every symbol, existing-row upgrades, legacy updates, shared symbol reads, unauthorized/viewer/other-owner/admin denials via direct RPC and signed HTTP, attempted self-grants, malformed values, revocation, stale revisions, and the original ownership/transfer/property/geometry/concurrency/cap checks. Catalog checks verify private grants, forced RLS, one RPC signature and the empty search paths.

## Supplied SVG symbol pack

`20261114132556_farm_watch_map_pin_symbol_pack_v1.sql` extends the existing icon allowlist with `corn_feeder`, `salt_mineral_block`, `tree`, `pop_up_blind` and `ladder_stand`. The seven previous names and standard `pin` are unchanged. The table constraint and authenticated CRUD RPC use the same expanded values; the Edge handler accepts only those named values. No asset URLs, SVG strings or arbitrary HTML are accepted from clients.

This migration does not update pin data/revisions, account grants, roles, geometry rules, the mutation guard or RPC signature. The same explicit single-account capability gates all nonstandard choices. Other authorized property users can view saved symbols and still cannot edit another creator's pins. Owner/admin roles alone remain insufficient. Feeder/mineral/tree/stand pictures on a custom pin remain user annotations, never scientific or verified operator observations.

Rollout: run the real PostGIS, signed HTTP and Edge tests; merge/apply this migration and deploy `farm-watch-map-pins` before publishing the paired notebook frontend. Verify the existing grant membership is unchanged. The paired frontend retains the supplied SVG sources, uses their artwork for fixtures/pins, keeps saved colors and supports native category defaults for newly selected symbols. Roll back the frontend first and retain persisted icon metadata. The added tests cover unchanged existing rows/grants/ACL/guard, all five added values, legacy edits, direct authenticated owner/admin/viewer denials, shared read-only symbols, conflicts and the original authorization/geometry/concurrency suite.
