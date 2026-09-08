#!/usr/bin/env python3
"""Refresh Scout's authoritative USACE NID coverage for KY/IN/OH.

Research/identity support only. This collector widens raw NID coverage to the
three supported states so federal navigation assets referenced by task orders can
be resolved deterministically before any opportunity or relationship promotion.

Required env:
  SUPABASE_URL
  SUPABASE_SERVICE_ROLE_KEY

Optional env:
  SCOUT_NID_STATES=Kentucky,Indiana,Ohio
  SCOUT_NID_BATCH_SIZE=100
  SCOUT_NID_PAGE_SIZE=1000
  SCOUT_NID_ARCGIS_URL=<override>
"""
from __future__ import annotations

import hashlib
import json
import math
import os
import time
from datetime import datetime, timezone
from typing import Any

import requests

SOURCE_SLUG = "usace-nid"
DEFAULT_URL = "https://geospatial.sec.usace.army.mil/dls/rest/services/NID/National_Inventory_of_Dams_Public_Service/FeatureServer/0"
ARCGIS_URL = os.getenv("SCOUT_NID_ARCGIS_URL", DEFAULT_URL).rstrip("/")
STATES = [s.strip() for s in os.getenv("SCOUT_NID_STATES", "Kentucky,Indiana,Ohio").split(",") if s.strip()]
BATCH_SIZE = int(os.getenv("SCOUT_NID_BATCH_SIZE", "100"))
PAGE_SIZE = int(os.getenv("SCOUT_NID_PAGE_SIZE", "1000"))
SUPABASE_URL = os.environ["SUPABASE_URL"].rstrip("/")
SERVICE_KEY = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
TIMEOUT = (30, 180)
MAX_ATTEMPTS = 6
TRANSIENT_HTTP = {408, 425, 429, 500, 502, 503, 504, 520, 521, 522, 523, 524}
LOUISVILLE_LAT = 38.2527
LOUISVILLE_LON = -85.7585
PILOT_RADIUS_MILES = 100.0

session = requests.Session()
session.headers.update({"User-Agent": "Scout-Cadastory-USACE-NID-Regional/1.0"})
supabase = requests.Session()
supabase.headers.update({
    "apikey": SERVICE_KEY,
    "Authorization": f"Bearer {SERVICE_KEY}",
    "Content-Type": "application/json",
    "User-Agent": "Scout-Cadastory-USACE-NID-Regional/1.0",
})


def retry_delay(attempt: int, response: requests.Response | None = None) -> float:
    if response is not None:
        value = response.headers.get("Retry-After")
        if value:
            try:
                return min(60.0, max(1.0, float(value)))
            except ValueError:
                pass
    return float(min(30, 2 ** attempt))


def request_json(url: str, *, params: dict[str, Any] | None = None) -> dict[str, Any]:
    last_error: Exception | None = None
    for attempt in range(1, MAX_ATTEMPTS + 1):
        response = None
        try:
            response = session.get(url, params=params, timeout=TIMEOUT)
            if response.ok:
                payload = response.json()
                if isinstance(payload, dict) and payload.get("error"):
                    raise RuntimeError(f"ArcGIS error: {payload['error']}")
                return payload
            if response.status_code not in TRANSIENT_HTTP:
                raise RuntimeError(f"GET {url} HTTP {response.status_code}: {response.text[:1200]}")
            last_error = RuntimeError(f"transient HTTP {response.status_code}: {response.text[:400]}")
        except (requests.RequestException, ValueError, RuntimeError) as exc:
            last_error = exc
            if isinstance(exc, RuntimeError) and response is not None and response.status_code not in TRANSIENT_HTTP:
                raise
        if attempt >= MAX_ATTEMPTS:
            break
        time.sleep(retry_delay(attempt, response))
    raise RuntimeError(f"GET {url} failed after {MAX_ATTEMPTS} attempts: {last_error}") from last_error


def rpc(name: str, payload: dict[str, Any]) -> Any:
    url = f"{SUPABASE_URL}/rest/v1/rpc/{name}"
    last_error: Exception | None = None
    for attempt in range(1, MAX_ATTEMPTS + 1):
        response = None
        try:
            response = supabase.post(url, json=payload, timeout=TIMEOUT)
            if response.ok:
                return response.json() if response.text else None
            if response.status_code not in TRANSIENT_HTTP:
                raise RuntimeError(f"RPC {name} HTTP {response.status_code}: {response.text[:1200]}")
            last_error = RuntimeError(f"RPC {name} transient HTTP {response.status_code}: {response.text[:400]}")
        except requests.RequestException as exc:
            last_error = exc
        if attempt >= MAX_ATTEMPTS:
            break
        time.sleep(retry_delay(attempt, response))
    raise RuntimeError(f"RPC {name} failed after {MAX_ATTEMPTS} attempts: {last_error}") from last_error


def set_quality(status: str, reason: str, metadata: dict[str, Any]) -> None:
    rpc("internal_set_source_quality_gate", {
        "p_source_slug": SOURCE_SLUG,
        "p_status": status,
        "p_reason": reason,
        "p_validation_version": "usace-nid-regional-v1",
        "p_metadata": metadata,
    })


