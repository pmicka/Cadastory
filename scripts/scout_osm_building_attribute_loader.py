#!/usr/bin/env python3
"""
Load explicit OSM building height, level and facade-material tags into Scout.

Requirements:
  - osmium-tool on PATH
  - SUPABASE_URL
  - SUPABASE_SERVICE_ROLE_KEY

Optional:
  - SCOUT_OSM_BUILDING_REGIONS=kentucky,indiana,ohio
  - SCOUT_OSM_BUILDING_BATCH_SIZE=500

This is intentionally separate from Scout's site-access snapshot loader. It
extracts only explicit building attributes inside Scout's current canonical
building coverage extents and sends them through the provenance-aware building-
attribute ingestion RPC. States without canonical building footprints are
skipped automatically. It never infers a material from building type and never
treats a missing OSM tag as evidence of absence.
"""

from __future__ import annotations

import email.utils
import json
import os
import re
import subprocess
import tempfile
import time
from datetime import timezone
from pathlib import Path

import requests

SUPABASE_URL = os.environ["SUPABASE_URL"].rstrip("/")
SERVICE_KEY = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
REGION_FILTER = {
    value.strip().lower()
    for value in os.getenv("SCOUT_OSM_BUILDING_REGIONS", "").split(",")
    if value.strip()
}
BATCH_SIZE = int(os.getenv("SCOUT_OSM_BUILDING_BATCH_SIZE", "500"))
TIMEOUT = (30, 300)
MAX_RPC_ATTEMPTS = 8
TRANSIENT_HTTP = {408, 425, 429, 500, 502, 503, 504, 520, 521, 522, 523, 524}

if not 1 <= BATCH_SIZE <= 1000:
    raise SystemExit("SCOUT_OSM_BUILDING_BATCH_SIZE must be between 1 and 1000")

SUPABASE_SESSION = requests.Session()
SUPABASE_SESSION.headers.update(
    {
        "apikey": SERVICE_KEY,
        "Authorization": f"Bearer {SERVICE_KEY}",
        "Content-Type": "application/json",
        "User-Agent": "Scout-Cadastory-OSM-Building-Attributes/1.2",
    }
)
DOWNLOAD_SESSION = requests.Session()
DOWNLOAD_SESSION.headers.update(
    {"User-Agent": "Scout-Cadastory-OSM-Building-Attributes/1.2"}
)


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


def run(*args: str) -> str:
    process = subprocess.run(args, check=True, text=True, capture_output=True)
    if process.stderr.strip():
        print(process.stderr.strip())
    return process.stdout.strip()


def require_osmium() -> None:
    try:
        print(run("osmium", "--version").splitlines()[0], flush=True)
    except (FileNotFoundError, subprocess.CalledProcessError) as exc:
        raise SystemExit("osmium-tool is required on PATH") from exc


def download(url: str, destination: Path) -> tuple[str | None, str | None]:
    etag = last_modified = None
    try:
        response = DOWNLOAD_SESSION.head(url, allow_redirects=True, timeout=TIMEOUT)
        if response.ok:
            etag = response.headers.get("ETag")
            last_modified = response.headers.get("Last-Modified")
    except requests.RequestException:
        pass

    print(f"Downloading {url}", flush=True)
    with DOWNLOAD_SESSION.get(url, stream=True, allow_redirects=True, timeout=TIMEOUT) as response:
        response.raise_for_status()
        etag = etag or response.headers.get("ETag")
        last_modified = last_modified or response.headers.get("Last-Modified")
        with destination.open("wb") as handle:
            for chunk in response.iter_content(chunk_size=8 * 1024 * 1024):
                if chunk:
                    handle.write(chunk)
    return etag, last_modified


def source_timestamp(pbf: Path, last_modified: str | None) -> str:
    try:
        value = run(
            "osmium", "fileinfo", "-g",
            "header.option.osmosis_replication_timestamp", str(pbf),
        ).strip()
        if value:
            return value
    except subprocess.CalledProcessError:
        pass

    if last_modified:
        parsed = email.utils.parsedate_to_datetime(last_modified)
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        return parsed.astimezone(timezone.utc).isoformat()
    raise RuntimeError("Unable to determine OSM source timestamp")


def prepare_geojsonseq(source_pbf: Path, bbox: list[float], work: Path) -> Path:
    clipped = work / "pilot.osm.pbf"
    filtered = work / "building-attributes.osm.pbf"
    exported = work / "building-attributes.geojsonseq"
    bbox_arg = ",".join(str(value) for value in bbox)

    run("osmium", "extract", "-b", bbox_arg, "-s", "complete_ways", "-O", "-o", str(clipped), str(source_pbf))
    run(
        "osmium", "tags-filter", "-O", "-o", str(filtered), str(clipped),
        "nwr/building:levels", "nwr/height", "nwr/building:material", "nwr/facade:material",
    )
    run(
        "osmium", "export", "-f", "geojsonseq", "-x", "print_record_separator=false",
        "-a", "type,id", "-O", "-o", str(exported), str(filtered),
    )
    return exported


_HEIGHT_RE = re.compile(r"^\s*(\d+(?:\.\d+)?)\s*(m|meter|meters|ft|feet|foot|')?\s*$", re.I)


