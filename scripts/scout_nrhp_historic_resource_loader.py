#!/usr/bin/env python3
"""
Load National Register of Historic Places spatial data into Scout.

Requirements:
  - SUPABASE_URL
  - SUPABASE_SERVICE_ROLE_KEY

Optional:
  - SCOUT_NRHP_STATES=KY,IN,OH
  - SCOUT_NRHP_BATCH_SIZE=500

The loader uses the National Park Service public ArcGIS FeatureServers for
National Register points and polygons. Historic designation is preserved as
context only; the database keeps individually-listed buildings distinct from
buildings that merely fall inside a listed historic district.
"""

from __future__ import annotations

import json
import os
from datetime import date, datetime, timezone

import requests

SUPABASE_URL = os.environ["SUPABASE_URL"].rstrip("/")
SERVICE_KEY = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
STATE_CODES = {
    value.strip().upper()
    for value in os.getenv("SCOUT_NRHP_STATES", "KY,IN,OH").split(",")
    if value.strip()
}
BATCH_SIZE = int(os.getenv("SCOUT_NRHP_BATCH_SIZE", "500"))
TIMEOUT = (30, 180)
PAGE_SIZE = 2000

if not 1 <= BATCH_SIZE <= 1000:
    raise SystemExit("SCOUT_NRHP_BATCH_SIZE must be between 1 and 1000")

STATE_NAMES = {
    "KY": "Kentucky",
    "IN": "Indiana",
    "OH": "Ohio",
}

POINT_LAYER = (
    "https://services.arcgis.com/UnTXoPXBYERF0OH6/ArcGIS/rest/services/"
    "NPS_National_Register_of_Historic_Places/FeatureServer/0"
)
POLYGON_LAYER = (
    "https://services.arcgis.com/UnTXoPXBYERF0OH6/ArcGIS/rest/services/"
    "NPS_National_Register_of_Historic_Places_Polygons/FeatureServer/24"
)

SUPABASE_SESSION = requests.Session()
SUPABASE_SESSION.headers.update(
    {
        "apikey": SERVICE_KEY,
        "Authorization": f"Bearer {SERVICE_KEY}",
        "Content-Type": "application/json",
        "User-Agent": "Scout-Cadastory-NRHP-Loader/1.0",
    }
)
NPS_SESSION = requests.Session()
NPS_SESSION.headers.update({"User-Agent": "Scout-Cadastory-NRHP-Loader/1.0"})


def rpc(name: str, payload: dict | None = None):
    response = SUPABASE_SESSION.post(
        f"{SUPABASE_URL}/rest/v1/rpc/{name}",
        json=payload or {},
        timeout=TIMEOUT,
    )
    if not response.ok:
        raise RuntimeError(
            f"RPC {name} failed: HTTP {response.status_code}: {response.text[:1200]}"
        )
    return response.json()


def arcgis_where(code: str) -> str:
    name = STATE_NAMES.get(code, code)
    escaped_name = name.replace("'", "''")
    escaped_code = code.replace("'", "''")
    return f"State='{escaped_name}' OR State='{escaped_code}'"


def fetch_layer(layer_url: str, state_code: str):
    offset = 0
    while True:
        params = {
            "where": arcgis_where(state_code),
            "outFields": "*",
            "returnGeometry": "true",
            "outSR": "4326",
            "f": "geojson",
            "resultOffset": str(offset),
            "resultRecordCount": str(PAGE_SIZE),
            "orderByFields": "OBJECTID",
        }
        response = NPS_SESSION.get(f"{layer_url}/query", params=params, timeout=TIMEOUT)
        response.raise_for_status()
        payload = response.json()
        if "error" in payload:
            raise RuntimeError(f"NPS ArcGIS query failed: {json.dumps(payload['error'])[:1000]}")
        features = payload.get("features") or []
        if not features:
            return
        for feature in features:
            yield feature
        if len(features) < PAGE_SIZE:
            return
        offset += len(features)


def parse_cert_date(value: object) -> str | None:
    if value in (None, ""):
        return None
    if isinstance(value, (int, float)):
        try:
            return datetime.fromtimestamp(float(value) / 1000.0, tz=timezone.utc).date().isoformat()
        except (OverflowError, OSError, ValueError):
            return None
    digits = "".join(ch for ch in str(value) if ch.isdigit())
    if len(digits) >= 8:
        try:
            return date(int(digits[:4]), int(digits[4:6]), int(digits[6:8])).isoformat()
        except ValueError:
            return None
    return None


