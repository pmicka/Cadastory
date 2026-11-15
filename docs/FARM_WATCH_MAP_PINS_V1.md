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
- Placement requires the selected property’s valid mapped geometry: `ST_Covers` for on-property points or spheroidal `ST_DWithin` for points no farther than 100 ft (30.48 m) outside it. The same allowance applies beside interior rings; deep holes and distant points are rejected. Missing, invalid, empty or inactive boundaries fail closed. Exact user coordinates are retained.
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

The database runner refuses an existing `farm_watch` schema. Use an **empty scratch database created from template0**, with PostGIS available. It applies the original account/property migration, original confirmed-Google email allowlist migration, current role migration, and the new pin migration. Only the minimal Auth schema, Storage catalog and PostgREST claim helper bootstraps are synthetic; pin operations, privileges, triggers, authorization functions and concurrency are the actual migration SQL.

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

## Legacy fixtures join the annotation system

`20261114180725_farm_watch_fixture_map_pins_v1.sql` migrates only `flat-creek-deer-feeder-01` and `flat-creek-salt-block-01` on `validation-property-01` into ordinary shared pins. It preserves exact coordinates and supplied category colors, with concise titles and no provenance text in notes. Existing pins/revisions, source observations, account grants, RPC definition/ACLs and scientific products remain unchanged.

The historical points were submitted by the owner/operator before Auth attribution. This explicit migration binds them to the sole pre-existing active owner account with the explicit icon grant, verified in preflight. Missing or ambiguous binding aborts the transaction; arbitrary owner/admin roles do not acquire them. Creation calls the existing CRUD RPC under that trusted migration binding, retaining boundary, capability, creator and 500-pin protections. Claims are restored afterward. This is not a client-callable import capability.

A private forced-RLS `property_map_pin_fixture_links_v1` ledger, with no client/service-role grants, records each source key and pin ID. Pin deletion nulls the ledger pin ID; replay keeps the tombstone and preserves edits/moves instead of restoring an old position or resurrecting a point. Source observations remain historical evidence and are never synchronized from annotations. The new frontend removes their old map renderer and uses one pin layer/popup/editor, retaining historical technical summaries.

Apply this migration before publishing the paired frontend. No Edge redeployment or RPC change is needed. Refresh old clients after rollout to avoid temporarily seeing the old fixture renderer alongside a new pin. Roll back the frontend first if necessary; retain annotations and migration links rather than deleting user edits.

Verification: actual PostGIS migration and CRUD/security/concurrency suites; signed PostgREST HTTP tests against creator, viewer, other owner/admin, outsider and anonymous identities; original evidence/pin/ACL preservation; missing/ambiguous creator and invalid-source/boundary fail-closed cases; edited/deleted replay. Registry-integrity and architecture-doctrine assertions passed in a read-only production transaction during preflight. No hosted migration was applied while preparing the PR.

## Pin map categories

`20261114201618_farm_watch_map_pin_categories_v1.sql` adds bounded annotation metadata `category`: `auto` (default), `general`, `hunting`, or `farming-orchard`. Existing pins, including migrated fixtures, receive `auto` without changing their other fields, revisions or timestamps. No historical observation, grant, ownership/boundary guard or scientific product changes.

The existing authenticated RPC adds one optional `p_category` parameter and returns `category` with each pin. The previous overload is removed so PostgREST has one unambiguous interface. Older clients omit the parameter: create defaults to `auto`, update preserves the saved choice. Explicit `auto` restores icon-based defaults. The Edge handler accepts only the four named strings; null, objects and unknown values are rejected. Category changes use the same creator/property lock and expected revision as all other edits. Categories are visible to authorized property users, never a new access permission or an icon grant.

Automatic category inference belongs to the frontend's static icon catalog: hunting stands/blinds, cameras, feeders and mineral blocks use Hunting; crops and trees use Farming & Orchard; standard pins, pumps, containers, gates and bonfires use general. A manual choice takes precedence even when the icon changes. The Property Map shows all categories by default. Hunting shows general and Hunting; Farming & Orchard shows general and Farming & Orchard. Technical presentation starts with all three; existing preview restoration preserves manual filters. Visibility filtering happens over the already-loaded, property-scoped, bounded pin list.

Rollout: apply the category migration, deploy `farm-watch-map-pins`, then publish the paired frontend. New category fields require the updated handler; previous clients remain compatible throughout. The migration is transactional, revokes default function privileges before granting only `authenticated`, and preserves the table's private forced-RLS access pattern. No category index is needed for the existing 500-pin bounded property fetch. Roll back the frontend first and retain category data.