def parse_height_m(value: object) -> float | None:
    if value is None:
        return None
    match = _HEIGHT_RE.match(str(value))
    if not match:
        return None
    numeric = float(match.group(1))
    unit = (match.group(2) or "m").lower()
    if unit in {"ft", "feet", "foot", "'"}:
        numeric *= 0.3048
    return numeric if numeric > 0 else None


def parse_story_count(value: object) -> int | None:
    if value is None:
        return None
    text = str(value).strip()
    if not re.fullmatch(r"\d+", text):
        return None
    result = int(text)
    return result if result > 0 else None


def normalize_material(value: object) -> tuple[str | None, str | None]:
    if value is None:
        return None, None
    raw = str(value).strip().lower()
    aliases = {
        "brick": "brick", "bricks": "brick", "concrete": "concrete",
        "cement_block": "cement_block", "concrete_blocks": "cement_block",
        "glass": "glass", "metal": "metal", "plaster": "plaster",
        "stucco": "plaster", "stone": "stone", "limestone": "stone",
        "sandstone": "stone", "wood": "wood", "timber": "wood",
        "timber_framing": "timber_framing",
    }
    return aliases.get(raw), raw


def iter_payload(path: Path, region_slug: str):
    with path.open("r", encoding="utf-8") as handle:
        for raw_line in handle:
            raw_line = raw_line.strip().lstrip("\x1e")
            if not raw_line:
                continue
            feature = json.loads(raw_line)
            geometry = feature.get("geometry")
            if not geometry or geometry.get("type") not in {"Polygon", "MultiPolygon"}:
                continue

            props = feature.get("properties") or {}
            osm_type = props.pop("@type", None)
            osm_id = props.pop("@id", None)
            if osm_type not in {"way", "relation"} or osm_id is None:
                continue
            if "building" not in props and "building:part" not in props:
                continue

            height = parse_height_m(props.get("height"))
            stories = parse_story_count(props.get("building:levels"))
            material, raw_material = normalize_material(
                props.get("facade:material") or props.get("building:material")
            )
            if height is None and stories is None and material is None and raw_material is None:
                continue

            yield {
                "source_native_id": f"{osm_type}/{osm_id}",
                "feature_kind": "building_part" if "building:part" in props else "building",
                "geometry": geometry,
                "height_m": height,
                "height_status": "documented" if height is not None else "unknown",
                "story_count": stories,
                "story_status": "documented" if stories is not None else "unknown",
                "facade_material": material,
                "raw_facade_material": raw_material,
                "facade_material_status": "documented" if raw_material is not None else "unknown",
                "glazing_signal": "glass_facade_present" if material == "glass" else None,
                "confidence": 0.92,
                "attributes": {
                    "region_slug": region_slug,
                    "building_tag": props.get("building"),
                    "building_part_tag": props.get("building:part"),
                    "raw_height": props.get("height"),
                    "raw_building_levels": props.get("building:levels"),
                    "material_key": "facade:material" if props.get("facade:material") else "building:material",
                },
            }


def upload(features, timestamp: str) -> tuple[int, int, int, int]:
    submitted = matched = unmatched = invalid = 0
    batch: list[dict] = []

    def flush(items: list[dict]) -> None:
        nonlocal submitted, matched, unmatched, invalid
        if not items:
            return
        result = rpc(
            "internal_ingest_building_attribute_batch",
            {
                "p_source_slug": "openstreetmap-geofabrik-building-attributes",
                "p_features": items,
                "p_source_timestamp": timestamp,
            },
        )
        submitted += len(items)
        matched += int(result.get("matched", 0))
        unmatched += int(result.get("unmatched", 0))
        invalid += int(result.get("invalid", 0))
        print(
            f"submitted={submitted:,} matched={matched:,} unmatched={unmatched:,} invalid={invalid:,}",
            flush=True,
        )

    for feature in features:
        batch.append(feature)
        if len(batch) >= BATCH_SIZE:
            flush(batch)
            batch = []
    flush(batch)
    return submitted, matched, unmatched, invalid


def main() -> None:
    require_osmium()
    config = rpc("internal_get_building_attribute_loader_config")
    regions = config["regions"]
    if REGION_FILTER:
        regions = [r for r in regions if r["region_slug"] in REGION_FILTER]
    if not regions:
        raise SystemExit("No canonical Scout building regions matched SCOUT_OSM_BUILDING_REGIONS")

    totals = [0, 0, 0, 0]
    for region in regions:
        with tempfile.TemporaryDirectory(prefix=f"scout-osm-building-{region['region_slug']}-") as temp_dir:
            work = Path(temp_dir)
            pbf = work / f"{region['region_slug']}.osm.pbf"
            _, last_modified = download(region["pbf_url"], pbf)
            timestamp = source_timestamp(pbf, last_modified)
            exported = prepare_geojsonseq(pbf, region["bbox"], work)
            result = upload(iter_payload(exported, region["region_slug"]), timestamp)
            totals = [a + b for a, b in zip(totals, result)]

    print(
        "OSM building enrichment complete: "
        f"submitted={totals[0]:,} matched={totals[1]:,} "
        f"unmatched={totals[2]:,} invalid={totals[3]:,}",
        flush=True,
    )


if __name__ == "__main__":
    main()
