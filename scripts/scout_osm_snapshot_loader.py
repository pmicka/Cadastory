#!/usr/bin/env python3
"""
One-shot Scout by Cadastory OSM access snapshot loader.

Requirements:
  - osmium-tool on PATH
  - Python requests
  - SUPABASE_URL
  - SUPABASE_SERVICE_ROLE_KEY

Optional:
  - SCOUT_OSM_REGIONS=kentucky,indiana,ohio
  - SCOUT_OSM_BATCH_SIZE=500

This loader intentionally has no recurring schedule. It downloads Geofabrik
regional .osm.pbf files, clips them to Scout's server-supplied pilot bbox,
filters access-relevant OSM objects, exports streaming GeoJSON, and sends
bounded batches to Scout's service-role-only snapshot import RPCs.
"""

from __future__ import annotations

import email.utils
import json
import os
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

import requests

SUPABASE_URL = os.environ["SUPABASE_URL"].rstrip("/")
SERVICE_KEY = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
REGION_FILTER = {
    x.strip().lower()
    for x in os.getenv("SCOUT_OSM_REGIONS", "").split(",")
    if x.strip()
}
BATCH_SIZE = int(os.getenv("SCOUT_OSM_BATCH_SIZE", "500"))
TIMEOUT = (30, 300)

if not 1 <= BATCH_SIZE <= 1000:
    raise SystemExit("SCOUT_OSM_BATCH_SIZE must be between 1 and 1000")

SUPABASE_SESSION = requests.Session()
SUPABASE_SESSION.headers.update(
    {
        "apikey": SERVICE_KEY,
        "Authorization": f"Bearer {SERVICE_KEY}",
        "Content-Type": "application/json",
        "User-Agent": "Scout-Cadastory-OSM-Snapshot-Loader/1.0",
    }
)

# Never reuse the authenticated Supabase session for third-party downloads.
# This prevents the service-role Authorization header from leaving Supabase.
DOWNLOAD_SESSION = requests.Session()
DOWNLOAD_SESSION.headers.update(
    {"User-Agent": "Scout-Cadastory-OSM-Snapshot-Loader/1.0"}
)


def rpc(name: str, payload: dict | None = None):
    r = SUPABASE_SESSION.post(
        f"{SUPABASE_URL}/rest/v1/rpc/{name}",
        json=payload or {},
        timeout=TIMEOUT,
    )
    if not r.ok:
        raise RuntimeError(f"RPC {name} failed: HTTP {r.status_code}: {r.text[:1000]}")
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
            # Osmium normally emits an RFC3339 UTC timestamp.
            return value
    except subprocess.CalledProcessError:
        pass

    if last_modified:
        dt = email.utils.parsedate_to_datetime(last_modified)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc).isoformat()

    return datetime.now(timezone.utc).isoformat()


def prepare_access_geojsonseq(source_pbf: Path, bbox: list[float], work: Path) -> Path:
    clipped = work / "pilot.osm.pbf"
    filtered = work / "access.osm.pbf"
    exported = work / "access.geojsonseq"
    bbox_arg = ",".join(str(v) for v in bbox)

    # Complete ways preserves nodes required to build road/access geometries.
    run(
        "osmium", "extract",
        "-b", bbox_arg,
        "-s", "complete_ways",
        "-O",
        "-o", str(clipped),
        str(source_pbf),
    )

    # Keep full arbitrary OSM tags on the matching objects. The database
    # classifier is authoritative and will reject irrelevant highway objects.
    run(
        "osmium", "tags-filter",
        "-O",
        "-o", str(filtered),
        str(clipped),
        "nwr/highway",
        "nwr/amenity=parking",
        "nwr/barrier",
        "nwr/area:highway",
    )

    # @type and @id retain stable OSM identity; all normal tags are preserved.
    run(
        "osmium", "export",
        "-f", "geojsonseq",
        "-x", "print_record_separator=false",
        "-a", "type,id",
        "-O",
        "-o", str(exported),
        str(filtered),
    )
    return exported


