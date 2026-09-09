#!/usr/bin/env python3
"""Transient probe of Indiana IDEM's current issued CFO/CAFO workbook.

Downloads the public XLS into memory, inspects schema/selected known farm rows,
prints only derived field-presence/schema diagnostics, then exits. The source
workbook is not persisted or uploaded as an artifact.
"""
from __future__ import annotations

import json
import re
from io import BytesIO

import requests
import xlrd

URL = "https://www.in.gov/dA/a65b5e6a25/permits_issued.xls?language_id=1"
USER_AGENT = "Scout-Cadastory-IDEM-CFO-Probe/1.0"
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
        "owner": ("owner", "operator"),
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
    best_row = 0
    best_headers: list[str] = []
    best_score = -1
    for r in range(min(sheet.nrows, 25)):
        headers = [as_text(sheet.cell_value(r, c)) for c in range(sheet.ncols)]
        score = sum(bool(classify_header(h)) for h in headers)
        if score > best_score:
            best_score = score
            best_row = r
            best_headers = headers
    return best_row, best_headers


def main() -> None:
    response = requests.get(URL, headers={"User-Agent": USER_AGENT}, timeout=(20, 60))
    response.raise_for_status()
    if len(response.content) > 25 * 1024 * 1024:
        raise RuntimeError("unexpectedly large workbook")

    book = xlrd.open_workbook(file_contents=response.content, on_demand=True)
    output: dict[str, object] = {
        "source_url": URL.split("?")[0],
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
            for tag in ("tempo_id", "county", "address", "city", "state", "zip", "latitude", "longitude", "section", "township", "range"):
                col = tagged.get(tag)
                if col is not None:
                    selected[tag] = as_text(sheet.cell_value(r, col))
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
