# WMW Farm homepage gallery catalog v1

## Scope and rollout

This unit adds an **authenticated metadata backend** for the existing ten homepage
photos. It does not upload, delete, move, or re-encode any images, create a Storage
bucket, or alter the current public asset URLs. The website and its existing
slideshow remain unchanged until a separate frontend integration is released.

The catalog is seeded **only** for active Farm Watch property
`validation-property-01`, the WMW property already selected by the frontend.
The seed preserves `[6,1,2,3,4,5,7,8,9,10]`, with `wmw_06.jpg` initially first.
Do not infer this legacy static asset collection for additional properties.

## Database boundary

- `farm_watch.home_gallery_v1` holds a property-scoped, monotonically increasing
  revision.
- `farm_watch.home_gallery_photos_v1` maps existing legacy photo numbers 1–10
  to order, caption, alt text, focal percentages, and visibility.
- Both tables are in the private schema, RLS is enabled/forced, and **no browser
  role has direct table permissions**.
- `public.farm_watch_home_gallery_v1` is the sole browser data interface.
  Its SECURITY DEFINER privileges are intentionally narrow. It verifies
  `auth.uid()`, rejects anonymous identities, checks that the auth user still
  exists, calls the existing Farm Watch authorization and current account-role
  functions, and requires an active selected property on **every call**.
- Owners/admins can list and mutate. Viewers can list **visible photos only**.
  Unauthorized callers receive a not-found-style error, not private metadata.
  Browser-side viewer preview does not affect authorization.
- Mutations lock the property gallery row and use an expected revision, returning
  SQLSTATE `PT409` on conflicts. Order changes are one atomic transaction.
  Hiding the final visible photo is rejected.

## Browser RPC contract

The browser must use the existing authenticated Supabase client, never a
service-role key. Example:

```js
const { data, error } = await client.rpc('farm_watch_home_gallery_v1', {
  p_property_slug: 'validation-property-01',
  p_action: 'list',
})
// { revision: 1, can_edit: true|false, source: 'legacy-static-v1', photos: [...] }
```

Every photo row contains `photo_number`, `sort_index`, `caption`,
`alt_text`, `focal_x`, `focal_y`, and `is_visible`. The source is
**legacy static**; resolve `photo_number` to the existing local
`assets/wmw/photos/wmw_XX.jpg` paths, not to a caller-provided URL.

Update one existing photo (only supplied fields change):

```js
await client.rpc('farm_watch_home_gallery_v1', {
  p_property_slug: 'validation-property-01',
  p_action: 'update',
  p_photo_number: 6,
  p_expected_revision: currentRevision,
  p_caption: 'Gathering area',
  p_alt_text: 'Outdoor gathering area near trees',
  p_focal_x: 50,
  p_focal_y: 40,
  p_is_visible: true,
})
```

Empty caption/alt strings clear those fields. Reorder the **full** ten-photo
catalog, including hidden photographs:

```js
await client.rpc('farm_watch_home_gallery_v1', {
  p_property_slug: 'validation-property-01',
  p_action: 'reorder',
  p_expected_revision: currentRevision,
  p_order: [6,1,2,3,4,5,7,8,9,10],
})
```

On conflict, refetch `list` and let the administrator reconcile changes;
never silently overwrite another edit. The cover is the first visible photo in
the resulting order, **not** a separate mutable object.

## Next units (not yet implemented)

1. Add a client-side gallery editor to `pmicka/notebook` that consumes this
   RPC, uses textContent rather than HTML injection for captions/alt labels,
   implements accessible ordering/visibility controls, and handles 409
   conflicts. Deploy the migration **before** enabling those controls.
2. Make the authenticated carousel consume the ordered *visible* catalog with
   a safe static fallback while avoiding eager image loads.
3. Design managed image uploads, a dedicated private Storage bucket, server-side
   image processing and bounds, authenticated retrieval, and deletion cleanup.
   Existing map-pin photos have different ownership semantics and must not be
   reused as homepage files. Only after this stage should delete/upload buttons
   be exposed. Keep legacy media intact until migration and rollback are tested.

## Verification

- Existing ten static image files remain unchanged.
- SQL regression: `tests/farm-watch-home-gallery.sql` (requires the existing
  Farm Watch authorization test fixtures and helper function
  `public.pin_test_expect_error` from the map pin tests).
- Test owner, admin, viewer, unauthorized, anonymous, revoked, stale revision,
  invalid/duplicate order, invalid text/focal fields, and property isolation.
- Before rollout, run this SQL regression in an **isolated test database** and
  perform authorized role-based HTTP/RPC smoke tests. No live edit or migration
  deployment is implied by merging this PR.
