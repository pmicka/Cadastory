#!/usr/bin/env python3
"""Resolve current Indiana IDEM livestock operations to authoritative PLSS sections.

Source workbooks and GIS payloads are processed transiently. Persisted output is
only derived location evidence: a county-validated representative point for the
PLSS section plus provenance/PLSS identifiers. Section points are intentionally
classified as approximate and are not operational farmstead/parcel coordinates.
"""
from __future__ import annotations

import json
import os
import re
import time
from collections import defaultdict
from datetime import datetime
from io import BytesIO
from typing import Any

import requests
import xlrd
from shapely.geometry import Polygon

SUPABASE_URL = os.getenv("SUPABASE_URL", "").rstrip("/")
SERVICE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "")
MAX_RECORDS = max(1, min(int(os.getenv("SCOUT_IN_PLSS_MAX_RECORDS", "250")), 500))
IDEM_URL = "https://www.in.gov/dA/a65b5e6a25/permits_issued.xls?language_id=1"
PLSS_URL = "https://gisdata.in.gov/server/rest/services/Hosted/PLSS_1/FeatureServer/3/query"
USER_AGENT = "Scout-Cadastory-Indiana-Livestock-PLSS/1.0"
TIMEOUT = (20, 60)

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


def norm(value: object) -> str:
    return re.sub(r"\s+", " ", str(value or "")).strip().lower()


def as_text(value: object) -> str:
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    return str(value or "").strip()


def parse_directional(value: str) -> tuple[int, str] | None:
    m = re.match(r"^\s*0*(\d+)\s*([NSEW])\b", value or "", re.I)
    return (int(m.group(1)), m.group(2).upper()) if m else None


def date_text(sheet: xlrd.sheet.Sheet, row: int, col: int, datemode: int) -> str:
    cell = sheet.cell(row, col)
    if cell.ctype == xlrd.XL_CELL_DATE:
        return xlrd.xldate_as_datetime(cell.value, datemode).date().isoformat()
    raw = as_text(cell.value)
    for fmt in ("%Y-%m-%d", "%m/%d/%Y", "%m/%d/%y", "%Y/%m/%d"):
        try:
            return datetime.strptime(raw, fmt).date().isoformat()
        except ValueError:
            pass
    return raw


def find_header_row(sheet: xlrd.sheet.Sheet) -> tuple[int, dict[str, int]]:
    wanted = {
        "farm_id": "farm id",
        "tempo_id": "tempo id",
        "county": "county",
        "date_issued": "date issued",
        "operation_name": "operation name",
        "section": "section",
        "township": "township",
        "range": "range",
    }
    best: tuple[int, dict[str, int]] | None = None
    for r in range(min(sheet.nrows, 25)):
        headers = [norm(sheet.cell_value(r, c)) for c in range(sheet.ncols)]
        mapping: dict[str, int] = {}
        for key, needle in wanted.items():
            for c, h in enumerate(headers):
                if needle in h:
                    mapping[key] = c
                    break
        if best is None or len(mapping) > len(best[1]):
            best = (r, mapping)
    assert best is not None
    missing = set(wanted) - set(best[1])
    if missing:
        raise RuntimeError(f"IDEM workbook missing required headers: {sorted(missing)}")
    return best


def load_idem_rows() -> tuple[dict[tuple[str, str], list[dict[str, Any]]], int]:
    r = HTTP.get(IDEM_URL, timeout=TIMEOUT)
    r.raise_for_status()
    if len(r.content) > 25 * 1024 * 1024:
        raise RuntimeError("unexpectedly large IDEM workbook")
    book = xlrd.open_workbook(file_contents=r.content, on_demand=True)
    sheet = book.sheet_by_name("Issued Projects")
    header_row, cols = find_header_row(sheet)
    index: dict[tuple[str, str], list[dict[str, Any]]] = defaultdict(list)
    for row in range(header_row + 1, sheet.nrows):
        farm_id = as_text(sheet.cell_value(row, cols["farm_id"]))
        tempo_id = as_text(sheet.cell_value(row, cols["tempo_id"]))
        if not farm_id or not tempo_id:
            continue
        rec = {
            "farm_id": farm_id,
            "tempo_id": tempo_id,
            "county": as_text(sheet.cell_value(row, cols["county"])),
            "date_issued": date_text(sheet, row, cols["date_issued"], book.datemode),
            "operation_name": as_text(sheet.cell_value(row, cols["operation_name"])),
            "section": as_text(sheet.cell_value(row, cols["section"])),
            "township": as_text(sheet.cell_value(row, cols["township"])),
            "range": as_text(sheet.cell_value(row, cols["range"])),
            "row_number": row + 1,
        }
        index[(farm_id, tempo_id)].append(rec)
    for records in index.values():
        records.sort(key=lambda x: x.get("date_issued") or "", reverse=True)
    rows = sheet.nrows
    book.unload_sheet("Issued Projects")
    return index, rows


def pick_idem_row(job: dict[str, Any], index: dict[tuple[str, str], list[dict[str, Any]]]) -> dict[str, Any] | None:
    records = index.get((str(job.get("farm_id") or ""), str(job.get("tempo_id") or ""))) or []
    if not records:
        return None
    expected_date = str(job.get("date_issued") or "")[:10]
    if expected_date:
        exact = [r for r in records if str(r.get("date_issued") or "")[:10] == expected_date]
        if exact:
            return exact[0]
    return records[0]


