#!/usr/bin/env python3
"""Transient probe of Indiana IDEM CFO/CAFO location keys.

Downloads the current public issued-project XLS into memory, inspects schema and
selected known farm rows, then resolves their Section/Township/Range keys against
Indiana's public PLSS section FeatureServer. No source workbook or GIS response
is retained as an artifact.
"""
from __future__ import annotations

import json
import re

import requests
import xlrd

IDEM_URL = "https://www.in.gov/dA/a65b5e6a25/permits_issued.xls?language_id=1"
PLSS_URL = "https://gisdata.in.gov/server/rest/services/Hosted/PLSS_1/FeatureServer/3/query"
USER_AGENT = "Scout-Cadastory-IDEM-CFO-Probe/1.2"
KNOWN_FARM_IDS = {"6394", "4494", "4695", "372", "1939"}
KNOWN_NAMES = {
    "50 west llc",
    "flat creek pork llc",
    "hawes farms llc",
    "brian begle farms",
    "country view family farms llc morristown",
}


def norm(value: object) -> str:
    return re.sub(r"\s+", " ", str(value or "")).strip().lower()


def as_text(value: object) -> str:
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    return str(value or "").strip()


def classify_header(header: str) -> list[str]:
    h = norm(header)
    tags: list[str] = []
    tests = {
        "farm_id": ("farm id", "farmid"),
        "tempo_id": ("tempo", "agency interest", "ai id", "program id"),
        "operation_name": ("operation name", "farm name", "facility name", "operation"),
        "address": ("address", "street"),
        "city": ("city",),
        "state": ("state",),
        "zip": ("zip", "postal"),
        "county": ("county",),
        "latitude": ("latitude", "lat"),
        "longitude": ("longitude", "lon", "long"),
        "section": ("section",),
        "township": ("township",),
        "range": ("range",),
        "animal": ("animal", "cattle", "swine", "poultry", "broiler", "layer", "turkey", "pig", "dairy", "beef"),
    }
    for tag, needles in tests.items():
        if any(n in h for n in needles):
            tags.append(tag)
    return tags


def find_header_row(sheet: xlrd.sheet.Sheet) -> tuple[int, list[str]]:
    best_row, best_headers, best_score = 0, [], -1
    for r in range(min(sheet.nrows, 25)):
        headers = [as_text(sheet.cell_value(r, c)) for c in range(sheet.ncols)]
        score = sum(bool(classify_header(h)) for h in headers)
        if score > best_score:
            best_row, best_headers, best_score = r, headers, score
    return best_row, best_headers


def parse_directional(value: str) -> tuple[int, str] | None:
    m = re.match(r"^\s*0*(\d+)\s*([NSEW])\b", value or "", re.I)
    if not m:
        return None
    return int(m.group(1)), m.group(2).upper()


def plss_lookup(section: str, township: str, range_value: str) -> dict[str, object]:
    t = parse_directional(township)
    rg = parse_directional(range_value)
    try:
        sec = int(float(section))
    except (TypeError, ValueError):
        return {"status": "invalid_plss_key"}
    if not t or not rg or not 1 <= sec <= 36:
        return {"status": "invalid_plss_key"}

    twp, twpd = t
    rng, rngd = rg
    # Query only the township/range server-side, then filter the small section set
    # client-side. This avoids brittle compound predicates on the hosted layer.
    where = f"twp={twp} AND twpd='{twpd}' AND rng={rng} AND rngd='{rngd}'"
    response = requests.get(
        PLSS_URL,
        params={
            "f": "json",
            "where": where,
            "outFields": "objectid_12,meridian,twp,twpd,rng,rngd,parcel_id",
            "returnGeometry": "true",
            "returnCentroid": "true",
            "outSR": "4326",
        },
        headers={"User-Agent": USER_AGENT},
        timeout=(20, 60),
    )
    response.raise_for_status()
    payload = response.json()
    if payload.get("error"):
        return {"status": "arcgis_error", "error": payload["error"].get("message")}

    features = []
    for feature in payload.get("features") or []:
        attrs = feature.get("attributes") or {}
        if str(attrs.get("parcel_id") or "").strip() != str(sec):
            continue
        centroid = feature.get("centroid") or {}
        lon = centroid.get("x")
        lat = centroid.get("y")
        if lon is None or lat is None:
            rings = (feature.get("geometry") or {}).get("rings") or []
            points = [p for ring in rings for p in ring if isinstance(p, list) and len(p) >= 2]
            if points:
                lon = sum(float(p[0]) for p in points) / len(points)
                lat = sum(float(p[1]) for p in points) / len(points)
        features.append({
            "objectid": attrs.get("objectid_12"),
            "meridian": attrs.get("meridian"),
            "section": attrs.get("parcel_id"),
            "approx_lon": round(float(lon), 6) if lon is not None else None,
            "approx_lat": round(float(lat), 6) if lat is not None else None,
        })
    return {"status": "ok", "feature_count": len(features), "features": features[:5]}


def main() -> None:
    response = requests.get(IDEM_URL, headers={"User-Agent": USER_AGENT}, timeout=(20, 60))
    response.raise_for_status()
    if len(response.content) > 25 * 1024 * 1024:
        raise RuntimeError("unexpectedly large workbook")

    book = xlrd.open_workbook(file_contents=response.content, on_demand=True)
    output: dict[str, object] = {
        "source_url": IDEM_URL.split("?")[0],
        "plss_source_url": PLSS_URL.rsplit("/query", 1)[0],
        "workbook_bytes": len(response.content),
        "sheet_names": book.sheet_names(),
        "sheets": [],
    }

    for sheet_name in book.sheet_names():
        sheet = book.sheet_by_name(sheet_name)
        if sheet.nrows == 0 or sheet.ncols == 0:
            continue
        header_row, headers = find_header_row(sheet)
        header_info = [
            {"index": i, "header": h, "tags": classify_header(h)}
            for i, h in enumerate(headers) if h
        ]
        tagged = {tag: i for i, h in enumerate(headers) for tag in classify_header(h)}
        matches: list[dict[str, object]] = []

        farm_id_col = tagged.get("farm_id")
        name_col = tagged.get("operation_name")
        for r in range(header_row + 1, sheet.nrows):
            farm_id = as_text(sheet.cell_value(r, farm_id_col)) if farm_id_col is not None else ""
            name = as_text(sheet.cell_value(r, name_col)) if name_col is not None else ""
            if farm_id not in KNOWN_FARM_IDS and norm(name) not in KNOWN_NAMES:
                continue
            selected: dict[str, object] = {"row": r + 1, "farm_id": farm_id, "operation_name": name}
            for tag in ("tempo_id", "county", "section", "township", "range"):
                col = tagged.get(tag)
                if col is not None:
                    selected[tag] = as_text(sheet.cell_value(r, col))
            selected["plss_lookup"] = plss_lookup(
                str(selected.get("section") or ""),
                str(selected.get("township") or ""),
                str(selected.get("range") or ""),
            )
            matches.append(selected)

        output["sheets"].append({
            "sheet": sheet_name,
            "rows": sheet.nrows,
            "cols": sheet.ncols,
            "header_row": header_row + 1,
            "headers": header_info,
            "semantic_fields_present": sorted(tagged),
            "known_candidate_matches": matches,
        })
        book.unload_sheet(sheet_name)

    print(json.dumps(output, sort_keys=True))


if __name__ == "__main__":
    main()
