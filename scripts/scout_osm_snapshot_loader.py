#!/usr/bin/env python3
"""One-shot Scout by Cadastory OSM access snapshot loader.

Requirements:
  - osmium-tool on PATH
  - Python requests
  - SUPABASE_URL
  - SUPABASE_SERVICE_ROLE_KEY

Optional environment:
  - SCOUT_OSM_REGIONS=kentucky,indiana,ohio
  - SCOUT_OSM_BATCH_SIZE=500
  - SCOUT_OSM_FINALIZE_BATCH_SIZE=5000
  - SCOUT_OSM_CLEANUP_BATCH_SIZE=1000
  - SCOUT_OSM_RESUME_REGION=indiana  # legacy workflow compatibility

Recovery CLI:
  --resume REGION        Resume the latest recoverable finalization for REGION.
  --finalize-only REGION Resume/finalize REGION without download or re-upload.

Uploads are independently committed in bounded batches. Finalization is also
checkpointed and bounded; an interruption resumes from the last committed
cursor instead of forcing a regional re-upload.
"""

from __future__ import annotations

import argparse
import email.utils
import json
import os
import subprocess
import sys
import tempfile
import time
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
FINALIZE_BATCH_SIZE = int(os.getenv("SCOUT_OSM_FINALIZE_BATCH_SIZE", "5000"))
CLEANUP_BATCH_SIZE = int(os.getenv("SCOUT_OSM_CLEANUP_BATCH_SIZE", "1000"))
RESUME_REGION = os.getenv("SCOUT_OSM_RESUME_REGION", "").strip().lower()
TIMEOUT = (30, 300)
MAX_RECOVERABLE_FINALIZE_RETRIES = 5

if not 1 <= BATCH_SIZE <= 1000:
    raise SystemExit("SCOUT_OSM_BATCH_SIZE must be between 1 and 1000")
if not 1 <= FINALIZE_BATCH_SIZE <= 20000:
    raise SystemExit("SCOUT_OSM_FINALIZE_BATCH_SIZE must be between 1 and 20000")
if not 1 <= CLEANUP_BATCH_SIZE <= 5000:
    raise SystemExit("SCOUT_OSM_CLEANUP_BATCH_SIZE must be between 1 and 5000")

SUPABASE_SESSION = requests.Session()
SUPABASE_SESSION.headers.update(
    {
        "apikey": SERVICE_KEY,
        "Authorization": f"Bearer {SERVICE_KEY}",
        "Content-Type": "application/json",
        "User-Agent": "Scout-Cadastory-OSM-Snapshot-Loader/2.0",
    }
)
DOWNLOAD_SESSION = requests.Session()
DOWNLOAD_SESSION.headers.update(
    {"User-Agent": "Scout-Cadastory-OSM-Snapshot-Loader/2.0"}
)


class RPCError(RuntimeError):
    def __init__(self, name: str, status_code: int, body: str):
        self.name = name
        self.status_code = status_code
        self.body = body
        self.code = None
        self.message = body[:1000]
        try:
            parsed = json.loads(body)
            if isinstance(parsed, dict):
                self.code = parsed.get("code")
                self.message = parsed.get("message") or self.message
        except (TypeError, ValueError):
            pass
        super().__init__(f"RPC {name} failed: HTTP {status_code}: {body[:1000]}")


def rpc(name: str, payload: dict | None = None):
    r = SUPABASE_SESSION.post(
        f"{SUPABASE_URL}/rest/v1/rpc/{name}",
        json=payload or {},
        timeout=TIMEOUT,
    )
    if not r.ok:
        raise RPCError(name, r.status_code, r.text)
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
            "osmium", "fileinfo", "-g",
            "header.option.osmosis_replication_timestamp", str(pbf),
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


