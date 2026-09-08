#!/usr/bin/env python3
"""Targeted local OSM building-identity cache loader for Scout by Cadastory.

This intentionally does not mirror regional OSM buildings. It asks Scout for
currently unresolved premium-exterior OSM node targets, clusters those targets
into small extraction boxes, and extracts only polygonal building=* ways and
relations from the same Geofabrik regional PBFs used by Scout's access snapshot.

Requirements:
  - osmium-tool on PATH
  - Python requests
  - SUPABASE_URL
  - SUPABASE_SERVICE_ROLE_KEY

Optional environment:
  - SCOUT_OSM_BUILDING_REGIONS=kentucky,indiana
  - SCOUT_OSM_BUILDING_BATCH_SIZE=100
  - SCOUT_OSM_BUILDING_TILE_DEGREES=0.08
  - SCOUT_OSM_BUILDING_MAX_TARGETS_PER_REGION=0  # 0 = all
"""

from __future__ import annotations

import email.utils
import json
import math
import os
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

SUPABASE_URL = os.environ["SUPABASE_URL"].rstrip("/")
SERVICE_KEY = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
REGION_FILTER = {
    x.strip().lower()
    for x in os.getenv("SCOUT_OSM_BUILDING_REGIONS", "").split(",")
    if x.strip()
}
BATCH_SIZE = int(os.getenv("SCOUT_OSM_BUILDING_BATCH_SIZE", "100"))
TILE_DEGREES = float(os.getenv("SCOUT_OSM_BUILDING_TILE_DEGREES", "0.08"))
MAX_TARGETS_PER_REGION = int(os.getenv("SCOUT_OSM_BUILDING_MAX_TARGETS_PER_REGION", "0"))
TIMEOUT = (30, 300)

if not 1 <= BATCH_SIZE <= 500:
    raise SystemExit("SCOUT_OSM_BUILDING_BATCH_SIZE must be between 1 and 500")
if not 0.02 <= TILE_DEGREES <= 0.25:
    raise SystemExit("SCOUT_OSM_BUILDING_TILE_DEGREES must be between 0.02 and 0.25")
if MAX_TARGETS_PER_REGION < 0:
    raise SystemExit("SCOUT_OSM_BUILDING_MAX_TARGETS_PER_REGION must be >= 0")

SUPABASE_SESSION = requests.Session()
SUPABASE_SESSION.headers.update(
    {
        "apikey": SERVICE_KEY,
        "Authorization": f"Bearer {SERVICE_KEY}",
        "Content-Type": "application/json",
        "User-Agent": "Scout-Cadastory-OSM-Building-Identity-Loader/1.0",
    }
)

retry = Retry(
    total=6,
    connect=6,
    read=3,
    status=6,
    backoff_factor=2.0,
    status_forcelist=(429, 500, 502, 503, 504),
    allowed_methods=frozenset({"GET", "HEAD"}),
    respect_retry_after_header=True,
    raise_on_status=True,
)
DOWNLOAD_SESSION = requests.Session()
DOWNLOAD_SESSION.mount("https://", HTTPAdapter(max_retries=retry))
DOWNLOAD_SESSION.mount("http://", HTTPAdapter(max_retries=retry))
DOWNLOAD_SESSION.headers.update(
    {"User-Agent": "Scout-Cadastory-OSM-Building-Identity-Loader/1.0"}
)


class RPCError(RuntimeError):
    pass


def rpc(name: str, payload: dict | None = None):
    r = SUPABASE_SESSION.post(
        f"{SUPABASE_URL}/rest/v1/rpc/{name}",
        json=payload or {},
        timeout=TIMEOUT,
    )
    if not r.ok:
        raise RPCError(f"RPC {name} failed: HTTP {r.status_code}: {r.text[:1500]}")
    return r.json()


def run(*args: str) -> str:
    print("+", " ".join(args), flush=True)
    p = subprocess.run(args, check=True, text=True, capture_output=True)
    if p.stderr.strip():
        print(p.stderr.strip(), file=sys.stderr)
    return p.stdout.strip()


def require_osmium():
    try:
        version = run("osmium", "--version")
    except (FileNotFoundError, subprocess.CalledProcessError) as exc:
        raise SystemExit("osmium-tool is required on PATH") from exc
    print(version.splitlines()[0], flush=True)