def iter_payload_features(path: Path):
    with path.open("r", encoding="utf-8") as fh:
        for raw in fh:
            raw = raw.strip().lstrip("\x1e")
            if not raw:
                continue
            feature = json.loads(raw)
            geom = feature.get("geometry")
            props = feature.get("properties") or {}
            osm_type = props.pop("@type", None)
            osm_id = props.pop("@id", None)
            if not geom or osm_type not in {"node", "way", "relation"} or osm_id is None:
                continue
            # Any other @attributes are metadata, not OSM tags.
            tags = {k: v for k, v in props.items() if not k.startswith("@")}
            yield {
                "osm_type": osm_type,
                "osm_id": str(osm_id),
                "geometry": geom,
                "tags": tags,
            }


def upload_region(region: dict):
    slug = region["region_slug"]
    print(f"\n=== {slug.upper()} ===", flush=True)

    with tempfile.TemporaryDirectory(prefix=f"scout-osm-{slug}-") as td:
        work = Path(td)
        source_pbf = work / f"{slug}.osm.pbf"
        etag, last_modified = download(region["pbf_url"], source_pbf)
        source_ts = pbf_source_timestamp(source_pbf, last_modified)
        exported = prepare_access_geojsonseq(source_pbf, region["bbox"], work)

        started = rpc(
            "internal_start_site_access_snapshot_import",
            {
                "p_region_slug": slug,
                "p_source_timestamp": source_ts,
                "p_upstream_etag": etag,
                "p_upstream_last_modified": last_modified,
                "p_upstream_checksum": None,
                "p_attributes": {
                    "loader": "osmium-tool-v1",
                    "source": "geofabrik-regional-pbf",
                },
            },
        )
        import_id = started["import_id"]
        accepted = 0
        submitted = 0
        batch = []

        try:
            for item in iter_payload_features(exported):
                batch.append(item)
                if len(batch) >= BATCH_SIZE:
                    result = rpc(
                        "internal_ingest_site_access_snapshot_batch",
                        {"p_import_id": import_id, "p_features": batch},
                    )
                    accepted += int(result.get("accepted", 0))
                    submitted += len(batch)
                    print(
                        f"{slug}: submitted={submitted:,} accepted={accepted:,}",
                        flush=True,
                    )
                    batch = []

            if batch:
                result = rpc(
                    "internal_ingest_site_access_snapshot_batch",
                    {"p_import_id": import_id, "p_features": batch},
                )
                accepted += int(result.get("accepted", 0))
                submitted += len(batch)

            finished = rpc(
                "internal_finish_site_access_snapshot_import",
                {
                    "p_import_id": import_id,
                    "p_attributes": {
                        "submitted_features": submitted,
                        "accepted_features_reported_by_batches": accepted,
                    },
                },
            )
            print(json.dumps(finished, indent=2), flush=True)
        except Exception as exc:
            try:
                rpc(
                    "internal_fail_site_access_snapshot_import",
                    {"p_import_id": import_id, "p_error": str(exc)[:1000]},
                )
            finally:
                raise


def main():
    require_osmium()
    config = rpc("internal_get_site_access_snapshot_loader_config")
    regions = config["regions"]
    if REGION_FILTER:
        regions = [r for r in regions if r["region_slug"] in REGION_FILTER]

    if not regions:
        raise SystemExit("No enabled Scout snapshot regions matched SCOUT_OSM_REGIONS")

    print(
        f"Scout snapshot loader contract v{config['contract_version']}; "
        f"regions={','.join(r['region_slug'] for r in regions)}; "
        f"batch={BATCH_SIZE}",
        flush=True,
    )

    for region in regions:
        upload_region(region)

    # This runs only when all enabled regions are ready. If a subset was loaded,
    # the database returns a safe snapshot_not_ready/no-op response.
    link = rpc("internal_refresh_site_access_snapshot_links")
    print("\nLink refresh:", json.dumps(link, indent=2), flush=True)
    print(
        "Opportunity target/access facts and the interactive spine will pick up "
        "the local access context on their existing hourly refresh chain.",
        flush=True,
    )


if __name__ == "__main__":
    main()