def content_hash(feature: dict[str, Any]) -> str:
    encoded = json.dumps(feature, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def miles_between(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r = 3958.7613
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def state_where() -> str:
    escaped = [s.replace("'", "''") for s in STATES]
    return "STATE IN (" + ",".join(f"'{s}'" for s in escaped) + ")"


def source_count(where: str) -> int:
    payload = request_json(f"{ARCGIS_URL}/query", params={
        "where": where,
        "returnCountOnly": "true",
        "f": "json",
    })
    count = payload.get("count")
    if not isinstance(count, int) or count <= 0:
        raise RuntimeError(f"NID count preflight invalid: {count!r}")
    return count


def fetch_features(where: str, expected_count: int) -> list[dict[str, Any]]:
    features: list[dict[str, Any]] = []
    offset = 0
    while offset < expected_count:
        payload = request_json(f"{ARCGIS_URL}/query", params={
            "where": where,
            "outFields": "*",
            "returnGeometry": "true",
            "outSR": "4326",
            "orderByFields": "OBJECTID ASC",
            "resultOffset": str(offset),
            "resultRecordCount": str(PAGE_SIZE),
            "f": "json",
        })
        page = payload.get("features")
        if not isinstance(page, list):
            raise RuntimeError("NID ArcGIS response missing features array")
        if not page:
            break
        features.extend(page)
        offset += len(page)
        print(f"NID fetch {len(features):,}/{expected_count:,}", flush=True)
        if len(page) < PAGE_SIZE and not payload.get("exceededTransferLimit"):
            break
    return features


def normalize_feature(feature: dict[str, Any], observed_at: str) -> dict[str, Any]:
    attrs = feature.get("attributes") or {}
    geom = feature.get("geometry") or {}
    native_id = str(attrs.get("NIDID") or attrs.get("FEDERAL_ID") or "").strip()
    if not native_id:
        raise RuntimeError("NID feature missing NIDID/FEDERAL_ID")
    lat = attrs.get("LATITUDE")
    lon = attrs.get("LONGITUDE")
    if lat is None:
        lat = geom.get("y")
    if lon is None:
        lon = geom.get("x")
    lat_f = float(lat) if lat is not None else None
    lon_f = float(lon) if lon is not None else None
    within_pilot = False
    if lat_f is not None and lon_f is not None:
        within_pilot = miles_between(LOUISVILLE_LAT, LOUISVILLE_LON, lat_f, lon_f) <= PILOT_RADIUS_MILES
    return {
        "source_slug": SOURCE_SLUG,
        "source_native_id": native_id,
        "source_url": ARCGIS_URL,
        "observed_at": observed_at,
        "content_hash": content_hash(feature),
        "parser_version": "usace-nid-regional-v1",
        "provisional_entity_type": "dam",
        "longitude": lon_f,
        "latitude": lat_f,
        "within_pilot_radius": within_pilot,
        "raw_payload": feature,
    }


def main() -> None:
    observed_at = datetime.now(timezone.utc).isoformat()
    where = state_where()
    try:
        expected = source_count(where)
        features = fetch_features(where, expected)
        by_id: dict[str, dict[str, Any]] = {}
        state_counts: dict[str, int] = {}
        navigation_count = 0
        for feature in features:
            item = normalize_feature(feature, observed_at)
            attrs = feature.get("attributes") or {}
            state = str(attrs.get("STATE") or "").strip()
            state_counts[state] = state_counts.get(state, 0) + 1
            purposes = str(attrs.get("PURPOSES") or "").lower()
            primary = str(attrs.get("PRIMARY_PURPOSE") or "").lower()
            locks = attrs.get("NUMBER_OF_LOCKS")
            if primary == "navigation" or "navigation" in purposes or (locks not in (None, "", 0, "0")):
                navigation_count += 1
            by_id[item["source_native_id"]] = item

        if len(features) != expected:
            raise RuntimeError(f"NID pagination mismatch: expected {expected:,}, received {len(features):,}")
        if len(by_id) != expected:
            raise RuntimeError(f"NID identity mismatch: expected {expected:,}, unique NID IDs {len(by_id):,}")
        missing_states = [s for s in STATES if state_counts.get(s, 0) == 0]
        if missing_states:
            raise RuntimeError(f"NID returned zero records for requested states: {missing_states}")

        items = list(by_id.values())
        inserted = 0
        for start in range(0, len(items), BATCH_SIZE):
            batch = items[start:start + BATCH_SIZE]
            inserted += int(rpc("internal_ingest_raw_records", {"records": batch}) or 0)
            print(f"NID upload {min(start+BATCH_SIZE,len(items)):,}/{len(items):,}", flush=True)

        stats = {
            "states": STATES,
            "source_count": expected,
            "unique_records": len(items),
            "new_raw_versions": inserted,
            "navigation_or_lock_records": navigation_count,
            "state_counts": state_counts,
            "arcgis_url": ARCGIS_URL,
        }
        set_quality(
            "healthy",
            "USACE NID KY/IN/OH regional refresh passed count, pagination, identity, and per-state coverage checks.",
            stats,
        )
        print(json.dumps(stats, indent=2, sort_keys=True), flush=True)
    except Exception as exc:
        try:
            set_quality("degraded", f"USACE NID regional refresh failed closed: {exc}", {"states": STATES, "arcgis_url": ARCGIS_URL})
        except Exception as quality_exc:
            print(f"quality-gate update also failed: {quality_exc}", flush=True)
        raise


if __name__ == "__main__":
    main()