def state_code_from_value(value: object, fallback: str) -> str:
    if value is None:
        return fallback
    text = str(value).strip()
    if len(text) == 2:
        return text.upper()
    lowered = text.lower()
    for code, name in STATE_NAMES.items():
        if lowered == name.lower():
            return code
    return fallback


def normalize_feature(feature: dict, geometry_kind: str, fallback_state: str) -> dict | None:
    geometry = feature.get("geometry")
    props = feature.get("properties") or {}
    if not geometry:
        return None

    object_id = props.get("OBJECTID")
    reference_number = props.get("NRIS_Refnu") or props.get("PROPERTY_I")
    stable_id = str(reference_number or object_id or "").strip()
    if not stable_id:
        return None

    resource_type = str(props.get("ResType") or "unknown").strip().lower()
    state_code = state_code_from_value(props.get("State"), fallback_state)
    source_native_id = f"{geometry_kind}:{stable_id}"
    nara_url = props.get("NARA_URL")
    source_url = str(nara_url).strip() if nara_url else None
    if source_url and not source_url.lower().startswith(("http://", "https://")):
        source_url = None

    return {
        "source_native_id": source_native_id,
        "resource_name": props.get("RESNAME"),
        "resource_type": resource_type,
        "reference_number": reference_number,
        "designation_status": props.get("STATUS") or "listed",
        "listed_date": parse_cert_date(props.get("CertDate")),
        "address_text": props.get("Address"),
        "city": props.get("City"),
        "county_name": props.get("County"),
        "state_code": state_code,
        "is_national_historic_landmark": str(props.get("Is_NHL") or "").strip().upper() in {"Y", "YES", "1", "TRUE"},
        "geometry": geometry,
        "confidence": 0.90 if geometry_kind == "point" else 0.92,
        "source_url": source_url,
        "attributes": {
            "geometry_kind": geometry_kind,
            "object_id": object_id,
            "vicinity": props.get("Vicinity"),
            "contributing_buildings": props.get("NumCBldg"),
            "contributing_structures": props.get("NumCStru"),
            "boundary_type": props.get("BND_TYPE"),
            "is_extant": props.get("IS_EXTANT"),
            "map_method": props.get("MAP_METHOD"),
            "source_accuracy": props.get("SRC_ACCU"),
            "edit_date": props.get("EDIT_DATE"),
        },
    }


def upload(items) -> tuple[int, int, int]:
    submitted = building_matches = invalid = 0
    batch: list[dict] = []

    def flush(features: list[dict]) -> None:
        nonlocal submitted, building_matches, invalid
        if not features:
            return
        result = rpc(
            "internal_ingest_historic_resource_batch",
            {
                "p_source_slug": "nps-national-register-historic-places",
                "p_features": features,
                "p_observed_at": datetime.now(timezone.utc).isoformat(),
            },
        )
        submitted += len(features)
        building_matches += int(result.get("building_matches", 0))
        invalid += int(result.get("invalid", 0))
        print(
            f"submitted={submitted:,} building_matches={building_matches:,} invalid={invalid:,}",
            flush=True,
        )

    for item in items:
        if item is None:
            continue
        batch.append(item)
        if len(batch) >= BATCH_SIZE:
            flush(batch)
            batch = []
    flush(batch)
    return submitted, building_matches, invalid


def iter_all_features():
    for code in sorted(STATE_CODES):
        if code not in STATE_NAMES:
            raise SystemExit(f"Unsupported SCOUT_NRHP_STATES code for pilot loader: {code}")
        print(f"NRHP {code}: points", flush=True)
        for feature in fetch_layer(POINT_LAYER, code):
            yield normalize_feature(feature, "point", code)
        print(f"NRHP {code}: polygons", flush=True)
        for feature in fetch_layer(POLYGON_LAYER, code):
            yield normalize_feature(feature, "polygon", code)


def main() -> None:
    result = upload(iter_all_features())
    print(
        "NRHP enrichment complete: "
        f"submitted={result[0]:,} building_matches={result[1]:,} invalid={result[2]:,}",
        flush=True,
    )


if __name__ == "__main__":
    main()