Verification: real PostGIS and signed HTTP category CRUD, omission/manual/automatic semantics, invalid values, unchanged legacy data/grants/guard/ACL, creator-only updates/moves/deletes, owner/admin/viewer denials, property isolation, concurrent edits, existing cap checks, and Edge validation. Hosted registry/doctrine assertions passed read-only during preparation; no production category migration or deployment was performed.

## Manual trail-camera view settings

`20261115055456_farm_watch_map_pin_camera_view_v1.sql` adds three nullable fields: `camera_bearing_deg` (integer 0–359 clockwise from true north), `camera_range_m` (finite ground meters 1.524–91.44, or 5–300 ft), and `camera_fov_deg` (integer full horizontal angle 10–120°). Storage permits either all three null or all three valid on a `trail_camera` pin. No user-supplied polygon/SVG or new geometry table is accepted. The browser derives a temporary cone; it is not operator evidence, a viewshed, actual detection coverage or an analytical product.

POST/PATCH accept these optional numeric fields; GET/mutation responses include them. The authenticated-only RPC appends corresponding optional `p_` parameters, removes the previous overload, and retains the exact creator/property/boundary/grant/revision/cap guards and empty search path. Edge verifies the JWT and calls SQL with that same JWT. New fields do not authorize another property member, owner or admin to mutate a camera they did not create. Restricted icon access remains required by the existing trigger, including after grant revocation.