def download(url: str, dest: Path) -> tuple[str | None, str | None]:
    etag = None
    last_modified = None
    try:
        h = DOWNLOAD_SESSION.head(url, allow_redirects=True, timeout=TIMEOUT)
        if h.ok:
            etag = h.headers.get("ETag")
            last_modified = h.headers.get("Last-Modified")
    except requests.RequestException:
        pass
    print(f"Downloading {url}", flush=True)
    with DOWNLOAD_SESSION.get(url, stream=True, allow_redirects=True, timeout=TIMEOUT) as r:
        r.raise_for_status()
        etag = etag or r.headers.get("ETag")
        last_modified = last_modified or r.headers.get("Last-Modified")
        with dest.open("wb") as fh:
            for chunk in r.iter_content(chunk_size=8 * 1024 * 1024):
                if chunk:
                    fh.write(chunk)
    print(f"Downloaded {dest.stat().st_size / (1024**2):.1f} MiB", flush=True)
    return etag, last_modified


def pbf_source_timestamp(pbf: Path, last_modified: str | None) -> str:
    try:
        value = run(
            "osmium",
            "fileinfo",
            "-g",
            "header.option.osmosis_replication_timestamp",
            str(pbf),
        ).strip()
        if value:
            return value
    except subprocess.CalledProcessError:
        pass
    if last_modified:
        dt = email.utils.parsedate_to_datetime(last_modified)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc).isoformat()
    return datetime.now(timezone.utc).isoformat()


def cluster_targets(targets: list[dict]) -> list[dict]:
    groups: dict[tuple[int, int], list[dict]] = {}
    for target in targets:
        lon = float(target["longitude"])
        lat = float(target["latitude"])
        key = (math.floor((lon + 180.0) / TILE_DEGREES), math.floor((lat + 90.0) / TILE_DEGREES))
        groups.setdefault(key, []).append(target)

    tiles = []
    for idx, (_, members) in enumerate(sorted(groups.items()), start=1):
        min_lon = min(float(x["longitude"]) for x in members)
        max_lon = max(float(x["longitude"]) for x in members)
        min_lat = min(float(x["latitude"]) for x in members)
        max_lat = max(float(x["latitude"]) for x in members)
        max_radius_m = max(float(x.get("radius_m") or 400) for x in members)
        center_lat = (min_lat + max_lat) / 2.0
        lat_pad = max_radius_m / 111_320.0 + 0.0005
        lon_pad = max_radius_m / max(1.0, 111_320.0 * math.cos(math.radians(center_lat))) + 0.0005
        tiles.append(
            {
                "id": idx,
                "target_count": len(members),
                "bbox": [min_lon - lon_pad, min_lat - lat_pad, max_lon + lon_pad, max_lat + lat_pad],
            }
        )
    return tiles


def write_extract_config(tiles: list[dict], extract_dir: Path, config_path: Path):
    extract_dir.mkdir(parents=True, exist_ok=True)
    config = {
        "directory": str(extract_dir),
        "extracts": [
            {
                "output": f"tile-{tile['id']:04d}.osm.pbf",
                "bbox": tile["bbox"],
            }
            for tile in tiles
        ],
    }
    config_path.write_text(json.dumps(config, indent=2), encoding="utf-8")


def iter_building_features(path: Path):
    with path.open("r", encoding="utf-8") as fh:
        for raw in fh:
            raw = raw.strip().lstrip("\x1e")
            if not raw:
                continue
            feature = json.loads(raw)
            geom = feature.get("geometry")
            if not geom or geom.get("type") not in {"Polygon", "MultiPolygon"}:
                continue
            props = feature.get("properties") or {}
            osm_type = props.pop("@type", None)
            osm_id = props.pop("@id", None)
            if osm_type not in {"way", "relation"} or osm_id is None:
                continue
            tags = {k: v for k, v in props.items() if not k.startswith("@")}
            building = str(tags.get("building") or "").strip().lower()
            if not building or building == "no":
                continue
            yield {
                "osm_type": osm_type,
                "osm_id": str(osm_id),
                "geometry": geom,
                "tags": tags,
            }


