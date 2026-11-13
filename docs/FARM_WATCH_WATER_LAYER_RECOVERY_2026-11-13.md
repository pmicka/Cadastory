# Farm Watch water-layer recovery

## Findings

The USGS 3DHP Flowline `/MapServer/50` query requested `onsurfacelabel`, which is
absent from the current published layer schema. The service returned ArcGIS 400
`Failed to execute query`, causing the stored hydrology snapshot to remain partial.
After its existing partial-refresh interval, the private read correctly withheld
the outdated snapshot. Viewer switches still looked enabled without explaining
the missing geometry.

A bounded public-area probe reproduced the error with the old field list. The
same geometry query with the supported fields returned 27 features. The fix drops
only the unsupported optional field. Feature identities, geometry selection,
buffers, normalization, spatial-reference handling, bounded retries, cache procedure,
authorization, and interpretation limits are unchanged. Surface-state metadata
that the provider does not supply remains unknown.

The terrain product independently failed canonical freshness with
`kyfromabove_phase3_dem_identity_changed`. This was an actual dependency mismatch,
not calendar expiry. Existing retained products contained 12 paths, but could not
be represented as current until regeneration and authoritative revalidation.

## Production recovery

- Re-ran the existing scheduled terrain job in
  [run 43463736295](https://github.com/pmicka/Cadastory/actions/runs/43463736295).
  It completed at 23:37:44 UTC on November 13. Canonical validation with an
  authoritative DEM observation now reports available with no stale reasons and
  12 modeled paths. No source checks or scientific calculations were bypassed.
- Retrieved all three hydrology sources using the existing refresh implementation
  and supported field list. All three returned available, with 221 normalized
  features. Saved the previous snapshot, then wrote the authoritative observations
  through `farm_watch_replace_hydrology_v1_internal` using the existing privileged
  maintenance procedure. Its service-role guard was retained; the administrative
  execution context was transaction-local, with no authorization/schema changes.
- Verified hydrology status available, identity current, and all sources available.
  The normal 1 km display filter includes 11 stream lines, 13 water areas, and
  12 wetland areas. None intersect the selected parcel; the nearest mapped stream
  is approximately 33 m away. These nearby features must not be relabeled as
  on-parcel water or present-day water observations.

Recovery backups and verification data are held in access-controlled workspace
scratch files, not published property geometry. The main endpoint still needs this
query fix deployed so a later refresh does not reintroduce the invalid request.

## Regression and companion UI

The provider-contract regression checks requested fields against the observed
Flowline schema and preserves the existing spatial query. The companion notebook
change adds local loading/empty/partial/stale/failure feedback and resource-specific
read retries beside stream, wetland, contour, and drainage controls. It withholds
stale/failed-source geometry, keeps independent available layers usable, and tests
actual Leaflet canvas output for viewer and technical-account guided preview.

No new refresh system, schema migration, role, materialization identity, or
scientific model is introduced. Existing ordinary reads remain read-only;
requesting map visibility or checking a failed layer does not recompute data in
the browser or perform an unauthorized refresh.
