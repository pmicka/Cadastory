# Farm Watch home weather

The guided home card uses the existing private endpoint with `context=weather`.
It returns a compact everyday NWS point forecast after the same session,
allowlist, normalized role, and active-property checks as bootstrap. All three
authorized roles may read this guided-safe resource. Missing stored coordinates
return unavailable; no geocoding or hardcoded property coordinates are added.

The forecast is not a weather-station observation. It supplies the current hourly
period, up to six upcoming 12-hour periods, wind, precipitation probability, source,
update time, timezone, and an explicit expiry. Null precipitation remains unknown,
not zero. The frontend displays three upcoming periods and appropriate local SVG
icons. This data never enters the scientific evidence stack, forcing identities,
deer evaluator, materializations, or any biological model.

The NWS `/points` lookup discovers the hourly and 12-hour grid endpoints; those
two requests run concurrently. Requests identify Farm Watch through User-Agent,
accept GeoJSON, validate the exact HTTPS NWS origin/grid path, and disallow
redirects. One 8-second deadline covers discovery, requests, and JSON bodies.
Hourly/daily source failures are isolated, with partial results retained.
Forecasts issued more than 12 hours ago or with invalid/missing period values are
withheld. The hourly period must actually contain the current time.

Successful forecasts are reused for at most 15 minutes, bounded further by the
current period end and source-age limit. The instance-local cache holds at most
20 locations; simultaneous reads for the same point share one request. Partial
and failed responses are not cached, so targeted retries can recover missing
details. Authorization runs on every request before cache access. Point mapping
is re-observed with each refresh, following NWS guidance that grid mappings can
occasionally change. No database, additional scheduler, or credentials are needed.

Reference: [NWS API Web Service](https://www.weather.gov/documentation/services-web-api).

Validation includes authorized/denied reads for owner/admin/viewer, absence of
scientific RPC/provider calls, bounded cache/in-flight deduplication, partial
failures, invalid provider URLs, missing values, old forecasts, missing coordinates,
and timeout handling. A live public-area probe at 38.2,-84.9 returned an available
forecast in 622 ms with a 2,050-byte projection on November 13, 2026. This is a
development source check, not a measured authenticated production endpoint or
mobile-dashboard performance result.

Deploy the private function before the companion notebook frontend: older backend
versions reject the new selector. Preserve its existing gateway setting and
server-side authentication. No schema migration is required. Rollback the frontend
first; the new backend remains compatible with existing selectors.
