# WMW Farm managed homepage photo uploads — staging v1

## Current release boundary

This unit establishes an **unpublished**, owner/admin-only staging service.
It is not a replacement for the current ten `wmw_XX.jpg` assets.

- Bucket: `farm-watch-home-gallery-uploads`, **private**, WebP only, maximum 512 KiB per optimized object.
- Database: `farm_watch.home_gallery_uploads_v1` (30 staged photos/property maximum) and `farm_watch.home_gallery_upload_deletions_v1` (retryable deletion outbox).
- Caller-authorized RPC: `public.farm_watch_home_gallery_uploads_v1`. Only current **owner/admin** roles may access unpublished uploads; viewers cannot even list staged media.
- Service-only cleanup RPC: `public.farm_watch_home_gallery_upload_cleanup_v1`.
- Edge service: `farm-watch-gallery-uploads`. Direct client access to the new bucket is blocked even if a broader Storage RLS policy is introduced later.
- Existing gallery RPC and existing public carousel still operate on the original 10-photo static catalog **without changes**.

**Deployment:** The private staging bucket and Edge service are already deployed. This corrective release updates only the gallery Edge handler and admin browser preprocessor. The original ten static photos and viewer slideshow are unchanged.

## Authenticated request contract

The client must use the current user's access token and the existing *publishable* project key, never a service-role key. The server re-verifies the Auth user and fresh Farm Watch role for each operation. The Edge handler must not accept caller-supplied Storage paths or owner IDs.

All requests use:
`/functions/v1/farm-watch-gallery-uploads?property=validation-property-01`

- `GET` lists staged photo metadata and the gallery revision.
- `GET ...&photo=<uuid>` returns authenticated WebP bytes for an existing staged photo (owner/admin only).
- `POST ...&revision=<integer>` accepts **browser-prepared WebP bytes** (content type `image/webp`; maximum 4 MiB request and 512 KiB canonical stored object). The updated administrator UI accepts JPEG, PNG and WebP source files up to 4 MiB and uses browser image decoding/canvas to orient, resize to at most 1600 px, flatten any transparency and encode an opaque WebP. This avoids the hosted Edge Function's 2-second CPU budget. The Edge service checks the live owner/admin authorization and revision before reading the file, parses its bounded RIFF container, rejects alpha/animation/lossless/unknown chunks, extracts one VP8 key frame and rebuilds the container without ICCP/EXIF/XMP metadata. This is **container-level normalization, not a complete VP8 bitstream decoder**; downloaded private images remain untrusted media. It then attaches via the authorized RPC and queues cleanup on failure. Raw JPEG/PNG sent directly to the Edge endpoint return HTTP 415; clients must update to the current admin page.
- `DELETE ...&photo=<uuid>&revision=<integer>` deletes the staged database attachment with revision check and queues its object for eventual Storage removal.

A successful attach/delete increments `farm_watch.home_gallery_v1.revision`, so concurrent admin metadata updates cannot silently overwrite one another. A prepared upload does **not** increment the revision; it is validated again at attachment time. The existing ten static assets cannot be deleted through this service.

Error behavior: `404` for unauthorized or unknown resources, `400` for invalid identity/input, `409` for stale revision/capacity conflicts, `413` for raw payloads exceeding 4 MiB, `415` for unsupported media type, and `503` for internal/transient Storage failures. Every response is `no-store`. Browser requests are restricted to the established Farm Watch origin allowlist.

## Privacy and publication boundary

All new media is **staged only** and intentionally invisible to both the existing `farm_watch_home_gallery_v1` slideshow projection and to viewer accounts. A future bounded product unit must:

1. Define publishing, ordering, visibility, caption/alt/focal metadata and rollback for new uploaded items without breaking the existing ten-photo identity contract.
2. Update the authenticated carousel and admin editor to support a mix of legacy and managed media, including authenticated image retrieval and account-switch cleanup.
3. Add owner/admin photo upload and remove controls with inline progress, conflicts, and retry UX.
4. Verify that unpublished/deleted uploads cannot be retrieved, and retained legacy assets are not lost. Public legacy website files remain accessible by their original URLs; visibility is a presentation setting, not file-level privacy.

Do not reuse the separate map-pin photo bucket: map pins have different ownership rules.

## Verification

- `tests/farm-watch-home-gallery-uploads.sql` runs in the existing isolated PostGIS harness. It tests viewer denial, authenticated role grants, storage policy fail-closed behavior, owner/admin staging, revision conflicts, property isolation, revocation, direct bucket denial, and queued cleanup. Fixtures roll back.
- `handler.test.ts` and `cleanup.test.ts` run in Deno using controlled RPC/storage mocks, covering auth and forbidden requests, body size, bad media types, immutable IDs/paths, conflict cleanup and metadata constraints.
- `optimized-webp.test.ts` verifies VP8-only containers, bounded image dimensions, metadata removal, malformed RIFF and animation/alpha rejection. The separate map-pin photo endpoint retains its ImageMagick tests and behavior.
- A real authenticated production session write/read/delete smoke test and policy advisory audit are required before exposing the service to end users.

No existing media bytes are changed by merging this PR.