def prepare_access_geojsonseq(source_pbf: Path, bbox: list[float], work: Path) -> Path:
    clipped = work / "pilot.osm.pbf"
    filtered = work / "access.osm.pbf"
    exported = work / "access.geojsonseq"
    bbox_arg = ",".join(str(v) for v in bbox)
    run(
        "osmium", "extract", "-b", bbox_arg, "-s", "complete_ways", "-O",
        "-o", str(clipped), str(source_pbf),
    )
    run(
        "osmium", "tags-filter", "-O", "-o", str(filtered), str(clipped),
        "nwr/highway", "nwr/amenity=parking", "nwr/barrier", "nwr/area:highway",
    )
    run(
        "osmium", "export", "-f", "geojsonseq",
        "-x", "print_record_separator=false", "-a", "type,id", "-O",
        "-o", str(exported), str(filtered),
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
            tags = {k: v for k, v in props.items() if not k.startswith("@")}
            yield {
                "osm_type": osm_type,
                "osm_id": str(osm_id),
                "geometry": geom,
                "tags": tags,
            }


def log_finalization_progress(result: dict):
    fields = [
        f"region={result.get('region_slug', '?')}",
        f"import={result.get('import_id', '?')}",
        f"phase={result.get('phase', '?')}",
    ]
    if result.get("batch_processed") is not None:
        fields.append(f"batch_processed={int(result['batch_processed']):,}")
    if result.get("total_processed") is not None:
        fields.append(f"total_processed={int(result['total_processed']):,}")
    if result.get("batch_requeued") is not None:
        fields.append(f"batch_requeued={int(result['batch_requeued']):,}")
    if result.get("total_requeued") is not None:
        fields.append(f"total_requeued={int(result['total_requeued']):,}")
    if result.get("feature_count") is not None:
        fields.append(f"canonical={int(result['feature_count']):,}")
    if result.get("already_finalizing"):
        fields.append("already_finalizing=true")
    if result.get("no_op"):
        fields.append("no_op=true")
    print("Finalization: " + " ".join(fields), flush=True)


def drive_finalization(import_id: str, attributes: dict | None = None):
    recoverable_timeouts = 0
    first = True
    while True:
        try:
            result = rpc(
                "internal_finish_site_access_snapshot_import_step",
                {
                    "p_import_id": import_id,
                    "p_batch_size": FINALIZE_BATCH_SIZE,
                    "p_attributes": (attributes or {}) if first else {},
                },
            )
            first = False
            recoverable_timeouts = 0
        except RPCError as exc:
            if exc.code == "57014":
                recoverable_timeouts += 1
                if recoverable_timeouts > MAX_RECOVERABLE_FINALIZE_RETRIES:
                    raise RuntimeError(
                        "Finalization repeatedly hit statement_timeout; import remains "
                        f"resumable at its last committed checkpoint: {import_id}"
                    ) from exc
                print(
                    "Recoverable finalization timeout; retrying the same checkpoint "
                    f"import={import_id} attempt={recoverable_timeouts}",
                    file=sys.stderr,
                    flush=True,
                )
                time.sleep(min(2 ** (recoverable_timeouts - 1), 8))
                continue
            raise
        log_finalization_progress(result)
        if result.get("complete"):
            return result
        if result.get("superseded"):
            raise RuntimeError(f"Snapshot import was superseded: {import_id}")
        if result.get("already_finalizing"):
            time.sleep(2)
            continue
        if not result.get("has_more", True):
            raise RuntimeError(
                "Finalizer returned neither completion nor a continuation: "
                + json.dumps(result, sort_keys=True)
            )


def drain_snapshot_cleanup(import_id: str):
    while True:
        result = rpc(
            "internal_process_site_access_snapshot_cleanup",
            {"p_import_id": import_id, "p_batch_size": CLEANUP_BATCH_SIZE},
        )
        print("Snapshot cleanup:", json.dumps(result, sort_keys=True), flush=True)
        if result.get("complete"):
            return result
        if result.get("skipped"):
            raise RuntimeError(
                "Snapshot cleanup did not run: "
                f"{result.get('reason', result.get('state', 'unknown reason'))}"
            )
        if not result.get("has_more"):
            raise RuntimeError("Snapshot cleanup returned neither completion nor a continuation")


def get_resumable_region(region_slug: str):
    region_slug = region_slug.strip().lower()
    try:
        return rpc(
            "internal_resume_latest_site_access_snapshot_import",
            {
                "p_region_slug": region_slug,
                "p_attributes": {
                    "loader": "osmium-tool-v2",
                    "recovery": "resumable-finalizer-step",
                },
            },
        )
    except RPCError as exc:
        if "no resumable finalizer import found" in exc.message.lower():
            return None
        raise


def resume_region(region_slug: str, recovered: dict | None = None):
    region_slug = region_slug.strip().lower()
    recovered = recovered or get_resumable_region(region_slug)
    if recovered is None:
        raise RuntimeError(f"No resumable snapshot import found for region {region_slug}")
    print("Resume state:", json.dumps(recovered, sort_keys=True), flush=True)
    import_id = recovered["import_id"]
    finished = drive_finalization(
        import_id,
        {"loader": "osmium-tool-v2", "recovery": "resumable-finalizer-step"},
    )
    cleanup = drain_snapshot_cleanup(import_id)
    finished["cleanup"] = cleanup
    requeue = rpc(
        "internal_requeue_site_access_snapshot_targets",
        {"p_region_slug": region_slug, "p_batch_size": CLEANUP_BATCH_SIZE},
    )
    print("Late requeue:", json.dumps(requeue, sort_keys=True), flush=True)
    return finished


def upload_region(region: dict):
    slug = region["region_slug"]
    print(f"\n=== {slug.upper()} ===", flush=True)

    recovered = get_resumable_region(slug)
    if recovered is not None:
        print(f"{slug}: resumable import detected; skipping download/re-upload", flush=True)
        return resume_region(slug, recovered)

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
                    "loader": "osmium-tool-v2",
                    "source": "geofabrik-regional-pbf",
                },
            },
        )
        import_id = started["import_id"]
        accepted = 0
        skipped = 0
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
                    skipped += int(result.get("skipped", 0))
                    submitted += len(batch)
                    print(
                        f"{slug}: submitted={submitted:,} accepted={accepted:,} skipped={skipped:,}",
                        flush=True,
                    )
                    batch = []
            if batch:
                result = rpc(
                    "internal_ingest_site_access_snapshot_batch",
                    {"p_import_id": import_id, "p_features": batch},
                )
                accepted += int(result.get("accepted", 0))
                skipped += int(result.get("skipped", 0))
                submitted += len(batch)
        except Exception as exc:
            try:
                rpc(
                    "internal_fail_site_access_snapshot_import",
                    {"p_import_id": import_id, "p_error": str(exc)[:1000]},
                )
            finally:
                raise

        print(
            f"{slug}: upload complete import={import_id} submitted={submitted:,} "
            f"accepted={accepted:,} skipped={skipped:,}",
            flush=True,
        )
        finished = drive_finalization(
            import_id,
            {
                "loader": "osmium-tool-v2",
                "submitted_features": submitted,
                "accepted_features_reported_by_batches": accepted,
            },
        )
        cleanup = drain_snapshot_cleanup(import_id)
        finished["cleanup"] = cleanup
        late_requeue = rpc(
            "internal_requeue_site_access_snapshot_targets",
            {"p_region_slug": slug, "p_batch_size": CLEANUP_BATCH_SIZE},
        )
        finished["late_requeue"] = late_requeue
        print("Completed import:", json.dumps(finished, indent=2), flush=True)