def upload_batch(region_slug: str, source_timestamp: str, batch: list[dict]):
    return rpc(
        "internal_upsert_premium_exterior_osm_building_batch",
        {
            "p_region_slug": region_slug,
            "p_source_timestamp": source_timestamp,
            "p_features": batch,
        },
    )


def process_region(region: dict):
    region_slug = region["region_slug"]
    targets = list(region.get("targets") or [])
    if MAX_TARGETS_PER_REGION:
        targets = targets[:MAX_TARGETS_PER_REGION]
    if not targets:
        print(f"{region_slug}: no targets", flush=True)
        return {"region_slug": region_slug, "targets": 0, "tiles": 0, "accepted": 0, "skipped": 0}

    tiles = cluster_targets(targets)
    print(
        f"{region_slug}: targets={len(targets):,} clustered into {len(tiles):,} extraction tiles",
        flush=True,
    )

    with tempfile.TemporaryDirectory(prefix=f"scout-osm-buildings-{region_slug}-") as td:
        work = Path(td)
        source_pbf = work / f"{region_slug}.osm.pbf"
        _, last_modified = download(region["pbf_url"], source_pbf)
        source_ts = pbf_source_timestamp(source_pbf, last_modified)

        extract_dir = work / "extracts"
        config_path = work / "extract-config.json"
        write_extract_config(tiles, extract_dir, config_path)
        run("osmium", "extract", "-c", str(config_path), "-O", str(source_pbf))

        accepted = 0
        skipped = 0
        seen: set[tuple[str, str]] = set()
        batch: list[dict] = []

        for tile in tiles:
            tile_pbf = extract_dir / f"tile-{tile['id']:04d}.osm.pbf"
            if not tile_pbf.exists() or tile_pbf.stat().st_size == 0:
                continue
            buildings_pbf = work / f"buildings-{tile['id']:04d}.osm.pbf"
            buildings_geojson = work / f"buildings-{tile['id']:04d}.geojsonseq"
            run(
                "osmium",
                "tags-filter",
                "-O",
                "-o",
                str(buildings_pbf),
                str(tile_pbf),
                "w/building",
                "r/building",
            )
            run(
                "osmium",
                "export",
                "-f",
                "geojsonseq",
                "-x",
                "print_record_separator=false",
                "-a",
                "type,id",
                "-O",
                "-o",
                str(buildings_geojson),
                str(buildings_pbf),
            )
            for feature in iter_building_features(buildings_geojson):
                key = (feature["osm_type"], feature["osm_id"])
                if key in seen:
                    continue
                seen.add(key)
                batch.append(feature)
                if len(batch) >= BATCH_SIZE:
                    result = upload_batch(region_slug, source_ts, batch)
                    accepted += int(result.get("accepted", 0))
                    skipped += int(result.get("skipped", 0))
                    batch = []
            buildings_pbf.unlink(missing_ok=True)
            buildings_geojson.unlink(missing_ok=True)

        if batch:
            result = upload_batch(region_slug, source_ts, batch)
            accepted += int(result.get("accepted", 0))
            skipped += int(result.get("skipped", 0))

        summary = {
            "region_slug": region_slug,
            "targets": len(targets),
            "tiles": len(tiles),
            "unique_buildings_seen": len(seen),
            "accepted": accepted,
            "skipped": skipped,
            "source_timestamp": source_ts,
        }
        print(json.dumps(summary, sort_keys=True), flush=True)
        return summary


def main():
    require_osmium()
    config = rpc("internal_get_premium_exterior_osm_building_snapshot_config")
    if int(config.get("unrouted_count") or 0) != 0:
        raise SystemExit(
            f"Refusing to load with {config.get('unrouted_count')} unresolved POIs lacking authoritative state routing"
        )
    regions = list(config.get("regions") or [])
    if REGION_FILTER:
        regions = [r for r in regions if r.get("region_slug") in REGION_FILTER]
    if not regions:
        raise SystemExit("No routed unresolved premium-exterior OSM node regions to process")

    print(
        f"Scout targeted OSM building identity snapshot contract v{config.get('contract_version')}; "
        f"regions={','.join(r['region_slug'] for r in regions)}",
        flush=True,
    )
    summaries = [process_region(region) for region in regions]
    print("Completed targeted building cache:", json.dumps(summaries, indent=2), flush=True)


if __name__ == "__main__":
    main()
