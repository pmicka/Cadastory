#!/usr/bin/env python3
"""
Load National Register of Historic Places spatial data into Scout.

Requirements:
  - SUPABASE_URL
  - SUPABASE_SERVICE_ROLE_KEY

Optional:
  - SCOUT_NRHP_BATCH_SIZE=500

The loader uses the authoritative National Park Service national NRHP MapServer
and queries it by Scout's server-supplied pilot area. Historic designation is
preserved as context only; the database keeps individually-listed buildings
distinct from buildings that merely fall inside a listed historic district.
"""

from __future__ import annotations

import json
import os
import time
from datetime import date, datetime, timezone

import requests

SUPABASE_URL = os.environ["SUPABASE_URL"].rstrip("/")
SERVICE_KEY = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
BATCH_SIZE = int(os.getenv("SCOUT_NRHP_BATCH_SIZE", "500"))
TIMEOUT = (30, 180)
PAGE_SIZE = 2000
MAX_RPC_ATTEMPTS = 8
TRANSIENT_HTTP = {408, 425, 429, 500, 502, 503, 504, 520, 521, 522, 523, 524}

if not 1 <= BATCH_SIZE <= 1000:
    raise SystemExit("SCOUT_NRHP_BATCH_SIZE must be between 1 and 1000")

STATE_NAMES = {"KY": "Kentucky", "IN": "Indiana", "OH": "Ohio"}
POINT_LAYER = (
    "https://mapservices.nps.gov/arcgis/rest/services/"
    "cultural_resources/nrhp_locations/MapServer/0"
)
POLYGON_LAYER = (
    "https://mapservices.nps.gov/arcgis/rest/services/"
    "cultural_resources/nrhp_locations/MapServer/1"
)

SUPABASE_SESSION = requests.Session()
SUPABASE_SESSION.headers.update(
    {
        "apikey": SERVICE_KEY,
        "Authorization": f"Bearer {SERVICE_KEY}",
        "Content-Type": "application/json",
        "User-Agent": "Scout-Cadastory-NRHP-Loader/1.2",
    }
)
NPS_SESSION = requests.Session()
NPS_SESSION.headers.update({"User-Agent": "Scout-Cadastory-NRHP-Loader/1.2"})


def _retry_delay(attempt: int, response: requests.Response | None = None) -> float:
    if response is not None:
        retry_after = response.headers.get("Retry-After")
        if retry_after:
            try:
                return min(60.0, max(1.0, float(retry_after)))
            except ValueError:
                pass
    return float(min(30, 2 ** attempt))


def rpc(name: str, payload: dict | None = None):
    url = f"{SUPABASE_URL}/rest/v1/rpc/{name}"
    last_error: Exception | None = None
    for attempt in range(1, MAX_RPC_ATTEMPTS + 1):
        response = None
        try:
            response = SUPABASE_SESSION.post(url, json=payload or {}, timeout=TIMEOUT)
            if response.ok:
                return response.json()
            if response.status_code not in TRANSIENT_HTTP:
                raise RuntimeError(
                    f"RPC {name} failed: HTTP {response.status_code}: {response.text[:1200]}"
                )
            last_error = RuntimeError(
                f"RPC {name} transient HTTP {response.status_code}: {response.text[:300]}"
            )
        except requests.RequestException as exc:
            last_error = exc

        if attempt >= MAX_RPC_ATTEMPTS:
            break
        delay = _retry_delay(attempt, response)
        print(
            f"RPC {name} transient failure; retry {attempt}/{MAX_RPC_ATTEMPTS - 1} "
            f"in {delay:.0f}s: {last_error}",
            flush=True,
        )
        time.sleep(delay)

    raise RuntimeError(
        f"RPC {name} failed after {MAX_RPC_ATTEMPTS} attempts: {last_error}"
    ) from last_error


def pilot_bbox() -> list[float]:
    config = rpc("internal_get_site_access_snapshot_loader_config")
    regions = config.get("regions") or []
    boxes = [r.get("bbox") for r in regions if r.get("bbox") and len(r.get("bbox")) == 4]
    if not boxes:
        raise RuntimeError("Scout loader config did not provide a pilot bounding box")
    return [
        min(float(b[0]) for b in boxes), min(float(b[1]) for b in boxes),
        max(float(b[2]) for b in boxes), max(float(b[3]) for b in boxes),
    ]