PLSS_CACHE: dict[tuple[int, str, int, str], list[dict[str, Any]]] = {}


def township_range_features(twp: int, twpd: str, rng: int, rngd: str) -> list[dict[str, Any]]:
    key = (twp, twpd, rng, rngd)
    if key in PLSS_CACHE:
        return PLSS_CACHE[key]
    where = f"twp={twp} AND twpd='{twpd}' AND rng={rng} AND rngd='{rngd}'"
    r = HTTP.get(PLSS_URL, params={
        "f": "json",
        "where": where,
        "outFields": "objectid_12,meridian,twp,twpd,rng,rngd,parcel_id",
        "returnGeometry": "true",
        "outSR": "4326",
    }, timeout=TIMEOUT)
    r.raise_for_status()
    payload = r.json()
    if payload.get("error"):
        raise RuntimeError(f"Indiana PLSS service error: {payload['error'].get('message')}")
    PLSS_CACHE[key] = payload.get("features") or []
    time.sleep(0.04)
    return PLSS_CACHE[key]


def section_candidates(section: int, twp: int, twpd: str, rng: int, rngd: str) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for feature in township_range_features(twp, twpd, rng, rngd):
        attrs = feature.get("attributes") or {}
        if str(attrs.get("parcel_id") or "").strip() != str(section):
            continue
        rings = (feature.get("geometry") or {}).get("rings") or []
        if not rings or len(rings[0]) < 4:
            continue
        try:
            poly = Polygon([(float(p[0]), float(p[1])) for p in rings[0]])
            point = poly.representative_point()
        except Exception:
            points = [p for p in rings[0] if isinstance(p, list) and len(p) >= 2]
            if not points:
                continue
            point = type("P", (), {
                "x": sum(float(p[0]) for p in points) / len(points),
                "y": sum(float(p[1]) for p in points) / len(points),
            })()
        out.append({
            "section": section,
            "township": twp,
            "township_direction": twpd,
            "range": rng,
            "range_direction": rngd,
            "meridian": attrs.get("meridian"),
            "objectid": attrs.get("objectid_12"),
            "lon": float(point.x),
            "lat": float(point.y),
        })
    return out


def self_test() -> None:
    assert parse_directional("04S - Four South") == (4, "S")
    assert parse_directional("03E - Three East") == (3, "E")
    assert parse_directional("") is None
    print("Indiana livestock PLSS loader self-test passed")


def main() -> None:
    if os.getenv("SCOUT_SELF_TEST") == "1":
        self_test()
        return
    queue = rpc("internal_get_indiana_livestock_plss_queue", {"p_limit": MAX_RECORDS}) or []
    index, workbook_rows = load_idem_rows()
    stats = {
        "queued": len(queue), "workbook_rows": workbook_rows, "matched": 0,
        "no_workbook_row": 0, "invalid_plss": 0, "no_plss_feature": 0,
        "county_rejected": 0, "errors": 0,
    }

    for job in queue:
        rec = pick_idem_row(job, index)
        if not rec:
            stats["no_workbook_row"] += 1
            continue
        try:
            section = int(float(rec.get("section") or 0))
            township = parse_directional(str(rec.get("township") or ""))
            range_value = parse_directional(str(rec.get("range") or ""))
            if not 1 <= section <= 36 or not township or not range_value:
                stats["invalid_plss"] += 1
                continue
            twp, twpd = township
            rng, rngd = range_value
            candidates = section_candidates(section, twp, twpd, rng, rngd)
            if not candidates:
                stats["no_plss_feature"] += 1
                continue
            source_record_key = "|".join([
                rec["farm_id"], rec["tempo_id"], str(rec.get("date_issued") or ""),
                str(section), f"{twp}{twpd}", f"{rng}{rngd}",
            ])
            accepted = False
            for candidate in candidates:
                result = rpc("internal_upsert_indiana_livestock_plss_location", {
                    "p_candidate_id": job["candidate_id"],
                    "p_farm_id": job["farm_id"],
                    "p_tempo_id": job["tempo_id"],
                    "p_section": section,
                    "p_township": twp,
                    "p_township_direction": twpd,
                    "p_range": rng,
                    "p_range_direction": rngd,
                    "p_meridian": candidate.get("meridian"),
                    "p_plss_objectid": candidate.get("objectid"),
                    "p_lon": candidate["lon"],
                    "p_lat": candidate["lat"],
                    "p_source_record_key": source_record_key,
                    "p_observed_at": None,
                })
                if result.get("accepted"):
                    accepted = True
                    stats["matched"] += 1
                    print(json.dumps({
                        "candidate_id": job["candidate_id"],
                        "farm": job.get("display_name"),
                        "status": "matched",
                        "county": result.get("county_name"),
                        "section": section,
                        "township": f"{twp}{twpd}",
                        "range": f"{rng}{rngd}",
                        "meridian": candidate.get("meridian"),
                        "accuracy_class": "section_approximate",
                    }, sort_keys=True), flush=True)
                    break
            if not accepted:
                stats["county_rejected"] += 1
        except Exception as exc:
            stats["errors"] += 1
            print(json.dumps({
                "candidate_id": job.get("candidate_id"),
                "farm": job.get("display_name"),
                "status": "error",
                "error": f"{type(exc).__name__}: {exc}",
            }, sort_keys=True), flush=True)

    print("summary=" + json.dumps(stats, sort_keys=True), flush=True)


if __name__ == "__main__":
    main()