def parse_args(argv: list[str] | None = None):
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--resume", metavar="REGION",
        help="Resume the latest recoverable finalization for REGION.",
    )
    mode.add_argument(
        "--finalize-only", metavar="REGION",
        help="Finalize REGION without downloading or re-uploading.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None):
    args = parse_args(argv)
    cli_region = (args.resume or args.finalize_only or "").strip().lower()
    recovery_region = cli_region or RESUME_REGION

    if recovery_region:
        if REGION_FILTER:
            raise SystemExit("Recovery/finalize-only mode cannot be combined with SCOUT_OSM_REGIONS")
        print(
            "Scout snapshot finalizer recovery; "
            f"region={recovery_region}; finalize_batch={FINALIZE_BATCH_SIZE}; "
            f"cleanup_batch={CLEANUP_BATCH_SIZE}",
            flush=True,
        )
        finished = resume_region(recovery_region)
        print("Recovered import:", json.dumps(finished, indent=2), flush=True)
        link = rpc("internal_refresh_site_access_snapshot_links")
        print("Link refresh:", json.dumps(link, indent=2), flush=True)
        return

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
        f"upload_batch={BATCH_SIZE}; finalize_batch={FINALIZE_BATCH_SIZE}",
        flush=True,
    )
    for region in regions:
        upload_region(region)

    link = rpc("internal_refresh_site_access_snapshot_links")
    print("\nLink refresh:", json.dumps(link, indent=2), flush=True)
    print(
        "Opportunity target/access facts and the interactive spine will pick up "
        "the local access context on their existing hourly refresh chain.",
        flush=True,
    )


if __name__ == "__main__":
    main()