def fetch_layer(layer_url: str, bbox: list[float]):
    minx, miny, maxx, maxy = bbox
    envelope = {
        "xmin": minx, "ymin": miny, "xmax": maxx, "ymax": maxy,
        "spatialReference": {"wkid": 4326},
    }
    offset = 0
    while True:
        params = {
            "where": "STATUS='Listed'",
            "geometry": json.dumps(envelope, separators=(",", ":")),
            "geometryType": "esriGeometryEnvelope",
            "inSR": "4326",
            "spatialRel": "esriSpatialRelIntersects",
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
    text = str(value).strip()
    for fmt in ("%Y-%m-%d", "%m/%d/%Y", "%Y%m%d"):
        try:
            return datetime.strptime(text, fmt).date().isoformat()
        except ValueError:
            pass
    digits = "".join(ch for ch in text if ch.isdigit())
    if len(digits) >= 8:
        for y, m, d in ((digits[:4], digits[4:6], digits[6:8]), (digits[4:8], digits[:2], digits[2:4])):
            try:
                return date(int(y), int(m), int(d)).isoformat()
            except ValueError:
                pass
    return None


def state_code_from_value(value: object) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    if len(text) == 2:
        return text.upper()
    lowered = text.lower()
    for code, name in STATE_NAMES.items():
        if lowered == name.lower():
            return code
    return None


def normalize_feature(feature: dict, geometry_kind: str) -> dict | None:
    geometry = feature.get("geometry")
    props = feature.get("properties") or {}
    if not geometry:
        return None

    object_id = props.get("OBJECTID")
    reference_number = (
        props.get("NRIS_Refnum") or props.get("NRIS_Refnu")
        or props.get("PROPERTY_ID") or props.get("PROPERTY_I")
    )
    stable_id = str(reference_number or props.get("CR_ID") or object_id or "").strip()
    if not stable_id:
        return None

    resource_type = str(props.get("ResType") or "unknown").strip().lower()
    state_code = state_code_from_value(props.get("State") or props.get("STATE"))
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
        "designation_status": props.get("STATUS") or "Listed",
        "listed_date": parse_cert_date(props.get("CertDate")),
        "address_text": props.get("Address"),
        "city": props.get("City"),
        "county_name": props.get("County"),
        "state_code": state_code,
        "is_national_historic_landmark": str(props.get("Is_NHL") or "").strip().upper()
        in {"X", "Y", "YES", "1", "TRUE"},
        "geometry": geometry,
        "confidence": 0.90 if geometry_kind == "point" else 0.92,
        "source_url": source_url,
        "attributes": {
            "geometry_kind": geometry_kind,
            "object_id": object_id,
            "cultural_resource_id": props.get("CR_ID"),
            "geometry_id": props.get("GEOM_ID"),
            "property_id": props.get("PROPERTY_ID"),
            "vicinity": props.get("Vicinity"),
            "contributing_buildings": props.get("NumCBldg"),
            "contributing_structures": props.get("NumCStru"),
            "boundary_type": props.get("BND_TYPE"),
            "is_extant": props.get("IS_EXTANT"),
            "map_method": props.get("MAP_METHOD"),
            "source_accuracy": props.get("SRC_ACCU"),
            "edit_date": props.get("EDIT_DATE"),
            "authoritative_service": "nps-cultural_resources-nrhp_locations",
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


def iter_all_features(bbox: list[float]):
    print(f"NRHP pilot AOI {bbox}: points", flush=True)
    for feature in fetch_layer(POINT_LAYER, bbox):
        yield normalize_feature(feature, "point")
    print(f"NRHP pilot AOI {bbox}: polygons", flush=True)
    for feature in fetch_layer(POLYGON_LAYER, bbox):
        yield normalize_feature(feature, "polygon")


def main() -> None:
    bbox = pilot_bbox()
    result = upload(iter_all_features(bbox))
    if result[0] == 0:
        raise RuntimeError("Authoritative NPS NRHP query returned zero resources for Scout's pilot AOI")
    print(
        "NRHP enrichment complete: "
        f"submitted={result[0]:,} building_matches={result[1]:,} invalid={result[2]:,}",
        flush=True,
    )


if __name__ == "__main__":
    main()