Defaults come from the original [Moultrie EDGE operator manual](https://www.moultrie.com/media/wp-content/uploads/2022/08/MM-Edge-OpManual_FNL-81922.pdf): up to 80 ft detection/flash and 40° field of view. A supplied direction with omitted range/FOV uses 24.384 m/40°. Without a direction, new/legacy cameras remain unconfigured: responses include null bearing and proposed default range/FOV, and no shared cone renders. Range/FOV alone cannot configure an unconfigured camera. Omitted fields preserve existing settings on update; changing to a noncamera icon clears all three. The migration updates no existing rows, revisions, timestamps, scientific data or grant membership.

Release sequence: run SQL/HTTP/Edge tests and the paired frontend browser checks; merge/apply this migration, deploy `farm-watch-map-pins` with its existing configuration, then publish the paired frontend. Check the single RPC signature, same authenticated-only execution ACL and private table protections; run registry-integrity/architecture-doctrine gates. Do not change Auth/Gateway policy. Roll back the frontend first and retain stored settings and the compatible optional-argument RPC.

Verification: actual PostGIS checks migration preservation, full settings lifecycle, unconfigured/legacy omission behavior, numeric bounds (including NaN/infinities), storage constraints, icon transition, revoked grant, shared reads, creator-only direction/range/FOV/reposition/delete and stale revisions. Signed HTTP tests bypass Edge/UI to prove the same authorization, input and immutable identity/property restrictions. Two independent sessions race different camera settings and only one atomic revision wins. Edge tests check strict finite numeric types, bounds, unknown fields and legacy omission. Original CRUD, roles, fixture migration/replay, 500-pin race, private artifact restrictions and presentation tests remain in the same suite. Production preflight is read-only; no deployment occurs during PR preparation.

## Private pin photos

`20261115065720_farm_watch_pin_photos_v1.sql` adds a private `farm-watch-pin-photos` Storage bucket (WebP only, 512 KiB/object), a forced-RLS attachment table and a private deletion outbox. Existing pin fields/identities/revisions, icon grants and the original ownership/boundary guard are unchanged. The existing pin RPC signature remains compatible and adds `photo_count` to responses. Photos are user-authored attachments shared with authorized property accounts, never scientific/operator evidence or model inputs.

The authenticated-only `farm_watch_pin_photos_v1` RPC checks the same current Auth user, non-anonymous identity, allowlist, account role and selected active property as pins. Reads additionally bind the photo to that selected pin. Prepare/attach/delete require the original pin creator and expected pin revision, retaining restricted-icon grant rules. Mutations lock the pin, enforce four attachments, and increment the same pin revision, so concurrent metadata/photo writes cannot silently overwrite each other or exceed the cap. Photo identity/path is immutable; object names are derived from canonical property/pin/photo UUIDs. Attach accepts only an existing, freshly server-processed Storage object with matching private metadata; no arbitrary image URL, object path, dimensions, owner or property reassignment is accepted from a client. A restrictive bucket policy blocks direct anonymous/authenticated Storage access even if a broader permissive policy is later introduced.

`farm-watch-pin-photos` verifies the caller with `getUser`, then uses that same caller JWT for every authorization RPC. A service client performs only authorized private Storage uploads/downloads and bounded cleanup. It does not replace user authorization with service-role data access. No public or signed image URL is returned. Binary downloads require a fresh authorized API request and use `image/webp`, `nosniff` and `no-store`; the browser uses temporary Blob URLs cleared on close/context change/sign-out.

| Edge request | Behavior |
| --- | --- |
| `GET ?property=slug&pin=uuid` | Ordered metadata for at most four photos. |
| `GET ?property=slug&pin=uuid&photo=uuid` | Authorized private WebP bytes. |
| `POST ?property=slug&pin=uuid&revision=n` | Raw JPEG/PNG/WebP body, at most 4 MiB; process, store, attach; returns photo metadata and new revision. |
| `DELETE ?property=slug&pin=uuid&photo=uuid&revision=n` | No body; creator-only removal with revision check. |

The browser optionally downsizes camera files first for reliable mobile transfer (JPEG/PNG/WebP, originals up to 20 MiB). The server independently checks magic/dimensions before decoding (at most 8 MP/10,000 px side), rejects animation, uses pinned ImageMagick WASM `0.0.46` to auto-orient, strip metadata including EXIF location, and re-encode WebP at up to 1600 px. It reduces dimensions/quality further if needed to stay within 512 KiB. Originals are never stored. Dependencies and lockfile are committed. This follows Supabase's [WASM image manipulation approach](https://supabase.com/docs/guides/functions/examples/image-manipulation); native Sharp is not used.

Photo removal and pin/Auth-user/property cascades enqueue private object deletion. Photo writes and the updated pin DELETE handler drain up to 20 queued objects; failed Storage deletions remain retryable. Interrupted, unlinked uploads older than one hour are also collectible. Attach rejects queued objects and objects older than 15 minutes, preventing reattachment races with cleanup. The cleanup RPC is service-role-only and cannot remove a live attachment. If no later mutations occur, queued/orphaned objects stay private and inaccessible until the next mutation or an operator runs the same service-only cleanup; periodic unattended draining is an optional operational follow-up, not an access-control dependency. Never remove only Storage SQL rows: cleanup uses the Storage API to delete actual bytes.

Rollout after approval:

1. Apply this migration without replaying history. Verify private bucket settings, forced RLS/no direct attachment/outbox grants, restrictive Storage policy, authenticated-only photo RPC and service-only cleanup RPC. Run registry-integrity and architecture-doctrine gates.
2. Deploy the new `farm-watch-pin-photos` function and redeploy `farm-watch-map-pins`, including their shared `farm-watch-pin-photo-storage.ts`. Include the photo function's image module and dependency lockfile. Keep the existing Farm Watch gateway convention; both handlers validate caller JWTs themselves. Use the automatically supplied Supabase URL/anon/service-role environment variables; no service key enters frontend code. Confirm cold-start WASM initialization and an authorized JPEG upload/download plus anonymous/noncreator denial.
3. Publish the paired notebook client. It stages files/removals until Save. Metadata and successive Storage uploads are not one distributed transaction: partial failures report that the pin saved and retain remaining files with the latest revision for retry; ambiguous timeouts require cancel/reload. Roll back frontend first and retain stored attachments and the compatible APIs.

Verification includes real PostGIS/PostgREST authorization, creator/viewer/other-owner/admin/outsider/anonymous reads/mutations, missing/forged Storage references, count cap, stale revisions, independent concurrent attaches, private table/Storage RLS even under a broad policy, deletion cascades/outbox and preserved legacy data/grants/guard. The scratch fixture models only the Storage catalog; SQL/RLS/RPC execution is real, while object bytes are verified by actual WASM decode/resize/EXIF-orientation/metadata-strip/WebP tests. Edge tests cover JWT-first checks, streamed size/type limits, no privileged Storage before authorization, cleanup retry and conflict recovery. Browser tests cover real file decoding/preparation, four-file creation/editing, save/cancel/retry, lazy authenticated reads, timed/manual/swipe navigation and in-flight upload/download sign-out. Production preflight is read-only; no migration/deployment occurs during PR preparation.


## Creator-only private pins

`is_private` defaults to false for existing and new pins. The creator can switch
between shared and private with the eye control in the popup. In create/edit mode
the change is staged with other fields until Save; Cancel discards it. In view
mode it saves immediately using the same creator check and optimistic revision.
A private marker (and camera coverage, if present) renders at 70% opacity for its
creator; icon menu previews and touch target sizes stay unchanged.

The map RPC excludes private pin DTOs for every other account, including owners
and admins. Photo list/read RPCs apply the same predicate before Edge Storage
reads. Photo writes still require the original creator and revision. Table and
Storage access remain private; role/profile and icon grants are unchanged. An
omitted/null `p_is_private` preserves visibility on update, so older clients never
silently reshare private pins. Stored ownership/property IDs remain immutable.

Deploy `20261115084333_farm_watch_private_map_pins_v1.sql` and the updated
`farm-watch-map-pins` Edge function before publishing the matching frontend. The
migration atomically replaces map/photo RPC definitions and the previous map RPC
overload. Retain the Edge function's existing verified-user JWT flow and deployment
configuration. Photo Edge source does not change: it calls the protected photo
RPC before each Storage read. No bucket or object migration is needed.

Requests after a visibility change use the new access rule. A response already
received by another browser cannot be recalled; existing open maps need Reload
pins/a fresh load to replace their earlier snapshot. No new realtime service is
introduced. Closing the popup/signing out retains existing photo URL cleanup.

Verification: migration snapshots preserve every prior pin field, guard and icon
grant. An injected failure before photo RPC replacement proves the column and both
RPC changes roll back together; the regression rejects an intermediate commit. Real PostGIS and signed PostgREST tests cover private DTO/photo omission,
creator read/write/share/unshare, other viewer/owner/admin denial, scoped property,
legacy omission, anonymous/outsider denial, stale revisions and a privacy/edit
race. Edge tests reject nonboolean input; browser tests exercise desktop/touch
controls, private drafts/cones, Save/Cancel, conflict and signout races.


## Nearby pin placement

`20261115134418_farm_watch_map_pin_boundary_buffer_v1.sql` permits annotation
creation and movement up to **100 ft (30.48 m)** beyond the selected property’s
mapped footprint. The original `ST_Covers` rule still accepts on-property
locations, while `ST_DWithin` on schema-qualified PostGIS geography enforces a
real distance in metres for nearby locations. It applies to every disjoint
property piece and near interior hole edges; it is not an expanded bounding box.
Missing/invalid/empty geometry fails closed, and an archived property cannot be
used. The original property geometry is not changed or used as a snapping target.

The migration replaces only the existing private trigger function, preserving
its icon-grant and immutable identity/property/creator checks, timestamp/revision
behavior and ACL. RPC definitions, role grants, privacy/photos, data rows and
scientific/operator observations are unchanged. All ordinary metadata/privacy
and photo writes to a nearby pin must continue to pass the same placement guard.
A nearby annotation still belongs to its explicitly selected property and creator;
proximity to another property does not confer reassignment or editing access.

Apply the migration and redeploy the map-pins Edge handler’s updated validation
message before publishing the paired frontend instructions. There is no new
request field or RPC signature. The old handler remains wire-compatible; the
new message explains the 100 ft limit when a location is rejected. Existing
inside-property pins keep every field and revision.

Verification uses real PostGIS probes at Kentucky latitude on both sides of the
100 ft cutoff, holes/multipart shapes, missing/invalid/empty/inactive properties,
metadata/private updates, rejected distant moves, selected-property isolation,
creator/grant checks and unchanged snapshots/ACLs. Independent signed PostgREST
probes cover nearby create/edit/move/privacy/photos and restricted icons, plus
anonymous/outsider/noncreator/incorrect-property denial. The complete existing
SQL/HTTP/concurrency and Edge suites remain enabled. The paired turkey reference
does not impose fall feeder exclusion circles across mapped property boundaries
merely because an off-property feeder pin is now allowed.


## Small dot annotations

Migration `20261115162439_farm_watch_map_pin_dot_v1.sql` adds `dot` to the
table/RPC icon whitelist; the Edge handler accepts the same value. It uses the
existing explicit pin-icon grant, creator-only mutations, private visibility,
category/color/photo metadata, property buffer and optimistic revision contract.
Existing rows/grants/ACL/RLS and photo authorization are unchanged. No scientific
input or materialization is affected. The paired frontend renders it as a plain
colored circle at 30% of the normal symbol diameter, with its existing touch target.

Run the real PostGIS, signed PostgREST HTTP and Edge suites, apply this migration
and deploy `farm-watch-map-pins` before publishing the notebook dot client.
Verify the single authenticated-only RPC and the registry-integrity/architecture
gates. Roll back the frontend first and keep the compatible whitelist/storage so
saved annotations survive. Dot tests cover CRUD, legacy omission, camera-to-dot
conversion, categories, privacy, stale/noncreator rejection, grant checks and
unchanged table/guard/photo authorization; HTTP tests bypass the UI/Edge.
