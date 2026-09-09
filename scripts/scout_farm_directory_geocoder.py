#!/usr/bin/env python3
"""Bounded U.S. Census geocoder for Scout Kentucky livestock-farm evidence.

Reads livestock candidates only through the service-role queue RPC and writes
results only through the validated farm-directory geocode upsert RPC.
No third-party map data or transient response bodies are persisted.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import time
from typing import Any

import requests

SUPABASE_URL = os.getenv("SUPABASE_URL", "").rstrip("/")
SERVICE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "")
MAX_RECORDS = max(1, min(int(os.getenv("SCOUT_FARM_GEOCODE_MAX_RECORDS", "300")), 500))
QUEUE_SIZE = max(1, min(int(os.getenv("SCOUT_FARM_GEOCODE_QUEUE_SIZE", "100")), 500))
TIMEOUT = (15, 45)
USER_AGENT = "Scout-Cadastory-Farm-Geocoder/1.1 (+U.S.-Census-public-geocoder)"
CENSUS_URL = "https://geocoding.geo.census.gov/geocoder/locations/onelineaddress"
KY_BBOX = (-89.75, -81.75, 36.35, 39.35)  # lon_min, lon_max, lat_min, lat_max

API = requests.Session()
API.headers.update({
    "apikey": SERVICE_KEY,
    "Authorization": f"Bearer {SERVICE_KEY}",
    "Content-Type": "application/json",
    "User-Agent": USER_AGENT,
})
HTTP = requests.Session()
HTTP.headers.update({"User-Agent": USER_AGENT, "Accept": "application/json"})


def rpc(name: str, payload: dict[str, Any] | None = None) -> Any:
    if not SUPABASE_URL or not SERVICE_KEY:
        raise RuntimeError("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required")
    r = API.post(f"{SUPABASE_URL}/rest/v1/rpc/{name}", json=payload or {}, timeout=TIMEOUT)
    r.raise_for_status()
    return r.json()


def zip_from_address(address: str) -> str | None:
    m = re.search(r"\b(\d{5})(?:-\d{4})?\b", address or "")
    return m.group(1) if m else None


def score_match(row: dict[str, Any], match: dict[str, Any]) -> tuple[bool, float, str]:
    components = match.get("addressComponents") or {}
    state = str(components.get("state") or "").upper()
    expected_state = str(row.get("state_code") or "").upper()
    if expected_state and state != expected_state:
        return False, 0.0, "state_mismatch"

    coords = match.get("coordinates") or {}
    try:
        lon = float(coords["x"])
        lat = float(coords["y"])
    except (KeyError, TypeError, ValueError):
        return False, 0.0, "missing_coordinates"

    if expected_state == "KY":
        lon_min, lon_max, lat_min, lat_max = KY_BBOX
        if not (lon_min <= lon <= lon_max and lat_min <= lat <= lat_max):
            return False, 0.0, "outside_kentucky_bbox"

    expected_zip = zip_from_address(str(row.get("address") or ""))
    matched_zip = str(components.get("zip") or "")[:5]
    confidence = 0.86
    if expected_zip and matched_zip == expected_zip:
        confidence = 0.93
    elif expected_zip and matched_zip and expected_zip != matched_zip:
        confidence = 0.80
    return True, confidence, "accepted"


def geocode(row: dict[str, Any]) -> dict[str, Any]:
    address = " ".join(str(row.get("address") or "").split())[:100]
    if not address:
        return {"status": "no_match", "reason": "empty_address"}

    last_error = None
    for attempt in range(3):
        try:
            r = HTTP.get(
                CENSUS_URL,
                params={"address": address, "benchmark": "Public_AR_Current", "format": "json"},
                timeout=TIMEOUT,
            )
            if r.status_code in (429, 500, 502, 503, 504):
                raise requests.HTTPError(f"transient census status {r.status_code}")
            r.raise_for_status()
            payload = r.json()
            matches = ((payload.get("result") or {}).get("addressMatches") or [])
            accepted: list[tuple[float, dict[str, Any]]] = []
            for match in matches:
                ok, confidence, _ = score_match(row, match)
                if ok:
                    accepted.append((confidence, match))
            if not accepted:
                return {"status": "no_match", "reason": "no_acceptable_census_match"}
            confidence, match = max(accepted, key=lambda item: item[0])
            coords = match["coordinates"]
            return {
                "status": "matched",
                "matched_address": match.get("matchedAddress"),
                "lon": float(coords["x"]),
                "lat": float(coords["y"]),
                "confidence": confidence,
            }
        except (requests.RequestException, ValueError, KeyError) as exc:
            last_error = f"{type(exc).__name__}: {exc}"
            if attempt < 2:
                time.sleep(1.5 * (attempt + 1))
    return {"status": "error", "reason": last_error or "unknown_error"}


def save(row: dict[str, Any], result: dict[str, Any]) -> Any:
    status = result["status"]
    return rpc("internal_upsert_farm_directory_geocode_result_v2", {
        "p_candidate_id": row["candidate_id"],
        "p_evidence_id": row["evidence_id"],
        "p_observed_address": row["address"],
        "p_matched_address": result.get("matched_address"),
        "p_lon": result.get("lon"),
        "p_lat": result.get("lat"),
        "p_status": status,
        "p_confidence": result.get("confidence"),
        "p_county_name": None,
    })


def self_test() -> None:
    row = {"state_code": "KY", "address": "1040 Hick Hardy Road, Cynthiana, KY 41031"}
    good = {
        "coordinates": {"x": -84.29, "y": 38.39},
        "addressComponents": {"state": "KY", "zip": "41031"},
    }
    bad_state = {
        "coordinates": {"x": -84.29, "y": 38.39},
        "addressComponents": {"state": "OH", "zip": "41031"},
    }
    assert zip_from_address(row["address"]) == "41031"
    assert score_match(row, good)[0] is True
    assert score_match(row, good)[1] == 0.93
    assert score_match(row, bad_state)[0] is False
    print("farm directory geocoder self-test passed")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return

    seen: set[str] = set()
    stats = {"matched": 0, "no_match": 0, "error": 0, "processed": 0}
    while stats["processed"] < MAX_RECORDS:
        queue = rpc("internal_get_livestock_farm_geocode_queue", {
            "p_limit": min(QUEUE_SIZE, MAX_RECORDS - stats["processed"]),
        }) or []
        fresh = [row for row in queue if str(row.get("candidate_id")) not in seen]
        if not fresh:
            break
        for row in fresh:
            if stats["processed"] >= MAX_RECORDS:
                break
            candidate_id = str(row["candidate_id"])
            seen.add(candidate_id)
            result = geocode(row)
            save(row, result)
            status = result["status"]
            stats[status] += 1
            stats["processed"] += 1
            print(json.dumps({
                "candidate_id": candidate_id,
                "name": row.get("name"),
                "status": status,
                "reason": result.get("reason"),
                "matched_address": result.get("matched_address"),
            }, sort_keys=True), flush=True)
            time.sleep(0.08)
    print("summary=" + json.dumps(stats, sort_keys=True), flush=True)


if __name__ == "__main__":
    main()
